import SwiftUI
import AppKit

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let state = store.state
        let main = state.snapshot?.main
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("Codex 用量").font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle().fill(state.stale ? Color.orange : Color.green).frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(main?.planType?.uppercased() ?? "连接中")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            QuotaSummaryView(main: main, now: state.now)
            ResetCardsView(count: state.snapshot?.resetCardCount, cards: state.snapshot?.resetCards, now: state.now)
            if let error = state.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if main?.spendControlReached == true || main?.rateLimitReachedType != nil {
                Text("账户已触及额度或支出限制").font(.caption2).foregroundStyle(.orange)
            }
            if let others = state.snapshot?.otherBuckets, !others.isEmpty {
                OtherQuotasView(buckets: others)
            }
            Divider()
            HStack(spacing: 6) {
                Button(action: store.refresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }.disabled(state.isRefreshing)
                Spacer(minLength: 4)
                Text(state.updateLabel).font(.caption2).foregroundStyle(.secondary)
                    .help(state.energyDescription)
                Spacer(minLength: 4)
                Button("退出应用") { NSApplication.shared.terminate(nil) }
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
