import SwiftUI
import Observation
import MorningCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The clock behind the palette. Refreshed once a minute by the root view; the
/// resolved blend is what every colour reads. Debug builds and UI tests may pin a phase.
@Observable @MainActor
final class MorningThemeClock {
    static let shared = MorningThemeClock()

    private(set) var blend: MorningPhaseBlend
    /// Sunrise and sunset in minutes. Fixed hours until a solar source supplies them.
    var solar: MorningSolarDay = .fixed
    /// A pinned phase for previews, snapshots and tests. `nil` follows the clock.
    var pinnedPhase: MorningDayPhase? {
        didSet { refresh() }
    }

    init(now: Date = .now) {
        blend = MorningDayClock.blend(at: now)
        pinnedPhase = Self.phaseFromArguments()
        if pinnedPhase != nil { refresh(now: now) }
    }

    func refresh(now: Date = .now) {
        let next = pinnedPhase.map(MorningPhaseBlend.steady) ?? MorningDayClock.blend(at: now, solar: solar)
        if next != blend { blend = next }
    }

    /// `--theme-phase=dawn` (UI tests, debug) or `MO_THEME_PHASE=dawn` (snapshots).
    private static func phaseFromArguments() -> MorningDayPhase? {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if let option = process.arguments.first(where: { $0.hasPrefix("--theme-phase=") }),
           let phase = MorningDayPhase(rawValue: String(option.dropFirst("--theme-phase=".count))) {
            return phase
        }
        if let value = process.environment["MO_THEME_PHASE"], let phase = MorningDayPhase(rawValue: value) {
            return phase
        }
        #endif
        return nil
    }
}

/// The resolved tokens for the current light. Colours are dynamic: they follow the
/// appearance and Increase Contrast on their own, so a view only ever asks for `ink`.
struct MorningTheme {
    let blend: MorningPhaseBlend
    var phase: MorningDayPhase { blend.dominant }

    /// The theme for the clock's current blend. Read inside a view body so the view
    /// follows the clock.
    @MainActor static var current: MorningTheme { MorningTheme(blend: MorningThemeClock.shared.blend) }

    // MARK: Colour

    /// The page.
    var paper: Color { dynamic(\.paper) }
    /// Cards, rows, sheets.
    var surface: Color { dynamic(\.surface) }
    /// Text and rules.
    var ink: Color { dynamic(\.ink) }
    /// Secondary text (4.5:1 or better everywhere; becomes ink under Increase Contrast).
    var inkSoft: Color { dynamic(\.inkSoft, highContrast: \.ink) }
    /// The one accent, for marks and fills. Never text.
    var accent: Color { dynamic(\.accent) }
    /// The accent for small text and icons.
    var accentText: Color { dynamic(\.accentText) }
    /// Text on an ink fill.
    var onInk: Color { dynamic(\.onInk) }
    /// A saved morning, an approved routine.
    var positive: Color { dynamic(\.positive) }
    /// The halftone dot's ink.
    var dot: Color { dynamic(\.dot) }
    /// Hairlines.
    var line: Color { ink.opacity(0.18) }

    private func dynamic(_ token: KeyPath<MorningPaletteValues, MorningRGB>,
                         highContrast: KeyPath<MorningPaletteValues, MorningRGB>? = nil) -> Color {
        let blend = blend
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            let values = MorningPaletteValues.resolve(blend, dark: traits.userInterfaceStyle == .dark)
            let key = traits.accessibilityContrast == .high ? (highContrast ?? token) : token
            let c = values[keyPath: key]
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let values = MorningPaletteValues.resolve(blend, dark: dark)
            let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let c = values[keyPath: high ? (highContrast ?? token) : token]
            return NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #endif
    }

    /// The plain values, for drawing code that needs numbers rather than a dynamic colour.
    func values(dark: Bool) -> MorningPaletteValues { MorningPaletteValues.resolve(blend, dark: dark) }

    // MARK: Type

    /// Native system serif keeps the print character, scales with Dynamic Type,
    /// and adds no font download or licence dependency. Mono carries labels.
    enum Typography {
        /// A page title.
        static let display = Font.system(.largeTitle, design: .serif, weight: .medium)
        /// A card or section title.
        static let title = Font.system(.title2, design: .serif, weight: .medium)
        /// A small heading inside a card.
        static let heading = Font.system(.headline, design: .serif, weight: .semibold)
        /// Reading text.
        static let body = Font.system(.body, design: .serif)
        /// Secondary reading text.
        static let note = Font.system(.subheadline, design: .serif)
        /// Eyebrows, dates, counts: mono, small caps feel.
        static let label = Font.system(.caption, design: .monospaced, weight: .medium)
        /// Minutes and times.
        static let number = Font.system(.caption, design: .monospaced).monospacedDigit()
        /// Buttons.
        static let control = Font.system(.subheadline, design: .serif, weight: .semibold)
    }

