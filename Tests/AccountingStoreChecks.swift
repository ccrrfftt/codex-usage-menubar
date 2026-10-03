import Combine
import Foundation

private actor ControlledDashboardReader: DashboardReading {
    private(set) var scopes: [[String]] = []
    private(set) var trackingStarts: [Date?] = []
    private(set) var cancelled = Set<Int>()
    private(set) var quotaOnlyReads = 0
    private var pending: [Int: CheckedContinuation<DashboardSnapshot, Error>] = [:]

    func read() async throws -> QuotaSnapshot {
        quotaOnlyReads += 1
        throw QuotaError.unavailable
    }

    func readDashboard(allowedWorkingDirectories: [String], trackingStart: Date?) async throws -> DashboardSnapshot {
        trackingStarts.append(trackingStart)
        return try await readDashboard(allowedWorkingDirectories: allowedWorkingDirectories)
    }

    func readDashboard(allowedWorkingDirectories: [String]) async throws -> DashboardSnapshot {
        let id = scopes.count
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                scopes.append(allowedWorkingDirectories)
                pending[id] = continuation
            }
        } onCancel: {
            Task { await self.markCancelled(id) }
        }
    }

    private func markCancelled(_ id: Int) { cancelled.insert(id) }
    // Intentionally returns successful late replies after cancellation.
    func resolve(_ id: Int, _ value: DashboardSnapshot) { pending.removeValue(forKey: id)?.resume(returning: value) }
}

@MainActor private final class AccountingTestClock { var value: TimeInterval = 1_000 }

@MainActor private final class AccountingTestScheduler: RefreshScheduling {
    private(set) var delay: TimeInterval?
    private var action: (@MainActor () -> Void)?
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.delay = delay; self.action = action
    }
    func cancel() { delay = nil; action = nil }
    func fire() { let saved = action; cancel(); saved?() }
}

private struct AccountingStoreFailure: Error, CustomStringConvertible {
    let description: String
}

@main @MainActor
struct AccountingStoreChecks {
    private static var checked = 0
    private static let folderA = "/private/tmp/synthetic-accounting-project-a"
    private static let folderB = "/private/tmp/synthetic-accounting-project-b"

    static func check(_ value: Bool, _ label: String) throws {
        guard value else { throw AccountingStoreFailure(description: "FAILED: " + label) }
        checked += 1
        print("PASS: " + label)
    }

