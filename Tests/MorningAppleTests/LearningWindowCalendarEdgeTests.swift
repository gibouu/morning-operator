import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Synthetic recordings only. UTC fixtures make the expected instants independent of
/// Calendar's resolution of nonexistent or repeated local times.
@Suite("Learning windows on unusual calendars: fractional offsets, the date line and odd clock changes")
struct LearningWindowCalendarEdgeTests {
    private func utc(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func local(_ date: Date, in zone: String) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let p = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                      p.year!, p.month!, p.day!, p.hour!, p.minute!, p.second!)
    }

    private func window(zone: String, minute: Int, startedAt: Date, mornings: Int = 1) throws -> LearningWindow {
        var value = try LearningWindow(startMinuteOfDay: minute, durationSeconds: 300,
            weekdays: Set(LearningWindowWeekday.allCases), timeZoneIdentifier: zone,
            morningCount: mornings, createdAt: startedAt.addingTimeInterval(-60), limits: .currentCapture,
            lateStartAllowanceSeconds: 0, earlyEndAllowanceSeconds: 0)
        try value.start(at: startedAt)
        return value
    }

    private func recording(_ start: Date, seconds: Double = 300, zone: String) throws -> ObservationAcquisition {
        let frames = try (0...20).map { index in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) / 1_000,
                actualTimeSeconds: seconds * Double(index) / 20, outcome: .observed,
                text: index % 4 < 2 ? "Feed" : "Chess")
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: seconds, frames: frames)
        let decisions = frames.map { frame in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds,
                timeBasis: frame.timeBasis,
                evidence: .identified(app: .init(key: "visual-context:\(frame.text)", displayName: frame.text),
                                      reference: frame.evidenceReference), evidenceQuote: frame.text)
        }
        let classification = ObservationContextClassification(decisions: decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result; no model call")
        return try .init(observedDate: .init(date: start, timeZoneIdentifier: zone, provenance: .recordingSession),
            origin: .human, sourceKind: .video, sourceLabel: "Synthetic recording",
            originalText: evidence.renderedText, videoEvidence: evidence, classification: classification,
            recordingContext: .init(startedAt: start, timeZoneIdentifier: zone))
    }

    private func declared(_ entries: [ObservationAcquisition], to window: LearningWindow) throws -> ObservationArchive {
        var archive = ObservationArchive()
        for entry in entries {
            try archive.insert(entry)
            let context = try #require(entry.recordingContext)
            let evidence = try #require(entry.videoEvidence)
            try archive.declareCapture(of: entry.id, to: window,
                at: context.startedAt.addingTimeInterval(evidence.durationSeconds + 60))
        }
        return archive
    }

    private func profile(_ window: LearningWindow, _ archive: ObservationArchive, now: Date) throws -> ComparableMorningProfile {
        try ComparableMorningProfile(window: window, archive: archive, now: now, maximumSampleGapSeconds: 60)
    }

    private func expectWholeMornings(_ window: LearningWindow, _ archive: ObservationArchive,
                                     keys: [String], entries: [ObservationAcquisition], now: Date) throws {
        let report = LearningWindowReport(window: window, archive: archive, now: now)
        #expect(report.mornings.map(\.dayKey) == keys)
        #expect(report.mornings.map(\.acquisitionIDs) == entries.map { [$0.id] })
        #expect(report.mornings.allSatisfy { $0.status == .observedInWindow && $0.countsTowardProgress
            && $0.coverage?.coveredSeconds == 300 })
        #expect(report.progress.adequateMorningCount == keys.count)
        #expect(report.ignoredAcquisitionIDs.isEmpty && report.reassignedAcquisitionIDs.isEmpty)
        let comparable = try profile(window, archive, now: now)
        #expect(comparable.report.includedDayKeys == keys)
        #expect(comparable.report.missingDayKeys.isEmpty && comparable.report.excludedDays.isEmpty)
        #expect(comparable.acquisitionIDsByDayKey == Dictionary(uniqueKeysWithValues: zip(keys, entries.map { [$0.id] })))
        #expect(comparable.acquisitionIDsByDayKey.values.flatMap { $0 }.count == entries.count)
        #expect(comparable.otherTimeZoneAcquisitionIDs.isEmpty && comparable.undatedAcquisitionIDs.isEmpty)
    }

    @Test func fractionalOffsetZonesUseTheSameInstantAcrossEveryPair() throws {
        // Offsets on 12 October 2026: +05:30, +05:45, +10:30, +11:00, +13:45.
        let zones = [("Asia/Kolkata", 330), ("Asia/Kathmandu", 345), ("Australia/Adelaide", 630),
                     ("Australia/Lord_Howe", 660), ("Pacific/Chatham", 825)]
        let nominalMidnight = try utc("2026-10-12T00:00:00Z")
        for (windowZone, offset) in zones {
            let midnight = nominalMidnight.addingTimeInterval(-Double(offset * 60))
            let start = midnight.addingTimeInterval(600)
            #expect(try local(start, in: windowZone) == "2026-10-12 00:10:00")
            let learning = try window(zone: windowZone, minute: 10, startedAt: midnight)
            #expect(learning.schedule(asOf: midnight).mornings.first?.expectedStart == start)
            for (phoneZone, _) in zones {
                let entry = try recording(start, zone: phoneZone)
                let archive = try declared([entry], to: learning)
                let capture = try #require(archive.entry(id: entry.id)?.windowCapture)
                #expect(capture.dayKey == "2026-10-12" && capture.timeZoneIdentifier == windowZone)
                #expect(capture.actualStart == start && capture.expectedStart == start && learning.counts(capture))
                try expectWholeMornings(learning, archive, keys: ["2026-10-12"], entries: [entry],
                                        now: start.addingTimeInterval(600))
            }
        }
    }

    @Test func dateLineTravelTwoCivilDatesApartNeverCollidesWithAnotherMorning() throws {
        // +14 versus -11: the first pair is Oct12 00:30 / Oct10 23:30;
        // the reverse pair is Oct12 23:30 / Oct14 00:30. Both differ by TWO date labels.
        let cases = [("Pacific/Kiritimati", "Pacific/Pago_Pago", 30, "2026-10-11T10:30:00Z", "2026-10-10"),
                     ("Pacific/Pago_Pago", "Pacific/Kiritimati", 23 * 60 + 30, "2026-10-13T10:30:00Z", "2026-10-14")]
        for (windowZone, phoneZone, minute, timestamp, phoneDay) in cases {
            let first = try utc(timestamp)
            let learning = try window(zone: windowZone, minute: minute,
                                      startedAt: first.addingTimeInterval(-600), mornings: 3)
            let entries = try (0..<3).map { try recording(first.addingTimeInterval(Double($0) * 86_400), zone: phoneZone) }
            #expect(entries[0].observedDate?.dayKey == phoneDay)
            let archive = try declared(entries, to: learning)
            let keys = ["2026-10-12", "2026-10-13", "2026-10-14"]
            #expect(archive.entries.map { $0.windowCapture?.dayKey } == keys.map(Optional.some))
            try expectWholeMornings(learning, archive, keys: keys, entries: entries,
                                    now: first.addingTimeInterval(2 * 86_400 + 600))
        }
    }

    @Test func halfHourDSTOnlyOnThePhoneDoesNotMoveTheKathmanduWindow() throws {
        let first = try utc("2026-04-04T01:15:00Z") // Kathmandu 07:00, Lord Howe 12:15.
        let second = try utc("2026-04-05T01:15:00Z") // Kathmandu 07:00, Lord Howe 11:45.
        let staleClock = try utc("2026-04-06T01:45:00Z") // Still recording at Lord Howe 12:15.
        #expect(try local(first, in: "Australia/Lord_Howe") == "2026-04-04 12:15:00")
        #expect(try local(second, in: "Australia/Lord_Howe") == "2026-04-05 11:45:00")
        #expect(try local(staleClock, in: "Australia/Lord_Howe") == "2026-04-06 12:15:00")
        let learning = try window(zone: "Asia/Kathmandu", minute: 420,
                                  startedAt: first.addingTimeInterval(-600), mornings: 3)
        let entries = try [first, second, staleClock].map { try recording($0, zone: "Australia/Lord_Howe") }
        let archive = try declared(entries, to: learning)
        let now = staleClock.addingTimeInterval(600)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.expectedStart) == [first, second, second.addingTimeInterval(86_400)])
        #expect(report.mornings.map(\.status) == [.observedInWindow, .observedInWindow, .observedOutsideWindow])
        #expect(report.mornings.map(\.acquisitionIDs) == entries.map { [$0.id] })
        #expect(report.mornings[2].coverage?.coveredSeconds == 0)
        let comparable = try profile(learning, archive, now: now)
        #expect(comparable.report.includedDayKeys == ["2026-04-04", "2026-04-05"])
        #expect(comparable.report.excludedDays == [.init(dayKey: "2026-04-06", reason: .partialCapture)])
        #expect(comparable.report.missingDayKeys.isEmpty)
    }

    @Test func recordingsStraddlingClippingAndTouchingAChathamWindowUseElapsedCoverage() throws {
        let first = try utc("2026-10-11T17:15:00Z") // Chatham Oct12 07:00.
        let learning = try window(zone: "Pacific/Chatham", minute: 420,
                                  startedAt: first.addingTimeInterval(-600), mornings: 3)
        let entries = [try recording(first.addingTimeInterval(-30), seconds: 390, zone: "Asia/Kolkata"),
                       try recording(first.addingTimeInterval(86_400 + 120), seconds: 180, zone: "Australia/Adelaide"),
                       try recording(first.addingTimeInterval(2 * 86_400 - 120), seconds: 120, zone: "Asia/Kathmandu")]
        let archive = try declared(entries, to: learning)
        let now = first.addingTimeInterval(2 * 86_400 + 600)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedInWindow, .observedPartly, .observedOutsideWindow])
        #expect(report.mornings.map { $0.coverage?.coveredSeconds } == [300, 180, 0])
        #expect(report.mornings[0].coverage?.startedLateSeconds == 0 && report.mornings[0].coverage?.endedEarlySeconds == 0)
        #expect(report.mornings[1].coverage?.startedLateSeconds == 120)
        #expect(report.mornings[2].coverage?.startedLateSeconds == nil)
        #expect(report.mornings.map(\.acquisitionIDs) == entries.map { [$0.id] })
        let comparable = try profile(learning, archive, now: now)
        #expect(comparable.report.includedDayKeys == ["2026-10-12"])
        #expect(comparable.report.excludedDays == [.init(dayKey: "2026-10-13", reason: .partialCapture),
                                                 .init(dayKey: "2026-10-14", reason: .partialCapture)])
    }

    @Test func crossingWindowCalendarMidnightCannotDonateCoverageToTheNextMorning() throws {
        let learning = try window(zone: "Asia/Kathmandu", minute: 5,
                                  startedAt: utc("2026-10-11T18:15:00Z"), mornings: 2)
        // Nepal Oct12 23:59 through Oct13 00:14: covers the entire next 00:05 window,
        // but the capture contract dates this recording solely by its start.
        let start = try utc("2026-10-12T18:14:00Z")
        let entry = try recording(start, seconds: 900, zone: "Pacific/Kiritimati")
        #expect(entry.observedDate?.dayKey == "2026-10-13")
        #expect(try local(start, in: "Asia/Kathmandu") == "2026-10-12 23:59:00")
        #expect(try local(start.addingTimeInterval(900), in: "Asia/Kathmandu") == "2026-10-13 00:14:00")
        var archive = try declared([entry], to: learning)
        #expect(archive.entry(id: entry.id)?.windowCapture?.dayKey == "2026-10-12")
        let now = start.addingTimeInterval(1_200)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedOutsideWindow, .missed])
        #expect(report.mornings.map(\.acquisitionIDs) == [[entry.id], []])
        let comparable = try profile(learning, archive, now: now)
        #expect(comparable.report.excludedDays == [.init(dayKey: "2026-10-12", reason: .partialCapture)])
        #expect(comparable.report.missingDayKeys == ["2026-10-13"])
        #expect(comparable.acquisitionIDsByDayKey == ["2026-10-12": [entry.id]])
        // At midnight itself a different recording belongs to the new day, even though
        // both recordings are filed under Oct13 on the phone's calendar.
        let boundary = try recording(start.addingTimeInterval(60), seconds: 600, zone: "Pacific/Kiritimati")
        try archive.insert(boundary)
        try archive.declareCapture(of: boundary.id, to: learning, at: now)
        let after = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(after.mornings.map(\.acquisitionIDs) == [[entry.id], [boundary.id]])
        #expect(after.mornings.map(\.status) == [.observedOutsideWindow, .observedInWindow])
        #expect(try profile(learning, archive, now: now).report.includedDayKeys == ["2026-10-13"])
    }

    @Test func twoRecordingsAtOneInstantAreOneDuplicateDayAndNeverDoubleCoverage() throws {
        let learning = try window(zone: "Australia/Adelaide", minute: 10,
                                  startedAt: utc("2026-10-10T13:30:00Z"), mornings: 2)
        let instant = try utc("2026-10-11T13:40:00Z") // Adelaide Oct12 00:10.
        let entries = [try recording(instant, zone: "Pacific/Kiritimati"),
                       try recording(instant, zone: "Pacific/Pago_Pago")]
        #expect(entries.map { $0.observedDate?.dayKey } == ["2026-10-12", "2026-10-11"])
        #expect(entries[0].videoEvidence?.id != entries[1].videoEvidence?.id)
        let archive = try declared(entries, to: learning)
        let now = instant.addingTimeInterval(600)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.missed, .observedInWindow])
        #expect(report.mornings.map(\.acquisitionIDs) == [[], entries.map(\.id)])
        #expect(report.mornings[1].coverage?.coveredSeconds == 300)
        #expect(report.mornings[1].notCountedReason == .severalRecordings)
        #expect(report.progress.adequateMorningCount == 0)
        let comparable = try profile(learning, archive, now: now)
        #expect(comparable.report.excludedDays == [.init(dayKey: "2026-10-12", reason: .duplicateDay)])
        #expect(comparable.report.missingDayKeys == ["2026-10-11"])
        #expect(comparable.acquisitionIDsByDayKey == ["2026-10-12": entries.map(\.id)])
    }

    @Test func gapsOfFifteenThirtySixtyAndOneHundredEightyMinutesChooseTheirFirstInstant() throws {
        // Kathmandu's 15-minute and Casey's 3-hour jumps are political offset changes,
        // not seasonal DST. None of these nonexistent wall times is parsed as a fixture.
        let cases = [
            ("Asia/Kathmandu", 5, "1985-12-31T18:00:00Z", "1985-12-31T18:30:00Z", "1986-01-01", "00:15:00"),
            ("Australia/Lord_Howe", 135, "2026-10-03T14:00:00Z", "2026-10-03T15:30:00Z", "2026-10-04", "02:30:00"),
            ("Australia/Adelaide", 150, "2026-10-03T14:00:00Z", "2026-10-03T16:30:00Z", "2026-10-04", "03:00:00"),
            ("Pacific/Chatham", 180, "2026-09-26T12:00:00Z", "2026-09-26T14:00:00Z", "2026-09-27", "03:45:00"),
            ("Antarctica/Casey", 330, "2018-10-06T17:00:00Z", "2018-10-06T20:00:00Z", "2018-10-07", "07:00:00")
        ]
        for (zone, minute, began, expected, key, clock) in cases {
            let start = try utc(expected)
            #expect(try local(start, in: zone) == "\(key) \(clock)")
            let learning = try window(zone: zone, minute: minute, startedAt: utc(began))
            let morning = try #require(learning.schedule(asOf: start).mornings.first)
            #expect(morning.dayKey == key, "\(zone): the gap must not lose its morning")
            #expect(morning.expectedStart == start, "\(zone): use the first instant after the gap")
            #expect(morning.expectedEnd == start.addingTimeInterval(300))
            let entry = try recording(start, zone: "Pacific/Pago_Pago")
            let archive = try declared([entry], to: learning)
            try expectWholeMornings(learning, archive, keys: [key], entries: [entry], now: start.addingTimeInterval(600))
        }
    }

    @Test func apiasMissingCalendarDateDoesNotRepeatAMorningOrAnInstant() throws {
        let learning = try window(zone: "Pacific/Apia", minute: 420,
                                  startedAt: utc("2011-12-29T16:00:00Z"), mornings: 3)
        // Apia jumped from Dec29 23:59:59 (-10) to Dec31 00:00:00 (+14).
        let starts = try ["2011-12-29T17:00:00Z", "2011-12-30T17:00:00Z", "2011-12-31T17:00:00Z"].map(utc)
        let keys = ["2011-12-29", "2011-12-31", "2012-01-01"]
        let plan = learning.schedule(asOf: starts[0])
        #expect(plan.mornings.map(\.dayKey) == keys)
        #expect(plan.mornings.map(\.expectedStart) == starts)
        #expect(Set(plan.mornings.map(\.dayKey)).count == 3 && Set(plan.mornings.map(\.expectedStart)).count == 3)
        #expect(plan.undatedMorningCount == 0)
        let entries = try starts.map { try recording($0, zone: "Pacific/Pago_Pago") }
        let archive = try declared(entries, to: learning)
        try expectWholeMornings(learning, archive, keys: keys, entries: entries, now: starts[2].addingTimeInterval(600))
    }

    @Test func chathamsRepeatedHourChoosesTheFirstOccurrenceAndRecognizesTheSecondAsOutside() throws {
        let first = try utc("2026-04-04T13:15:00Z")
        let second = try utc("2026-04-04T14:15:00Z")
        #expect(try local(first, in: "Pacific/Chatham") == "2026-04-05 03:00:00")
        #expect(try local(second, in: "Pacific/Chatham") == "2026-04-05 03:00:00")
        let learning = try window(zone: "Pacific/Chatham", minute: 180,
                                  startedAt: utc("2026-04-04T12:00:00Z"))
        #expect(learning.schedule(asOf: second).mornings.map(\.expectedStart) == [first])
        let early = try recording(first, zone: "Asia/Kolkata")
        let earlyArchive = try declared([early], to: learning)
        try expectWholeMornings(learning, earlyArchive, keys: ["2026-04-05"], entries: [early],
                                now: second.addingTimeInterval(600))
        let late = try recording(second, zone: "Asia/Kathmandu")
        let lateArchive = try declared([late], to: learning)
        let now = second.addingTimeInterval(600)
        #expect(lateArchive.entry(id: late.id)?.windowCapture?.dayKey == "2026-04-05")
        let report = LearningWindowReport(window: learning, archive: lateArchive, now: now)
        #expect(report.mornings.map(\.status) == [.observedOutsideWindow])
        #expect(report.mornings[0].coverage?.coveredSeconds == 0)
        let comparable = try profile(learning, lateArchive, now: now)
        #expect(comparable.report.excludedDays == [.init(dayKey: "2026-04-05", reason: .partialCapture)])
        #expect(comparable.report.missingDayKeys.isEmpty)
    }

    @Test func archiveJSONPreservesAwayDeclarationsAndTheirDistinctApiaMornings() throws {
        let first = try utc("2026-10-11T11:10:00Z") // Apia Oct12 00:10 (+13).
        let learning = try window(zone: "Pacific/Apia", minute: 10,
                                  startedAt: first.addingTimeInterval(-600), mornings: 3)
        let entries = [try recording(first, zone: "Pacific/Pago_Pago"),
                       try recording(first.addingTimeInterval(86_400), zone: "Pacific/Kiritimati"),
                       try recording(first.addingTimeInterval(2 * 86_400), zone: "Asia/Kathmandu")]
        #expect(entries.map { $0.observedDate?.dayKey } == ["2026-10-11", "2026-10-13", "2026-10-13"])
        let archive = try declared(entries, to: learning)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let bytes = try encoder.encode(archive)
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: bytes)
        let restoredWindow = try JSONDecoder().decode(LearningWindow.self, from: encoder.encode(learning))
        #expect(restored == archive && restoredWindow == learning)
        #expect(try encoder.encode(restored) == bytes)
        for entry in entries {
            let saved = try #require(restored.entry(id: entry.id))
            let capture = try #require(saved.windowCapture)
            #expect(saved.observedDate == entry.observedDate && saved.recordingContext == entry.recordingContext)
            #expect(capture.timeZoneIdentifier == "Pacific/Apia" && restoredWindow.counts(capture))
            #expect(capture.actualStart == entry.recordingContext?.startedAt)
            #expect(capture.actualEnd == capture.actualStart.addingTimeInterval(300))
        }
        let now = first.addingTimeInterval(2 * 86_400 + 600)
        try expectWholeMornings(restoredWindow, restored, keys: ["2026-10-12", "2026-10-13", "2026-10-14"],
                                entries: entries, now: now)
        #expect(LearningWindowReport(window: restoredWindow, archive: restored, now: now)
                == LearningWindowReport(window: learning, archive: archive, now: now))
        #expect(try profile(restoredWindow, restored, now: now).report == profile(learning, archive, now: now).report)
    }
}
