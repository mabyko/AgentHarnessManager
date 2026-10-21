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

extension View {
    func keyboardActivation(_ action: @escaping () -> Void) -> some View {
        modifier(KeyboardActivation(action: action))
    }
}

private struct KeyboardActivation: ViewModifier {
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content.focusable().focused($focused).focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(focused && enabled ? WorkbenchTheme.accent : .clear, lineWidth: 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                guard enabled else { return .ignored }
                action()
                return .handled
            }
    }
}

struct SidebarButtonStyle: ButtonStyle {
    var selected = false
    var resting: Color = .clear
    var outlineSelection = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected, resting: resting, outlineSelection: outlineSelection)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let resting: Color
        let outlineSelection: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .background(selected ? WorkbenchTheme.selection : resting, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(enabled ? configuration.isPressed ? 0.12 : hovered ? 0.05 : 0 : 0))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(selected && outlineSelection ? WorkbenchTheme.accent : .clear, lineWidth: 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .onHover { hovered = $0 }
        }
    }
}
