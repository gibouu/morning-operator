import XCTest

/// Isolated synthetic observations, with the production AVSpeechSynthesizer path.
/// These journeys do not perform capture, OCR, inference, or prove listener audibility.
@MainActor
final class ObservationNarrationTests: XCTestCase {
    private let sourceID = "00000000-0000-4000-8000-000000000101"
    private let excerpt = "Synthetic fixture only. No app was opened, movie captured, OCR performed or model called."

    func testSelectedExcerptPreviewsPersistsAndAdvancesAfterNativeSpeech() throws {
        let app = launchFixture()
        openNarration(in: app)
        let text = try selectExcerpt(in: app)
        XCTAssertTrue(text.contains(excerpt))
        XCTAssertTrue(text.contains("synthetic sample"))

        tap("narration.hear", in: app)
        let playback = app.descendants(matching: .any).matching(identifier: "narration.playback").firstMatch
        // Thirty seconds: the simulator's first speech request has taken more
        // than ten to start on a slow hosted runner.
        wait(playback, predicate: "value == %@", argument: "speaking", timeout: 30,
             message: "The real native speech delegate must enter speaking, not merely accept a request.", in: app)
        attach("saved-excerpt-native-preview-speaking", app)
        tap("narration.stop", in: app)
        wait(playback, predicate: "value == %@", argument: "idle", timeout: 5,
             message: "Stopping preview must release its playback before the routine can use speech.", in: app)

        addDraftAndRelaunch(app)
        approveDraft(expectedText: text, in: app)
        enableReadAloud(in: app)
        startAndEnableHandsFree(in: app)

        waitForSession(step: "People and messages", timeout: 60, in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["completed"], "2",
                       "Native speech must complete both the saved excerpt and Your morning without Next.")
        MorningUITestNavigation.openSettings(in: app)
        XCTAssertTrue(app.buttons["morning.next"].waitForExistence(timeout: 5),
                      "The next manual moment still needs the person's explicit continuation.")
        attach("saved-excerpt-and-calm-start-completed-by-native-speech", app)
        stopMorning(in: app)
    }

