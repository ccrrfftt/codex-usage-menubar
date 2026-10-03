/// The ring uses the same remaining quota as the adjacent percentage.
struct QuotaRingState: Equatable, Sendable {
    let fraction: Double?
    let showsValueWarning: Bool

    init(remaining: Double?, showsValueWarning: Bool = false) {
        fraction = remaining.flatMap { $0.isFinite ? max(0, min(100, $0)) / 100 : nil }
        self.showsValueWarning = showsValueWarning
    }

    var isLow: Bool { fraction.map { $0 < 0.15 } ?? false }
}
