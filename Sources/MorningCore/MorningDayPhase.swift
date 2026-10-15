import Foundation

/// The five lights of a day. The palette moves between them with the clock, so the
/// screen uses cooler paper in the morning and warmer paper in the evening.
/// This is a visual preference, not a claim about display brightness or health. Pure values: no SwiftUI, no clock read here.
public enum MorningDayPhase: String, CaseIterable, Sendable, Codable {
    case dawn, morning, day, evening, night
}

/// Sunrise and sunset as minutes after local midnight. Fixed hours stand in until a
/// solar source exists; they already give the day a believable shape.
public struct MorningSolarDay: Sendable, Equatable {
    public var sunriseMinute: Double
    public var sunsetMinute: Double

    public init(sunriseMinute: Double, sunsetMinute: Double) {
        self.sunriseMinute = sunriseMinute
        self.sunsetMinute = sunsetMinute
    }

    /// 07:00 and 19:00.
    public static let fixed = MorningSolarDay(sunriseMinute: 7 * 60, sunsetMinute: 19 * 60)
}

/// Where the day is between two phases. `progress` is 0 at `from` and 1 at `to`,
/// already eased so a one-minute tick never jumps.
public struct MorningPhaseBlend: Sendable, Equatable {
    public var from: MorningDayPhase
    public var to: MorningDayPhase
    public var progress: Double

    public init(from: MorningDayPhase, to: MorningDayPhase, progress: Double) {
        self.from = from
        self.to = to
        self.progress = min(1, max(0, progress))
    }

    public static func steady(_ phase: MorningDayPhase) -> MorningPhaseBlend {
        MorningPhaseBlend(from: phase, to: phase, progress: 0)
    }

    /// The phase that currently dominates.
    public var dominant: MorningDayPhase { progress < 0.5 ? from : to }
}

public enum MorningDayClock {
    /// A keyframe: at `minute` the light is fully `phase`. Between two keyframes of
    /// different phases the palette crosses over; between equal ones it holds.
    struct Keyframe { let minute: Double; let phase: MorningDayPhase }

    static func keyframes(for solar: MorningSolarDay) -> [Keyframe] {
        let rise = solar.sunriseMinute, set = solar.sunsetMinute
        return [
            Keyframe(minute: rise - 75, phase: .night),
            Keyframe(minute: rise - 15, phase: .dawn),
            Keyframe(minute: rise + 30, phase: .dawn),
            Keyframe(minute: rise + 75, phase: .morning),
            Keyframe(minute: rise + 180, phase: .morning),
            Keyframe(minute: rise + 300, phase: .day),
            Keyframe(minute: set - 120, phase: .day),
            Keyframe(minute: set - 45, phase: .evening),
            Keyframe(minute: set + 30, phase: .evening),
            Keyframe(minute: set + 120, phase: .night)
        ]
    }

    /// The blend for a minute of the day (0 ..< 1440; other values wrap).
    public static func blend(atMinute minute: Double, solar: MorningSolarDay = .fixed) -> MorningPhaseBlend {
        let frames = keyframes(for: solar)
        let dayLength = 24.0 * 60
        var t = minute.truncatingRemainder(dividingBy: dayLength)
        if t < 0 { t += dayLength }
        guard let first = frames.first, let last = frames.last else { return .steady(.day) }
        // Before the first or after the last keyframe the night holds across midnight.
        if t < first.minute || t >= last.minute { return .steady(last.phase) }
        for index in 0..<(frames.count - 1) {
            let a = frames[index], b = frames[index + 1]
            guard t >= a.minute, t < b.minute else { continue }
            if a.phase == b.phase { return .steady(a.phase) }
            let linear = (t - a.minute) / (b.minute - a.minute)
            return MorningPhaseBlend(from: a.phase, to: b.phase, progress: smoothstep(linear))
        }
        return .steady(last.phase)
    }

    /// The blend for a date in a calendar's time zone.
    public static func blend(at date: Date, calendar: Calendar = .current, solar: MorningSolarDay = .fixed) -> MorningPhaseBlend {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double(parts.hour ?? 12) * 60 + Double(parts.minute ?? 0) + Double(parts.second ?? 0) / 60
        return blend(atMinute: minute, solar: solar)
    }

    static func smoothstep(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }
}

