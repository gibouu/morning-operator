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
        app.navigationBars["Settings"].buttons["Done"].tap()
        MorningUITestNavigation.openRoutine(in: app)
        app.buttons["routine.approve"].tap()
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
        MorningUITestNavigation.tapButton("run.start", in: app)
        let step = app.staticTexts["run.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(step.label, "Your morning")
        // The first fixture step is a real spokenNote operation; the next is manual.
        // Enabling automatic progression dispatches the production speech executor.
        app.buttons["run.controls"].tap()
        // SwiftUI exposes a menu Toggle as a menu button on iOS and as a switch
        // on some test runtimes. Both represent the same visible Hands free action.
        let handsFree = app.switches["Hands free"].exists ? app.switches["Hands free"] : app.buttons["Hands free"]
        XCTAssertTrue(handsFree.waitForExistence(timeout: 5))
        handsFree.tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "People and messages"), object: step)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 30), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "synthetic-routine-spoken-step-completed-manual-step-waiting"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["run.controls"].tap()
        app.buttons["run.stop"].tap()
        // Does not establish listener audibility, calendar access or cross-app narration.
    }

    func testSystemVoicePreviewStartsAndFinishes() throws {
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing speech on the selected phone.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        let preview = app.buttons["setup.testVoice"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.containing(.button, identifier: "setup.testVoice").firstMatch
        for _ in 0..<4 where !preview.isHittable { sheet.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        let status = app.staticTexts["setup.speechStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "speaking"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND label == %@", "idle", "Ready to speak"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed)
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
        let begin = app.buttons["learn.begin"]
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
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].exists, "A stopped routine should offer an explicit restart.")
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
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5), "The current draft must remain intact outside history.")
        app.buttons["morning.closeActions"].tap()
        selectTab("Review", in: app)
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5), "History must reopen the period, not a previously pushed day detail.")
        XCTAssertFalse(app.staticTexts["No routine saved for this day."].exists)
    }

    func testEditedDraftRestoresApprovedRoutineAndRunningSessionRecoversAfterRelaunch() throws {
        let app = launchFixture(workspaceID: UUID())
        MorningUITestNavigation.openRoutine(in: app)
        tapButton("routine.approve", in: app)
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
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
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.start"].exists, "An edited draft must not start from Morning.")

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
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))

        tapButton("run.start", in: app)
        tapButton("run.next", in: app)
        assertState("running", in: app)
        let interruptedStep = stepTitle(in: app)
        XCTAssertFalse(interruptedStep.isEmpty)
        app.terminate()
        MorningUITestNavigation.launch(app)
        assertState("paused", in: app)
        XCTAssertEqual(stepTitle(in: app), interruptedStep, "Reopening must preserve the current step and require explicit continuation.")
        XCTAssertTrue(app.buttons["run.resume"].exists)
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
        let done = app.navigationBars["Learn my morning"].buttons["Done"]
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
        if expected == "stopped" {
            MorningUITestNavigation.revealMorningAction("run.start", in: app, file: file, line: line)
            XCTAssertTrue(app.buttons["run.start"].isHittable, file: file, line: line)
            XCTAssertFalse(app.buttons["run.pause"].exists, file: file, line: line)
            return
        }
        let state = app.staticTexts["run.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5), file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while !MorningUITestState.labels(for: expected).contains(accessibleText(state)), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(MorningUITestState.labels(for: expected).contains(accessibleText(state)), accessibleText(state), file: file, line: line)
    }

    private func stepTitle(in app: XCUIApplication) -> String {
        let step = app.staticTexts["run.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        // A SwiftUI Text uses its accessibility label; its value can be an empty
        // string even when the title is visible. Values belong to the state/editor.
        return step.label
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }
}

