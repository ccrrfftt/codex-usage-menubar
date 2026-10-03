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

        let account = try JSONDecoder().decode(AccountTokenActivity.self, from: Data(#"{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":null}"#.utf8))
        check(account.summary.lifetimeTokens == nil && account.dailyUsageBuckets == nil, "unavailable account metrics are not zero")
        let scoped = try JSONDecoder().decode(AccountingThreadDescriptor.self, from: Data(#"{"id":"fixture","name":null,"cwd":"/fixture/project","path":null,"createdAt":1,"updatedAt":2,"preview":"synthetic private text"}"#.utf8))
        check(scoped.name == nil, "message preview is never substituted for a title")
        print("Accounting checks passed: \(checked)")
    }
}
