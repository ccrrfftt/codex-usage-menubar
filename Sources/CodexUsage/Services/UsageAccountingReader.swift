import Foundation
import CryptoKit

/// Incremental, in-memory counter cache. Only caller-selected, server-filtered
/// rollout paths are opened. No session directory enumeration or raw persistence.
final class UsageAccountingReader: @unchecked Sendable {
    private var files: [String: AccountingFileState] = [:]
    private var accountIdentity: String?
    private var cachedTrackingStart: Date?
    private let allowedSessionRoots: [URL]

    init(allowedSessionRoots: [URL]? = nil) {
        self.allowedSessionRoots = allowedSessionRoots ?? CodexStateLocation().sessionRoots
    }

    func read(threads: [AccountingThreadDescriptor], allowedWorkingDirectories: [String], accountID: String?, trackingStart: Date? = nil, shouldContinue: () -> Bool = { true }) -> (records: [AccountingUsageRecord], issues: Set<AccountingIssue>, scanned: Int, quotaObservations: [RecordedQuotaObservation]) {
        if accountIdentity != accountID || cachedTrackingStart != trackingStart {
            files.removeAll(); accountIdentity = accountID; cachedTrackingStart = trackingStart
        }
        if let trackingStart, !trackingStart.timeIntervalSince1970.isFinite {
            files.removeAll(); return ([], [.invalidRecord], 0, [])
        }
        let scopes = AccountingPathScope.roots(allowedWorkingDirectories)
        guard !scopes.isEmpty else { files.removeAll(); return ([], [.scopeRequired], 0, []) }
        let eligibleThreads = threads.filter { thread in
            trackingStart.map { max(thread.createdAt, thread.updatedAt) >= $0.timeIntervalSince1970 } ?? true
        }
        var issues = Set<AccountingIssue>(), active = Set<String>(), scanned = 0
        var byteBudget = 32 * 1024 * 1024
        for thread in eligibleThreads.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard shouldContinue() else { issues.insert(.historyCatchingUp); break }
            guard AccountingPathScope.contains(thread.cwd, roots: scopes),
                  let path = thread.path, let url = validatedURL(path) else {
                files.removeValue(forKey: thread.id)
                issues.insert(.rolloutUnavailable); continue
            }
            active.insert(thread.id)
            let state = files[thread.id] ?? AccountingFileState(trackingStart: trackingStart)
            do {
                let update = try state.update(url: url, descriptor: thread, byteBudget: min(byteBudget, 4 * 1024 * 1024), shouldContinue: shouldContinue)
                byteBudget -= update.bytesRead
                if !update.complete { issues.insert(.historyCatchingUp) }
                files[thread.id] = state; scanned += 1
                issues.formUnion(state.parser.issues)
            } catch { issues.insert(.rolloutUnavailable) }
        }
        let authorizedIDs = Set(eligibleThreads.filter { AccountingPathScope.contains($0.cwd, roots: scopes) }.map(\.id))
        files = files.filter { authorizedIDs.contains($0.key) }
        // Response IDs are global across copied fork histories. Exact records
        // supersede legacy estimates for the same thread/turn.
        let all = files.values.flatMap { $0.parser.records }
        var unique: [String: AccountingUsageRecord] = [:]
        for record in all {
            if unique[record.id]?.quality == .reported { continue }
            unique[record.id] = record
        }
        let records = unique.values.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
        if records.contains(where: { $0.quality == .estimated }) { issues.insert(.estimatedUsage) }
        if records.contains(where: { $0.model == nil }) { issues.insert(.missingModel) }
        if records.contains(where: { $0.cachedInputTokens == nil || $0.cacheWriteInputTokens == nil }) { issues.insert(.missingCacheCounts) }
        var quotaByKey: [RecordedQuotaObservationKey: RecordedQuotaObservation] = [:]
        for observation in files.values.flatMap({ $0.parser.quotaObservations }) {
            quotaByKey[RecordedQuotaObservationKey(observation)] = observation
        }
        let observations = quotaByKey.values.sorted { $0.timestamp < $1.timestamp }
        return (records, issues, scanned, observations)
    }

    private func validatedURL(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension == "jsonl", url.resolvingSymlinksInPath().path == url.path,
              allowedSessionRoots.contains(where: { root in
                  let standardized = root.standardizedFileURL
                  return standardized.resolvingSymlinksInPath().path == standardized.path && url.path.hasPrefix(standardized.path + "/")
              }) else { return nil }
        return url
    }
}

