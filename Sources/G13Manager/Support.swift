import SwiftUI
import G13Core

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Color {
    init(_ rgb: G13Core.RGBColor) {
        self.init(.sRGB,
                  red: Double(rgb.r) / 255,
                  green: Double(rgb.g) / 255,
                  blue: Double(rgb.b) / 255)
    }

    var rgbColor: G13Core.RGBColor {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func c(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        return G13Core.RGBColor(r: c(ns.redComponent), g: c(ns.greenComponent), b: c(ns.blueComponent))
    }
}