    static func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AccountingStoreFailure(description: "Timed out waiting for controlled Store operation")
    }

    static func fixture(_ marker: String, todayTokens: Int64 = 500, used: Double = 40,
                        reset: Date = .now.addingTimeInterval(3_600), empty: Bool = false) throws -> DashboardSnapshot {
        let now = Date.now
        let calendar = AccountingCalendar(renewalDay: 5).calendar
        let today = calendar.startOfDay(for: now)
        let previous = calendar.date(byAdding: .day, value: -1, to: today)!
        let object: [String: Any] = ["accountId": "synthetic-store-account", "rateLimits": [
            "primary": ["usedPercent": used, "windowDurationMins": 10_080, "resetsAt": reset.timeIntervalSince1970]]]
        let quota = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        func record(_ suffix: String, at date: Date, total: Int64) -> AccountingUsageRecord {
            .init(id: marker + suffix, threadID: marker, timestamp: date, model: "gpt-6-astra", serviceTier: "fast",
                  inputTokens: total, cachedInputTokens: 0, cacheWriteInputTokens: 0, outputTokens: 0,
                  reasoningOutputTokens: 0, totalTokens: total, quality: .reported)
        }
        return DashboardSnapshot(quota: quota, accounting: AccountingSnapshot(observedAt: now, account: nil,
            recentThreads: empty ? [] : [.init(id: marker, name: "Synthetic " + marker, updatedAt: now, recencyAt: now, usage: nil)],
            records: empty ? [] : [record("-today", at: today, total: todayTokens), record("-prior", at: previous, total: 250)],
            issues: empty ? [.scopeRequired] : [], scannedThreadCount: empty ? 0 : 1, recordsAreComplete: !empty))
    }

    static func billingAndLanguage() async throws {
        let reader = ControlledDashboardReader(), clock = AccountingTestClock(), scheduler = AccountingTestScheduler()
        let store = UsageStore(connection: reader, monitor: nil, scheduler: scheduler, preferences: nil,
                               startImmediately: false, uptime: { clock.value })
        defer { store.stop() }
        store.setBillingDay(5)
        try check(store.state.accountingPresentation.billingDay == 5
                  && store.state.accountingPresentation.cycleStart != nil, "setting renewal day updates period presentation immediately")
        store.setBillingDay(0)
        try check(store.state.accountingPresentation.billingDay == nil
                  && store.state.accountingPresentation.cycleStart == nil, "clearing renewal day removes the subscription period")
        try check(await reader.scopes.isEmpty, "billing settings do not trigger an API query")
        store.setAccountingFolders([folderA])
        try await waitFor { await reader.scopes.count == 1 }
        let day = AccountingCalendar(renewalDay: 5).calendar.component(.day, from: .now)
        store.setBillingDay(day)
        await reader.resolve(0, try fixture("first"))
        try await waitFor { !store.state.isRefreshing }
        try check(store.state.accountingPresentation.today.tokens == 500
                  && store.state.accountingPresentation.cycle.tokens == 500,
                  "renewal today excludes the previous day's usage while today remains correct")
        store.setBillingDay(day == 1 ? 31 : day - 1)
        try check(store.state.accountingPresentation.cycle.tokens == 500 && store.state.accountingPresentation.cycle.tokensArePartial,
                  "changing billing day never imports pre-tracking history or hides missing cycle days")
        let today = store.state.accountingPresentation.today
        store.setBillingDay(0)
        try check(store.state.accountingPresentation.cycle.tokens == nil
                  && store.state.accountingPresentation.cycle.apiUSD == nil
                  && store.state.accountingPresentation.today == today,
                  "clearing the cycle preserves independent today totals")
        store.setBillingDay(day)
        let presentation = store.state.accountingPresentation
        let updated = store.state.updatedAt, delay = scheduler.delay, language = store.state.language
        store.toggleLanguage()
        try check(store.state.language == language.other
                  && store.state.accountingPresentation.today == presentation.today
                  && store.state.accountingPresentation.cycle == presentation.cycle
                  && store.state.updatedAt == updated && scheduler.delay == delay,
                  "language switches preserve numeric accounting, freshness, and refresh timer")
        let quotaOnlyReads = await reader.quotaOnlyReads
        try check(await reader.scopes.count == 1 && quotaOnlyReads == 0,
                  "period and language edits send no additional dashboard or quota-only requests")
        try check(scheduler.delay == 60 && store.state.remaining == 60,
                  "accounting success retains normal quota and AC refresh scheduling")
    }

    static func replaceAndClearScopes() async throws {
        let reader = ControlledDashboardReader(), clock = AccountingTestClock(), scheduler = AccountingTestScheduler()
        let store = UsageStore(connection: reader, monitor: nil, scheduler: scheduler, preferences: nil,
                               startImmediately: false, uptime: { clock.value })
        defer { store.stop() }
        store.setBillingDay(5)
        store.setAccountingFolders([folderA])
        try await waitFor { await reader.scopes.count == 1 }
        await reader.resolve(0, try fixture("scope-a"))
        try await waitFor { !store.state.isRefreshing }
        clock.value += 6
        store.refresh()
        try await waitFor { await reader.scopes.count == 2 }
        clock.value += 6
        store.setAccountingFolders([folderB])
        try check(store.state.accountingPresentation.today.tokens == nil
                  && store.state.accountingPresentation.conversations.isEmpty,
                  "changing scope immediately removes previously displayed source records")
        try await waitFor {
            let count = await reader.scopes.count, cancelled = await reader.cancelled
            return count == 3 && cancelled.contains(1)
        }
        try check(await reader.scopes[2] == [folderB], "replacement request contains only the new chosen directory")
        await reader.resolve(1, try fixture("removed-late-a", todayTokens: 99_000, used: 99))
        try await Task.sleep(for: .milliseconds(20))
        try check(store.state.isRefreshing && store.state.accountingPresentation.today.tokens == nil,
                  "cancelled old-scope success cannot repopulate data or finish a newer request")
        await reader.resolve(2, try fixture("scope-b", todayTokens: 1_000))
        try await waitFor { !store.state.isRefreshing }
        try check(store.state.accountingPresentation.today.tokens == 1_000
                  && store.state.accountingPresentation.conversations.map(\.id) == ["scope-b"],
                  "only the replacement scope becomes visible")
        clock.value += 6
        store.refresh()
        try await waitFor { await reader.scopes.count == 4 }
        clock.value += 6
        store.clearAccountingFolders()
        try check(store.state.accountingPresentation.sourceFolderCount == 0
                  && store.state.accountingPresentation.conversations.isEmpty,
                  "clearing source selection immediately removes all local conversation rows")
        try await waitFor {
            let count = await reader.scopes.count, cancelled = await reader.cancelled
            return count == 5 && cancelled.contains(3)
        }
        try check(await reader.scopes[4].isEmpty, "empty selection is passed as an empty directory scope")
        await reader.resolve(4, try fixture("empty", used: 30, empty: true))
        try await waitFor { !store.state.isRefreshing }
        let empty = store.state.accountingPresentation
        await reader.resolve(3, try fixture("removed-late-b", todayTokens: 88_000, used: 88))
        try await Task.sleep(for: .milliseconds(20))
        try check(store.state.accountingPresentation == empty && empty.sourceFolderCount == 0
                  && empty.today.tokens == nil && empty.cycle.apiUSD == nil && store.state.remaining == 70,
                  "a removed source's late response cannot overwrite the completed empty-scope result")
        store.clearAccountingFolders()
        await Task.yield()
        try check(await reader.scopes.count == 5, "clearing an already-empty selection causes no duplicate query")
    }

    static func isolatedPersistence() async throws {
        let suite = "local.codexusage.tests.accounting." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        preferences.removePersistentDomain(forName: suite)
        defer { preferences.removePersistentDomain(forName: suite); preferences.synchronize() }
        preferences.set(5, forKey: "billingRenewalDay")
        preferences.set([String](), forKey: "accountingFolders")
        preferences.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        let reader = ControlledDashboardReader(), clock = AccountingTestClock(), scheduler = AccountingTestScheduler()
        let store = UsageStore(connection: reader, monitor: nil, scheduler: scheduler, preferences: preferences,
                               startImmediately: false, uptime: { clock.value })
        defer { store.stop() }
        try check(store.state.accountingPresentation.billingDay == 5 && store.state.language == .english,
                  "an isolated preference suite restores renewal day and language without querying")
        let expectedStart = AccountingCalendar(renewalDay: nil).today(containing: .now).start
        try check(preferences.double(forKey: "accountingTrackingStart") == expectedStart.timeIntervalSince1970 &&
                  store.state.accountingPresentation.trackingStartedAt == expectedStart,
                  "first launch persists today's local midnight before any query or app termination")
        let reset = Date.now.addingTimeInterval(3_600)
        store.setAccountingFolders([folderA, folderA + "/../synthetic-accounting-project-a", "relative-invalid"])
        try await waitFor { await reader.scopes.count == 1 }
        try check(await reader.scopes[0] == [folderA], "scope preferences deduplicate normalized absolute paths")
        try check(await reader.trackingStarts[0] == expectedStart,
                  "the query receives the same persisted prospective cutoff as the presentation")
        await reader.resolve(0, try fixture("persist", used: 80, reset: reset))
        try await waitFor { !store.state.isRefreshing }
        clock.value += 6
        store.refresh()
        try await waitFor { await reader.scopes.count == 2 }
        let advanced = reset.addingTimeInterval(7 * 86400)
        await reader.resolve(1, try fixture("persist", used: 1, reset: advanced))
        try await waitFor { !store.state.isRefreshing }
        store.setBillingDay(17)
        store.toggleLanguage()
        try check(await reader.scopes.count == 2, "persisting settings does not requery existing accounting")
        store.stop()
        preferences.synchronize()
        let reopened = UserDefaults(suiteName: suite)!
        try check(reopened.integer(forKey: "billingRenewalDay") == 17
                  && reopened.stringArray(forKey: "accountingFolders") == [folderA]
                  && reopened.string(forKey: AppLanguage.preferenceKey) == AppLanguage.chinese.rawValue,
                  "settings round-trip through a fresh instance of the isolated suite")
        guard let data = reopened.data(forKey: "resetObservation") else {
            throw AccountingStoreFailure(description: "Reset observation was not persisted on stop")
        }
        let saved = try JSONDecoder().decode(AccountingResetTracker.self, from: data)
        try check(saved.accountID == "synthetic-store-account" && saved.resetLowerBound != nil
                  && saved.resetUpperBound != nil && saved.resetLowerBound! < saved.resetUpperBound!,
                  "stop persists the synthetic observed reset interval with account identity")
        let secondReader = ControlledDashboardReader(), secondScheduler = AccountingTestScheduler()
        let second = UsageStore(connection: secondReader, monitor: nil, scheduler: secondScheduler, preferences: reopened,
                                startImmediately: false, uptime: { clock.value })
        defer { second.stop() }
        try check(second.state.accountingPresentation.billingDay == 17
                  && second.state.accountingPresentation.sourceFolderCount == 1 && second.state.language == .chinese,
                  "a new Store restores persisted settings without carrying old displayed records")
        try check(second.state.accountingPresentation.trackingStartedAt == expectedStart &&
                  reopened.double(forKey: "accountingTrackingStart") == expectedStart.timeIntervalSince1970,
                  "reopening preserves the initial tracking date instead of starting over")
        second.refresh()
        try await waitFor { await secondReader.scopes.count == 1 }
        await secondReader.resolve(0, try fixture("restored", used: 2, reset: advanced))
        try await waitFor { !second.state.isRefreshing }
        try check(second.state.accountingPresentation.lastReset == saved.resetUpperBound,
                  "a same-account refresh preserves the restored observed reset boundary")
        second.clearAccountingFolders()
        // The refresh cooldown queues the empty-scope read; stopping cancels that timer.
        second.setBillingDay(0)
        second.stop()
        try check(reopened.integer(forKey: "billingRenewalDay") == 0
                  && reopened.stringArray(forKey: "accountingFolders") == [],
                  "cleared billing day and source selection are persisted")
        preferences.removePersistentDomain(forName: suite)
        preferences.synchronize()
        try check(preferences.persistentDomain(forName: suite)?.isEmpty ?? true,
                  "temporary preference domain contains no values after cleanup")
    }

    static func quitAfterScopeCancellation() async throws {
        let reader = ControlledDashboardReader(), clock = AccountingTestClock(), scheduler = AccountingTestScheduler()
        let store = UsageStore(connection: reader, monitor: nil, scheduler: scheduler, preferences: nil,
                               startImmediately: false, uptime: { clock.value })
        store.setAccountingFolders([folderA])
        try await waitFor { await reader.scopes.count == 1 }
        store.setAccountingFolders([folderB])
        let cleanup = store.stop()
        try check(cleanup != nil, "quit retains cleanup for a query already cancelled by a scope change")
        var finished = false
        let waiting = Task { await cleanup?.value; finished = true }
        try await Task.sleep(for: .milliseconds(20))
        try check(!finished, "termination waits for the cancelled reader instead of orphaning its process")
        await reader.resolve(0, try fixture("retired"))
        await waiting.value
        try check(finished && store.state.accountingPresentation.conversations.isEmpty,
                  "retired query cleanup finishes without restoring removed records")
    }

    static func earlierTrackingStartSurvivesRelaunch() throws {
        let suite = "local.codexusage.tests.tracking." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); preferences.synchronize() }
        let earlier = AccountingCalendar(renewalDay: nil).today(containing: .now).start.addingTimeInterval(-3 * 86_400)
        preferences.set(earlier.timeIntervalSince1970, forKey: "accountingTrackingStart")
        let store = UsageStore(connection: ControlledDashboardReader(), monitor: nil,
                               scheduler: AccountingTestScheduler(), preferences: preferences, startImmediately: false)
        try check(store.state.accountingPresentation.trackingStartedAt == earlier,
                  "a launch on a later day retains the original tracking start")
        store.stop()
        preferences.set(Date.now.addingTimeInterval(86_400).timeIntervalSince1970, forKey: "accountingTrackingStart")
        let repaired = UsageStore(connection: ControlledDashboardReader(), monitor: nil,
                                  scheduler: AccountingTestScheduler(), preferences: preferences, startImmediately: false)
        try check(repaired.state.accountingPresentation.trackingStartedAt == AccountingCalendar(renewalDay: nil).today(containing: .now).start,
                  "a corrupt future tracking date is repaired instead of suppressing new records")
        repaired.stop()
    }

    static func main() async throws {
        try await billingAndLanguage()
        try await replaceAndClearScopes()
        try await isolatedPersistence()
        try earlierTrackingStartSurvivesRelaunch()
        try await quitAfterScopeCancellation()
        print("\(checked) accounting Store checks passed.")
    }
}
