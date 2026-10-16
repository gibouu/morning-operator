import XCTest

/// Isolated timed moments and local speech; no personal account or recording.
@MainActor
final class MorningHomePlaybackTests: XCTestCase {
    private let longPassage = "Take your time this morning. Let the light come into the room while you take a slow breath and prepare for the day ahead. There is nothing to press while MORE reads this passage. You can keep getting ready and return whenever you want to read along. Each passage should replace the one being spoken before it. Your routine stays here on the same home screen. If you need a little longer, a tap makes the small controls available. When this quiet moment ends, MORE will continue with the next part of your morning."

    func testDaySettingsKeepTheirAppearanceAcrossRoutineAccountsAndVoice() {
        let app = launch()
        defer { app.terminate() }
        openIdleSettings(app)
        assertSettingsAppearance("day", in: app)
        XCTAssertTrue(app.buttons["setup.routine"].isHittable)
        attach("settings-day-top", app)
        app.buttons["setup.routine"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].isHittable)
        attach("settings-day-routine", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertSettingsAppearance("day", in: app)
        settingsButton("setup.connections", in: app).tap()
        XCTAssertTrue(app.navigationBars["Apps & accounts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["connections.instagram"].exists)
        attach("settings-day-apps-and-accounts", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertSettingsAppearance("day", in: app)
        settingsButton("setup.voice", in: app).tap()
        XCTAssertTrue(app.buttons["voice.gender.male"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["voice.gender.female"].exists)
        XCTAssertTrue(app.navigationBars["Voice"].exists)
        XCTAssertTrue(app.buttons["voice.done"].isHittable)
        attach("settings-day-voice", app)
        app.buttons["voice.done"].tap()
        assertSettingsAppearance("day", in: app)
    }

    func testNightSettingsRemainReadableInFrenchAtLargestTextSize() {
        let app = launch(["--ui-testing-reduce-motion", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"], french: true, night: true)
        defer { app.terminate() }
        openIdleSettings(app)
        assertSettingsAppearance("night", in: app)
        let routine = app.buttons["setup.routine"]
        XCTAssertTrue(routine.isHittable)
        assertFitsOnScreen(routine, in: app)
        attach("settings-night-french-largest-top", app)
        routine.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].isHittable)
        attach("settings-night-french-largest-routine", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertSettingsAppearance("night", in: app)
        let accounts = settingsButton("setup.connections", in: app)
        assertFitsOnScreen(accounts, in: app)
        attach("settings-night-french-largest-connections-row", app)
        accounts.tap()
        XCTAssertTrue(app.navigationBars["Apps et comptes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["connections.instagram"].exists)
        attach("settings-night-french-largest-apps-and-accounts", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertSettingsAppearance("night", in: app)
        settingsButton("setup.voice", in: app).tap()
        let male = app.buttons["voice.gender.male"]
        let female = app.buttons["voice.gender.female"]
        XCTAssertTrue(male.waitForExistence(timeout: 5))
        XCTAssertEqual(male.label, "Homme")
        XCTAssertEqual(female.label, "Femme")
        assertFitsOnScreen(male, in: app)
        assertFitsOnScreen(female, in: app)
        attach("settings-night-french-largest-voice", app)
        app.buttons["voice.done"].tap()
        assertSettingsAppearance("night", in: app)
    }

    func testConnectionsExplainProfessionalLimitsAndReturnFromWebsiteNativeAndAccountDestinations() {
        let app = launch(["--ui-testing-connections-catalog", "--ui-testing-briefing-fixture"])
        defer { app.terminate() }
        openIdleSettings(app)
        settingsButton("setup.connections", in: app).tap()
        let title = app.navigationBars["Apps & accounts"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        app.buttons["connections.instagram"].tap()
        XCTAssertTrue(app.buttons["web.close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "web.page").firstMatch.exists)
        XCTAssertTrue(app.buttons["connections.confirmReady"].exists)
        attach("connections-website-destination-only", app)
        app.buttons["web.close"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["connections.instagram"].label.contains("Website · Sign in"))

        connectionControl("connections.calendar", in: app).tap()
        let done = app.navigationBars["Your day"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        attach("connections-native-day-destination", app)
        done.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        connectionControl("connections.account.notion", in: app).tap()
        XCTAssertTrue(app.buttons["accounts.connect.notion"].waitForExistence(timeout: 5))
        attach("connections-synthetic-empty-account-destination", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        connectionControl("connections.professional", in: app).tap()
        let limits = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Instagram requires a professional account")).firstMatch
        XCTAssertTrue(limits.waitForExistence(timeout: 5))
        XCTAssertTrue(limits.label.contains("WhatsApp requires a Business Cloud account"))
        XCTAssertTrue(limits.label.contains("Facebook uses your Pages"))
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "connections-synthetic-professional-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
        for name in ["Instagram professional", "WhatsApp Business Cloud", "Facebook Pages"] {
            // DisclosureGroup gives its links the same accessibility identifier.
            let row = app.staticTexts[name]
            scrollConnectionControl(row, in: app)
            assertFitsOnScreen(row, in: app)
        }
        attach("connections-synthetic-professional-limits-and-rows", app)
        for (name, service) in [("Instagram professional", "instagram"), ("WhatsApp Business Cloud", "whatsapp"), ("Facebook Pages", "facebook")] {
            let row = app.staticTexts[name]
            scrollConnectionControl(row, in: app)
            row.tap()
            XCTAssertTrue(app.navigationBars[service.capitalized].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["accounts.connect.\(service)"].waitForExistence(timeout: 5))
            attach("connections-synthetic-professional-\(service)-destination", app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertSettingsAppearance("day", in: app)
    }

    func testFrenchLargestNightProfessionalConnectionsKeepTheirTitlesReachable() {
        let app = launch(["--ui-testing-connections-catalog", "--ui-testing-reduce-motion",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true, night: true)
        defer { app.terminate() }
        openIdleSettings(app)
        settingsButton("setup.connections", in: app).tap()
        let professional = app.staticTexts["Comptes professionnels"]
        for _ in 0..<20 where !professional.exists || !professional.isHittable { app.swipeUp(velocity: .fast) }
        scrollConnectionControl(professional, in: app)
        professional.tap()
        for (index, name) in ["Instagram professionnel", "WhatsApp Business Cloud", "Facebook Pages"].enumerated() {
            let row = app.staticTexts[name]
            scrollConnectionControl(row, in: app)
            assertFitsOnScreen(row, in: app)
            attach("connections-french-largest-night-professional-\(index)", app)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertSettingsAppearance("night", in: app)
    }

    func testFrenchLargestNightConnectionsExplainUnavailableAccountsAndKeepRetryReachable() {
        let app = launch(["--ui-testing-connections-unavailable", "--ui-testing-reduce-motion",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true, night: true)
        defer { app.terminate() }
        openIdleSettings(app)
        settingsButton("setup.connections", in: app).tap()
        XCTAssertTrue(app.navigationBars["Apps et comptes"].waitForExistence(timeout: 5))
        let issue = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Impossible de charger vos comptes")).firstMatch
        scrollConnectionControl(issue, in: app)
        attach("connections-french-largest-night-unavailable-accounts", app)
        let retry = app.buttons["Réessayer"]
        scrollConnectionControl(retry, in: app)
        XCTAssertTrue(retry.isEnabled)
        assertFitsOnScreen(retry, in: app)
        retry.tap()
        scrollConnectionControl(issue, in: app)
        XCTAssertFalse(app.buttons["connections.account.slack"].exists)
        attach("connections-french-largest-night-unavailable-retry", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertSettingsAppearance("night", in: app)
    }

    func testNightSettingsAndWeatherSheetUseDarkAppearanceAtStandardTextSize() {
        let app = launch(["--ui-testing-briefing-fixture"], night: true)
        defer { app.terminate() }
        openIdleSettings(app)
        assertSettingsAppearance("night", in: app)
        attach("settings-night-standard-text", app)
        settingsButton("setup.briefing", in: app).tap()
        let done = app.navigationBars["Your day"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        let location = app.descendants(matching: .any).matching(identifier: "briefing.locationSource").firstMatch
        for _ in 0..<6 where !(location.exists && location.isHittable) {
            let form = app.collectionViews.firstMatch
            let container = form.exists ? form : app.scrollViews.firstMatch
            container.swipeUp()
        }
        XCTAssertTrue(location.exists && location.isHittable)
        XCTAssertEqual(app.alerts.count, 0)
        attach("settings-night-standard-weather-sheet", app)
        done.tap()
        assertSettingsAppearance("night", in: app)
    }

    func testNightSettingsPermissionsKeepDarkAppearance() {
        let app = launch(night: true)
        defer { app.terminate() }
        openIdleSettings(app)
        assertSettingsAppearance("night", in: app)
        settingsButton("setup.permissions", in: app).tap()
        XCTAssertTrue(app.buttons["permissions.option.location"].waitForExistence(timeout: 5))
        app.buttons["permissions.option.location"].tap()
        XCTAssertTrue(app.staticTexts["permissions.title.location"].waitForExistence(timeout: 5))
        for identifier in ["permissions.allow", "permissions.skip"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(button.isEnabled)
            assertFitsOnScreen(button, in: app)
        }
        XCTAssertEqual(app.alerts.count, 0)
        attach("settings-night-standard-iphone-permissions", app)
    }

    func testIdleTapShowsOnlyPlayAndSettingsThenHidesAndOpensRoutineThroughSettings() {
        let app = launch()
        defer { app.terminate() }
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["morning.begin"].exists)
        XCTAssertFalse(app.buttons["morning.settings"].exists)
        landscape.tap()
        let play = app.buttons["morning.begin"]
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(play.isHittable)
        XCTAssertTrue(settings.isHittable)
        let visibleButtons = Set(app.buttons.allElementsBoundByIndex.map(\.identifier))
            .subtracting(["morning.actions"])
        XCTAssertEqual(visibleButtons, Set(["morning.begin", "morning.settings"]))
        XCTAssertEqual(play.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(play.frame.midY, app.frame.midY, accuracy: app.frame.height * 0.12)
        XCTAssertGreaterThan(settings.frame.midX, app.frame.midX)
        XCTAssertLessThan(settings.frame.maxY, app.frame.height * 0.25)
        XCTAssertFalse(app.buttons["morning.closeActions"].exists)
        XCTAssertFalse(app.buttons["morning.review"].exists)
        XCTAssertFalse(app.staticTexts["morning.readyQuestion"].exists)
        XCTAssertEqual(app.scrollViews.count, 0)
        attach("home-idle-only-glass-play-and-settings", app)
        XCTAssertTrue(play.waitForNonExistence(timeout: 7))
        XCTAssertFalse(settings.exists)
        attach("home-idle-controls-hidden", app)

        landscape.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let routine = app.buttons["setup.routine"]
        XCTAssertTrue(routine.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["morning.begin"].exists)
        routine.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("home-idle-routine-reached-through-settings", app)
    }

    func testHomeShowsOnlyCurrentTextAndContinuesAutomatically() {
        let app = launch(["--ui-testing-short-budgets"], night: true)
        defer { app.terminate() }
        start(app)
        assertCaption("Take a breath.", in: app)
        assertPureReading(app)
        attach("home-playback-only-current-text", app)

        assertCaption("Your next moment.", in: app, timeout: 15)
        assertPureReading(app)
        attach("home-playback-automatic-next-text", app)
    }

    func testLiveUserTranscriptionReplacesTheSingleCaptionAsWordsAndCorrectionsArrive() {
        let app = launch(["--ui-testing-live-captions"], french: true)
        defer { app.terminate() }
        start(app)
        assertCaption("Je", in: app, timeout: 10)
        assertCaption("Je voudrais", in: app)
        assertCaption("Je voudrais connaître mon prochain rendez-vous.", in: app)
        assertCaption("Je voudrais connaître mes prochains rendez-vous.", in: app)

        assertCaption("Votre prochain rendez-vous est à neuf heures.", in: app, timeout: 12)
        assertPureReading(app)
        attach("home-synthetic-live-transcription-answer", app)
    }

    func testFrenchLargestNightLiveTranscriptionKeepsNewestWordsInTheSingleCaption() {
        let app = launch(["--ui-testing-live-captions", "--ui-testing-reduce-motion",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
                         french: true, night: true)
        defer { app.terminate() }
        start(app)
        let caption = app.staticTexts["morning.caption"]
        let newestWords = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label ENDSWITH %@", "puis prépare une réponse pour demain matin."), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [newestWords], timeout: 20), .completed)
        XCTAssertLessThanOrEqual(caption.label.count, 111)
        XCTAssertGreaterThanOrEqual(caption.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(caption.frame.maxX, app.frame.maxX)
        attach("home-synthetic-live-transcription-french-largest-night", app)

        assertCaption("Votre prochain rendez-vous est à neuf heures.", in: app, timeout: 10)
        assertPureReading(app)
    }

    func testFrenchLargestTextRevealsPauseAndKeepsNextInSettings() {
        let app = launch(["--ui-testing-reduce-motion", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"], french: true, night: true)
        defer { app.terminate() }
        start(app)
        assertPureReading(app)
        assertFitsOnScreen(app.staticTexts["morning.caption"], in: app)
        attach("home-playback-french-largest-pure-text", app)
        let readingFrame = app.scrollViews["morning.captions"].frame
        revealControls(app)
        XCTAssertEqual(app.scrollViews["morning.captions"].frame, readingFrame, "Revealing controls must not move the passage.")
        assertPassageClearOfPlayback(in: app)
        for identifier in ["morning.playback", "morning.settings"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            assertFitsOnScreen(button, in: app)
        }
        XCTAssertFalse(app.buttons["morning.next"].exists)
        XCTAssertFalse(app.buttons["morning.more"].exists)
        attach("home-playback-night-floating-glass-pause", app)
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Continuer", in: app)
        attach("home-playback-french-largest-revealed-controls", app)
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Pause", in: app)
        app.buttons["morning.settings"].tap()
        let next = app.buttons["morning.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.label, "Suivant")
        next.tap()
        returnHome(app)
        assertCaption("Your next moment.", in: app)
        assertNoHeaderOrHistory(app)
    }

    func testControlsHideAfterInactivityAndInteractionRestartsTheirLifetime() {
        let app = launch()
        defer { app.terminate() }
        start(app)
        let readingFrame = app.scrollViews["morning.captions"].frame
        revealControls(app)
        XCTAssertEqual(app.scrollViews["morning.captions"].frame, readingFrame)
        assertPassageClearOfPlayback(in: app)
        let playback = app.buttons["morning.playback"]
        assertRemainsVisible(playback, for: 3)
        playback.tap()
        assertPlaybackLabel("Continue", in: app)
        assertRemainsVisible(playback, for: 3)
        XCTAssertTrue(playback.waitForNonExistence(timeout: 7), "Controls must disappear after inactivity.")
        assertPureReading(app)
        attach("home-playback-controls-hidden-after-inactivity", app)
        revealControls(app)
        assertPlaybackLabel("Continue", in: app)
    }

    func testCaptionDragRestartsControlsLifetime() {
        let app = launch(["--ui-testing-reduce-motion", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        _ = setFirstMomentDetails(longPassage, in: app)
        start(app)
        revealControls(app)
        let playback = app.buttons["morning.playback"]
        assertRemainsVisible(playback, for: 3)
        let captions = app.scrollViews["morning.captions"]
        // The central floating Play/Pause symbol must not receive this drag.
        captions.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.65))
            .press(forDuration: 0.1, thenDragTo: captions.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.2)))
        assertRemainsVisible(playback, for: 3)
        XCTAssertTrue(playback.waitForNonExistence(timeout: 7), "Five seconds restart after the real caption drag ends.")
        attach("home-playback-caption-drag-controls-hidden-after-inactivity", app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        revealControls(app)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        assertPassageClearOfPlayback(in: app)
        attach("home-playback-largest-landscape-passage-clear-of-pause", app)
    }

    func testRealLocalSpeechReplacesTheSingleCaptionWithoutHistory() {
        let app = launch(["--ui-testing-read-aloud"], night: true)
        defer { app.terminate() }
        let configured = setFirstMomentDetails(longPassage, in: app)
        start(app)
        let caption = app.staticTexts["morning.caption"]
        let firstPassage = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label CONTAINS %@ AND label.length < %d", "Take your time this morning", configured.count), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [firstPassage], timeout: 15), .completed)
        let first = caption.label
        XCTAssertLessThan(first.count, configured.count)
        assertPureReading(app)
        attach("home-playback-real-speech-first-passage", app)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", first), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 35), .completed)
        XCTAssertFalse(caption.label.isEmpty)
        XCTAssertLessThan(caption.label.count, configured.count)
        assertPureReading(app)
        attach("home-playback-real-speech-replaced-passage", app)
    }

    private func launch(_ flags: [String] = [], french: Bool = false, night: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
            "--ui-testing-automation", "--ui-testing-hands-free", "--ui-testing-workspace=\(workspace)",
            night ? "--dark-preview" : "--light-preview", night ? "--theme-phase=night" : "--theme-phase=morning",
            "-more.appLanguage", french ? "fr" : "en",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"] + flags
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) || marker.value as? String != workspace {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.value as? String, workspace)
        return app
    }

    private func start(_ app: XCUIApplication) {
        let actions = app.buttons["morning.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.tap()
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()
        XCTAssertTrue(app.staticTexts["morning.caption"].waitForExistence(timeout: 8))
    }

    private func revealControls(_ app: XCUIApplication) {
        let reveal = app.scrollViews["morning.captions"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        reveal.tap()
        XCTAssertTrue(app.buttons["morning.playback"].waitForExistence(timeout: 5))
    }

    private func assertPassageClearOfPlayback(in app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let reading = app.scrollViews["morning.captions"], passage = app.staticTexts["morning.caption"]
        let playback = app.buttons["morning.playback"]
        XCTAssertTrue(reading.exists && passage.exists && playback.isHittable, file: file, line: line)
        let visiblePassage = passage.frame.intersection(reading.frame)
        XCTAssertFalse(visiblePassage.isNull || visiblePassage.isEmpty, file: file, line: line)
        XCTAssertFalse(reading.frame.intersects(playback.frame), "The real reading viewport must exclude the central control.", file: file, line: line)
        XCTAssertFalse(visiblePassage.intersects(playback.frame), "The visible spoken passage must remain readable.", file: file, line: line)
    }

    private func openIdleSettings(_ app: XCUIApplication) {
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10))
        landscape.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["setup.routine"].waitForExistence(timeout: 5))
    }

    private func assertSettingsAppearance(_ appearance: String, in app: XCUIApplication,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let marker = app.descendants(matching: .any).matching(identifier: "settings.appearance").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(marker.value as? String, appearance, file: file, line: line)
    }

    private func settingsButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<14 {
            if button.exists && button.isHittable { break }
            let form = app.collectionViews.firstMatch
            let container = form.exists ? form : app.scrollViews.firstMatch
            container.swipeUp()
        }
        XCTAssertTrue(button.exists && button.isHittable, "Settings keeps \(identifier) reachable.")
        return button
    }

    private func connectionControl(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        scrollConnectionControl(control, in: app)
        return control
    }

    private func scrollConnectionControl(_ control: XCUIElement, in app: XCUIApplication) {
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.frame.maxY - 24
        for attempt in 0..<20 {
            let frame = control.exists ? control.frame : .zero
            let fits = frame.height > bottom - top || (frame.minY >= top && frame.maxY <= bottom)
            if control.exists && control.isHittable && fits { return }
            if frame.height > 0 {
                // A full swipe can jump over a tall accessibility row forever.
                // Move its nearest clipped edge into the visible content area.
                let distance = frame.minY < top
                    ? min(160, top - frame.minY + 12)
                    : -min(160, frame.maxY - bottom + 12)
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
            } else if attempt < 10 { app.swipeUp() }
            else { app.swipeDown() }
        }
        XCTAssertTrue(control.exists && control.isHittable)
    }

    private func setFirstMomentDetails(_ text: String, in app: XCUIApplication) -> String {
        app.buttons["morning.actions"].tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let review = app.buttons["setup.routine"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        let first = app.buttons["routine.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step details")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        details.typeText(text)
        let configured = details.value as? String ?? ""
        XCTAssertTrue(configured.contains(text))
        app.buttons["step.save"].tap()
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.tap()
        returnHome(app)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5))
        return configured
    }

    private func returnHome(_ app: XCUIApplication) {
        for _ in 0..<3 {
            if app.buttons["morning.actions"].exists || app.scrollViews["morning.captions"].exists { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        XCTFail("Expected to return to the landscape.")
    }

    private func assertPureReading(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.scrollViews["morning.captions"].exists, file: file, line: line)
        XCTAssertEqual(app.staticTexts.matching(identifier: "morning.caption").count, 1, file: file, line: line)
        for identifier in ["morning.playback", "morning.settings", "morning.next", "morning.more", "morning.closeActions"] {
            XCTAssertFalse(app.buttons[identifier].exists, "Reading keeps controls hidden: \(identifier)", file: file, line: line)
        }
        assertNoHeaderOrHistory(app, file: file, line: line)
        XCTAssertFalse(app.textViews["mail.selfBody"].exists, file: file, line: line)
        XCTAssertEqual(app.navigationBars.count, 0, file: file, line: line)
    }

    private func assertNoHeaderOrHistory(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["morning.currentStep", "morning.remaining", "morning.previousCaption"] {
            XCTAssertFalse(app.staticTexts[identifier].exists, "Home keeps only the current passage: \(identifier)", file: file, line: line)
        }
    }

    private func assertCaption(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 5,
                               file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text),
                                                object: app.staticTexts["morning.caption"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: timeout), .completed, file: file, line: line)
    }

    private func assertPlaybackLabel(_ label: String, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label),
                                                object: app.buttons["morning.playback"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, file: file, line: line)
    }

    private func assertRemainsVisible(_ element: XCUIElement, for seconds: TimeInterval,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        disappeared.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: seconds), .completed, file: file, line: line)
    }

    private func assertFitsOnScreen(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, file: file, line: line)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
