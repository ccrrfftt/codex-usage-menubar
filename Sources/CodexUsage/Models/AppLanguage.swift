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
        case ordinaryUsageUnavailable
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
        case .ordinaryUsageUnavailable: pair = ("常规用量暂不可用，请查看 Codex 用量页面", "Included usage is unavailable. Check usage in Codex.")
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

extension AppLanguage {
    enum AccountingText {
        case usageDetails, tokens, apiEquivalent, today, sinceReset, billingCycle, settings
        case coverageHelp, cycleNotSet, resetNotObserved, actualReset, recentConversations
        case noConversations, untitledConversation, billingDay, notSet, billingHelp
        case historicalReset, historicalResetHelp
        case recordSources, chooseFolders, clearSources, sourcesHelp
        case observedResetInterval, resetIntervalHelp, serviceDateHelp
        case comparisonHelp, trackingHelp, recentTrackingHelp
    }

    func accountingText(_ key: AccountingText) -> String {
        let pair: (String, String)
        switch key {
        case .usageDetails: pair = ("用量明细", "Usage details")
        case .tokens: pair = ("Token", "tokens")
        case .apiEquivalent: pair = ("API 等值 · USD", "API equiv. · USD")
        case .today: pair = ("今日", "Today")
        case .sinceReset: pair = ("上次重置以来", "Since last reset")
        case .billingCycle: pair = ("本订阅周期", "This cycle")
        case .settings: pair = ("统计设置", "Usage settings")
        case .coverageHelp:
            pair = ("统计仅覆盖可读取的用量记录。≥ 为已知下界；≈ 为历史遥测估算；— 为暂不可用。Token 和金额的覆盖范围可能不同。",
                    "Totals cover readable records. ≥ marks a known lower bound, ≈ legacy telemetry estimates, and — unavailable values. Token and price coverage can differ.")
        case .cycleNotSet: pair = ("尚未设置订阅起算日", "Subscription start day is not set")
        case .resetNotObserved:
            pair = ("尚未记录实际额度重置时间，暂不能确定统计起点。", "No actual quota reset has been recorded yet.")
        case .historicalReset: pair = ("历史重置观测", "Historical reset observation")
        case .historicalResetHelp:
            pair = ("根据与当前额度窗口一致的历史快照估计；统计观测点之后的用量。记录未提供精确重置瞬间或历史账户标识。",
                    "Estimated from historical snapshots matching the current limit window. Counts usage after the observation; the exact reset instant and historical account identity are unavailable.")
        case .actualReset: pair = ("重置观测结束", "Reset observation ended")
        case .observedResetInterval: pair = ("观察到的重置区间", "Observed reset interval")
        case .resetIntervalHelp:
            pair = ("重置发生于该区间内，具体时刻未知；仅统计区间结束后的记录。", "The reset occurred within this interval; its exact time is unknown. Only records after its end are counted.")
        case .serviceDateHelp:
            pair = ("服务返回日级 Token，未提供日期时区及模型拆分；日期归属为近似值。", "The service reports daily tokens without a calendar time zone or model breakdown; date attribution is approximate.")
        case .comparisonHelp:
            pair = ("仅在统计覆盖完整周期时，！表示已选记录的 API 等值低于 $200。使用当前 Standard API 单价，未验证账户完整覆盖。",
                    "! appears below $200 only when tracking covers the complete cycle. It compares selected records at current Standard API rates; full-account coverage is unverified.")
        case .trackingHelp:
            pair = ("只累计所选本地根目录及其子目录中，从已保存统计起点开始的用量。首个订阅周期缺少此前日期，覆盖完整周期前不判断是否低于 $200。",
                    "Counts usage in selected local roots and their descendants from the saved tracking start. Earlier days in the first subscription cycle are outside this range, so the below-$200 comparison stays off until a complete cycle is covered.")
        case .recentTrackingHelp:
            pair = ("最近三个对话的数值仅累计统计起点之后的用量，不含更早历史。",
                    "The last three conversation totals accumulate only usage since tracking started, excluding earlier history.")
        case .recentConversations: pair = ("最近 3 个对话", "Last 3 conversations")
        case .noConversations: pair = ("所选来源暂无可统计的对话记录", "No conversation records in the selected sources")
        case .untitledConversation: pair = ("未命名对话", "Untitled conversation")
        case .billingDay: pair = ("每月起算日", "Monthly start day")
        case .notSet: pair = ("未设置", "Not set")
        case .billingHelp:
            pair = ("以本地时区的当日 00:00 起算，并非精确扣费时刻。短月份使用当月最后一天。", "Cycles start at local midnight, not the exact billing time. Short months use their last day.")
        case .recordSources: pair = ("用量记录来源", "Usage record sources")
        case .chooseFolders: pair = ("选择目录…", "Choose folders…")
        case .clearSources: pair = ("清除选择", "Clear selection")
        case .sourcesHelp:
            pair = ("仅累计所选根目录及子目录中，统计起点之后的用量。API 等值不是实际账单；缺少记录不会计为零。", "Counts usage in selected roots and descendants since tracking started. API estimates are not billed charges; missing records are never counted as zero.")
        }
        return self == .chinese ? pair.0 : pair.1
    }