/// One colour as sRGB components in 0...1. Interpolation and contrast live here so a
/// test can prove every phase reads, without a display.
public struct MorningRGB: Sendable, Equatable, Hashable {
    public var red: Double, green: Double, blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    public static func mix(_ a: MorningRGB, _ b: MorningRGB, _ t: Double) -> MorningRGB {
        let c = min(1, max(0, t))
        return MorningRGB(a.red + (b.red - a.red) * c, a.green + (b.green - a.green) * c, a.blue + (b.blue - a.blue) * c)
    }

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2 contrast ratio, 1...21.
    public static func contrast(_ a: MorningRGB, _ b: MorningRGB) -> Double {
        let l1 = max(a.luminance, b.luminance), l2 = min(a.luminance, b.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

/// The ink and paper of one moment of the day. Two inks on cream paper: ultramarine
/// for everything that is structure and text, burnt orange for the one thing that
/// matters now. Paper gets cooler and brighter towards the morning, warmer and dimmer
/// towards the night.
public struct MorningPaletteValues: Sendable, Equatable {
    /// The page.
    public var paper: MorningRGB
    /// Cards, rows, the raised sheet.
    public var surface: MorningRGB
    /// The halftone dot, laid over the paper at a low opacity.
    public var dot: MorningRGB
    /// Text and rules.
    public var ink: MorningRGB
    /// Secondary text; always at least 4.5:1 on paper and surface.
    public var inkSoft: MorningRGB
    /// The one accent: marks, the sun, the italic word. At least 3:1 on paper; never text.
    public var accent: MorningRGB
    /// The accent for small text and icons, deep enough for 4.5:1.
    public var accentText: MorningRGB
    /// Text on an ink fill (the primary control). The accent never carries text.
    public var onInk: MorningRGB
    /// Good news: a saved morning, an approved routine.
    public var positive: MorningRGB

    public init(paper: MorningRGB, surface: MorningRGB, dot: MorningRGB, ink: MorningRGB, inkSoft: MorningRGB,
                accent: MorningRGB, accentText: MorningRGB, onInk: MorningRGB, positive: MorningRGB) {
        self.paper = paper; self.surface = surface; self.dot = dot; self.ink = ink; self.inkSoft = inkSoft
        self.accent = accent; self.accentText = accentText; self.onInk = onInk; self.positive = positive
    }

    public static func mix(_ a: MorningPaletteValues, _ b: MorningPaletteValues, _ t: Double) -> MorningPaletteValues {
        MorningPaletteValues(
            paper: .mix(a.paper, b.paper, t), surface: .mix(a.surface, b.surface, t), dot: .mix(a.dot, b.dot, t),
            ink: .mix(a.ink, b.ink, t), inkSoft: .mix(a.inkSoft, b.inkSoft, t),
            accent: .mix(a.accent, b.accent, t), accentText: .mix(a.accentText, b.accentText, t),
            onInk: .mix(a.onInk, b.onInk, t), positive: .mix(a.positive, b.positive, t))
    }

    /// The palette for a blend, mixed between its two phases.
    public static func resolve(_ blend: MorningPhaseBlend, dark: Bool) -> MorningPaletteValues {
        let a = phase(blend.from, dark: dark), b = phase(blend.to, dark: dark)
        return blend.from == blend.to ? a : mix(a, b, blend.progress)
    }

    // MARK: The five lights

    /// Light appearance: cream paper, ultramarine ink.
    /// Dark appearance: the paper is the ink, the ink is the paper; the night is the
    /// print turned over.
    public static func phase(_ phase: MorningDayPhase, dark: Bool) -> MorningPaletteValues {
        switch (phase, dark) {
        case (.dawn, false):
            // The dawn reference: a warm, slightly rosy cream, ink not yet at full blue.
            return MorningPaletteValues(
                paper: .init(hex: 0xF3E6D6), surface: .init(hex: 0xFAF1E5), dot: .init(hex: 0x8C5A4A),
                ink: .init(hex: 0x24305E), inkSoft: .init(hex: 0x5A5A6E),
                accent: .init(hex: 0xCF5220), accentText: .init(hex: 0x9B3A12), onInk: .init(hex: 0xFBF3E6),
                positive: .init(hex: 0x2C6045))
        case (.morning, false):
            // The brightest, coolest paper of the day: a blue-tinted cream with full ultramarine.
            return MorningPaletteValues(
                paper: .init(hex: 0xF6F3EC), surface: .init(hex: 0xFDFBF6), dot: .init(hex: 0x1D3A8A),
                ink: .init(hex: 0x16307A), inkSoft: .init(hex: 0x4A5578),
                accent: .init(hex: 0xCF5220), accentText: .init(hex: 0x9B3A12), onInk: .init(hex: 0xFBF6EC),
                positive: .init(hex: 0x27624A))
        case (.day, false):
            // The riso print as printed: the kit's cream and ink blue.
            return MorningPaletteValues(
                paper: .init(hex: 0xF4ECDD), surface: .init(hex: 0xFCF7EE), dot: .init(hex: 0x1D3A8A),
                ink: .init(hex: 0x1A2F6E), inkSoft: .init(hex: 0x4F556B),
                accent: .init(hex: 0xCF5220), accentText: .init(hex: 0x9B3A12), onInk: .init(hex: 0xFBF3E6),
                positive: .init(hex: 0x2C6045))
        case (.evening, false):
            // Amber paper, less blue in the ink; the orange comes forward.
            return MorningPaletteValues(
                paper: .init(hex: 0xEFDFC4), surface: .init(hex: 0xF7EBD7), dot: .init(hex: 0x8A4A2A),
                ink: .init(hex: 0x27305A), inkSoft: .init(hex: 0x5B5560),
                accent: .init(hex: 0xC84E1E), accentText: .init(hex: 0x8F3410), onInk: .init(hex: 0xFBF0DE),
                positive: .init(hex: 0x2F5E44))
        case (.night, false):
            // Dim amber-cream for a lit room at night; still cream, never a dark theme by day.
            return MorningPaletteValues(
                paper: .init(hex: 0xE6D4B4), surface: .init(hex: 0xEFE0C7), dot: .init(hex: 0x6E3F28),
                ink: .init(hex: 0x272B4C), inkSoft: .init(hex: 0x56525C),
                accent: .init(hex: 0xC2471A), accentText: .init(hex: 0x843010), onInk: .init(hex: 0xF8ECD8),
                positive: .init(hex: 0x2F5E44))
        case (.dawn, true):
            return MorningPaletteValues(
                paper: .init(hex: 0x1B1A2E), surface: .init(hex: 0x27253D), dot: .init(hex: 0xD9A27A),
                ink: .init(hex: 0xF0E2CE), inkSoft: .init(hex: 0xC2B3A6),
                accent: .init(hex: 0xE8814A), accentText: .init(hex: 0xF2A26F), onInk: .init(hex: 0x1B1A2E),
                positive: .init(hex: 0x8FC7A6))
        case (.morning, true):
            return MorningPaletteValues(
                paper: .init(hex: 0x0F1F45), surface: .init(hex: 0x1A2C57), dot: .init(hex: 0xBFD0FF),
                ink: .init(hex: 0xF4F1EA), inkSoft: .init(hex: 0xC3C8D8),
                accent: .init(hex: 0xE8814A), accentText: .init(hex: 0xF2A26F), onInk: .init(hex: 0x0F1F45),
                positive: .init(hex: 0x8FC7A6))
        case (.day, true):
            return MorningPaletteValues(
                paper: .init(hex: 0x12224A), surface: .init(hex: 0x1D2F5C), dot: .init(hex: 0xC9D4F5),
                ink: .init(hex: 0xF3ECDD), inkSoft: .init(hex: 0xC4C3C9),
                accent: .init(hex: 0xE8814A), accentText: .init(hex: 0xF2A26F), onInk: .init(hex: 0x12224A),
                positive: .init(hex: 0x8FC7A6))
        case (.evening, true):
            return MorningPaletteValues(
                paper: .init(hex: 0x1A1626), surface: .init(hex: 0x272035), dot: .init(hex: 0xD9A27A),
                ink: .init(hex: 0xEFDFC4), inkSoft: .init(hex: 0xC2AE9A),
                accent: .init(hex: 0xE07A42), accentText: .init(hex: 0xF0A06C), onInk: .init(hex: 0x1A1626),
                positive: .init(hex: 0x8FC7A6))
        case (.night, true):
            // The deepest ink with warm, readable text.
            return MorningPaletteValues(
                paper: .init(hex: 0x0B1226), surface: .init(hex: 0x161D34), dot: .init(hex: 0xB89A78),
                ink: .init(hex: 0xE6D4B4), inkSoft: .init(hex: 0xB3A48E),
                accent: .init(hex: 0xD96F3A), accentText: .init(hex: 0xEE9C68), onInk: .init(hex: 0x0B1226),
                positive: .init(hex: 0x8FC7A6))
        }
    }
}
