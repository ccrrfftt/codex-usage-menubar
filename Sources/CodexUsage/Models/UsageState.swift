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
    var accountingPresentation = AccountingPresentation.empty

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
        let percent = quotaPercent(remaining, language: language)
        let label = language.text(.statusItemLabel)
        let metric = accountingPresentation.cycle
        let upper = metric.costUpperBoundUSD ?? metric.apiUSD
        let belowSubscription = accountingPresentation.canCompareSelectedCycle && !stale && !metric.isEstimated && !metric.costIsPartial && upper.map { $0.isFinite && $0 >= 0 && $0 < 200 } == true
        let valueText = metric.costText(compact: true)
        let valueTitle = valueText == "—" ? "$—" : valueText
        let valueHelp = language.accountingText(.billingCycle) + " · " + (language == .chinese ? "所选记录 Standard API 等值 " : "Selected records, Standard API equivalent ") + valueText
        let warningHelp = belowSubscription ? (language == .chinese ? "；所选范围本周期 Standard API 等值低于 $200；全账户未核验" : "; selected sources this cycle are below $200 Standard API equivalent; account-wide coverage is unverified") : ""
        let restriction = restrictionMessage.map { "\n" + $0 } ?? ""
        return StatusItemState(
            title: percent + (remaining != nil && stale ? " ·" : ""),
            ring: QuotaRingState(remaining: remaining, showsValueWarning: belowSubscription),
            valueTitle: valueTitle,
            tooltip: "\(label) \(percent) · \(status)\(restriction)\n\(valueHelp)\(warningHelp)\n\(energyDescription)",
            accessibilityLabel: label,
            accessibilityValue: percent + restriction + "; " + valueHelp + warningHelp)
    }
}

struct StatusItemState: Equatable {
    let title: String
    let ring: QuotaRingState
    var valueTitle: String = "$—"
    let tooltip: String
    let accessibilityLabel: String
    let accessibilityValue: String
}
