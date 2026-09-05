import SwiftUI

struct OtherQuotasView: View {
    let buckets: [QuotaBucket]
    @State private var showOthers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showOthers.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showOthers ? 90 : 0))
                        .frame(width: 10)
                    Text("其他额度").font(.caption)
                    Spacer(minLength: 0)
                    Text("\(buckets.count) 项").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("其他额度")
            .accessibilityValue(showOthers ? "已展开" : "已折叠")
            .accessibilityHint("点击整行展开或折叠")
            if showOthers {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(buckets) { bucket in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(bucket.name.prefix(30))).font(.caption2.weight(.medium))
                            ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                                HStack {
                                    Text(window.period).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(quotaPercent(window.remaining)).monospacedDigit()
                                }.font(.caption2)
                            }
                        }
                    }
                }
                .padding(.leading, 15)
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

}
