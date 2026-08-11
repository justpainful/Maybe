import SwiftUI

enum MaybePalette {
    static let cream = Color(hex: "F3F0E7")
    static let ink = Color(hex: "171717")
    static let purple = Color(hex: "7957FF")
    static let yellow = Color(hex: "FFD83D")
    static let blue = Color(hex: "70AEFF")
    static let green = Color(hex: "87E56D")
    static let coral = Color(hex: "FF8066")
    static let glassWhite = Color.white.opacity(0.62)

    static let accents = [purple, yellow, blue, green, coral]
    static let accentHexes = ["7957FF", "FFD83D", "70AEFF", "87E56D", "FF8066"]
}

enum MaybeMetrics {
    static let pageInset: CGFloat = 18
    static let sectionSpacing: CGFloat = 28
    static let cardRadius: CGFloat = 24
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        switch cleaned.count {
        case 8:
            red = value >> 24
            green = value >> 16 & 0xFF
            blue = value >> 8 & 0xFF
            alpha = value & 0xFF
        default:
            red = value >> 16
            green = value >> 8 & 0xFF
            blue = value & 0xFF
            alpha = 0xFF
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

extension Font {
    static func maybeRounded(_ size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if interactive {
            content
                .glassEffect(
                    .regular.tint(tint).interactive(),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .glassEffect(
                    .regular.tint(tint),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }
}

extension View {
    func maybeGlass(
        cornerRadius: CGFloat = 22,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

struct KeycapButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var cornerRadius: CGFloat = 18
    var depth: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(MaybePalette.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.opacity(0.94))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.3)
                            .padding(1)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MaybePalette.ink.opacity(0.18), lineWidth: 1)
            }
            .shadow(
                color: MaybePalette.ink.opacity(configuration.isPressed ? 0.06 : 0.2),
                radius: configuration.isPressed ? 0 : 1,
                y: configuration.isPressed ? 1 : depth
            )
            .offset(y: configuration.isPressed && !reduceMotion ? depth - 1 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct RoundKeycapButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var size: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .black, design: .rounded))
            .foregroundStyle(MaybePalette.ink)
            .frame(width: size, height: size)
            .background(color.opacity(0.96), in: Circle())
            .overlay(alignment: .top) {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.3)
                    .padding(1)
            }
            .overlay(Circle().stroke(MaybePalette.ink.opacity(0.17), lineWidth: 1))
            .shadow(color: MaybePalette.ink.opacity(configuration.isPressed ? 0.06 : 0.22), radius: 1, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed && !reduceMotion ? 3 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CreamCanvas: View {
    var body: some View {
        MaybePalette.cream
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(MaybePalette.yellow.opacity(0.18))
                    .frame(width: 240)
                    .blur(radius: 70)
                    .offset(x: 90, y: -110)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(MaybePalette.purple.opacity(0.11))
                    .frame(width: 280)
                    .blur(radius: 84)
                    .offset(x: -120, y: 120)
            }
            .ignoresSafeArea()
    }
}
