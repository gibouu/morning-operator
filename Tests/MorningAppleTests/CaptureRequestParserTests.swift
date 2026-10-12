import Foundation
import Testing
@testable import MorningApple

@Suite("Quick capture date suggestions")
struct CaptureRequestParserTests {
    private func parisCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    @Test("A dream keeps narrative dates without creating an action")
    func dreamRemainsNarrative() {
        let text = "Dream: I had to catch a train tomorrow morning"
        let parsed = CaptureRequestParser.parse(text)
        #expect(parsed.destination == .dream)
        #expect(parsed.originalText == text)
        #expect(parsed.content == "I had to catch a train tomorrow morning")
        #expect(parsed.suggestedDate == nil)
        #expect(!parsed.needsDateReview)
        #expect(CaptureRequestParser.parse("I dreamed about a mountain").destination == .dream)
        #expect(CaptureRequestParser.parse("An idea for tomorrow morning").destination == .thought)
    }

    @Test("An explicit relative reminder uses elapsed time, including compact speech text")
    func relativeHours() throws {
        let calendar = try parisCalendar()
        let now = try date(2026, 10, 9, 7, calendar: calendar)
        for phrase in ["in 4 hours", "in4hours", "in four hours", "dans 4 heures"] {
            let parsed = CaptureRequestParser.parse("Remind me to call Alex \(phrase)", now: now, calendar: calendar)
            #expect(parsed.destination == .reminder)
            #expect(parsed.content == "call Alex")
            #expect(parsed.suggestedDate == now.addingTimeInterval(4 * 3_600))
            #expect(parsed.needsDateReview)
            #expect(parsed.matchedDatePhrase == phrase)
        }
    }

    @Test("Next morning uses the next local day across the spring daylight-saving transition")
    func nextMorningAcrossDaylightSaving() throws {
        let calendar = try parisCalendar()
        let now = try date(2026, 3, 28, 23, calendar: calendar)
        let expected = try date(2026, 3, 29, 9, calendar: calendar)
        let parsed = CaptureRequestParser.parse("Reminder: water the plants next morning", now: now, calendar: calendar)
        #expect(parsed.suggestedDate == expected)
        let actual = try #require(parsed.suggestedDate)
        #expect(actual.timeIntervalSince(now) == TimeInterval(9 * 3_600))
        #expect(parsed.dateExplanation?.contains("09:00") == true)
        #expect(parsed.dateExplanation?.contains("Europe/Paris") == true)
    }

    @Test("Relative hours remain elapsed hours across the autumn repeated hour")
    func relativeHoursAcrossRepeatedHour() throws {
        let calendar = try parisCalendar()
        let now = try date(2026, 10, 25, 0, calendar: calendar)
        let parsed = CaptureRequestParser.parse("Reminder: check the oven in 4 hours", now: now, calendar: calendar)
        let actual = try #require(parsed.suggestedDate)
        #expect(actual.timeIntervalSince(now) == 4 * 3_600)
        #expect(calendar.component(.hour, from: actual) == 3)
    }

    @Test("French morning capture and calendar requests are drafts with review required")
    func frenchAndCalendar() throws {
        let calendar = try parisCalendar()
        let now = try date(2026, 10, 9, 7, calendar: calendar)
        let parsed = CaptureRequestParser.parse("Rappelle-moi de rappeler Alice demain matin", now: now, calendar: calendar)
        #expect(parsed.destination == .reminder)
        #expect(parsed.content == "rappeler Alice")
        #expect(parsed.suggestedDate == calendar.date(bySettingHour: 9, minute: 0, second: 0,
            of: try date(2026, 10, 10, 0, calendar: calendar)))
        let event = CaptureRequestParser.parse("Schedule breakfast with Sam tomorrow morning", now: now, calendar: calendar)
        #expect(event.destination == .calendar)
        #expect(event.content == "breakfast with Sam")
        #expect(event.needsDateReview)
    }

    @Test("Ambiguous, unsupported, invalid, and nonterminal date clauses stay intact")
    func unresolvedDatesAreNeverGuessed() {
        for body in ["call Alex tomorrow morning or in 4 hours", "call Alex on Friday",
                     "call Alex in 0 hours", "call Alex in 9999 hours", "call Alex tomorrow morning at 10",
                     "in 4 hours", "call Alex in 4 hours after lunch"] {
            let parsed = CaptureRequestParser.parse("Reminder: \(body)")
            #expect(parsed.suggestedDate == nil)
            #expect(parsed.content == body)
            #expect(parsed.needsDateReview)
        }
    }

    @Test("Midnight and custom morning times stay in the requested local calendar")
    func customMorningHour() throws {
        let calendar = try parisCalendar()
        let now = try date(2026, 12, 31, 23, calendar: calendar)
        let parsed = CaptureRequestParser.parse("Reminder: breakfast tomorrow morning", now: now, calendar: calendar, morningHour: 8)
        #expect(parsed.suggestedDate == (try date(2027, 1, 1, 8, calendar: calendar)))
        #expect(CaptureRequestParser.parse("Reminder: breakfast tomorrow morning", morningHour: 24).suggestedDate == nil)
    }
}
