import AppKit
import Foundation
import SwiftUI

extension Color {
    init?(hexRGB: String) {
        let normalized = JobStatusColorPalette.normalizedHex(hexRGB, fallback: "")
        guard normalized.count == 7 else { return nil }
        let raw = String(normalized.dropFirst())
        guard let red = Int(raw.prefix(2), radix: 16),
              let green = Int(raw.dropFirst(2).prefix(2), radix: 16),
              let blue = Int(raw.dropFirst(4).prefix(2), radix: 16) else {
            return nil
        }
        self = Color(nsColor: NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        ))
    }

    var hexRGBString: String? {
        let color = NSColor(self)
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return nil
        }
        let red = max(0, min(255, Int((rgb.redComponent * 255).rounded())))
        let green = max(0, min(255, Int((rgb.greenComponent * 255).rounded())))
        let blue = max(0, min(255, Int((rgb.blueComponent * 255).rounded())))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
