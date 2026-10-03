import AppKit

enum StatusItemRing {
    static func image(for state: QuotaRingState) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            draw(state, in: NSRect(x: 0, y: 0, width: 16, height: 16), foreground: .black)
            return true
        }
        image.isTemplate = !state.isLow
        return image
    }

    static func draw(_ state: QuotaRingState, in rect: NSRect, foreground: NSColor) {
        let color: NSColor = state.isLow ? .systemRed : foreground
        let track = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
        track.lineWidth = 2
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
                arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: 6,
                              startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                arc.stroke()
            }
        }
        if state.showsValueWarning {
            // A small vector mark stays optically centered and crisp at both scales.
            color.setStroke()
            let stem = NSBezierPath()
            stem.lineWidth = 1.25
            stem.lineCapStyle = .round
            stem.move(to: NSPoint(x: rect.midX, y: rect.midY + 2.5))
            stem.line(to: NSPoint(x: rect.midX, y: rect.midY - 0.5))
            stem.stroke()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 0.7, y: rect.midY - 3, width: 1.4, height: 1.4)).fill()
        }
    }
}