private final class AccountingFileState {
    var parser: AccountingRolloutParser
    private let trackingStart: Date?
    init(trackingStart: Date?) {
        self.trackingStart = trackingStart
        parser = AccountingRolloutParser(trackingStart: trackingStart)
    }
    private var offset: UInt64 = 0
    private var tail = Data()
    private var inode: UInt64?
    private var path: String?
    private var discardingLongLine = false
    private var modificationDate: Date?

    func update(url: URL, descriptor: AccountingThreadDescriptor, byteBudget: Int, shouldContinue: () -> Bool) throws -> (bytesRead: Int, complete: Bool) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let currentInode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let modified = attributes[.modificationDate] as? Date
        if path != url.path || inode != currentInode || size < offset || (size == offset && modificationDate != modified) {
            parser = AccountingRolloutParser(trackingStart: trackingStart); offset = 0; tail.removeAll(); discardingLongLine = false
        }
        path = url.path; inode = currentInode; modificationDate = modified
        if offset == size && tail.isEmpty && !discardingLongLine { return (0, true) }
        if byteBudget == 0 && tail.isEmpty { return (0, false) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var bytesRead = 0
        while shouldContinue() {
            while let newline = tail.firstIndex(of: 10) {
                guard shouldContinue() else { return (bytesRead, false) }
                let line = Data(tail[..<newline]); tail.removeSubrange(...newline)
                if !discardingLongLine { parser.consume(line, descriptor: descriptor) }
                discardingLongLine = false
            }
            if tail.count > 8_000_000 {
                tail.removeAll(keepingCapacity: true); discardingLongLine = true
                parser.issues.insert(.unsupportedHistory)
            }
            guard bytesRead < byteBudget, offset < size else { break }
            guard let chunk = try handle.read(upToCount: min(65_536, byteBudget - bytesRead)), !chunk.isEmpty else { break }
            offset += UInt64(chunk.count); bytesRead += chunk.count; tail.append(chunk)
        }
        return (bytesRead, offset >= size && tail.isEmpty && !discardingLongLine)
    }

}

/// A typed projection reads only accounting fields. The caller owns privacy
/// filtering before supplying bytes; unrelated item bodies are never decoded.
struct AccountingRolloutParser {
    private let trackingStart: Date?
    init(trackingStart: Date? = nil) { self.trackingStart = trackingStart }
    private var forkedHistory = false
    private var model: String?
    private var tier: String?
    private var turnID: String?
    private var previousTotal: RolloutTokens?
    private var exactTurns = Set<String>()
    private var estimatedIDsByTurn: [String: Set<String>] = [:]
    private var entries: [String: (turn: String, record: AccountingUsageRecord)] = [:]
    var records: [AccountingUsageRecord] { entries.values.map(\.record) }
    private var quotaByKey: [RecordedQuotaObservationKey: RecordedQuotaObservation] = [:]
    var quotaObservations: [RecordedQuotaObservation] { Array(quotaByKey.values) }
    var issues = Set<AccountingIssue>()

