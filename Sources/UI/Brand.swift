import AppKit
import SwiftUI

enum Brand {
    static var icon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Oriel") ?? NSImage()
    }

    static let tagline = "A calmer desktop for macOS."
    static let github = URL(string: "https://github.com/Irfanwani/oriel")!
}

extension Color {
    init(orielHex hex: String) {
        let ns = NSColor(orielHex: hex)
        self.init(nsColor: ns)
    }

    var orielHexString: String {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return "accent" }
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension NSColor {
    static var orielAccent: NSColor { .controlAccentColor }
}
