import SwiftUI

struct ResetCardsView: View {
    let count: Int?
    let cards: [ResetCard]?
    let now: Date
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "ticket").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(language.text(.resetCards)).foregroundStyle(.secondary)
                Spacer()
                Text(count.map(language.cardCount) ?? "—")
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
                        Text(language.cardLabel(index + 1)).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let expires = card.expirationDate {
                            Text(language.dateTime(expires, includeYear: true))
                                .foregroundStyle(expires <= now ? Color.orange : Color.secondary)
                        } else {
                            Text(language.text(.expiryUnavailable)).foregroundStyle(.secondary)
                        }
                    }.font(.caption2)
                }
                if let count, cards.count < count {
                    Text(language.partialDetails(cards.count, total: count))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else if (count ?? 0) > 0 {
            Text(language.text(.detailsUnavailable)).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
