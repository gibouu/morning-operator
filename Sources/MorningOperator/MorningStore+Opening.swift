import Foundation
import MorningCore
import MorningApple

/// The opening of a morning as the screen shows it (issue #28). It lives in memory only:
/// a relaunch pauses the morning and does not bring the opening back.
struct MorningOpeningPresentation: Equatable {
    enum Phase: Equatable {
        /// The selected sources are being read for this start.
        case preparing
        /// The opening is on screen and waits for a choice.
        case choosing
        /// The person chose the recap and it is being read.
        case brief
    }

    let sessionID: UUID
    var phase: Phase = .preparing
    /// Nil only while preparing.
    var opening: MorningOpening?
    /// The briefing the opening quotes. The recap reads this same document.
    var document: PreparedMorningBriefing?
    /// The recap exactly as it is read, shown while it plays.
    var briefText: String?
    /// True when the opening text was handed to the speech coordinator.
    var speechRequested = false
    /// The opening's own utterance, so ending the opening stops nothing else.
    var playbackID: UUID?
    /// The recap was asked for and could not be read; it is no longer offered.
    var briefWithdrawn = false
}

extension MorningStore {
    /// The opening of the current morning, or nil once the person has chosen.
    var currentOpening: MorningOpeningPresentation? {
        guard let openingPresentation, sessionActive, openingPresentation.sessionID == session?.id else { return nil }
        return openingPresentation
    }

    /// Lets UI tests read whether speech was requested. Empty outside them, so
    /// VoiceOver reads nothing more than the opening itself.
    var openingSpeechObservation: String {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              let presentation = currentOpening, presentation.opening != nil else { return "" }
        return presentation.speechRequested ? "speech requested" : "silent"
        #else
        return ""
        #endif
    }

    /// Only an explicit morning start asks, and each session is granted once. The mark is
    /// taken whether or not spoken guidance is on: a morning shown its opening in silence
    /// is not greeted aloud later.
    func claimOpeningPlayback() -> Bool {
        guard let session else { return false }
        return greetingState.claimPlayback(for: .morningStart, sessionID: session.id)
    }

    /// Called once, by `start()`, after the new session is saved. Nothing else opens a
    /// morning: not a launch, a refresh, a preview, a return to the home or a resume.
    func beginOpening(mayGreet: Bool) {
        endOpening()
        guard !privacyBlocksWork, let session, session.status == .running else { return }
        let sessionID = session.id
        openingPresentation = MorningOpeningPresentation(sessionID: sessionID)
        guard briefing.hasConfiguredSources else {
            // Nothing to read: the opening is on screen before `start()` returns. If it
            // cannot be composed, `start()` begins the first moment as it always did.
            if !presentOpening(document: nil, sessionID: sessionID, mayGreet: mayGreet) { endOpening() }
            return
        }
        openingTask = Task { [weak self] in
            guard let self else { return }
            // The same preparation a briefing moment uses: current sections come from
            // memory, the others are read again within the source deadline.
            let document = await briefing.refresh()
            guard !Task.isCancelled, openingPresentation?.sessionID == sessionID,
                  openingPresentation?.phase == .preparing else { return }
            openingTask = nil
            if !presentOpening(document: document, sessionID: sessionID, mayGreet: mayGreet) {
                // Without an opening the morning simply begins, as it did before.
                endOpening()
                runCurrentIfEnabled()
            }
        }
    }

    /// False when no opening can be shown for this session; the caller then lets the morning begin.
    private func presentOpening(document: PreparedMorningBriefing?, sessionID: UUID, mayGreet: Bool) -> Bool {
        let now = Date(), zone = TimeZone.current.identifier
        guard !privacyBlocksWork, session?.id == sessionID, session?.status == .running,
              let source = document ?? briefingWithoutFacts(at: now, timeZoneIdentifier: zone) else { return false }
        // No counts, forecast or sender share: this version has no source for them, so
        // the composer says nothing about them.
        let opening = MorningOpeningComposer.compose(briefing: source, at: now, timeZoneIdentifier: zone)
        var presentation = MorningOpeningPresentation(sessionID: sessionID, phase: .choosing,
                                                      opening: opening, document: document)
        if mayGreet, readAloud, !voiceInputBlocksPlayback {
            // The steps' own speech path. Pause, an interruption and Stop reach it there.
            speech.speak(opening.spokenText)
            presentation.speechRequested = true
            presentation.playbackID = speech.playbackID
        }
        openingPresentation = presentation
        return true
    }

