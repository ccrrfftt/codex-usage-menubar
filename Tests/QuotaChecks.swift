import Foundation

@main
struct QuotaChecks {
    static func main() throws {
        func decode(_ json: String) throws -> QuotaSnapshot {
            try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8))
        }
        func check(_ success: @autoclosure () -> Bool, _ name: String) {
            guard success() else { fatalError("FAILED: " + name) }
            print("PASS: " + name)
        }
        let mapped = try decode(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":18,"windowDurationMins":10080}}}}"#)
        check(mapped.main?.headline?.remaining == 82 && mapped.main?.headline?.period == "7 天额度", "multi-bucket precedence and actual period")
        let missing = try decode(#"{"rateLimits":{"primary":{"usedPercent":null},"secondary":null}}"#)
        check(missing.main?.headline?.remaining == nil && quotaPercent(missing.main?.headline?.remaining) == "—", "null is unavailable, not full quota")
        let multiple = try decode(#"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300},"secondary":{"usedPercent":65,"windowDurationMins":10080}}}"#)
        check(multiple.main?.headline?.remaining == 35 && multiple.main?.windows.count == 2, "most restrictive window wins")
        for (used, expected) in [(130.0, 0.0), (-5.0, 100.0), (20.5, 79.5)] {
            check(QuotaWindow(usedPercent: used, windowDurationMins: nil, resetsAt: nil).remaining == expected, "clamped remaining for usage \(used)")
        }
        let expired = QuotaWindow(usedPercent: 88, windowDurationMins: 10080, resetsAt: 100)
        check(expired.remaining == 12 && resetCountdown(expired.resetDate, now: Date(timeIntervalSince1970: 200)) == "等待额度更新", "elapsed reset does not invent a new allowance")
        let noMain = try decode(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"spark":{"limitId":"spark","primary":{"usedPercent":0}}}}"#)
        check(noMain.main == nil, "no substitution of unrelated or legacy quota")
        print("8 quota checks passed.")
    }
}