/// Shared navigation for Morning's sunrise actions and the Review home control.
/// The historical method name keeps callers consistent without relying on a tab bar.
@MainActor
enum MorningUITestNavigation {
    /// Fixture tests choose their interface language independently of earlier tests.
    /// Ordinary app launches and tests that explicitly set a language keep their choice.
    static func launch(_ app: XCUIApplication) {
        if app.launchArguments.contains("--ui-testing") {
            var arguments = app.launchArguments
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
    }

    private enum IsolatedLaunchError: Error { case invalidArguments, missingWorkspace, wrongWorkspace }

    /// Only explicitly isolated journeys may retry a missing launch marker.
    /// A present, incorrect workspace is never repaired or retried.
    static func requireIsolatedWorkspace(_ expected: String, in app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
        let arguments = app.launchArguments
        let workspaces = arguments.filter { $0.hasPrefix("--ui-testing-workspace=") }
        guard arguments.contains("--ui-testing"), arguments.contains("--fixture-mode"),
              UUID(uuidString: expected) != nil, workspaces == ["--ui-testing-workspace=" + expected] else {
            XCTFail("The private journey must request its one exact isolated workspace.", file: file, line: line)
            throw IsolatedLaunchError.invalidArguments
        }
        func record(_ name: String) {
            XCTContext.runActivity(named: name) { activity in
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = name + "-screenshot"; screenshot.lifetime = .keepAlways; activity.add(screenshot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = name + "-accessibility"; hierarchy.lifetime = .keepAlways; activity.add(hierarchy)
            }
        }
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 10) {
            record("Invalid isolated launch - workspace absent after ten seconds")
            // Capturing diagnostics can take time. A marker that appeared in
            // that interval must be checked, never hidden by another launch.
            if !marker.exists {
                try XCTContext.runActivity(named: "Isolated launch retry 1 of 1 - exact original arguments") { _ in
                    app.terminate()
                    guard app.launchArguments == arguments else {
                        XCTFail("A launch retry must retain the exact original arguments.", file: file, line: line)
                        throw IsolatedLaunchError.invalidArguments
                    }
                    app.launch()
                }
            }
        }
        guard marker.waitForExistence(timeout: 10) else {
            record("Isolated launch refused - workspace still absent after one retry")
            XCTFail("The expected workspace marker must exist before any gesture.", file: file, line: line)
            throw IsolatedLaunchError.missingWorkspace
        }
        guard marker.value as? String == expected else {
            record("Isolated launch refused - wrong workspace - no retry")
            XCTFail("The present workspace must equal the requested UUID; no retry is allowed.", file: file, line: line)
            throw IsolatedLaunchError.wrongWorkspace
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

    static func selectTab(_ title: String, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) {
        switch title {
        case "Morning":
            // Settings, History and their details are pushed on Home. Follow
            // the same native Back route as a person, rather than an old tab/date.
            for _ in 0..<8 where app.navigationBars.count > 0 {
                let back = app.navigationBars.buttons.element(boundBy: 0)
                guard back.exists, becomesHittable(back) else {
                    XCTFail("The visible navigation must offer Back.\n\(app.debugDescription)", file: file, line: line)
                    return
                }
                back.tap()
            }
            let closeActions = app.buttons["morning.closeActions"]
            if closeActions.exists, closeActions.isHittable { closeActions.tap() }
            let home = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons["morning.actions"].exists || app.scrollViews["morning.captions"].exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [home], timeout: 5), .completed,
                           "Home must show its landscape or current passage.\n\(app.debugDescription)", file: file, line: line)
        case "Review":
            if app.buttons["review.period"].exists, app.buttons["review.period"].isHittable { return }
            selectTab("Morning", in: app, file: file, line: line)
            tapButton("morning.settings", in: app, file: file, line: line)
            tapButton("setup.history", in: app, file: file, line: line)
            XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5),
                          "Settings must open morning History.\n\(app.debugDescription)", file: file, line: line)
        default:
            XCTFail("Unsupported destination: \(title)", file: file, line: line)
        }
    }

    /// Right after launch the home screen can still be settling, so an element on screen
    /// can read as not hittable for a moment. Waits briefly instead of judging once.
    static func becomesHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        if element.isHittable { return true }
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                                 object: element)
        return XCTWaiter.wait(for: [hittable], timeout: timeout) == .completed
    }

    /// Opens the visible sunrise menu only when the requested action is hidden.
    static func revealMorningAction(_ identifier: String, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let action = app.buttons[identifier]
        if action.exists, action.isHittable { return }
        let sunrise = app.buttons["morning.actions"]
        if sunrise.exists {
            XCTAssertTrue(becomesHittable(sunrise), app.debugDescription, file: file, line: line)
            sunrise.tap()
        } else if app.scrollViews["morning.captions"].exists {
            let passage = app.scrollViews["morning.captions"]
            XCTAssertTrue(becomesHittable(passage), app.debugDescription, file: file, line: line)
            passage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        } else if !app.buttons["morning.closeActions"].exists {
            XCTAssertTrue(sunrise.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
            XCTAssertTrue(sunrise.isHittable, app.debugDescription, file: file, line: line)
            sunrise.tap()
        }
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing morning action: \(identifier)\n\(app.debugDescription)", file: file, line: line)
        let horizontal = app.scrollViews["morning.actionsScroll"]
        for _ in 0..<4 where !action.isHittable && horizontal.exists {
            if action.frame.midX < horizontal.frame.midX { horizontal.swipeRight() }
            else { horizontal.swipeLeft() }
        }
        XCTAssertTrue(action.isHittable, app.debugDescription, file: file, line: line)
    }

    /// The dock's actions do not exist until the sunrise is opened. This opens
    /// it when needed, checks that `identifier` is offered and `absent` is not,
    /// then closes it again so the screen is left as it was found.
    static func assertMorningAction(_ identifier: String, without absent: String? = nil, in app: XCUIApplication,
                                    timeout: TimeInterval = 10, _ message: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        let action = app.buttons[identifier]
        let sunrise = app.buttons["morning.actions"]
        let close = app.buttons["morning.closeActions"]
        let opened = !close.exists
        if opened {
            XCTAssertTrue(sunrise.waitForExistence(timeout: timeout),
                          "Morning must expose its sunrise control. \(message)\n\(app.debugDescription)", file: file, line: line)
            sunrise.tap()
        }
        XCTAssertTrue(action.waitForExistence(timeout: 5),
                      "Missing morning action: \(identifier). \(message)\n\(app.debugDescription)", file: file, line: line)
        if let absent {
            XCTAssertFalse(app.buttons[absent].exists,
                           "Unexpected morning action: \(absent). \(message)\n\(app.debugDescription)", file: file, line: line)
        }
        if opened {
            closeMorningActions(in: app, file: file, line: line)
        }
    }

    static func closeMorningActions(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let close = app.buttons["morning.closeActions"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        close.tap()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }

    static func reviewAction(_ identifier: String, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        selectTab("Review", in: app, file: file, line: line)
        tapButton(identifier, in: app, file: file, line: line)
    }

    static func openRoutine(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if app.buttons["morning.review"].exists {
            tapButton("morning.review", in: app, file: file, line: line)
        } else {
            reviewAction("review.routine", in: app, file: file, line: line)
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.waitForExistence(timeout: 5), file: file, line: line)
    }

    static func closeRoutine(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let editor = app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), file: file, line: line)
        let done = app.buttons["destination.close"]
        if done.exists, done.isHittable { done.tap() }
        else {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.exists && becomesHittable(back), app.debugDescription, file: file, line: line)
            back.tap()
        }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, file: file, line: line)
    }

    /// Starting a morning answers its opening with "start my routine", so a journey about
    /// the routine continues from the first moment. Pass `keepingOpening` to stay on it.
    static func tapButton(_ identifier: String, in app: XCUIApplication, keepingOpening: Bool = false,
                          file: StaticString = #filePath, line: UInt = #line) {
        if ["run.start", "run.resume", "morning.reviewDraft", "morning.review", "morning.learn", "morning.settings"].contains(identifier) {
            revealMorningAction(identifier, in: app, file: file, line: line)
        }
        let button = app.buttons[identifier]
        if !button.waitForExistence(timeout: 5) {
            // A native list creates its rows as they scroll into view, so a row
            // below the fold does not exist yet. Scroll the list to reach it.
            let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
            for _ in 0..<8 where !button.exists && list.exists { list.swipeUp() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing control: \(identifier)", file: file, line: line)
        // A control on a sheet that is still sliding in exists before it can be
        // touched. Give it a moment before deciding it has to be scrolled to.
        // Known and left as it is: on the iOS 27.0 simulator XCTest sometimes
        // cannot compute a control's hit point and records "Failed to determine
        // hittability … Activation point invalid" as a failure of the test,
        // instead of answering no. Tolerating it with an expected failure was
        // tried and removed: a matched expected failure ends the test on the
        // spot without a failure, so its remaining checks never run.
        func canBeTouched() -> Bool { button.exists && button.isHittable }
        let touchable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in canBeTouched() }, object: nil)
        _ = XCTWaiter.wait(for: [touchable], timeout: 2)
        for _ in 0..<4 where !canBeTouched() {
            let collection = app.collectionViews.containing(.button, identifier: identifier).firstMatch
            let table = app.tables.containing(.button, identifier: identifier).firstMatch
            let scroll = app.scrollViews.containing(.button, identifier: identifier).firstMatch
            let container: XCUIElement
            if collection.exists { container = collection }
            else if table.exists { container = table }
            else {
                XCTAssertTrue(scroll.exists, "No visible scroll container for \(identifier)", file: file, line: line)
                container = scroll
            }
            // Review preserves its scroll position after Settings/Learn closes. A row
            // above that position needs the opposite gesture from a row below it.
            if button.frame.height > 0, button.frame.midY < container.frame.midY { container.swipeDown() }
            else { container.swipeUp() }
        }
        XCTAssertTrue(button.isHittable, "Control is not hittable: \(identifier)", file: file, line: line)
        button.tap()
        if identifier == "run.start" {
            let confirm = app.buttons["morning.confirmStart"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                          "Play must open the explicit ready state.\n\(app.debugDescription)", file: file, line: line)
            XCTAssertTrue(confirm.isHittable && confirm.isEnabled, app.debugDescription, file: file, line: line)
            confirm.tap()
            XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), app.debugDescription, file: file, line: line)
            if !keepingOpening { chooseRoutineAtOpening(in: app, file: file, line: line) }
        }
    }

    /// Every started morning opens with a greeting and a choice (issue #28).
    static func chooseRoutineAtOpening(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let close = app.buttons["morning.closeActions"]
        if close.exists && close.isHittable { close.tap() }
        let routine = app.buttons["opening.routine"]
        XCTAssertTrue(routine.waitForExistence(timeout: 15),
                      "A started morning must show its opening.\n\(app.debugDescription)", file: file, line: line)
        // Larger text scrolls the page: the opening may be above or below what is visible.
        let scroll = app.scrollViews.containing(.button, identifier: "opening.routine").firstMatch
        for _ in 0..<6 where !routine.isHittable && scroll.exists {
            if routine.frame.height > 0, routine.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(routine.isHittable, app.debugDescription, file: file, line: line)
        routine.tap()
        XCTAssertTrue(routine.waitForNonExistence(timeout: 5), app.debugDescription, file: file, line: line)
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
