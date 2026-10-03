import Foundation

@main
struct RecordedResetChecks {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ title: String) {
            precondition(value(), "FAILED: " + title)
            count += 1
            print("PASS: " + title)
        }
        func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
        func point(_ time: Double, _ used: Double, _ reset: Double, minutes: Double = 10080) -> RecordedQuotaObservation {
            .init(timestamp: date(time), window: .init(usedPercent: used, windowDurationMins: minutes, resetsAt: reset))
        }
        var live = AccountingResetTracker()
        live.observe(accountID: "synthetic-account", window: .init(usedPercent: 12, windowDurationMins: 10080, resetsAt: 3000), at: date(2100))
        let history = [point(900, 80, 1000), point(1100, 2, 3000), point(2000, 10, 3000)]
        check(RecordedResetInference.upperBound(observations: history, current: live, now: date(2100)) == date(1100),
              "historical quota change bootstraps a reset observation for the current live window")
        check(live.resetUpperBound == nil, "historical inference does not invent a live reset observation")
        check(RecordedResetInference.upperBound(observations: Array(history.reversed()), current: live, now: date(2100)) == date(1100),
              "cross-conversation historical observations are ordered chronologically")
        check(RecordedResetInference.upperBound(observations: [history[1], history[2]], current: live, now: date(2100)) == nil,
              "a single new-window snapshot cannot establish a previous reset")
        check(RecordedResetInference.upperBound(observations: [point(900, 1, 1000), point(1100, 2, 3000)], current: live, now: date(2100)) == nil,
              "a changed reset schedule without a usage drop is not treated as a reset")
        check(RecordedResetInference.upperBound(observations: history + [point(2050, 1, 3000)], current: live, now: date(2100)) == date(1100),
              "replayed same-window headers do not erase a previously observed reset")
        check(RecordedResetInference.upperBound(observations: history + [point(2050, 90, 2100)], current: live, now: date(2100)) == date(1100),
              "a late older-window header cannot replace the newer quota window")
        check(RecordedResetInference.upperBound(observations: history + [point(2200, 1, 5000)], current: live, now: date(2100)) == date(1100),
              "future observations do not influence current-period inference")
        check(RecordedResetInference.upperBound(observations: history.map { point($0.timestamp.timeIntervalSince1970, $0.window.usedPercent!, $0.window.resetsAt!, minutes: 300) }, current: live, now: date(2100)) == nil,
              "a different quota period cannot supply the displayed reset boundary")
        var changed = AccountingResetTracker()
        changed.observe(accountID: "synthetic-account", window: .init(usedPercent: 1, windowDurationMins: 10080, resetsAt: 5000), at: date(2100))
        check(RecordedResetInference.upperBound(observations: history, current: changed, now: date(2100)) == nil,
              "history that does not end in the current live window remains unavailable")
        check(RecordedResetInference.upperBound(observations: history, current: .init(), now: date(2100)) == nil,
              "missing live account/window context cannot adopt unrelated history")
        let payload = try JSONDecoder().decode(RecordedQuotaSnapshotPayload.self, from: Data(#"{"limit_id":"codex","primary":{"used_percent":20,"window_minutes":300,"resets_at":2500},"secondary":{"used_percent":70,"window_minutes":10080,"resets_at":3000}}"#.utf8))
        check(payload.observation(at: date(2100))?.window.windowDurationMins == 10080,
              "history tracks the longest Codex main allowance consistently with live monitoring")
        let other = try JSONDecoder().decode(RecordedQuotaSnapshotPayload.self, from: Data(#"{"limit_id":"other-model","primary":{"used_percent":20,"window_minutes":300,"resets_at":2500}}"#.utf8))
        check(other.observation(at: date(2100)) == nil, "separate model allowances cannot seed the Codex reset")
        let missing = try JSONDecoder().decode(RecordedQuotaSnapshotPayload.self, from: Data(#"{"primary":{"used_percent":20,"window_minutes":300,"resets_at":2500}}"#.utf8))
        check(missing.observation(at: date(2100)) == nil, "unidentified legacy quota remains unattributed")
        check(payload.observation(at: date(4000)) == nil, "already-expired replayed snapshots cannot fabricate a current reset")
        var scheduled = AccountingResetTracker()
        scheduled.observe(accountID: "synthetic", window: .init(usedPercent: 20, windowDurationMins: 300, resetsAt: 100_000), at: date(90_000))
        check(RecordedResetInference.scheduledStart(current: scheduled, now: date(90_000)) == date(82_000),
              "fallback estimates only the start of a currently active schedule window")
        check(RecordedResetInference.scheduledStart(current: scheduled, now: date(100_001)) == nil,
              "an expired schedule cannot provide an estimated current reset")
        check(RecordedResetInference.scheduledStart(current: scheduled, now: date(80_000)) == nil,
              "a calculated future window start is rejected")
        check(RecordedResetInference.scheduledStart(current: .init(), now: date(90_000)) == nil,
              "missing quota context remains unavailable rather than copying today's total")
        print("\(count) recorded reset checks passed.")
    }
}
