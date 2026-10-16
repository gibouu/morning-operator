import AVFAudio
import XCTest

/// Synthetic data in a unique workspace. Never installs on or controls a physical phone.
@MainActor
final class LocalizationJourneyTests: XCTestCase {
    func testLanguageSwitchPersistsAndKeepsTwoVoiceChoices() {
        continueAfterFailure = false
        let workspace = UUID()
        var app = launch(workspace: workspace, initialLanguage: "fr")
        openSettings(app)
        choose("Français", in: app)
        XCTAssertTrue(app.staticTexts["Langue"].exists)
        attach("localization-fr-settings", app)
        let frenchInvitation = app.staticTexts["Aucune invitation n’est programmée."]
        scrollTo(frenchInvitation, in: app)
        XCTAssertTrue(frenchInvitation.exists)
        verifyVoices(app, french: true)

        choose("English", in: app)
        XCTAssertTrue(app.staticTexts["Language"].exists)
        attach("localization-en-settings", app)
        let englishInvitation = app.staticTexts["No invitation is scheduled."]
        scrollTo(englishInvitation, in: app)
        XCTAssertTrue(englishInvitation.exists)
        verifyVoices(app, french: false)
        app.terminate()

        // No preference override on relaunch: the choice must come from saved defaults,
        // while the device continues to prefer French.
        app = launch(workspace: workspace, systemLanguage: "fr")
        openSettings(app)
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        XCTAssertTrue(picker.buttons["English"].isSelected, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Language"].exists)
        choose("Français", in: app)
        XCTAssertTrue(picker.buttons["Français"].isSelected)
        verifyVoices(app, french: true)
        app.terminate()
    }

    func testVoiceGenderPersistsAcrossLaunchAndLanguageWithoutStartingAudio() {
        continueAfterFailure = false
        let workspace = UUID()
        var app = launch(workspace: workspace, initialLanguage: "en")
        openSettings(app)
        openVoiceChoices(app)
        XCTAssertEqual(app.buttons["voice.gender.female"].value as? String, "Selected",
                       "New workspaces start with the female voice.")
        app.buttons["voice.gender.male"].tap()
        XCTAssertEqual(app.buttons["voice.gender.male"].value as? String, "Selected")
        XCTAssertEqual(app.alerts.count, 0, "Choosing a voice does not request microphone access.")
        app.buttons["voice.done"].tap()
        app.terminate()

        app = launch(workspace: workspace, systemLanguage: "fr")
        openSettings(app)
        choose("Français", in: app)
        openVoiceChoices(app)
        XCTAssertEqual(app.buttons["voice.gender.male"].label, "Homme")
        XCTAssertEqual(app.buttons["voice.gender.male"].value as? String, "Sélectionné")
        app.buttons["voice.gender.female"].tap()
        XCTAssertEqual(app.buttons["voice.gender.female"].value as? String, "Sélectionné")
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["voice.done"].tap()
        app.terminate()

        app = launch(workspace: workspace)
        openSettings(app)
        openVoiceChoices(app)
        XCTAssertEqual(app.buttons["voice.gender.female"].label, "Femme")
        XCTAssertEqual(app.buttons["voice.gender.female"].value as? String, "Sélectionné")
        attach("voice-gender-restored-without-audio", app)
        app.terminate()
    }

    func testSameConnectionsAndRoutineInBothLanguagesWithoutChangingSavedText() {
        continueAfterFailure = false
        let workspace = UUID()
        let app = launch(workspace: workspace, initialLanguage: "fr")
        openSettings(app)
        scrollTo(app.buttons["setup.routine"], in: app, upward: false)
        app.buttons["setup.routine"].tap()
        let moment = app.descendants(matching: .any)["routine.step.0"].firstMatch
        XCTAssertTrue(moment.waitForExistence(timeout: 10), app.debugDescription)
        moment.tap()
        let titleField = app.textFields["step.name"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), app.debugDescription)
        titleField.tap()
        titleField.typeText(" — Salut / Hello (é)")
        let originalTitle = titleField.value as? String
        XCTAssertTrue(originalTitle?.contains("Salut / Hello") == true)
        app.buttons["step.save"].tap()
        attach("localization-fr-routine", app)
        back(app)
        scrollTo(app.buttons["setup.connections"], in: app, upward: false)
        app.buttons["setup.connections"].tap()
        XCTAssertTrue(app.navigationBars["Apps et comptes"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["connections.linkedin"].exists)
        XCTAssertTrue(app.buttons["connections.slack"].exists)
        XCTAssertTrue(app.staticTexts["connections.inlineSignIn"].label.contains("pendant l’apprentissage ou votre routine"))
        XCTAssertTrue(app.buttons["connections.gmailReader"].exists)
        attach("localization-fr-connections", app)
        back(app)
        choose("English", in: app)
        scrollTo(app.buttons["setup.connections"], in: app, upward: false)
        app.buttons["setup.connections"].tap()
        XCTAssertTrue(app.navigationBars["Apps & accounts"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["connections.linkedin"].exists)
        XCTAssertTrue(app.buttons["connections.slack"].exists)
        XCTAssertTrue(app.staticTexts["connections.inlineSignIn"].label.contains("during learning or your routine"))
        XCTAssertTrue(app.buttons["connections.gmailReader"].exists)
        attach("localization-en-connections", app)
        back(app)
        scrollTo(app.buttons["setup.routine"], in: app, upward: false)
        app.buttons["setup.routine"].tap()
        XCTAssertTrue(moment.waitForExistence(timeout: 10))
        moment.tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(titleField.value as? String, originalTitle)
        app.buttons["Cancel"].tap()
        attach("localization-en-routine-retained", app)
        app.terminate()
    }

    func testLanguageSwitchPausesSameSyntheticSession() {
        continueAfterFailure = false
        let app = launch(workspace: UUID(), initialLanguage: "fr", extraArguments: ["--ui-testing-automation"])
        app.buttons["morning.actions"].tap()
        app.buttons["morning.begin"].tap()
        let current = app.scrollViews["morning.captions"]
        XCTAssertTrue(current.waitForExistence(timeout: 10), app.debugDescription)
        let identity = current.value as? String
        let ids = identity?.split(separator: "|") ?? []
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.allSatisfy { UUID(uuidString: String($0)) != nil })
        current.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        choose("English", in: app)
        back(app)
        XCTAssertTrue(current.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(current.value as? String, identity)
        if !app.buttons["morning.playback"].exists { current.tap() }
        XCTAssertTrue(app.buttons["morning.playback"].label.contains("Continue"), app.debugDescription)
        attach("localization-active-session-preserved-paused", app)
        app.terminate()
    }

    func testPairedLearningAndNativeEmptyStates() {
        continueAfterFailure = false
        for french in [true, false] {
            let code = french ? "fr" : "en"
            var app = launch(workspace: UUID(), initialLanguage: code, extraArguments: ["--ui-testing-empty-workspace"])
            app.buttons["morning.actions"].tap()
            app.buttons["morning.begin"].tap()
            XCTAssertTrue(app.buttons["learn.screenTime"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.buttons["learn.connections"].exists)
            attach("localization-\(code)-learn-empty", app)
            app.buttons["learn.screenTime"].tap()
            scrollTo(app.buttons["learn.import"], in: app)
            XCTAssertTrue(app.buttons["learn.import"].exists, app.debugDescription)
            attach("localization-\(code)-learn-import", app)
            app.terminate()

            app = launch(workspace: UUID(), initialLanguage: code)
            openSettings(app)
            scrollTo(app.buttons["setup.connections"], in: app, upward: false)
            app.buttons["setup.connections"].tap()
            let reminders = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", french ? "Rappels" : "Reminders")).firstMatch
            scrollTo(reminders, in: app)
            reminders.tap()
            XCTAssertTrue(app.buttons["native.remindersRead"].waitForExistence(timeout: 10), app.debugDescription)
            attach("localization-\(code)-native-reminders-empty", app)
            app.terminate()
        }
    }

    func testPairedInAppBrowserControls() {
        continueAfterFailure = false
        for french in [true, false] {
            let code = french ? "fr" : "en"
            let app = XCUIApplication()
            let workspace = UUID().uuidString
            app.launchArguments = ["--ui-testing", "--web-morning", "--web-morning-site=news", "--light-preview",
                                   "--ui-testing-workspace=\(workspace)", "-more.appLanguage", code, "-webMorning.explained", "NO"]
            launchConfirmedWorkspace(app, workspace: workspace)
            let explanation = app.buttons["web.aboutDone"]
            if explanation.waitForExistence(timeout: 4) {
                attach("localization-\(code)-browser-explanation", app)
                explanation.tap()
            }
            XCTAssertTrue(app.buttons["web.close"].waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertEqual(app.buttons["web.close"].label, french ? "Fermer" : "Close")
            XCTAssertEqual(app.buttons["web.reload"].label, french ? "Recharger la page" : "Reload page")
            attach("localization-\(code)-browser-controls", app)
            app.terminate()
        }
    }

    func testSleepStaysOffAndItsUnavailableReaderErrorFollowsThePersistedLanguage() {
        continueAfterFailure = false
        let workspace = UUID()
        let fixture = ["--ui-testing-briefing-fixture"]
        var app = launch(workspace: workspace, initialLanguage: "en", extraArguments: fixture)
        defer { app.terminate() }
        openSettings(app)
        let sources = app.buttons["setup.briefing"]
        scrollTo(sources, in: app, upward: false)
        XCTAssertEqual(sources.label, "Calendar & weather")
        sources.tap()
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 5), app.debugDescription)
        let sleep = app.switches["briefing.healthIncluded"].firstMatch
        scrollTo(sleep, in: app)
        XCTAssertEqual(sleep.label, "Health in my morning")
        XCTAssertEqual(sleep.value as? String, "0")
        let issue = app.staticTexts["briefing.healthError"]
        XCTAssertFalse(issue.exists)
        attach("localization-en-sleep-off-default", app)

        // This fixture has no HealthKit reader. One attempted inclusion cannot prompt or read Health.
        let nativeSwitch = sleep.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { sleep.tap() }
        XCTAssertTrue(issue.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(issue.label, "Sleep reading is not available in this version.")
        XCTAssertEqual(sleep.value as? String, "0")
        XCTAssertEqual(app.alerts.count, 0)
        attach("localization-en-sleep-unavailable", app)
        app.navigationBars["Your day"].buttons["Done"].tap()

        choose("Français", in: app)
        scrollTo(sources, in: app, upward: false)
        XCTAssertEqual(sources.label, "Calendrier et météo")
        sources.tap()
        XCTAssertTrue(app.navigationBars["Votre journée"].waitForExistence(timeout: 5), app.debugDescription)
        scrollTo(sleep, in: app)
        XCTAssertEqual(sleep.label, "La santé dans mon matin")
        XCTAssertEqual(sleep.value as? String, "0")
        XCTAssertTrue(issue.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(issue.label, "La lecture du sommeil n’est pas disponible dans cette version.")
        XCTAssertEqual(app.alerts.count, 0)
        attach("localization-fr-sleep-retained-error-off", app)
        app.terminate()

        // The saved French choice must win over English system preferences; no second Health action.
        app = launch(workspace: workspace, systemLanguage: "en", extraArguments: fixture)
        openSettings(app)
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        XCTAssertTrue(picker.buttons["Français"].isSelected, app.debugDescription)
        let restoredSources = app.buttons["setup.briefing"]
        scrollTo(restoredSources, in: app, upward: false)
        XCTAssertEqual(restoredSources.label, "Calendrier et météo")
        restoredSources.tap()
        let restoredSleep = app.switches["briefing.healthIncluded"].firstMatch
        scrollTo(restoredSleep, in: app)
        XCTAssertEqual(restoredSleep.label, "La santé dans mon matin")
        XCTAssertEqual(restoredSleep.value as? String, "0")
        XCTAssertFalse(app.staticTexts["briefing.healthError"].exists, "Connection failures stay transient across relaunch.")
        XCTAssertEqual(app.alerts.count, 0)
        attach("localization-fr-sleep-off-after-relaunch", app)
    }

    func testUnsupportedSystemLanguageStartsInEnglish() {
        continueAfterFailure = false
        let app = launch(workspace: UUID(), initialLanguage: "unsupported", systemLanguage: "de")
        openSettings(app)
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        XCTAssertEqual(picker.buttons.count, 2)
        XCTAssertTrue(picker.buttons["English"].isSelected)
        XCTAssertTrue(app.staticTexts["Language"].exists)
        attach("localization-unsupported-system-fallback", app)
        app.terminate()
    }

    private func launch(workspace: UUID, initialLanguage: String? = nil, systemLanguage: String = "en", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved", "--light-preview", "--ui-testing-reduce-motion",
                               "--ui-testing-workspace=\(workspace.uuidString)", "-AppleLanguages", "(\(systemLanguage))",
                               "-AppleLocale", systemLanguage == "fr" ? "fr_FR" : "en_US"]
        app.launchArguments += extraArguments
        if let initialLanguage { app.launchArguments += ["-more.appLanguage", initialLanguage] }
        launchConfirmedWorkspace(app, workspace: workspace.uuidString)
        let home = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["morning.actions"].exists || app.scrollViews["morning.captions"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [home], timeout: 15), .completed, app.debugDescription)
        return app
    }

    private func launchConfirmedWorkspace(_ app: XCUIApplication, workspace: String) {
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) || marker.value as? String != workspace {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(marker.value as? String, workspace, app.debugDescription)
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["morning.settings"]
        if !(settings.exists && settings.isHittable) {
            let reading = app.scrollViews["morning.captions"]
            if reading.exists { reading.tap() }
            else { app.buttons["morning.actions"].tap() }
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(settings.isHittable, app.debugDescription)
        settings.tap()
        XCTAssertTrue(app.buttons["setup.connections"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func choose(_ language: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        // A retained Settings position can put the segment under the navigation
        // bar even when XCTest reports it hittable. Move the whole row clear.
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        for _ in 0..<3 where picker.frame.minY < top {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let shift = min(180, max(60, top + 12 - picker.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: shift)))
        }
        XCTAssertGreaterThanOrEqual(picker.frame.minY, top, app.debugDescription)
        picker.buttons[language].tap()
        XCTAssertTrue(picker.buttons[language].isSelected, app.debugDescription)
    }

    private func verifyVoices(_ app: XCUIApplication, french: Bool) {
        openVoiceChoices(app)
        XCTAssertEqual(app.buttons["voice.gender.male"].label, french ? "Homme" : "Male")
        XCTAssertEqual(app.buttons["voice.gender.female"].label, french ? "Femme" : "Female")
        attach(french ? "localization-fr-voices" : "localization-en-voices", app)
        let preview = app.buttons["voice.preview"]
        XCTAssertEqual(preview.label, french ? "Écouter" : "Listen")
        preview.tap()
        let stop = app.buttons["voice.stopPreview"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), app.debugDescription)
        let speaking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@",
            french ? "Lecture en cours…" : "Speaking…"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 10), .completed, app.debugDescription)
        XCTAssertEqual(app.alerts.count, 0, "The fixed sample never requests microphone access.")
        stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 5))
        app.buttons["voice.done"].tap()
    }

