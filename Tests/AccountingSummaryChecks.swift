import Foundation

@main
struct AccountingSummaryChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ title: String) {
            precondition(condition(), "FAILED: " + title)
            count += 1
            print("PASS: " + title)
        }
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        let now = date("2026-10-03T12:00:00Z")
        let calendar = AccountingCalendar(renewalDay: 5, timeZone: TimeZone(secondsFromGMT: 0)!)
        func record(_ id: String, _ timestamp: String, model: String? = "gpt-6.1-sol",
                    quality: AccountingRecordQuality = .reported) -> AccountingUsageRecord {
            AccountingUsageRecord(id: id, threadID: "fixture", timestamp: date(timestamp), model: model,
                serviceTier: "irrelevant-subscription-speed", inputTokens: 1_000, cachedInputTokens: 0,
                cacheWriteInputTokens: 0, outputTokens: 100, reasoningOutputTokens: 30,
                totalTokens: 1_100, quality: quality)
        }
        func snapshot(_ records: [AccountingUsageRecord], complete: Bool = true) -> AccountingSnapshot {
            AccountingSnapshot(observedAt: now, account: nil, recentThreads: [], records: records,
                issues: complete ? [] : [.threadLimitReached], scannedThreadCount: 1, recordsAreComplete: complete)
        }
        let records = [record("old", "2026-09-04T12:00:00Z"), record("cycle", "2026-09-06T12:00:00Z"),
                       record("today", "2026-10-03T10:00:00Z"), record("future", "2026-10-03T20:00:00Z")]
        let summary = AccountingSummary.make(snapshot: snapshot(records), calendar: calendar,
            reset: AccountingResetTracker(), now: now, folderCount: 1, language: .english)
        check(summary.today.tokens == 1_100, "today excludes previous days and future timestamps")
        check(summary.cycle.tokens == 2_200, "subscription day 5 includes September usage without using the calendar month")
        check(summary.cycleStart == date("2026-09-05T00:00:00Z") && summary.cycleEnd == date("2026-10-05T00:00:00Z"), "cycle dates use the configured billing anchor")
        check(abs((summary.cycle.apiUSD ?? -1) - 0.006) < 0.0000001, "per-request Standard value counts reasoning only once and preserves request context")
        check(summary.sinceReset.tokens == nil, "unobserved reset does not invent a statistical starting time")
        check(summary.canCompareSelectedCycle, "complete selected scope enables an explicitly scoped comparison")
        let partial = AccountingSummary.metric(records: records, complete: false)
        check(partial.tokensArePartial && partial.costIsPartial && partial.costText().hasPrefix("≥"), "missing records are a disclosed lower bound")
        let legacy = AccountingSummary.metric(records: [record("legacy", "2026-10-03T10:00:00Z", quality: .estimated)], complete: false)
        check(legacy.isEstimated && legacy.tokenText(in: .english).hasPrefix("≈") && legacy.costText().hasPrefix("≈"), "legacy estimates are not falsely presented as guaranteed lower bounds")
        let unknown = AccountingSummary.metric(records: [record("unknown", "2026-10-03T10:00:00Z", model: "unknown-model")], complete: true)
        check(unknown.tokens == 1_100 && unknown.apiUSD == nil, "unknown model keeps tokens but never becomes zero dollars")
        let mixed = AccountingSummary.metric(records: [records[0], record("unknown", "2026-10-03T10:00:00Z", model: nil)], complete: true)
        check(mixed.apiUSD != nil && mixed.costIsPartial, "known model subtotal survives an unpriced model with explicit partial coverage")
        check(AccountingSummary.metric(records: [], complete: false).tokens == nil, "an incomplete empty source is unavailable, not zero")
        check(AccountingSummary.metric(records: [], complete: true).tokens == 0, "an explicitly complete empty source can represent zero")
        let account = try JSONDecoder().decode(AccountTokenActivity.self, from: Data(#"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-09-04","tokens":100},{"startDate":"2026-09-05","tokens":200},{"startDate":"2026-10-03","tokens":300}]}"#.utf8))
        let service = AccountingSnapshot(observedAt: now, account: account, recentThreads: [], records: [],
            issues: [.scopeRequired], scannedThreadCount: 0, recordsAreComplete: false)
        let serviceSummary = AccountingSummary.make(snapshot: service, calendar: calendar, reset: .init(), now: now, folderCount: 0, language: .english)
        check(serviceSummary.cycle.tokens == 500 && serviceSummary.today.tokens == 300, "service-date buckets respect billing day instead of natural month")
        check(serviceSummary.cycle.isEstimated && serviceSummary.cycle.apiUSD == nil, "undocumented service timezone remains approximate and does not invent per-model prices")
        let quota = try JSONDecoder().decode(QuotaSnapshot.self, from: Data(#"{"rateLimits":{"primary":{"usedPercent":50}}}"#.utf8))
        var state = UsageState(snapshot: quota, updatedAt: now, now: now)
        state.accountingPresentation.cycle = .init(tokens: 100, apiUSD: 199)
        check(!state.statusItem.ring.showsValueWarning, "unverified scope cannot assert a below-cost value")
        state.accountingPresentation.canCompareSelectedCycle = true
        check(state.statusItem.ring.showsValueWarning, "complete sub-$200 equivalent displays the center marker")
        state.accountingPresentation.cycle.apiUSD = 200
        check(!state.statusItem.ring.showsValueWarning, "exactly $200 is not below the subscription cost")
        state.accountingPresentation.cycle = .init(apiUSD: 150, costUpperBoundUSD: 210)
        check(!state.statusItem.ring.showsValueWarning, "a price interval crossing $200 does not make a false below-cost assertion")
        state.accountingPresentation.cycle = .init(apiUSD: 100, costIsPartial: true)
        check(!state.statusItem.ring.showsValueWarning, "partial dollar coverage never triggers the below-cost marker")
        state.accountingPresentation.cycle = .init(apiUSD: 100)
        state.lastError = .timedOut
        check(!state.statusItem.ring.showsValueWarning, "stale values do not trigger a new below-cost assertion")
        print("\(count) accounting summary checks passed.")
    }
}
