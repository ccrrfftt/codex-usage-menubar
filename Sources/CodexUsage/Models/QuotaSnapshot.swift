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
        guard let minutes = windowDurationMins, minutes.isFinite, minutes > 0 else { return "额度周期未提供" }
        if minutes == 10080 { return "7 天额度" }
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
        windows.filter { $0.remaining != nil }.min { ($0.remaining ?? 101) < ($1.remaining ?? 101) } ?? windows.first
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
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    let rateLimitResetCredits: ResetCreditBalance?

    var resetCardCount: Int? {
        guard let count = rateLimitResetCredits?.availableCount, count >= 0 else { return nil }
        return count
    }

    var resetCards: [ResetCard]? {
        rateLimitResetCredits?.credits?
            .filter { $0.status == nil || $0.status == "available" }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    }

    var buckets: [QuotaBucket] {
        if let mapped = rateLimitsByLimitId, !mapped.isEmpty {
            return mapped.sorted { a, b in
                if a.key == "codex" { return true }
                if b.key == "codex" { return false }
                return a.key < b.key
            }.map { $0.value }
        }
        return [rateLimits].compactMap { $0 }
    }

    var main: QuotaBucket? {
        if let mapped = rateLimitsByLimitId, !mapped.isEmpty { return mapped["codex"] }
        return rateLimits
    }
}

func quotaPercent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...1))) + "%"
}

func resetCountdown(_ date: Date?, now: Date = .now) -> String {
    guard let date else { return "重置时间未提供" }
    let seconds = date.timeIntervalSince(now)
    guard seconds > 0 else { return "等待额度更新" }
    let minutes = Int(ceil(seconds / 60))
    let days = minutes / 1440, hours = (minutes % 1440) / 60
    if days > 0 { return "\(days) 天 \(hours) 小时后" }
    if hours > 0 { return "\(hours) 小时 \(minutes % 60) 分钟后" }
    return "\(max(1, minutes)) 分钟后"
}
