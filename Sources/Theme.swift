import SwiftUI
import AppKit

// MARK: - Palette (values measured from Instagram for iOS and Apple Messages)

extension Color {
    /// A color that follows the window's light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// Instagram's primary button and link blue.
    static let igBlue = Color(hex: 0x0095F6)
    /// Instagram's grey secondary buttons ("Message", "Following").
    static let igSecondaryFill = Color(light: 0xEFEFEF, dark: 0x363636)
    /// Profile website links.
    static let igLink = Color(light: 0x00376B, dark: 0xE0F1FF)
    /// The red of a filled like heart.
    static let igLike = Color(hex: 0xFF3040)
    /// Hairlines between rows and under the profile tab strip.
    static let igSeparator = Color(light: 0xDBDBDB, dark: 0x262626)

    /// Outgoing bubble in Apple Messages.
    static let messagesBlue = Color(light: 0x0A7CFF, dark: 0x0A84FF)
    /// Incoming bubble in Apple Messages.
    static let messagesGray = Color(light: 0xE9E9EB, dark: 0x3B3B3D)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Buttons

/// Instagram's flat 8pt rounded profile buttons.
struct IGButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .secondary
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(kind == .primary ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(kind == .primary ? Color.igBlue : Color.igSecondaryFill)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shrinks a little while pressed, the way iOS cells and story avatars respond to touch.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.22, bounce: 0.35), value: configuration.isPressed)
    }
}

extension Int {
    /// "1.234", "12,3 B", "4,5 Mn" — the way Instagram abbreviates counts in Turkish.
    var igCompact: String {
        self < 10_000 ? formatted() : formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}

extension Date {
    /// "şimdi", "5 dk", "3 sa", "2 g", "4 hf" — Instagram's short ages.
    var igAge: String {
        let seconds = max(0, Date.now.timeIntervalSince(self))
        switch seconds {
        case ..<60: return "şimdi"
        case ..<3_600: return "\(Int(seconds / 60)) dk"
        case ..<86_400: return "\(Int(seconds / 3_600)) sa"
        case ..<604_800: return "\(Int(seconds / 86_400)) g"
        default: return "\(Int(seconds / 604_800)) hf"
        }
    }
}
