import SwiftUI
import AppKit

// Offline layout fixtures only. No accounts, Codex process, network, preference
// store, folder enumeration, or user conversations are read by this executable.
@main @MainActor
struct DemoImage {
    static let fixedNow = fixedDate("2030-10-03T12:00:00Z")

    static func fixedDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: [
            "rateLimits": ["planType": "demo", "primary": ["usedPercent": 28, "windowDurationMins": 10_080,
                "resetsAt": fixedNow.addingTimeInterval(3 * 86_400).timeIntervalSince1970]],
            "rateLimitResetCredits": ["availableCount": 2, "credits": [
                ["status": "available", "expiresAt": fixedNow.addingTimeInterval(30 * 86_400).timeIntervalSince1970],
                ["status": "available", "expiresAt": fixedNow.addingTimeInterval(60 * 86_400).timeIntervalSince1970]
            ]]
        ])
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        for language in [AppLanguage.chinese, .english] {
            for dark in [false, true] {
                let fixture = accountingFixture(language: language, partial: !dark)
                let localeName = language == .chinese ? "zh" : "en"
                let appearanceName = dark ? "dark" : "light"
                let panel = panel(snapshot: snapshot, accounting: fixture, language: language, dark: dark)
                try render(panel, to: output.appendingPathComponent("panel-\(localeName)-\(appearanceName).png"), dark: dark)
                if language == .chinese && !dark {
                    try render(panel, to: output.appendingPathComponent("screenshot.png"), dark: dark)
                }
            }
        }
        for dark in [false, true] {
            let strip = statusBoundaryStrip(dark: dark)
            try render(strip, to: output.appendingPathComponent("status-boundaries-\(dark ? "dark" : "light").png"), dark: dark)
        }
    }

    static func accountingFixture(language: AppLanguage, partial: Bool) -> AccountingPresentation {
        let titles = language == .chinese
            ? ["菜单栏布局示例", "合成数据解析测试", "文档排版与可读性示例"]
            : ["Menu bar layout example", "Synthetic parsing checks", "Documentation readability example"]
        let totals: [AccountingMetricPresentation] = [
            .init(tokens: 1_280_400, apiUSD: 12.75, costUpperBoundUSD: 13.10),
            .init(tokens: partial ? 1_280_400 : 4_926_220, apiUSD: partial ? 12.75 : 44.60,
                  tokensArePartial: true, costIsPartial: true),
            .init(tokens: partial ? 1_280_400 : 21_780_500, apiUSD: partial ? 12.75 : 148.72,
                  tokensArePartial: partial, costIsPartial: partial)
        ]
        return AccountingPresentation(
            today: totals[0], sinceReset: totals[1], cycle: totals[2],
            conversations: titles.enumerated().map { index, title in
                AccountingConversationPresentation(id: "fixture-\(index)", title: title,
                    updatedAt: fixedNow.addingTimeInterval(-Double(index * 3600)),
                    metric: .init(tokens: Int64(248_600 + index * 174_820),
                                  apiUSD: 2.35 + Double(index) * 1.47))
            },
            coverage: partial ? .partial : .complete, tokenSource: .local, billingDay: 5,
            cycleStart: fixedDate("2030-09-05T00:00:00Z"),
            cycleEnd: fixedDate("2030-10-05T00:00:00Z"),
            lastReset: fixedNow.addingTimeInterval(-4 * 86_400),
            lastResetLowerBound: fixedNow.addingTimeInterval(-4 * 86_400 - 60),
            resetWindowMinutes: 10_080, sourceFolderCount: 1,
            canCompareSelectedCycle: !partial,
            trackingStartedAt: fixedDate(partial ? "2030-10-03T00:00:00Z" : "2030-09-05T00:00:00Z"))
    }

    static func panel(snapshot: QuotaSnapshot, accounting: AccountingPresentation,
                      language: AppLanguage, dark: Bool) -> some View {
        let status = status(remaining: 72, value: accounting.cycle.costText(),
                            warning: accounting.canCompareSelectedCycle
                                && (accounting.cycle.costUpperBoundUSD ?? accounting.cycle.apiUSD ?? .infinity) < 200)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language == .chinese ? "离线合成示例" : "OFFLINE SYNTHETIC FIXTURE")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Image(nsImage: statusImage(state: status, dark: dark))
            }
            Divider()
            HStack(spacing: 5) {
                Text(language.text(.title)).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(language.toggleTitle).font(.system(size: 10, weight: .medium))
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("DEMO").font(.caption2).foregroundStyle(.secondary)
            }
            QuotaSummaryView(main: snapshot.main, now: fixedNow, language: language)
            ResetCardsView(count: snapshot.resetCardCount, cards: snapshot.resetCards,
                           now: fixedNow, language: language)
            Divider()
            UsageAccountingView(presentation: accounting, language: language,
                                setBillingDay: { _ in }, chooseFolders: {}, clearFolders: {},
                                initiallyShowsConversations: true)
            Divider()
            HStack(spacing: 6) {
                Label(language.text(.refresh), systemImage: "arrow.clockwise")
                Spacer(minLength: 4)
                Text(language == .chinese ? "更新于 00:00:00" : "Updated 00:00:00").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(language.text(.quit))
            }.font(.caption2)
            Text(language == .chinese ? "所有数值与对话均为虚构；非交互截图。" : "Fictional values and conversations; not an interactive capture.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(12).frame(width: 312, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(12).background(Color(nsColor: .underPageBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    static func status(remaining: Double?, value: String, warning: Bool = false) -> StatusItemState {
        StatusItemState(title: remaining.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))%" } ?? "—",
                        ring: QuotaRingState(remaining: remaining, showsValueWarning: warning),
                        valueTitle: value, tooltip: "Synthetic fixture", accessibilityLabel: "Synthetic fixture",
                        accessibilityValue: value)
    }

    static func statusBoundaryStrip(dark: Bool) -> some View {
        let values: [(String, StatusItemState)] = [
            ("14.9% · red", status(remaining: 14.9, value: "$148.72", warning: true)),
            ("15% · normal", status(remaining: 15, value: "$148.72", warning: true)),
            ("Partial value", status(remaining: 72, value: "≥$174.30")),
            ("Unavailable", status(remaining: nil, value: "$—"))
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("OFFLINE NATIVE LABEL FIXTURES · 22 PT HEIGHT")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, fixture in
                    VStack(spacing: 6) {
                        Image(nsImage: statusImage(state: fixture.1, dark: dark))
                        Text(fixture.0).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// Draws the real AppKit label into an offscreen bitmap at menu bar height.
    static func statusImage(state: StatusItemState, dark: Bool) -> NSImage {
        let width = StatusItemLabel.width(for: state)
        let view = StatusItemLabel(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        view.state = state
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        view.appearance = appearance
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: 44,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
            view.draw(view.bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: 22))
        image.addRepresentation(bitmap)
        return image
    }

    static func render<V: View>(_ content: V, to url: URL, dark: Bool) throws {
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: content)
        host.appearance = NSApplication.shared.appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        print("Wrote offline fixture: \(url.lastPathComponent) · \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
        window.contentView = nil
    }
}
