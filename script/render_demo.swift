import SwiftUI
import AppKit

struct DemoProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                Capsule().fill(Color.green)
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
            }
        }.frame(height: 5)
    }
}

// Offline documentation fixture. No account, Codex process, network, or preferences are read.
@main @MainActor
struct DemoImage {
    static func main() throws {
        _ = NSApplication.shared
        let fixedNow = Date(timeIntervalSince1970: 1893456000) // 2030-01-01 00:00 UTC
        let data = Data(#"{"rateLimits":{"planType":"demo","primary":{"usedPercent":28,"windowDurationMins":10080,"resetsAt":1893715200}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"status":"available","expiresAt":1896048000},{"status":"available","expiresAt":1898467200}]}}"#.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        let content = VStack(alignment: .leading, spacing: 12) {
            Label("演示数据 · SAMPLE DATA", systemImage: "photo.badge.checkmark")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.blue)
            Divider()
            HStack {
                Text("Codex 用量").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("EN / 中文").font(.system(size: 10)).foregroundStyle(.secondary)
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("DEMO").font(.caption2).foregroundStyle(.secondary)
            }
            QuotaSummaryView(main: snapshot.main, now: fixedNow, language: .chinese)
            ResetCardsView(count: snapshot.resetCardCount, cards: snapshot.resetCards,
                           now: fixedNow, language: .chinese)
            Divider()
            HStack {
                Label("刷新", systemImage: "arrow.clockwise")
                Spacer()
                Text("更新于 08:00:00").foregroundStyle(.secondary)
                Spacer()
                Text("退出应用")
            }.font(.caption2)
            Text("所有数值与日期均为虚构示例")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 308)
        .background(Color(red: 0.94, green: 0.96, blue: 0.99))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(12).background(Color(red: 0.85, green: 0.89, blue: 0.96))
        .environment(\.colorScheme, .light)
        .progressViewStyle(DemoProgressStyle())
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Wrote offline demo image: \(cg.width) × \(cg.height)")
    }
}
