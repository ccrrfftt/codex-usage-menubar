import AppKit
import Combine
import SwiftUI

// Interactive acceptance harness. Production UI, state, scheduling and pricing
// are used unchanged. This reader never opens a file or creates CodexConnection.
private enum FixtureScenario: String, CaseIterable, Identifiable, Sendable {
    case below, equal, above, lowQuota, boundaryQuota, partial, legacy, unknownPrice, serviceDates, unavailable, failure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .below: "Complete · $150"
        case .equal: "Exactly $200"
        case .above: "Above · $250"
        case .lowQuota: "14.9% · red"
        case .boundaryQuota: "15% · ordinary"
        case .partial: "Partial records"
        case .legacy: "Legacy estimate"
        case .unknownPrice: "Unknown pricing"
        case .serviceDates: "Service-only omitted"
        case .unavailable: "Unavailable"
        case .failure: "Read failure → stale"
        }
    }
    var expected: String {
        switch self {
        case .below: "$150.00; center !; ordinary quota color."
        case .equal: "$200.00; no center !."
        case .above: "$250.00; no center !."
        case .lowQuota: "14.9% in red; $150.00 with center !."
        case .boundaryQuota: "Exactly 15% uses the ordinary color; center ! remains."
        case .partial: "Known totals use ≥; comparison unavailable."
        case .legacy: "Historical estimates use ≈ and a price range; no center !."
        case .unknownPrice: "Tokens remain available; USD shows —."
        case .serviceDates: "Account date/lifetime buckets are excluded; local prospective totals remain —."
        case .unavailable: "Unavailable values show —, never a fabricated zero."
        case .failure: "The last successful values remain and show a stale/error state."
        }
    }
}

@MainActor
private final class FixtureClock {
    private var offset: TimeInterval = 0
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime + offset }
    func advancePastCooldown() { offset += 6 }
}

@MainActor
private final class SyntheticDashboardReader: DashboardReading {
    static let accountID = "qa-synthetic-account"
    let anchor: Date
    var scenario = FixtureScenario.below
    private(set) var reads = 0

    init(anchor: Date) { self.anchor = anchor }

    var weeklyReset: Date { anchor.addingTimeInterval(7 * 86_400) }

    func seedResetObservation() -> AccountingResetTracker {
        var tracker = AccountingResetTracker()
        tracker.observe(accountID: Self.accountID,
                        window: QuotaWindow(usedPercent: 80, windowDurationMins: 10_080,
                                            resetsAt: anchor.addingTimeInterval(3 * 86_400).timeIntervalSince1970),
                        at: anchor.addingTimeInterval(-8 * 3_600))
        tracker.observe(accountID: Self.accountID,
                        window: QuotaWindow(usedPercent: 15, windowDurationMins: 10_080,
                                            resetsAt: weeklyReset.timeIntervalSince1970),
                        at: anchor.addingTimeInterval(-6 * 3_600))
        return tracker
    }

    func read() async throws -> QuotaSnapshot { try quota() }

    func readDashboard(allowedWorkingDirectories: [String]) async throws -> DashboardSnapshot {
        try Task.checkCancellation()
        reads += 1
        if scenario == .failure { throw QuotaError.timedOut }
        let quota = try quota()
        // The actual strings are deliberately ignored; no selected directory is read.
        guard !allowedWorkingDirectories.isEmpty else {
            return DashboardSnapshot(quota: quota, accounting: emptyAccounting(issues: [.scopeRequired]))
        }
        if scenario == .unavailable {
            return DashboardSnapshot(quota: quota, accounting: emptyAccounting(issues: [.rolloutUnavailable]))
        }
        if scenario == .serviceDates {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let account = AccountTokenActivity(
                summary: AccountTokenSummary(lifetimeTokens: 1_200_000, peakDailyTokens: 1_200_000,
                    longestRunningTurnSec: nil, currentStreakDays: nil, longestStreakDays: nil),
                dailyUsageBuckets: [AccountDailyUsageBucket(startDate: formatter.string(from: anchor), tokens: 1_200_000)],
                threadUsage: nil)
            return DashboardSnapshot(quota: quota, accounting: AccountingSnapshot(observedAt: anchor,
                account: account, recentThreads: [], records: [], issues: [.rolloutUnavailable],
                scannedThreadCount: 0, recordsAreComplete: false))
        }
        let records = makeRecords()
        let issues: Set<AccountingIssue> = scenario == .partial ? [.rolloutUnavailable]
            : (scenario == .legacy ? [.estimatedUsage] : [])
        let names = ["QA · Menu panel", "QA · Pricing boundary",
                     "QA · Long synthetic conversation title for truncation"]
        let threads = names.enumerated().map { index, title in
            AccountingThread(id: "qa-thread-\(index)", name: title,
                             updatedAt: anchor.addingTimeInterval(-Double(index * 60)),
                             recencyAt: anchor.addingTimeInterval(-Double(index * 60)), usage: nil)
        }
        let snapshot = AccountingSnapshot(observedAt: anchor, account: nil, recentThreads: threads,
            records: records, issues: issues, scannedThreadCount: threads.count,
            recordsAreComplete: scenario != .partial)
        return DashboardSnapshot(quota: quota, accounting: snapshot)
    }

