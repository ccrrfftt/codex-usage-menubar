import Foundation

/// Day-level subscription periods. Billing-provider charge timestamps are not inferred.
struct AccountingCalendar: Sendable {
    let renewalDay: Int?
    let timeZone: TimeZone

    init(renewalDay: Int?, timeZone: TimeZone = .current) {
        self.renewalDay = renewalDay.flatMap { (1...31).contains($0) ? $0 : nil }
        self.timeZone = timeZone
    }

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    func today(containing now: Date) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    func subscriptionCycle(containing now: Date) -> DateInterval? {
        guard let day = renewalDay,
              let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        func anchor(_ monthStart: Date) -> Date? {
            guard let days = calendar.range(of: .day, in: .month, for: monthStart) else { return nil }
            return calendar.date(byAdding: .day, value: min(day, days.count) - 1, to: monthStart)
        }
        guard let thisAnchor = anchor(month.start) else { return nil }
        if now >= thisAnchor {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: month.start),
                  let nextAnchor = anchor(nextMonth) else { return nil }
            return DateInterval(start: thisAnchor, end: nextAnchor)
        }
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: month.start),
              let previousAnchor = anchor(previousMonth) else { return nil }
        return DateInterval(start: previousAnchor, end: thisAnchor)
    }
}

/// Keep an observed reset boundary, never subtract a nominal window from a future reset.
struct AccountingResetTracker: Codable, Sendable {
    private(set) var accountID: String?
    private(set) var observedAt: Date?
    private(set) var windowMinutes: Double?
    private(set) var usedPercent: Double?
    private(set) var nextReset: Date?
    private(set) var resetLowerBound: Date?
    private(set) var resetUpperBound: Date?

    mutating func observe(accountID: String?, window: QuotaWindow?, at now: Date) {
        let identity = accountID.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        // Unknown identity cannot prove continuity; equal-time callbacks cannot order two samples.
        if self.accountID != identity || identity == nil {
            self = AccountingResetTracker()
            self.accountID = identity
        } else if let observedAt, now <= observedAt {
            return
        }
        defer {
            observedAt = now
            windowMinutes = window?.windowDurationMins
            usedPercent = window?.usedPercent
            nextReset = window?.resetDate
        }
        guard let newMinutes = window?.windowDurationMins, newMinutes.isFinite, newMinutes > 0,
              let newUsed = window?.usedPercent, newUsed.isFinite, newUsed >= 0,
              let newReset = window?.resetDate, newReset > now else {
            resetLowerBound = nil
            resetUpperBound = nil
            return
        }
        guard let oldTime = observedAt, oldTime < now,
              windowMinutes == newMinutes,
              let oldUsed = usedPercent, oldUsed.isFinite, oldUsed >= 0,
              let oldReset = nextReset else {
            resetLowerBound = nil
            resetUpperBound = nil
            return
        }
        if newReset > oldReset && newUsed < oldUsed {
            // A manual reset can happen between polls even across the scheduled boundary.
            resetLowerBound = oldTime
            resetUpperBound = now
        } else if newReset != oldReset || newUsed < oldUsed {
            // The window changed without enough evidence to retain the previous reset boundary.
            resetLowerBound = nil
            resetUpperBound = nil
        }
    }
}