    // MARK: Space

    enum Space {
        /// Side gutters.
        static let gutter: CGFloat = 24
        /// Inside a card.
        static let card: CGFloat = 18
        /// Between cards.
        static let stack: CGFloat = 16
        /// Corner radius of cards and sheets. Small: this is print, not glass.
        static let radius: CGFloat = 10
        /// The halftone cell.
        static let halftoneCell: CGFloat = 7
    }
}

// MARK: - Paper

/// The printed sheet: paper, a halftone dot screen and a faint grain. Static, drawn
/// in one Canvas pass. Nothing here is interactive or announced. Reduce Transparency keeps
/// the plain paper only.
struct MorningPaper: View {
    var showsSun = true
    /// 0...1: how far the morning has come. The sun climbs with it.
    var progress: Double = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = MorningTheme.current
        ZStack(alignment: .topTrailing) {
            theme.paper
            if !reduceTransparency {
                MorningHalftone(color: theme.dot, opacity: scheme == .dark ? 0.16 : 0.11)
                if showsSun {
                    MorningHalftoneSun(progress: progress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: progress)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A regular dot screen, the print's halftone. Cheap: one Canvas, one fill per dot,
/// rendered as one path. No animation or timer drives the texture.
struct MorningHalftone: View {
    var color: Color
    var opacity: Double
    var cell: CGFloat = MorningTheme.Space.halftoneCell
    var radius: CGFloat = 1.05

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var path = Path()
            var y: CGFloat = cell / 2
            var row = 0
            while y < size.height + cell {
                var x: CGFloat = (row % 2 == 0) ? cell / 2 : cell
                while x < size.width + cell {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += cell
                }
                y += cell * 0.866
                row += 1
            }
            context.fill(path, with: .color(color))
        }
        .opacity(opacity)
    }
}

/// The sun of the print: a disc whose dots grow towards the centre. It sits behind
/// the top corner and rises with the morning's progress.
struct MorningHalftoneSun: View {
    var progress: Double
    var diameter: CGFloat = 220
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = MorningTheme.current
        let lift = diameter * 0.55 * min(1, max(0, progress))
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let cell: CGFloat = 9
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = size.width / 2
            var path = Path()
            var y: CGFloat = cell / 2
            while y < size.height {
                var x: CGFloat = cell / 2
                while x < size.width {
                    let d = hypot(x - centre.x, y - centre.y) / maxRadius
                    if d < 1 {
                        // Big dots in the middle, fading to pinpricks at the rim.
                        let r = max(0.6, (1 - d * d) * cell * 0.46)
                        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                    x += cell
                }
                y += cell
            }
            context.fill(path, with: .color(theme.accent))
        }
        .frame(width: diameter, height: diameter)
        .opacity(scheme == .dark ? 0.55 : 0.75)
        .offset(x: diameter * 0.28, y: -diameter * 0.62 + diameter * 0.55 - lift)
    }
}

// MARK: - Controls

/// The one primary action on a screen: an ink pill with paper text. Pressed, it
/// tints; disabled, it fades.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let theme = MorningTheme.current
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .foregroundStyle(theme.onInk)
            .background(theme.ink.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
/// The primary fill at the secondary size, for the one case where two actions must
/// sit side by side (record / choose).
struct CompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let theme = MorningTheme.current
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(theme.onInk)
            .background(theme.ink.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
/// Every other action: an outlined ink pill on the paper.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let theme = MorningTheme.current
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(theme.ink)
            .background(theme.surface.opacity(configuration.isPressed ? 0.5 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(theme.ink.opacity(0.7), lineWidth: 1.2))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
/// A quiet text action in the accent ink; for the third choice, never the first.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MorningTheme.Typography.control)
            .foregroundStyle(MorningTheme.current.accentText)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : isEnabled ? 1 : 0.4)
    }
}

/// Destructive intent stays explicit, with a stable contrast in both appearances.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Color(red: 0.59, green: 0.15, blue: 0.12), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .contentShape(Capsule())
    }
}
