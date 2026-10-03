import Foundation

private struct FixtureThreadIndex: ThreadIndexReading {
    let sessionRoot: URL
    let unavailable: Bool
    func read(allowedRoots: [String], limit: Int, shouldContinue: @escaping @Sendable () -> Bool) throws -> ScopedThreadIndexResult {
        if unavailable { throw ThreadIndexError.unavailable }
        precondition(allowedRoots == ["/fixture/project"])
        let entries = ["fixture-current", "fixture-archived", "wrong-cwd"].map { id in
            AccountingThreadDescriptor(id: id, name: nil,
                cwd: id == "wrong-cwd" ? "/not-selected" : "/fixture/project/nested",
                path: sessionRoot.appendingPathComponent(id + ".jsonl").path,
                createdAt: 0, updatedAt: id == "fixture-current" ? 2 : 1, recencyAt: nil,
                forkedFromId: nil, parentThreadId: nil)
        }
        return ScopedThreadIndexResult(threads: entries, isComplete: true, issues: [])
    }
}

@main @MainActor struct AccountingConnectionChecks {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), "FAILED: " + label); checks += 1; print("PASS: " + label)
    }
    static func main() async throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("accounting-connection-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func connection(_ mode: String) throws -> (CodexConnection, URL) {
            let runtime = root.appendingPathComponent(mode)
            let sessions = runtime.appendingPathComponent("sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            if mode == "usage-error" { try mode.write(to: runtime.appendingPathComponent("mode"), atomically: true, encoding: .utf8) }
            for id in ["fixture-current", "fixture-archived"] {
                let content = """
                {"type":"turn_context","payload":{"model":"fixture-model","turn_id":"fixture-turn"}}
                {"timestamp":"2026-10-02T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","secondary":{"used_percent":30,"window_minutes":10080,"resets_at":1791504000}}}}
                {"timestamp":"2026-10-02T12:00:00Z","type":"token_usage_record","payload":{"response_id":"\(id)-response","thread_id":"\(id)","turn_id":"fixture-turn","usage":{"input_tokens":100,"cached_input_tokens":20,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":110}}}

                """
                try content.write(to: sessions.appendingPathComponent(id + ".jsonl"), atomically: true, encoding: .utf8)
            }
            return (CodexConnection(executable: executable, runtime: runtime, accountingReader: UsageAccountingReader(allowedSessionRoots: [sessions]),
                threadIndex: FixtureThreadIndex(sessionRoot: sessions, unavailable: mode == "fallback" || mode == "index-missing"),
                allowExactScopeFallback: mode == "fallback"), runtime)
        }
        let (empty, emptyRuntime) = try connection("empty")
        let emptyResult = try await empty.readDashboard(allowedWorkingDirectories: [])
        let emptyCalls = try String(contentsOf: emptyRuntime.appendingPathComponent("requests"), encoding: .utf8).split(separator: "\n").map(String.init)
        check(emptyCalls == ["initialize", "initialized", "account/rateLimits/read", "account/usage/read"], "empty scope makes only aggregate read-only requests")
        check(emptyResult.accounting.recentThreads.isEmpty && emptyResult.accounting.records.isEmpty, "empty scope cannot expose conversation data")
        check(emptyResult.accounting.account?.summary.lifetimeTokens == 1000, "aggregate usage survives without local scope")

        let (scoped, scopedRuntime) = try connection("scoped")
        let result = try await scoped.readDashboard(allowedWorkingDirectories: ["/fixture/project"])
        let calls = try String(contentsOf: scopedRuntime.appendingPathComponent("requests"), encoding: .utf8).split(separator: "\n").map(String.init)
        let starts = try String(contentsOf: scopedRuntime.appendingPathComponent("starts"), encoding: .utf8).split(separator: "\n")
        check(starts.count == 1 && calls.filter { $0 == "initialize" }.count == 1, "rich dashboard refresh owns exactly one child")
        check(!calls.contains("thread/list"), "recursive index performs no global or exact-cwd RPC listing")
        check(result.accounting.recentThreads.count == 2 && result.accounting.recentThreads.first?.id == "fixture-current", "recent conversations include archived and sort by recency")
        check(result.accounting.records.count == 2 && result.accounting.scannedThreadCount == 2, "unexpected cwd never reaches file reader")
        check(result.accounting.recentThreads.allSatisfy { $0.usage != nil }, "conversation usage uses individual read-only billing routes")
        check(Set(calls).isSubset(of: ["initialize", "initialized", "account/rateLimits/read", "account/usage/read", "thread/list"]), "dashboard sends no mutation or model methods")
        check(result.accounting.quotaObservations.count == 1, "dashboard publishes deduplicated historical quota evidence")
        check(result.quota.accountId == "fixture-account", "opaque account identity is available for cache separation")

        let (errorConnection, _) = try connection("usage-error")
        let partial = try await errorConnection.readDashboard(allowedWorkingDirectories: [])
        check(partial.quota.main?.primary?.usedPercent == 20 && partial.accounting.issues.contains(.accountUsageUnavailable), "usage endpoint failure preserves quota and marks missing metrics")
        let (fallbackConnection, fallbackRuntime) = try connection("fallback")
        let fallback = try await fallbackConnection.readDashboard(allowedWorkingDirectories: ["/fixture/project"])
        let fallbackCalls = try String(contentsOf: fallbackRuntime.appendingPathComponent("requests"), encoding: .utf8).split(separator: "\n").map(String.init)
        check(fallbackCalls.filter { $0 == "thread/list" }.count == 2 && fallback.accounting.issues.contains(.recursiveCoverageUnavailable) && !fallback.accounting.recordsAreComplete, "explicit exact-scope fallback cannot claim recursive completeness")
        let (missingIndexConnection, missingRuntime) = try connection("index-missing")
        let missingIndex = try await missingIndexConnection.readDashboard(allowedWorkingDirectories: ["/fixture/project"])
        let missingCalls = try String(contentsOf: missingRuntime.appendingPathComponent("requests"), encoding: .utf8)
        check(!missingCalls.contains("thread/list") && missingIndex.accounting.records.isEmpty && missingIndex.accounting.issues.contains(.threadIndexUnavailable), "default missing-index behavior fails closed without a history RPC")
        let (prospectiveConnection, prospectiveRuntime) = try connection("prospective")
        let prospective = try await prospectiveConnection.readDashboard(allowedWorkingDirectories: ["/fixture/project"], trackingStart: Date(timeIntervalSince1970: 0))
        let prospectiveCalls = try String(contentsOf: prospectiveRuntime.appendingPathComponent("requests"), encoding: .utf8).split(separator: "\n").map(String.init)
        check(prospectiveCalls == ["initialize", "initialized", "account/rateLimits/read"], "prospective mode makes no account or conversation lifetime usage requests")
        check(prospective.accounting.account == nil && prospective.accounting.records.count == 2 && prospective.accounting.recentThreads.allSatisfy { $0.usage == nil }, "prospective recent metrics rely on local tracked responses only")
        let (zeroConnection, zeroRuntime) = try connection("prospective-zero")
        let zero = try await zeroConnection.readDashboard(allowedWorkingDirectories: ["/fixture/project"], trackingStart: Date(timeIntervalSince1970: 3))
        check(zero.accounting.records.isEmpty && zero.accounting.recentThreads.isEmpty && zero.accounting.recordsAreComplete && zero.accounting.issues.isEmpty, "complete empty prospective index establishes a known zero")
        let zeroCalls = try String(contentsOf: zeroRuntime.appendingPathComponent("requests"), encoding: .utf8).split(separator: "\n")
        check(zeroCalls.count == 3, "known-zero refresh still makes only quota RPCs")
        print("Accounting connection checks passed: \(checks)")
    }
}
