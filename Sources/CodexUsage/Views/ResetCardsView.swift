import SwiftUI

struct ResetCardsView: View {
    let count: Int?
    let cards: [ResetCard]?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "ticket").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("重置卡到期时间").foregroundStyle(.secondary)
                Spacer()
                Text(count.map { "\($0) 张" } ?? "—")
                    .fontWeight(.medium).monospacedDigit()
            }.font(.caption)
            resetCardDetails
        }
    }

    @ViewBuilder
    private var resetCardDetails: some View {
        if let cards, !cards.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    HStack(alignment: .firstTextBaseline) {
                        Text("第 \(index + 1) 张").foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let expires = card.expirationDate {
                            Text(expires.formatted(.dateTime.year().month().day().hour().minute()))
                                .foregroundStyle(expires <= now ? Color.orange : Color.secondary)
                        } else {
                            Text("未提供到期时间").foregroundStyle(.secondary)
                        }
                    }.font(.caption2)
                }
                if let count, cards.count < count {
                    Text("已返回 \(cards.count)/\(count) 张卡片的到期明细")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else if (count ?? 0) > 0 {
            Text("暂未返回到期明细").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