    func accountingCoverage(_ coverage: AccountingCoverage) -> String {
        let pair: (String, String)
        switch coverage {
        case .loading: pair = ("读取中…", "Reading…")
        case .unavailable: pair = ("记录不可用", "Unavailable")
        case .partial: pair = ("部分记录", "Partial coverage")
        case .complete: pair = ("范围内完整", "Complete in scope")
        }
        return self == .chinese ? pair.0 : pair.1
    }

    func accountingScope(source: AccountingTokenSource, folderCount: Int) -> String {
        let pair: (String, String)
        switch source {
        case .account:
            pair = ("服务日期 Token · 无模型拆分", "Service-date tokens · no model breakdown")
        case .local: pair = ("所选本地记录 · API 等值", "Selected local usage · API equivalent")
        case .mixed: pair = ("账户及本地 Token · 所选记录等值", "Account and local tokens · selected records priced")
        case .unavailable: pair = ("尚无可统计记录", "No usage records available")
        }
        return self == .chinese ? pair.0 : pair.1
    }

    func accountingCostHelp(_ metric: AccountingMetricPresentation) -> String {
        guard metric.apiUSD != nil else {
            return self == .chinese ? "缺少可计价记录，API 等值暂不可用。" : "API equivalent is unavailable without priceable records."
        }
        let detail: String
        if metric.isEstimated {
            detail = self == .chinese
                ? "历史遥测估算，可能包含重放或不完整记录，不能视为精确总量或保证下界。"
                : "Legacy telemetry may contain replayed or missing records; this is not an exact total or a guaranteed lower bound."
        } else if metric.costIsPartial {
            detail = self == .chinese ? "仅含可计价记录，尚缺部分用量。" : "Only priceable records are included; some usage is missing."
        } else if metric.costUpperBoundUSD != nil {
            detail = self == .chinese ? "根据适用价格区间估算。" : "Estimated from the applicable price range."
        } else {
            detail = ""
        }
        let ending = self == .chinese
            ? "按当前 Standard API 单价估算，不代表实际账单。"
            : "Estimated at current Standard API rates, not a billed charge."
        return metric.costText() + " USD · " + detail + " " + ending
    }

    func accountingMetricDescription(_ metric: AccountingMetricPresentation) -> String {
        let values = metric.tokenText(in: self, compact: false) + " " + accountingText(.tokens)
            + ", " + accountingText(.apiEquivalent) + " " + metric.costText()
        guard metric.tokensArePartial || metric.costIsPartial else { return values }
        return values + ", " + accountingCoverage(.partial)
    }

    func accountingDateRange(start: Date, end: Date) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale)
        let dates = start.formatted(style) + " → " + end.formatted(style)
        return (self == .chinese ? "订阅周期 · " : "Cycle · ") + dates
    }

    func accountingTrackingStart(_ date: Date) -> String {
        let date = date.formatted(Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale))
        return self == .chinese ? "自 \(date) 统计" : "Tracking since \(date)"
    }

    func accountingDay(_ day: Int) -> String {
        self == .chinese ? "\(day) 日" : "Day \(day)"
    }

    func accountingResetTitle(minutes: Double?) -> String {
        guard let minutes, minutes.isFinite, minutes > 0, minutes < 10_000_000 else { return accountingText(.sinceReset) }
        let count: Int
        let unit: PeriodUnit
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 { count = Int(minutes / 1440); unit = .day }
        else if minutes.truncatingRemainder(dividingBy: 60) == 0 { count = Int(minutes / 60); unit = .hour }
        else if minutes.truncatingRemainder(dividingBy: 1) == 0 { count = Int(minutes); unit = .minute }
        else { return accountingText(.sinceReset) }
        return self == .chinese ? "\(count) \(unit.names.0)额度重置后" : "Since \(count)-\(unit.names.1) reset"
    }

    func accountingConversation(_ number: Int, updatedAt: Date) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute().locale(locale)
        let title = self == .chinese ? "对话 \(number)" : "Chat \(number)"
        return title + " · " + updatedAt.formatted(style)
    }

    func accountingFolderCount(_ count: Int) -> String {
        self == .chinese ? "已选 \(count) 个目录" : "\(count) \(count == 1 ? "folder" : "folders") selected"
    }
}
