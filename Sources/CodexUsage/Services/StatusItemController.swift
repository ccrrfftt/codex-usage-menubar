import AppKit
import Combine
import SwiftUI

/// Keep only menu-bar chrome in AppKit; the existing SwiftUI view owns the popover.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let item: NSStatusItem
    private let itemContent = StatusItemContent(frame: .zero)
    private let popover = NSPopover()
    private let countdownScheduler = RefreshScheduler()
    private var observation: AnyCancellable?
    private var displayedRing: QuotaRingState?
    private var countdownUpdateAt: Date?

    init(store: UsageStore) {
        self.store = store
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            itemContent.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(itemContent)
            NSLayoutConstraint.activate([
                itemContent.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                itemContent.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
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
        if displayedRing != state.ring {
            itemContent.ring.image = StatusItemRing.image(for: state.ring)
            displayedRing = state.ring
        }
        if itemContent.percent.stringValue != state.title || itemContent.countdown.stringValue != state.countdown {
            itemContent.percent.stringValue = state.title
            itemContent.countdown.stringValue = state.countdown
            item.length = ceil(itemContent.fittingSize.width) + 12
        }
        if button.toolTip != state.tooltip { button.toolTip = state.tooltip }
        if button.accessibilityLabel() != state.accessibilityLabel {
            button.setAccessibilityLabel(state.accessibilityLabel)
        }
        if button.accessibilityValue() as? String != state.accessibilityValue {
            button.setAccessibilityValue(state.accessibilityValue)
        }
        if countdownUpdateAt != state.countdownUpdateAt {
            countdownUpdateAt = state.countdownUpdateAt
            if let countdownUpdateAt {
                countdownScheduler.schedule(after: max(0.1, countdownUpdateAt.timeIntervalSinceNow)) { [weak self] in
                    self?.store.updateDisplayTime()
                }
            } else {
                countdownScheduler.cancel()
            }
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

@MainActor
private final class StatusItemContent: NSStackView {
    let ring = NSImageView()
    let percent = NSTextField(labelWithString: "")
    let countdown = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 4
        ring.imageScaling = .scaleNone
        ring.contentTintColor = .labelColor
        ring.setAccessibilityElement(false)
        percent.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        countdown.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        for label in [percent, countdown] {
            label.alignment = .center
            label.setAccessibilityElement(false)
        }

        let labels = NSStackView(views: [percent, countdown])
        labels.orientation = .vertical
        labels.alignment = .centerX
        labels.distribution = .fill
        labels.spacing = -4 // Two 13-point label frames fit in a 22-point status item.
        addArrangedSubview(ring)
        addArrangedSubview(labels)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Let the native status button handle clicks anywhere in the item.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
