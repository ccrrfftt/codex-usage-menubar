import SwiftUI
import AppKit

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore
    @State private var showOthers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Codex 用量").font(.headline)
                Spacer()
                Text(store.main?.planType?.uppercased() ?? "").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Circle().fill(store.stale ? Color.orange : Color.green).frame(width: 5, height: 5)
                Text(store.status).font(.caption).foregroundStyle(.secondary)
            }
            quotaSummary
            if let error = store.lastError {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if store.main?.spendControlReached == true || store.main?.rateLimitReachedType != nil {
                Text("账户已触及额度或支出限制").font(.caption).foregroundStyle(.orange)
            }
            if let others = store.snapshot?.buckets.filter({ $0.id != "codex" }), !others.isEmpty {
                DisclosureGroup("其他额度", isExpanded: $showOthers) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(others) { bucket in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(bucket.name.prefix(30))).font(.caption.weight(.medium))
                                ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                                    HStack {
                                        Text(window.period).foregroundStyle(.secondary)
                                        Spacer()
                                        Text(quotaPercent(window.remaining)).monospacedDigit()
                                    }.font(.caption)
                                }
                            }
                        }
                    }.padding(.top, 8)
                }.font(.caption)
            }
            Divider()
            HStack {
                Button { Task { await store.refresh() } } label: {
                    Label("立即刷新", systemImage: "arrow.clockwise")
                }.disabled(store.isRefreshing)
                Spacer()
                Button(store.paused ? "继续" : "暂停") { store.togglePause() }
            }.controlSize(.small)
            HStack {
                Text("自动更新").foregroundStyle(.secondary)
                Spacer()
                Picker("自动更新间隔", selection: $store.interval) {
                    Text("15 秒").tag(15)
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                }.labelsHidden().frame(width: 83)
            }.font(.caption).controlSize(.small)
            Button("在访达中显示应用") {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }.font(.caption).buttonStyle(.plain)
            Divider()
            HStack {
                if let updated = store.updatedAt {
                    Text("同步于 \(updated.formatted(date: .omitted, time: .standard))")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("尚未同步").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("退出应用") { store.stop(); NSApplication.shared.terminate(nil) }
                    .font(.caption).buttonStyle(.plain)
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(17)
        .frame(width: 292)
    }

    private var quotaSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.main?.headline?.period ?? "Codex 主额度").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(quotaPercent(store.remaining)).font(.system(size: 35, weight: .medium, design: .rounded)).monospacedDigit()
                Text("剩余可用").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: store.remaining ?? 0, total: 100)
                .tint((store.remaining ?? 100) <= 20 ? .orange : .green)
                .accessibilityLabel("剩余额度 \(quotaPercent(store.remaining))")
            HStack(alignment: .top) {
                Text("下次重置").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(resetCountdown(store.main?.headline?.resetDate, now: store.now))
                    if let reset = store.main?.headline?.resetDate {
                        Text(reset.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.font(.caption)
            if let main = store.main {
                ForEach(Array(main.windows.filter { $0 != main.headline }.enumerated()), id: \.offset) { _, window in
                    HStack {
                        Text(window.period).foregroundStyle(.secondary)
                        Spacer()
                        Text(quotaPercent(window.remaining)).monospacedDigit()
                    }.font(.caption)
                }
            }
        }
    }
}
