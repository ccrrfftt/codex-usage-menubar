import Foundation

/// A refresh publishes its start and its completed result as two coherent states.
struct UsageState {
    var snapshot: QuotaSnapshot?
    var updatedAt: Date?
    var lastError: QuotaError?
    var isRefreshing = false
    var now = Date.now
    var energy = EnergyState()
    var language = AppLanguage.chinese

    var errorMessage: String? { lastError?.message(in: language) }

    var remaining: Double? { snapshot?.main?.headline?.remaining }
    var stale: Bool {
        lastError != nil || !energy.allowsRefresh ||
            (updatedAt.map { now.timeIntervalSince($0) > (EnergyPolicy.refreshInterval(state: energy) ?? 60) * 2 } ?? true)
    }
    var status: String {
        if !energy.networkAvailable { return language.text(.offlineStatus) }
        if !energy.allowsRefresh { return language.text(.pausedStatus) }
        if isRefreshing { return language.text(.syncing) }
        if stale { return language.text(updatedAt == nil ? .waitingForConnection : .previousData) }
        return language.text(.efficientUpdates)
    }
    var energyDescription: String {
        if !energy.networkAvailable { return language.text(.offlineHelp) }
        if !energy.allowsRefresh { return language.text(.pausedHelp) }
        return language.text(energy.onBattery ? .batteryHelp : .acHelp)
    }
    var updateLabel: String {
        if isRefreshing { return language.text(.updating) }
        guard let updatedAt else { return language.text(.notSynced) }
        return language.updatedLabel(updatedAt, stale: stale)
    }
    var statusItem: StatusItemState {
        let percent = quotaPercent(remaining, language: language)
        let label = language.text(.statusItemLabel)
        return StatusItemState(
            title: percent + (remaining != nil && stale ? " ·" : ""),
            tooltip: "\(label) \(percent) · \(status)\n\(energyDescription)",
            accessibilityLabel: label,
            accessibilityValue: percent)
    }
}

struct StatusItemState: Equatable {
    let title: String
    let tooltip: String
    let accessibilityLabel: String
    let accessibilityValue: String
}