    func testDeletedSourceBlocksApprovedExcerptWithoutAdvancing() throws {
        let app = launchFixture()
        openNarration(in: app)
        let text = try selectExcerpt(in: app)
        addDraftAndRelaunch(app)
        approveDraft(expectedText: text, in: app)
        enableReadAloud(in: app)

        openSource(in: app)
        tap("observation.delete", in: app)
        let confirmation = app.alerts["Delete this observation?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
        let delete = confirmation.buttons.matching(NSPredicate(format: "label == %@", "Delete observation")).firstMatch
        XCTAssertTrue(delete.isHittable, app.debugDescription)
        delete.tap()
        waitForAbsence(confirmation, in: app)

        // Persisted deletion, not a stale in-memory projection, must invalidate playback.
        relaunchWithoutSeed(app)
        startAndEnableHandsFree(in: app)
        let refusal = "This saved excerpt has changed or was removed. Choose it again in Review, or tap Next."
        let caption = app.staticTexts["morning.caption"]
        wait(caption, predicate: "label == %@", argument: refusal, timeout: 10,
             message: "The executor must refuse the deleted source before any pause or manual action.", in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["completed"], "0")
        MorningUITestNavigation.openSettings(in: app)
        XCTAssertTrue(app.buttons["morning.next"].isEnabled, "Refusal must leave a manual way to continue.")
        tap("morning.details", in: app)
        let unavailable = app.staticTexts.matching(NSPredicate(format: "label == %@", refusal)).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10), app.debugDescription)
        tap("morning.closeDetails", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "paused", step: "A saved moment", in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["completed"], "0",
                       "An unavailable source must not report successful completion.")
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.sessionSnapshot(in: app)["step"] != "A saved moment"
        }, object: nil)
        advanced.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 3), .completed,
                       "An unavailable source must not advance while its details are read.")
        attach("deleted-excerpt-source-refused-without-advancement", app)
        stopMorning(in: app)
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
                               "--ui-testing-observation-review", "--light-preview",
                               "--ui-testing-workspace=\(UUID().uuidString)"]
        MorningUITestNavigation.launch(app)
        return app
    }

    private func openSource(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        XCTAssertTrue(app.navigationBars["Observations"].waitForExistence(timeout: 5), app.debugDescription)
        let row = app.buttons["observation.row.\(sourceID)"]
        reveal(row, in: app).tap()
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func openNarration(in app: XCUIApplication) {
        openSource(in: app)
        tap("observation.prepareNarration", in: app)
        XCTAssertTrue(app.navigationBars["A saved moment"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func selectExcerpt(in app: XCUIApplication) throws -> String {
        // IDs contain the actual candidate's frame/line/hash. Find the chosen visible
        // words instead of manufacturing a source identifier inside the test.
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "narration.candidate.", excerpt)).firstMatch
        reveal(candidate, in: app).tap()
        let prepared = app.staticTexts["narration.text"]
        reveal(prepared, in: app)
        let text = prepared.label
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.hasSuffix(excerpt), "The displayed sentence must retain the exact selected whole line.")
        return text
    }

    private func addDraftAndRelaunch(_ app: XCUIApplication) {
        tap("narration.add", in: app)
        let message = app.staticTexts["narration.message"]
        wait(message, predicate: "label == %@", argument: "Review and approve your updated morning before running it.",
             timeout: 5, message: "Adding an excerpt must create a reviewable draft.", in: app)
        tap("narration.done", in: app)
        waitForAbsence(app.navigationBars["A saved moment"], in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", without: "run.start", in: app,
            "Selecting source content cannot approve a new routine.")
        relaunchWithoutSeed(app)
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", without: "run.start", in: app)
    }

    private func approveDraft(expectedText: String, in app: XCUIApplication) {
        MorningUITestNavigation.openRoutine(in: app)
        let first = app.buttons["routine.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(first.label.contains("A saved moment"), first.debugDescription)
        first.tap()
        XCTAssertTrue(app.navigationBars["Make it yours"].waitForExistence(timeout: 5), app.debugDescription)
        let sourceText = app.staticTexts.matching(NSPredicate(format: "label == %@", expectedText)).firstMatch
        reveal(sourceText, in: app)
        XCTAssertEqual(sourceText.label, expectedText, "The approved draft must preserve the same reviewed sentence after relaunch.")
        app.navigationBars["Make it yours"].buttons["Cancel"].tap()
        waitForAbsence(app.navigationBars["Make it yours"], in: app)
        tap("routine.approve", in: app)
        MorningUITestNavigation.assertMorningAction("run.start", in: app)
    }

    private func enableReadAloud(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        let choice = app.switches["setup.readAloud"]
        reveal(choice, in: app)
        if choice.value as? String != "1" {
            // Native grouped toggles can expose an enclosing row plus a nested Switch.
            let control = choice.switches.firstMatch.exists ? choice.switches.firstMatch : choice
            XCTAssertTrue(control.isHittable, app.debugDescription)
            control.tap()
        }
        wait(choice, predicate: "value == %@", argument: "1", timeout: 5,
             message: "Spoken guidance must be explicitly enabled through the production setting.", in: app)
        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        MorningUITestNavigation.selectTab("Morning", in: app)
        waitForAbsence(settings, in: app)
    }

    private func startAndEnableHandsFree(in app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("run.start", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "A saved moment", in: app)
        MorningUITestNavigation.openSettings(in: app)
        let handsFree = app.switches["setup.handsFree"]
        reveal(handsFree, in: app)
        XCTAssertEqual(handsFree.value as? String, "0")
        let control = handsFree.switches.firstMatch.exists ? handsFree.switches.firstMatch : handsFree
        control.tap()
        XCTAssertEqual(handsFree.value as? String, "1")
        MorningUITestNavigation.selectTab("Morning", in: app)
        // No Next/Skip action is used: the production automatic executor owns completion.
    }

    private func stopMorning(in app: XCUIApplication) {
        tap("run.controls", in: app)
        tap("run.stop", in: app)
    }

    private func waitForSession(step: String, timeout: TimeInterval, in app: XCUIApplication) {
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.sessionSnapshot(in: app)["step"] == step
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: timeout), .completed,
                       "Native speech must finish the saved excerpt and Your morning before reaching the manual moment.\n\(app.debugDescription)")
        MorningUITestNavigation.assertSession(state: "running", step: step, in: app)
    }

    private func relaunchWithoutSeed(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-observation-review" || $0 == "--ui-testing-approved" }
        MorningUITestNavigation.launch(app)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        if identifier.hasPrefix("run.") {
            MorningUITestNavigation.tapButton(identifier, in: app)
            return
        }
        reveal(app.buttons[identifier], in: app).tap()
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<10 where !element.isHittable {
            // A full-screen list can report no hit point of its own on iOS 27.0;
            // a swipe on the window scrolls the same list.
            let container = app.collectionViews.allElementsBoundByIndex.first(where: { $0.isHittable })
                ?? app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? app
            if element.exists && element.frame.height > 0 && element.frame.midY < container.frame.midY { container.swipeDown() }
            else { container.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
        return element
    }

    private func wait(_ element: XCUIElement, predicate: String, argument: String, timeout: TimeInterval,
                      message: String, in app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate, argument), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed, "\(message)\n\(app.debugDescription)")
    }

    private func waitForAbsence(_ element: XCUIElement, in app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, app.debugDescription)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