    private func openVoiceChoices(_ app: XCUIApplication) {
        let voice = app.buttons["setup.voice"]
        scrollTo(voice, in: app)
        voice.tap()
        XCTAssertTrue(app.buttons["voice.gender.male"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["voice.gender.female"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'voice.gender.'")).count, 2)
        XCTAssertFalse(app.buttons["voice.default"].exists)
        XCTAssertTrue(app.buttons["voice.preview"].exists)
        XCTAssertEqual(app.searchFields.count, 0)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ElevenLabs")).firstMatch.exists)
    }

    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<6 {
            if element.exists && element.isHittable { break }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        for _ in 0..<10 {
            if element.exists && element.isHittable { break }
            if upward { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Opt-in acceptance on the owner's ordinary installation. No workspace, language
/// override, permission grant or routine execution is injected. Only the app's
/// fixed, non-personal voice sample is sent through its ordinary playback route.
@MainActor
final class PhysicalLocalizationAcceptanceTests: XCTestCase {
    func testFrenchEnglishVoiceChoicePersistsInOrdinaryApp() throws {
        guard ProcessInfo.processInfo.environment["MORE_PHYSICAL_LOCALIZATION_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Physical language acceptance requires its explicit runner opt-in.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This acceptance requires a physical iPhone.")
        #else
        // Swift errors let the best-effort preference restoration run on failures too.
        continueAfterFailure = true
        captureInstalledAppleVoiceQuality()
        let requirePrimary = ProcessInfo.processInfo.environment["MORE_REQUIRE_PRIMARY_PREVIEW"] == "1"
        let app = XCUIApplication(bundleIdentifier: "com.gibouu.morningoperator")
        app.launchArguments = []
        app.launchEnvironment = [:]
        try relaunchAndOpenSettings(app)
        let picker = app.segmentedControls["setup.language"]
        try reveal(picker, in: app)
        let selectedLanguages = ["Français", "English"].filter { picker.buttons[$0].isSelected }
        let originalLanguage = try XCTUnwrap(selectedLanguages.count == 1 ? selectedLanguages.first : nil)
        try openVoices(app)
        let originalGender = try selectedGender(in: app)
        app.buttons["voice.done"].tap()
        var restored = false
        defer {
            if !restored {
                do { try restore(language: originalLanguage, gender: originalGender, in: app) }
                catch { XCTFail("The original language and voice preferences could not be restored.") }
            }
        }

        for language in ["Français", "English"] {
            try reveal(picker, in: app)
            XCTAssertEqual(picker.buttons.count, 2)
            picker.buttons[language].tap()
            XCTAssertTrue(picker.buttons[language].isSelected)
            XCTAssertTrue(app.staticTexts[language == "Français" ? "Langue" : "Language"].exists)
            for gender in ["male", "female"] {
                try openVoices(app)
                let male = app.buttons["voice.gender.male"], female = app.buttons["voice.gender.female"]
                XCTAssertEqual(male.label, language == "Français" ? "Homme" : "Male")
                XCTAssertEqual(female.label, language == "Français" ? "Femme" : "Female")
                XCTAssertFalse(app.buttons["voice.default"].exists)
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "voice.option.")).firstMatch.exists)
                let chosen = app.buttons["voice.gender.\(gender)"]
                chosen.tap()
                XCTAssertEqual(try selectedGender(in: app), gender)
                let preview = app.buttons["voice.preview"]
                try reveal(preview, in: app)
                preview.tap()
                let speaking = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", language == "Français" ? "Lecture en cours…" : "Speaking…"),
                    object: preview)
                let playbackObserved = XCTWaiter.wait(for: [speaking], timeout: 40) == .completed
                XCTAssertTrue(playbackObserved,
                               "The selected voice did not begin physical playback.")
                let backup = app.staticTexts.matching(NSPredicate(format: "label IN %@",
                    ["La voix de secours est activée.", "Backup voice is active."])).firstMatch.exists
                let capture = XCTAttachment(screenshot: app.screenshot())
                capture.name = "physical-\(language == "Français" ? "fr" : "en")-voice-\(gender)"
                capture.lifetime = .keepAlways
                add(capture)
                let ready = language == "Français" ? "Prêt à parler" : "Ready to speak"
                let completion = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    preview.value as? String == ready && !app.buttons["voice.stopPreview"].exists
                }, object: nil)
                let finished = XCTWaiter.wait(for: [completion], timeout: 45) == .completed
                XCTAssertTrue(finished, "The sample did not finish through its ordinary playback callback.")
                XCTAssertEqual(app.state, .runningForeground)
                let backupAfterPlayback = app.staticTexts.matching(NSPredicate(format: "label IN %@",
                    ["La voix de secours est activée.", "Backup voice is active."])).firstMatch.exists
                let unavailable = app.staticTexts.matching(NSPredicate(format: "label IN %@",
                    ["L’exemple vocal est indisponible. Réessayez.", "The voice sample is unavailable. Try again."])).firstMatch.exists
                XCTAssertFalse(unavailable, "The voice sample reported a playback failure.")
                if requirePrimary {
                    XCTAssertFalse(backup || backupAfterPlayback,
                                   "The primary voice failed; Apple backup playback is not a primary-provider pass.")
                }
                let route = playbackObserved ? (backup || backupAfterPlayback ? "apple-backup" : "primary") : "unconfirmed"
                let report = XCTAttachment(string: "language=\(language == "Français" ? "fr" : "en"); gender=\(gender); playback=\(route); finished=\(finished); primaryRequired=\(requirePrimary)")
                report.name = "physical-voice-route"
                report.lifetime = .keepAlways
                add(report)
                app.buttons["voice.done"].tap()

                try relaunchAndOpenSettings(app)
                try reveal(picker, in: app)
                XCTAssertTrue(picker.buttons[language].isSelected,
                              "The ordinary app did not retain its language across relaunch.")
                try openVoices(app)
                XCTAssertEqual(try selectedGender(in: app), gender,
                               "The ordinary app did not retain its voice choice across relaunch.")
                app.buttons["voice.done"].tap()
            }
        }
        try restore(language: originalLanguage, gender: originalGender, in: app)
        restored = true
        #endif
    }

    private func restore(language: String, gender: String, in app: XCUIApplication) throws {
        try relaunchAndOpenSettings(app)
        let picker = app.segmentedControls["setup.language"]
        try reveal(picker, in: app)
        picker.buttons[language].tap()
        try openVoices(app)
        app.buttons["voice.gender.\(gender)"].tap()
        app.buttons["voice.done"].tap()
        try relaunchAndOpenSettings(app)
        try reveal(picker, in: app)
        XCTAssertTrue(picker.buttons[language].isSelected)
        try openVoices(app)
        XCTAssertEqual(try selectedGender(in: app), gender)
        app.buttons["voice.done"].tap()
        app.navigationBars.buttons.firstMatch.tap()
    }

    private func captureInstalledAppleVoiceQuality() {
        // Read public inventory only. Never authorize/export Personal Voice or
        // report voice names/identifiers; keep just the best eligible quality.
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.identifier.hasPrefix("com.apple.")
                && !$0.voiceTraits.contains(.isPersonalVoice)
                && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        var rows: [String] = []
        for language in ["fr", "en"] {
            for gender in ["male", "female"] {
                let best = voices.filter {
                    $0.language.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first.map { String($0) } == language
                        && (gender == "male" ? $0.gender == .male : $0.gender == .female)
                }.map { $0.quality.rawValue }.max()
                let quality = best.map { $0 >= 3 ? "Premium" : $0 == 2 ? "Enhanced" : "Standard" } ?? "none"
                rows.append("language=\(language); gender=\(gender); bestInstalledAppleQuality=\(quality)")
            }
        }
        let report = XCTAttachment(string: rows.joined(separator: "\n"))
        report.name = "physical-apple-voice-quality"
        report.lifetime = .keepAlways
        add(report)
    }

    private func relaunchAndOpenSettings(_ app: XCUIApplication) throws {
        app.terminate()
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 15) else {
            throw unreachable("The ordinary app did not reach the foreground.")
        }
        XCTAssertFalse(app.staticTexts["qa.testWorkspace"].exists)
        XCTAssertFalse(app.staticTexts["onboarding.preview"].exists)
        let landscape = app.buttons["morning.actions"]
        guard landscape.waitForExistence(timeout: 12) else {
            throw XCTSkip("The ordinary app's existing access/setup does not expose Home; no grant was changed.")
        }
        let settings = app.buttons["morning.settings"]
        for _ in 0..<3 {
            if settings.exists && settings.isHittable { break }
            landscape.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
            if settings.waitForExistence(timeout: 2) { break }
        }
        guard settings.exists && settings.isHittable else { throw unreachable("Settings was not reachable.") }
        settings.tap()
        guard app.buttons["setup.connections"].waitForExistence(timeout: 10) else {
            throw unreachable("The ordinary Settings did not appear.")
        }
    }

