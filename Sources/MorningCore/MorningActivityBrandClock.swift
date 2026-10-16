import Foundation

/// The app's solar clock without its location or any private routine content.
/// Live Activities render on system updates, not on a widget timeline.
public struct MorningActivityBrandClock: Codable, Hashable, Sendable {
    private enum Condition: String, Codable { case dayAndNight, allDay, allNight }
    private let sunriseMinute: Double
    private let sunsetMinute: Double
    private let condition: Condition
    private let timeZoneIdentifier: String
    private let pinnedAppearance: MorningBrandAppearance?

    public init(solar: MorningSolarDay, calendar: Calendar = .current,
                pinnedAppearance: MorningBrandAppearance? = nil) {
        let day = solar.validated
        sunriseMinute = day.sunriseMinute.isFinite ? day.sunriseMinute : MorningSolarDay.fixed.sunriseMinute
        sunsetMinute = day.sunsetMinute.isFinite ? day.sunsetMinute : MorningSolarDay.fixed.sunsetMinute
        switch day.condition {
        case .dayAndNight: condition = .dayAndNight
        case .allDay: condition = .allDay
        case .allNight: condition = .allNight
        }
        timeZoneIdentifier = calendar.timeZone.identifier
        self.pinnedAppearance = pinnedAppearance
    }

    public func appearance(at date: Date) -> MorningBrandAppearance {
        if let pinnedAppearance { return pinnedAppearance }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let solarCondition: MorningSolarDay.Condition = switch condition {
        case .dayAndNight: .dayAndNight
        case .allDay: .allDay
        case .allNight: .allNight
        }
        let solar = MorningSolarDay(sunriseMinute: sunriseMinute, sunsetMinute: sunsetMinute,
                                    condition: solarCondition)
        return .resolve(moonOpacity: MorningCelestialClock.scene(at: date, calendar: calendar, solar: solar).moon.opacity)
    }
}
