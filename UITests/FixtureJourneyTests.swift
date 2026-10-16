import XCTest

/// An opt-in audible device check. A passing callback check is not listener confirmation.
@MainActor
final class VoicePlaybackTests: XCTestCase {
    func testSpokenRoutineStepAdvancesOnlyAfterPlayback() throws {
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing a sample routine on the selected phone.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        let readAloud = app.switches["setup.readAloud"]
        XCTAssertTrue(readAloud.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.containing(.switch, identifier: "setup.readAloud").firstMatch
        for _ in 0..<4 where !readAloud.isHittable { sheet.swipeUp() }
        XCTAssertTrue(readAloud.isHittable)
        readAloud.tap()
        XCTAssertEqual(readAloud.value as? String, "1")
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.openRoutine(in: app)
        app.buttons["routine.approve"].tap()
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        // The first fixture step is a real spokenNote operation; the next is manual.
        // Enabling automatic progression dispatches the production speech executor.
        MorningUITestNavigation.openSettings(in: app)
        let handsFree = app.switches["setup.handsFree"]
        XCTAssertTrue(handsFree.waitForExistence(timeout: 5))
        for _ in 0..<8 where !handsFree.isHittable { app.swipeUp() }
        XCTAssertTrue(handsFree.isHittable)
        handsFree.tap()
        MorningUITestNavigation.selectTab("Morning", in: app)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.stepTitle(in: app) == "People and messages"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 30), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "synthetic-routine-spoken-step-completed-manual-step-waiting"
        shot.lifetime = .keepAlways
        add(shot)
        MorningUITestNavigation.tapButton("run.stop", in: app)
        // Does not establish listener audibility, calendar access or cross-app narration.
    }

