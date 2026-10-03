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
        let unnamedThreads = (1...4).map { index in
            AccountingThread(id: "synthetic-\(index)", name: nil, updatedAt: now, recencyAt: now, usage: nil)
        }
        let unnamedSnapshot = AccountingSnapshot(observedAt: now, account: nil, recentThreads: unnamedThreads,
            records: [], issues: [.scopeRequired], scannedThreadCount: 0, recordsAreComplete: false)
        let unnamed = AccountingSummary.make(snapshot: unnamedSnapshot, calendar: calendar, reset: .init(),
            now: now, folderCount: 1, language: .english)
        check(unnamed.conversations.count == 3 && unnamed.conversations[0].title.hasPrefix("Unnamed chat 1 · ") &&
              unnamed.conversations[2].title.hasPrefix("Unnamed chat 3 · "),
              "unnamed conversations stay identifiable by order and timestamp without reading message previews")
        check(AppLanguage.chinese.accountingConversation(2, updatedAt: now).hasPrefix("未命名对话 2 · "),
              "privacy-preserving conversation labels follow the selected language")
        let nextWindow = date("2026-10-08T00:00:00Z")
        let oldWindow = date("2026-10-01T00:00:00Z")
        var historyTracker = AccountingResetTracker()
        historyTracker.observe(accountID: "synthetic-account", window: .init(usedPercent: 10,
            windowDurationMins: 10080, resetsAt: nextWindow.timeIntervalSince1970), at: now)
        var historicalSnapshot = snapshot(records)
        historicalSnapshot.quotaObservations = [
            .init(timestamp: date("2026-09-30T20:00:00Z"), window: .init(usedPercent: 80, windowDurationMins: 10080, resetsAt: oldWindow.timeIntervalSince1970)),
            .init(timestamp: date("2026-10-01T00:03:00Z"), window: .init(usedPercent: 2, windowDurationMins: 10080, resetsAt: nextWindow.timeIntervalSince1970)),
            .init(timestamp: date("2026-10-03T10:00:00Z"), window: .init(usedPercent: 9, windowDurationMins: 10080, resetsAt: nextWindow.timeIntervalSince1970))
        ]
        let historicalSummary = AccountingSummary.make(snapshot: historicalSnapshot, calendar: calendar,
            reset: historyTracker, now: now, folderCount: 1, language: .english)
        check(historicalSummary.sinceReset.tokens == 1_100 && historicalSummary.lastResetFromHistory &&
              historicalSummary.sinceReset.isEstimated && historicalSummary.lastReset == date("2026-10-01T00:03:00Z"),
              "historical quota evidence makes the since-reset row useful on first launch without inventing an exact instant")
        var liveTracker = AccountingResetTracker()
        liveTracker.observe(accountID: "synthetic-account", window: .init(usedPercent: 80,
            windowDurationMins: 10080, resetsAt: oldWindow.timeIntervalSince1970), at: date("2026-09-30T20:00:00Z"))
        liveTracker.observe(accountID: "synthetic-account", window: .init(usedPercent: 1,
            windowDurationMins: 10080, resetsAt: nextWindow.timeIntervalSince1970), at: date("2026-10-01T00:01:00Z"))
        liveTracker.observe(accountID: "synthetic-account", window: .init(usedPercent: 10,
            windowDurationMins: 10080, resetsAt: nextWindow.timeIntervalSince1970), at: now)
        let preferredLive = AccountingSummary.make(snapshot: historicalSnapshot, calendar: calendar,
            reset: liveTracker, now: now, folderCount: 1, language: .english)
        check(!preferredLive.lastResetFromHistory && preferredLive.lastReset == date("2026-10-01T00:01:00Z"),
              "live account-bound reset evidence takes precedence over historical inference")
        check(AppLanguage.english.accountingResetTitle(minutes: 10080) == "Since last reset" &&
              AppLanguage.chinese.accountingResetTitle(minutes: 10080) == "上次重置",
              "reset row keeps the requested compact bilingual label")
        let trackingStart = date("2026-10-03T00:00:00Z")
        let prospective = AccountingSummary.make(snapshot: snapshot(records), calendar: calendar,
            reset: .init(), now: now, folderCount: 1, language: .english, trackingStart: trackingStart)
        check(prospective.today.tokens == 1_100 && !prospective.today.tokensArePartial &&
              prospective.trackingStartedAt == trackingStart,
              "prospective totals include the first local day and expose their fixed tracking start")
        check(prospective.cycle.tokens == 1_100 && prospective.cycle.tokensArePartial &&
              prospective.cycle.costIsPartial && !prospective.canCompareSelectedCycle,
              "the first incomplete subscription cycle excludes older history and cannot assert below $200")
        let emptyScoped = AccountingSnapshot(observedAt: now, account: nil, recentThreads: [], records: [],
            issues: [], scannedThreadCount: 0, recordsAreComplete: true)
        let prospectiveZero = AccountingSummary.make(snapshot: emptyScoped, calendar: calendar,
            reset: .init(), now: now, folderCount: 1, language: .english, trackingStart: trackingStart)
        check(prospectiveZero.today.tokens == 0 && prospectiveZero.today.apiUSD == 0 &&
              prospectiveZero.coverage == .complete,
              "a successful empty prospective index means known zero usage today")
        check(prospectiveZero.cycle.tokens == 0 && prospectiveZero.cycle.costIsPartial &&
              !prospectiveZero.canCompareSelectedCycle,
              "an empty first partial cycle retains the missing-days boundary")
        let noScope = AccountingSummary.make(snapshot: service, calendar: calendar, reset: .init(), now: now,
            folderCount: 0, language: .english, trackingStart: trackingStart)
        check(noScope.today.tokens == nil && noScope.cycle.apiUSD == nil,
              "prospective local accounting never substitutes account-wide service-date buckets")
        let nextNow = date("2026-10-06T12:00:00Z")
        let next = AccountingSummary.make(snapshot: snapshot(records + [record("next", "2026-10-05T08:00:00Z")]),
            calendar: calendar, reset: .init(), now: nextNow, folderCount: 1, language: .english,
            trackingStart: trackingStart)
        check(next.cycle.tokens == 1_100 && !next.cycle.tokensArePartial && next.canCompareSelectedCycle,
              "the next subscription cycle becomes fully comparable without changing tracking start")
        let lifetime = try JSONDecoder().decode(AccountingThreadUsage.self, from: Data(#"{"threadId":"fixture","estimatedUsageCreditsMicros":0,"groups":[{"model":"gpt-6.1-sol","inputTokens":9000000,"outputTokens":1000000,"totalTokens":10000000,"estimatedUsageCreditsMicros":0}]}"#.utf8))
        let prospectiveThreads = AccountingSnapshot(observedAt: now, account: nil, recentThreads: [
            .init(id: "fixture", name: nil, updatedAt: now, recencyAt: now, usage: lifetime),
            .init(id: "old", name: nil, updatedAt: date("2026-10-02T20:00:00Z"),
                  recencyAt: date("2026-10-02T20:00:00Z"), usage: nil)],
            records: records, issues: [], scannedThreadCount: 2, recordsAreComplete: true)
        let recentProspective = AccountingSummary.make(snapshot: prospectiveThreads, calendar: calendar,
            reset: .init(), now: now, folderCount: 1, language: .english, trackingStart: trackingStart)
        check(recentProspective.conversations.count == 1 && recentProspective.conversations[0].metric.tokens == 1_100,
              "recent conversations show only post-start usage, never lifetime service totals or inactive old chats")
        let priorReset = AccountingSummary.make(snapshot: historicalSnapshot, calendar: calendar,
            reset: liveTracker, now: now, folderCount: 1, language: .english, trackingStart: trackingStart)
        check(priorReset.sinceReset.tokens == 1_100 && priorReset.sinceReset.tokensArePartial,
              "a reset before tracking start remains a partial known subtotal")
        var initialWindow = AccountingResetTracker()
        initialWindow.observe(accountID: "synthetic-account", window: .init(usedPercent: 30,
            windowDurationMins: 10080, resetsAt: date("2026-10-10T05:00:00Z").timeIntervalSince1970), at: now)
        let sameDayRecords = [record("before-reset", "2026-10-03T02:00:00Z"), record("after-reset", "2026-10-03T10:00:00Z")]
        let initial = AccountingSummary.make(snapshot: snapshot(sameDayRecords), calendar: calendar,
            reset: initialWindow, now: now, folderCount: 1, language: .english, trackingStart: trackingStart)
        check(initial.today.tokens == 2_200 && initial.sinceReset.tokens == 1_100 &&
              initial.lastResetFromSchedule && initial.sinceReset.isEstimated,
              "an unobserved reset shows an explicit window estimate and excludes earlier usage today")
        check(initial.lastReset == date("2026-10-03T05:00:00Z") && initialWindow.resetUpperBound == nil,
              "scheduled fallback never fabricates an observed reset timestamp")
        check(!preferredLive.lastResetFromSchedule && !historicalSummary.lastResetFromSchedule,
              "stronger live and historical reset evidence precedes the scheduled estimate")
        let named = AccountingThread(id: "fixture", name: "A named Codex conversation", updatedAt: now, recencyAt: now, usage: nil)
        let namedSnapshot = AccountingSnapshot(observedAt: now, account: nil, recentThreads: [named], records: records,
            issues: [], scannedThreadCount: 1, recordsAreComplete: true)
        check(AccountingSummary.make(snapshot: namedSnapshot, calendar: calendar, reset: .init(), now: now,
            folderCount: 1, language: .chinese, trackingStart: trackingStart).conversations.first?.title == named.name,
            "the real scoped conversation title takes precedence over the unnamed fallback")
        check(AccountingMetricPresentation(apiUSD: 206.76).menuCostText() == "$207" &&
              AccountingMetricPresentation(apiUSD: 206.76).costText() == "$206.76",
              "menu values remove decimals while detailed values retain cents")
        check(AccountingMetricPresentation(apiUSD: 206.76, costIsPartial: true).menuCostText() == "≥$206",
              "rounded partial values never overstate a known lower bound")
        for (value, expected) in [(999.0, "$999"), (999.5, "$1K"), (1200.0, "$1K"),
            (999_500.0, "$1M"), (1_500_000.0, "$2M"), (999_500_000.0, "$1B"), (2_400_000_000.0, "$2B")] {
            check(AccountingMetricPresentation(apiUSD: value).menuCostText() == expected,
                  "compact menu boundary: \(value) → \(expected)")
        }
        check(AccountingMetricPresentation(apiUSD: 12.75, costUpperBoundUSD: 13.10).menuCostText() == "$12–14",
              "integer price ranges retain both outward-rounded bounds")
        check(AccountingMetricPresentation(apiUSD: 0.2).menuCostText() == "<$1" &&
              AccountingMetricPresentation().menuCostText() == "—", "small and unavailable amounts remain distinct")
        check(MenuBarFormatting.percent(14.9) == "14%" && MenuBarFormatting.percent(15) == "15%",
              "integer percentages remain consistent with the strict below-15 warning")
        state.lastError = nil
        state.accountingPresentation.cycle = .init(apiUSD: 199.99)
        check(state.statusItem.valueTitle == "<$200" && state.statusItem.ring.showsValueWarning &&
              state.statusItem.tooltip.contains("$199.99"),
              "rounded menu text cannot contradict the below-$200 marker and tooltip retains detail")
        print("\(count) accounting summary checks passed.")
    }
}
