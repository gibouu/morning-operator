import XCTest

/// The opening of a started morning in an isolated fixture workspace. The
/// landscape shows its passage; playback and Settings replace the old opening
/// cards. Speech observations prove requests, never audibility on a device.
@MainActor
final class MorningOpeningUITests: XCTestCase {
    func testStartShowsTheOpeningAndRoutineReachesTheFirstStep() {
        let app = launch()
        start(app)
        let opening = openingText(in: app)
        XCTAssertFalse(opening.label.isEmpty)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 0")
        XCTAssertFalse(app.buttons["opening.brief"].exists)
        XCTAssertFalse(app.staticTexts["run.state"].exists)
        XCTAssertFalse(app.staticTexts["run.step"].exists)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Continue")
        XCTAssertTrue(app.buttons["morning.settings"].isHittable)
        attach("opening-no-source-connected", app)
        let leaves = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.sessionSnapshot(in: app)["opening"] != "choosing"
        }, object: nil)
        leaves.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [leaves], timeout: 4), .completed,
                       "Without Hands free the opening waits for the playback choice.")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 0")
        MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none")
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Pause")
        attach("opening-routine-started-current-passage", app)
    }

    /// With spoken guidance off, a hands-free morning still starts without a tap.
    func testHandsFreeStartWithoutSpeechReachesTheFirstStepWithoutATap() {
        let app = launch(extra: ["--ui-testing-hands-free"])
        start(app)
        let handedOver = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let snapshot = MorningUITestNavigation.sessionSnapshot(in: app)
            return snapshot["opening"] == "none" && snapshot["starts"] == "routine started 1"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [handedOver], timeout: 15), .completed,
                       "A hands-free morning starts its routine on its own.\n\(app.debugDescription)")
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        XCTAssertFalse(app.buttons["opening.routine"].exists)
        XCTAssertFalse(app.staticTexts["opening.briefText"].exists)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Pause")
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    func testStopAtTheOpeningEndsTheMorning() {
        let app = launch()
        start(app)
        _ = openingText(in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
        MorningUITestNavigation.assertSession(state: "stopped", in: app)
        XCTAssertFalse(app.scrollViews["morning.captions"].exists)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 0")
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertTrue(app.buttons["morning.begin"].isHittable, "A stopped morning offers an explicit restart.")
        XCTAssertFalse(app.buttons["morning.playback"].exists)
    }

    func testOpeningDoesNotReturnAfterRelaunchOrWhenTheMorningContinues() {
        let app = launch()
        start(app)
        _ = openingText(in: app)
        let identity = app.scrollViews["morning.captions"].value as? String
        XCTAssertFalse(identity?.isEmpty ?? true)
        app.terminate()
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.assertSession(state: "paused", step: "Your morning", in: app)
        XCTAssertEqual(app.scrollViews["morning.captions"].value as? String, identity)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["speech"], "")
        let starts = MorningUITestNavigation.sessionSnapshot(in: app)["starts"]
        MorningUITestNavigation.tapButton("run.resume", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        XCTAssertEqual(app.scrollViews["morning.captions"].value as? String, identity)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], starts,
                       "Resuming the existing session must not hand over a new opening.")
    }

    func testSpokenGuidanceOffRequestsNoSpeech() {
        let app = launch()
        start(app)
        _ = openingText(in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["speech"], "silent")
        MorningUITestNavigation.openSettings(in: app)
        let status = app.staticTexts["setup.speechStatus"]
        reveal(status, in: app)
        XCTAssertEqual(status.value as? String, "idle")
    }

    /// Requests real synthesis. On a phone it retains the audible opt-in guard.
    func testSpokenGuidanceOnRequestsTheOpeningOnceAndNotAfterRelaunch() throws {
        #if !targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing speech on the selected phone.")
        }
        #endif
        let app = launch(approved: false)
        MorningUITestNavigation.openSettings(in: app)
        let readAloud = app.switches["setup.readAloud"]
        reveal(readAloud, in: app)
        XCTAssertEqual(readAloud.value as? String, "0")
        let nativeSwitch = readAloud.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { readAloud.tap() }
        XCTAssertEqual(readAloud.value as? String, "1")
        MorningUITestNavigation.openRoutine(in: app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        start(app)
        _ = openingText(in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["speech"], "speech requested")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 0")
        let identity = app.scrollViews["morning.captions"].value as? String
        app.terminate()
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.assertSession(state: "paused", step: "Your morning", in: app)
        XCTAssertEqual(app.scrollViews["morning.captions"].value as? String, identity)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none",
                       "A relaunch must not greet the same morning again.")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["speech"], "")
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    /// Native pictures in both languages, palettes and the largest text size.
    func testOpeningScreenshotsInEnglishFrenchAndLargestText() {
        for (name, arguments) in [
            ("opening-english", ["-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]),
            ("opening-french", ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]),
            ("opening-english-dark", ["--dark-preview", "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]),
            ("opening-french-dark", ["--dark-preview", "-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]),
        ] {
            let app = launch(extra: arguments)
            start(app)
            _ = openingText(in: app)
            attach(name, app)
            app.terminate()
        }
        for (name, language) in [("opening-largest-text-english", "en"), ("opening-largest-text-french", "fr")] {
            let app = launch(extra: ["-more.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US",
                                     "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
            MorningUITestNavigation.revealControls(in: app)
            let play = app.buttons["morning.begin"]
            XCTAssertTrue(play.isHittable)
            XCTAssertGreaterThanOrEqual(play.frame.width, 44)
            XCTAssertGreaterThanOrEqual(play.frame.height, 44)
            start(app)
            _ = openingText(in: app)
            let scroll = app.scrollViews["morning.captions"]
            XCTAssertTrue(scroll.exists)
            attach("\(name)-top", app)
            scroll.swipeUp()
            attach("\(name)-after-one-swipe", app)
            MorningUITestNavigation.revealControls(in: app)
            XCTAssertTrue(app.buttons["morning.playback"].isHittable)
            XCTAssertTrue(app.buttons["morning.settings"].isHittable)
            attach("\(name)-revealed-controls", app)
            app.terminate()
        }
    }

    private func launch(approved: Bool = true, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"] + (extra.contains("--dark-preview") ? [] : ["--light-preview"])
            + ["--ui-testing-workspace=\(UUID().uuidString)"]
            + (approved ? ["--ui-testing-approved"] : []) + extra
        if !extra.contains("-more.appLanguage") { app.launchArguments += ["-more.appLanguage", "en"] }
        MorningUITestNavigation.launch(app)
        return app
    }

    private func start(_ app: XCUIApplication) {
        MorningUITestNavigation.tapButton("run.start", in: app, keepingOpening: true)
    }

    private func openingText(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let opening = app.staticTexts["morning.caption"]
        XCTAssertTrue(opening.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        let prepared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.sessionSnapshot(in: app)["opening"] == "choosing"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [prepared], timeout: 10), .completed,
                       "A manually started morning shows its greeting before the routine begins.", file: file, line: line)
        XCTAssertFalse(opening.label.isEmpty, file: file, line: line)
        return opening
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        for _ in 0..<10 where !element.exists || !element.isHittable {
            if element.exists, element.frame.midY < form.frame.midY { form.swipeDown() }
            else { form.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
