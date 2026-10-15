import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Inline day archive adapter")
struct MorningInlineDayEvidenceArchiveTests {
    @Test func importDateNeverAssignsAnObservedDayAndOriginsStayExplicit() throws {
        let importedAt = try #require(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
        let observedAt = try #require(ISO8601DateFormatter().date(from: "2026-10-09T00:30:00Z"))
        let savedDay = try ObservationObservedDate(date: observedAt, timeZoneIdentifier: "America/Los_Angeles",
                                                    provenance: .userAssigned)
        let dated = try ObservationAcquisition(importedAt: importedAt, observedDate: savedDay, origin: .human,
            sourceKind: .image, sourceLabel: "Unit-test dated source", originalText: "Unit-test evidence")
        let undated = try ObservationAcquisition(importedAt: importedAt, origin: .human,
            sourceKind: .image, sourceLabel: "Unit-test undated import", originalText: "Unit-test evidence")
        let unknown = try ObservationAcquisition(importedAt: importedAt, observedDate: savedDay,
            sourceKind: .image, sourceLabel: "Unit-test unmarked source", originalText: "Unit-test evidence")
        let synthetic = try ObservationAcquisition(importedAt: importedAt, observedDate: savedDay, origin: .synthetic,
            sourceKind: .image, sourceLabel: "Unit-test demo source", originalText: "Unit-test evidence")
        let automated = try ObservationAcquisition(importedAt: importedAt, observedDate: savedDay, origin: .automated,
            sourceKind: .image, sourceLabel: "Unit-test automated source", originalText: "Unit-test evidence")
        let archive = try ObservationArchive(entries: [dated, undated, unknown, synthetic, automated])
        let projected = try archive.inlineDayEvidence
        #expect(projected.map(\.id) == archive.entries.map(\.id))
        #expect(projected[0].dayKey == "2026-10-08")
        #expect(projected[0].observedAt == observedAt)
        #expect(projected[0].timeZoneIdentifier == "America/Los_Angeles")
        #expect(projected[1].dayKey == nil)
        #expect(projected[1].observedAt == nil)
        #expect(projected.map(\.origin) == [.human, .human, .unknown, .synthetic, .automated])
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let importedDay = try MorningInlineDaySnapshot(selectedDate: importedAt, today: importedAt,
            calendar: paris, observations: projected)
        #expect(importedDay.state == .noSavedEvidence)
        #expect(importedDay.undatedObservationCount == 1)
        let originalDay = try MorningInlineDaySnapshot(selectedDate: observedAt.addingTimeInterval(-43_200),
            today: importedAt, calendar: paris, observations: projected)
        #expect(originalDay.observations.map(\.id) == [dated.id])
        #expect(originalDay.state == .evidenceOnly)
        #expect(archive.entries[1].observedDate == nil)
    }
}
