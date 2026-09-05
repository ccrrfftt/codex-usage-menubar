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
            // Keep the system menu-bar face, one point smaller than its default size.
            let defaultSize = NSFont.menuBarFont(ofSize: 0).pointSize
            button.font = NSFont.menuBarFont(ofSize: max(10, defaultSize - 1))
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
        }
        let content = NSHostingController(rootView: UsageMenuView(store: store))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient
        // Resize immediately below the status-item anchor; do not recenter the
        // SwiftUI content through an animated intermediate window height.
        popover.animates = false
        observation = store.$state.map(\.statusItem).removeDuplicates().sink { [weak self] state in
            self?.updateButton(state)
        }
    }

    private func updateButton(_ state: StatusItemState) {
        guard let button = item.button else { return }
        if button.title != state.title { button.title = state.title }
        if button.toolTip != state.tooltip { button.toolTip = state.tooltip }
        if button.accessibilityLabel() != state.accessibilityLabel {
            button.setAccessibilityLabel(state.accessibilityLabel)
        }
        if button.accessibilityValue() as? String != state.accessibilityValue {
            button.setAccessibilityValue(state.accessibilityValue)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    func showPopover() {
        guard let button = item.button, !popover.isShown else { return }
        store.prepareForDisplay()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

}
