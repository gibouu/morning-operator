import XCTest

/// Synthetic source data only. The negative journey exercises deterministic validation;
/// the positive journey attempts the actual local model without a fixture-generation flag.
@MainActor
final class OnDeviceLearningTests: XCTestCase {
    /// This validates a deterministic evidence guard, not model inference or screen capture.
    func testSetupOnlyRecordingDoesNotReplaceTheExistingRoutine() throws {
        let app = launch(useSyntheticProposal: true)
        let observation = """
        [User-selected video: 00:40.3; 3 frames sampled. This is partial visual evidence, not a complete interaction log.]

        [Observed frame at 00:00.0]
        Screen Sharing
        Morning Operator
        Share Screen
        Cancel

        [Observed frame at 00:10.0]
        Less handling. More morning.
        The briefing. The messages. That game of chess. Let's make space for the things you care about.
        Learn my morning

        [Observed frame at 00:20.0]
        App Library
        Suggestions
        Recently Added
        Social
        Entertainment
        """
        enterNotes(observation, in: app)
        assignSyntheticProvenance(in: app)
        XCTAssertFalse(app.buttons["proposal.approve"].exists,
                       "Saving provenance cannot start analysis.")
        tapButton("learn.analyze", in: app)
        let message = "Each selected observation needs usable activity evidence. Review its notes or choose another observation."
        let insufficient = app.staticTexts.matching(NSPredicate(format: "label == %@", message)).firstMatch
        XCTAssertTrue(insufficient.waitForExistence(timeout: 15))
        let notes = app.textViews["learn.notes"]
        XCTAssertTrue(notes.exists)
        XCTAssertEqual(notes.value as? String, observation)
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        attachScreenshot("setup-only-source-rejected-before-model", from: app)
        closeLearn(in: app)
        assertOriginalApprovedRoutine(in: app)
        attachScreenshot("setup-only-source-preserves-approved-routine", from: app)
    }

    /// Historical method name retained for existing explicit device-test invocations.
    /// The new unapproved routine is now a pending proposal, never an immediate replacement.
    func testAvailableLocalModelProducesANewUnapprovedRoutine() throws {
        let app = launch(useSyntheticProposal: false)
        let observation = "I check today's calendar for three minutes, then play chess for ten minutes. Keep chess as a ritual."
        enterNotes(observation, in: app)
        assignSyntheticProvenance(in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "learn.fixtureMode").firstMatch.exists,
                       "This path must never substitute deterministic assembly for native inference.")
        let analyze = app.buttons["learn.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: analyze)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            attachScreenshot("learning-skipped-model-unavailable", from: app)
            throw XCTSkip("Actual local-model learning was not run: the analysis action remains disabled after valid synthetic notes and explicit day/origin. No generated result is claimed.")
        }
        tapButton("learn.analyze", in: app)
        // Once an actual attempt starts, errors/timeouts fail. This is never a model-
        // unavailable skip after the fact and never an automatic fixture fallback.
        let proposal = app.buttons["proposal.approve"]
        #if targetEnvironment(simulator)
        // One exception, on a simulator only: a simulator without the model's
        // files still reports the model as available, then refuses the request
        // with model-manager error 1019. That is a missing capability, not a
        // result. Any other model-manager error (an invalid schema, say) fails.
        let refusal = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                            "app.notice", "ModelManagerError error 1019")).firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in proposal.exists || refusal.exists },
                                                object: nil)
        _ = XCTWaiter.wait(for: [settled], timeout: 120)
        if !proposal.exists, refusal.exists {
            attachScreenshot("learning-skipped-simulator-has-no-model", from: app)
            throw XCTSkip("Actual local-model learning was not run: this simulator reports the on-device model as available but has no model to run (\(refusal.label)). No generated result is claimed.")
        }
        #endif
        XCTAssertTrue(proposal.waitForExistence(timeout: 120),
                      "Actual native inference must produce a validated pending proposal within 120 seconds.")
        let first = app.descendants(matching: .any).matching(identifier: "proposal.step.0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse((first.value as? String ?? "").isEmpty)
        XCTAssertTrue(app.buttons["proposal.keepCurrent"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attachScreenshot("actual-local-model-pending-proposal-needs-review", from: app)
        tapButton("proposal.close", in: app)
        waitAbsent(app.buttons["proposal.approve"])
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 5))
        closeLearn(in: app)
        assertOriginalApprovedRoutine(in: app)
        attachScreenshot("actual-local-model-proposal-preserves-current-morning", from: app)
    }

    private func launch(useSyntheticProposal: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
            "--ui-testing-workspace=\(UUID().uuidString)"]
        if useSyntheticProposal { app.launchArguments.append("--ui-testing-evidence-proposals") }
        app.launch()
        return app
    }

    private func enterNotes(_ observation: String, in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let notes = app.textViews["learn.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        revealNotes(in: app)
        XCTAssertTrue(notes.isEnabled)
        XCTAssertEqual(notes.value as? String ?? "", "", "Never append synthetic notes to an unexpected existing workspace.")
        notes.tap()
        notes.typeText(observation)
        XCTAssertEqual(notes.value as? String, observation)
        let dismissKeyboard = app.buttons["input.done"]
        if dismissKeyboard.waitForExistence(timeout: 2), dismissKeyboard.isHittable { dismissKeyboard.tap() }
    }

    private func assignSyntheticProvenance(in app: XCUIApplication) {
        tapButton("learn.analyze", in: app)
        XCTAssertTrue(app.buttons["observation.saveDate"].waitForExistence(timeout: 5))
        tapButton("observation.originPicker", in: app)
        tapButton("Sample or test", in: app)
        tapButton("observation.saveDate", in: app)
        waitAbsent(app.buttons["observation.saveDate"])
        XCTAssertTrue(app.textViews["learn.notes"].exists)
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
    }

    private func closeLearn(in app: XCUIApplication) {
        let done = app.navigationBars["Learn my morning"].buttons["Done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        waitAbsent(app.textViews["learn.notes"])
    }

    private func assertOriginalApprovedRoutine(in app: XCUIApplication) {
        MorningUITestNavigation.openRoutine(in: app)
        let first = app.buttons["routine.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("Your morning"))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step.")).count, 4)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.closeRoutine(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("run.start", in: app)
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        MorningUITestNavigation.tapButton(identifier, in: app, file: file, line: line)
    }

    private func revealNotes(in app: XCUIApplication) {
        let notes = app.textViews["learn.notes"]
        let sheet = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        XCTAssertTrue(sheet.exists)
        for _ in 0..<4 where !notes.isHittable { sheet.swipeUp() }
        XCTAssertTrue(notes.isHittable)
    }

    private func waitAbsent(_ element: XCUIElement) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 5), .completed)
    }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
