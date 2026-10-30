/// The ring uses the same remaining quota as the adjacent percentage.
struct QuotaRingState: Equatable, Sendable {
    let fraction: Double?

    init(remaining: Double?) {
        fraction = remaining.flatMap { $0.isFinite ? max(0, min(100, $0)) / 100 : nil }
    }

    var isLow: Bool { fraction.map { $0 < 0.2 } ?? false }
}
