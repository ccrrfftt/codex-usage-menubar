import SwiftUI

struct UsageAccountingView: View {
    let presentation: AccountingPresentation
    let language: AppLanguage
    let setBillingDay: @MainActor @Sendable (Int) -> Void
    let chooseFolders: @MainActor @Sendable () -> Void
    let clearFolders: @MainActor @Sendable () -> Void
    @State private var showsConversations: Bool
    @State private var showsSettings = false

    init(presentation: AccountingPresentation, language: AppLanguage,
         setBillingDay: @escaping @MainActor @Sendable (Int) -> Void, chooseFolders: @escaping @MainActor @Sendable () -> Void,
         clearFolders: @escaping @MainActor @Sendable () -> Void, initiallyShowsConversations: Bool = false) {
        self.presentation = presentation
        self.language = language
        self.setBillingDay = setBillingDay
        self.chooseFolders = chooseFolders
        self.clearFolders = clearFolders
        _showsConversations = State(initialValue: initiallyShowsConversations)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            Grid(horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Color.clear.frame(height: 1).gridCellUnsizedAxes(.vertical)
                    Text(language.accountingText(.tokens)).gridColumnAlignment(.trailing)
                    Text(language.accountingText(.apiEquivalent)).gridColumnAlignment(.trailing)
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                metricRow(.today, metric: presentation.today)
                metricRow(.sinceReset, metric: presentation.sinceReset)
                metricRow(.billingCycle, metric: presentation.cycle, emphasized: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cycleLabel).fixedSize(horizontal: false, vertical: true)
                if let start = presentation.trackingStartedAt {
                    Spacer(minLength: 0)
                    Text(language.accountingTrackingStart(start))
                        .fixedSize(horizontal: true, vertical: false)
                        .help(language.dateTime(start, includeYear: true) + "\n"
                            + language.accountingText(.trackingHelp))
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)

            conversations
            Text(language.accountingScope(source: presentation.tokenSource,
                                          folderCount: presentation.sourceFolderCount))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help(language.accountingText(.coverageHelp))
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(language.accountingText(.usageDetails))
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 0)
            Text(language.accountingCoverage(presentation.coverage))
                .font(.system(size: 10))
                .foregroundStyle(presentation.coverage == .partial ? Color.orange : Color.secondary)
                .help(language.accountingText(.coverageHelp))
            Button { showsSettings.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(language.accountingText(.settings))
            .accessibilityLabel(language.accountingText(.settings))
            .popover(isPresented: $showsSettings, arrowEdge: .trailing) {
                AccountingSettingsView(presentation: presentation, language: language,
                                       setBillingDay: { day in setBillingDay(day) },
                                       chooseFolders: { chooseFolders() },
                                       clearFolders: { clearFolders() })
            }
        }
    }

