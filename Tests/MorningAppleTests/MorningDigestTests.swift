import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Hand-authored claims exercise the checking policy only. Nothing here runs a model,
/// reads real messages or speaks, and no result is evidence of inference quality.
@Suite("Morning digest — contract shape and claim validation")
struct MorningDigestTests {
    private struct FixedGenerator: MorningDigestGenerating {
        let producer = MorningDigestProducer.handAuthored
        let make: @Sendable (PreparedLearningEvidence) throws -> [MorningDigestClaim]
        func claims(from evidence: PreparedLearningEvidence) async throws -> [MorningDigestClaim] { try make(evidence) }
    }
    private struct GeneratorFailure: Error {}

    private let instant = Date(timeIntervalSince1970: 1_760_000_000)
    private let cedar = "Synthetic Cedar\nMeet beside the library."
    private let amelie = "Amélie Birch\nBring the blue folder on Friday."

    private func source(_ text: String, id: UUID = UUID(), day: Int = 0) throws -> ObservationAcquisition {
        try ObservationAcquisition(id: id, importedAt: instant, observedDate: ObservationObservedDate(
            date: instant.addingTimeInterval(Double(day) * 86_400), timeZoneIdentifier: "Europe/Paris",
            provenance: .userAssigned), origin: .synthetic, sourceKind: .text,
            sourceLabel: "Synthetic digest fixture", originalText: text)
    }

    private func claim(_ evidence: PreparedLearningEvidence, source index: Int = 0, field: String, value: String,
                       quote: String? = nil, quotedFrom unit: Int? = nil, revision: String? = nil) -> MorningDigestClaim {
        let snapshot = evidence.sourceSnapshots[index]
        let id = MorningDigestPreparation.sourceID(for: snapshot)
        return .init(sourceID: id, sourceRevision: revision ?? snapshot.sourceRevision, field: field, value: value,
            evidence: [.init(sourceID: id, evidenceID: MorningDigestPreparation.evidenceID(for: evidence.units[unit ?? index]),
                             quote: quote ?? value)])
    }

    private func outcome(_ evidence: PreparedLearningEvidence, undetermined: [MorningDigestSourceState] = [],
                         _ make: @escaping @Sendable (PreparedLearningEvidence) throws -> [MorningDigestClaim]) async throws -> MorningDigestOutcome {
        try await MorningDigestPreparation.prepare(runID: "synthetic-unit-test", evidence: evidence,
            undeterminedSources: undetermined, generator: FixedGenerator(make: make))
    }

    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test("The contract's example decodes and encodes back to the same JSON")
    func contractExampleRoundTrips() throws {
        let example = Data("""
        {
          "schemaVersion": 1,
          "runID": "same-controller-run-id",
          "status": "completed",
          "producer": "native-model",
          "sourceStates": [{"sourceID": "ocr-source-1", "status": "available"}],
          "claims": [{
            "sourceID": "ocr-source-1", "sourceRevision": "actual-input-unit-revision",
            "field": "sender", "value": "Synthetic Cedar",
            "evidence": [{"sourceID": "ocr-source-1", "evidenceID": "ocr-line-1", "quote": "Synthetic Cedar"}]
          }],
          "spokenText": "The exact prepared sentence supplied for speech."
        }
        """.utf8)
        let digest = try JSONDecoder().decode(MorningDigest.self, from: example)
        #expect(digest.producer == .nativeModel)
        #expect(digest.claims.first?.evidence.first?.evidenceID == "ocr-line-1")
        #expect(try jsonObject(JSONEncoder().encode(digest)) == jsonObject(example))
    }

