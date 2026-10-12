import Foundation
import Testing
@testable import MorningApple

@Suite("Native voice selection")
struct SpeechVoicePolicyTests {
    @Test("Voice quality is preferred within the device's exact language and dialect")
    func qualityAndDialectRanking() {
        let standard = voice("system", "en-GB", .standard)
        let enhanced = voice("enhanced", "en-GB", .enhanced)
        let premium = voice("premium", "en-GB", .premium)
        let otherDialect = voice("other", "en-US", .premium)
        let foreign = voice("foreign", "fr-FR", .premium)
        #expect(SpeechVoicePolicy.recommended(from: [foreign, standard, enhanced, otherDialect, premium],
            language: "en_GB", systemVoiceID: standard.id)?.id == premium.id)
        #expect(SpeechVoicePolicy.recommended(from: [foreign, standard, otherDialect],
            language: "en-GB")?.id == standard.id)
    }

    @Test("Fallback stays in the same language; unrelated premium voices do not win")
    func languageFallback() {
        let french = voice("french", "fr-FR", .enhanced)
        let english = voice("english", "en-US", .premium)
        #expect(SpeechVoicePolicy.recommended(from: [english, french], language: "fr-CA")?.id == french.id)
        #expect(SpeechVoicePolicy.recommended(from: [english], language: "fr-CA") == nil)
        #expect(SpeechVoicePolicy.recommended(from: [], language: "en-US") == nil)
        #expect(SpeechVoicePolicy.recommended(from: [english], language: "") == nil)
        #expect(SpeechVoicePolicy.languageMatch("zh-Hans-CN", "zh-Hant-TW") == 0)
    }

    @Test("The existing system voice wins equivalent choices without relying on list order")
    func stableSystemTieBreak() {
        let first = voice("a", "fr-FR", .enhanced)
        let system = voice("z", "fr-FR", .enhanced)
        #expect(SpeechVoicePolicy.recommended(from: [first, system], language: "fr-FR", systemVoiceID: "z") == system)
        #expect(SpeechVoicePolicy.recommended(from: [system, first], language: "fr-FR") == first)
    }

    @Test("Common-language previews match the chosen voice language")
    func previewLanguage() {
        #expect(SpeechVoicePolicy.previewText(language: "fr_CA").hasPrefix("Bonjour"))
        #expect(SpeechVoicePolicy.previewText(language: "en-GB").hasPrefix("Good morning"))
        #expect(SpeechVoicePolicy.previewText(language: "es-MX").hasPrefix("Buenos días"))
    }

    private func voice(_ id: String, _ language: String, _ quality: SpeechVoiceQuality) -> SpeechVoiceDescriptor {
        .init(id: id, name: id, language: language, quality: quality)
    }
}

@Suite("Speech activation ownership")
@MainActor
struct SpeechAudioSessionGateTests {
    @Test("Stop before queued preparation avoids activating audio at all")
    func cancelledQueuedRequestDoesNotActivate() async throws {
        let driver = ControlledAudioDriver()
        let gate = SpeechAudioSessionGate(activate: { try await driver.activate() }, deactivate: { driver.deactivate() })
        let pending = gate.prepare(for: UUID())
        gate.cancel()
        #expect(try await pending.value == false)
        #expect(driver.activationCount == 0)
        #expect(driver.deactivationCount == 0)
    }

    @Test("A late activation after Stop is released and cannot authorize speech")
    func stoppedActivationNeverBecomesReady() async throws {
        let driver = ControlledAudioDriver()
        let gate = SpeechAudioSessionGate(activate: { try await driver.activate() }, deactivate: { driver.deactivate() })
        let pending = gate.prepare(for: UUID())
        await driver.waitForActivations(1)
        gate.cancel()
        driver.completeNext()
        #expect(try await pending.value == false)
        #expect(driver.deactivationCount == 1)
    }

    @Test("Replacement waits for stale activation cleanup before activating the new request")
    func replacementSerializesActivation() async throws {
        let driver = ControlledAudioDriver()
        let gate = SpeechAudioSessionGate(activate: { try await driver.activate() }, deactivate: { driver.deactivate() })
        let first = gate.prepare(for: UUID())
        await driver.waitForActivations(1)
        let second = gate.prepare(for: UUID())
        #expect(driver.activationCount == 1)
        driver.completeNext()
        #expect(try await first.value == false)
        await driver.waitForActivations(2)
        #expect(driver.deactivationCount == 1)
        driver.completeNext()
        #expect(try await second.value)
        gate.cancel()
        await driver.waitForDeactivations(2)
    }

    @Test("Failed activation does not block a later attempt")
    func activationFailureCanRetry() async throws {
        let driver = ControlledAudioDriver()
        let gate = SpeechAudioSessionGate(activate: { try await driver.activate() }, deactivate: { driver.deactivate() })
        let first = gate.prepare(for: UUID())
        await driver.waitForActivations(1)
        driver.completeNext(error: AudioFixtureError.unavailable)
        await #expect(throws: AudioFixtureError.unavailable) { try await first.value }
        let second = gate.prepare(for: UUID())
        await driver.waitForActivations(2)
        driver.completeNext()
        #expect(try await second.value)
        gate.cancel()
        await driver.waitForDeactivations(1)
    }

