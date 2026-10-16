import SwiftUI
import Observation
import MorningCore
import MorningApple
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The clock behind the palette. Refreshes resolve the weather location's solar day
/// locally using the iPhone's date and time zone.
/// Debug builds and UI tests may pin a phase.
@Observable @MainActor
final class MorningThemeClock {
    static let shared = MorningThemeClock()

    private(set) var blend: MorningPhaseBlend
    private(set) var celestial: MorningCelestialScene
    var brandAppearance: MorningBrandAppearance {
        .resolve(moonOpacity: celestial.moon.opacity)
    }
    var brandAccessibilityValue: String {
        AppLanguage.localized(brandAppearance == .night ? "Night" : "Day")
    }
    private(set) var solar: MorningSolarDay = .fixed
    private(set) var location: WeatherLocation?
    private(set) var weatherScene: MorningWeatherScene?
    private(set) var weatherAttribution: WeatherAttributionInfo?
    private var weatherSnapshot: WeatherObservationSnapshot?
    private var weatherStatus: MorningBriefingSourceStatus = .notConfigured
    private let weatherPreview = MorningThemeClock.weatherFromArguments()
    #if DEBUG
    @ObservationIgnored private let recordingTimeline = MorningSolarRecordingTimeline.from(arguments: ProcessInfo.processInfo.arguments)
    @ObservationIgnored private let recordingStartUptime = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var recordingFrozenElapsed: TimeInterval?
    var isRecordingSolarDay: Bool { recordingTimeline != nil }
    private var recordingElapsed: TimeInterval {
        recordingFrozenElapsed ?? (ProcessInfo.processInfo.systemUptime - recordingStartUptime)
    }
    #endif
    var usesWeatherFixture: Bool { weatherPreview != nil }
    var weatherStatusDescription: String {
        if let weatherPreview {
            return AppLanguage.localized("Weather preview: \(weatherPreview) (sample).")
        }
        guard let location else { return AppLanguage.localized("Allow location access or choose a city in Your day to show its weather on Home.") }
        if let weatherSnapshot, weatherScene != nil {
            return AppLanguage.localized("\(location.displayName): \(weatherSnapshot.localizedConditionDescription()).")
        }
        switch weatherStatus {
        case .stale: return AppLanguage.localized("Weather for \(location.displayName) needs an update.")
        case .notConfigured: return AppLanguage.localized("Weather for \(location.displayName) is not available yet.")
        default: return AppLanguage.localized("Weather for \(location.displayName) is unavailable right now.")
        }
    }
    var skyAccessibilityDescription: String { weatherStatusDescription }
    var isUsingReferenceDay: Bool { location == nil }
    var solarSourceDescription: String {
        if let location {
            return String(localized: "Home follows sunrise and sunset in \(location.displayName), calculated on this iPhone using its date and time zone.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        return String(localized: "Allow location access or choose a city for local sunrise and sunset on Home. Until then, Home uses a 7 am–7 pm reference day following this iPhone's clock; it is not your local daylight.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }
    /// A pinned phase for previews, snapshots and tests. `nil` follows the clock.
    var pinnedPhase: MorningDayPhase? {
        didSet { refresh() }
    }

    init(now: Date = .now) {
        blend = MorningDayClock.blend(at: now)
        celestial = MorningCelestialClock.scene(at: now)
        pinnedPhase = Self.phaseFromArguments()
        refresh(now: now)
    }

    func setLocation(_ location: WeatherLocation?, now: Date = .now) {
        if self.location != location {
            weatherSnapshot = nil; weatherAttribution = nil; weatherScene = nil
            weatherStatus = .notConfigured
        }
        self.location = location
        refresh(now: now)
    }

    func setWeather(snapshot: WeatherObservationSnapshot?, status: MorningBriefingSourceStatus,
                    location: WeatherLocation?, now: Date = .now) {
        setLocation(location, now: now)
        weatherSnapshot = snapshot
        weatherStatus = status
        refreshWeather(now: now)
    }

    func refresh(now: Date = .now) {
        refreshVisuals(now: now)
        refreshWeather(now: now)
    }

    #if DEBUG
    /// Keep the selected pose still even when ordinary refreshes occur. Removing
    /// Reduce Motion rejoins the filming clock rather than restarting the take.
    func setRecordingReducedMotion(_ reduced: Bool) {
        guard recordingTimeline != nil else { return }
        if reduced {
            recordingFrozenElapsed = recordingFrozenElapsed ?? recordingElapsed
        } else {
            recordingFrozenElapsed = nil
        }
        refreshVisuals(now: .now)
    }

    /// Called only while the filming build is active. Weather freshness and the
    /// separate real-time cloud/star clock retain their ordinary cadence.
    func refreshRecordingFrame() -> Bool {
        guard let recordingTimeline, recordingFrozenElapsed == nil else { return false }
        refreshVisuals(now: .now)
        return recordingElapsed < recordingTimeline.duration
    }
    #endif

    private func refreshVisuals(now: Date) {
        let calendar = Calendar.current
        let day = location.flatMap {
            MorningSolarDay.calculate(for: now, latitude: $0.latitude, longitude: $0.longitude, calendar: calendar)
        } ?? .fixed
        if day != solar { solar = day }
        let next: MorningPhaseBlend
        let art: MorningCelestialScene
        #if DEBUG
        if let recordingTimeline {
            let minute = recordingTimeline.minute(atElapsed: recordingElapsed)
            next = MorningDayClock.blend(atMinute: minute, solar: day)
            art = MorningCelestialClock.scene(atMinute: minute, solar: day)
        } else {
            next = pinnedPhase.map(MorningPhaseBlend.steady) ?? MorningDayClock.blend(at: now, calendar: calendar, solar: day)
            art = pinnedPhase.map(MorningCelestialClock.scene(for:)) ?? MorningCelestialClock.scene(at: now, calendar: calendar, solar: day)
        }
        #else
        next = pinnedPhase.map(MorningPhaseBlend.steady) ?? MorningDayClock.blend(at: now, calendar: calendar, solar: day)
        art = pinnedPhase.map(MorningCelestialClock.scene(for:)) ?? MorningCelestialClock.scene(at: now, calendar: calendar, solar: day)
        #endif
        if next != blend { blend = next }
        if art != celestial { celestial = art }
    }

    private func refreshWeather(now: Date) {
        if let weatherPreview {
            weatherScene = Self.fixtureScene(weatherPreview)
            weatherAttribution = nil
            return
        }
        guard let location, let snapshot = weatherSnapshot,
              snapshot.isCurrent(for: location, at: now) else {
            if weatherSnapshot != nil { weatherStatus = .stale }
            weatherSnapshot = nil; weatherScene = nil; weatherAttribution = nil
            return
        }
        weatherScene = snapshot.scene
        weatherAttribution = snapshot.attribution
        weatherStatus = .fresh
    }

    private static func weatherFromArguments() -> String? {
        #if DEBUG
        if let option = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--theme-weather=") }) {
            let value = String(option.dropFirst("--theme-weather=".count))
            if ["unavailable", "calm", "breeze", "gustOnly", "strongWind", "westWind", "eastWind", "humid"].contains(value)
                || MorningWeatherCondition(rawValue: value) != nil { return value }
        }
        #endif
        return nil
    }

    private static func fixtureScene(_ name: String) -> MorningWeatherScene? {
        switch name {
        case "calm": MorningWeatherScene(condition: .clear, windSpeedMetersPerSecond: 0)
        case "breeze": MorningWeatherScene(condition: .clear, windSpeedMetersPerSecond: 2, windGustMetersPerSecond: 4)
        case "gustOnly": MorningWeatherScene(condition: .clear, windSpeedMetersPerSecond: 0, windGustMetersPerSecond: 12)
        case "strongWind": MorningWeatherScene(condition: .clear, windSpeedMetersPerSecond: 15, windGustMetersPerSecond: 25)
        case "westWind", "eastWind":
            MorningWeatherScene(condition: .partlyCloudy, cloudCover: 0.3,
                windSpeedMetersPerSecond: 8, windGustMetersPerSecond: 12,
                windDirectionDegrees: name == "westWind" ? 270 : 90)
        case "humid": MorningWeatherScene(condition: .haze, cloudCover: 0.15, humidity: 0.95, visibilityMeters: 3_000)
        default: MorningWeatherCondition(rawValue: name).map { MorningWeatherScene(condition: $0) }
        }
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

    /// Utility screens use native type; Home keeps its explicit Raleway reading face.
    enum Typography {
        static let display = Font.system(.largeTitle, weight: .bold)
        static let title = Font.system(.title, weight: .semibold)
        static let heading = Font.system(.headline)
        static let body = Font.system(.body)
        static let note = Font.system(.subheadline)
        static let label = Font.system(.caption, weight: .medium)
        static let number = Font.system(.caption).monospacedDigit()
        static let control = Font.system(.body, weight: .semibold)
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
            MorningStyle.background
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

/// Flat utility controls follow the native foreground and surface palette.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 22).padding(.vertical, 12).frame(minHeight: 48)
            .foregroundStyle(MorningStyle.onControl)
            .background(MorningStyle.controlTint, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
struct CompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 44)
            .foregroundStyle(MorningStyle.onControl)
            .background(MorningStyle.controlTint, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MorningTheme.Typography.control)
            .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 44)
            .foregroundStyle(MorningStyle.ink)
            .background(MorningStyle.selected, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MorningTheme.Typography.control)
            .foregroundStyle(MorningStyle.accent)
            .padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
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

extension Font {
    /// The system's default point size for each text style, so custom faces scale with
    /// Dynamic Type from the same starting point as San Francisco.
    fileprivate static func basePointSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    /// Raleway at a text style's size, following Dynamic Type.
    static func raleway(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom("Raleway", size: basePointSize(style), relativeTo: style).weight(weight)
    }

    /// DM Serif Display for titles. It has one weight; a requested weight is ignored.
    static func serif(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom("DM Serif Display", size: basePointSize(style) + 2, relativeTo: style)
    }
}

/// Home's sun-coloured horizontal lines over a whole page, fainter so text stays easy
/// to read: pale at the top, warmer lower down.
struct MorningQuietLines: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var random = MorningSeededRandom(seed: 11)
            context.addFilter(.blur(radius: 2.6))
            for _ in 0..<40 {
                let depth = random.next()
                let y = depth * size.height
                let length = size.width * random.range(0.35, 0.95)
                let x = random.range(-0.2, 1.0) * (size.width - length * 0.6)
                let thickness = random.range(2.0, 5.5)
                let colour: Color = depth < 0.35 ? Color(red: 0.97, green: 0.78, blue: 0.66)
                    : depth < 0.7 ? Color(red: 0.95, green: 0.60, blue: 0.40) : Color(red: 0.82, green: 0.38, blue: 0.26)
                let alpha = random.range(0.18, 0.38) * (0.4 + 0.6 * depth)
                let rect = CGRect(x: x, y: y, width: length, height: thickness)
                context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2),
                             with: .linearGradient(Gradient(stops: [.init(color: colour.opacity(0), location: 0),
                                                                    .init(color: colour.opacity(alpha), location: 0.3),
                                                                    .init(color: colour.opacity(alpha), location: 0.7),
                                                                    .init(color: colour.opacity(0), location: 1)]),
                                               startPoint: CGPoint(x: rect.minX, y: y), endPoint: CGPoint(x: rect.maxX, y: y)))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}


/// The clock stays live before entry, in every screen and while a sheet is open.
struct MorningBrandClockLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var enteredBackground = false
    #if DEBUG
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var recordingMotionReduced: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion")
    }
    #endif

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    MorningThemeClock.shared.refresh()
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                }
            }
            #if DEBUG
            .task(id: [scenePhase == .active, recordingMotionReduced]) {
                MorningThemeClock.shared.setRecordingReducedMotion(recordingMotionReduced)
                guard scenePhase == .active, !recordingMotionReduced,
                      MorningThemeClock.shared.isRecordingSolarDay else { return }
                while !Task.isCancelled {
                    guard MorningThemeClock.shared.refreshRecordingFrame() else { return }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
            #endif
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { enteredBackground = true }
                guard phase == .active else { return }
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if enteredBackground, arguments.contains("--ui-testing"), arguments.contains("--fixture-mode"),
                   arguments.contains("--ui-testing-brand-night-on-return") {
                    MorningThemeClock.shared.pinnedPhase = .night
                }
                #endif
                MorningThemeClock.shared.refresh()
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                MorningThemeClock.shared.refresh()
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                MorningThemeClock.shared.refresh()
            }
    }
}
