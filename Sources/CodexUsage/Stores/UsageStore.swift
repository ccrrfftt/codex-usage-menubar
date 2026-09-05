import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var now = Date.now
    @Published private(set) var energy = EnergyState()
    private let connection = CodexConnection()
    private let systemMonitor = SystemActivityMonitor()
    private var refreshTimer: Timer?
    private var lastAttempt: Date?
    private var lastCompletion: Date?
    private var failures = 0
    private var stopped = false
    private var menuVisible = false

    var main: QuotaBucket? { snapshot?.main }
    var remaining: Double? { main?.headline?.remaining }
    var effectiveInterval: TimeInterval? {
        EnergyPolicy.refreshInterval(state: energy, failures: failures)
    }
    var stale: Bool {
        lastError != nil || !energy.allowsRefresh ||
            (updatedAt.map { now.timeIntervalSince($0) > max(90, (effectiveInterval ?? 60) * 2) } ?? true)
    }
    var title: String {
        quotaPercent(remaining) + (remaining != nil && stale ? " ·" : "")
    }
    var status: String {
        if !energy.networkAvailable { return "离线，联网后更新" }
        if !energy.allowsRefresh { return "休眠期间暂停查询" }
        if isRefreshing { return "正在同步…" }
        if stale { return updatedAt == nil ? "等待连接" : "当前显示上次数据" }
        return "智能节能更新"
    }
    var energyDescription: String {
        if !energy.networkAvailable { return "离线时暂停查询，网络恢复后自动更新。" }
        if !energy.allowsRefresh { return "屏幕或系统休眠期间暂停查询。" }
        return energy.onBattery ? "使用电池：每 5 分钟自动更新。" : "已接通电源：每 1 分钟自动更新。"
    }

    init() {
        energy = systemMonitor.state
        systemMonitor.onChange = { [weak self] state in self?.systemStateChanged(state) }
        Task { await refresh() }
    }

    func setMenuVisible(_ visible: Bool) {
        guard !stopped, visible != menuVisible else { return }
        menuVisible = visible
        now = .now
        // Opening the panel neither accelerates polling nor postpones the existing timer.
        if visible, let interval = effectiveInterval,
           lastCompletion.map({ now.timeIntervalSince($0) >= interval }) ?? true {
            Task { await refresh() }
        }
    }

    func refresh() async {
        guard !stopped, energy.allowsRefresh, !isRefreshing else { return }
        if let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < 5 { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRefreshing = true
        now = .now
        lastAttempt = now
        defer {
            isRefreshing = false
            lastCompletion = .now
            scheduleNextRefresh()
        }
        do {
            let result = try await connection.read()
            guard !stopped, energy.allowsRefresh else { return }
            snapshot = result
            updatedAt = .now
            now = .now
            lastError = nil
            failures = 0
        } catch {
            guard !stopped, energy.allowsRefresh else { return }
            lastError = error.localizedDescription
            failures += 1
        }
    }

    func stop() {
        stopped = true
        refreshTimer?.invalidate()
        refreshTimer = nil
        systemMonitor.stop()
        connection.stop()
    }

    private func systemStateChanged(_ state: EnergyState) {
        guard !stopped else { return }
        let wasSuspended = !energy.allowsRefresh
        energy = state
        now = .now
        if !state.allowsRefresh { connection.stop() }
        scheduleNextRefresh()
        if wasSuspended && state.allowsRefresh {
            Task { await refresh() }
        }
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard !stopped, !isRefreshing, let interval = effectiveInterval else { return }
        let elapsed = lastCompletion.map { Date.now.timeIntervalSince($0) } ?? 0
        let delay = max(5, interval - elapsed)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = EnergyPolicy.timerTolerance(interval: interval)
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
