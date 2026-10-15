import Foundation

/// Decorative positions only. Values describe a drawing in unit screen coordinates;
/// they do not describe measured sky positions, light exposure, or screen brightness.
public struct MorningCelestialPosition: Sendable, Equatable {
    public let centerX: Double
    public let centerY: Double
    public let opacity: Double
}

public struct MorningCelestialScene: Sendable, Equatable {
    public let sun: MorningCelestialPosition
    public let moon: MorningCelestialPosition
}

/// A continuous, local-time journey: sunrise begins at the bottom centre, the sun
/// climbs towards midday and returns to the horizon; a crescent takes over at night.
/// Fixed reference hours are used until the app has a real solar-time provider.
public enum MorningCelestialClock {
    public static func scene(atMinute minute: Double, solar: MorningSolarDay = .fixed) -> MorningCelestialScene {
        let usable = solar.sunriseMinute.isFinite && solar.sunsetMinute.isFinite
            && solar.sunriseMinute >= 75 && solar.sunsetMinute <= 1320
            && solar.sunsetMinute - solar.sunriseMinute >= 120
        let day = usable ? solar : .fixed
        let safeMinute = minute.isFinite ? minute : 12 * 60
        let wrapped = safeMinute.truncatingRemainder(dividingBy: 1440)
        let t = wrapped < 0 ? wrapped + 1440 : wrapped
        let rise = day.sunriseMinute, set = day.sunsetMinute
        let daylight = set - rise
        let dayProgress = clamp((t - rise) / daylight)
        let altitude = sin(.pi * dayProgress)
        // Smooth arrival below the horizon before sunrise and departure after sunset.
        let horizonOffset: Double
        if t < rise { horizonOffset = 0.10 * (1 - smooth((t - rise + 60) / 60)) }
        else if t > set { horizonOffset = 0.10 * smooth((t - set) / 60) }
        else { horizonOffset = 0 }
        let visible = smooth((t - rise + 45) / 60) * (1 - smooth((t - set + 15) / 60))
        let nightLength = 1440 - daylight
        let nightProgress: Double
        if t >= set { nightProgress = (t - set) / nightLength }
        else if t <= rise { nightProgress = (t + 1440 - set) / nightLength }
        else { nightProgress = 0 } // Below the horizon while hidden during the day.
        let moonAltitude = sin(.pi * clamp(nightProgress))
        return MorningCelestialScene(
            sun: .init(centerX: 0.5, centerY: max(0.2, 0.94 - 0.74 * altitude + horizonOffset), opacity: visible),
            moon: .init(centerX: 0.5, centerY: max(0.24, 0.94 - 0.70 * moonAltitude), opacity: 1 - visible))
    }

    public static func scene(at date: Date, calendar: Calendar = .current,
                             solar: MorningSolarDay = .fixed) -> MorningCelestialScene {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return scene(atMinute: Double(parts.hour ?? 12) * 60 + Double(parts.minute ?? 0)
                     + Double(parts.second ?? 0) / 60, solar: solar)
    }

    /// Pinning a theme in debug previews also pins its artwork to a representative time.
    public static func scene(for phase: MorningDayPhase) -> MorningCelestialScene {
        let minute: Double
        switch phase {
        case .dawn: minute = 6 * 60 + 45
        case .morning: minute = 9 * 60
        case .day: minute = 13 * 60
        case .evening: minute = 18 * 60 + 45
        case .night: minute = 23 * 60
        }
        return scene(atMinute: minute)
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func smooth(_ value: Double) -> Double {
        let t = clamp(value)
        return t * t * (3 - 2 * t)
    }
}
