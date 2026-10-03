import Foundation

@main @MainActor
struct AccountingCalendarChecks {
    private static var checked = 0

    static func check(_ success: Bool, _ label: String) {
        precondition(success, "FAILED: " + label)
        checked += 1
        print("PASS: " + label)
    }

    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    static func matches(_ interval: DateInterval?, _ start: String, _ end: String) -> Bool {
        interval?.start == date(start) && interval?.end == date(end)
    }

    static func window(_ used: Double?, reset: Date?, minutes: Double? = 10_080) -> QuotaWindow {
        QuotaWindow(usedPercent: used, windowDurationMins: minutes, resetsAt: reset?.timeIntervalSince1970)
    }

    static func calendarChecks() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let fifth = AccountingCalendar(renewalDay: 5, timeZone: shanghai)
        let boundary = date("2026-10-05T00:00:00+08:00")
        check(matches(fifth.subscriptionCycle(containing: boundary.addingTimeInterval(-1)),
                      "2026-09-05T00:00:00+08:00", "2026-10-05T00:00:00+08:00"),
              "one second before Oct 5 stays in the Sep 5 subscription cycle")
        check(matches(fifth.subscriptionCycle(containing: boundary),
                      "2026-10-05T00:00:00+08:00", "2026-11-05T00:00:00+08:00"),
              "Oct 5 midnight belongs to the new cycle in Shanghai, not UTC")
        check(matches(fifth.subscriptionCycle(containing: date("2027-01-01T12:00:00+08:00")),
                      "2026-12-05T00:00:00+08:00", "2027-01-05T00:00:00+08:00"),
              "subscription cycles cross the year without changing renewal day")
        check(matches(fifth.subscriptionCycle(containing: date("2026-11-05T00:00:00+08:00")),
                      "2026-11-05T00:00:00+08:00", "2026-12-05T00:00:00+08:00"),
              "successive cycle boundaries are contiguous and roll over immediately")
        let last = AccountingCalendar(renewalDay: 31, timeZone: shanghai)
        check(matches(last.subscriptionCycle(containing: date("2027-02-27T23:59:59+08:00")),
                      "2027-01-31T00:00:00+08:00", "2027-02-28T00:00:00+08:00"),
              "day 31 clamps February to its last day in a non-leap year")
        check(matches(last.subscriptionCycle(containing: date("2027-02-28T00:00:00+08:00")),
                      "2027-02-28T00:00:00+08:00", "2027-03-31T00:00:00+08:00"),
              "February clamp does not drift March renewal to the 28th")
        check(matches(last.subscriptionCycle(containing: date("2028-02-29T00:00:00+08:00")),
                      "2028-02-29T00:00:00+08:00", "2028-03-31T00:00:00+08:00"),
              "leap February renews on the 29th and restores March 31")
        check(matches(last.subscriptionCycle(containing: date("2026-04-30T00:00:00+08:00")),
                      "2026-04-30T00:00:00+08:00", "2026-05-31T00:00:00+08:00"),
              "a 30-day month clamps locally without persistent day drift")
        for invalid in [nil, -1, 0, 32, Int.max] as [Int?] {
            let calendar = AccountingCalendar(renewalDay: invalid, timeZone: shanghai)
            check(calendar.renewalDay == nil && calendar.subscriptionCycle(containing: boundary) == nil,
                  "invalid or absent renewal day is unavailable: \(String(describing: invalid))")
        }
        check(matches(fifth.today(containing: date("2026-10-03T23:59:59+08:00")),
                      "2026-10-03T00:00:00+08:00", "2026-10-04T00:00:00+08:00"),
              "today uses the selected local midnight boundaries")
        let losAngeles = AccountingCalendar(renewalDay: 8, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let spring = losAngeles.today(containing: date("2026-03-08T15:00:00-07:00"))
        check(spring.duration == 23 * 3600
              && matches(spring, "2026-03-08T00:00:00-08:00", "2026-03-09T00:00:00-07:00"),
              "spring DST day has 23 hours and still ends at local midnight")
        let fall = losAngeles.today(containing: date("2026-11-01T15:00:00-08:00"))
        check(fall.duration == 25 * 3600
              && matches(fall, "2026-11-01T00:00:00-07:00", "2026-11-02T00:00:00-08:00"),
              "fall DST day has 25 hours and still ends at local midnight")
        check(matches(losAngeles.subscriptionCycle(containing: date("2026-03-08T15:00:00-07:00")),
                      "2026-03-08T00:00:00-08:00", "2026-04-08T00:00:00-07:00"),
              "monthly cycles follow local dates across a DST transition")
    }

