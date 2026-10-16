import SwiftUI
import UIKit

/// Wely's look, taken from wely-web's tokens (`src/styles/_theme.scss`): the blue → orange brand
/// gradient, a warm off-white canvas with white cards (warm off-black and a step lighter in the
/// dark), soft ink, and Outfit, the app's face.
nonisolated enum Theme {
    // MARK: Colours

    /// `--brand-blue` and `--brand-orange`, the two ends of the gradient.
    static let blue = Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
    static let orange = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
    /// `--primary-blue`: solid fills and blue text, one step darker so white type stays readable.
    static let primary = Color("AccentColor")

    static let canvas = Color("Canvas")
    static let subtle = Color("Subtle")
    static let card = Color("Card")
    static let ink = Color("Ink")
    static let ink2 = Color("Ink2")
    static let ink3 = Color("Ink3")
    static let border = Color.primary.opacity(0.06)
    static let danger = Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
    static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)

    /// The brand gradient as the logo draws it: the OKLCH path from blue to orange, through violet
    /// and pink — the sRGB one goes through a dull grey-mauve.
    static let gradientStops: [Color] = [0x3B82F6, 0x8274F7, 0xB168E4, 0xD45FC2, 0xED5C96, 0xFA6263, 0xF97316].map(Color.init(hex:))
    static let gradient = LinearGradient(colors: gradientStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    static let horizontalGradient = LinearGradient(colors: gradientStops, startPoint: .leading, endPoint: .trailing)

    /// An entry's colour: blue for the user's own events, orange for friends', grey for a proposed date.
    @MainActor static func color(for entry: CalendarEntry) -> Color {
        if entry.tentative { return ink3 }
        return entry.mine ? blue : orange
    }

    // MARK: Shapes

    static let cardRadius: CGFloat = 18
    static let fieldRadius: CGFloat = 12
}

extension Color {
    nonisolated init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: Typography

/// Outfit at the sizes of the system's text styles, scaling with Dynamic Type as they do:
/// `.font(.wely.headline)`, `.font(.wely.caption.bold())`.
nonisolated struct WelyFonts: Sendable {
    static let family = "Outfit"

    var largeTitle: Font { Self.outfit(34, .largeTitle, .bold) }
    var title: Font { Self.outfit(28, .title, .bold) }
    var title2: Font { Self.outfit(22, .title2, .semibold) }
    var title3: Font { Self.outfit(20, .title3, .semibold) }
    var headline: Font { Self.outfit(17, .headline, .semibold) }
    var body: Font { Self.outfit(17, .body) }
    var callout: Font { Self.outfit(16, .callout) }
    var subheadline: Font { Self.outfit(15, .subheadline) }
    var footnote: Font { Self.outfit(13, .footnote) }
    var caption: Font { Self.outfit(12, .caption) }
    var caption2: Font { Self.outfit(11, .caption2) }

    /// A fixed size, for what is drawn rather than read (initials in an avatar, a date tile).
    func fixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(Self.family, fixedSize: size).weight(weight)
    }

    private static func outfit(_ size: CGFloat, _ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(family, size: size, relativeTo: style).weight(weight)
    }

    static func uiFont(_ size: CGFloat, _ weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [.family: family])
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}

extension Font {
    nonisolated static let wely = WelyFonts()
}

// MARK: Buttons

/// The main action: white type on the brand gradient, as wely-web's primary buttons.
struct WelyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wely.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, controlSize == .large ? 20 : 14)
            .padding(.vertical, controlSize == .large ? 14 : 8)
            .background(Theme.gradient, in: Capsule())
            .shadow(color: Theme.blue.opacity(isEnabled ? 0.25 : 0), radius: 8, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A secondary action: blue ink on the brand tint.
struct WelySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wely.subheadline.weight(.semibold))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, controlSize == .large ? 20 : 14)
            .padding(.vertical, controlSize == .large ? 14 : 8)
            .background(Theme.blue.opacity(configuration.isPressed ? 0.2 : 0.1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A destructive action: red ink on a red tint, or white on red for the last step.
struct WelyDangerButtonStyle: ButtonStyle {
    var solid = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wely.subheadline.weight(.semibold))
            .foregroundStyle(solid ? .white : Theme.danger)
            .padding(.horizontal, controlSize == .large ? 20 : 14)
            .padding(.vertical, controlSize == .large ? 14 : 10)
            .background(solid ? Theme.danger : Theme.danger.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed && solid ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == WelyDangerButtonStyle {
    static var welyDanger: WelyDangerButtonStyle { WelyDangerButtonStyle() }
    static func welyDanger(solid: Bool) -> WelyDangerButtonStyle { WelyDangerButtonStyle(solid: solid) }
}

extension ButtonStyle where Self == WelyPrimaryButtonStyle {
    static var welyPrimary: WelyPrimaryButtonStyle { WelyPrimaryButtonStyle() }
}

extension ButtonStyle where Self == WelySecondaryButtonStyle {
    static var welySecondary: WelySecondaryButtonStyle { WelySecondaryButtonStyle() }
}

// MARK: Surfaces

extension View {
    /// A white card on the canvas, with the web's hairline border and soft shadow.
    func welyCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat? = nil) -> some View {
        self
            .padding(padding ?? 0)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    /// A screen on Wely's canvas: lists and forms drop the system's grey behind their rows.
    func welyScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .containerBackground(Theme.canvas, for: .navigation)
            .background(Theme.canvas.ignoresSafeArea())
            .font(.wely.body)
            .tint(Theme.primary)
    }
}

/// A navigation stack on Wely's canvas; in a sheet, the sheet takes the canvas too.
struct WelyNavigationStack<Content: View>: View {
    private var path: Binding<NavigationPath>?
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    init(path: Binding<NavigationPath>, @ViewBuilder content: () -> Content) {
        self.path = path
        self.content = content()
    }

    var body: some View {
        Group {
            if let path {
                NavigationStack(path: path) { content.welyScreen() }
            } else {
                NavigationStack { content.welyScreen() }
            }
        }
        .presentationBackground(Theme.canvas)
    }
}

// MARK: UIKit

enum WelyAppearance {
    /// What SwiftUI only draws through UIKit: the navigation bar's titles, segmented controls.
    @MainActor static func apply() {
        let ink = UIColor(named: "Ink") ?? .label
        let bar = UINavigationBarAppearance()
        bar.configureWithDefaultBackground()
        bar.backgroundColor = UIColor(named: "Canvas")?.withAlphaComponent(0.85)
        bar.shadowColor = .clear
        bar.titleTextAttributes = [.font: WelyFonts.uiFont(17, .semibold, style: .headline), .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: WelyFonts.uiFont(32, .bold, style: .largeTitle), .foregroundColor: ink]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: WelyFonts.uiFont(17, .medium, style: .body)]
        bar.buttonAppearance = button
        bar.doneButtonAppearance = button
        let scrollEdge = bar.copy()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.titleTextAttributes = bar.titleTextAttributes
        scrollEdge.largeTitleTextAttributes = bar.largeTitleTextAttributes
        scrollEdge.buttonAppearance = button
        scrollEdge.doneButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge

        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: WelyFonts.uiFont(13, .medium, style: .footnote)], for: .normal)
        segmented.setTitleTextAttributes([.font: WelyFonts.uiFont(13, .semibold, style: .footnote)], for: .selected)
    }
}

extension Date {
    /// « 19:00 – 22:00 », the 24-hour clock read in France.
    static func timeRange(_ start: Date, _ end: Date) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

extension Locale {
    static let wely = Locale(identifier: "fr_FR")
}
