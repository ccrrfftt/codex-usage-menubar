import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState
    private let connection: any QuotaReading
    private let systemMonitor: SystemActivityMonitor?
    private let scheduler: any RefreshScheduling
    private let uptime: () -> TimeInterval
    private var refreshTask: Task<Void, Never>?
    private var needsRefreshAfterCooldown = false
    private var lastAttempt: TimeInterval?
    private var lastCompletion: TimeInterval?
    private var failures = 0
    private var stopped = false

    init(connection: any QuotaReading = CodexConnection(),
         monitor: SystemActivityMonitor? = SystemActivityMonitor(),
         scheduler: any RefreshScheduling = RefreshScheduler(),
         startImmediately: Bool = true,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.connection = connection
        systemMonitor = monitor
        self.scheduler = scheduler
        self.uptime = uptime
        state = UsageState(energy: monitor?.state ?? EnergyState())
        monitor?.onChange = { [weak self] state in self?.updateSystemState(state) }
        if startImmediately { refresh() }
    }

    func prepareForDisplay() {
        guard !stopped else { return }
        state.now = .now
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
        refreshTask = Task { [weak self, connection] in
            let result: Result<QuotaSnapshot, Error>
            do { result = .success(try await connection.read()) }
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
        let pending = refreshTask
        pending?.cancel()
        refreshTask = nil
        systemMonitor?.stop()
        return pending
    }

    func updateSystemState(_ energy: EnergyState) {
        guard !stopped, energy != state.energy else { return }
        let wasSuspended = !state.energy.allowsRefresh
        var next = state
        next.energy = energy
        next.now = .now
        if !energy.allowsRefresh {
            refreshTask?.cancel()
            refreshTask = nil
            next.isRefreshing = false
        }
        state = next
        if wasSuspended && energy.allowsRefresh { refresh() }
        else { scheduleNextRefresh() }
    }

    private func complete(_ result: Result<QuotaSnapshot, Error>) {
        refreshTask = nil
        lastCompletion = uptime()
        var next = state
        next.isRefreshing = false
        next.now = .now
        switch result {
        case .success(let snapshot):
            next.snapshot = snapshot
            next.updatedAt = next.now
            next.lastError = nil
            failures = 0
        case .failure(let error):
            next.lastError = error.localizedDescription
            failures = min(5, failures + 1)
        }
        state = next
        scheduleNextRefresh()
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