    private func emptyAccounting(issues: Set<AccountingIssue>) -> AccountingSnapshot {
        AccountingSnapshot(observedAt: anchor, account: nil, recentThreads: [], records: [],
                           issues: issues, scannedThreadCount: 0, recordsAreComplete: false)
    }

    private func quota() throws -> QuotaSnapshot {
        let remaining: Double = scenario == .lowQuota ? 14.9 : (scenario == .boundaryQuota ? 15 : 72)
        var primary: [String: Any] = ["windowDurationMins": 300,
            "resetsAt": anchor.addingTimeInterval(5 * 3_600).timeIntervalSince1970]
        var secondary: [String: Any] = ["windowDurationMins": 10_080,
            "resetsAt": weeklyReset.timeIntervalSince1970]
        if scenario != .unavailable {
            primary["usedPercent"] = 100 - remaining
            secondary["usedPercent"] = 15
        }
        let object: [String: Any] = [
            "accountId": Self.accountID, "ordinaryUsageAllowed": true,
            "rateLimitsByLimitId": [
                "codex": ["planType": "qa", "primary": primary, "secondary": secondary],
                "qa-review": ["limitName": "QA Review", "primary": ["usedPercent": 32,
                    "windowDurationMins": 10_080, "resetsAt": weeklyReset.timeIntervalSince1970]],
                "qa-extra": ["limitName": "QA Extra", "primary": ["usedPercent": 10,
                    "windowDurationMins": 1_440, "resetsAt": anchor.addingTimeInterval(86_400).timeIntervalSince1970]]
            ],
            "rateLimitResetCredits": ["availableCount": 2, "credits": [
                ["status": "available", "expiresAt": anchor.addingTimeInterval(10 * 86_400).timeIntervalSince1970],
                ["status": "available", "expiresAt": anchor.addingTimeInterval(25 * 86_400).timeIntervalSince1970]
            ]]
        ]
        return try JSONDecoder().decode(QuotaSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func makeRecords() -> [AccountingUsageRecord] {
        let astraCount = scenario == .above ? 100 : 50
        let solCount = scenario == .equal ? 100 : 50
        let calendar = AccountingCalendar(renewalDay: 5)
        let cycleStart = calendar.subscriptionCycle(containing: anchor)!.start
        let todayStart = calendar.today(containing: anchor).start
        let timestamps = [
            cycleStart.addingTimeInterval(min(3_600, anchor.timeIntervalSince(cycleStart) / 4)),
            max(cycleStart, anchor.addingTimeInterval(-9 * 3_600)),
            max(cycleStart, anchor.addingTimeInterval(-2 * 3_600)),
            todayStart.addingTimeInterval(anchor.timeIntervalSince(todayStart) / 2)
        ]
        return (0..<(astraCount + solCount)).map { index in
            let astra = index < astraCount
            let model = scenario == .unknownPrice ? "qa-unknown-model" : (astra ? "gpt-6-astra" : "gpt-6.1-sol")
            let output: Int64 = astra ? 20_000 : 80_000
            return AccountingUsageRecord(id: "qa-record-\(index)", threadID: "qa-thread-\(index % 3)",
                timestamp: timestamps[index % timestamps.count], model: model, serviceTier: "standard",
                inputTokens: 100_000, cachedInputTokens: 0, cacheWriteInputTokens: 0,
                outputTokens: output, reasoningOutputTokens: 5_000, totalTokens: 100_000 + output,
                quality: scenario == .legacy ? .estimated : .reported)
        }
    }
}

@MainActor
private final class FixtureController: ObservableObject {
    static let preferenceDomain = "local.codexusage.acceptance"
    @Published private(set) var selected = FixtureScenario.below
    let store: UsageStore
    let reader: SyntheticDashboardReader
    let sourcesRoot: URL
    private let clock: FixtureClock
    private(set) var status: StatusItemController?

    init() throws {
        let reader = SyntheticDashboardReader(anchor: .now)
        self.reader = reader
        let clock = FixtureClock()
        self.clock = clock
        sourcesRoot = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Synthetic Sources", isDirectory: true)
        let firstSource = sourcesRoot.appendingPathComponent("Project A", isDirectory: true)
        // Only directories owned by this QA bundle are created.
        for name in ["Project A", "Project B"] {
            try FileManager.default.createDirectory(at: sourcesRoot.appendingPathComponent(name, isDirectory: true),
                                                    withIntermediateDirectories: true)
        }
        guard let preferences = UserDefaults(suiteName: Self.preferenceDomain) else { throw CocoaError(.fileWriteUnknown) }
        if !preferences.bool(forKey: "fixtureInitialized") {
            preferences.set(5, forKey: "billingRenewalDay")
            preferences.set([firstSource.path], forKey: "accountingFolders")
            preferences.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.preferenceKey)
            preferences.set(true, forKey: "fixtureInitialized")
        }
        // Only this isolated synthetic fixture starts at the cycle boundary so
        // the $150/$200/$250 comparison scenarios cover a complete cycle.
        let trackingStart = AccountingCalendar(renewalDay: 5).subscriptionCycle(containing: reader.anchor)!.start
        preferences.set(trackingStart.timeIntervalSince1970, forKey: "accountingTrackingStart")
        // A synthetic observed interval is loaded through the production preference path.
        // Date/language/source settings remain unchanged on later QA launches.
        preferences.set(try JSONEncoder().encode(reader.seedResetObservation()), forKey: "resetObservation")
        store = UsageStore(connection: reader, monitor: nil, scheduler: RefreshScheduler(),
                           preferences: preferences, startImmediately: false, uptime: { clock.uptime })
        status = StatusItemController(store: store)
    }

    func select(_ scenario: FixtureScenario) {
        selected = scenario
        reader.scenario = scenario
        refresh()
    }

    func refresh() {
        clock.advancePastCooldown()
        store.refresh()
    }

    func setNetwork(_ available: Bool) {
        clock.advancePastCooldown()
        var energy = store.state.energy
        energy.networkAvailable = available
        store.updateSystemState(energy)
        if available { store.refresh() }
    }

    func setBattery(_ onBattery: Bool) {
        clock.advancePastCooldown()
        var energy = store.state.energy
        energy.onBattery = onBattery
        store.updateSystemState(energy)
        store.refresh()
    }

    func restoreQADefaults() {
        clock.advancePastCooldown()
        store.setBillingDay(5)
        store.setAccountingFolders([sourcesRoot.appendingPathComponent("Project A").path])
        if store.state.language != .chinese { store.toggleLanguage() }
        select(.below)
    }

    func openPanel() { status?.showPopover() }
}

private struct FixtureControls: View {
    @ObservedObject var controller: FixtureController
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex Usage QA").font(.system(size: 17, weight: .semibold))
            Text("Production UI · synthetic inputs only")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(FixtureScenario.allCases) { scenario in
                    Button(scenario.title) { controller.select(scenario) }
                        .frame(maxWidth: .infinity)
                        .tint(controller.selected == scenario ? .accentColor : .secondary)
                }
            }
            .controlSize(.small).disabled(store.state.isRefreshing)
            Text(controller.selected.expected)
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 30, alignment: .topLeading)
            Divider()
            HStack {
                Button("Offline") { controller.setNetwork(false) }
                Button("Online") { controller.setNetwork(true) }
                Spacer()
                Text(store.state.energy.networkAvailable ? "Online" : "Offline").foregroundStyle(.secondary)
            }
            HStack {
                Button("AC power") { controller.setBattery(false) }
                Button("Battery") { controller.setBattery(true) }
                Spacer()
                Text(store.state.energy.onBattery ? "5-minute cadence" : "1-minute cadence").foregroundStyle(.secondary)
            }
            .disabled(store.state.isRefreshing)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow { Text("Menu quota"); Text(store.state.statusItem.title).monospacedDigit() }
                GridRow { Text("Cycle API value"); Text(store.state.statusItem.valueTitle).monospacedDigit() }
                GridRow { Text("Fixture reads"); Text("\(controller.reader.reads)").monospacedDigit() }
                GridRow { Text("Status"); Text(store.state.status).lineLimit(2) }
            }.font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Open menu panel") { controller.openPanel() }
                Spacer()
                Button("Advance + refresh") { controller.refresh() }.disabled(store.state.isRefreshing)
            }
            HStack {
                Button("Restore QA defaults") { controller.restoreQADefaults() }
                Spacer()
                Button("Quit QA") { NSApp.terminate(nil) }
            }.controlSize(.small)
            Text("Use the real panel for language, disclosures, billing day, source selection and quit. No account or conversation history is read.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 420, alignment: .leading)
    }
}

@MainActor
private final class FixtureApplicationDelegate: NSObject, NSApplicationDelegate {
    private var controller: FixtureController?
    private var window: NSWindow?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let controller = try FixtureController()
            self.controller = controller
            let content = NSHostingView(rootView: FixtureControls(controller: controller, store: controller.store))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: content.fittingSize),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Codex Usage QA — Synthetic fixtures"
            window.identifier = NSUserInterfaceItemIdentifier("codex-usage-qa-controls")
            window.contentView = content
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            controller.select(.below)
        } catch {
            let alert = NSAlert()
            alert.messageText = "QA fixture setup failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        guard let pending = controller?.store.stop() else { return .terminateNow }
        terminating = true
        Task { await pending.value; sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.store.stop() }
}

@main @MainActor
private struct UIAcceptanceFixture {
    static func main() {
        let app = NSApplication.shared
        let delegate = FixtureApplicationDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
