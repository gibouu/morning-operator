import XCTest

/// The opening of a started morning (issue #28) in an isolated fixture workspace. No
/// source is connected here, so the opening is the greeting and the routine/stop choice;
/// the sourced opening is in `MorningBriefingTests`. These checks read what the app
/// requested from its speech coordinator, never audio: they do not establish what a
/// listener hears, on a phone or on a speaker.
@MainActor
final class MorningOpeningUITests: XCTestCase {
    func testStartShowsTheOpeningAndRoutineReachesTheFirstStep() {
        let app = launch()
        start(app)
        let opening = openingText(in: app)
        XCTAssertFalse(opening.label.isEmpty)
        XCTAssertFalse(app.buttons["opening.brief"].exists, "With no source connected there is no recap to offer.")
        for identifier in ["opening.routine", "opening.stop"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists, identifier)
            XCTAssertTrue(control.isHittable, identifier)
            XCTAssertFalse(control.label.isEmpty, identifier)
        }
        // Issue #99: the first moment's "Now" card waits with the routine. The run controls stay.
        XCTAssertFalse(app.staticTexts["run.state"].exists, "The Now card is hidden while the opening waits.")
        XCTAssertFalse(app.staticTexts["run.step"].exists, "The Now card is hidden while the opening waits.")
        XCTAssertTrue(app.buttons["run.pause"].exists)
        attach("opening-no-source-connected", app)
        // A normal morning waits for the tap: nothing moves on its own.
        let leaves = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["opening.routine"])
        leaves.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [leaves], timeout: 4), .completed, "Without Hands free the opening waits for a choice.")
        XCTAssertFalse(app.staticTexts["run.step"].exists)

        app.buttons["opening.routine"].tap()
        XCTAssertTrue(opening.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["opening.routine"].exists)
        XCTAssertEqual(app.staticTexts["run.state"].value as? String, "running")
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
        XCTAssertEqual(app.staticTexts["run.step"].value as? String, "routine started 1")
        XCTAssertTrue(app.buttons["run.pause"].exists)
        attach("opening-routine-started-now-card", app)
    }

    /// Issue #99, with spoken guidance off: a hands-free morning does not wait for a tap.
    /// The spoken case, with a recap on offer, is in `MorningBriefingTests`.
    func testHandsFreeStartWithoutSpeechReachesTheFirstStepWithoutATap() {
        let app = launch(extra: ["--ui-testing-hands-free"])
        start(app)
        let step = app.staticTexts["run.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 15), "A hands-free morning starts its routine on its own.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["opening.text"].exists)
        XCTAssertFalse(app.buttons["opening.routine"].exists)
        XCTAssertFalse(app.staticTexts["opening.briefText"].exists)
        XCTAssertEqual(step.label, "Your morning")
        XCTAssertEqual(step.value as? String, "routine started 1")
        XCTAssertTrue(app.buttons["run.pause"].exists)
        MorningUITestNavigation.tapButton("run.controls", in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    func testStopAtTheOpeningEndsTheMorning() {
        let app = launch()
        start(app)
        let opening = openingText(in: app)
        app.buttons["opening.stop"].tap()
        XCTAssertTrue(opening.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.pause"].exists)
        XCTAssertFalse(app.buttons["run.resume"].exists)
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].isHittable, "A stopped morning offers an explicit restart.")
    }

    func testOpeningDoesNotReturnAfterRelaunchOrWhenTheMorningContinues() {
        let app = launch()
        start(app)
        _ = openingText(in: app)

        app.terminate()
        app.launch()
        // The same session comes back paused, and the opening does not come back with it.
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["opening.text"].exists)
        XCTAssertFalse(app.buttons["opening.routine"].exists)
        MorningUITestNavigation.tapButton("run.resume", in: app)
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["opening.text"].exists)
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
    }

    func testSpokenGuidanceOffRequestsNoSpeech() {
        let app = launch()
        start(app)
        let opening = openingText(in: app)
        XCTAssertEqual(opening.value as? String, "silent")
        // The speech coordinator's own state, where the voice settings show it.
        MorningUITestNavigation.tapButton("morning.settings", in: app)
        let status = app.staticTexts["setup.speechStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "idle")
    }

    /// Requests real synthesis. Runs on a simulator; on a phone it needs the audible opt-in.
    func testSpokenGuidanceOnRequestsTheOpeningOnceAndNotAfterRelaunch() throws {
        #if !targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing speech on the selected phone.")
        }
        #endif
        let app = launch(approved: false)
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        let readAloud = app.switches["setup.readAloud"]
        XCTAssertTrue(readAloud.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.containing(.switch, identifier: "setup.readAloud").firstMatch
        for _ in 0..<4 where !readAloud.isHittable { sheet.swipeUp() }
        XCTAssertTrue(readAloud.isHittable)
        readAloud.tap()
        XCTAssertEqual(readAloud.value as? String, "1")
        app.navigationBars["Settings"].buttons["Done"].tap()
        MorningUITestNavigation.openRoutine(in: app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)

        start(app)
        let opening = openingText(in: app)
        XCTAssertEqual(opening.value as? String, "speech requested")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["opening.text"].exists, "A relaunch must not greet the same morning again.")
        MorningUITestNavigation.tapButton("run.controls", in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    /// Pictures for a person to look at: English and French, light and dark, and the largest text size.
    /// Nothing about wording or layout is asserted here.
    func testOpeningScreenshotsInEnglishFrenchAndLargestText() {
        for (name, arguments) in [
            ("opening-english", ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]),
            ("opening-french", ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]),
            ("opening-english-dark", ["--dark-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]),
            ("opening-french-dark", ["--dark-preview", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]),
        ] {
            let app = launch(extra: arguments)
            start(app)
            _ = openingText(in: app)
            attach(name, app)
            app.terminate()
        }
        for (name, language) in [("opening-largest-text-english", "en"), ("opening-largest-text-french", "fr")] {
            let app = launch(extra: ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US",
                                     "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
            let scroll = app.scrollViews["morning.accessibleScroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 10), "This picture requires the largest accessibility text size.")
            MorningUITestNavigation.revealMorningAction("run.start", in: app)
            let play = app.buttons["run.start"]
            for _ in 0..<8 where !play.isHittable { scroll.swipeUp() }
            start(app)
            _ = openingText(in: app)
            for _ in 0..<4 { scroll.swipeDown() }
            attach("\(name)-top", app)
            scroll.swipeUp()
            attach("\(name)-after-one-swipe", app)
            scroll.swipeUp()
            attach("\(name)-after-two-swipes", app)
            app.terminate()
        }
    }

    private func launch(approved: Bool = true, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // An isolated temporary workspace; the fixture keeps speech and hands-free off
        // unless `extra` asks for them.
        // The light palette unless a test asks for the dark one.
        app.launchArguments = ["--ui-testing", "--fixture-mode"] + (extra.contains("--dark-preview") ? [] : ["--light-preview"])
            + ["--ui-testing-workspace=\(UUID().uuidString)"]
            + (approved ? ["--ui-testing-approved"] : []) + extra
        app.launch()
        return app
    }

    /// Play, then the explicit Start, leaving the opening on screen.
    private func start(_ app: XCUIApplication) {
        MorningUITestNavigation.tapButton("run.start", in: app, keepingOpening: true)
    }

    private func openingText(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let opening = app.staticTexts["opening.text"]
        XCTAssertTrue(opening.waitForExistence(timeout: 10),
                      "A started morning must show its opening.\n\(app.debugDescription)", file: file, line: line)
        return opening
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
