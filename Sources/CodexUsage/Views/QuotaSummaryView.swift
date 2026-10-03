import SwiftUI

struct QuotaSummaryView: View {
    let main: QuotaBucket?
    let now: Date
    let language: AppLanguage
    var cycleValue: AccountingMetricPresentation = .init()

    var body: some View {
        let headline = main?.headline
        let remaining = headline?.remaining
        let percent = quotaPercent(remaining, language: language)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(percent)
                        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(language.text(.remaining) + " · " + (headline?.period(in: language) ?? language.text(.mainLimit)))
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cycleValue.menuCostText())
                        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .help(language.accountingCostHelp(cycleValue))
                    Text(language == .chinese ? "本周期 API 等值" : "Cycle API equivalent")
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            ProgressView(value: remaining ?? 0, total: 100)
                .controlSize(.small)
                .tint((remaining ?? 100) < 15 ? .red : .green)
                .accessibilityLabel("\(language.text(.remainingQuota)) \(percent)")
            HStack(alignment: .top) {
                Text(language.text(.nextReset)).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(resetCountdown(headline?.resetDate, now: now, language: language))
                    if let reset = headline?.resetDate {
                        Text(language.dateTime(reset))
                            .foregroundStyle(.secondary)
                    }
                }
            }.font(.caption2)
            if let main {
                ForEach(Array(main.windows.filter { $0 != headline }.enumerated()), id: \.offset) { _, window in
                    HStack {
                        Text(window.period(in: language)).foregroundStyle(.secondary)
                        Spacer()
                        Text(quotaPercent(window.remaining, language: language)).monospacedDigit()
                    }.font(.caption2)
                }
            }
        }
    }
}
