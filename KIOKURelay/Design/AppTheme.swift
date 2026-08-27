import SwiftUI

enum AppTheme {
    static let ink = Color(hex: 0x121415)
    static let panel = Color(hex: 0x1B1E1D)
    static let panelRaised = Color(hex: 0x242826)
    static let lime = Color(hex: 0xD8FF63)
    static let mint = Color(hex: 0x7CF5C8)
    static let coral = Color(hex: 0xFF8E73)
    static let fog = Color(hex: 0xA8AFAB)
    static let paper = Color(hex: 0xF4F5EF)

    static let background = LinearGradient(
        colors: [Color(hex: 0x111312), Color(hex: 0x1B1F1C)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct GlassCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.panel.opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = 18) -> some View {
        modifier(GlassCardModifier(padding: padding))
    }
}
