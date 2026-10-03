import Foundation

/// Historical quota evidence contains numeric limit fields only, never messages.
struct RecordedQuotaObservation: Sendable, Equatable {
    let timestamp: Date
    let window: QuotaWindow
}

struct RecordedQuotaSnapshotPayload: Decodable, Sendable {
    let limitId: String?
    let primary: RecordedQuotaWindow?
    let secondary: RecordedQuotaWindow?

    enum CodingKeys: String, CodingKey {
        case limitId = "limit_id", primary, secondary
    }

    func observation(at timestamp: Date) -> RecordedQuotaObservation? {
        // A legacy unidentified limit may belong to a separate model allowance.
        guard limitId == "codex", timestamp.timeIntervalSince1970.isFinite else { return nil }
        let windows = [primary, secondary].compactMap { $0?.quotaWindow }
            .filter { ($0.resetDate ?? .distantPast) > timestamp }
        guard let window = windows.max(by: { ($0.windowDurationMins ?? 0) < ($1.windowDurationMins ?? 0) }) else { return nil }
        return RecordedQuotaObservation(timestamp: timestamp, window: window)
    }
}

struct RecordedQuotaWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowMinutes: Double?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent", windowMinutes = "window_minutes", resetsAt = "resets_at"
    }

    var quotaWindow: QuotaWindow? {
        guard let usedPercent, usedPercent.isFinite, usedPercent >= 0,
              let windowMinutes, windowMinutes.isFinite, windowMinutes > 0, windowMinutes < 10_000_000,
              let resetsAt, resetsAt.isFinite, resetsAt > 0, resetsAt < 32_503_680_000 else { return nil }
        return QuotaWindow(usedPercent: usedPercent, windowDurationMins: windowMinutes, resetsAt: resetsAt)
    }
}

enum RecordedResetInference {
    /// An observation's timestamp is an upper bound, not the instant of reset.
    /// Historical headers may be replayed or account-unattributed, so callers
    /// must label this result as an estimate and never replace stronger live evidence.
    static func upperBound(observations: [RecordedQuotaObservation], current: AccountingResetTracker,
                           now: Date) -> Date? {
        guard current.accountID != nil, let minutes = current.windowMinutes,
              let reset = current.nextReset, reset > now,
              let used = current.usedPercent, used.isFinite, used >= 0 else { return nil }
        let relevant = observations.filter {
            $0.timestamp <= now && $0.timestamp.timeIntervalSince1970.isFinite &&
            $0.window.windowDurationMins == minutes && $0.window.resetDate != nil &&
            $0.window.usedPercent.map { $0.isFinite && $0 >= 0 } == true &&
            ($0.window.resetDate ?? .distantPast) > $0.timestamp
        }.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return ($0.window.resetDate ?? .distantPast) < ($1.window.resetDate ?? .distantPast)
        }
        var previous: RecordedQuotaObservation?
        var upper: Date?
        for point in relevant {
            if let previous {
                guard point.window.resetDate! >= previous.window.resetDate! else { continue }
                if point.window.resetDate! > previous.window.resetDate! {
                    upper = point.window.usedPercent! < previous.window.usedPercent! ? point.timestamp : nil
                } else if point.window.usedPercent! < previous.window.usedPercent! {
                    // Repeated token-count events can carry an older header snapshot.
                    continue
                }
            }
            previous = point
        }
        guard let previous, previous.window.resetDate == reset,
              used >= previous.window.usedPercent! else { return nil }
        return upper
    }
}
