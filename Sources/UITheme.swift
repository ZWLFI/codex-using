import AppKit
import SwiftUI

// The instrument palette is deliberately dark to match the physical dial reference.
enum UITheme {
    static let background = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.075)
    static let border = Color.white.opacity(0.09)
    static let secondaryText = Color(red: 0.69, green: 0.68, blue: 0.65)
    static let accent = Color(red: 1, green: 0.68, blue: 0.26)
    static let warning = Color(red: 1, green: 0.77, blue: 0.48)
    static let critical = Color(red: 1, green: 0.52, blue: 0.49)
    static let positive = Color(red: 0.45, green: 0.86, blue: 0.64)
    static let caption = Font.system(size: 11)
    static let body = Font.system(size: 13)
    static let section = Font.system(size: 13, weight: .semibold)
    static let shell = LinearGradient(colors: [Color(white: 0.16), Color(white: 0.115)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension View {
    func insetSurface(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(UITheme.surface.shadow(.inner(color: .black.opacity(0.65), radius: 4, x: 0, y: 3)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(UITheme.border, lineWidth: 0.5)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}