    mutating func consume(_ data: Data, descriptor: AccountingThreadDescriptor) {
        let line: RolloutAccountingLine
        do { line = try JSONDecoder().decode(RolloutAccountingLine.self, from: data) }
        catch {
            // A malformed historical usage payload is not a permanent gap in
            // prospective tracking. Drop its unusable baseline, so the next
            // request must use its own last-request count rather than a lifetime delta.
            if let trackingStart,
               let envelope = try? JSONDecoder().decode(RolloutAccountingEnvelope.self, from: data),
               let timestamp = Self.date(envelope.timestamp), timestamp < trackingStart {
                previousTotal = nil
                if envelope.type == "turn_context" { model = nil; tier = nil; turnID = nil }
                return
            }
            issues.insert(.invalidRecord); return
        }
        if line.type == "session_meta" {
            forkedHistory = forkedHistory || line.hasForkParent
            return
        }
        if line.type == "turn_context" {
            model = line.model; tier = line.serviceTier; turnID = line.turnID
            return
        }
        guard line.isUsage else { return }
        guard let timestamp = Self.date(line.timestamp) else {
            if line.isUsage { issues.insert(.invalidRecord) }; return
        }
        let beforeTracking = trackingStart.map { timestamp < $0 } ?? false
        let inherited = (forkedHistory || descriptor.forkedFromId != nil) && timestamp.timeIntervalSince1970 < descriptor.createdAt
        // Quota headers remain useful when token_count.info is null, and are
        // independent of whether a usable request token delta exists.
        if !beforeTracking, !inherited, let observation = line.quota?.observation(at: timestamp) {
            quotaByKey[RecordedQuotaObservationKey(observation)] = observation
        }
        if line.type == "token_usage_record" || line.eventType == "raw_response_completed" {
            // Historical exact records are not today's requests and must not
            // suppress post-midnight legacy updates in a still-running turn.
            if beforeTracking {
                // An exact response can advance a previous legacy cumulative
                // baseline; discard that baseline until a newer counter confirms it.
                previousTotal = nil
                return
            }
            guard !inherited, line.threadID == nil || line.threadID == descriptor.id,
                  let response = line.responseID, !response.isEmpty,
                  let usage = line.usage, usage.valid else { if !inherited { issues.insert(.invalidRecord) }; return }
            let turn = line.turnID ?? turnID ?? ""
            exactTurns.insert(turn)
            for id in estimatedIDsByTurn.removeValue(forKey: turn) ?? [] { entries.removeValue(forKey: id) }
            let record = usage.record(id: "response:" + response, thread: descriptor.id, at: timestamp,
                                      model: line.model ?? model, tier: line.serviceTier ?? tier, quality: .reported)
            entries[record.id] = (turn, record)
            return
        }
        guard line.eventType == "token_count", let current = line.total else { return }
        if beforeTracking {
            // Keep the baseline needed by a resumed conversation, without adding
            // its lifetime total or preserving obsolete synthetic context fills.
            previousTotal = current.valid ? current : nil
            return
        }
        guard current.valid else { issues.insert(.invalidRecord); return }
        defer { previousTotal = current }
        guard !inherited, !exactTurns.contains(turnID ?? "") else { return }
        let delta: RolloutTokens
        if let previousTotal {
            guard let difference = current.subtracting(previousTotal) else { issues.insert(.invalidRecord); return }
            delta = difference
        } else {
            // No prior baseline: only the reported last request can be used.
            // A cumulative value may include replayed or inherited history.
            guard let last = line.last, last.valid else { issues.insert(.invalidRecord); return }
            delta = last
        }
        guard delta.total > 0 else { return }
        // Synthetic context-fill events carry total without matching input/output.
        guard delta.input <= Int64.max - delta.output, delta.total == delta.input + delta.output else { issues.insert(.invalidRecord); return }
        let fingerprint = "\(turnID ?? descriptor.id)|\(line.timestamp ?? "")|\(current.fingerprint)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        let record = delta.record(id: "estimate:" + digest, thread: descriptor.id, at: timestamp, model: model, tier: tier, quality: .estimated)
        entries[record.id] = (turnID ?? "", record)
        estimatedIDsByTurn[turnID ?? "", default: []].insert(record.id)
    }

    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct RecordedQuotaObservationKey: Hashable {
    let timestamp: Date
    let usedPercent: Double?
    let durationMinutes: Double?
    let resetsAt: Double?
    init(_ observation: RecordedQuotaObservation) {
        timestamp = observation.timestamp
        usedPercent = observation.window.usedPercent
        durationMinutes = observation.window.windowDurationMins
        resetsAt = observation.window.resetsAt
    }
}

private struct RolloutTokens: Decodable {
    let input: Int64, output: Int64, total: Int64
    let cached: Int64?, cacheWrite: Int64?, reasoning: Int64?
    enum CodingKeys: String, CodingKey {
        case input = "input_tokens", output = "output_tokens", total = "total_tokens"
        case cached = "cached_input_tokens", cacheWrite = "cache_write_input_tokens", reasoning = "reasoning_output_tokens"
    }
    var valid: Bool {
        input >= 0 && output >= 0 && total >= 0 && input <= Int64.max - output && total == input + output &&
        (cached.map { $0 >= 0 && $0 <= input } ?? true) && (cacheWrite.map { $0 >= 0 && $0 <= input } ?? true) &&
        (reasoning.map { $0 >= 0 && $0 <= output } ?? true)
    }
    var fingerprint: String { "\(input),\(cached.map(String.init) ?? "?"),\(output),\(total)" }
    func subtracting(_ old: Self) -> Self? {
        guard input >= old.input, output >= old.output, total >= old.total else { return nil }
        func difference(_ a: Int64?, _ b: Int64?) -> Int64? { guard let a, let b, a >= b else { return nil }; return a - b }
        return Self(input: input - old.input, output: output - old.output, total: total - old.total,
                    cached: difference(cached, old.cached), cacheWrite: difference(cacheWrite, old.cacheWrite), reasoning: difference(reasoning, old.reasoning))
    }
    func record(id: String, thread: String, at: Date, model: String?, tier: String?, quality: AccountingRecordQuality) -> AccountingUsageRecord {
        AccountingUsageRecord(id: id, threadID: thread, timestamp: at, model: model, serviceTier: tier,
            inputTokens: input, cachedInputTokens: cached, cacheWriteInputTokens: cacheWrite,
            outputTokens: output, reasoningOutputTokens: reasoning, totalTokens: total, quality: quality)
    }
}

private struct RolloutAccountingEnvelope: Decodable {
    let type: String
    let timestamp: String?
}

private struct RolloutAccountingLine: Decodable {
    let type: String, timestamp: String?
    var hasForkParent = false
    var eventType: String?, model: String?, serviceTier: String?, turnID: String?, threadID: String?, responseID: String?
    var usage: RolloutTokens?, total: RolloutTokens?, last: RolloutTokens?
    var quota: RecordedQuotaSnapshotPayload?
    var isUsage: Bool { type == "token_usage_record" || eventType == "token_count" || eventType == "raw_response_completed" }
    enum Keys: String, CodingKey {
        case type, timestamp, payload, model, info, usage
        case forkedFromID = "forked_from_id", rateLimits = "rate_limits"
        case serviceTier = "service_tier", turnID = "turn_id", threadID = "thread_id", responseID = "response_id"
        case tokenUsage = "token_usage", total = "total_token_usage", last = "last_token_usage"
    }
    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Keys.self)
        type = try outer.decode(String.self, forKey: .type)
        timestamp = try outer.decodeIfPresent(String.self, forKey: .timestamp)
        guard ["session_meta", "turn_context", "token_usage_record", "event_msg"].contains(type) else { return }
        let payload = try outer.nestedContainer(keyedBy: Keys.self, forKey: .payload)
        if type == "session_meta" {
            hasForkParent = try payload.contains(.forkedFromID) && !payload.decodeNil(forKey: .forkedFromID)
            return
        }
        if type == "event_msg" {
            eventType = try payload.decodeIfPresent(String.self, forKey: .type)
            guard ["token_count", "raw_response_completed"].contains(eventType) else { return }
        }
        if eventType == "token_count" {
            // A malformed optional quota header must not discard valid usage.
            quota = try? payload.decodeIfPresent(RecordedQuotaSnapshotPayload.self, forKey: .rateLimits)
        }
        model = try payload.decodeIfPresent(String.self, forKey: .model)
        serviceTier = try payload.decodeIfPresent(String.self, forKey: .serviceTier)
        turnID = try payload.decodeIfPresent(String.self, forKey: .turnID)
        threadID = try payload.decodeIfPresent(String.self, forKey: .threadID)
        responseID = try payload.decodeIfPresent(String.self, forKey: .responseID)
        usage = try payload.decodeIfPresent(RolloutTokens.self, forKey: type == "token_usage_record" ? .usage : .tokenUsage)
        if eventType == "token_count", payload.contains(.info), try !payload.decodeNil(forKey: .info) {
            let info = try payload.nestedContainer(keyedBy: Keys.self, forKey: .info)
            total = try info.decodeIfPresent(RolloutTokens.self, forKey: .total)
            last = try info.decodeIfPresent(RolloutTokens.self, forKey: .last)
        }
    }
}
