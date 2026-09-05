import Foundation

struct QuotaWindow: Decodable, Sendable, Equatable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: Double?

    var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }

    var period: String {
        guard let minutes = windowDurationMins, minutes.isFinite,
              minutes > 0, minutes < Double(Int.max) else { return "额度周期未提供" }
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(Int(minutes / 1440)) 天额度" }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(minutes / 60)) 小时额度" }
        return "\(Int(minutes)) 分钟额度"
    }

    var resetDate: Date? {
        guard let resetsAt, resetsAt.isFinite, resetsAt > 0 else { return nil }
        return Date(timeIntervalSince1970: resetsAt)
    }
}

struct QuotaBucket: Decodable, Sendable, Identifiable {
    let limitId: String?
    let limitName: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
    let rateLimitReachedType: String?
    let spendControlReached: Bool?

    var id: String { limitId ?? limitName ?? "codex" }
    var name: String { id == "codex" ? "Codex 主额度" : (limitName ?? id) }
    var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
    var headline: QuotaWindow? {
        guard let primary else { return secondary }
        guard let secondary else { return primary }
        guard let first = primary.remaining else { return secondary.remaining == nil ? primary : secondary }
        guard let second = secondary.remaining else { return primary }
        return first <= second ? primary : secondary
    }

    func identified(by id: String) -> QuotaBucket {
        QuotaBucket(limitId: id, limitName: limitName, primary: primary, secondary: secondary,
                    planType: planType, rateLimitReachedType: rateLimitReachedType,
                    spendControlReached: spendControlReached)
    }
}

struct ResetCard: Decodable, Sendable {
    let expiresAt: Double?
    let status: String?

    var expirationDate: Date? {
        guard let expiresAt, expiresAt.isFinite, expiresAt > 0 else { return nil }
        return Date(timeIntervalSince1970: expiresAt)
    }
}

struct ResetCreditBalance: Decodable, Sendable {
    let availableCount: Int?
    let credits: [ResetCard]?
}

struct QuotaSnapshot: Decodable, Sendable {
    let main: QuotaBucket?
    let otherBuckets: [QuotaBucket]
    let resetCardCount: Int?
    let resetCards: [ResetCard]?

    private enum CodingKeys: String, CodingKey {
        case rateLimits, rateLimitsByLimitId, rateLimitResetCredits
    }

    // Normalize once on the query queue, not every time SwiftUI reads the snapshot.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let mapped = try values.decodeIfPresent([String: QuotaBucket].self, forKey: .rateLimitsByLimitId)
        if let mapped, !mapped.isEmpty {
            main = mapped["codex"]?.identified(by: "codex")
            otherBuckets = mapped.keys.filter { $0 != "codex" }.sorted().compactMap { key in
                mapped[key]?.identified(by: key)
            }
        } else {
            main = try values.decodeIfPresent(QuotaBucket.self, forKey: .rateLimits)?.identified(by: "codex")
            otherBuckets = []
        }
        let balance = try values.decodeIfPresent(ResetCreditBalance.self, forKey: .rateLimitResetCredits)
        resetCardCount = balance?.availableCount.flatMap { $0 >= 0 ? $0 : nil }
        resetCards = balance?.credits?
            .filter { $0.status == nil || $0.status == "available" }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    }
}

func quotaPercent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...1))) + "%"
}

func resetCountdown(_ date: Date?, now: Date = .now) -> String {
    guard let date else { return "重置时间未提供" }
    let seconds = date.timeIntervalSince(now)
    guard seconds.isFinite, seconds / 60 < Double(Int.max) else { return "重置时间未提供" }
    guard seconds > 0 else { return "等待额度更新" }
    let minutes = Int(ceil(seconds / 60))
    let days = minutes / 1440, hours = (minutes % 1440) / 60
    if days > 0 { return "\(days) 天 \(hours) 小时后" }
    if hours > 0 { return "\(hours) 小时 \(minutes % 60) 分钟后" }
    return "\(max(1, minutes)) 分钟后"
}
