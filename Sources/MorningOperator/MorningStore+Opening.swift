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
    /// True when the opening text was handed to the speech coordinator. Its playback
    /// is `openingTask`: cancelling that task stops this utterance and nothing else.
    var speechRequested = false
    /// The recap was asked for and could not be read; it is no longer offered.
    var briefWithdrawn = false
}

extension MorningStore {
    /// The opening of the current morning, or nil once the person has chosen.
    var currentOpening: MorningOpeningPresentation? {
        guard let openingPresentation, sessionActive, openingPresentation.sessionID == session?.id else { return nil }
        return openingPresentation
    }

    /// Lets UI tests count how often this morning's opening handed over to its routine.
    /// Empty outside them.
    var openingRoutineStartObservation: String {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return "" }
        return "routine started \(openingRoutineStarts)"
        #else
        return ""
        #endif
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

    /// Called once, by `start()`, after the new session is saved, whatever asked for the
    /// start: the Start button, an invitation, a shortcut or a voice request. Nothing else
    /// opens a morning: not a launch, a refresh, a preview, a return to the home or a
    /// resume. From here the opening decides when the routine begins.
    func beginOpening(mayGreet: Bool) {
        endOpening()
        openingRoutineStarts = 0
        guard !privacyBlocksWork, let session, session.status == .running else { return }
        let sessionID = session.id
        openingPresentation = MorningOpeningPresentation(sessionID: sessionID)
        guard briefing.hasConfiguredSources else {
            // Nothing to read: the opening is on screen before `start()` returns.
            presentOpening(document: nil, sessionID: sessionID, mayGreet: mayGreet)
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
            presentOpening(document: document, sessionID: sessionID, mayGreet: mayGreet)
        }
    }

    private func presentOpening(document: PreparedMorningBriefing?, sessionID: UUID, mayGreet: Bool) {
        let now = Date(), zone = TimeZone.current.identifier
        guard !privacyBlocksWork, session?.id == sessionID, session?.status == .running,
              let source = document ?? briefingWithoutFacts(at: now, timeZoneIdentifier: zone) else {
            // Without an opening the morning simply begins, as it did before.
            endOpening()
            runCurrentIfEnabled()
            return
        }
        // No counts, forecast or sender share: this version has no source for them, so
        // the composer says nothing about them.
        let opening = MorningOpeningComposer.compose(briefing: source, at: now, timeZoneIdentifier: zone)
        openingPresentation = MorningOpeningPresentation(sessionID: sessionID, phase: .choosing,
                                                         opening: opening, document: document)
        if mayGreet, readAloud, !voiceInputBlocksPlayback {
            greet(opening.spokenText, sessionID: sessionID)
        } else {
            handOverOpening(after: .notSpoken)
        }
    }

    /// Reads the opening once, on the steps' own speech path, so Pause, an interruption and
    /// Stop reach it there. Its end is handed to `handOverOpening`: a hands-free morning
    /// starts its routine only after the greeting, never over it (issue #99).
    private func greet(_ text: String, sessionID: UUID) {
        openingPresentation?.speechRequested = true
        openingTask = Task { [weak self] in
            guard let self else { return }
            let end: MorningGreetingEnd
            do {
                try await speech.speakAndWait(text)
                end = .finished
            } catch is CancellationError {
                end = .stopped
            } catch {
                end = .failed
            }
            // Ended with the opening (a choice, Pause, Stop, a new morning): nothing to hand over.
            guard !Task.isCancelled, openingPresentation?.sessionID == sessionID,
                  openingPresentation?.phase == .choosing else { return }
            openingTask = nil
            handOverOpening(after: end)
        }
    }

    /// When the opening has nothing more to say, a hands-free morning starts its routine
    /// on its own; a normal one waits for the person's choice (issue #99). It never plays
    /// the recap. True when the routine was started. Callers hand over only once nothing
    /// is being read: the greeting's own end, or a settings change that has just stopped it.
    @discardableResult
    func handOverOpening(after end: MorningGreetingEnd) -> Bool {
        guard !privacyBlocksWork, let presentation = currentOpening, presentation.phase == .choosing,
              session?.status == .running,
              MorningOpeningHandOver.after(end, handsFree: automatic) == .startRoutine else { return false }
        startRoutineFromOpening()
        return true
    }

    /// Hands free or spoken guidance changed, after their speech was stopped. A recap that
    /// was playing returns to the choice here, before its task sees the stop, so a
    /// hands-free morning hands over at once instead of waiting. True when the routine started.
    func openingListeningSettingsChanged() -> Bool {
        guard currentOpening != nil else { return false }
        if openingPresentation?.phase == .brief {
            openingTask?.cancel()
            openingTask = nil
            openingPresentation?.phase = .choosing
            openingPresentation?.briefText = nil
        }
        return handOverOpening(after: .notSpoken)
    }

    /// The one way the opening gives way to its routine. Ending the opening first makes
    /// every later caller, a tap on "Start my routine" included, find nothing to start.
    private func startRoutineFromOpening() {
        endOpening()
        openingRoutineStarts += 1
        runCurrentIfEnabled()
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
            startRoutineFromOpening()
        case .brief:
            playOpeningBrief(presentation)
        }
    }

    private func playOpeningBrief(_ presentation: MorningOpeningPresentation) {
        guard presentation.phase == .choosing, !presentation.briefWithdrawn, session?.status == .running,
              !voiceInputBlocksPlayback, let quoted = presentation.document else { return }
        let sessionID = presentation.sessionID
        // The answer ends the opening sentence if it is still being read: cancelling its
        // task stops that utterance only.
        openingTask?.cancel()
        openingPresentation?.phase = .brief
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
                notice = AppLanguage.localized("This recap needs an update before playback.")
                handOverOpening(after: .failed)
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
                if !(error is CancellationError) {
                    notice = error.localizedDescription
                    handOverOpening(after: .failed)
                }
                return
            }
            guard openingPresentation?.sessionID == sessionID, openingPresentation?.phase == .brief,
                  session?.id == sessionID, session?.status == .running else { return }
            openingTask = nil
            openingPresentation = nil
            openingRoutineStarts += 1
            // A first moment that reads this same recap has just been heard.
            if currentStep?.automation == .morningBriefing { advance() } else { runCurrentIfEnabled() }
        }
    }

    /// Ends the opening and its own speech. A step's speech is never stopped from here:
    /// cancelling the greeting's task stops the greeting's utterance only.
    func endOpening() {
        let task = openingTask
        openingTask = nil
        guard let presentation = openingPresentation else { task?.cancel(); return }
        openingPresentation = nil
        task?.cancel()
        if presentation.phase == .brief { speech.stop() }
    }
}
