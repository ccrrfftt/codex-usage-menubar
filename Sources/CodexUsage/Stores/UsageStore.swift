import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState
    private let connection: any QuotaReading
    private let systemMonitor: SystemActivityMonitor?
    private let uptime: () -> TimeInterval
    private var refreshTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var lastAttempt: TimeInterval?
    private var lastCompletion: TimeInterval?
    private var failures = 0
    private var stopped = false

    init(connection: any QuotaReading = CodexConnection(),
         monitor: SystemActivityMonitor? = SystemActivityMonitor(),
         startImmediately: Bool = true,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.connection = connection
        systemMonitor = monitor
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
            scheduleRefresh(after: cooldown)
            return
        }
        invalidateTimer()
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

    func stop() {
        guard !stopped else { return }
        stopped = true
        invalidateTimer()
        refreshTask?.cancel()
        refreshTask = nil
        systemMonitor?.stop()
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
            invalidateTimer()
            return
        }
        let elapsed = lastCompletion.map { uptime() - $0 } ?? interval
        scheduleRefresh(after: max(1, interval - elapsed))
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        invalidateTimer()
        guard !stopped, state.energy.allowsRefresh, refreshTask == nil else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = EnergyPolicy.timerTolerance(interval: delay)
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func invalidateTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
