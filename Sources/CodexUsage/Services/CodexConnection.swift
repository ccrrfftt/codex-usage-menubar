import Foundation
import Darwin

protocol QuotaReading: Sendable {
    func read() async throws -> QuotaSnapshot
}

/// Serial utility work; each read owns and closes its process before returning.
final class CodexConnection: QuotaReading, @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.codexusage.connection", qos: .utility, autoreleaseFrequency: .workItem)
    private let executable: URL?
    private let runtime: URL
    private let timeout: TimeInterval

    init(executable: URL? = nil, runtime: URL? = nil, timeout: TimeInterval = 25) {
        self.executable = executable
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

    private static func findExecutable() throws -> URL {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw QuotaError.unavailable
        }
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

    init(executable: URL, runtime: URL, timeout: TimeInterval, cancellation: QueryCancellation) throws {
        self.cancellation = cancellation
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let quoted = String(decoding: try encoder.encode(runtime.path), as: UTF8.self)
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "sqlite_home=" + quoted,
                             "-c", "log_dir=" + quoted, "-c", "analytics.enabled=false"]
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
            try cancellation.check()
            try process.run()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            let _: EmptyResult = try call("initialize", params: ["clientInfo": [
                "name": "codex_usage_menubar", "title": "Codex Usage Menu Bar", "version": version
            ]])
            try send(["method": "initialized"])
            return try call("account/rateLimits/read")
        } catch {
            try cancellation.check()
            throw error is QuotaError ? error : (error is DecodingError ? QuotaError.malformed : QuotaError.disconnected)
        }
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
