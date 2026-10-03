import Foundation

/// Compact menu-bar text; tooltips and the panel retain their detailed values.
enum MenuBarFormatting {
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        // Keep a sub-15% warning consistent with its visible integer percentage.
        return String(Int(floor(min(100, max(0, value))))) + "%"
    }

    static func usd(_ value: Double, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> String {
        let scales: [Double] = [1, 1_000, 1_000_000, 1_000_000_000]
        let units = ["", "K", "M", "B"]
        var index = 0
        while index < scales.count - 1 && (value / scales[index]).rounded(rounding) >= 1_000 { index += 1 }
        let number = (value / scales[index]).rounded(rounding)
            .formatted(.number.grouping(.never).precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
        return "$" + number + units[index]
    }
}

extension AccountingMetricPresentation {
    func menuCostText() -> String {
        guard let apiUSD, apiUSD.isFinite, apiUSD >= 0 else { return "—" }
        let prefix = isEstimated ? "≈" : (costIsPartial ? "≥" : "")
        if !costIsPartial, let upper = costUpperBoundUSD, upper.isFinite, upper > apiUSD {
            let lowerText = MenuBarFormatting.usd(apiUSD, rounding: .down)
            let upperText = MenuBarFormatting.usd(upper, rounding: .up)
            return prefix + lowerText + (lowerText == upperText ? "" : "–" + upperText.dropFirst())
        }
        if apiUSD > 0 && apiUSD < 1 {
            return costIsPartial && !isEstimated ? ">$0" : (isEstimated ? "≈<$1" : "<$1")
        }
        return prefix + MenuBarFormatting.usd(apiUSD, rounding: costIsPartial && !isEstimated ? .down : .toNearestOrAwayFromZero)
    }
}
