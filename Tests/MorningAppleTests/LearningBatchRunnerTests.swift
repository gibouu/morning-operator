import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Long saved-observation learning — bounded requests, complete source coverage")
@MainActor
struct LearningBatchRunnerTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let sentence = "I review my calendar after breakfast."

    private func source(_ text: String, day: Int = 0) throws -> ObservationAcquisition {
        try ObservationAcquisition(observedDate: ObservationObservedDate(
            date: now.addingTimeInterval(Double(day) * 86_400), timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic long-source fixture", originalText: text)
    }

    private func input(_ unit: PreparedLearningEvidenceUnit, title: String = "Review calendar") throws -> EvidenceRoutineStepInput {
        let quote = try #require(unit.text.components(separatedBy: .newlines).first { $0.count >= 8 && $0.count <= 240 })
        return .init(title: title, detail: "Consider reviewing the calendar.", kind: .calendar,
            durationMinutes: 3, citations: [.init(unitID: unit.id, quote: quote)])
    }

    @Test func fiveMaximumLengthSourcesKeepEveryByteAndReachTheLastUnit() throws {
        let sources = try (0..<5).map { day in
            let ending = "\nFinal source \(day): I play chess after reviewing my calendar."
            let prefix = String(String(repeating: sentence + "\n", count: 1_000)
                .prefix(ObservationArchive.maximumOriginalTextCharacters - ending.count))
            return try source(prefix + ending, day: day)
        }
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: sources)
        #expect(prepared.submittedCharacterCount > 8_000)
        #expect(prepared.modelRequestCount > 6)
        #expect(prepared.modelRequestCount <= LearningEvidencePreparation.maximumModelCalls)
        #expect(prepared.prompts.allSatisfy { $0.count <= 1_500 && $0.utf8.count <= 6_000 })
        #expect(Set(prepared.units.map(\.id)).count == prepared.units.count)
        #expect(prepared.batches.flatMap { $0 }.map(\.id) == prepared.units.map(\.id))
        for entry in sources {
            let units = prepared.units.filter { $0.acquisitionID == entry.id }
            #expect(units.map(\.text).joined().utf8.elementsEqual(entry.originalText.utf8))
            var offset = 0
            for unit in units {
                #expect(unit.startCharacterOffset == offset)
                offset += unit.text.count
            }
            #expect(offset == entry.originalText.count)
        }
        let last = try #require(prepared.units.last)
        #expect(last.acquisitionID == sources.last?.id)
        #expect(last.text.contains("Final source 4:"))
        // The source, including the final sentence, was not overwritten by preparation.
        #expect(sources.allSatisfy { $0.originalText.count == ObservationArchive.maximumOriginalTextCharacters })
    }

    @Test func recordedMorningBeyondEightThousandRetainsEveryEligibleFrameAndTimestamp() throws {
        let frames = try (0..<24).map { index in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index * 30), actualTimeSeconds: Double(index * 30),
                outcome: .observed, text: "Calendar \(index)\n" + String(repeating: "09:00 Synthetic planning meeting\n", count: 35))
        }
        let video = try ObservationVideoEvidence(durationSeconds: 720, frames: frames)
        let entry = try ObservationAcquisition(observedDate: source(sentence).observedDate, origin: .synthetic,
            sourceKind: .video, sourceLabel: "Synthetic sampled recording", originalText: video.renderedText, videoEvidence: video)
        let before = try JSONEncoder().encode(entry)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(prepared.submittedCharacterCount > 8_000)
        #expect(Set(prepared.units.compactMap(\.sampleID)) == Set(frames.map(\.id)))
        #expect(prepared.omissions.isEmpty)
        for frame in frames {
            let units = prepared.units.filter { $0.sampleID == frame.id }
            #expect(units.map(\.text).joined().utf8.elementsEqual(frame.text.utf8))
            #expect(units.allSatisfy { $0.sourceLayer == .videoFrame })
        }
        #expect(try JSONDecoder().decode(ObservationAcquisition.self, from: before) == entry)
        #expect(entry.videoEvidence?.frames.last?.actualTimeSeconds == 690)
    }

    @Test func unicodeAndSeparatorsKeepExactOffsetsWithinBothRequestBounds() throws {
        let line = "I review cafe\u{301} appointments 👩🏽‍💻 after breakfast.\r\n"
        let text = String(repeating: line, count: 420)
        let entry = try source(text)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(prepared.units.map(\.text).joined().utf8.elementsEqual(text.utf8))
        #expect(prepared.prompts.allSatisfy { $0.count <= 1_500 && $0.utf8.count <= 6_000 })
        let last = try #require(prepared.units.last)
        let proposal = try LearningEvidencePreparation.assemble(evidence: prepared, steps: [input(last)], preserving: nil)
        let citation = try #require(proposal.support.first?.citations.first)
        let start = text.index(text.startIndex, offsetBy: citation.startCharacterOffset)
        let end = text.index(text.startIndex, offsetBy: citation.endCharacterOffset)
        #expect(text[start..<end].utf8.elementsEqual(citation.quote.utf8))
        #expect(citation.startCharacterOffset >= last.startCharacterOffset)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test func singleOversizedGraphemeFailsExplicitlyWithoutSplittingItsScalars() throws {
        let oversized = "a" + String(repeating: "\u{301}", count: 4_000)
        #expect(oversized.count == 1)
        #expect(throws: RoutineEvidenceProposalError.inputBudgetExceeded) {
            try LearningTextChunker.split(oversized, maximumCharacters: 1_100, maximumUTF8Bytes: 3_000)
        }
        let text = "Some words\n\n" + String(repeating: "🧑🏽‍💻 ", count: 200) + "\nFinal words."
        let chunks = try LearningTextChunker.split(text, maximumCharacters: 41, maximumUTF8Bytes: 160)
        #expect(chunks.allSatisfy { $0.count <= 41 && $0.utf8.count <= 160 })
        #expect(chunks.joined().utf8.elementsEqual(text.utf8))
    }

    @Test func serialRequestsReachLastSourceMergeRepeatedStepsAndRetainIndependentCitations() async throws {
        let entries = try (0..<2).map { try source(String(repeating: sentence + "\n", count: 840), day: $0) }
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: entries)
        var submitted: [UUID] = []
        var completed: [Int] = []
        var totals: [Int] = []
        let results = try await LearningBatchRunner.run(evidence: prepared, progress: { done, total in
            completed.append(done); totals.append(total)
        }) { batch, _ in
            submitted += batch.map(\.id)
            return try batch.map { try input($0, title: submitted.count.isMultiple(of: 2) ? "Review calendar" : " review CALENDAR ") }
        }
        #expect(submitted == prepared.units.map(\.id))
        #expect(completed == Array(0...prepared.modelRequestCount))
        #expect(totals.allSatisfy { $0 == prepared.modelRequestCount })
        let proposal = try LearningEvidencePreparation.assemble(evidence: prepared, steps: results, preserving: nil)
        try #require(proposal.routine.steps.count == 1 && proposal.support.count == 1)
        let support = proposal.support[0]
        #expect(support.citations.count > 24)
        #expect(Set(support.citations.map(\.acquisitionID)) == Set(entries.map(\.id)))
        let last = try #require(prepared.units.last)
        #expect(support.citations.contains { $0.acquisitionID == last.acquisitionID && $0.startCharacterOffset >= last.startCharacterOffset })
        #expect(proposal.routine.steps[0].detail.components(separatedBy: "Evidence:").count == 2)
        #expect(proposal.routine.sourceLabel.contains("Demo fixture"))
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil))
        #expect(!restored.routine.isApproved)
    }

    @Test func intermediateFailureReturnsNoPartialResultAndDoesNotSubmitLaterUnits() async throws {
        enum Failure: Error { case unavailable }
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [source(String(repeating: sentence + "\n", count: 600))])
        var calls = 0
        var completed: [Int] = []
        var returned: [EvidenceRoutineStepInput]?
        do {
            returned = try await LearningBatchRunner.run(evidence: prepared, progress: { done, _ in completed.append(done) }) { batch, _ in
                calls += 1
                if calls == 3 { throw Failure.unavailable }
                return try batch.map { try input($0) }
            }
            Issue.record("A failed request must not return a partial set of proposed steps.")
        } catch Failure.unavailable { }
        #expect(returned == nil && calls == 3)
        #expect(completed == [0, 1, 2])
    }

    @Test func cancellationDuringNoncooperativeResponseDiscardsLateResultAndStopsTheLoop() async throws {
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [source(String(repeating: sentence + "\n", count: 400))])
        let gate = LearningResponseGate()
        var calls = 0
        var completed: [Int] = []
        let task = Task {
            try await LearningBatchRunner.run(evidence: prepared, progress: { done, _ in completed.append(done) }) { batch, _ in
                calls += 1
                await gate.pause()
                return try batch.map { try input($0) }
            }
        }
        await gate.waitUntilPaused()
        task.cancel()
        gate.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(calls == 1 && completed == [0])
    }

    @Test func aCitationFromAnotherRequestAbortsBeforeReportingThatRequestComplete() async throws {
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [source(String(repeating: sentence + "\n", count: 100))])
        let last = try #require(prepared.units.last)
        try #require(prepared.modelRequestCount > 1)
        var completed: [Int] = []
        await #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try await LearningBatchRunner.run(evidence: prepared, progress: { done, _ in completed.append(done) }) { _, _ in
                [try input(last)]
            }
        }
        #expect(completed == [0])
    }

    @Test func legacyEntryPointAcceptsSavedSourcesBeyondEightThousandBeforeInference() throws {
        let text = String(repeating: sentence + "\n", count: 500)
        #expect(text.count > 8_000)
        #expect(try ObservationText.validated(text, maximumCharacters: AppleIntelligenceService.maximumInputCharacters)
            == text.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(AppleIntelligenceService.maximumInputCharacters == ObservationArchive.maximumOriginalTextCharacters)
    }
}

@MainActor
private final class LearningResponseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            ready?.resume(); ready = nil
        }
    }
    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { ready = $0 }
    }
    func resume() {
        let pending = continuation; continuation = nil; pending?.resume()
    }
}
