import AppKit
import Combine
import SwiftUI

/// Keep only menu-bar chrome in AppKit; the existing SwiftUI view owns the popover.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    init(store: UsageStore) {
        self.store = store
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            // Match the system menu-bar font role; never inherit a SwiftUI body font.
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.alignment = .center
            if let url = Bundle.main.url(forResource: "CodexStatusIcon", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                icon.size = NSSize(width: 16, height: 16)
                button.image = icon
            }
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Codex 剩余用量")
        }
        let content = NSHostingController(rootView: UsageMenuView(store: store))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = true
        updateButton()
        observation = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateButton() }
        }
    }

    private func updateButton() {
        guard let button = item.button else { return }
        button.title = store.title
        button.toolTip = "Codex 剩余 \(quotaPercent(store.remaining)) · \(store.status)"
        button.setAccessibilityValue(quotaPercent(store.remaining))
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    func showPopover() {
        guard let button = item.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
