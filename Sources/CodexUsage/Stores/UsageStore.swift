import Combine
import Foundation
import AppKit

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState
    private let connection: any QuotaReading
    private let systemMonitor: SystemActivityMonitor?
    private let scheduler: any RefreshScheduling
    private let preferences: UserDefaults?
    private let uptime: () -> TimeInterval
    private var refreshTask: Task<Void, Never>?
    private var retiringTasks: [UUID: Task<Void, Never>] = [:]
    private var needsRefreshAfterCooldown = false
    private var lastAttempt: TimeInterval?
    private var lastCompletion: TimeInterval?
    private var failures = 0
    private var stopped = false
    private var accountingSnapshot: AccountingSnapshot?
    private var billingDay: Int?
    private let trackingStart: Date
    private var accountingFolders: [String] = []
    private var resetTracker = AccountingResetTracker()
    private var folderPanel: NSOpenPanel?

    private struct RefreshPayload {
        let quota: QuotaSnapshot
        let accounting: AccountingSnapshot?
    }

    init(connection: any QuotaReading = CodexConnection(),
         monitor: SystemActivityMonitor? = SystemActivityMonitor(),
         scheduler: any RefreshScheduling = RefreshScheduler(),
         preferences: UserDefaults? = .standard,
         startImmediately: Bool = true,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.connection = connection
        systemMonitor = monitor
        self.scheduler = scheduler
        self.preferences = preferences
        self.uptime = uptime
        let started = Date.now
        let savedStart = preferences?.double(forKey: "accountingTrackingStart") ?? 0
        if savedStart.isFinite && savedStart > 0 && savedStart <= started.timeIntervalSince1970 {
            trackingStart = Date(timeIntervalSince1970: savedStart)
        } else {
            trackingStart = AccountingCalendar(renewalDay: nil).today(containing: started).start
            preferences?.set(trackingStart.timeIntervalSince1970, forKey: "accountingTrackingStart")
        }
        state = UsageState(energy: monitor?.state ?? EnergyState(),
                           language: AppLanguage.restored(from: preferences?.string(forKey: AppLanguage.preferenceKey)))
        monitor?.onChange = { [weak self] state in self?.updateSystemState(state) }
        let day = preferences?.integer(forKey: "billingRenewalDay") ?? 0
        billingDay = (1...31).contains(day) ? day : nil
        accountingFolders = preferences?.stringArray(forKey: "accountingFolders") ?? []
        if let data = preferences?.data(forKey: "resetObservation"),
           let saved = try? JSONDecoder().decode(AccountingResetTracker.self, from: data) { resetTracker = saved }
        updateAccountingPresentation()
        if startImmediately { refresh() }
    }

    func toggleLanguage() {
        guard !stopped else { return }
        var next = state
        next.language = state.language.other
        next.now = .now
        preferences?.set(next.language.rawValue, forKey: AppLanguage.preferenceKey)
        state = next
        updateAccountingPresentation()
    }

    func prepareForDisplay() {
        guard !stopped else { return }
        state.now = .now
        updateAccountingPresentation()
        // Opening never postpones the timer or bypasses the normal failure backoff.
        if let interval = EnergyPolicy.refreshInterval(state: state.energy, failures: failures),
           lastCompletion.map({ uptime() - $0 >= interval }) ?? true {
            refresh()
        }
    }

    func refresh() {
        guard !stopped, state.energy.allowsRefresh, refreshTask == nil else { return }
        let cooldown = lastAttempt.map { max(0, 5 - (uptime() - $0)) } ?? 0
        if cooldown > 0 {
            needsRefreshAfterCooldown = true
            scheduleRefresh(after: cooldown)
            return
        }
        needsRefreshAfterCooldown = false
        scheduler.cancel()
        lastAttempt = uptime()
        var next = state
        next.isRefreshing = true
        next.now = .now
        state = next
        let scopes = accountingFolders
        let cutoff = trackingStart
        refreshTask = Task { [weak self, connection] in
            let result: Result<RefreshPayload, Error>
            do {
                if let dashboardReader = connection as? any DashboardReading {
                    let dashboard = try await dashboardReader.readDashboard(allowedWorkingDirectories: scopes, trackingStart: cutoff)
                    result = .success(RefreshPayload(quota: dashboard.quota, accounting: dashboard.accounting))
                } else {
                    result = .success(RefreshPayload(quota: try await connection.read(), accounting: nil))
                }
            }
            catch { result = .failure(error) }
            // A cancelled read must not overwrite a newer request after wake/reconnect.
            guard !Task.isCancelled, let self, !self.stopped else { return }
            self.complete(result)
        }
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        guard !stopped else { return nil }
        stopped = true
        scheduler.cancel()
        cancelRefreshForCleanup()
        let pending = Array(retiringTasks.values)
        systemMonitor?.stop()
        folderPanel?.cancel(nil)
        if let data = try? JSONEncoder().encode(resetTracker) { preferences?.set(data, forKey: "resetObservation") }
        guard !pending.isEmpty else { return nil }
        return Task { for cleanup in pending { await cleanup.value } }
    }

    private func cancelRefreshForCleanup() {
        guard let pending = refreshTask else { return }
        refreshTask = nil
        pending.cancel()
        let id = UUID()
        retiringTasks[id] = pending
        Task { [weak self] in
            await pending.value
            self?.retiringTasks.removeValue(forKey: id)
        }
    }

    func updateSystemState(_ energy: EnergyState) {
        guard !stopped, energy != state.energy else { return }
        let wasSuspended = !state.energy.allowsRefresh
        var next = state
        next.energy = energy
        next.now = .now
        if !energy.allowsRefresh {
            cancelRefreshForCleanup()
            next.isRefreshing = false
        }
        state = next
        if wasSuspended && energy.allowsRefresh { refresh() }
        else { scheduleNextRefresh() }
    }

    private func complete(_ result: Result<RefreshPayload, Error>) {
        refreshTask = nil
        lastCompletion = uptime()
        var next = state
        next.isRefreshing = false
        next.now = .now
        switch result {
        case .success(let payload):
            let snapshot = payload.quota
            next.snapshot = snapshot
            accountingSnapshot = payload.accounting
            let window = snapshot.main?.windows.max { ($0.windowDurationMins ?? 0) < ($1.windowDurationMins ?? 0) }
            resetTracker.observe(accountID: snapshot.accountId, window: window, at: next.now)
            next.accountingPresentation = AccountingSummary.make(snapshot: accountingSnapshot,
                calendar: AccountingCalendar(renewalDay: billingDay), reset: resetTracker,
                now: next.now, folderCount: accountingFolders.count, language: next.language, trackingStart: trackingStart)
            next.updatedAt = next.now
            next.lastError = nil
            failures = 0
        case .failure(let error):
            next.lastError = error as? QuotaError ?? .disconnected
            failures = min(5, failures + 1)
        }
        state = next
        scheduleNextRefresh()
    }

    func setBillingDay(_ day: Int) {
        guard !stopped else { return }
        billingDay = (1...31).contains(day) ? day : nil
        preferences?.set(billingDay ?? 0, forKey: "billingRenewalDay")
        updateAccountingPresentation()
    }

    func chooseAccountingFolders() {
        guard !stopped, folderPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if let currentRoot = accountingFolders.first {
            panel.directoryURL = URL(fileURLWithPath: currentRoot, isDirectory: true)
        }
        panel.title = state.language.accountingText(.recordSources)
        panel.message = state.language == .chinese
            ? "只统计所选项目目录对应的对话用量记录。"
            : "Only usage records for conversations in the selected project directories are included."
        folderPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.folderPanel = nil
            guard response == .OK, !self.stopped else { return }
            self.setAccountingFolders(panel.urls.map { $0.standardizedFileURL.path })
        }
    }

    func clearAccountingFolders() { setAccountingFolders([]) }

    func setAccountingFolders(_ folders: [String]) {
        guard !stopped else { return }
        let selected = Array(Set(folders.filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
        guard selected != accountingFolders else { return }
        // Cancel before replacing scope; a removed source must not return in a late reply.
        cancelRefreshForCleanup()
        accountingFolders = selected
        accountingSnapshot = nil
        preferences?.set(selected, forKey: "accountingFolders")
        state.isRefreshing = false
        updateAccountingPresentation()
        refresh()
    }

    private func updateAccountingPresentation() {
        let presentation = AccountingSummary.make(snapshot: accountingSnapshot,
            calendar: AccountingCalendar(renewalDay: billingDay), reset: resetTracker,
            now: state.now, folderCount: accountingFolders.count, language: state.language, trackingStart: trackingStart)
        if state.accountingPresentation != presentation { state.accountingPresentation = presentation }
    }

    private func scheduleNextRefresh() {
        guard let interval = EnergyPolicy.refreshInterval(state: state.energy, failures: failures) else {
            scheduler.cancel()
            return
        }
        if needsRefreshAfterCooldown { refresh(); return }
        let elapsed = lastCompletion.map { uptime() - $0 } ?? interval
        scheduleRefresh(after: max(1, interval - elapsed))
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        guard !stopped, state.energy.allowsRefresh, refreshTask == nil else {
            scheduler.cancel()
            return
        }
        scheduler.schedule(after: delay) { [weak self] in self?.refresh() }
    }
}