    func testSystemVoicePreviewStartsAndFinishes() throws {
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing speech on the selected phone.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(UUID().uuidString)",
                               "-more.appLanguage", "en", "-AppleLanguages", "(en)"]
        defer { app.terminate() }
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        MorningUITestNavigation.tapButton("setup.voice", in: app)
        let preview = app.buttons["voice.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Speaking…"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready to speak"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed)
        XCTAssertFalse(app.buttons["voice.stopPreview"].exists)
        XCTAssertEqual(app.alerts.count, 0, "The synthetic voice sample does not request microphone access.")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "system-voice-preview-completed-listener-confirmation-separate"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// Exercises only Morning Operator's synthetic fixture, never an external inbox.
@MainActor
final class FixtureJourneyTests: XCTestCase {
    func testFirstUseCanStartLearningWithoutScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-workspace=\(UUID().uuidString)"]
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.revealControls(in: app)
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 10))
        XCTAssertTrue(begin.isHittable, "The first-use learning action must be available before any scroll.")
        attachScreenshot("first-use-learning-above-fold", from: app)
        begin.tap()
        XCTAssertTrue(app.navigationBars["Learn my morning"].waitForExistence(timeout: 5))
    }

    func testApproveRunPauseResumeAndStop() throws {
        let app = launchFixture()
        attachScreenshot("fixture-initial-timeline-before-approval", from: app)

        MorningUITestNavigation.openRoutine(in: app)
        tapButton("routine.approve", in: app)
        tapButton("run.start", in: app)
        assertState("running", in: app)
        let firstStep = stepTitle(in: app)
        XCTAssertFalse(firstStep.isEmpty)

        tapButton("run.next", in: app)
        let secondStep = stepTitle(in: app)
        XCTAssertFalse(secondStep.isEmpty)
        XCTAssertNotEqual(firstStep, secondStep, "Next must advance the actual fixture run.")

        tapButton("run.pause", in: app)
        assertState("paused", in: app)
        XCTAssertEqual(stepTitle(in: app), secondStep)
        tapButton("run.resume", in: app)
        assertState("running", in: app)
        XCTAssertEqual(stepTitle(in: app), secondStep, "Resuming must preserve the current item.")

        tapButton("run.controls", in: app)
        tapButton("run.stop", in: app)
        assertState("stopped", in: app)
        let restart = MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(restart.isHittable, "A stopped routine should offer an explicit restart.")
        attachScreenshot("fixture-stopped", from: app)
    }

    func testDreamIsSavedLocallyAndRetainedAcrossReviewNavigation() throws {
        let app = launchFixture()
        let dream = "I dreamed of a blue library above the sea."

        MorningUITestNavigation.reviewAction("review.thoughts", in: app)
        tapButton("capture.open", in: app)
        tapButton("capture.kind.dream", in: app)
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(dream)
        XCTAssertEqual(accessibleText(editor), dream)
        let dismissKeyboard = app.buttons["input.done"]
        if dismissKeyboard.waitForExistence(timeout: 2) { dismissKeyboard.tap() }

        let save = app.buttons["capture.save"]
        XCTAssertEqual(save.label, "Save my dream", "This fixture must use the local dream path, not a system write.")
        XCTAssertFalse(app.buttons["Add to Reminders"].exists)
        XCTAssertFalse(app.buttons["Add to Calendar"].exists)
        tapButton("capture.save", in: app)
        waitFor(editor, exists: false)
        XCTAssertTrue(app.staticTexts[dream].waitForExistence(timeout: 5))

        // Filtering verifies that the capture was saved as a dream, not merely echoed in the editor.
        tapButton("capture.filter.thought", in: app)
        waitFor(app.staticTexts[dream], exists: false)
        tapButton("capture.filter.dream", in: app)
        XCTAssertTrue(app.staticTexts[dream].waitForExistence(timeout: 5))
        selectTab("Morning", in: app)
        // Review reopens at its first screen, so return to Saved thoughts to look.
        MorningUITestNavigation.reviewAction("review.thoughts", in: app)
        XCTAssertTrue(app.staticTexts[dream].waitForExistence(timeout: 5), "The saved dream must survive leaving its screen.")
        XCTAssertEqual(app.alerts.count, 0, "Local capture must not request external permissions.")
        attachScreenshot("fixture-local-dream", from: app)
    }

    func testReviewPeriodAndEmptyDayDoNotInventMorningHistory() throws {
        let app = launchFixture()
        selectTab("Review", in: app)
        let period = app.buttons["review.period"]
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        let currentPeriod = period.label
        XCTAssertFalse(app.staticTexts["review.average"].exists, "A sample plan must not create a measured average.")
        XCTAssertFalse(app.buttons["review.nextWeek"].isEnabled)
        tapButton("review.previousWeek", in: app)
        XCTAssertNotEqual(period.label, currentPeriod)
        XCTAssertTrue(app.buttons["review.nextWeek"].isEnabled)
        XCTAssertFalse(app.staticTexts["review.average"].exists)
        tapButton("review.nextWeek", in: app)
        XCTAssertEqual(period.label, currentPeriod)
        XCTAssertFalse(app.buttons["review.nextWeek"].isEnabled)
        tapButton("review.period", in: app)

        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let dateKey = DateFormatter()
        dateKey.calendar = Calendar(identifier: .gregorian)
        dateKey.locale = Locale(identifier: "en_US_POSIX")
        dateKey.timeZone = .current
        dateKey.dateFormat = "yyyy-MM-dd"
        if !app.buttons["review.day.\(dateKey.string(from: yesterday))"].waitForExistence(timeout: 3) {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "synthetic-review-days-accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        tapButton("review.day.\(dateKey.string(from: yesterday))", in: app)
        XCTAssertTrue(app.staticTexts["No routine saved for this day."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A missing run stays unknown. It isn't counted as a zero-minute morning."].exists)
        XCTAssertFalse(app.buttons["routine.approve"].exists, "An empty past day must not show today's draft as history.")
        XCTAssertFalse(app.buttons["run.start"].exists)
        XCTAssertFalse(app.buttons["routine.step.0"].exists)
        XCTAssertFalse(app.staticTexts["Active routine time"].exists)
        attachScreenshot("fixture-review-empty-history-day", from: app)
        selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", without: "run.start", in: app,
                                                    "The current draft must remain intact outside history.")
        selectTab("Review", in: app)
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5), "History must reopen the period, not a previously pushed day detail.")
        XCTAssertFalse(app.staticTexts["No routine saved for this day."].exists)
    }

    func testEditedDraftRestoresApprovedRoutineAndRunningSessionRecoversAfterRelaunch() throws {
        let app = launchFixture(workspaceID: UUID())
        MorningUITestNavigation.openRoutine(in: app)
        tapButton("routine.approve", in: app)
        MorningUITestNavigation.assertMorningAction("run.start", in: app)
        MorningUITestNavigation.openRoutine(in: app)
        tapButton("routine.step.0", in: app)

        let name = app.textFields["Step name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let originalName = accessibleText(name)
        XCTAssertFalse(originalName.isEmpty)
        name.tap()
        // Insert a harmless marker instead of relying on localized selection menus.
        name.typeText(" test revision")
        let editedName = accessibleText(name)
        XCTAssertNotEqual(editedName, originalName)
        XCTAssertTrue(editedName.contains("test revision"))
        tapButton("Save", in: app)
        waitFor(name, exists: false)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.start"].exists, "Editing an approved version creates a draft that cannot start yet.")
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(editedName))
        MorningUITestNavigation.closeRoutine(in: app)
        selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", without: "run.start", in: app,
                                                    "An edited draft must open its editor without starting from Morning.")

        // Reuse only this test's UUID under the application's temporary fixture directory.
        // Relaunch must load the existing draft and retained approved version rather than reseed.
        app.terminate()
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.openRoutine(in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(editedName), "The edited draft must survive relaunch.")
        XCTAssertTrue(app.buttons["routine.restore"].exists, "The previous approved version must also survive relaunch.")
        attachScreenshot("fixture-persisted-draft-before-restore", from: app)
        tapButton("routine.restore", in: app)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(originalName))
        XCTAssertFalse(app.buttons["routine.step.0"].label.contains("test revision"))
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.closeRoutine(in: app)
        selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("run.start", in: app)

        tapButton("run.start", in: app)
        tapButton("run.next", in: app)
        assertState("running", in: app)
        let interruptedStep = stepTitle(in: app)
        XCTAssertFalse(interruptedStep.isEmpty)
        app.terminate()
        MorningUITestNavigation.launch(app)
        assertState("paused", in: app)
        XCTAssertEqual(stepTitle(in: app), interruptedStep, "Reopening must preserve the current step and require explicit continuation.")
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertTrue(app.buttons["morning.playback"].isHittable)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Continue")
        attachScreenshot("fixture-recovered-paused-session", from: app)
        tapButton("run.resume", in: app)
        assertState("running", in: app)
        XCTAssertEqual(stepTitle(in: app), interruptedStep)
        tapButton("run.controls", in: app)
        tapButton("run.stop", in: app)
        assertState("stopped", in: app)
    }

    func testImportedObservationPersistsAndStaysClearedAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let expected = "[Synthetic UI-test observation]\nI check my calendar, drink water, and enjoy ten minutes of chess."
        app.launchArguments = ["--ui-testing", "--fixture-mode",
                               "--ui-testing-workspace=\(UUID().uuidString)",
                               "--ui-testing-import-observation"]
        MorningUITestNavigation.launch(app)

        // The test hook imports a synthetic UTF-8 file while Learn is presented,
        // through the real async importer and the already-mounted observation editor.
        // This checks observation persistence; it does not exercise screen recording.
        openLearnAndAssertNotes(expected, in: app)
        attachScreenshot("synthetic-import-visible-notes", from: app)
        closeLearn(in: app)
        openLearnAndAssertNotes(expected, in: app)
        closeLearn(in: app)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-import-observation" }
        MorningUITestNavigation.launch(app)
        openLearnAndAssertNotes(expected, in: app)
        attachScreenshot("synthetic-import-restored-without-reimport", from: app)

        let editor = app.textViews["learn.notes"]
        editor.tap()
        editor.typeText(" I also make tea.")
        let corrected = try XCTUnwrap(editor.value as? String)
        XCTAssertNotEqual(corrected, expected)
        XCTAssertTrue(corrected.contains("I also make tea."))
        closeLearn(in: app)
        app.terminate()
        MorningUITestNavigation.launch(app)
        openLearnAndAssertNotes(corrected, in: app)
        attachScreenshot("corrected-observation-restored-after-relaunch", from: app)

        let clear = app.buttons["learn.clear"]
        let learnScroll = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        for _ in 0..<3 where !clear.isHittable { learnScroll.swipeUp() }
        XCTAssertTrue(clear.isHittable)
        XCTAssertTrue(clear.isEnabled, "The async import must finish before clearing its saved text.")
        clear.tap()
        assertNotes("", in: app)
        XCTAssertFalse(clear.exists)
        app.terminate()
        MorningUITestNavigation.launch(app)
        openLearnAndAssertNotes("", in: app)
        XCTAssertFalse(app.buttons["learn.clear"].exists, "Cleared text must not return from disk or a test reimport.")
        attachScreenshot("synthetic-import-cleared-after-relaunch", from: app)
    }

    private func openLearnAndAssertNotes(_ expected: String, in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let editor = app.textViews["learn.notes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let learnScroll = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        for _ in 0..<3 where !editor.isHittable { learnScroll.swipeUp() }
        XCTAssertTrue(editor.isHittable, "The extracted observation must be visible in Learn.")
        assertNotes(expected, in: app)
    }

    private func assertNotes(_ expected: String, in app: XCUIApplication) {
        let editor = app.textViews["learn.notes"]
        // UIKit may expose an empty editor as nil rather than the empty string.
        // Nonempty evidence still requires an exact match; disappearance of Clear
        // and the subsequent relaunch also verify the underlying saved state.
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (editor.value as? String ?? "") == expected
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "Unexpected observation editor value: \(String(describing: editor.value))")
    }

    private func closeLearn(in app: XCUIApplication) {
        let done = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        waitFor(app.textViews["learn.notes"], exists: false)
    }

    private func launchFixture(workspaceID: UUID? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Each launch uses an isolated temporary workspace and disables speech/automatic progression.
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        if let workspaceID { app.launchArguments.append("--ui-testing-workspace=\(workspaceID.uuidString)") }
        MorningUITestNavigation.launch(app)
        return app
    }

    private func selectTab(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        MorningUITestNavigation.selectTab(title, in: app, file: file, line: line)
    }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitFor(_ element: XCUIElement, exists: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == %@", NSNumber(value: exists)), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        MorningUITestNavigation.tapButton(identifier, in: app, file: file, line: line)
    }

    private func assertState(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        MorningUITestNavigation.assertSession(state: expected, in: app, file: file, line: line)
    }

    private func stepTitle(in app: XCUIApplication) -> String {
        MorningUITestNavigation.stepTitle(in: app)
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }
}

