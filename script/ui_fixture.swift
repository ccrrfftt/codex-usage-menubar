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
        case .below: "$150; center !; ordinary quota color."
        case .equal: "$200; no center !."
        case .above: "$250; no center !."
        case .lowQuota: "14% (raw 14.9%) in red; $150 with center !."
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
    private var selfTester: NativeFixtureSelfTest?

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
            if let index = CommandLine.arguments.firstIndex(of: "--self-test"),
               CommandLine.arguments.indices.contains(index + 1) {
                let tester = NativeFixtureSelfTest(controller: controller, controls: window,
                    output: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
                selfTester = tester
                Task { await tester.run() }
            }
        } catch {
            if CommandLine.arguments.contains("--self-test") {
                FileHandle.standardError.write(Data("QA setup failed: \(error.localizedDescription)\n".utf8))
                NSApp.terminate(nil)
                return
            }
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

/// Bounded, opt-in native verification within this QA process. This does not use
/// AXUIElement, System Events, screen recording, or another app's accessibility tree.
@MainActor
private final class NativeFixtureSelfTest {
    private let controller: FixtureController
    private let controls: NSWindow
    private let output: URL
    private var checks: [[String: String]] = []
    private var captures: [String] = []
    private var finished = false

    init(controller: FixtureController, controls: NSWindow, output: URL) {
        self.controller = controller
        self.controls = controls
        self.output = output
    }

    func run() async {
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(40))
            guard !Task.isCancelled, let self, !self.finished else { return }
            self.record("Bounded runtime", "fail", "40-second timeout")
            self.finish()
            NSApp.terminate(nil)
        }
        defer { watchdog.cancel() }
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        await settle()
        controller.restoreQADefaults()
        controller.setNetwork(true)
        controller.setBattery(false)
        await settle()
        check("Native startup", NSApp.activationPolicy() == .accessory && controls.isVisible,
              "Own accessory app and control window are running")
        check("Synthetic pricing path", controller.store.state.accountingPresentation.cycle.apiUSD == 150,
              "Production summary and pricing computed $150 from synthetic records")
        capture(controls.contentView, "01-qa-controls.png")

        if let button = statusButton() {
            button.performClick(nil)
            record("Status item action", "pass", "Invoked the actual NSStatusBarButton")
        } else {
            record("Status item action", "limitation", "Status button not present in own NSApp window hierarchy")
            _ = press("Open menu panel", in: controls, name: "QA panel action")
        }
        await settle()
        guard let panel = mainPanel() else {
            record("Native popover", "fail", "No visible production popover after open action")
            dumpTree(controls, file: "controls-accessibility.txt")
            finish(); NSApp.terminate(nil); return
        }
        check("Native popover", panel.isVisible, "Production NSPopover is visible")
        capture(panel.contentView, "02-panel-collapsed-zh.png")
        dumpTree(panel, file: "panel-accessibility.txt")

        let changedLanguage = press("Switch to English", in: panel, name: "Language button")
        await settle()
        if changedLanguage {
            check("Language result", controller.store.state.language == .english, "Actual panel action switched to English")
            let stored = UserDefaults(suiteName: FixtureController.preferenceDomain)?.string(forKey: AppLanguage.preferenceKey)
            check("Language persistence", stored == AppLanguage.english.rawValue, "English written only to QA preference suite")
        }
        let lang = controller.store.state.language
        let before = panel.frame
        if let row = element(lang.accountingText(.recentConversations), in: panel) {
            check("Conversation whole-row target", row.accessibilityFrame().width >= panel.frame.width - 60,
                  "Native button accessibility width \(row.accessibilityFrame().width) pt")
        }
        if press(lang.accountingText(.recentConversations), in: panel, name: "Conversation disclosure") {
            await settle()
            check("Conversation expansion", panel.frame.height > before.height + 20,
                  "Height before \(before.height), after \(panel.frame.height)")
            check("Conversation top anchor", abs(panel.frame.maxY - before.maxY) <= 1.5,
                  "Top delta \(panel.frame.maxY - before.maxY) pt")
        }
        let beforeOthers = panel.frame
        if let row = element(lang.text(.otherLimits), in: panel) {
            check("Other limits whole-row target", row.accessibilityFrame().width >= panel.frame.width - 60,
                  "Native button accessibility width \(row.accessibilityFrame().width) pt")
        }
        if press(lang.text(.otherLimits), in: panel, name: "Other limits disclosure") {
            await settle()
            check("Other limits expansion", panel.frame.height > beforeOthers.height + 20,
                  "Height before \(beforeOthers.height), after \(panel.frame.height)")
            check("Other limits top anchor", abs(panel.frame.maxY - beforeOthers.maxY) <= 1.5,
                  "Top delta \(panel.frame.maxY - beforeOthers.maxY) pt")
        }
        if let footer = element(lang.text(.quit), in: panel) {
            let frame = footer.accessibilityFrame()
            if frame.width > 0 && frame.height > 0 {
                check("Footer visibility", panel.frame.insetBy(dx: -1, dy: -1).contains(frame),
                      "Quit control frame is inside the expanded popover")
            } else { record("Footer visibility", "limitation", "Native accessibility returned an empty footer frame") }
        } else { record("Footer visibility", "limitation", "Quit control not exposed to in-process accessibility") }
        capture(panel.contentView, "03-panel-expanded.png")

        if press(lang.accountingText(.settings), in: panel, name: "Settings action") {
            await settle()
            if let settings = settingsPanel(excluding: panel) {
                capture(settings.contentView, "04-settings.png")
                if let picker = views(in: settings).compactMap({ $0 as? NSPopUpButton }).first {
                    let day = lang.accountingDay(6)
                    if let action = picker.action, picker.indexOfItem(withTitle: day) >= 0 {
                        picker.selectItem(withTitle: day)
                        _ = NSApp.sendAction(action, to: picker.target, from: picker)
                        await settle()
                        check("Billing picker action", controller.store.state.accountingPresentation.billingDay == 6,
                              "Selected day 6 through the real NSPopUpButton action")
                        picker.selectItem(withTitle: lang.accountingDay(5))
                        _ = NSApp.sendAction(action, to: picker.target, from: picker)
                        await settle()
                    } else { record("Billing picker action", "limitation", "Native menu item titles not exposed as expected") }
                } else { record("Billing picker action", "limitation", "SwiftUI picker is not an NSPopUpButton in the native subview tree") }
                if press(lang.accountingText(.chooseFolders), in: settings, name: "Source picker action") {
                    await settle()
                    if let chooser = NSApp.windows.compactMap({ $0 as? NSOpenPanel }).first(where: \.isVisible) {
                        let expected = controller.sourcesRoot.appendingPathComponent("Project A").standardizedFileURL
                        check("Source picker scope", chooser.directoryURL?.standardizedFileURL == expected,
                              "Native folder picker starts at the synthetic selected root; no picker content captured")
                        chooser.cancel(nil)
                        await settle()
                    } else { record("Source picker scope", "limitation", "No visible NSOpenPanel found after the action") }
                }
                if settings.isVisible && press(lang.accountingText(.clearSources), in: settings, name: "Clear source action") {
                    await settle()
                    check("Cleared source result", controller.store.state.accountingPresentation.sourceFolderCount == 0,
                          "Actual settings button cleared only QA sources")
                }
                _ = press(lang.accountingText(.settings), in: panel, name: "Close settings action")
                await settle()
            } else { record("Settings native window", "limitation", "Settings window not separately discoverable") }
        }

        controller.restoreQADefaults()
        await settle()
        for scenario in [FixtureScenario.equal, .above, .lowQuota, .boundaryQuota, .partial, .legacy, .unknownPrice, .unavailable] {
            let usedControl = press(scenario.title, in: controls, name: "Scenario: \(scenario.rawValue)")
            if !usedControl { controller.select(scenario) }
            await settle()
            let state = controller.store.state
            let value = state.accountingPresentation.cycle
            let condition: Bool
            switch scenario {
            case .equal: condition = value.apiUSD == 200 && !state.statusItem.ring.showsValueWarning
            case .above: condition = value.apiUSD == 250 && !state.statusItem.ring.showsValueWarning
            case .lowQuota: condition = state.statusItem.ring.isLow && state.statusItem.ring.showsValueWarning
            case .boundaryQuota: condition = !state.statusItem.ring.isLow && state.statusItem.ring.showsValueWarning
            case .partial: condition = value.costIsPartial && !state.statusItem.ring.showsValueWarning
            case .legacy: condition = value.isEstimated && !state.statusItem.ring.showsValueWarning
            case .unknownPrice: condition = value.tokens != nil && value.apiUSD == nil
            case .unavailable: condition = state.remaining == nil && value.apiUSD == nil
            default: condition = false
            }
            check("Runtime state: \(scenario.rawValue)", condition,
                  "Value \(state.statusItem.valueTitle), low \(state.statusItem.ring.isLow), mark \(state.statusItem.ring.showsValueWarning)")
            if let label = viewsInOwnWindows().compactMap({ $0 as? StatusItemLabel }).first {
                check("Native label state: \(scenario.rawValue)", label.state == state.statusItem,
                      "Actual status view received the production store state")
            }
            if scenario == .lowQuota || scenario == .boundaryQuota {
                capture(statusButton(), "05-status-\(scenario.rawValue).png")
            }
        }
        controller.select(.below); await settle()
        let previous = controller.store.state.updatedAt
        if !press(FixtureScenario.failure.title, in: controls, name: "Failure action") { controller.select(.failure) }
        await settle()
        check("Failure retains stale values", controller.store.state.lastError != nil
                && controller.store.state.updatedAt == previous
                && controller.store.state.accountingPresentation.cycle.apiUSD == 150,
              "Last successful synthetic totals retained with error state")
        if !press("Offline", in: controls, name: "Offline action") { controller.setNetwork(false) }
        await settle()
        let reads = controller.reader.reads
        controller.select(.below); await settle()
        check("Offline suppresses query", !controller.store.state.energy.networkAvailable && controller.reader.reads == reads,
              "A normal store refresh did not call the synthetic reader while offline")
        if !press("Online", in: controls, name: "Online action") { controller.setNetwork(true) }
        await settle()
        check("Online recovery", controller.store.state.lastError == nil && controller.reader.reads > reads,
              "Normal state transition resumed reads and cleared the old error")
        if !press("Battery", in: controls, name: "Battery action") { controller.setBattery(true) }
        await settle()
        check("Battery cadence", EnergyPolicy.refreshInterval(state: controller.store.state.energy) == 300, "Production cadence is five minutes")
        if !press("AC power", in: controls, name: "AC action") { controller.setBattery(false) }
        await settle()
        check("AC cadence", EnergyPolicy.refreshInterval(state: controller.store.state.energy) == 60, "Production cadence is one minute")
        controller.openPanel(); await settle()
        if let finalPanel = mainPanel() {
            let finalLanguage = controller.store.state.language
            let beforeRefresh = controller.reader.reads
            if press(finalLanguage.text(.refresh), in: finalPanel, name: "Production refresh action") {
                try? await Task.sleep(for: .seconds(5.3))
                check("Production refresh result", controller.reader.reads > beforeRefresh,
                      "Actual panel button completed through the existing cooldown/scheduler")
            }
            capture(finalPanel.contentView, "06-panel-final.png")
            record("Quit action", "info", "Report written before dispatching the real panel quit action; runner verifies process exit")
            finish()
            if !press(finalLanguage.text(.quit), in: finalPanel, name: "Production quit dispatch") { NSApp.terminate(nil) }
            Task { try? await Task.sleep(for: .seconds(1)); NSApp.terminate(nil) }
        } else { finish(); NSApp.terminate(nil) }
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(250)) }

    private func record(_ name: String, _ status: String, _ detail: String) {
        checks.append(["name": name, "status": status, "detail": detail])
        let text = checks.map { "\($0["status"]!) · \($0["name"]!) · \($0["detail"]!)" }.joined(separator: "\n")
        try? text.write(to: output.appendingPathComponent("progress.txt"), atomically: true, encoding: .utf8)
    }
    private func check(_ name: String, _ passed: Bool, _ detail: String) { record(name, passed ? "pass" : "fail", detail) }

    private func finish() {
        guard !finished else { return }
        finished = true
        let report: [String: Any] = ["mode": "native-in-process", "computerToolUsed": false,
            "scope": "Own synthetic QA process only", "checks": checks, "captures": captures,
            "limitations": "No external Computer tool, physical pointer/keyboard, VoiceOver audit, or real account data was used."]
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: output.appendingPathComponent("result.json"))
        }
        let text = checks.map { "\($0["status"]!.uppercased()) · \($0["name"]!) · \($0["detail"]!)" }.joined(separator: "\n")
        try? text.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }

    private func views(in window: NSWindow) -> [NSView] {
        guard let root = window.contentView else { return [] }
        func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
        return walk(root)
    }
    private func viewsInOwnWindows() -> [NSView] { NSApp.windows.filter { !($0 is NSOpenPanel) }.flatMap(views) }
    private func statusButton() -> NSStatusBarButton? { viewsInOwnWindows().compactMap { $0 as? NSStatusBarButton }.first }
    private func mainPanel() -> NSWindow? {
        NSApp.windows.filter { $0 !== controls && !($0 is NSOpenPanel) && $0.isVisible
            && $0.frame.width >= 300 && $0.frame.width < 390 && $0.frame.height > 250 }
            .max { $0.frame.height < $1.frame.height }
    }
    private func settingsPanel(excluding panel: NSWindow) -> NSWindow? {
        NSApp.windows.first { $0 !== controls && $0 !== panel && !($0 is NSOpenPanel) && $0.isVisible
            && $0.frame.width > 200 && element(controller.store.state.language.accountingText(.chooseFolders), in: $0) != nil }
    }
    private func elements(in window: NSWindow) -> [any NSAccessibilityProtocol] {
        var result: [any NSAccessibilityProtocol] = []
        var visited = Set<ObjectIdentifier>()
        func walk(_ object: Any, depth: Int) {
            guard depth < 24, result.count < 800, let element = object as? any NSAccessibilityProtocol else { return }
            let id = ObjectIdentifier(element as AnyObject)
            guard visited.insert(id).inserted else { return }
            result.append(element)
            for child in element.accessibilityChildren() ?? [] { walk(child, depth: depth + 1) }
        }
        walk(window, depth: 0)
        if let root = window.contentView { walk(root, depth: 0) }
        return result
    }
    private func text(of element: any NSAccessibilityProtocol) -> String {
        [element.accessibilityLabel(), element.accessibilityTitle(), element.accessibilityValue() as? String]
            .compactMap { $0 }.joined(separator: " | ")
    }
    private func element(_ label: String, in window: NSWindow) -> (any NSAccessibilityProtocol)? {
        elements(in: window).first { $0.accessibilityRole() == .button && text(of: $0).contains(label) }
    }
    private func press(_ label: String, in window: NSWindow, name: String) -> Bool {
        guard let element = element(label, in: window) else {
            if window !== controls, window.frame.width >= 300, window.frame.width < 390,
               let view = window.contentView {
                let point: NSPoint?
                // These locations are from the inspected native fixture capture.
                // Disclosure clicks deliberately target the blank trailing part of the row.
                switch label {
                case "Switch to English", "切换为中文": point = NSPoint(x: view.bounds.width - 56, y: 20)
                case "最近 3 个对话", "Last 3 conversations": point = NSPoint(x: view.bounds.width * 0.75, y: view.bounds.height - 110.5)
                case "其他额度", "Other limits": point = NSPoint(x: view.bounds.width * 0.75, y: view.bounds.height - 62)
                case "刷新", "Refresh": point = NSPoint(x: 42, y: view.bounds.height - 20)
                case "退出应用", "Quit": point = NSPoint(x: view.bounds.width - 18, y: view.bounds.height - 20)
                default: point = nil
                }
                if let point, postClick(point, in: view, window: window) {
                    record(name, "pass", "Posted own-window mouse down/up at inspected content point \(point.x),\(point.y); result checked separately")
                    return true
                }
            }
            record(name, "limitation", "Control not exposed in own native accessibility tree: \(label)"); return false
        }
        let success = element.accessibilityPerformPress()
        record(name, success ? "pass" : "limitation", "Native accessibilityPerformPress: \(label)")
        return success
    }
    private func postClick(_ topPoint: NSPoint, in view: NSView, window: NSWindow) -> Bool {
        let point = NSPoint(x: topPoint.x, y: view.isFlipped ? topPoint.y : view.bounds.height - topPoint.y)
        let location = view.convert(point, to: nil)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { return false }
        NSApp.postEvent(up, atStart: true)
        NSApp.postEvent(down, atStart: true)
        return true
    }
    private func capture(_ view: NSView?, _ filename: String) {
        guard let view, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            record("Capture \(filename)", "limitation", "Own native view did not provide a bitmap"); return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // Native cached content is transparent. Composite only this owned view
        // against its native appearance background, without capturing the desktop.
        guard let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide,
            pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: opaque) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(bitmap.pixelsWide) / view.bounds.width,
                                 y: CGFloat(bitmap.pixelsHigh) / view.bounds.height)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: view.bounds.size).fill()
            if let image = bitmap.cgImage {
                context.cgContext.setBlendMode(.normal)
                context.cgContext.draw(image, in: NSRect(origin: .zero, size: view.bounds.size))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = opaque.representation(using: .png, properties: [:]) else { return }
        do { try data.write(to: output.appendingPathComponent(filename)); captures.append(filename) }
        catch { record("Capture \(filename)", "fail", "Could not save native bitmap") }
    }
    private func dumpTree(_ window: NSWindow, file: String) {
        let tree = elements(in: window).map { "\($0.accessibilityRole()?.rawValue ?? "unknown") | \(text(of: $0)) | \(NSStringFromRect($0.accessibilityFrame()))" }
        try? tree.joined(separator: "\n").write(to: output.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }
}

@main @MainActor
private struct UIAcceptanceFixture {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--self-test"),
           CommandLine.arguments.indices.contains(index + 1) {
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try? "QA process entered main\n".write(to: output.appendingPathComponent("started.txt"), atomically: true, encoding: .utf8)
        }
        let app = NSApplication.shared
        let delegate = FixtureApplicationDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
