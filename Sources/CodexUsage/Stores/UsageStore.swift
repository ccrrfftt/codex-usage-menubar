import Foundation
import SwiftUI
import AppKit

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var paused = false
    @Published var interval = 30 {
        didSet { restartTimer() }
    }
    @Published private(set) var now = Date.now
    private let connection = CodexConnection()
    private var polling: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var lastAttempt: Date?
    private var failures = 0
    private var wakeObserver: NSObjectProtocol?

    var main: QuotaBucket? { snapshot?.main }
    var remaining: Double? { main?.headline?.remaining }
    var stale: Bool { lastError != nil || (updatedAt.map { now.timeIntervalSince($0) > max(90, Double(interval) * 2) } ?? true) }
    var title: String {
        quotaPercent(remaining) + (remaining != nil && stale ? " ·" : "")
    }
    var status: String {
        if isRefreshing { return "正在同步…" }
        if paused { return "已暂停自动更新" }
        if stale { return updatedAt == nil ? "等待连接" : "当前显示上次数据" }
        return "自动同步中"
    }

    init() {
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.now = .now
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.paused else { return }
                await self.refresh()
            }
        }
        restartTimer()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        if let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < 5 { return }
        isRefreshing = true
        lastAttempt = .now
        defer { isRefreshing = false }
        do {
            snapshot = try await connection.read()
            updatedAt = .now
            now = .now
            lastError = nil
            failures = 0
        } catch {
            lastError = error.localizedDescription
            failures += 1
        }
    }

    func togglePause() {
        paused.toggle()
        restartTimer()
        if !paused { Task { await refresh() } }
    }

    func stop() {
        polling?.cancel()
        clock?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        connection.stop()
    }

    private func restartTimer() {
        polling?.cancel()
        guard !paused else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = min(120, Double(self.interval) * pow(2, Double(min(self.failures, 2))))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, !self.paused else { return }
                await self.refresh()
            }
        }
    }
}