    private func openVoices(_ app: XCUIApplication) throws {
        let voice = app.buttons["setup.voice"]
        try reveal(voice, in: app)
        guard voice.isEnabled else {
            throw XCTSkip("Voice selection is unavailable during the existing morning session; it was not stopped or reset.")
        }
        voice.tap()
        guard app.buttons["voice.gender.male"].waitForExistence(timeout: 15) else {
            throw unreachable("The ordinary voice choices did not appear.")
        }
    }

    private func selectedGender(in app: XCUIApplication) throws -> String {
        let selected = ["male", "female"].filter { gender in
            let button = app.buttons["voice.gender.\(gender)"]
            return button.isSelected || ["Selected", "Sélectionné"].contains(button.value as? String ?? "")
        }
        return try XCTUnwrap(selected.count == 1 ? selected.first : nil)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        for upward in [true, false] {
            for _ in 0..<14 {
                if element.exists && element.isHittable { return }
                let list = app.collectionViews.firstMatch
                let container = list.exists ? list : app.scrollViews.firstMatch
                if upward { container.swipeUp() } else { container.swipeDown() }
            }
        }
        throw unreachable("The language or voice control was not reachable.")
    }

    private func unreachable(_ message: String) -> NSError {
        NSError(domain: "MOREPhysicalLocalization", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
