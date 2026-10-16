#if MORE_JURY_DEMO
import XCTest

/// Navigation checks stay isolated. The separately opted-in physical-device check
/// uses real permissions/audio and never injects speech or authorizes a mail send.
@MainActor
final class JuryDemoJourneyTests: XCTestCase {
    func testPreparedMorningUsesTheOrdinaryLandscapeAndSettings() throws {
        let app = try launchDemo()
        defer { app.terminate() }

        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10))
        assertNoSpecialPresentation(app)
        XCTAssertFalse(app.buttons["morning.begin"].exists)
        XCTAssertFalse(app.buttons["morning.settings"].exists)
        XCTAssertEqual(app.navigationBars.count, 0)
        XCTAssertEqual(app.scrollViews.count, 0)

        landscape.tap()
        XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5))
        let buttons = Set(app.buttons.allElementsBoundByIndex.map(\.identifier))
            .subtracting(["morning.actions"])
        XCTAssertEqual(buttons, ["morning.begin", "morning.settings"],
                       "The demo keeps the same two transient Home controls.")

        openSettings(app)
        let routine = app.buttons["setup.routine"]
        XCTAssertTrue(routine.waitForExistence(timeout: 5))
        routine.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor")
            .firstMatch.waitForExistence(timeout: 5))
        for (index, title) in ["Mon réveil", "Mes messages", "Mon moment Instagram", "Prêt à partir"].enumerated() {
            let step = app.buttons["routine.step.\(index)"]
            reveal(step, in: app)
            XCTAssertTrue(step.label.contains(title), "The prepared moment stays in the normal routine editor.")
        }
        XCTAssertFalse(app.buttons["routine.step.4"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        assertNoSpecialPresentation(app)
    }

    func testListeningPreparationShowsRealStatusWithoutStartingMicrophone() throws {
        let app = try launchDemo()
        defer { app.terminate() }
        openSettings(app)
        let listening = app.buttons["setup.voiceAccess"]
        reveal(listening, in: app)
        XCTAssertTrue(listening.isEnabled)
        listening.tap()

        let status = app.staticTexts["voice.access.status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertFalse(status.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(app.buttons["voice.access.refresh"].exists)
        XCTAssertTrue(app.buttons["voice.access.close"].exists)
        XCTAssertFalse(app.staticTexts["voice.access.synthetic"].exists,
                       "Reading the device status must not claim simulated authorization or audio success.")
        XCTAssertFalse(app.buttons["voice.access.begin"].exists)
        XCTAssertFalse(app.buttons["voice.access.withoutListening"].exists)
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Inspecting access must not request system grants.")

        app.buttons["voice.access.close"].tap()
        XCTAssertTrue(app.buttons["setup.voiceAccess"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["morning.stop"].exists, "No morning was started by visiting voice preparation.")
        assertNoSpecialPresentation(app)
    }

    /// This checks the visible refusal and paused session, not a transport trace.
    func testDecliningOnlineVoiceKeepsTheSameMorningPausedInBothLanguages() throws {
        for french in [true, false] {
            let app = try launchDemo(french: french, additionalArguments: [
                "--ui-testing-hands-free", "--ui-testing-read-aloud", "--ui-testing-natural-voice-consent"
            ])
            defer { app.terminate() }
            app.buttons["morning.actions"].tap()
            let begin = app.buttons["morning.begin"]
            XCTAssertTrue(begin.waitForExistence(timeout: 5)); begin.tap()

            let consent = app.staticTexts["voice.readingConsent"]
            XCTAssertTrue(consent.waitForExistence(timeout: 8))
            XCTAssertFalse(app.staticTexts["voice.access.synthetic"].exists,
                           "The system permission state must not be simulated.")
            XCTAssertEqual(app.alerts.count, 0, "Reviewing consent must not request microphone access.")
            let decline = app.buttons["voice.access.withoutOnlineVoice"]
            reveal(decline, in: app); decline.tap()
            XCTAssertTrue(consent.waitForNonExistence(timeout: 10))

            let captions = app.scrollViews["morning.captions"]
            XCTAssertTrue(captions.waitForExistence(timeout: 10))
            let identity = captions.value as? String
            let parts = identity?.components(separatedBy: "|") ?? []
            XCTAssertEqual(parts.count, 2)
            XCTAssertTrue(parts.allSatisfy { UUID(uuidString: $0) != nil })
            let caption = app.staticTexts["morning.caption"]
            let refusal = french
                ? "La voix en ligne est désactivée pour ce matin. Arrêtez puis recommencez un matin pour changer ce choix."
                : "Online voice is off for this morning. Stop and start a new morning to change this choice."
            let refusalShown = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", refusal), object: caption)
            XCTAssertEqual(XCTWaiter.wait(for: [refusalShown], timeout: 10), .completed)
            let playback = revealLivePlayback(app)
            XCTAssertEqual(playback.label, french ? "Continuer" : "Continue")
            playback.tap()
            XCTAssertFalse(consent.waitForExistence(timeout: 1), "The same morning keeps its explicit refusal.")
            let stillPaused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", french ? "Continuer" : "Continue"), object: playback)
            XCTAssertEqual(XCTWaiter.wait(for: [stillPaused], timeout: 10), .completed)
            XCTAssertEqual(caption.label, refusal)
            XCTAssertEqual(captions.value as? String, identity,
                           "Retrying Play must preserve the refused morning and its current moment.")
            XCTAssertEqual(app.alerts.count, 0, "Refusing online voice must not require system permissions.")
        }
    }

    /// Evidence is deliberately narrow: decoded backend audio started, the same
    /// moment survived background/pause/resume, and normal Stop ended the session.
    /// This does not prove audible output, ASR recognition or hardware mic release.
    func testLivePhysicalPhoneAudioAndBackgroundLifecycle() async throws {
        guard ProcessInfo.processInfo.environment["MORE_JURY_LIVE_PHONE"] == "1" else {
            throw XCTSkip("Set MORE_JURY_LIVE_PHONE=1 only for the authorized physical demo iPhone.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Real jury audio/lifecycle acceptance runs only on a physical iPhone.")
        #else
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = try demoApplication()
        app.launchArguments = ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)"]
        let permissionMonitor = addUIInterruptionMonitor(withDescription: "Real MORE demo iPhone permissions") { alert in
            let explanation = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            guard explanation.localizedCaseInsensitiveContains("MORE") else { return false }
            for title in ["Autoriser", "Allow", "OK", "Autoriser l’accès complet", "Allow Full Access"] {
                let allow = alert.buttons[title]
                if allow.exists { allow.tap(); return true }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(permissionMonitor); app.terminate() }
        app.launch()

        if app.buttons["permissions.allow"].waitForExistence(timeout: 3) {
            finishRealPermissionSetup(app)
            returnToLiveHome(app)
        } else {
            XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        }
        XCTAssertFalse(app.staticTexts["qa.testWorkspace"].exists)
        assertNoSpecialPresentation(app)

        openSettings(app)
        // Live acceptance ends its preceding demo rehearsal through the normal UI.
        let previousStop = app.buttons["morning.stop"]
        if previousStop.exists {
            previousStop.tap()
            XCTAssertTrue(previousStop.waitForNonExistence(timeout: 10))
        }
        let listening = app.buttons["setup.voiceAccess"]
        reveal(listening, in: app); listening.tap()
        let access = app.staticTexts["voice.access.status"].firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        if app.buttons["voice.access.prepare"].exists {
            app.buttons["voice.access.prepare"].tap()
            handleRealSystemGrants()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = access.label
            return value.contains("Reconnaissance vocale : autorisée.") &&
                value.contains("Microphone : autorisé.") && value.contains("Reconnaissance locale disponible")
        }, object: access)
        let accessResult = await XCTWaiter.fulfillment(of: [ready], timeout: 20)
        XCTAssertEqual(accessResult, .completed,
                       "Real iOS grants and local recognition must be available; no fake authorization is accepted.")
        app.buttons["voice.access.close"].tap()
        returnToLiveHome(app)

        app.buttons["morning.actions"].tap()
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5)); begin.tap()
        acceptLiveMorningVoiceConsent(app)
        await waitForLiveSpokenPassage(app)
        attachLive("jury-live-real-audio-started", app)

        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(9))
        let systemScreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        systemScreen.name = "jury-live-background-system-screen"
        systemScreen.lifetime = .keepAlways
        add(systemScreen)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemHierarchy = XCTAttachment(string: springboard.debugDescription)
        systemHierarchy.name = "jury-live-background-springboard-hierarchy"
        systemHierarchy.lifetime = .keepAlways
        add(systemHierarchy)
        app.activate()
        let playback = revealLivePlayback(app)
        XCTAssertEqual(playback.label, "Pause", "The same morning must still run after backgrounding.")
        let retainedCaption = app.staticTexts["morning.caption"]
        XCTAssertTrue(retainedCaption.exists)
        XCTAssertFalse(retainedCaption.label.isEmpty)
        XCTAssertFalse(retainedCaption.label.lowercased().contains("indisponible"))
        XCTAssertFalse(retainedCaption.label.lowercased().contains("connexion"))
        attachLive("jury-live-after-background", app)

        playback.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Continuer"), object: playback)
        let pauseResult = await XCTWaiter.fulfillment(of: [paused], timeout: 10)
        XCTAssertEqual(pauseResult, .completed)
        openLiveSettings(app)
        let details = app.buttons["morning.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5)); details.tap()
        let voiceStatus = app.staticTexts["morning.voiceStatus"]
        XCTAssertTrue(voiceStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(voiceStatus.label.lowercased().contains("pause"), "Pause must reach the real voice coordinator.")
        XCTAssertTrue(app.navigationBars["Mon réveil"].exists, "No input or external action may advance this check.")
        attachLive("jury-live-paused-real-voice-status", app)
        app.buttons["morning.closeDetails"].tap()
        returnToLiveHome(app)

        let resume = revealLivePlayback(app)
        let captionBeforeResume = app.staticTexts["morning.caption"].label
        XCTAssertEqual(resume.label, "Continuer"); resume.tap()
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: resume)
        let resumeResult = await XCTWaiter.fulfillment(of: [running], timeout: 10)
        XCTAssertEqual(resumeResult, .completed)
        await waitForLiveSpokenPassage(app, replacing: captionBeforeResume)
        attachLive("jury-live-resumed-real-audio", app)
        openLiveSettings(app)
        let stop = app.buttons["morning.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 10))
        returnToLiveHome(app)
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertTrue(app.buttons["morning.actions"].exists)
        attachLive("jury-live-stopped-through-normal-settings", app)
        #endif
    }

    /// A person or an external speaker supplies the real acoustic answer during
    /// the marked window. XCTest never types, posts or injects that answer.
    func testLivePhysicalPhoneRecognizesAcousticYesAndOpensMailMoment() async throws {
        guard ProcessInfo.processInfo.environment["MORE_JURY_ACOUSTIC_PHONE"] == "1" else {
            throw XCTSkip("Set MORE_JURY_ACOUSTIC_PHONE=1 only for the authorized acoustic iPhone check.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Acoustic recognition acceptance requires a physical iPhone.")
        #else
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = try demoApplication()
        app.launchArguments = ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)"]
        defer { app.terminate() }
        app.launch()
        if app.buttons["permissions.allow"].waitForExistence(timeout: 3) {
            finishRealPermissionSetup(app)
            returnToLiveHome(app)
        }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10),
                      "This check starts only from idle Home and does not reset an existing morning.")
        XCTAssertFalse(app.staticTexts["qa.testWorkspace"].exists)
        assertNoSpecialPresentation(app)

        openSettings(app)
        // Live acceptance ends its preceding demo rehearsal through the normal UI.
        let previousStop = app.buttons["morning.stop"]
        if previousStop.exists {
            previousStop.tap()
            XCTAssertTrue(previousStop.waitForNonExistence(timeout: 10))
        }
        let listening = app.buttons["setup.voiceAccess"]
        reveal(listening, in: app); listening.tap()
        let access = app.staticTexts["voice.access.status"].firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        if app.buttons["voice.access.prepare"].exists {
            app.buttons["voice.access.prepare"].tap()
            handleRealSystemGrants()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = access.label
            return value.contains("Reconnaissance vocale : autorisée.") &&
                value.contains("Microphone : autorisé.") && value.contains("Reconnaissance locale disponible")
        }, object: access)
        let accessResult = await XCTWaiter.fulfillment(of: [ready], timeout: 20)
        XCTAssertEqual(accessResult, .completed, "The acoustic check requires real iOS authorization and local recognition.")
        app.buttons["voice.access.close"].tap()
        returnToLiveHome(app)

        app.buttons["morning.actions"].tap()
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5)); begin.tap()
        acceptLiveMorningVoiceConsent(app)
        await waitForLiveSpokenPassage(app)
        attachLive("jury-acoustic-before-external-answer", app)
        print("JURY_ACOUSTIC_READY_FOR_YES")

        let caption = app.staticTexts["morning.caption"]
        let mailMoment = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard caption.exists else { return false }
            let value = caption.label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            return ["propose un point produit", "tu veux que je lui reponde"].contains { value.contains($0) } &&
                !value.contains("indisponible") && !value.contains("connexion")
        }, object: caption)
        let recognized = await XCTWaiter.fulfillment(of: [mailMoment], timeout: 45)
        XCTAssertEqual(recognized, .completed,
                       "A real acoustic answer must reach the backend and advance to its mail conversation.")
        attachLive("jury-acoustic-mail-response-after-real-input", app)

        if ProcessInfo.processInfo.environment["MORE_JURY_NATIVE_REMINDER_PHONE"] == "1" {
            // The external speaker supplies a real reminder request; only the
            // app's EventKit readback/ACK can produce this confirmed passage.
            print("JURY_ACOUSTIC_READY_FOR_REMINDER")
            let reminderCreated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard caption.exists else { return false }
                let value = caption.label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
                return value.hasPrefix("le rappel est cree") &&
                    !value.contains("pas ete cree") && !value.contains("a verifier")
            }, object: caption)
            let reminderResult = await XCTWaiter.fulfillment(of: [reminderCreated], timeout: 45)
            XCTAssertEqual(reminderResult, .completed,
                           "A real spoken request must create and reread the native reminder before the backend confirms it.")
            attachLive("jury-acoustic-native-reminder-confirmed-after-readback", app)
        }

        openLiveSettings(app)
        let details = app.buttons["morning.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5)); details.tap()
        XCTAssertTrue(app.navigationBars["Mes messages"].waitForExistence(timeout: 5),
                      "The routine must reflect the backend's actual mail stage, beyond a changed caption.")
        attachLive("jury-acoustic-server-mail-stage", app)
        app.buttons["morning.closeDetails"].tap()
        let stop = app.buttons["morning.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 10))
        returnToLiveHome(app)
        XCTAssertTrue(app.buttons["morning.actions"].exists)
        #endif
    }

    func testStopPreparedRehearsalThroughOrdinaryUI() throws {
        guard ProcessInfo.processInfo.environment["MORE_JURY_STOP_REHEARSAL_PHONE"] == "1" else {
            throw XCTSkip("Set MORE_JURY_STOP_REHEARSAL_PHONE=1 only to stop the authorized demo rehearsal.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Rehearsal cleanup runs only on the physical demo iPhone.")
        #else
        continueAfterFailure = false
        let app = try demoApplication()
        app.launchArguments = ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)"]
        app.launch()
        XCTAssertFalse(app.staticTexts["qa.testWorkspace"].exists)
        if app.scrollViews["morning.captions"].waitForExistence(timeout: 5) {
            openLiveSettings(app)
        } else {
            openSettings(app)
        }
        let stop = app.buttons["morning.stop"]
        if stop.exists { stop.tap(); XCTAssertTrue(stop.waitForNonExistence(timeout: 10)) }
        returnToLiveHome(app)
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        XCTAssertTrue(app.buttons["morning.actions"].exists)
        attachLive("jury-rehearsal-cleanup-idle", app)
        #endif
    }

    /// Diagnostics only: numeric device logs establish whether raw input has a
    /// signal. This makes no ASR, acoustic recognition or acceptance claim.
    func testLivePhysicalPhoneRawMicrophoneDiagnostic() async throws {
        guard ProcessInfo.processInfo.environment["MORE_JURY_RAW_MIC_PHONE"] == "1" else {
            throw XCTSkip("Set MORE_JURY_RAW_MIC_PHONE=1 only for the authorized raw microphone diagnosis.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Raw microphone diagnosis requires a physical iPhone.")
        #else
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = try demoApplication()
        app.launchArguments = ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "--jury-raw-microphone-diagnostic"]
        defer { app.terminate() }
        app.launch()
        if app.buttons["permissions.allow"].waitForExistence(timeout: 3) {
            finishRealPermissionSetup(app)
            returnToLiveHome(app)
        }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["qa.testWorkspace"].exists)
        assertNoSpecialPresentation(app)
        openSettings(app)
        let previousStop = app.buttons["morning.stop"]
        if previousStop.exists { previousStop.tap(); XCTAssertTrue(previousStop.waitForNonExistence(timeout: 10)) }
        let listening = app.buttons["setup.voiceAccess"]
        reveal(listening, in: app); listening.tap()
        if app.buttons["voice.access.prepare"].waitForExistence(timeout: 3) {
            app.buttons["voice.access.prepare"].tap()
            handleRealSystemGrants()
        }
        app.buttons["voice.access.close"].tap()
        returnToLiveHome(app)
        app.buttons["morning.actions"].tap()
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5)); begin.tap()
        acceptLiveMorningVoiceConsent(app)
        await waitForLiveSpokenPassage(app)
        attachLive("jury-raw-mic-diagnostic-real-audio-started", app)
        print("JURY_RAW_MIC_READY")
        try await Task.sleep(for: .seconds(25))
        attachLive("jury-raw-mic-diagnostic-after-acoustic-window", app)
        openLiveSettings(app)
        let stop = app.buttons["morning.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 10))
        returnToLiveHome(app)
        XCTAssertTrue(app.buttons["morning.actions"].exists)
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        #endif
    }

    /// The compact activity is opened only by its observed MORE accessibility
    /// label. Every action then requires a demo-only control identifier.
    func testLivePhysicalPhoneDynamicIslandPauseResumeAndStop() async throws {
        guard ProcessInfo.processInfo.environment["MORE_JURY_ISLAND_PHONE"] == "1" else {
            throw XCTSkip("Set MORE_JURY_ISLAND_PHONE=1 only for the authorized Dynamic Island iPhone check.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Dynamic Island acceptance requires a physical iPhone.")
        #else
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = try demoApplication()
        app.launchArguments = ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)"]
        defer { app.terminate() }
        app.launch()
        if app.buttons["permissions.allow"].waitForExistence(timeout: 3) {
            finishRealPermissionSetup(app)
            returnToLiveHome(app)
        }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["qa.testWorkspace"].exists)
        assertNoSpecialPresentation(app)

        openSettings(app)
        let previousStop = app.buttons["morning.stop"]
        if previousStop.exists {
            previousStop.tap()
            XCTAssertTrue(previousStop.waitForNonExistence(timeout: 10))
        }
        let listening = app.buttons["setup.voiceAccess"]
        reveal(listening, in: app); listening.tap()
        let access = app.staticTexts["voice.access.status"].firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        if app.buttons["voice.access.prepare"].exists {
            app.buttons["voice.access.prepare"].tap()
            handleRealSystemGrants()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = access.label
            return value.contains("Reconnaissance vocale : autorisée.") &&
                value.contains("Microphone : autorisé.") && value.contains("Reconnaissance locale disponible")
        }, object: access)
        let accessResult = await XCTWaiter.fulfillment(of: [ready], timeout: 20)
        XCTAssertEqual(accessResult, .completed, "The Island check requires real iOS voice authorization.")
        app.buttons["voice.access.close"].tap()
        returnToLiveHome(app)

        app.buttons["morning.actions"].tap()
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5)); begin.tap()
        acceptLiveMorningVoiceConsent(app)
        await waitForLiveSpokenPassage(app)
        let captionBeforePause = app.staticTexts["morning.caption"].label
        attachLive("jury-island-real-audio-started", app)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(9))
        let pause = expandedJuryIslandControl("jury.demo.island.pause", in: springboard)
        pause.tap()
        let resume = expandedJuryIslandControl("jury.demo.island.resume", in: springboard)
        XCTAssertFalse(springboard.descendants(matching: .any)
            .matching(identifier: "jury.demo.island.pause").firstMatch.exists,
                       "The demo activity must publish its paused state before resuming.")
        resume.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10),
                      "The Island resume link must bring the app to the foreground itself.")
        let playback = revealLivePlayback(app)
        XCTAssertEqual(playback.label, "Pause")
        await waitForLiveSpokenPassage(app, replacing: captionBeforePause)
        attachLive("jury-island-foreground-resume-real-audio", app)

        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(9))
        let stop = expandedJuryIslandControl("jury.demo.island.stop", in: springboard)
        stop.tap()
        app.activate()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10),
                      "The demo Island Stop must end the actual morning.")
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attachLive("jury-island-stopped-through-live-activity", app)
        #endif
    }

    private func expandedJuryIslandControl(_ identifier: String, in springboard: XCUIApplication) -> XCUIElement {
        let control = springboard.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if !control.waitForExistence(timeout: 5) || !control.isHittable {
            let compact = springboard.otherElements.matching(identifier: "regular.view")
                .containing(NSPredicate(format: "label BEGINSWITH[c] %@", "MORE."))
            let compactAppeared = compact.firstMatch.waitForExistence(timeout: 10)
            if !compactAppeared || compact.count != 1 {
                let hierarchy = XCTAttachment(string: springboard.debugDescription)
                hierarchy.name = "jury-island-missing-or-ambiguous-compact"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "jury-island-before-compact-assertion"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            XCTAssertTrue(compactAppeared,
                          "The observed compact MORE activity must be present; no coordinate fallback is allowed.")
            XCTAssertEqual(compact.count, 1, "An ambiguous MORE activity is not safe to open automatically.")
            compact.firstMatch.press(forDuration: 1.2)
        }
        let expanded = control.waitForExistence(timeout: 10)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = identifier
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if !expanded {
            let hierarchy = XCTAttachment(string: springboard.debugDescription)
            hierarchy.name = "jury-island-missing-demo-controls"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(expanded && control.isHittable,
                      "Only the demo-specific Island control may be tapped; the ordinary MORE activity is never controlled.")
        return control
    }

    private func launchDemo(french: Bool = true, additionalArguments: [String] = []) throws -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let workspace = UUID().uuidString
        let app = try demoApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace",
            "--ui-testing-workspace=\(workspace)", "--ui-testing-reduce-motion", "--theme-phase=day",
            "-more.appLanguage", french ? "fr" : "en", "-AppleLanguages", french ? "(fr)" : "(en)",
            "-AppleLocale", french ? "fr_FR" : "en_US"] + additionalArguments
        app.launch()
        let isolation = app.staticTexts["qa.testWorkspace"]
        XCTAssertTrue(isolation.waitForExistence(timeout: 10), "The launch must use a disposable test workspace.")
        XCTAssertEqual(isolation.value as? String, workspace)
        return app
    }

    private func demoApplication() throws -> XCUIApplication {
        let testBundle = Bundle(for: JuryDemoJourneyTests.self).bundleIdentifier ?? ""
        guard testBundle.hasSuffix(".uitests") else {
            throw NSError(domain: "JuryDemoJourneyTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The demo UI-test bundle identity is missing."])
        }
        let bundleID = String(testBundle.dropLast(".uitests".count))
        guard bundleID != "com.gibouu.morningoperator", bundleID.lowercased().split(separator: ".").contains("demo") else {
            throw NSError(domain: "JuryDemoJourneyTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Refusing to launch the ordinary MORE app."])
        }
        return XCUIApplication(bundleIdentifier: bundleID)
    }

    private func finishRealPermissionSetup(_ app: XCUIApplication) {
        for _ in 0..<12 {
            let finish = app.buttons["permissions.finish"]
            if finish.exists { finish.tap(); XCTAssertTrue(finish.waitForNonExistence(timeout: 5)); return }
            let title = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "permissions.title.")).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            let identifier = title.identifier
            let needsAccess = ["permissions.title.speech", "permissions.title.microphone", "permissions.title.reminders"].contains(identifier)
            let control = app.buttons[needsAccess ? "permissions.allow" : "permissions.skip"]
            reveal(control, in: app); control.tap()
            if needsAccess { handleRealSystemGrants() }
            XCTAssertTrue(app.staticTexts[identifier].waitForNonExistence(timeout: 15))
        }
        XCTFail("Real permission setup did not finish.")
    }

    /// Some iOS betas cannot bind a TCC interruption to the foreground app.
    /// Query the alert's actual owner instead of relying only on the monitor.
    private func handleRealSystemGrants() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for index in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: index == 0 ? 5 : 2) else { return }
            let explanation = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            guard explanation.localizedCaseInsensitiveContains("MORE") else {
                add(XCTAttachment(string: springboard.debugDescription))
                XCTFail("An unrelated system alert blocks the MORE permission request.")
                return
            }
            let allow = alert.buttons.matching(NSPredicate(format:
                "label ==[c] %@ OR label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@",
                "OK", "Allow", "Autoriser")).firstMatch
            guard allow.waitForExistence(timeout: 3), allow.isEnabled else {
                add(XCTAttachment(string: springboard.debugDescription))
                XCTFail("The real MORE authorization alert has no recognized Allow control.")
                return
            }
            allow.tap()
        }
    }

    /// Accepts the ordinary reading consent. It never supplies a spoken command.
    private func acceptLiveMorningVoiceConsent(_ app: XCUIApplication) {
        let consent = app.staticTexts["voice.readingConsent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 8), "Each new live morning must review online voice consent.")
        let begin = app.buttons["voice.access.begin"]
        if begin.waitForExistence(timeout: 1) {
            reveal(begin, in: app); begin.tap()
        } else {
            let prepare = app.buttons["voice.access.prepare"]
            XCTAssertTrue(prepare.waitForExistence(timeout: 5), "Real grants must be prepared before this morning can begin.")
            reveal(prepare, in: app); prepare.tap()
        }
        handleRealSystemGrants()
        XCTAssertTrue(consent.waitForNonExistence(timeout: 20),
                      "The real preparation must finish and dismiss before accepting audio as evidence.")
        handleRealSystemGrants() // Includes the genuine local-network grant, if requested.
    }

    private func waitForLiveSpokenPassage(_ app: XCUIApplication, replacing previous: String? = nil) async {
        let caption = app.staticTexts["morning.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        let spoken = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = caption.label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            let isPreparedPassage = ["bonjour", "tu as dormi", "on regarde le message"].contains { text.contains($0) }
            return (previous == nil || caption.label != previous) && isPreparedPassage &&
                !["indisponible", "connexion", "configuree", "autorisation"].contains { text.contains($0) }
        }, object: caption)
        let result = await XCTWaiter.fulfillment(of: [spoken], timeout: 45)
        XCTAssertEqual(result, .completed,
                       "Only a passage published after real backend audio playback starts counts as success.")
    }

    private func revealLivePlayback(_ app: XCUIApplication) -> XCUIElement {
        let control = app.buttons["morning.playback"]
        if !control.exists || !control.isHittable {
            let captions = app.scrollViews["morning.captions"]
            XCTAssertTrue(captions.waitForExistence(timeout: 10)); captions.tap()
        }
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(control.isHittable)
        return control
    }

    private func openLiveSettings(_ app: XCUIApplication) {
        _ = revealLivePlayback(app)
        app.buttons["morning.settings"].tap()
        XCTAssertTrue(app.buttons["setup.routine"].waitForExistence(timeout: 5))
    }

    private func returnToLiveHome(_ app: XCUIApplication) {
        for _ in 0..<4 {
            if app.buttons["morning.actions"].exists || app.scrollViews["morning.captions"].exists { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        }
        XCTFail("Expected the ordinary MORE landscape.")
    }

    private func attachLive(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["morning.settings"]
        if !settings.exists {
            let landscape = app.buttons["morning.actions"]
            XCTAssertTrue(landscape.waitForExistence(timeout: 10))
            landscape.tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["setup.routine"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            let collection = app.collectionViews.firstMatch
            let container = collection.exists ? collection : app.scrollViews.firstMatch
            XCTAssertTrue(container.exists)
            container.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func assertNoSpecialPresentation(_ app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts["system.qaIdentity"].exists)
        XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
        XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
        XCTAssertFalse(app.buttons["paywall.restore"].exists)
        XCTAssertFalse(app.staticTexts["morning.currentStep"].exists)
        XCTAssertFalse(app.staticTexts["morning.remaining"].exists)
        XCTAssertFalse(app.staticTexts["morning.previousCaption"].exists)
    }
}
#endif
