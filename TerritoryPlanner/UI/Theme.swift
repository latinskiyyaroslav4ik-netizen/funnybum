import SwiftUI

enum Theme {
    static let accent = Color(red: 0.24, green: 0.88, blue: 0.78)        // aqua
    static let accentSecondary = Color(red: 0.42, green: 0.55, blue: 1.0) // periwinkle
    static let success = Color(red: 0.35, green: 0.86, blue: 0.47)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.28)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.40)
    static let start = Color(red: 1.0, green: 0.62, blue: 0.26)

    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.10)
    static let hairline = Color.white.opacity(0.09)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.40)

    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let cornerRadius: CGFloat = 18
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

extension View {
    /// Frosted card used throughout panels.
    func glassCard(padding: CGFloat = 14, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }

    /// Floating control over the map.
    func floatingGlass(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}
