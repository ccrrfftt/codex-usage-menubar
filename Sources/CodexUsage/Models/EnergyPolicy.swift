import Foundation

struct EnergyState: Equatable, Sendable {
    var onBattery = false
    var lowPower = false
    var thermallyConstrained = false
    var systemSleeping = false
    var displaySleeping = false
    var sessionInactive = false
    var networkAvailable = true

    var allowsRefresh: Bool {
        !systemSleeping && !displaySleeping && !sessionInactive && networkAvailable
    }

    var constrained: Bool { lowPower || thermallyConstrained }
}

enum EnergyPolicy {
    static func refreshInterval(menuVisible: Bool, requestedInterval: Int,
                                state: EnergyState, failures: Int = 0) -> TimeInterval? {
        guard state.allowsRefresh else { return nil }
        let base: Double
        if menuVisible {
            base = state.constrained ? max(60, Double(requestedInterval)) : Double(requestedInterval)
        } else {
            base = state.constrained ? 600 : state.onBattery ? 300 : 120
        }
        return min(1800, max(15, base) * pow(2, Double(min(max(failures, 0), 5))))
    }

    static func timerTolerance(interval: TimeInterval) -> TimeInterval {
        min(30, interval * 0.1)
    }
}
