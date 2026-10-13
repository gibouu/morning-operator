import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Saved observation playback admission")
@MainActor
struct ObservationNarrationExecutionTests {
    @Test func repeatRevalidatesSourceAndNeverFallsBackToStaticDetail() async throws {
        let entry = try source()
        var archive = try ObservationArchive(entries: [entry])
        let candidate = try #require(ObservationNarrationComposer.candidates(for: entry).first)
        let prepared = try ObservationNarrationComposer.prepare(acquisition: entry, candidate: candidate)
        let step = step(prepared)
        var spoken: [String] = []
        let executor = MorningAppStepExecutor(prepare: { Issue.record("Not a live briefing"); return nil },
            speak: { spoken.append($0) }, stop: {}, resolveObservation: { step in
                guard let reference = step.observationReference else { return nil }
                return try? ObservationNarrationComposer.resolve(reference: reference, archive: archive).spokenText
            })
        let context = context(step)
        #expect(try await executor.execute(step: step, context: context) == .completed)
        #expect(spoken == [prepared.spokenText])
        try archive.delete(id: entry.id)
        guard case .unavailable = try await executor.execute(step: step, context: context) else {
            Issue.record("Deleting the source must block Repeat"); return
        }
        #expect(spoken == [prepared.spokenText])
    }

    @Test(arguments: [true, false])
    func missingBindingOrChangedApprovedSentenceCannotSpeak(missingBinding: Bool) async throws {
        let entry = try source()
        let prepared = try ObservationNarrationComposer.prepare(acquisition: entry,
            candidate: #require(ObservationNarrationComposer.candidates(for: entry).first))
        var step = step(prepared)
        if missingBinding { step.observationReference = nil }
        else { step.detail = "A substituted synthetic sentence." }
        var spoken: [String] = []
        let executor = MorningAppStepExecutor(prepare: { nil }, speak: { spoken.append($0) },
            stop: {}, resolveObservation: { _ in prepared.spokenText })
        guard case .unavailable = try await executor.execute(step: step, context: context(step)) else {
            Issue.record("A saved-source operation cannot silently become a note"); return
        }
        #expect(spoken.isEmpty)
    }

    @Test func disabledSpeechDoesNotEvenResolveTheSource() async throws {
        var reads = 0
        let executor = MorningAppStepExecutor(prepare: { nil }, speak: { _ in Issue.record("Unexpected speech") },
            stop: {}, resolveObservation: { _ in reads += 1; return nil })
        executor.spokenEnabled = false
        let step = RoutineStep(title: "Saved moment", automation: .savedObservation)
        guard case .needsUser = try await executor.execute(step: step, context: context(step)) else {
            Issue.record("Disabled speech is user-led"); return
        }
        #expect(reads == 0)
    }

    @Test func cancellationWhileSpeakingCannotCompleteTheMoment() async throws {
        let entry = try source()
        let prepared = try ObservationNarrationComposer.prepare(acquisition: entry,
            candidate: #require(ObservationNarrationComposer.candidates(for: entry).first))
        let step = step(prepared), context = context(step)
        let gate = NarrationSpeechGate()
        var stops = 0
        let executor = MorningAppStepExecutor(prepare: { nil }, speak: { _ in await gate.pause() },
            stop: { stops += 1 }, resolveObservation: { _ in prepared.spokenText })
        let task = Task { try await executor.execute(step: step, context: context) }
        await gate.waitForSpeech()
        executor.cancel(context: context)
        gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(stops == 1)
    }

    private func source() throws -> ObservationAcquisition {
        try ObservationAcquisition(observedDate: ObservationObservedDate(date: Date(timeIntervalSince1970: 1_791_590_400),
            timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned), origin: .synthetic,
            sourceKind: .text, sourceLabel: "Synthetic saved note", originalText: "Remember the sketch of the garden.")
    }
    private func step(_ prepared: PreparedObservationNarration) -> RoutineStep {
        .init(title: "A saved moment", detail: prepared.spokenText, automation: .savedObservation,
              observationReference: prepared.reference)
    }
    private func context(_ step: RoutineStep) -> MorningStepContext {
        .init(executionID: .init(sessionID: UUID(), routineVersionID: UUID(), stepID: step.id))
    }

    /// Mirrors the app's resolver: the saved, approved sentence selects the composition.
    private func archiveExecutor(_ archive: ObservationArchive, speak: @escaping @MainActor (String) -> Void) -> MorningAppStepExecutor {
        MorningAppStepExecutor(prepare: { Issue.record("Not a live briefing"); return nil },
            speak: { speak($0) }, stop: {}, resolveObservation: { step in
                guard let reference = step.observationReference else { return nil }
                return try? ObservationNarrationComposer.resolve(reference: reference, archive: archive,
                    approvedText: step.detail).spokenText
            })
    }

    @Test("An approved moment still plays after the interface language changes",
          arguments: ObservationNarrationLanguage.allCases)
    func approvedMomentPlaysInItsApprovedLanguage(approved: ObservationNarrationLanguage) async throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let prepared = try ObservationNarrationComposer.prepare(acquisition: entry,
            candidate: #require(ObservationNarrationComposer.candidates(for: entry).first), language: approved)
        let step = step(prepared)
        var spoken: [String] = []
        let executor = archiveExecutor(archive) { spoken.append($0) }
        #expect(try await executor.execute(step: step, context: context(step)) == .completed)
        #expect(spoken == [prepared.spokenText])
    }

    @Test func englishMomentSavedBeforeFrenchExistedStillPlays() async throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let reference = try ObservationNarrationComposer.prepare(acquisition: entry,
            candidate: #require(ObservationNarrationComposer.candidates(for: entry).first)).reference
        let saved = "In this synthetic sample's saved text from October 10, 2026:\nRemember the sketch of the garden."
        let step = RoutineStep(title: "A saved moment", detail: saved, automation: .savedObservation,
                               observationReference: reference)
        var spoken: [String] = []
        let executor = archiveExecutor(archive) { spoken.append($0) }
        #expect(try await executor.execute(step: step, context: context(step)) == .completed)
        #expect(spoken == [saved])
        var edited = step
        edited.detail = saved.replacingOccurrences(of: "garden", with: "harbor")
        guard case .unavailable = try await executor.execute(step: edited, context: context(edited)) else {
            Issue.record("An edited sentence is not the approved one"); return
        }
        #expect(spoken == [saved])
    }
}

@MainActor
private final class NarrationSpeechGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiting?.resume(); waiting = nil
        }
    }
    func waitForSpeech() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