    private func metricRow(_ title: AppLanguage.AccountingText,
                           metric: AccountingMetricPresentation, emphasized: Bool = false) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title == .sinceReset ? language.accountingResetTitle(minutes: presentation.resetWindowMinutes) : language.accountingText(title))
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
                .help(title == .sinceReset ? resetHelp : language.accountingText(title))
            Text(metric.tokenText(in: language))
                .monospacedDigit()
                .help(tokenHelp(metric, title: title))
            Text(metric.costText(compact: true))
                .monospacedDigit()
                .help(language.accountingCostHelp(metric) + (title == .billingCycle
                    ? "\n" + language.accountingText(.comparisonHelp) : ""))
        }
        .font(.system(size: 11, weight: emphasized ? .semibold : .regular))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title == .sinceReset ? language.accountingResetTitle(minutes: presentation.resetWindowMinutes) : language.accountingText(title))
        .accessibilityValue(language.accountingMetricDescription(metric))
    }

    private var cycleLabel: String {
        guard let start = presentation.cycleStart, let end = presentation.cycleEnd else {
            return language.accountingText(.cycleNotSet)
        }
        return language.accountingDateRange(start: start, end: end)
    }

    private var resetHelp: String {
        guard let reset = presentation.lastReset else { return language.accountingText(.resetNotObserved) }
        let window = QuotaWindow(usedPercent: nil, windowDurationMins: presentation.resetWindowMinutes, resetsAt: nil)
        let period = presentation.resetWindowMinutes == nil ? "" : window.period(in: language) + " · "
        if presentation.lastResetFromSchedule {
            return period + language.accountingText(.scheduledReset) + " · " + language.dateTime(reset) + "\n"
                + language.accountingText(.scheduledResetHelp)
        }
        if presentation.lastResetFromHistory {
            return period + language.accountingText(.historicalReset) + " · " + language.dateTime(reset) + "\n"
                + language.accountingText(.historicalResetHelp)
        }
        if let lower = presentation.lastResetLowerBound {
            return period + language.accountingText(.observedResetInterval) + " · "
                + language.dateTime(lower) + " → " + language.dateTime(reset) + "\n"
                + language.accountingText(.resetIntervalHelp)
        }
        return period + language.accountingText(.actualReset) + " · " + language.dateTime(reset)
    }

    private func tokenHelp(_ metric: AccountingMetricPresentation, title: AppLanguage.AccountingText) -> String {
        let count = metric.tokenText(in: language, compact: false) + " " + language.accountingText(.tokens)
        if title == .sinceReset { return count + "\n" + resetHelp }
        if presentation.tokenSource == .account { return count + "\n" + language.accountingText(.serviceDateHelp) }
        return count
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showsConversations.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showsConversations ? 90 : 0))
                        .frame(width: 10)
                    Text(language.accountingText(.recentConversations))
                        .font(.system(size: 11))
                    Spacer(minLength: 0)
                    Text("\(min(3, presentation.conversations.count))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.accountingText(.recentConversations))
            .accessibilityValue(language.text(showsConversations ? .expanded : .collapsed))
            .accessibilityHint(language.text(.expandHint) + " " + language.accountingText(.recentTrackingHelp))
            .help(language.accountingText(.recentTrackingHelp))
            if showsConversations {
                if presentation.conversations.isEmpty {
                    Text(language.accountingText(.noConversations))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 15)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(presentation.conversations.prefix(3)) { conversation in
                            conversationRow(conversation)
                        }
                    }.padding(.leading, 15)
                }
            }
        }
    }

    private func conversationRow(_ conversation: AccountingConversationPresentation) -> some View {
        let title = conversation.title.isEmpty ? language.accountingText(.untitledConversation) : conversation.title
        return VStack(alignment: .leading, spacing: 2) {
            Text(title.count > 30 ? String(title.prefix(29)) + "…" : title)
                .font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                .help(title)
            HStack(spacing: 8) {
                Text(conversation.metric.tokenText(in: language) + " " + language.accountingText(.tokens))
                Spacer(minLength: 0)
                Text(conversation.metric.costText(compact: true))
            }
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            .help(language.accountingCostHelp(conversation.metric) + "\n"
                + language.accountingText(.recentTrackingHelp))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(language.accountingMetricDescription(conversation.metric))
    }
}

private struct AccountingSettingsView: View {
    let presentation: AccountingPresentation
    let language: AppLanguage
    let setBillingDay: @MainActor @Sendable (Int) -> Void
    let chooseFolders: @MainActor @Sendable () -> Void
    let clearFolders: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.accountingText(.settings)).font(.system(size: 12, weight: .semibold))
            Picker(language.accountingText(.billingDay), selection: Binding(
                get: { presentation.billingDay ?? 0 }, set: { day in setBillingDay(day) })) {
                Text(language.accountingText(.notSet)).tag(0)
                ForEach(1...31, id: \.self) { day in
                    Text(language.accountingDay(day)).tag(day)
                }
            }
            .pickerStyle(.menu).controlSize(.small)
            Text(language.accountingText(.billingHelp))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(language.accountingText(.recordSources)).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(language.accountingFolderCount(presentation.sourceFolderCount))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Button(language.accountingText(.chooseFolders), action: chooseFolders)
                Spacer(minLength: 0)
                Button(language.accountingText(.clearSources), action: clearFolders)
                    .disabled(presentation.sourceFolderCount == 0)
            }.controlSize(.small)
            Text(language.accountingText(.sourcesHelp))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 278, alignment: .leading)
    }
}
