import SwiftUI
import AppKit

@main
struct CodexUsageApp: App {
    @NSApplicationDelegateAdaptor(UsageApplicationDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class UsageApplicationDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusController: StatusItemController?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let store = UsageStore()
        self.store = store
        statusController = StatusItemController(store: store)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.statusController?.showPopover()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        guard let pending = store?.stop() else { return .terminateNow }
        terminating = true
        Task {
            await pending.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
