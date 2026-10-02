import AppKit
import SwiftUI

enum WorkbenchTheme {
    static let sidebarText = adaptive(0x202020, 0xEEEEEE)
    static let sidebarSecondary = adaptive(0x606060, 0xB6B6B6)
    static let surface = adaptive(0xFAFAFA, 0x202020)
    static let raised = adaptive(0xF5F5F5, 0x292929)
    static let selection = adaptive(0xEFEFEF, 0x303030)
    static let border = adaptive(0xDADADA, 0x494949)
    static let accent = adaptive(0x3059C7, 0xA9BCFF)
    static let warning = adaptive(0x805520, 0xE6C08D)
    static let warningSurface = adaptive(0xF7EEDC, 0x413522)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

extension URL {
    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
}
