import Foundation

@main
struct QuotaChecks {
    static func main() throws {
        var checked = 0
        func decode(_ json: String) throws -> QuotaSnapshot {
            try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8))
        }
        func check(_ success: @autoclosure () -> Bool, _ name: String) {
            guard success() else { fatalError("FAILED: " + name) }
            checked += 1
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
        let cards = try decode(#"{"rateLimitResetCredits":{"availableCount":3,"credits":[{"id":"example"}]}}"#)
        check(cards.resetCardCount == 3, "reset count uses availableCount, not the detail list length")
        let unknownCards = try decode(#"{"rateLimitResetCredits":null}"#)
        check(unknownCards.resetCardCount == nil, "unknown reset count stays unavailable")
        let zeroCards = try decode(#"{"rateLimitResetCredits":{"availableCount":0}}"#)
        check(zeroCards.resetCardCount == 0, "zero reset cards is a known value")
        let datedCards = try decode(#"{"rateLimitResetCredits":{"availableCount":3,"credits":[{"expiresAt":300,"status":"available"},{"expiresAt":100,"status":"available"},{"expiresAt":null,"status":"available"},{"expiresAt":50,"status":"used"}]}}"#)
        check(datedCards.resetCards?.count == 3, "only available or unspecified cards appear")
        check(datedCards.resetCards?.first?.expirationDate == Date(timeIntervalSince1970: 100), "cards sorted by earliest expiry")
        check(datedCards.resetCards?.last?.expirationDate == nil, "unknown expiry remains unknown and sorts last")
        check(unknownCards.resetCards == nil, "unavailable card detail is not an empty fetched list")
        let ac = EnergyState()
        var battery = ac; battery.onBattery = true
        var low = battery; low.lowPower = true
        let closed: (EnergyState) -> TimeInterval? = { EnergyPolicy.refreshInterval(menuVisible: false, requestedInterval: 30, state: $0) }
        check(closed(ac) == 120, "closed menu on AC queries every two minutes")
        check(closed(battery) == 300, "closed menu on battery queries every five minutes")
        check(closed(low) == 600, "closed menu in low power queries every ten minutes")
        check(EnergyPolicy.refreshInterval(menuVisible: true, requestedInterval: 30, state: ac) == 30, "open menu keeps requested freshness")
        check(EnergyPolicy.refreshInterval(menuVisible: true, requestedInterval: 15, state: low) == 60, "low power mode limits foreground polling")
        var asleep = ac; asleep.systemSleeping = true
        check(closed(asleep) == nil, "system sleep stops query scheduling")
        asleep = ac; asleep.displaySleeping = true
        check(closed(asleep) == nil, "screen sleep stops query scheduling")
        var offline = ac; offline.networkAvailable = false
        check(closed(offline) == nil, "offline state schedules no queries")
        var inactive = ac; inactive.sessionInactive = true
        check(closed(inactive) == nil, "inactive user session schedules no queries")
        check(EnergyPolicy.refreshInterval(menuVisible: false, requestedInterval: 30, state: ac, failures: 10) == 1800, "repeated failures back off to thirty minutes")
        check(EnergyPolicy.timerTolerance(interval: 300) == 30, "timer coalescing tolerance is applied")
        print("\(checked) checks passed.")
    }
}
