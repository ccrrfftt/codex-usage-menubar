import Foundation

struct EnergyState: Equatable, Sendable {
    var onBattery = false
    var systemSleeping = false
    var displaySleeping = false
    var sessionInactive = false
    var networkAvailable = true

    var allowsRefresh: Bool {
        !systemSleeping && !displaySleeping && !sessionInactive && networkAvailable
    }
}

enum EnergyPolicy {
    static func refreshInterval(state: EnergyState, failures: Int = 0) -> TimeInterval? {
        guard state.allowsRefresh else { return nil }
        let base: Double = state.onBattery ? 300 : 60
        return min(1800, base * pow(2, Double(min(max(failures, 0), 5))))
    }

    static func timerTolerance(interval: TimeInterval) -> TimeInterval {
        min(30, interval * 0.1)
    }
}
