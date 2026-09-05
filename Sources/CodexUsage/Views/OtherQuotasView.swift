import SwiftUI

struct OtherQuotasView: View {
    let buckets: [QuotaBucket]
    let language: AppLanguage
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
                    Text(language.text(.otherLimits)).font(.caption)
                    Spacer(minLength: 0)
                    Text(language.itemCount(buckets.count)).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text(.otherLimits))
            .accessibilityValue(language.text(showOthers ? .expanded : .collapsed))
            .accessibilityHint(language.text(.expandHint))
            if showOthers {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(buckets) { bucket in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(bucket.name(in: language).prefix(30))).font(.caption2.weight(.medium))
                            ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                                HStack {
                                    Text(window.period(in: language)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(quotaPercent(window.remaining, language: language)).monospacedDigit()
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
