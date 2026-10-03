import Foundation

/// UI-only values. Token coverage and price coverage are deliberately independent.
struct AccountingMetricPresentation: Equatable, Sendable {
    var tokens: Int64? = nil
    var apiUSD: Double? = nil
    var costUpperBoundUSD: Double? = nil
    var tokensArePartial = false
    var costIsPartial = false
    var isEstimated = false

    func tokenText(in language: AppLanguage, compact: Bool = true) -> String {
        guard let tokens, tokens >= 0 else { return "—" }
        let number: String
        if compact {
            number = tokens.formatted(.number.notation(.compactName)
                .precision(.fractionLength(0...1)).locale(language.locale))
        } else {
            number = tokens.formatted(.number.locale(language.locale))
        }
        return (isEstimated ? "≈" : (tokensArePartial ? "≥" : "")) + number
    }

    func costText(compact: Bool = false) -> String {
        guard let apiUSD, apiUSD.isFinite, apiUSD >= 0 else { return "—" }
        let prefix = isEstimated ? "≈" : (costIsPartial ? "≥" : "")
        if !costIsPartial, let upper = costUpperBoundUSD, upper.isFinite, upper > apiUSD {
            return prefix + Self.usd(apiUSD, compact: compact) + "–" + Self.usd(upper, compact: compact).dropFirst()
        }
        if apiUSD > 0 && apiUSD < 0.01 {
            if isEstimated {
                return "≈$" + apiUSD.formatted(.number.precision(.fractionLength(3...6))
                    .locale(Locale(identifier: "en_US")))
            }
            return costIsPartial ? "> $0" : "<$0.01"
        }
        return prefix + Self.usd(apiUSD, compact: compact)
    }

    private static func usd(_ amount: Double, compact: Bool) -> String {
        if compact && amount >= 10_000 {
            return "$" + amount.formatted(.number.notation(.compactName)
                .precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
        }
        return "$" + amount.formatted(.number.precision(.fractionLength(2))
            .locale(Locale(identifier: "en_US")))
    }
}

struct AccountingConversationPresentation: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var updatedAt: Date? = nil
    var metric: AccountingMetricPresentation
}

enum AccountingCoverage: String, Equatable, Sendable {
    case loading, unavailable, partial, complete
}

enum AccountingTokenSource: String, Equatable, Sendable {
    case account, local, mixed, unavailable
}

struct AccountingPresentation: Equatable, Sendable {
    var today = AccountingMetricPresentation()
    var sinceReset = AccountingMetricPresentation()
    var cycle = AccountingMetricPresentation()
    var conversations: [AccountingConversationPresentation] = []
    var coverage = AccountingCoverage.unavailable
    var tokenSource = AccountingTokenSource.unavailable
    var billingDay: Int? = nil
    var cycleStart: Date? = nil
    var cycleEnd: Date? = nil
    var lastReset: Date? = nil
    var lastResetLowerBound: Date? = nil
    var sourceFolderCount = 0
    /// This compares only the selected records; it never asserts whole-account coverage.
    var canCompareSelectedCycle = false

    static let empty = AccountingPresentation()
}
