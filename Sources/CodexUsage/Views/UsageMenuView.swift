import SwiftUI
import AppKit

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore
    @State private var showOthers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("Codex 用量").font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle().fill(store.stale ? Color.orange : Color.green).frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(store.main?.planType?.uppercased() ?? "连接中")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            quotaSummary
            HStack(spacing: 5) {
                Image(systemName: "ticket").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("重置卡到期时间").foregroundStyle(.secondary)
                Spacer()
                Text(store.snapshot?.resetCardCount.map { "\($0) 张" } ?? "—")
                    .fontWeight(.medium).monospacedDigit()
            }.font(.caption)
            resetCardDetails
            if let error = store.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.main?.spendControlReached == true || store.main?.rateLimitReachedType != nil {
                Text("账户已触及额度或支出限制").font(.caption2).foregroundStyle(.orange)
            }
            if let others = store.snapshot?.buckets.filter({ $0.id != "codex" }), !others.isEmpty {
                otherQuotas(others)
            }
            Divider()
            HStack(spacing: 6) {
                Button { Task { await store.refresh() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }.disabled(store.isRefreshing)
                Spacer(minLength: 4)
                Text("查看时").font(.caption2).foregroundStyle(.secondary)
                Picker("自动更新间隔", selection: $store.interval) {
                    Text("15 秒").tag(15)
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                }.labelsHidden().frame(width: 71)
                    .help(store.energyDescription)
            }.controlSize(.small)
            HStack {
                Text(updateLabel).font(.caption2).foregroundStyle(.secondary)
                    .help(store.energyDescription)
                Spacer()
                Button("退出应用") { store.stop(); NSApplication.shared.terminate(nil) }
                    .font(.caption2).buttonStyle(.plain)
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(12)
        .frame(width: 276, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var updateLabel: String {
        if store.isRefreshing { return "正在更新…" }
        guard let updated = store.updatedAt else { return "尚未同步" }
        let time = updated.formatted(date: .omitted, time: .standard)
        return store.stale ? "旧数据 · \(time)" : "更新于 \(time)"
    }

    @ViewBuilder
    private var resetCardDetails: some View {
        if let cards = store.snapshot?.resetCards, !cards.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    HStack(alignment: .firstTextBaseline) {
                        Text("第 \(index + 1) 张").foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let expires = card.expirationDate {
                            Text(expires.formatted(.dateTime.year().month().day().hour().minute()))
                                .foregroundStyle(expires <= store.now ? Color.orange : Color.secondary)
                        } else {
                            Text("未提供到期时间").foregroundStyle(.secondary)
                        }
                    }.font(.caption2)
                }
                if let count = store.snapshot?.resetCardCount, cards.count < count {
                    Text("已返回 \(cards.count)/\(count) 张卡片的到期明细")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else if (store.snapshot?.resetCardCount ?? 0) > 0 {
            Text("暂未返回到期明细").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func otherQuotas(_ buckets: [QuotaBucket]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { showOthers.toggle() }
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
                .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quotaSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(quotaPercent(store.remaining))
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                Text("剩余").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(store.main?.headline?.period ?? "主额度")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: store.remaining ?? 0, total: 100)
                .controlSize(.small)
                .tint((store.remaining ?? 100) <= 20 ? .orange : .green)
                .accessibilityLabel("剩余额度 \(quotaPercent(store.remaining))")
            HStack(alignment: .top) {
                Text("下次重置").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(resetCountdown(store.main?.headline?.resetDate, now: store.now))
                    if let reset = store.main?.headline?.resetDate {
                        Text(reset.formatted(.dateTime.month().day().hour().minute()))
                            .foregroundStyle(.secondary)
                    }
                }
            }.font(.caption2)
            if let main = store.main {
                ForEach(Array(main.windows.filter { $0 != main.headline }.enumerated()), id: \.offset) { _, window in
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
