import Foundation

/// A refresh publishes its start and its completed result as two coherent states.
struct UsageState {
    var snapshot: QuotaSnapshot?
    var updatedAt: Date?
    var lastError: String?
    var isRefreshing = false
    var now = Date.now
    var energy = EnergyState()

    var remaining: Double? { snapshot?.main?.headline?.remaining }
    var stale: Bool {
        lastError != nil || !energy.allowsRefresh ||
            (updatedAt.map { now.timeIntervalSince($0) > (EnergyPolicy.refreshInterval(state: energy) ?? 60) * 2 } ?? true)
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
    var updateLabel: String {
        if isRefreshing { return "正在更新…" }
        guard let updatedAt else { return "尚未同步" }
        let time = updatedAt.formatted(date: .omitted, time: .standard)
        return stale ? "旧数据 · \(time)" : "更新于 \(time)"
    }
    var statusItem: StatusItemState {
        let percent = quotaPercent(remaining)
        return StatusItemState(
            title: percent + (remaining != nil && stale ? " ·" : ""),
            tooltip: "Codex 剩余 \(percent) · \(status)\n\(energyDescription)",
            accessibilityValue: percent)
    }
}

struct StatusItemState: Equatable {
    let title: String
    let tooltip: String
    let accessibilityValue: String
}
