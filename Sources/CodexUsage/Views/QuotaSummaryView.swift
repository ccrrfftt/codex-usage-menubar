import SwiftUI

struct QuotaSummaryView: View {
    let main: QuotaBucket?
    let now: Date
    let language: AppLanguage

    var body: some View {
        let headline = main?.headline
        let remaining = headline?.remaining
        let percent = quotaPercent(remaining, language: language)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(percent)
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                Text(language.text(.remaining)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(headline?.period(in: language) ?? language.text(.mainLimit))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: remaining ?? 0, total: 100)
                .controlSize(.small)
                .tint((remaining ?? 100) <= 20 ? .orange : .green)
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
