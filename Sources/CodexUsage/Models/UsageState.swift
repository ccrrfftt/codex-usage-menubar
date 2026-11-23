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
    var restrictionMessage: String? {
        if snapshot?.ordinaryUsageAllowed == false { return language.text(.ordinaryUsageUnavailable) }
        if snapshot?.main?.spendControlReached == true || snapshot?.main?.rateLimitReachedType != nil {
            return language.text(.limitReached)
        }
        return nil
    }
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
        let headline = snapshot?.main?.headline
        let remaining = headline?.remaining
        let percent = quotaPercent(remaining, language: language)
        let resetDate = headline?.resetDate
        let countdown = compactResetCountdown(resetDate, now: now)
        let reset = "\(language.text(.nextReset)) · \(resetCountdown(resetDate, now: now, language: language))"
        let label = language.text(.statusItemLabel)
        let restriction = restrictionMessage.map { "\n" + $0 } ?? ""
        return StatusItemState(
            title: percent + (remaining != nil && stale ? " ·" : ""),
            countdown: countdown.text,
            countdownUpdateAt: energy.allowsDisplayUpdates ? countdown.updateAt : nil,
            ring: QuotaRingState(remaining: remaining),
            tooltip: "\(label) \(percent) · \(status)\n\(reset)\(restriction)\n\(energyDescription)",
            accessibilityLabel: label,
            accessibilityValue: "\(percent)\n\(reset)\(restriction)")
    }
}

struct StatusItemState: Equatable {
    let title: String
    let countdown: String
    let countdownUpdateAt: Date?
    let ring: QuotaRingState
    let tooltip: String
    let accessibilityLabel: String
    let accessibilityValue: String
}

func compactResetCountdown(_ date: Date?, now: Date) -> (text: String, updateAt: Date?) {
    guard let date else { return ("—", nil) }
    let seconds = date.timeIntervalSince(now)
    guard seconds > 0, seconds / 60 < Double(Int.max) else { return ("—", nil) }

    let minutes = Int(seconds / 60)
    let hours = minutes / 60
    if minutes == 0 { return ("0h0m", date) }

    // The next whole unit disappears just after its exact boundary.
    if hours >= 24 {
        return ("\(hours / 24)d\(hours % 24)h", date.addingTimeInterval(0.1 - Double(hours) * 3600))
    }
    return ("\(hours)h\(minutes % 60)m", date.addingTimeInterval(0.1 - Double(minutes) * 60))
}