    static func resetChecks() throws {
        let start = date("2026-10-03T08:00:00+08:00")
        let oldReset = start.addingTimeInterval(600)
        let newReset = oldReset.addingTimeInterval(7 * 86400)
        let after = start.addingTimeInterval(660)
        var scheduled = AccountingResetTracker()
        scheduled.observe(accountID: "synthetic-account-a", window: window(80, reset: oldReset), at: start)
        check(scheduled.resetLowerBound == nil && scheduled.resetUpperBound == nil,
              "first observation never derives a past reset by subtracting a nominal window")
        scheduled.observe(accountID: "synthetic-account-a", window: window(2, reset: newReset), at: after)
        check(scheduled.resetLowerBound == start && scheduled.resetUpperBound == after,
              "crossing a scheduled reset records an interval, because a manual reset is indistinguishable")
        var manual = AccountingResetTracker()
        manual.observe(accountID: "synthetic-account-a", window: window(80, reset: oldReset), at: start)
        let beforeScheduled = start.addingTimeInterval(120)
        manual.observe(accountID: "synthetic-account-a", window: window(0, reset: newReset), at: beforeScheduled)
        check(manual.resetLowerBound == start && manual.resetUpperBound == beforeScheduled,
              "an early manual reset uses observed polling bounds")
        scheduled.observe(accountID: "synthetic-account-a", window: window(5, reset: newReset),
                          at: after.addingTimeInterval(60))
        check(scheduled.resetLowerBound == start && scheduled.resetUpperBound == after,
              "ordinary quota growth within the same window preserves observed reset bounds")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let stable = try encoder.encode(scheduled)
        scheduled.observe(accountID: "synthetic-account-a", window: window(99, reset: oldReset),
                          at: start.addingTimeInterval(60))
        check(try encoder.encode(scheduled) == stable,
              "a stale same-account response cannot move observation time or restore old counters")
        scheduled.observe(accountID: "synthetic-account-a", window: window(0, reset: newReset.addingTimeInterval(86400)),
                          at: after.addingTimeInterval(60))
        check(try encoder.encode(scheduled) == stable,
              "equal-time conflicting responses cannot establish observation order")
        let restored = try JSONDecoder().decode(AccountingResetTracker.self, from: stable)
        check(restored.resetLowerBound == start && restored.resetUpperBound == after
              && restored.accountID == "synthetic-account-a", "persistence preserves interval and account identity")
        var changed = restored
        changed.observe(accountID: "synthetic-account-b", window: window(1, reset: newReset),
                        at: after.addingTimeInterval(120))
        check(changed.accountID == "synthetic-account-b" && changed.resetLowerBound == nil
              && changed.resetUpperBound == nil, "switching accounts invalidates prior reset history")
        for unknown in [nil, "", "   "] as [String?] {
            var tracker = restored
            tracker.observe(accountID: unknown, window: window(90, reset: oldReset), at: start)
            tracker.observe(accountID: unknown, window: window(0, reset: newReset), at: after)
            check(tracker.accountID == nil && tracker.resetLowerBound == nil && tracker.resetUpperBound == nil,
                  "unknown or empty account identity cannot prove continuity")
        }
        var durationChange = restored
        durationChange.observe(accountID: "synthetic-account-a", window: window(1, reset: newReset, minutes: 300),
                               at: after.addingTimeInterval(120))
        check(durationChange.resetUpperBound == nil && durationChange.resetLowerBound == nil,
              "changing quota-window duration invalidates the old period boundary")
        var missedCycle = restored
        missedCycle.observe(accountID: "synthetic-account-a", window: window(50, reset: newReset.addingTimeInterval(7 * 86400)),
                            at: newReset.addingTimeInterval(60))
        check(missedCycle.resetUpperBound == nil, "missed cycles with no observed usage drop cannot retain an obsolete reset")
        var movedBack = restored
        movedBack.observe(accountID: "synthetic-account-a", window: window(6, reset: newReset.addingTimeInterval(-60)),
                          at: after.addingTimeInterval(120))
        check(movedBack.resetUpperBound == nil, "a backwards reset-schedule change invalidates prior bounds")
        var sameScheduleDrop = restored
        sameScheduleDrop.observe(accountID: "synthetic-account-a", window: window(0, reset: newReset),
                                 at: after.addingTimeInterval(120))
        check(sameScheduleDrop.resetUpperBound == nil,
              "an unexplained usage drop with unchanged schedule is not false continuity")
        let invalidWindows: [QuotaWindow?] = [nil, window(nil, reset: newReset), window(.nan, reset: newReset),
            window(-1, reset: newReset), window(5, reset: nil), window(5, reset: newReset, minutes: nil),
            window(5, reset: newReset, minutes: 0), window(5, reset: newReset, minutes: .infinity),
            window(5, reset: after)]
        for invalid in invalidWindows {
            var tracker = restored
            tracker.observe(accountID: "synthetic-account-a", window: invalid, at: after.addingTimeInterval(120))
            check(tracker.resetLowerBound == nil && tracker.resetUpperBound == nil,
                  "missing, invalid, or expired current-window evidence clears reset continuity")
        }
    }

    static func main() throws {
        calendarChecks()
        try resetChecks()
        print("\(checked) accounting calendar checks passed.")
    }
}
