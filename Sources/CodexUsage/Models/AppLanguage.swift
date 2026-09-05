import Foundation

enum AppLanguage: String, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    static let preferenceKey = "displayLanguage"
    static func restored(from value: String?) -> AppLanguage {
        value.flatMap(AppLanguage.init(rawValue:)) ?? .chinese
    }

    var other: AppLanguage { self == .chinese ? .english : .chinese }
    var locale: Locale { self == .chinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US") }
    var toggleTitle: String { self == .chinese ? "EN" : "中文" }
    var toggleHint: String { self == .chinese ? "Switch to English" : "切换为中文" }

    enum Text {
        case title, connecting, remaining, mainLimit, nextReset, resetCards, refresh, quit
        case otherLimits, expanded, collapsed, expandHint, periodUnavailable, resetUnavailable
        case waitingForReset, expiryUnavailable, detailsUnavailable, limitReached, remainingQuota
        case offlineStatus, pausedStatus, syncing, waitingForConnection, previousData, efficientUpdates
        case offlineHelp, pausedHelp, acHelp, batteryHelp, updating, notSynced, statusItemLabel
        case errorUnavailable, errorDisconnected, errorTimedOut, errorAccount, errorMalformed
    }

    func text(_ key: Text) -> String {
        let pair: (String, String)
        switch key {
        case .title: pair = ("Codex 用量", "Codex Usage")
        case .connecting: pair = ("连接中", "Connecting")
        case .remaining: pair = ("剩余", "remaining")
        case .mainLimit: pair = ("主额度", "Main limit")
        case .nextReset: pair = ("下次重置", "Next reset")
        case .resetCards: pair = ("重置卡到期时间", "Reset card expiry")
        case .refresh: pair = ("刷新", "Refresh")
        case .quit: pair = ("退出应用", "Quit")
        case .otherLimits: pair = ("其他额度", "Other limits")
        case .expanded: pair = ("已展开", "Expanded")
        case .collapsed: pair = ("已折叠", "Collapsed")
        case .expandHint: pair = ("点击整行展开或折叠", "Click the row to expand or collapse")
        case .periodUnavailable: pair = ("额度周期未提供", "Period unavailable")
        case .resetUnavailable: pair = ("重置时间未提供", "Reset time unavailable")
        case .waitingForReset: pair = ("等待额度更新", "Waiting for usage update")
        case .expiryUnavailable: pair = ("未提供到期时间", "Expiry unavailable")
        case .detailsUnavailable: pair = ("暂未返回到期明细", "Expiry details unavailable")
        case .limitReached: pair = ("账户已触及额度或支出限制", "Usage or spending limit reached")
        case .remainingQuota: pair = ("剩余额度", "Remaining quota")
        case .offlineStatus: pair = ("离线，联网后更新", "Offline; updates resume when connected")
        case .pausedStatus: pair = ("休眠期间暂停查询", "Updates paused while inactive")
        case .syncing: pair = ("正在同步…", "Syncing…")
        case .waitingForConnection: pair = ("等待连接", "Waiting for connection")
        case .previousData: pair = ("当前显示上次数据", "Showing the last available data")
        case .efficientUpdates: pair = ("智能节能更新", "Automatic updates")
        case .offlineHelp: pair = ("离线时暂停查询，网络恢复后自动更新。", "Updates pause offline and resume when connected.")
        case .pausedHelp: pair = ("屏幕或系统休眠期间暂停查询。", "Updates pause while the screen or system is asleep.")
        case .acHelp: pair = ("已接通电源：每 1 分钟自动更新。", "On AC power: updates every minute.")
        case .batteryHelp: pair = ("使用电池：每 5 分钟自动更新。", "On battery: updates every 5 minutes.")
        case .updating: pair = ("正在更新…", "Updating…")
        case .notSynced: pair = ("尚未同步", "Not synced yet")
        case .statusItemLabel: pair = ("Codex 剩余用量", "Codex remaining quota")
        case .errorUnavailable: pair = ("未找到 Codex，请先安装桌面应用。", "Codex not found. Install the desktop app first.")
        case .errorDisconnected: pair = ("用量连接已中断，稍后自动重试。", "Usage connection lost. Retrying automatically.")
        case .errorTimedOut: pair = ("用量查询超时，请检查网络。", "Usage request timed out. Check your connection.")
        case .errorAccount: pair = ("请确认 Codex 已登录 ChatGPT 账户。", "Check that Codex is signed in to your ChatGPT account.")
        case .errorMalformed: pair = ("暂时无法识别服务返回的用量数据。", "The usage response could not be read.")
        }
        return self == .chinese ? pair.0 : pair.1
    }

    enum PeriodUnit {
        case day, hour, minute
        var names: (String, String) {
            switch self {
            case .day: ("天", "day")
            case .hour: ("小时", "hour")
            case .minute: ("分钟", "minute")
            }
        }
    }

    func period(_ count: Int, unit: PeriodUnit) -> String {
        self == .chinese ? "\(count) \(unit.names.0)额度" : "\(count)-\(unit.names.1) limit"
    }

    func cardCount(_ count: Int) -> String {
        self == .chinese ? "\(count) 张" : "\(count) \(count == 1 ? "card" : "cards")"
    }

    func cardLabel(_ number: Int) -> String {
        self == .chinese ? "第 \(number) 张" : "Card \(number)"
    }

    func itemCount(_ count: Int) -> String {
        self == .chinese ? "\(count) 项" : "\(count) \(count == 1 ? "item" : "items")"
    }

    func partialDetails(_ count: Int, total: Int) -> String {
        self == .chinese ? "已返回 \(count)/\(total) 张卡片的到期明细" : "Expiry details: \(count) of \(total) cards"
    }

    func countdown(days: Int, hours: Int, minutes: Int) -> String {
        if days > 0 { return self == .chinese ? "\(days) 天 \(hours) 小时后" : "in \(days)d \(hours)h" }
        if hours > 0 { return self == .chinese ? "\(hours) 小时 \(minutes) 分钟后" : "in \(hours)h \(minutes)m" }
        return self == .chinese ? "\(max(1, minutes)) 分钟后" : "in \(max(1, minutes))m"
    }

    func dateTime(_ date: Date, includeYear: Bool = false) -> String {
        var style = Date.FormatStyle.dateTime.month().day().hour().minute().locale(locale)
        if includeYear { style = style.year() }
        return date.formatted(style)
    }

    func updatedLabel(_ date: Date, stale: Bool) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(locale))
        if stale { return self == .chinese ? "旧数据 · \(time)" : "Stale · \(time)" }
        return self == .chinese ? "更新于 \(time)" : "Updated \(time)"
    }
}