    /// The briefing behind an opening when nothing was prepared. A source that is not
    /// selected stays silent. A selected one that could not be prepared is unavailable,
    /// which the opening says in words: never a zero, never an invented fact.
    private func briefingWithoutFacts(at now: Date, timeZoneIdentifier: String) -> PreparedMorningBriefing? {
        let settings = briefing.settings
        return try? MorningBriefingComposer.prepare(
            calendar: settings.calendarIDs.isEmpty ? .notConfigured : .unavailable,
            weather: settings.weatherLocation == nil ? .notConfigured : .unavailable,
            for: now, at: now, timeZoneIdentifier: timeZoneIdentifier,
            localeIdentifier: AppLanguage.localeIdentifier, temperatureUnit: settings.temperatureUnit)
    }

    /// The person's answer. Only a choice the opening offered is accepted.
    func chooseOpening(_ choice: MorningOpeningChoice) {
        guard !privacyBlocksWork, let presentation = currentOpening,
              let opening = presentation.opening, opening.choices.contains(choice) else { return }
        switch choice {
        case .stop:
            stop()
        case .ritual:
            guard session?.status == .running, !voiceInputBlocksPlayback else { return }
            endOpening()
            runCurrentIfEnabled()
        case .brief:
            playOpeningBrief(presentation)
        }
    }

    private func playOpeningBrief(_ presentation: MorningOpeningPresentation) {
        guard presentation.phase == .choosing, !presentation.briefWithdrawn, session?.status == .running,
              !voiceInputBlocksPlayback, let quoted = presentation.document else { return }
        let sessionID = presentation.sessionID
        openingTask?.cancel()
        // The answer ends the opening sentence if it is still being read.
        if let id = presentation.playbackID, id == speech.playbackID { speech.stop() }
        openingPresentation?.phase = .brief
        openingPresentation?.playbackID = nil
        openingTask = Task { [weak self] in
            guard let self else { return }
            @MainActor func stillAsked() -> Bool {
                !Task.isCancelled && openingPresentation?.sessionID == sessionID && openingPresentation?.phase == .brief
            }
            // The same admission checks as a briefing moment.
            @MainActor func playable(_ document: PreparedMorningBriefing) -> Bool {
                document.isCurrent(at: Date(), timeZoneIdentifier: TimeZone.current.identifier)
                    && briefing.permitsPlayback(of: document)
            }
            var document = quoted
            if !playable(document) {
                // The opening waited past one of its facts. Prepare again, as a briefing moment does.
                let fresh = await briefing.refresh()
                guard stillAsked() else { return }
                if let fresh { document = fresh }
            }
            let text = playable(document) ? MorningAppStepExecutor.text(for: .morningBriefing, in: document) : ""
            guard !text.isEmpty else {
                // No recap can be read. Say so, show what is out of date, and stop offering it.
                // Shown, not spoken: a morning is greeted aloud once.
                openingTask = nil
                openingPresentation?.phase = .choosing
                openingPresentation?.briefWithdrawn = true
                openingPresentation?.document = document
                openingPresentation?.opening = MorningOpeningComposer.compose(briefing: document, at: Date(),
                    timeZoneIdentifier: TimeZone.current.identifier, offersBrief: false)
                notice = String(localized: "This recap needs an update before playback.")
                return
            }
            openingPresentation?.document = document
            openingPresentation?.briefText = text
            do {
                try await speech.speakAndWait(text)
            } catch {
                // Stopped or failed. If the opening is still up, offer the choice again.
                guard openingPresentation?.sessionID == sessionID, openingPresentation?.phase == .brief else { return }
                openingTask = nil
                openingPresentation?.phase = .choosing
                openingPresentation?.briefText = nil
                if !(error is CancellationError) { notice = error.localizedDescription }
                return
            }
            guard openingPresentation?.sessionID == sessionID, openingPresentation?.phase == .brief,
                  session?.id == sessionID, session?.status == .running else { return }
            openingTask = nil
            openingPresentation = nil
            // A first moment that reads this same recap has just been heard.
            if currentStep?.automation == .morningBriefing { advance() } else { runCurrentIfEnabled() }
        }
    }

    /// Ends the opening and its own speech. A step's speech is never stopped from here.
    func endOpening() {
        let task = openingTask
        openingTask = nil
        guard let presentation = openingPresentation else { task?.cancel(); return }
        openingPresentation = nil
        task?.cancel()
        if presentation.phase == .brief || (presentation.playbackID != nil && presentation.playbackID == speech.playbackID) {
            speech.stop()
        }
    }
}
