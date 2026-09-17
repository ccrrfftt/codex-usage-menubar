import AppKit

enum StatusItemRing {
    static func image(for state: QuotaRingState) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let color: NSColor = state.isLow ? .systemRed : .black
            let track = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12))
            track.lineWidth = 2
            // The empty track stays visible, including when no quota remains.
            color.withAlphaComponent(0.25).setStroke()
            track.stroke()
            if let fraction = state.fraction, fraction > 0 {
                color.setStroke()
                if fraction == 1 {
                    track.stroke()
                } else {
                    let arc = NSBezierPath()
                    arc.lineWidth = 2
                    arc.lineCapStyle = .round
                    arc.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 6,
                                  startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                    arc.stroke()
                }
            }
            return true
        }
        // AppKit adapts the regular ring to the menu bar and its selected state.
        // Keep the low-quota image in color so the warning remains red.
        image.isTemplate = !state.isLow
        return image
    }
}
