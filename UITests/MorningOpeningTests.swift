import XCTest

/// A start runs the approved routine on the landscape. These isolated fixtures
/// establish playback state and continuity, never live service access or audibility.
@MainActor
final class MorningOpeningUITests: XCTestCase {
    func testStartImmediatelyRunsTheFirstStepWithoutAnOpeningChoice() {
        let app = launch()
        defer { app.terminate() }
        start(app)
        assertStarted(app)
        XCTAssertEqual(app.staticTexts["morning.caption"].label, "Enjoy this moment. I’ll continue when its time is up.")
        XCTAssertFalse(app.buttons["opening.brief"].exists)
        XCTAssertFalse(app.buttons["opening.routine"].exists)
        XCTAssertFalse(app.staticTexts["run.state"].exists)
        XCTAssertFalse(app.staticTexts["run.step"].exists)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Pause")
        XCTAssertTrue(app.buttons["morning.settings"].isHittable)
        attach("direct-start-first-routine-passage", app)
    }

    func testVoicePreparationAndNaturalVoiceFlagsDoNotBlockStart() throws {
        #if !targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing speech on the selected phone.")
        }
        #endif
        let app = launch(extra: ["--ui-testing-voice-preparation", "--ui-testing-natural-voice-consent", "--ui-testing-read-aloud"])
        defer { app.terminate() }
        start(app)
        assertStarted(app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["speech"], "",
                       "Starting a routine does not request a separate spoken greeting.")
        attach("direct-start-without-voice-preparation", app)
    }

    func testPauseAndResumeKeepTheSameSessionAndMoment() {
        let app = launch(extra: ["--ui-testing-voice-preparation", "--ui-testing-natural-voice-consent"])
        defer { app.terminate() }
        start(app)
        assertStarted(app)
        let identity = sessionIdentity(in: app)
        MorningUITestNavigation.revealControls(in: app)
        app.buttons["morning.playback"].tap()
        MorningUITestNavigation.assertSession(state: "paused", step: "A quiet moment", in: app)
        XCTAssertEqual(sessionIdentity(in: app), identity)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Continue")
        app.buttons["morning.playback"].tap()
        assertStarted(app)
        XCTAssertEqual(sessionIdentity(in: app), identity)
        attach("direct-start-resumed-same-moment", app)
    }

    func testRelaunchRestoresTheSamePausedMorningWithoutAnOpening() {
        let app = launch(extra: ["--ui-testing-voice-preparation", "--ui-testing-natural-voice-consent"])
        start(app)
        assertStarted(app)
        let identity = sessionIdentity(in: app)
        app.terminate()
        MorningUITestNavigation.launch(app)
        defer { app.terminate() }
        MorningUITestNavigation.assertSession(state: "paused", step: "A quiet moment", in: app)
        XCTAssertEqual(sessionIdentity(in: app), identity)
        assertNoPreparation(app)
        let starts = MorningUITestNavigation.sessionSnapshot(in: app)["starts"]
        MorningUITestNavigation.tapButton("run.resume", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "A quiet moment", in: app)
        XCTAssertEqual(sessionIdentity(in: app), identity)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], starts,
                       "Resume must not start another morning.")
        assertNoPreparation(app)
    }

    func testAStoppedMorningCanStartANewSessionWithoutPreparation() {
        let app = launch(extra: ["--ui-testing-voice-preparation", "--ui-testing-natural-voice-consent"])
        defer { app.terminate() }
        start(app)
        assertStarted(app)
        let identity = sessionIdentity(in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
        MorningUITestNavigation.assertSession(state: "stopped", in: app)
        start(app)
        MorningUITestNavigation.assertSession(state: "running", step: "A quiet moment", in: app)
        assertNoPreparation(app)
        XCTAssertNotEqual(sessionIdentity(in: app), identity, "A new morning needs a new session identity.")
        attach("direct-start-new-morning-after-stop", app)
    }

    func testAutomaticRoutineCompletesWithoutASecondStartOrNext() {
        let app = launch(extra: ["--ui-testing-hands-free", "--ui-testing-short-budgets",
                                 "--ui-testing-voice-preparation", "--ui-testing-natural-voice-consent"])
        defer { app.terminate() }
        start(app)
        assertStarted(app)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.sessionSnapshot(in: app)["state"] == "completed"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 35), .completed, app.debugDescription)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["completed"], "2")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
        assertNoPreparation(app)
        attach("direct-start-automatic-routine-completed", app)
    }

    func testFrenchLargestTextStartsAndPausesOnTheLandscape() {
        let app = launch(extra: ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
                                 "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                 "--ui-testing-voice-preparation", "--ui-testing-natural-voice-consent"])
        defer { app.terminate() }
        MorningUITestNavigation.revealControls(in: app)
        let play = app.buttons["morning.begin"]
        XCTAssertTrue(play.isHittable)
        XCTAssertGreaterThanOrEqual(play.frame.width, 44)
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        start(app)
        assertStarted(app)
        let identity = sessionIdentity(in: app)
        MorningUITestNavigation.revealControls(in: app)
        let pause = app.buttons["morning.playback"]
        XCTAssertTrue(pause.isHittable)
        XCTAssertEqual(pause.label, "Pause")
        XCTAssertGreaterThanOrEqual(pause.frame.width, 44)
        XCTAssertGreaterThanOrEqual(pause.frame.height, 44)
        XCTAssertTrue(app.buttons["morning.settings"].isHittable)
        attach("direct-start-french-largest-running", app)
        pause.tap()
        MorningUITestNavigation.assertSession(state: "paused", in: app)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Continuer")
        XCTAssertEqual(sessionIdentity(in: app), identity)
        assertNoPreparation(app)
        attach("direct-start-french-largest-paused", app)
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview", "--ui-testing-automation",
                               "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-approved"] + extra
        if !extra.contains("-more.appLanguage") { app.launchArguments += ["-more.appLanguage", "en"] }
        MorningUITestNavigation.launch(app)
        return app
    }

    private func start(_ app: XCUIApplication) {
        // Do not let the compatibility helper dismiss an unexpected opening.
        MorningUITestNavigation.tapButton("run.start", in: app, keepingOpening: true)
    }

    private func assertStarted(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        MorningUITestNavigation.assertSession(state: "running", step: "A quiet moment", in: app, file: file, line: line)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1", file: file, line: line)
        XCTAssertTrue(app.staticTexts["morning.caption"].exists, file: file, line: line)
        assertNoPreparation(app, file: file, line: line)
    }

    private func assertNoPreparation(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none", file: file, line: line)
        XCTAssertFalse(app.staticTexts["voice.access.status"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["voice.readingConsent"].exists, file: file, line: line)
        XCTAssertEqual(app.sheets.count, 0, file: file, line: line)
        XCTAssertEqual(app.alerts.count, 0, file: file, line: line)
    }

    private func sessionIdentity(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> String {
        let identity = app.scrollViews["morning.captions"].value as? String ?? ""
        let identifiers = identity.components(separatedBy: "|")
        XCTAssertEqual(identifiers.count, 2, file: file, line: line)
        XCTAssertTrue(identifiers.allSatisfy { UUID(uuidString: $0) != nil }, file: file, line: line)
        return identity
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
