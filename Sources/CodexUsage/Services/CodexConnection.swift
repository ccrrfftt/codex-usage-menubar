import Foundation
import Darwin

protocol QuotaReading: Sendable {
    func read() async throws -> QuotaSnapshot
}

protocol DashboardReading: QuotaReading {
    func readDashboard(allowedWorkingDirectories: [String]) async throws -> DashboardSnapshot
    func readDashboard(allowedWorkingDirectories: [String], trackingStart: Date?) async throws -> DashboardSnapshot
}

extension DashboardReading {
    func readDashboard(allowedWorkingDirectories: [String], trackingStart: Date?) async throws -> DashboardSnapshot {
        try await readDashboard(allowedWorkingDirectories: allowedWorkingDirectories)
    }
}

/// Serial utility work; each read owns and closes its process before returning.
final class CodexConnection: DashboardReading, @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.codexusage.connection", qos: .utility, autoreleaseFrequency: .workItem)
    private let executable: URL?
    private let runtime: URL
    private let timeout: TimeInterval
    private let accountingReader: UsageAccountingReader
    private let threadIndex: any ThreadIndexReading
    private let allowExactScopeFallback: Bool

    init(executable: URL? = nil, runtime: URL? = nil, timeout: TimeInterval = 25,
         accountingReader: UsageAccountingReader = UsageAccountingReader(),
         threadIndex: any ThreadIndexReading = ScopedThreadIndex(), allowExactScopeFallback: Bool = false) {
        self.executable = executable
        self.accountingReader = accountingReader
        self.threadIndex = threadIndex
        self.allowExactScopeFallback = allowExactScopeFallback
        self.runtime = runtime ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.codexusage.menubar/runtime", isDirectory: true)
        self.timeout = timeout
    }

    func read() async throws -> QuotaSnapshot {
        try Task.checkCancellation()
        let cancellation = QueryCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let result = Result {
                        try cancellation.check()
                        let session = try QuerySession(executable: self.executable ?? Self.findExecutable(),
                                                       runtime: self.runtime, timeout: self.timeout,
                                                       cancellation: cancellation)
                        return try session.read()
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func readDashboard(allowedWorkingDirectories: [String]) async throws -> DashboardSnapshot {
        try await readDashboard(allowedWorkingDirectories: allowedWorkingDirectories, trackingStart: nil)
    }

    func readDashboard(allowedWorkingDirectories: [String], trackingStart: Date?) async throws -> DashboardSnapshot {
        try Task.checkCancellation()
        let cancellation = QueryCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let result = Result {
                        try cancellation.check()
                        let session = try QuerySession(executable: self.executable ?? Self.findExecutable(),
                            runtime: self.runtime, timeout: self.timeout, cancellation: cancellation,
                            scopedAccounting: self.allowExactScopeFallback && !allowedWorkingDirectories.isEmpty)
                        return try session.readDashboard(allowedWorkingDirectories: allowedWorkingDirectories,
                                                         reader: self.accountingReader, threadIndex: self.threadIndex,
                                                         allowExactScopeFallback: self.allowExactScopeFallback, trackingStart: trackingStart)
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    static func findExecutable(
        applicationDirectories: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ],
        standalonePaths: [String] = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
    ) throws -> URL {
        // Prefer the packaged launcher; retain the native payload and older layout
        // as fallbacks. Resolve on each query so a desktop update needs no restart.
        let relativePaths = [
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex"
        ]
        let candidates = applicationDirectories.flatMap { directory in
            ["ChatGPT.app", "Codex.app"].flatMap { app in
                relativePaths.map { directory.appendingPathComponent(app).appendingPathComponent($0).path }
            }
        } + standalonePaths
        let files = FileManager.default
        guard let path = candidates.first(where: { path in
            var isDirectory: ObjCBool = false
            return files.fileExists(atPath: path, isDirectory: &isDirectory) &&
                !isDirectory.boolValue && files.isExecutableFile(atPath: path)
        }) else { throw QuotaError.unavailable }
        return URL(fileURLWithPath: path)
    }
}

/// A single-byte pipe wakes a blocked poll immediately without a polling timer.
private final class QueryCancellation: @unchecked Sendable {
    let signal = Pipe()
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.withLock {
            guard !cancelled else { return }
            cancelled = true
            try? signal.fileHandleForWriting.write(contentsOf: Data([1]))
        }
    }

    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}

private final class QuerySession {
    private let process = Process()
    private let exited = DispatchSemaphore(value: 0)
    private let input = Pipe()
    private let output = Pipe()
    private let cancellation: QueryCancellation
    private let deadline: TimeInterval
    private let decoder = JSONDecoder()
    private var buffer = Data()
    private var serial = 0

    init(executable: URL, runtime: URL, timeout: TimeInterval, cancellation: QueryCancellation, scopedAccounting: Bool = false) throws {
        self.cancellation = cancellation
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let quoted = String(decoding: try encoder.encode(runtime.path), as: UTF8.self)
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://",
                             "-c", "log_dir=" + quoted, "-c", "analytics.enabled=false"]
        if !scopedAccounting { process.arguments! += ["-c", "sqlite_home=" + quoted] }
        process.currentDirectoryURL = runtime
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = self.exited
        process.terminationHandler = { _ in exited.signal() }
    }

    func read() throws -> QuotaSnapshot {
        defer { close() }
        do {
            try initialize()
            return try call("account/rateLimits/read")
        } catch {
            try cancellation.check()
            throw error is QuotaError ? error : (error is DecodingError ? QuotaError.malformed : QuotaError.disconnected)
        }
    }

    private func initialize() throws {
            try cancellation.check()
            try process.run()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            let _: EmptyResult = try call("initialize", params: ["clientInfo": [
                "name": "codex_usage_menubar", "title": "Codex Usage Menu Bar", "version": version
            ]])
            try send(["method": "initialized"])
    }

    func readDashboard(allowedWorkingDirectories: [String], reader: UsageAccountingReader,
                       threadIndex: any ThreadIndexReading, allowExactScopeFallback: Bool, trackingStart: Date?) throws -> DashboardSnapshot {
        defer { close() }
        try initialize()
        let quota: QuotaSnapshot = try call("account/rateLimits/read")
        var issues = Set<AccountingIssue>()
        let account: AccountTokenActivity?
        if trackingStart == nil {
            do { account = try call("account/usage/read") }
            catch { try cancellation.check(); account = nil; issues.insert(.accountUsageUnavailable) }
        } else { account = nil }
        let scopes = AccountingPathScope.roots(allowedWorkingDirectories)
        var descriptors: [AccountingThreadDescriptor] = []
        let queryDeadline = deadline
        let queryCancellation = cancellation
        let mayContinue: @Sendable () -> Bool = {
            (try? queryCancellation.check()) != nil && ProcessInfo.processInfo.systemUptime < queryDeadline
        }
        if scopes.isEmpty { issues.insert(.scopeRequired) }
        else {
            var indexUnavailable = false
            do {
                let index = try threadIndex.read(allowedRoots: scopes, limit: 1000, trackingStart: trackingStart, shouldContinue: mayContinue)
                descriptors = index.threads.filter { AccountingPathScope.contains($0.cwd, roots: scopes) }
                issues.formUnion(index.issues)
                if descriptors.count != index.threads.count { issues.insert(.invalidRecord) }
                if !index.isComplete { issues.insert(.recursiveCoverageUnavailable) }
            } catch ThreadIndexError.interrupted {
                try cancellation.check(); issues.insert(.historyCatchingUp)
            } catch ThreadIndexError.unsupportedSchema {
                issues.insert(.threadIndexUnsupported); indexUnavailable = true
            } catch {
                try cancellation.check(); issues.insert(.threadIndexUnavailable); indexUnavailable = true
            }
            if indexUnavailable {
                issues.insert(.recursiveCoverageUnavailable)
                if allowExactScopeFallback && mayContinue() {
                    do {
                        for archived in [false, true] {
                            if descriptors.count >= 1000 { issues.insert(.threadLimitReached); break }
                            var cursor: String?
                            var seenCursors = Set<String>()
                            repeat {
                                var params: [String: Any] = ["cwd": scopes, "limit": 100, "sortKey": "updated_at",
                                    "sortDirection": "desc", "archived": archived, "useStateDbOnly": true, "modelProviders": ["openai"],
                                    "sourceKinds": ["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther"]]
                                if let cursor { params["cursor"] = cursor }
                                let page: AccountingThreadPage = try call("thread/list", params: params)
                                // Recheck server filtering before any path can reach the reader.
                                descriptors += page.data.filter { scopes.contains(AccountingPathScope.normalized($0.cwd) ?? "") }.map {
                                    AccountingThreadDescriptor(id: $0.id, name: nil, cwd: $0.cwd, path: $0.path,
                                        createdAt: $0.createdAt, updatedAt: $0.updatedAt, recencyAt: $0.recencyAt,
                                        forkedFromId: $0.forkedFromId, parentThreadId: $0.parentThreadId)
                                }
                                cursor = page.nextCursor
                                if let cursor, !seenCursors.insert(cursor).inserted { issues.insert(.threadListUnavailable); break }
                                if descriptors.count >= 1000 { issues.insert(.threadLimitReached); break }
                            } while cursor != nil
                        }
                    } catch { try cancellation.check(); issues.insert(.threadListUnavailable) }
                }
            }
        }
        var unique: [String: AccountingThreadDescriptor] = [:]
        for descriptor in descriptors { unique[descriptor.id] = descriptor }
        descriptors = Array(unique.values).filter { thread in
            trackingStart.map { max(thread.createdAt, thread.updatedAt) >= $0.timeIntervalSince1970 } ?? true
        }
        let local = reader.read(threads: descriptors, allowedWorkingDirectories: scopes, accountID: quota.accountId, trackingStart: trackingStart,
            shouldContinue: { (try? self.cancellation.check()) != nil && ProcessInfo.processInfo.systemUptime < self.deadline })
        try cancellation.check()
        issues.formUnion(local.issues)
        var recent: [AccountingThread] = []
        let latestTrackedResponse = Dictionary(grouping: local.records, by: \.threadID)
            .compactMapValues { $0.map(\.timestamp).max() }
        let recentDescriptors = descriptors.filter {
            $0.parentThreadId == nil && (trackingStart == nil || latestTrackedResponse[$0.id] != nil)
        }.sorted {
            let lhs = trackingStart == nil ? ($0.recencyAt ?? $0.updatedAt) : latestTrackedResponse[$0.id]!.timeIntervalSince1970
            let rhs = trackingStart == nil ? ($1.recencyAt ?? $1.updatedAt) : latestTrackedResponse[$1.id]!.timeIntervalSince1970
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
        for thread in recentDescriptors.prefix(3) {
            var usage: AccountingThreadUsage?
            if trackingStart == nil {
                do {
                    let result: AccountTokenActivity = try call("account/usage/read", params: ["threadId": thread.id])
                    if result.threadUsage?.threadId == thread.id { usage = result.threadUsage }
                    if usage == nil { issues.insert(.conversationUsageUnavailable) }
                } catch { try cancellation.check(); issues.insert(.conversationUsageUnavailable) }
            }
            recent.append(AccountingThread(id: thread.id, name: thread.name,
                updatedAt: Date(timeIntervalSince1970: thread.updatedAt),
                recencyAt: trackingStart == nil ? Date(timeIntervalSince1970: thread.recencyAt ?? thread.updatedAt) : latestTrackedResponse[thread.id]!, usage: usage))
        }
        // A service-reported nonempty conversation cannot become a complete local zero
        // if a newer/unsupported rollout shape contains no recognized usage records.
        if recent.contains(where: { thread in
            let hasUsage = thread.usage?.groups.contains { ($0.totalTokens ?? 0) > 0 || ($0.inputTokens ?? 0) > 0 || ($0.outputTokens ?? 0) > 0 } == true
            return hasUsage && !local.records.contains { $0.threadID == thread.id }
        }) { issues.insert(.unsupportedHistory) }
        let incomplete: Set<AccountingIssue> = [.scopeRequired, .threadListUnavailable, .threadLimitReached,
            .rolloutUnavailable, .unsupportedHistory, .invalidRecord, .historyCatchingUp,
            .threadIndexUnavailable, .threadIndexUnsupported, .recursiveCoverageUnavailable]
        return DashboardSnapshot(quota: quota, accounting: AccountingSnapshot(observedAt: .now, account: account,
            recentThreads: recent, records: local.records, issues: issues, scannedThreadCount: local.scanned,
            recordsAreComplete: issues.isDisjoint(with: incomplete), quotaObservations: local.quotaObservations))
    }

    private struct EmptyResult: Decodable {}
    private static let responseIDKey = CodingUserInfoKey(rawValue: "responseID")!
    private struct Response<Value: Decodable>: Decodable {
        let matches: Bool
        let result: Value?

        private enum CodingKeys: String, CodingKey { case id, result, error }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let id = try? values.decode(Int.self, forKey: .id)
            matches = id != nil && id == decoder.userInfo[QuerySession.responseIDKey] as? Int
            guard matches else { result = nil; return }
            if values.contains(.error), try !values.decodeNil(forKey: .error) { throw QuotaError.account }
            result = try values.decodeIfPresent(Value.self, forKey: .result)
        }
    }

    private func send(_ object: [String: Any]) throws {
        try cancellation.check()
        guard process.isRunning else { throw QuotaError.disconnected }
        var bytes = try JSONSerialization.data(withJSONObject: object)
        bytes.append(10)
        try input.fileHandleForWriting.write(contentsOf: bytes)
    }

    private func call<Value: Decodable>(_ method: String, params: [String: Any]? = nil) throws -> Value {
        serial += 1
        var request: [String: Any] = ["method": method, "id": serial]
        if let params { request["params"] = params }
        try send(request)
        decoder.userInfo[Self.responseIDKey] = serial
        while true {
            // Decode directly into the result model, avoiding a JSON dictionary round trip.
            let response = try decoder.decode(Response<Value>.self, from: readLine())
            guard response.matches else { continue }
            guard let result = response.result else { throw QuotaError.malformed }
            return result
        }
    }

    private func readLine() throws -> Data {
        while true {
            try cancellation.check()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw QuotaError.timedOut }
            if let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                return line
            }
            var descriptors = [
                pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: cancellation.signal.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            ]
            let ready = Darwin.poll(&descriptors, 2, Int32(max(1, remaining * 1000)))
            try cancellation.check()
            if ready < 0 {
                if errno == EINTR { continue }
                throw QuotaError.disconnected
            }
            if ready == 0 { continue }
            let bytes = output.fileHandleForReading.availableData
            guard !bytes.isEmpty else { throw QuotaError.disconnected }
            buffer.append(bytes)
            guard buffer.count <= 4_000_000 else { throw QuotaError.malformed }
        }
    }

    private func close() {
        try? input.fileHandleForWriting.close()
        defer { try? output.fileHandleForReading.close() }
        guard process.isRunning else { return }
        // Prefer normal EOF shutdown, then bound cleanup of a stalled owned child.
        if exited.wait(timeout: .now() + .milliseconds(100)) == .success { return }
        if process.isRunning { process.terminate() }
        if exited.wait(timeout: .now() + .milliseconds(250)) == .success { return }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        _ = exited.wait(timeout: .now() + .milliseconds(250))
    }
}