    @Test("The fixture scored by the Python scorer is in the shape Swift emits")
    func sharedScorerFixtureRoundTrips() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/tests/fixtures/swift-digest-hand-authored.json")
        let fixture = try Data(contentsOf: url)
        let digest = try JSONDecoder().decode(MorningDigest.self, from: fixture)
        #expect(digest.producer == .handAuthored)
        #expect(digest.spokenText == MorningDigestPreparation.spokenText(for: digest.claims))
        #expect(try jsonObject(JSONEncoder().encode(digest)) == jsonObject(fixture))
    }

    @Test("Decoding refuses other versions, unknown values and claims on an output that did not complete")
    func decodingRejectsContractViolations() throws {
        func decode(_ json: String) throws -> MorningDigest {
            try JSONDecoder().decode(MorningDigest.self, from: Data(json.utf8))
        }
        let claim = #"{"sourceID":"a","sourceRevision":"r","field":"sender","value":"Synthetic Cedar"}"#
        let blocked = try decode(#"{"schemaVersion":1,"runID":"r","status":"blocked","producer":"unavailable"}"#)
        #expect(blocked.claims.isEmpty && blocked.sourceStates.isEmpty && blocked.spokenText == nil)
        #expect(try decode(#"{"schemaVersion":1,"runID":"r","status":"completed","producer":"hand-authored","claims":[\#(claim)]}"#)
            .claims[0].evidence.isEmpty)
        for invalid in [
            #"{"schemaVersion":2,"runID":"r","status":"blocked","producer":"unavailable"}"#,
            #"{"schemaVersion":1,"runID":" ","status":"blocked","producer":"unavailable"}"#,
            #"{"schemaVersion":1,"runID":"r","status":"passed","producer":"unavailable"}"#,
            #"{"schemaVersion":1,"runID":"r","status":"blocked","producer":"model"}"#,
            #"{"schemaVersion":1,"runID":"r","status":"blocked","producer":"unavailable","spokenText":""}"#,
            #"{"schemaVersion":1,"runID":"r","status":"blocked","producer":"unavailable","claims":[\#(claim)]}"#
        ] {
            #expect(throws: DecodingError.self) { try decode(invalid) }
        }
    }

    @Test("Exactly quoted claims at the current revision are kept, emitted and spoken")
    func supportedClaimsComplete() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar)])
        let result = try await outcome(evidence) { [self] evidence in
            [claim(evidence, field: "sender", value: "Synthetic Cedar"),
             claim(evidence, field: "body", value: "library", quote: "Meet beside the library.")]
        }
        #expect(result.rejections.isEmpty)
        #expect(result.digest.status == .completed)
        #expect(result.digest.producer == .handAuthored)
        #expect(result.digest.claims.count == 2)
        #expect(result.digest.sourceStates == [.init(sourceID: evidence.sourceSnapshots[0].acquisitionID.uuidString, status: .available)])
        #expect(result.digest.spokenText == "sender: Synthetic Cedar\nbody: library")
        let encoded = try JSONEncoder().encode(result.digest)
        #expect(try JSONDecoder().decode(MorningDigest.self, from: encoded) == result.digest)
        #expect(Set(try jsonObject(encoded).allKeys.compactMap { $0 as? String })
            == ["schemaVersion", "runID", "status", "producer", "sourceStates", "claims", "spokenText"])
    }

    @Test("A quote borrowed from another unit or another source's unit is rejected")
    func borrowedQuoteIsRejected() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar), source(amelie, day: 1)])
        #expect(evidence.units.count == 2)
        let result = try await outcome(evidence) { [self] evidence in
            // The text exists, but only in the second source's unit.
            [claim(evidence, field: "body", value: "Bring the blue folder on Friday."),
             // The quote is real, but the cited unit belongs to the other source.
             claim(evidence, field: "body", value: "Bring the blue folder on Friday.", quotedFrom: 1),
             claim(evidence, source: 1, field: "body", value: "Bring the blue folder on Friday.")]
        }
        #expect(result.rejections == [.init(claimIndex: 0, reason: .invalidEvidence), .init(claimIndex: 1, reason: .invalidEvidence)])
        #expect(result.digest.claims.map(\.sourceID) == [evidence.sourceSnapshots[1].acquisitionID.uuidString])
    }

    @Test("One bad citation, a missing citation or a value outside its quote rejects the claim")
    func everyCitationMustHold() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar)])
        let result = try await outcome(evidence) { [self] evidence in
            let good = claim(evidence, field: "sender", value: "Synthetic Cedar")
            let invented = MorningDigestCitation(sourceID: good.sourceID, evidenceID: UUID().uuidString, quote: "Synthetic Cedar")
            return [.init(sourceID: good.sourceID, sourceRevision: good.sourceRevision, field: "sender",
                          value: good.value, evidence: good.evidence + [invented]),
                    .init(sourceID: good.sourceID, sourceRevision: good.sourceRevision, field: "sender",
                          value: good.value, evidence: []),
                    claim(evidence, field: "sender", value: "Someone Else", quote: "Synthetic Cedar"),
                    claim(evidence, field: "not a field", value: "Synthetic Cedar")]
        }
        #expect(result.rejections.map(\.reason) == [.invalidEvidence, .missingEvidence, .invalidEvidence, .malformedClaim])
        #expect(result.digest.status == .completed)
        #expect(result.digest.claims.isEmpty && result.digest.spokenText == nil)
    }

    @Test("A claim made against an earlier revision of the source is rejected")
    func staleRevisionIsRejected() async throws {
        let id = UUID()
        let earlier = try LearningEvidencePreparation.prepare(acquisitions: [source("Synthetic Cedar\nMeet beside the station.", id: id)])
        let current = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar, id: id)])
        let stale = earlier.sourceSnapshots[0].sourceRevision
        #expect(stale != current.sourceSnapshots[0].sourceRevision)
        let result = try await outcome(current) { [self] evidence in
            [claim(evidence, field: "sender", value: "Synthetic Cedar", revision: stale)]
        }
        #expect(result.rejections == [.init(claimIndex: 0, reason: .staleRevision)])
        #expect(result.digest.claims.isEmpty)
    }

    @Test("A Unicode look-alike of the visible text is not an exact quote")
    func unicodeLookAlikeIsRejected() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(amelie)])
        let decomposed = "Ame\u{301}lie Birch"
        // Swift string equality cannot tell these apart; the validator must.
        #expect(decomposed == "Amélie Birch")
        let result = try await outcome(evidence) { [self] evidence in
            [claim(evidence, field: "sender", value: decomposed),
             claim(evidence, field: "sender", value: "Amelie Birch"),
             // Cyrillic capital Ve in place of the Latin B.
             claim(evidence, field: "sender", value: "Amélie \u{412}irch"),
             // The exact text is accepted, and a look-alike is not treated as its duplicate.
             claim(evidence, field: "sender", value: "Amélie Birch")]
        }
        #expect(result.rejections.map(\.reason) == [.invalidEvidence, .invalidEvidence, .invalidEvidence])
        #expect(result.digest.claims.count == 1)
        #expect(result.digest.claims[0].value.utf8.elementsEqual("Amélie Birch".utf8))
        #expect(try #require(result.digest.spokenText).utf8.elementsEqual("sender: Amélie Birch".utf8))
    }

    @Test("No claim may name an unavailable, unknown or undeclared source")
    func unavailableAndUnknownSourcesCarryNoClaims() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar), source(amelie, day: 1)])
        let withheld = MorningDigestPreparation.sourceID(for: evidence.sourceSnapshots[1])
        let undetermined: [MorningDigestSourceState] = [
            .init(sourceID: "mail-inbox", status: .unavailable), .init(sourceID: "messages", status: .unknown),
            // Declared available without any prepared evidence: reported as unknown.
            .init(sourceID: "calendar", status: .available),
            // Prepared, but the caller could not confirm it was complete.
            .init(sourceID: withheld, status: .unavailable)
        ]
        let result = try await outcome(evidence, undetermined: undetermined) { [self] evidence in
            let first = claim(evidence, field: "sender", value: "Synthetic Cedar")
            func elsewhere(_ id: String) -> MorningDigestClaim {
                .init(sourceID: id, sourceRevision: first.sourceRevision, field: "unreadCount", value: "0",
                      evidence: [.init(sourceID: id, evidenceID: first.evidence[0].evidenceID, quote: "0")])
            }
            return [first, elsewhere("mail-inbox"), elsewhere("messages"), elsewhere("calendar"), elsewhere("never-declared"),
                    claim(evidence, source: 1, field: "sender", value: "Amélie Birch")]
        }
        #expect(result.rejections.map(\.reason) == [.unavailableSource, .unknownSource, .unknownSource, .unknownSource, .unavailableSource])
        #expect(result.digest.claims.count == 1)
        #expect(result.digest.sourceStates == [
            .init(sourceID: MorningDigestPreparation.sourceID(for: evidence.sourceSnapshots[0]), status: .available),
            .init(sourceID: "mail-inbox", status: .unavailable), .init(sourceID: "messages", status: .unknown),
            .init(sourceID: "calendar", status: .unknown), .init(sourceID: withheld, status: .unavailable)
        ])
    }

    @Test("A repeated claim is rejected, but a properly cited retry after a bad attempt is kept")
    func duplicatesAreRejected() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar)])
        let result = try await outcome(evidence) { [self] evidence in
            let good = claim(evidence, field: "sender", value: "Synthetic Cedar")
            return [claim(evidence, field: "sender", value: "Synthetic Cedar", quote: "Not in the source"), good, good,
                    claim(evidence, field: "sender", value: "Synthetic Cedar", quote: cedar)]
        }
        #expect(result.rejections == [.init(claimIndex: 0, reason: .invalidEvidence),
                                      .init(claimIndex: 2, reason: .duplicate), .init(claimIndex: 3, reason: .duplicate)])
        #expect(result.digest.claims.count == 1)
        #expect(result.digest.spokenText == "sender: Synthetic Cedar")
    }

    @Test("Without a generator the output is blocked and nothing is invented")
    func unavailableGeneratorBlocks() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar)])
        let result = try await MorningDigestPreparation.prepare(runID: "synthetic-unit-test", evidence: evidence, generator: nil)
        #expect(result.digest.status == .blocked)
        #expect(result.digest.producer == .unavailable)
        #expect(result.digest.claims.isEmpty && result.rejections.isEmpty)
        #expect(result.digest.spokenText == nil)
        #expect(result.digest.sourceStates.map(\.status) == [.available])
        let encoded = try JSONEncoder().encode(result.digest)
        #expect(try jsonObject(encoded)["spokenText"] == nil)
        #expect(try JSONDecoder().decode(MorningDigest.self, from: encoded) == result.digest)
        await #expect(throws: MorningDigestError.invalidRunID) {
            try await MorningDigestPreparation.prepare(runID: " ", evidence: evidence, generator: nil)
        }
        let tooMany = (0..<MorningDigestPreparation.maximumSourceStates).map {
            MorningDigestSourceState(sourceID: "inbox-\($0)", status: .unknown)
        }
        // U+001C is blank to the scorer although Foundation does not trim it.
        for states in [[MorningDigestSourceState(sourceID: "", status: .unavailable)],
                       [MorningDigestSourceState(sourceID: "\u{1C}", status: .unknown)], tooMany] {
            await #expect(throws: MorningDigestError.invalidSourceStates) {
                try await MorningDigestPreparation.prepare(runID: "synthetic-unit-test", evidence: evidence,
                    undeterminedSources: states, generator: nil)
            }
        }
    }

    @Test("A failing or unbounded generator gives a failed output without claims or speech")
    func generatorFailureIsNotCompleted() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar)])
        let thrown = try await outcome(evidence) { _ in throw GeneratorFailure() }
        let flooded = try await outcome(evidence) { [self] evidence in
            Array(repeating: claim(evidence, field: "sender", value: "Synthetic Cedar"),
                  count: MorningDigestPreparation.maximumClaims + 1)
        }
        // Each claim is valid alone; together their citations exceed what the scorer reads.
        let filler = "The team reviews the calendar after breakfast every morning. "
        let long = try LearningEvidencePreparation.prepare(acquisitions: [source(String(repeating: filler, count: 16))])
        let oversized = try await outcome(long) { [self] evidence in
            let one = claim(evidence, field: "f", value: "calendar", quote: evidence.units[0].text)
            return (0..<200).map { index in
                .init(sourceID: one.sourceID, sourceRevision: one.sourceRevision, field: "f\(index)", value: one.value,
                      evidence: Array(repeating: one.evidence[0], count: MorningDigestPreparation.maximumCitationsPerClaim))
            }
        }
        #expect(long.units[0].text.utf8.count * 200 * 64 > MorningDigestPreparation.maximumArtifactBytes)
        for result in [thrown, flooded, oversized] {
            #expect(result.digest.status == .failed)
            #expect(result.digest.claims.isEmpty && result.digest.spokenText == nil)
        }
    }

    @Test("Spoken text contains nothing from a claim that failed validation")
    func spokenTextUsesOnlyValidatedClaims() async throws {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(cedar), source(amelie, day: 1)])
        let result = try await outcome(evidence, undetermined: [.init(sourceID: "mail-inbox", status: .unavailable)]) { [self] evidence in
            [claim(evidence, field: "sender", value: "Synthetic Cedar"),
             claim(evidence, field: "location", value: "Harbour office", quote: "Meet at the Harbour office."),
             claim(evidence, field: "deadline", value: "Friday", quote: "Bring the blue folder on Friday."),
             claim(evidence, field: "time", value: "Meet beside the library.", revision: String(repeating: "0", count: 64)),
             .init(sourceID: "mail-inbox", sourceRevision: "1", field: "unreadCount", value: "zero unread",
                   evidence: [.init(sourceID: "mail-inbox", evidenceID: "none", quote: "zero unread")]),
             claim(evidence, source: 1, field: "body", value: "Bring the blue folder on Friday.")]
        }
        #expect(result.rejections.map(\.claimIndex) == [1, 2, 3, 4])
        let spoken = try #require(result.digest.spokenText)
        #expect(spoken == "sender: Synthetic Cedar\nbody: Bring the blue folder on Friday.")
        for rejected in ["Harbour", "location", "deadline", "time", "Meet beside", "unreadCount", "zero unread"] {
            #expect(!spoken.contains(rejected))
        }
        #expect(spoken == MorningDigestPreparation.spokenText(for: result.digest.claims))
    }
}