    @Test("A handoff waits for both late activation and asynchronous release")
    func handoffWaitsForActivationAndRelease() async throws {
        let driver = ControlledAudioDriver()
        let gate = SpeechAudioSessionGate(activate: { try await driver.activate() },
                                          deactivate: { try await driver.deactivateAndWait() })
        let preparing = gate.prepare(for: UUID())
        await driver.waitForActivations(1)
        let release = gate.cancel()
        let handoff = Task { @MainActor in
            try await release.task.value
            #expect(gate.isCurrent(release))
            driver.recordHandoff()
        }
        #expect(driver.deactivationCount == 0, "Activation must finish before its session can be released.")
        driver.completeNext()
        await driver.waitForDeactivations(1)
        #expect(!driver.events.contains("handoff"), "Starting release is not the same as completing it.")
        driver.completeNextDeactivation()
        #expect(try await preparing.value == false, "The stopped preparation must never authorize speech.")
        try await handoff.value
        #expect(driver.events == ["release started", "release finished", "handoff"])
    }

    @Test("A newer playback supersedes an awaiting handoff and is not deactivated by it")
    func replacementSupersedesHandoffWithoutLateCleanup() async throws {
        let driver = ControlledAudioDriver()
        let gate = SpeechAudioSessionGate(activate: { try await driver.activate() },
                                          deactivate: { try await driver.deactivateAndWait() })
        let first = gate.prepare(for: UUID())
        await driver.waitForActivations(1)
        driver.completeNext()
        #expect(try await first.value)

        let handoff = Task { @MainActor in try await gate.cancelAndWait() }
        await driver.waitForDeactivations(1)
        let replacement = gate.prepare(for: UUID())
        #expect(driver.activationCount == 1, "Replacement must wait for the prior session's release.")
        driver.completeNextDeactivation()
        await #expect(throws: CancellationError.self) { try await handoff.value }
        await driver.waitForActivations(2)
        driver.completeNext()
        #expect(try await replacement.value)
        #expect(driver.deactivationCount == 1, "An old handoff must not deactivate replacement playback.")

        let cleanup = gate.cancel()
        await driver.waitForDeactivations(2)
        driver.completeNextDeactivation()
        try await cleanup.task.value
    }

    @Test("A failed release cannot report handoff success and can be explicitly retried")
    func handoffSurfacesReleaseFailure() async throws {
        let driver = ControlledAudioDriver()
        let gate = SpeechAudioSessionGate(activate: { try await driver.activate() },
                                          deactivate: { try await driver.deactivateAndWait() })
        let preparing = gate.prepare(for: UUID())
        await driver.waitForActivations(1)
        driver.completeNext()
        #expect(try await preparing.value)

        let failed = Task { @MainActor in try await gate.cancelAndWait() }
        await driver.waitForDeactivations(1)
        driver.completeNextDeactivation(error: AudioFixtureError.unavailable)
        await #expect(throws: AudioFixtureError.unavailable) { try await failed.value }

        let retry = Task { @MainActor in try await gate.cancelAndWait() }
        await driver.waitForDeactivations(2)
        driver.completeNextDeactivation()
        try await retry.value
        #expect(driver.activationCount == 1)
        #expect(driver.deactivationCount == 2, "The failed release must retain ownership until a successful retry.")
    }

    @Test("Idle output changes do not offer Resume, and Stop clears old playback errors")
    func idleInterruptionDoesNotInventPausedSpeech() {
        let speech = SpeechCoordinator()
        speech.handleAudioInterruption(outputChanged: true)
        #expect(speech.state == .idle)
        #expect(speech.lastError == nil)
        speech.speak(" \n ")
        #expect(speech.lastError != nil)
        speech.stop()
        speech.handleAudioInterruption(outputChanged: false)
        #expect(speech.state == .idle)
        #expect(speech.lastError == nil)
        #expect(speech.playbackID == nil)
        #expect(speech.statusText == "Ready to speak")
    }
}

private enum AudioFixtureError: Error, Equatable { case unavailable }

/// No real audio session or synthesis: deterministic completion controls the async boundary.
@MainActor
private final class ControlledAudioDriver {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    private(set) var events: [String] = []
    private var pending: [CheckedContinuation<Void, any Error>] = []
    private var pendingDeactivations: [CheckedContinuation<Void, any Error>] = []
    private var activationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var deactivationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func activate() async throws {
        activationCount += 1
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            let ready = activationWaiters.filter { activationCount >= $0.0 }
            activationWaiters.removeAll { activationCount >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    func deactivate() {
        deactivationCount += 1
        let ready = deactivationWaiters.filter { deactivationCount >= $0.0 }
        deactivationWaiters.removeAll { deactivationCount >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func deactivateAndWait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            pendingDeactivations.append(continuation)
            events.append("release started")
            deactivate()
        }
    }

    func completeNextDeactivation(error: (any Error)? = nil) {
        let continuation = pendingDeactivations.removeFirst()
        if let error { continuation.resume(throwing: error) }
        else {
            events.append("release finished")
            continuation.resume()
        }
    }

    func recordHandoff() { events.append("handoff") }

    func completeNext(error: (any Error)? = nil) {
        let continuation = pending.removeFirst()
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    func waitForActivations(_ count: Int) async {
        guard activationCount < count else { return }
        await withCheckedContinuation { activationWaiters.append((count, $0)) }
    }

    func waitForDeactivations(_ count: Int) async {
        guard deactivationCount < count else { return }
        await withCheckedContinuation { deactivationWaiters.append((count, $0)) }
    }
}
