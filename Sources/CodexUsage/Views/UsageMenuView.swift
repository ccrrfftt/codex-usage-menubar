import SwiftUI
import AppKit

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let state = store.state
        let language = state.language
        let main = state.snapshot?.main
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(language.text(.title)).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(language.toggleTitle, action: store.toggleLanguage)
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered).controlSize(.mini)
                    .help(language.toggleHint)
                    .accessibilityLabel(language.toggleHint)
                Circle().fill(state.stale ? Color.orange : Color.green).frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(main?.planType?.uppercased() ?? language.text(.connecting))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            QuotaSummaryView(main: main, now: state.now, language: language)
            ResetCardsView(count: state.snapshot?.resetCardCount, cards: state.snapshot?.resetCards,
                           now: state.now, language: language)
            if let error = state.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if main?.spendControlReached == true || main?.rateLimitReachedType != nil {
                Text(language.text(.limitReached)).font(.caption2).foregroundStyle(.orange)
            }
            if let others = state.snapshot?.otherBuckets, !others.isEmpty {
                OtherQuotasView(buckets: others, language: language)
            }
            Divider()
            HStack(spacing: 6) {
                Button(action: store.refresh) {
                    Label(language.text(.refresh), systemImage: "arrow.clockwise")
                }.disabled(state.isRefreshing)
                Spacer(minLength: 4)
                Text(state.updateLabel).font(.caption2).foregroundStyle(.secondary)
                    .help(state.energyDescription)
                Spacer(minLength: 4)
                Button(language.text(.quit)) { NSApplication.shared.terminate(nil) }
                    .font(.caption2).buttonStyle(.plain)
                    .keyboardShortcut("q", modifiers: .command)
            }.controlSize(.small)
        }
        .padding(12)
        .frame(width: 276, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}
