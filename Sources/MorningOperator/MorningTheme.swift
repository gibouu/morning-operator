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
    private(set) var celestial: MorningCelestialScene
    /// Sunrise and sunset in minutes. Fixed hours until a solar source supplies them.
    var solar: MorningSolarDay = .fixed
    /// A pinned phase for previews, snapshots and tests. `nil` follows the clock.
    var pinnedPhase: MorningDayPhase? {
        didSet { refresh() }
    }

    init(now: Date = .now) {
        blend = MorningDayClock.blend(at: now)
        celestial = MorningCelestialClock.scene(at: now)
        pinnedPhase = Self.phaseFromArguments()
        if pinnedPhase != nil { refresh(now: now) }
    }

    func refresh(now: Date = .now) {
        let next = pinnedPhase.map(MorningPhaseBlend.steady) ?? MorningDayClock.blend(at: now, solar: solar)
        if next != blend { blend = next }
        let art = pinnedPhase.map(MorningCelestialClock.scene(for:)) ?? MorningCelestialClock.scene(at: now, solar: solar)
        if art != celestial { celestial = art }
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
/// local time and Increase Contrast. System dark mode does not change MORE's paper.
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
    /// Opaque paper tint for selection; texture never sits under selected-row text.
    var selected: Color { dynamic(\.selectedSurface) }

    private func dynamic(_ token: KeyPath<MorningPaletteValues, MorningRGB>,
                         highContrast: KeyPath<MorningPaletteValues, MorningRGB>? = nil) -> Color {
        let blend = blend
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            let values = MorningPaletteValues.resolve(blend, dark: false)
            let key = traits.accessibilityContrast == .high ? (highContrast ?? token) : token
            let c = values[keyPath: key]
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { _ in
            let values = MorningPaletteValues.resolve(blend, dark: false)
            let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let c = values[keyPath: high ? (highContrast ?? token) : token]
            return NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #endif
    }

    /// The plain values, for drawing code that needs numbers rather than a dynamic colour.
    func values(dark: Bool) -> MorningPaletteValues { MorningPaletteValues.resolve(blend, dark: false) }

    // MARK: Type

    /// One native sans-serif family for titles, reading, dates and controls.
    /// Semantic styles keep the hierarchy and follow Dynamic Type.
    enum Typography {
        static let display = Font.system(.largeTitle, design: .default, weight: .semibold)
        static let title = Font.system(.title, design: .default, weight: .semibold)
        static let heading = Font.system(.headline, design: .default, weight: .semibold)
        static let body = Font.system(.body, design: .default)
        static let note = Font.system(.subheadline, design: .default)
        static let label = Font.system(.caption, design: .default, weight: .medium)
        static let number = Font.system(.caption, design: .default).monospacedDigit()
        static let control = Font.system(.body, design: .default, weight: .semibold)
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

/// Quiet opaque paper with separate celestial art. Reduce Transparency keeps the plain sheet.
/// The solar journey follows local time; the retained progress argument is source
/// compatible with older callers and does not move the sky with routine completion.
struct MorningPaper: View {
    var showsSun = true
    var progress: Double = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            MorningPaperSurface()
            if showsSun && !reduceTransparency {
                MorningCelestialArtwork(scene: MorningThemeClock.shared.celestial)
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
                var column = 0
                while x < size.width + cell {
                    // Deterministic ink variation: a printed screen, not a moving noise field.
                    let grain = CGFloat((row * 73 + column * 37) % 11) / 10
                    let r = radius * (0.65 + grain * 0.5)
                    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += cell
                    column += 1
                }
                y += cell * 0.866
                row += 1
            }
            context.fill(path, with: .color(color))
        }
        .opacity(opacity)
    }
}

/// Compatibility wrapper for earlier previews. New screens use the full local-time scene.
struct MorningHalftoneSun: View {
    var progress: Double
    var diameter: CGFloat = 160
    var body: some View {
        MorningSolarArtwork()
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Controls

/// A printed paper ticket. The dotted edge and offset ink impression belong to
/// MORE; no system capsule or glass is involved.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let theme = MorningTheme.current
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .frame(minHeight: 48)
            .foregroundStyle(theme.ink)
            .background(theme.selected, in: RoundedRectangle(cornerRadius: 8))
            .overlay(MorningDottedFrame(cornerRadius: 8, spacing: 5, dotRadius: 1.15).fill(theme.ink))
            .offset(y: configuration.isPressed ? 2 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
    }
}
/// The same printed ticket at a smaller size, for the case where two actions must
/// sit side by side (record / choose).
struct CompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let theme = MorningTheme.current
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(minHeight: 44)
            .foregroundStyle(theme.ink)
            .background(theme.selected, in: RoundedRectangle(cornerRadius: 8))
            .overlay(MorningDottedFrame(cornerRadius: 8, spacing: 5, dotRadius: 1).fill(theme.ink))
            .offset(y: configuration.isPressed ? 2 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
    }
}
/// Secondary actions read like an ink annotation with a dotted underline.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let theme = MorningTheme.current
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(minHeight: 44)
            .foregroundStyle(theme.ink)
            .background(theme.surface.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .bottom) {
                MorningDottedFrame(cornerRadius: 0, spacing: 6, dotRadius: 0.9)
                    .fill(theme.ink.opacity(0.7)).frame(height: 3).padding(.horizontal, 10)
            }
            .contentShape(Rectangle())
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
