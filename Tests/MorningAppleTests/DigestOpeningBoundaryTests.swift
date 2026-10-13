import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Synthetic inputs probe provenance and playback boundaries; no model, inbox,
/// native source or speech adapter is involved.
@Suite("Digest provenance and opening boundaries", .timeLimit(.minutes(1)))
struct DigestOpeningBoundaryTests {
    private let now = Date(timeIntervalSince1970: 1_791_619_200)

    private struct FixedGenerator: MorningDigestGenerating {
        let producer = MorningDigestProducer.handAuthored
        let output: [MorningDigestClaim]
        func claims(from evidence: PreparedLearningEvidence) async throws -> [MorningDigestClaim] { output }
    }

    @Test("A byte substring inside a grapheme is not an exact quotation or value")
    func partialGraphemeQuotesAndValuesAreRejected() async throws {
        let text = "Synthetic glyphs Q\u{301} 👩‍💻 👍🏽 X\r\nY"
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(text)])
        try #require(evidence.units.count == 1)
        #expect(evidence.units[0].text.utf8.elementsEqual(text.utf8))
        let candidates = [
            claim(evidence, value: "Q"),
            claim(evidence, value: "\u{301}"),
            claim(evidence, value: "👩"),
            claim(evidence, value: "🏽"),
            claim(evidence, value: "X", quote: "X\r"),
            // The quote itself is whole; the value still cuts its final grapheme.
            claim(evidence, value: "Q", quote: "Q\u{301}"),
            claim(evidence, value: "Q\u{301}"),
            claim(evidence, value: "👩‍💻")
        ]
        let result = try await prepare(evidence, candidates)
        #expect(result.rejections == (0..<6).map { .init(claimIndex: $0, reason: .invalidEvidence) })
        #expect(result.digest.claims.map(\.value) == ["Q\u{301}", "👩‍💻"])
        #expect(result.digest.spokenText?.utf8.elementsEqual("glyph: Q\u{301}\nglyph: 👩‍💻".utf8) == true)
    }

    @Test("A restored claim cannot replay an old preparation's unit ID or change revision spelling")
    func decodedClaimReplayRequiresCurrentUnitAndExactRevision() async throws {
        let acquisition = try source("Synthetic Cedar meets beside the library.")
        let previous = try LearningEvidencePreparation.prepare(acquisitions: [acquisition])
        let current = try LearningEvidencePreparation.prepare(acquisitions: [acquisition])
        try #require(previous.sourceSnapshots == current.sourceSnapshots)
        try #require(previous.units[0].id != current.units[0].id)
        let saved = try JSONEncoder().encode(claim(previous, value: "Synthetic Cedar"))
        let replay = try JSONDecoder().decode(MorningDigestClaim.self, from: saved)
        let good = claim(current, value: "Synthetic Cedar")
        let differentlySpelledRevision = good.sourceRevision.uppercased()
        try #require(!differentlySpelledRevision.utf8.elementsEqual(good.sourceRevision.utf8))
        let wrongRevision = MorningDigestClaim(sourceID: good.sourceID, sourceRevision: differentlySpelledRevision,
            field: good.field, value: good.value, evidence: good.evidence)
        let result = try await prepare(current, [replay, wrongRevision, good])
        #expect(result.rejections == [.init(claimIndex: 0, reason: .invalidEvidence),
                                      .init(claimIndex: 1, reason: .staleRevision)])
        #expect(result.digest.claims == [good])
        #expect(result.digest.spokenText == "glyph: Synthetic Cedar")
    }

    @Test("Cancel wins over a generator that returns or throws after cancellation")
    func lateGeneratorCompletionCannotPublishAfterCancellation() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source("Synthetic Cedar reads the calendar.")])
        let supported = claim(evidence, value: "Synthetic Cedar")
        for fails in [false, true] {
            let generator = SuspendedGenerator()
            let task = Task {
                try await MorningDigestPreparation.prepare(runID: "boundary-cancel", evidence: evidence,
                    generator: generator)
            }
            await generator.waitUntilCalled()
            task.cancel()
            await generator.complete(fails ? .failure(SyntheticFailure()) : .success([supported]))
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        // Cancellation must not poison a later explicit preparation.
        let retry = try await prepare(evidence, [supported])
        #expect(retry.digest.status == .completed && retry.digest.claims == [supported])
    }

    @Test("Non-finite clock and forecast endpoints cannot manufacture current facts or an umbrella")
    func nonFiniteClockAndForecastEndpointsFailClosed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let day = try #require(calendar.dateInterval(of: .day, for: now))
        let choice = CalendarChoice(id: "synthetic", title: "Synthetic calendar", sourceTitle: "Synthetic source")
        let snapshot = CalendarSnapshot(retrievedAt: now, dayStart: day.start, dayEnd: day.end,
            events: [.init(id: "synthetic-event", title: "SYNTHETIC_BOUNDARY_EVENT",
                start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(3_600), isAllDay: false,
                calendarTitle: choice.title, calendarID: choice.id)],
            timeZoneIdentifier: "UTC", selectedCalendars: [choice])
        let briefing = try MorningBriefingComposer.prepare(calendar: .snapshot(snapshot), weather: .unavailable,
            for: now, at: now, timeZoneIdentifier: "UTC", localeIdentifier: "en_US")
        let end = now.addingTimeInterval(3_600), expiry = now.addingTimeInterval(600)
        let validForecast = MorningPrecipitationForecast(chance: 1, windowEnd: end, expiresAt: expiry)
        func opening(at date: Date, forecast: MorningPrecipitationForecast?) -> MorningOpening {
            MorningOpeningComposer.compose(briefing: briefing, at: date, timeZoneIdentifier: "UTC",
                counts: [.unreadMessages: .unavailable, .unreadEmail: .available(Int.min), .missedCalls: .unavailable],
                precipitation: forecast)
        }
        let baseline = opening(at: now, forecast: validForecast)
        #expect(baseline.segments.contains { $0.source == .umbrella })
        #expect(baseline.text.contains("SYNTHETIC_BOUNDARY_EVENT"))
        for nonFinite in [Double.nan, Double.infinity, -Double.infinity] {
            let invalidDate = Date(timeIntervalSinceReferenceDate: nonFinite)
            let invalidClock = opening(at: invalidDate, forecast: validForecast)
            #expect(!invalidClock.segments.contains { $0.source == .umbrella || $0.source == .count })
            #expect(!invalidClock.text.contains("SYNTHETIC_BOUNDARY_EVENT"))
            #expect(invalidClock.choices == [.ritual, .stop])
            for forecast in [MorningPrecipitationForecast(chance: 1, windowEnd: invalidDate, expiresAt: expiry),
                             MorningPrecipitationForecast(chance: 1, windowEnd: end, expiresAt: invalidDate)] {
                let invalidForecast = opening(at: now, forecast: forecast)
                #expect(!invalidForecast.segments.contains { $0.source == .umbrella || $0.source == .count })
                #expect(invalidForecast.text.contains("SYNTHETIC_BOUNDARY_EVENT"))
                #expect(invalidForecast.choices.contains(.brief))
            }
        }
    }

    private func source(_ text: String) throws -> ObservationAcquisition {
        try .init(importedAt: now, observedDate: .init(date: now, timeZoneIdentifier: "UTC", provenance: .userAssigned),
            origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic boundary source", originalText: text)
    }

    private func claim(_ evidence: PreparedLearningEvidence, value: String, quote: String? = nil) -> MorningDigestClaim {
        let snapshot = evidence.sourceSnapshots[0]
        let sourceID = MorningDigestPreparation.sourceID(for: snapshot)
        return .init(sourceID: sourceID, sourceRevision: snapshot.sourceRevision, field: "glyph", value: value,
            evidence: [.init(sourceID: sourceID, evidenceID: MorningDigestPreparation.evidenceID(for: evidence.units[0]),
                quote: quote ?? value)])
    }

    private func prepare(_ evidence: PreparedLearningEvidence, _ claims: [MorningDigestClaim]) async throws -> MorningDigestOutcome {
        try await MorningDigestPreparation.prepare(runID: "boundary-provenance", evidence: evidence,
            generator: FixedGenerator(output: claims))
    }

    private struct SyntheticFailure: Error {}

    /// Deliberately ignores cancellation until the test delivers a late response.
    private actor SuspendedGenerator: MorningDigestGenerating {
        nonisolated let producer = MorningDigestProducer.handAuthored
        private var response: CheckedContinuation<[MorningDigestClaim], any Error>?
        private var entered = false
        private var waiter: CheckedContinuation<Void, Never>?

        func claims(from evidence: PreparedLearningEvidence) async throws -> [MorningDigestClaim] {
            try await withCheckedThrowingContinuation { continuation in
                response = continuation
                entered = true
                waiter?.resume(); waiter = nil
            }
        }

        func waitUntilCalled() async {
            if entered { return }
            // A regression that never invokes the generator should fail the suite's
            // time limit instead of leaving its signal wait suspended forever.
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if entered || Task.isCancelled { continuation.resume() }
                    else { waiter = continuation }
                }
            } onCancel: {
                Task { await self.cancelWait() }
            }
        }

        private func cancelWait() { waiter?.resume(); waiter = nil }

        func complete(_ result: Result<[MorningDigestClaim], any Error>) {
            response?.resume(with: result); response = nil
        }
    }
}
