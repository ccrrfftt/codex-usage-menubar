import AppKit

/// Draw only the two-line label; NSStatusBarButton retains clicks, focus and accessibility.
@MainActor
final class StatusItemLabel: NSView {
    var state: StatusItemState? {
        didSet {
            if oldValue?.title != state?.title || oldValue?.valueTitle != state?.valueTitle || oldValue?.ring != state?.ring {
                needsDisplay = true
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func width(for state: StatusItemState) -> CGFloat {
        let width = max(measure(state.title, size: 10.5), measure(state.valueTitle, size: 9))
        return ceil(max(44, width) + 30)
    }

    private static func measure(_ text: String, size: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)]).width
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let state else { return }
        let selected = (superview as? NSButton)?.isHighlighted == true
        let foreground: NSColor = selected ? .selectedMenuItemTextColor : .labelColor
        StatusItemRing.draw(state.ring,
            in: NSRect(x: 5, y: floor((bounds.height - 16) / 2), width: 16, height: 16),
            foreground: foreground)
        let color: NSColor = state.ring.isLow ? .systemRed : foreground
        let textRect = NSRect(x: 25, y: 0, width: bounds.width - 30, height: bounds.height)
        drawLine(state.title, fontSize: 10.5, color: color, in: textRect, centerY: bounds.midY + 5)
        drawLine(state.valueTitle, fontSize: 9, color: color, in: textRect, centerY: bounds.midY - 5)
    }

    private func drawLine(_ text: String, fontSize: CGFloat, color: NSColor, in rect: NSRect, centerY: CGFloat) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: centerY - size.height / 2),
                               withAttributes: attributes)
    }
}
