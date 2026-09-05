import SwiftUI

struct QuotaSummaryView: View {
    let main: QuotaBucket?
    let now: Date

    var body: some View {
        let headline = main?.headline
        let remaining = headline?.remaining
        let percent = quotaPercent(remaining)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(percent)
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                Text("剩余").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(headline?.period ?? "主额度")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: remaining ?? 0, total: 100)
                .controlSize(.small)
                .tint((remaining ?? 100) <= 20 ? .orange : .green)
                .accessibilityLabel("剩余额度 \(percent)")
            HStack(alignment: .top) {
                Text("下次重置").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(resetCountdown(headline?.resetDate, now: now))
                    if let reset = headline?.resetDate {
                        Text(reset.formatted(.dateTime.month().day().hour().minute()))
                            .foregroundStyle(.secondary)
                    }
                }
            }.font(.caption2)
            if let main {
                ForEach(Array(main.windows.filter { $0 != headline }.enumerated()), id: \.offset) { _, window in
                    HStack {
                        Text(window.period).foregroundStyle(.secondary)
                        Spacer()
                        Text(quotaPercent(window.remaining)).monospacedDigit()
                    }.font(.caption2)
                }
            }
        }
    }
}
