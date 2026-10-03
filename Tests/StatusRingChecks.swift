import AppKit

@main @MainActor
struct StatusRingChecks {
    static func main() {
        _ = NSApplication.shared
        var checked = 0
        func check(_ success: @autoclosure () -> Bool, _ name: String) {
            guard success() else { fatalError("FAILED: " + name) }
            checked += 1
            print("PASS: " + name)
        }
        func render(_ value: Double?, appearance: NSAppearance.Name = .aqua) -> NSBitmapImageRep {
            let image = StatusItemRing.image(for: QuotaRingState(remaining: value))
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
                NSGraphicsContext.restoreGraphicsState()
            }
            return bitmap
        }
        let regular = StatusItemRing.image(for: QuotaRingState(remaining: 15))
        let warning = StatusItemRing.image(for: QuotaRingState(remaining: 14.9))
        check(regular.size == NSSize(width: 16, height: 16) && warning.size == regular.size,
              "normal and warning icons retain the same menu-bar dimensions")
        check(regular.isTemplate && !warning.isTemplate, "normal icon adapts to AppKit while warning preserves red")
        let quarter = render(25)
        // Bitmap rows run from top to bottom; sample inside the upper-right arc.
        let filled = quarter.colorAt(x: 24, y: 7)!
        let unfilled = quarter.colorAt(x: 7, y: 7)!
        check(filled.alphaComponent > 0.9 && unfilled.alphaComponent < 0.4,
              "quarter ring starts at the top and fills clockwise")
        let full = render(100)
        check(full.colorAt(x: 7, y: 7)!.alphaComponent > 0.9,
              "full quota fills the far side of the ring")
        check(full.colorAt(x: 16, y: 16)!.alphaComponent == 0 &&
              full.colorAt(x: 0, y: 16)!.alphaComponent == 0,
              "center and outer padding remain transparent without clipping")
        let unknown = render(nil)
        check(unknown.colorAt(x: 24, y: 7)!.alphaComponent < 0.4,
              "unknown quota shows only the empty track")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for value in [0.0, 14.0] {
                let color = render(value, appearance: appearance).colorAt(x: 16, y: 3)!.usingColorSpace(.deviceRGB)!
                check(color.redComponent > color.greenComponent * 1.5 && color.alphaComponent > 0.1,
                      "low quota \(value) remains visibly red in \(appearance.rawValue)")
            }
        }
        print("\(checked) ring rendering checks passed.")
    }
}
