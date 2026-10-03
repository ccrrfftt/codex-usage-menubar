import Foundation

@main @MainActor
struct AccountingChecks {
    static var checked = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), "FAILED: " + label); checked += 1; print("PASS: " + label)
    }
    static func descriptor(id: String = "fixture-thread", path: String? = nil, fork: String? = nil, created: Double = 0) -> AccountingThreadDescriptor {
        AccountingThreadDescriptor(id: id, name: "Fixture", cwd: "/fixture/project", path: path,
            createdAt: created, updatedAt: 100, recencyAt: 100, forkedFromId: fork, parentThreadId: nil)
    }
    static func line(_ type: String, _ payload: [String: Any], at: String = "2026-10-02T12:00:00Z") -> Data {
        try! JSONSerialization.data(withJSONObject: ["timestamp": at, "type": type, "payload": payload])
    }
    static func tokens(_ input: Int64, _ output: Int64, cached: Int64? = 20, cacheWrite: Int64? = 0) -> [String: Any] {
        var result: [String: Any] = ["input_tokens": input, "output_tokens": output, "total_tokens": input + output,
                                   "reasoning_output_tokens": 2]
        if let cached { result["cached_input_tokens"] = cached }
        if let cacheWrite { result["cache_write_input_tokens"] = cacheWrite }
        return result
    }
    static func context(_ model: String = "fixture-model", turn: String = "fixture-turn") -> Data {
        line("turn_context", ["model": model, "turn_id": turn, "developer_instructions": "synthetic ignored text"])
    }
    static func request(_ id: String = "response-a", thread: String = "fixture-thread", usage: [String: Any]? = nil) -> Data {
        line("token_usage_record", ["response_id": id, "thread_id": thread, "turn_id": "fixture-turn", "usage": usage ?? tokens(100, 10)])
    }
    static func legacy(_ total: [String: Any], last: [String: Any]? = nil, at: String = "2026-10-02T12:00:00Z") -> Data {
        line("event_msg", ["type": "token_count", "info": ["total_token_usage": total, "last_token_usage": last ?? total]], at: at)
    }
    static func main() throws {
        let d = descriptor()
        var parser = AccountingRolloutParser()
        parser.consume(context(), descriptor: d)
        parser.consume(request(), descriptor: d); parser.consume(request(), descriptor: d)
        check(parser.records.count == 1, "response ID replay deduplicates")
        check(parser.records.first?.totalTokens == 110 && parser.records.first?.quality == .reported, "per-response usage preserves total and quality")
        check(parser.records.first?.model == "fixture-model", "request uses its turn context model")
        parser.consume(line("response_item", ["text": "synthetic ignored message"]), descriptor: d)
        check(parser.records.count == 1, "message bodies do not create accounting records")

        var missing = AccountingRolloutParser()
        missing.consume(request(usage: tokens(100, 10, cached: nil, cacheWrite: nil)), descriptor: d)
        check(missing.records.first?.cachedInputTokens == nil && missing.records.first?.cacheWriteInputTokens == nil, "missing cache counters stay unknown")
        check(missing.records.first?.model == nil, "missing request model remains unknown")
        var bad = tokens(100, 10); bad["cached_input_tokens"] = 101
        missing.consume(request("invalid", usage: bad), descriptor: d)
        check(missing.records.count == 1 && missing.issues.contains(.invalidRecord), "invalid cache subsets are rejected")

        var old = AccountingRolloutParser()
        old.consume(context(), descriptor: d)
        old.consume(legacy(tokens(100, 10)), descriptor: d)
        old.consume(legacy(tokens(100, 10)), descriptor: d)
        old.consume(legacy(tokens(200, 20), last: tokens(100, 10), at: "2026-10-02T12:00:01Z"), descriptor: d)
        check(old.records.count == 2 && old.records.reduce(0) { $0 + $1.totalTokens } == 220, "legacy cumulative updates add only differences")
        check(old.records.allSatisfy { $0.quality == .estimated }, "legacy counters never claim exact billing")
        old.consume(request(), descriptor: d)
        check(old.records.count == 1 && old.records.first?.quality == .reported, "exact records replace estimates in the same turn")
        old.consume(legacy(tokens(300, 30)), descriptor: d)
        check(old.records.count == 1, "late legacy update cannot double-count an exact turn")

        var reset = AccountingRolloutParser()
        reset.consume(legacy(tokens(100, 10)), descriptor: d)
        reset.consume(legacy(tokens(50, 5)), descriptor: d)
        check(reset.issues.contains(.invalidRecord) && reset.records.count == 1, "counter rollback is a coverage gap, never negative spend")
        reset.consume(legacy(["input_tokens": 0, "output_tokens": 0, "total_tokens": 100000]), descriptor: d)
        check(reset.records.count == 1, "context window fill is not billable usage")

        let created = ISO8601DateFormatter().date(from: "2026-10-02T13:00:00Z")!.timeIntervalSince1970
        var fork = AccountingRolloutParser()
        fork.consume(context(), descriptor: descriptor(fork: "parent", created: created))
        fork.consume(request(), descriptor: descriptor(fork: "parent", created: created))
        check(fork.records.isEmpty, "fork inherited responses before creation are excluded")

        var indexedFork = AccountingRolloutParser()
        indexedFork.consume(line("session_meta", ["forked_from_id": "synthetic-parent", "base_instructions": "ignored fixture"]), descriptor: descriptor(created: created))
        indexedFork.consume(context(), descriptor: descriptor(created: created))
        indexedFork.consume(request(), descriptor: descriptor(created: created))
        check(indexedFork.records.isEmpty, "indexed fork uses metadata boolean without exposing parent identity")

        let quotaPayload: [String: Any] = ["limit_id": "codex",
            "primary": ["used_percent": 10, "window_minutes": 300, "resets_at": 1790996400],
            "secondary": ["used_percent": 30, "window_minutes": 10080, "resets_at": 1791504000]]
        let quotaOnly = line("event_msg", ["type": "token_count", "info": NSNull(), "rate_limits": quotaPayload])
        var quotaParser = AccountingRolloutParser()
        quotaParser.consume(quotaOnly, descriptor: d)
        quotaParser.consume(quotaOnly, descriptor: d)
        check(quotaParser.records.isEmpty && quotaParser.quotaObservations.count == 1, "quota-only events survive null usage and duplicate replay")
        check(quotaParser.quotaObservations.first?.window.windowDurationMins == 10080, "historical observation keeps the longest valid Codex window")
        var unrelatedQuota = quotaPayload; unrelatedQuota["limit_id"] = "codex_other"
        quotaParser.consume(line("event_msg", ["type": "token_count", "rate_limits": unrelatedQuota]), descriptor: d)
        var unidentifiedQuota = quotaPayload; unidentifiedQuota.removeValue(forKey: "limit_id")
        quotaParser.consume(line("event_msg", ["type": "token_count", "rate_limits": unidentifiedQuota]), descriptor: d)
        check(quotaParser.quotaObservations.count == 1, "unidentified and separate model allowances do not become main quota evidence")
        quotaParser.consume(line("event_msg", ["type": "token_count", "rate_limits": "malformed fixture", "info": ["total_token_usage": tokens(100, 10), "last_token_usage": tokens(100, 10)]]), descriptor: d)
        check(quotaParser.records.count == 1 && quotaParser.issues.isEmpty, "malformed optional quota preserves otherwise valid token usage")
        var forkQuotaParser = AccountingRolloutParser()
        forkQuotaParser.consume(line("session_meta", ["forked_from_id": "synthetic-parent"]), descriptor: descriptor(created: created))
        forkQuotaParser.consume(quotaOnly, descriptor: descriptor(created: created))
        check(forkQuotaParser.quotaObservations.isEmpty, "fork inherited quota headers cannot bootstrap a child's reset")

        // Local midnight in UTC+8 is the prior UTC date at 16:00.
        let trackingStart = ISO8601DateFormatter().date(from: "2026-10-02T16:00:00Z")!
        var prospectiveParser = AccountingRolloutParser(trackingStart: trackingStart)
        prospectiveParser.consume(context(), descriptor: d)
        prospectiveParser.consume(request("old-exact"), descriptor: d)
        prospectiveParser.consume(legacy(tokens(1000, 100), at: "2026-10-02T15:59:59Z"), descriptor: d)
        prospectiveParser.consume(quotaOnly, descriptor: d)
        check(prospectiveParser.records.isEmpty && prospectiveParser.quotaObservations.isEmpty, "pre-cutoff usage and quota snapshots are omitted")
        prospectiveParser.consume(legacy(tokens(1100, 110), last: tokens(100, 10), at: "2026-10-02T16:00:00Z"), descriptor: d)
        check(prospectiveParser.records.count == 1 && prospectiveParser.records.first?.totalTokens == 110, "resumed old turn counts only the increment exactly at local midnight")
        check(prospectiveParser.records.first?.model == "fixture-model", "pre-cutoff context remains available for post-cutoff pricing")
        var firstPost = AccountingRolloutParser(trackingStart: trackingStart)
        firstPost.consume(legacy(tokens(1_000_100, 100_010), last: tokens(100, 10), at: "2026-10-02T16:00:01Z"), descriptor: d)
        check(firstPost.records.first?.totalTokens == 110, "a first observed lifetime counter is never counted as today's total")
        var boundaryExact = AccountingRolloutParser(trackingStart: trackingStart)
        boundaryExact.consume(context(), descriptor: d)
        boundaryExact.consume(request("old-exact"), descriptor: d)
        boundaryExact.consume(line("token_usage_record", ["response_id": "midnight-response", "thread_id": d.id, "turn_id": "fixture-turn", "usage": tokens(100, 10)], at: "2026-10-02T16:00:00Z"), descriptor: d)
        check(boundaryExact.records.count == 1 && boundaryExact.records.first?.quality == .reported, "exact request at midnight is included once without old responses")

        var oldMalformed = AccountingRolloutParser(trackingStart: trackingStart)
        oldMalformed.consume(context(), descriptor: d)
        oldMalformed.consume(legacy(tokens(1000, 100), at: "2026-10-02T15:00:00Z"), descriptor: d)
        oldMalformed.consume(line("event_msg", ["type": "token_count", "info": "malformed old fixture"], at: "2026-10-02T15:59:59Z"), descriptor: d)
        oldMalformed.consume(legacy(tokens(1_000_100, 100_010), last: tokens(100, 10), at: "2026-10-02T16:00:01Z"), descriptor: d)
        check(oldMalformed.records.first?.totalTokens == 110 && oldMalformed.issues.isEmpty, "malformed pre-cutoff usage drops its baseline without contaminating today's coverage")
        check(oldMalformed.records.first?.model == "fixture-model", "bad historical usage does not discard a valid model context")
        var oldRollback = AccountingRolloutParser(trackingStart: trackingStart)
        oldRollback.consume(legacy(tokens(1000, 100), at: "2026-10-02T14:00:00Z"), descriptor: d)
        oldRollback.consume(legacy(tokens(500, 50), at: "2026-10-02T15:59:59Z"), descriptor: d)
        oldRollback.consume(legacy(tokens(600, 60), last: tokens(100, 10), at: "2026-10-02T16:00:01Z"), descriptor: d)
        check(oldRollback.records.first?.totalTokens == 110 && oldRollback.issues.isEmpty, "historical counter rollback establishes a fresh prospective baseline")
        oldMalformed.consume(line("event_msg", ["type": "token_count", "info": "malformed current fixture"], at: "2026-10-02T17:00:00Z"), descriptor: d)
        check(oldMalformed.issues.contains(.invalidRecord), "malformed post-cutoff usage remains a coverage gap")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("accounting-fixtures-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.jsonl")
        var bytes = context(); bytes.append(10); bytes.append(request()); bytes.append(10)
        try bytes.write(to: file)
        let reader = UsageAccountingReader(allowedSessionRoots: [root])
        let fd = descriptor(path: file.path)
        var result = reader.read(threads: [fd], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture-account")
        check(result.records.count == 1 && result.scanned == 1, "reader opens only supplied scoped paths")
        result = reader.read(threads: [fd], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture-account")
        check(result.records.count == 1, "unchanged file uses cache without double-counting")
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        try handle.write(contentsOf: request("response-b")); try handle.close()
        result = reader.read(threads: [fd], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture-account")
        check(result.records.count == 1, "partial final line waits for complete append")
        let append = try FileHandle(forWritingTo: file); try append.seekToEnd(); try append.write(contentsOf: Data([10])); try append.close()
        result = reader.read(threads: [fd], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture-account")
        check(result.records.count == 2, "appended record is read incrementally")
        result = reader.read(threads: [fd], allowedWorkingDirectories: [], accountID: "fixture-account")
        check(result.records.isEmpty && result.issues.contains(.scopeRequired), "empty scope clears cache and never opens history")
        result = reader.read(threads: [fd], allowedWorkingDirectories: ["/different/project"], accountID: "fixture-account")
        check(result.records.isEmpty && result.issues.contains(.rolloutUnavailable), "cwd mismatch is rejected before opening the path")
        let symlink = root.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
        result = reader.read(threads: [descriptor(path: symlink.path)], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture-account")
        check(result.records.isEmpty, "symlink rollouts are rejected")
        result = reader.read(threads: [descriptor(path: root.path + "/../fixture.jsonl")], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture-account")
        check(result.records.isEmpty, "path traversal is rejected")
        try (context() + Data([10]) + request("replacement") + Data([10])).write(to: file)
        result = reader.read(threads: [fd], allowedWorkingDirectories: ["/fixture/project"], accountID: "different-account")
        check(result.records.count == 1 && result.records.first?.id == "response:replacement", "account change invalidates stale cached records")

        let budgetFile = root.appendingPathComponent("budget.jsonl")
        let filler = line("response_item", ["text": String(repeating: "x", count: 256)]) + Data([10])
        var large = Data()
        for _ in 0..<18_000 { large.append(filler) }
        large.append(context()); large.append(10); large.append(request("budget-response")); large.append(10)
        try large.write(to: budgetFile)
        let budgetDescriptor = descriptor(path: budgetFile.path)
        let budgetReader = UsageAccountingReader(allowedSessionRoots: [root])
        var budgetResult = budgetReader.read(threads: [budgetDescriptor], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture")
        check(budgetResult.issues.contains(.historyCatchingUp) && budgetResult.records.isEmpty, "large first import obeys per-file byte budget")
        budgetResult = budgetReader.read(threads: [budgetDescriptor], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture")
        check(budgetResult.records.count == 1 && !budgetResult.issues.contains(.historyCatchingUp), "next refresh continues at the saved byte offset")
        let cancelledReader = UsageAccountingReader(allowedSessionRoots: [root])
        var continuationChecks = 0
        let cancelled = cancelledReader.read(threads: [budgetDescriptor], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture", shouldContinue: {
            continuationChecks += 1; return continuationChecks < 3
        })
        check(cancelled.records.isEmpty && cancelled.issues.contains(.historyCatchingUp), "cancellation interrupts history import before more file reads")
        let cachedBeforeRejection = reader.read(threads: [fd], allowedWorkingDirectories: ["/fixture/project"], accountID: "different-account")
        check(cachedBeforeRejection.records.count == 1, "valid source is cached before rejection regression")
        let rejectedCached = reader.read(threads: [descriptor(path: symlink.path)], allowedWorkingDirectories: ["/fixture/project"], accountID: "different-account")
        check(rejectedCached.records.isEmpty, "a newly invalid path drops its old cached counters")

        let nested = AccountingThreadDescriptor(id: fd.id, name: nil, cwd: "/fixture/project/nested", path: file.path,
            createdAt: 0, updatedAt: 100, recencyAt: nil, forkedFromId: nil, parentThreadId: nil)
        let recursive = reader.read(threads: [nested], allowedWorkingDirectories: ["/fixture/project"], accountID: "different-account")
        check(recursive.records.count == 1, "reader accepts indexed descendants under an authorized root")
        let sibling = AccountingThreadDescriptor(id: fd.id, name: nil, cwd: "/fixture/project-sibling", path: file.path,
            createdAt: 0, updatedAt: 100, recencyAt: nil, forkedFromId: nil, parentThreadId: nil)
        let siblingResult = reader.read(threads: [sibling], allowedWorkingDirectories: ["/fixture/project"], accountID: "different-account")
        check(siblingResult.records.isEmpty, "reader independently rejects sibling prefixes after a cached import")

        let quotaFile1 = root.appendingPathComponent("quota-one.jsonl"), quotaFile2 = root.appendingPathComponent("quota-two.jsonl")
        try (quotaOnly + Data([10])).write(to: quotaFile1)
        try (quotaOnly + Data([10])).write(to: quotaFile2)
        let quotaMerged = reader.read(threads: [descriptor(id: "quota-one", path: quotaFile1.path), descriptor(id: "quota-two", path: quotaFile2.path)],
            allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture-account")
        check(quotaMerged.quotaObservations.count == 1, "identical quota snapshots deduplicate across scoped files")

        let prospectiveFile = root.appendingPathComponent("prospective.jsonl")
        let beforeLine = line("token_usage_record", ["response_id": "before-midnight", "thread_id": d.id, "turn_id": "fixture-turn", "usage": tokens(100, 10)], at: "2026-10-02T15:59:59Z")
        let afterLine = line("token_usage_record", ["response_id": "after-midnight", "thread_id": d.id, "turn_id": "fixture-turn", "usage": tokens(100, 10)], at: "2026-10-02T16:00:00Z")
        let laterLine = line("token_usage_record", ["response_id": "later-response", "thread_id": d.id, "turn_id": "fixture-turn", "usage": tokens(100, 10)], at: "2026-10-02T17:00:00Z")
        try (context() + Data([10]) + beforeLine + Data([10]) + afterLine + Data([10]) + laterLine + Data([10])).write(to: prospectiveFile)
        let continued = AccountingThreadDescriptor(id: d.id, name: nil, cwd: "/fixture/project", path: prospectiveFile.path,
            createdAt: 100, updatedAt: trackingStart.timeIntervalSince1970 + 3600, recencyAt: nil, forkedFromId: nil, parentThreadId: nil)
        let prospectiveReader = UsageAccountingReader(allowedSessionRoots: [root])
        let fromMidnight = prospectiveReader.read(threads: [continued], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture", trackingStart: trackingStart)
        check(fromMidnight.records.count == 2, "continued old conversation imports only today's exact responses")
        let laterStart = trackingStart.addingTimeInterval(3600)
        let fromLater = prospectiveReader.read(threads: [continued], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture", trackingStart: laterStart)
        check(fromLater.records.map(\.id) == ["response:later-response"], "cutoff change clears cached earlier records")
        let restartReader = UsageAccountingReader(allowedSessionRoots: [root])
        let restarted = restartReader.read(threads: [continued], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture", trackingStart: trackingStart)
        check(restarted.records == fromMidnight.records, "cold restart replays the same prospective records")
        let newAppend = try FileHandle(forWritingTo: prospectiveFile)
        try newAppend.seekToEnd(); try newAppend.write(contentsOf: laterLine + Data([10])); try newAppend.close()
        let replayed = restartReader.read(threads: [continued], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture", trackingStart: trackingStart)
        check(replayed.records.count == 2, "post-cutoff append replay remains idempotent")
        let inactive = AccountingThreadDescriptor(id: "inactive", name: nil, cwd: "/fixture/project", path: nil,
            createdAt: 100, updatedAt: 200, recencyAt: nil, forkedFromId: nil, parentThreadId: nil)
        let skipped = restartReader.read(threads: [inactive], allowedWorkingDirectories: ["/fixture/project"], accountID: "fixture", trackingStart: trackingStart)
        check(skipped.records.isEmpty && skipped.scanned == 0 && skipped.issues.isEmpty, "inactive pre-cutoff descriptor is skipped before any log-path access")

        let account = try JSONDecoder().decode(AccountTokenActivity.self, from: Data(#"{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":null}"#.utf8))
        check(account.summary.lifetimeTokens == nil && account.dailyUsageBuckets == nil, "unavailable account metrics are not zero")
        let scoped = try JSONDecoder().decode(AccountingThreadDescriptor.self, from: Data(#"{"id":"fixture","name":null,"cwd":"/fixture/project","path":null,"createdAt":1,"updatedAt":2,"preview":"synthetic private text"}"#.utf8))
        check(scoped.name == nil, "message preview is never substituted for a title")
        print("Accounting checks passed: \(checked)")
    }
}
