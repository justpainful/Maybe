import SwiftUI

// MARK: - Palette

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

    static func accent(at index: Int) -> Color {
        accents[abs(index) % accents.count]
    }

    static func accentHex(at index: Int) -> String {
        accentHexes[abs(index) % accentHexes.count]
    }

    /// Ink tints. Text is almost always ink; these are the only allowed steps.
    static let inkSoft = ink.opacity(0.58)
    static let inkFaint = ink.opacity(0.38)
    static let hairline = ink.opacity(0.10)
}

enum MaybeMetrics {
    static let pageInset: CGFloat = 20
    static let gutter: CGFloat = 12
    static let sectionSpacing: CGFloat = 26
    static let tileRadius: CGFloat = 22
    static let panelRadius: CGFloat = 24
    static let controlRadius: CGFloat = 18
    /// Height reserved under scrolling content so the floating tab bar never covers a card.
    static let tabBarClearance: CGFloat = 92
}

// MARK: - Type

extension Font {
    /// SF Pro Rounded — headings, buttons, anything structural.
    static func maybeRounded(_ size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let maybeScreenTitle = Font.system(size: 32, weight: .black, design: .rounded)
    static let maybeSectionTitle = Font.system(size: 21, weight: .bold, design: .rounded)
    static let maybeTileTitle = Font.system(size: 15, weight: .bold, design: .rounded)
    static let maybeControl = Font.system(size: 15, weight: .bold, design: .rounded)
    static let maybeMeta = Font.system(size: 12.5, weight: .semibold, design: .rounded)
}

// MARK: - Color from hex

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

// MARK: - Surfaces

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

/// A flat, tactile card. Not glass — glass is for chrome, cards hold content.
private struct PanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(MaybePalette.hairline, lineWidth: 1)
            }
            .shadow(color: MaybePalette.ink.opacity(0.07), radius: 1, y: 2)
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

    func maybePanel(
        cornerRadius: CGFloat = MaybeMetrics.panelRadius,
        fill: Color = Color.white.opacity(0.66)
    ) -> some View {
        modifier(PanelSurfaceModifier(cornerRadius: cornerRadius, fill: fill))
    }
}

// MARK: - Keycaps

/// The shared keycap look: solid colour, white top highlight, thin ink edge, short hard shadow.
struct KeycapSurface: View {
    var color: Color
    var cornerRadius: CGFloat = MaybeMetrics.controlRadius
    var pressed = false
    var depth: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.2)
                    .padding(1)
                    .blendMode(.plusLighter)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(MaybePalette.ink.opacity(0.16), lineWidth: 1)
            }
            .shadow(
                color: MaybePalette.ink.opacity(pressed ? 0.10 : 0.24),
                radius: 0,
                y: pressed ? 1 : depth
            )
    }
}

struct KeycapButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var cornerRadius: CGFloat = MaybeMetrics.controlRadius
    var depth: CGFloat = 4
    var minHeight: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.maybeControl)
            .foregroundStyle(MaybePalette.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .background {
                KeycapSurface(
                    color: color,
                    cornerRadius: cornerRadius,
                    pressed: configuration.isPressed,
                    depth: depth
                )
            }
            .offset(y: configuration.isPressed && !reduceMotion ? depth - 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct RoundKeycapButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var size: CGFloat = 46
    var depth: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(MaybePalette.ink)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(color)
                    .overlay(alignment: .top) {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.2)
                            .padding(1)
                            .blendMode(.plusLighter)
                    }
                    .overlay(Circle().strokeBorder(MaybePalette.ink.opacity(0.16), lineWidth: 1))
                    .shadow(
                        color: MaybePalette.ink.opacity(configuration.isPressed ? 0.10 : 0.24),
                        radius: 0,
                        y: configuration.isPressed ? 1 : depth
                    )
            }
            .offset(y: configuration.isPressed && !reduceMotion ? depth - 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Press feedback for things that are not keycaps (tiles, rows, thumbnails).
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Canvas

struct CreamCanvas: View {
    var body: some View {
        MaybePalette.cream.ignoresSafeArea()
    }
}

// MARK: - Media geometry

enum MediaAspect {
    /// Clamped so one extreme photo cannot blow a column out of proportion,
    /// while still never cropping the image itself.
    static let minimum: CGFloat = 0.62
    static let maximum: CGFloat = 1.45

    static func ratio(width: Double, height: Double) -> CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return min(max(CGFloat(width / height), minimum), maximum)
    }
}
