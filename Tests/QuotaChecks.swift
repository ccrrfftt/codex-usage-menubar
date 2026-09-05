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
        check(mapped.main?.headline?.remaining == 82 && mapped.main?.headline?.period() == "7 天额度", "multi-bucket precedence and actual period")
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
        let identifiers = try decode(#"{"rateLimitsByLimitId":{"spark":{"limitId":"codex","primary":{"usedPercent":30}},"codex":{"primary":{"usedPercent":20}},"other":{"primary":{"usedPercent":40}}}}"#)
        check(identifiers.main?.id == "codex" && identifiers.otherBuckets.map(\.id) == ["other", "spark"], "map keys provide stable authoritative bucket IDs")
        let malformedLegacy = try decode(#"{"rateLimits":"obsolete","rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20}}}}"#)
        check(malformedLegacy.main?.headline?.remaining == 80, "unused legacy data cannot break a valid modern response")
        check(QuotaWindow(usedPercent: .infinity, windowDurationMins: 1e30, resetsAt: nil).period() == "额度周期未提供", "oversized periods cannot trap integer conversion")
        check(resetCountdown(Date(timeIntervalSince1970: 1e30)) == "重置时间未提供", "oversized reset dates cannot trap integer conversion")
        let ac = EnergyState()
        var battery = ac; battery.onBattery = true
        let cadence: (EnergyState) -> TimeInterval? = { EnergyPolicy.refreshInterval(state: $0) }
        check(cadence(ac) == 60, "AC queries every minute independently of the panel")
        check(cadence(battery) == 300, "battery queries every five minutes independently of the panel")
        check(EnergyPolicy.refreshInterval(state: ac, failures: 1) == 120, "AC query failure doubles retry delay")
        check(EnergyPolicy.refreshInterval(state: battery, failures: 1) == 600, "battery query failure doubles retry delay")
        var asleep = ac; asleep.systemSleeping = true
        check(cadence(asleep) == nil, "system sleep stops query scheduling")
        asleep = ac; asleep.displaySleeping = true
        check(cadence(asleep) == nil, "screen sleep stops query scheduling")
        var offline = ac; offline.networkAvailable = false
        check(cadence(offline) == nil, "offline state schedules no queries")
        var inactive = ac; inactive.sessionInactive = true
        check(cadence(inactive) == nil, "inactive user session schedules no queries")
        check(EnergyPolicy.refreshInterval(state: ac, failures: 10) == 1800, "AC failures back off to thirty minutes")
        check(EnergyPolicy.refreshInterval(state: battery, failures: 10) == 1800, "battery failures back off to thirty minutes")
        check(EnergyPolicy.timerTolerance(interval: 300) == 30, "timer coalescing tolerance is applied")
        check(AppLanguage.restored(from: "en") == .english && AppLanguage.restored(from: nil) == .chinese && AppLanguage.restored(from: "invalid") == .chinese, "language preference restores safely with a Chinese default")
        check(AppLanguage.chinese.other.other == .chinese, "one-click language toggle is reversible")
        check(mapped.main?.headline?.period(in: .english) == "7-day limit", "English quota period uses the actual window length")
        check(quotaPercent(79.5, language: .english) == "79.5%" && quotaPercent(nil, language: .english) == "—", "English formatting preserves fractional and missing quota")
        let reference = Date(timeIntervalSince1970: 1000)
        check(resetCountdown(reference.addingTimeInterval(26 * 3600), now: reference, language: .english) == "in 1d 2h", "English reset countdown preserves the duration")
        check(resetCountdown(reference, now: reference, language: .english) == "Waiting for usage update", "English expired-reset state does not invent fresh quota")
        let exampleDate = ISO8601DateFormatter().date(from: "2026-09-21T00:23:00Z")!
        check(AppLanguage.english.dateTime(exampleDate, includeYear: true).contains("Sep") && AppLanguage.chinese.dateTime(exampleDate, includeYear: true).contains("年"), "date language follows the app rather than the system locale")
        check(AppLanguage.english.cardCount(1) == "1 card" && AppLanguage.english.cardCount(3) == "3 cards", "English reset-card counts have correct singular and plural")
        let englishError = UsageState(lastError: .timedOut, language: .english)
        check(englishError.errorMessage == "Usage request timed out. Check your connection.", "stored error type can render in English without another request")
        check(englishError.statusItem.accessibilityLabel == "Codex remaining quota" && englishError.energyDescription == "On AC power: updates every minute.", "menu-bar accessibility and power help follow the language")
        print("\(checked) checks passed.")
    }
}
