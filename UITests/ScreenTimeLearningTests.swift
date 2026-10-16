import XCTest

/// Learn from Screen Time with the DEBUG fixture source (`--ui-testing-screen-time-fixture`):
/// five synthetic mornings, no Screen Time, no Apple sheet. Proves the card, the review,
/// the edits and that only Approve changes the routine; not the reading of real data.
@MainActor
final class ScreenTimeLearningTests: XCTestCase {
    private let currentTitle = "Your morning"

    func testSuggestionIsEditedAndOnlyApprovalReplacesTheRoutine() throws {
        let app = launch()
        startLearning(in: app)
        let first = app.staticTexts["screenTimeProposal.step.0"]
        XCTAssertEqual(first.label, "Messages")
        XCTAssertEqual(app.staticTexts["screenTimeProposal.label.0"].label, "Minutes measured")
        XCTAssertTrue(app.staticTexts["screenTimeProposal.sources"].label.contains("comparable mornings"))
        let instagram = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                             "screenTimeProposal.step.", "Instagram")).firstMatch
        XCTAssertTrue(instagram.exists, "The long Instagram stretch belongs in the suggestion.")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "screenTimeProposal.scroll.")).firstMatch.exists, "A long social stretch is flagged.")
        attach("screen-time-suggestion", app)

        // Leave the second app out before approving.
        let secondTitle = app.staticTexts["screenTimeProposal.step.1"].label
        let toggle = app.switches["screenTimeProposal.include.1"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 5), .completed)

        MorningUITestNavigation.tapButton("screenTimeProposal.approve", in: app)
        MorningUITestNavigation.openRoutine(in: app)
        let row = app.buttons["routine.step.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Messages"), row.label)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step.")).allElementsBoundByIndex
        XCTAssertFalse(rows.contains { $0.label.contains(secondTitle) }, "The app left out must not be in the routine.")
        XCTAssertFalse(rows.contains { $0.label.contains(currentTitle) })
        attach("screen-time-routine-approved", app)
        MorningUITestNavigation.closeRoutine(in: app)
    }

    func testSuggestionWaitsAndKeepCurrentLeavesTheRoutine() throws {
        let app = launch()
        startLearning(in: app)
        // Closing the review is not approval.
        MorningUITestNavigation.tapButton("screenTimeProposal.close", in: app)
        closeLearn(in: app)
        assertCurrentRoutine(in: app)

        MorningUITestNavigation.reviewAction("review.learn", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime.review", in: app)
        XCTAssertTrue(app.staticTexts["screenTimeProposal.step.0"].waitForExistence(timeout: 5))
        MorningUITestNavigation.tapButton("screenTimeProposal.keepCurrent", in: app)
        XCTAssertTrue(app.buttons["learn.screenTime.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["learn.screenTime.review"].exists)
        closeLearn(in: app)
        assertCurrentRoutine(in: app)
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "-more.appLanguage", "en", "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-approved", "--ui-testing-screen-time-fixture"]
        app.launch()
        return app
    }

    private func startLearning(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime.start", in: app)
        XCTAssertTrue(app.buttons["learn.screenTime.review"].waitForExistence(timeout: 15))
        MorningUITestNavigation.tapButton("learn.screenTime.review", in: app)
        XCTAssertTrue(app.staticTexts["screenTimeProposal.step.0"].waitForExistence(timeout: 15), app.debugDescription)
    }

    private func closeLearn(in app: XCUIApplication) {
        let screenTime = app.navigationBars["Screen Time"]
        if screenTime.exists, screenTime.buttons.element(boundBy: 0).exists { screenTime.buttons.element(boundBy: 0).tap() }
        let learn = app.navigationBars["Learn my morning"]
        XCTAssertTrue(learn.waitForExistence(timeout: 5))
        learn.buttons.element(boundBy: 0).tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: learn)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    private func assertCurrentRoutine(in app: XCUIApplication) {
        MorningUITestNavigation.openRoutine(in: app)
        let row = app.buttons["routine.step.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains(currentTitle), row.label)
        MorningUITestNavigation.closeRoutine(in: app)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
