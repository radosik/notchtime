import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

/// Steel black surfaces, cloudy white controls, one pink accent (the tongue).
enum Theme {
    static let steel = Color(hex: 0x17191D)
    static let steelDeep = Color(hex: 0x0A0B0D)
    static let steelRaised = Color(hex: 0x24272C)
    static let edge = Color.white.opacity(0.09)
    static let text = Color(hex: 0xF4F5F7)
    static let textDim = Color(hex: 0x8C9199)
    static let textFaint = Color(hex: 0x5A5F67)
    static let ink = Color(hex: 0x15171A)
    static let cloudTop = Color(hex: 0xFFFFFF)
    static let cloudBottom = Color(hex: 0xD9DCE2)
    static let tongueTop = Color(hex: 0xFF7A95)
    static let tongueBottom = Color(hex: 0xE0405F)

    static var surface: LinearGradient {
        LinearGradient(colors: [steel, steelDeep], startPoint: .top, endPoint: .bottom)
    }

    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let rounded = Font.system(size: 13, weight: .medium, design: .rounded)
}

enum PillowTint {
    case cloud, tongue, ghost

    var fill: [Color] {
        switch self {
        case .cloud: return [Theme.cloudTop, Theme.cloudBottom]
        case .tongue: return [Theme.tongueTop, Theme.tongueBottom]
        case .ghost: return [Color.white.opacity(0.10), Color.white.opacity(0.05)]
        }
    }
    var foreground: Color {
        switch self {
        case .cloud: return Theme.ink
        case .tongue: return .white
        case .ghost: return Theme.text
        }
    }
    var sheen: Double {
        switch self {
        case .cloud: return 0.95
        case .tongue: return 0.45
        case .ghost: return 0.12
        }
    }
    var glow: Color {
        switch self {
        case .cloud: return Color.white.opacity(0.18)
        case .tongue: return Theme.tongueBottom.opacity(0.45)
        case .ghost: return .clear
        }
    }
}

/// Boo-style button: soft white capsule with a glossy top highlight and a cushion shadow.
struct PillowButtonStyle: ButtonStyle {
    var tint: PillowTint = .cloud
    var size: CGFloat = 14
    var horizontal: CGFloat = 22
    var vertical: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(tint.foreground)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                ZStack {
                    Capsule().fill(LinearGradient(colors: tint.fill, startPoint: .top, endPoint: .bottom))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(tint.sheen), Color.white.opacity(0)],
                                             startPoint: .top, endPoint: .center))
                        .padding(1.5)
                    Capsule().strokeBorder(Color.white.opacity(tint == .ghost ? 0.10 : 0.55), lineWidth: 0.6)
                }
            )
            .shadow(color: Color.black.opacity(0.45), radius: 9, x: 0, y: 5)
            .shadow(color: tint.glow, radius: 16, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small rounded label used for client / project tags.
struct Chip: View {
    var text: String
    var tint: Color = Theme.textDim
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// Minimal dark text field (no bezel), used inside the island and editors.
struct GhostField: View {
    var placeholder: String
    @Binding var text: String
    var font: Font = .system(size: 14, weight: .medium, design: .rounded)
    var alignment: TextAlignment = .center
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .multilineTextAlignment(alignment)
            .foregroundStyle(Theme.text)
            .onSubmit(onSubmit)
    }
}