/// Shared navigation for Home playback and the destinations inside Settings.
/// The historical method name keeps callers consistent without relying on a tab bar.
@MainActor
enum MorningUITestNavigation {
    /// Fixture tests choose their interface language independently of earlier tests.
    /// Ordinary app launches and tests that explicitly set a language keep their choice.
    static func launch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if app.launchArguments.contains("--ui-testing") {
            var arguments = app.launchArguments
            if !arguments.contains(where: { $0.hasPrefix("--ui-testing-workspace=") }) {
                arguments.append("--ui-testing-workspace=\(UUID().uuidString)")
            }
            if !arguments.contains("-more.appLanguage") {
                let french = arguments.firstIndex(of: "-AppleLanguages").map { index in
                    arguments.indices.contains(index + 1) && arguments[index + 1].contains("fr")
                } ?? false
                arguments += ["-more.appLanguage", french ? "fr" : "en"]
            }
            if !arguments.contains("-AppleLanguages") {
                arguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            }
            app.launchArguments = arguments
        }
        app.launch()
        if let argument = app.launchArguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") }) {
            let workspace = String(argument.dropFirst("--ui-testing-workspace=".count))
            let marker = app.staticTexts["qa.testWorkspace"]
            // Xcode can prelaunch the first target without its test arguments.
            // Confirm isolation before touching any state, then relaunch once if needed.
            if !marker.waitForExistence(timeout: 5) || marker.value as? String != workspace {
                app.terminate()
                app.launch()
            }
            XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
            XCTAssertEqual(marker.value as? String, workspace, app.debugDescription, file: file, line: line)
        }
    }

    /// Weather starts from the authorized current position. City-search journeys
    /// choose the manual source explicitly, in either shipped interface language.
    static func chooseManualWeatherCity(in app: XCUIApplication,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let source = app.descendants(matching: .any).matching(identifier: "briefing.locationSource").firstMatch
        for _ in 0..<12 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable, app.debugDescription, file: file, line: line)
        source.tap()
        let english = app.buttons["Choose a city"].firstMatch
        let french = app.buttons["Choisir une ville"].firstMatch
        let choice = english.waitForExistence(timeout: 2) ? english : french
        XCTAssertTrue(choice.waitForExistence(timeout: 3), app.debugDescription, file: file, line: line)
        choice.tap()
    }

    static func isHome(_ app: XCUIApplication) -> Bool {
        app.buttons["morning.actions"].exists || app.scrollViews["morning.captions"].exists
    }

    static func selectTab(_ title: String, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) {
        switch title {
        case "Morning":
            for _ in 0..<10 {
                if isHome(app) { return }
                let closeDetails = app.buttons["morning.closeDetails"]
                let closeDestination = app.buttons["destination.close"]
                let back = app.navigationBars.buttons.element(boundBy: 0)
                if closeDetails.exists { closeDetails.tap() }
                else if closeDestination.exists { closeDestination.tap() }
                else if back.waitForExistence(timeout: 2) { back.tap() }
                else { break }
            }
            XCTAssertTrue(isHome(app), "Expected the actual Home landscape or reading surface.\n\(app.debugDescription)", file: file, line: line)
        case "Review":
            if app.scrollViews["review.week"].exists { return }
            openSettings(in: app, file: file, line: line)
            tapVisible("setup.history", in: app, file: file, line: line)
            XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        default:
            XCTFail("Unsupported destination: \(title)", file: file, line: line)
        }
    }

    static func revealControls(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        selectTab("Morning", in: app, file: file, line: line)
        let settings = app.buttons["morning.settings"]
        for _ in 0..<3 {
            if settings.exists && settings.isHittable { return }
            let captions = app.scrollViews["morning.captions"]
            let surface = captions.exists ? captions : app.buttons["morning.actions"]
            XCTAssertTrue(surface.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
            if settings.waitForExistence(timeout: 2), settings.isHittable { return }
        }
        XCTAssertTrue(settings.isHittable, "Home must reveal playback and Settings.", file: file, line: line)
    }

    static func openSettings(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if app.descendants(matching: .any).matching(identifier: "settings.appearance").firstMatch.exists { return }
        revealControls(in: app, file: file, line: line)
        app.buttons["morning.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings.appearance").firstMatch
            .waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }

    static func becomesHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        if element.isHittable { return true }
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        return XCTWaiter.wait(for: [expected], timeout: timeout) == .completed
    }

    @discardableResult
    static func revealMorningAction(_ identifier: String, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        switch identifier {
        case "run.start", "morning.begin":
            revealControls(in: app, file: file, line: line)
            return app.buttons["morning.begin"]
        case "morning.review", "morning.reviewDraft":
            openSettings(in: app, file: file, line: line)
            return app.buttons["setup.routine"]
        case "morning.learn":
            selectTab("Review", in: app, file: file, line: line)
            return app.buttons["review.learn"]
        case "morning.settings":
            revealControls(in: app, file: file, line: line)
            return app.buttons[identifier]
        default:
            openSettings(in: app, file: file, line: line)
            return app.buttons[identifier]
        }
    }

    static func assertMorningAction(_ identifier: String, without absent: String? = nil, in app: XCUIApplication,
                                    timeout: TimeInterval = 10, _ message: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        if identifier == "morning.reviewDraft" || absent == "run.start" {
            // Play opens an unapproved editor, rather than creating a session.
            revealControls(in: app, file: file, line: line)
            app.buttons["morning.begin"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch
                .waitForExistence(timeout: timeout), message, file: file, line: line)
            XCTAssertTrue(app.buttons["routine.approve"].exists, message, file: file, line: line)
            closeRoutine(in: app, file: file, line: line)
            selectTab("Morning", in: app, file: file, line: line)
            XCTAssertFalse(app.scrollViews["morning.captions"].exists, "A draft must not start. \(message)", file: file, line: line)
            return
        }
        if identifier == "run.start" {
            // Play is also offered for drafts; verify approval before claiming readiness.
            openRoutine(in: app, file: file, line: line)
            XCTAssertTrue(app.buttons["routine.step.0"].waitForExistence(timeout: timeout), message, file: file, line: line)
            XCTAssertFalse(app.buttons["routine.approve"].exists, "Starting requires an approved routine. \(message)", file: file, line: line)
            closeRoutine(in: app, file: file, line: line)
        }
        let action = revealMorningAction(identifier, in: app, file: file, line: line)
        XCTAssertTrue(action.waitForExistence(timeout: timeout) && becomesHittable(action), message, file: file, line: line)
        closeMorningActions(in: app, file: file, line: line)
    }

    static func closeMorningActions(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        selectTab("Morning", in: app, file: file, line: line)
        if app.buttons["morning.settings"].exists {
            let captions = app.scrollViews["morning.captions"]
            let surface = captions.exists ? captions : app.buttons["morning.actions"]
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
        }
    }

    static func reviewAction(_ identifier: String, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        if identifier == "navigation.setup" { openSettings(in: app, file: file, line: line); return }
        selectTab("Review", in: app, file: file, line: line)
        tapVisible(identifier, in: app, file: file, line: line)
    }

    static func openRoutine(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.exists { return }
        openSettings(in: app, file: file, line: line)
        tapVisible("setup.routine", in: app, file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch
            .waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }

    static func closeRoutine(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let editor = app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), file: file, line: line)
        let done = app.buttons["destination.close"]
        if done.exists { done.tap() }
        else {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5), file: file, line: line)
            back.tap()
        }
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    static func tapButton(_ identifier: String, in app: XCUIApplication, keepingOpening: Bool = false,
                          file: StaticString = #filePath, line: UInt = #line) {
        switch identifier {
        case "run.start":
            revealControls(in: app, file: file, line: line)
            tapVisible("morning.begin", in: app, file: file, line: line)
            if !keepingOpening { chooseRoutineAtOpening(in: app, file: file, line: line) }
            return
        case "run.controls": openSettings(in: app, file: file, line: line); return
        case "run.pause", "run.resume", "run.next", "run.stop":
            openSettings(in: app, file: file, line: line)
            let actual = ["run.pause": "morning.playback", "run.resume": "morning.playback",
                          "run.next": "morning.next", "run.stop": "morning.stop"][identifier]!
            tapVisible(actual, in: app, file: file, line: line)
            selectTab("Morning", in: app, file: file, line: line)
            return
        case "morning.date", "morning.review": selectTab("Review", in: app, file: file, line: line); return
        case "morning.reviewDraft": openRoutine(in: app, file: file, line: line); return
        case "morning.learn": reviewAction("review.learn", in: app, file: file, line: line); return
        case "morning.settings", "navigation.setup": openSettings(in: app, file: file, line: line); return
        case "morning.begin": revealControls(in: app, file: file, line: line)
        case "morning.next", "morning.extend", "morning.details", "morning.stop":
            if !app.buttons[identifier].exists { openSettings(in: app, file: file, line: line) }
        default: break
        }
        tapVisible(identifier, in: app, file: file, line: line)
    }

    private static func tapVisible(_ identifier: String, in app: XCUIApplication,
                                   file: StaticString, line: UInt) {
        let button = app.buttons[identifier]
        for _ in 0..<10 {
            if button.exists {
                let frame = button.frame
                let collection = app.collectionViews.containing(.button, identifier: identifier).firstMatch
                let table = app.tables.containing(.button, identifier: identifier).firstMatch
                let scroll = app.scrollViews.containing(.button, identifier: identifier).firstMatch
                let container: XCUIElement = collection.exists ? collection : (table.exists ? table : scroll)
                var viewport = (container.exists ? container.frame : app.frame).intersection(app.frame)
                if container.exists {
                    let navigation = app.navigationBars.firstMatch
                    let top = navigation.exists ? max(viewport.minY, navigation.frame.maxY) : viewport.minY
                    let selectionSummary = app.staticTexts["observations.selectionSummary"]
                    // List AX frames include the pinned selection footer. Its covered rows
                    // can report hittable even though a tap reaches the footer instead.
                    let bottom = selectionSummary.exists
                        ? min(viewport.maxY, selectionSummary.frame.minY - 20) : viewport.maxY
                    viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
                }
                if !frame.isEmpty, viewport.contains(CGPoint(x: frame.midX, y: frame.midY)), button.isHittable { break }
                if container.exists {
                    let distance = viewport.midY - frame.midY
                    let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: distance > 0 ? 0.2 : 0.8))
                    let step = min(viewport.height * 0.6, max(-viewport.height * 0.6, distance))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: step)),
                                withVelocity: .slow, thenHoldForDuration: 0.2)
                }
            } else {
                let container = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
                if container.exists { container.swipeUp() }
                else if button.waitForExistence(timeout: 2) { continue }
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing control: \(identifier)\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(button.isHittable, "Control is not touchable: \(identifier)", file: file, line: line)
        button.tap()
    }

    static func sessionSnapshot(in app: XCUIApplication) -> [String: String] {
        let caption = app.staticTexts["morning.caption"]
        let value = (caption.exists ? caption.value : app.buttons["morning.actions"].value) as? String ?? ""
        guard let json = value.components(separatedBy: "\n").last?.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: json) as? [String: String] else { return [:] }
        return fields
    }

    static func stepTitle(in app: XCUIApplication) -> String { sessionSnapshot(in: app)["step"] ?? "" }

    static func assertSession(state: String, step: String? = nil, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        selectTab("Morning", in: app, file: file, line: line)
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let snapshot = sessionSnapshot(in: app)
            return snapshot["state"] == state && (step == nil || snapshot["step"] == step)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed,
                       "Expected \(state), step \(step ?? "any"); actual \(sessionSnapshot(in: app))", file: file, line: line)
    }

    static func chooseRoutineAtOpening(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        selectTab("Morning", in: app, file: file, line: line)
        let captions = app.scrollViews["morning.captions"]
        XCTAssertTrue(captions.waitForExistence(timeout: 15), app.debugDescription, file: file, line: line)
        let prepared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            sessionSnapshot(in: app)["opening"] != "preparing"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [prepared], timeout: 15), .completed, file: file, line: line)
        if sessionSnapshot(in: app)["opening"] != "none" {
            revealControls(in: app, file: file, line: line)
            tapVisible("morning.playback", in: app, file: file, line: line)
        }
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            sessionSnapshot(in: app)["opening"] == "none"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 10), .completed, file: file, line: line)
    }

}

/// Lifecycle tests accept the human state in either supported app language.
/// LocalizationJourneyTests separately enforce the selected language.
enum MorningUITestState {
    static func labels(for state: String) -> [String] {
        switch state {
        case "ready": ["Ready", "Prêt"]
        case "running": ["In progress", "En cours"]
        case "paused": ["Paused", "En pause"]
        case "completed": ["Complete", "Terminé"]
        case "stopped": ["Stopped", "Arrêté"]
        default: [state]
        }
    }
}
