import XCTest

/// Learn from Screen Time with the DEBUG fixture source (`--ui-testing-screen-time-fixture`):
/// five synthetic mornings, no Screen Time, no Apple sheet. Proves the card, the review,
/// the edits and that only Approve changes the routine; not the reading of real data.
@MainActor
final class ScreenTimeLearningTests: XCTestCase {
    private let currentTitle = "Your morning"

    func testOnlyMorningWindowsAppearBeforeReviewAndApproval() throws {
        let app = launch()
        defer { app.terminate() }
        readMorningWindows(in: app)
        assertMorningWindow(in: app)
        attach("screen-time-only-retained-morning-window", app)
        MorningUITestNavigation.tapButton("learn.screenTime.review", in: app)
        XCTAssertTrue(app.staticTexts["screenTimeProposal.step.0"].waitForExistence(timeout: 10))
        let suggestions = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "screenTimeProposal.step."))
        XCTAssertFalse(suggestions.allElementsBoundByIndex.contains { $0.label == "Mail" }, "Evening use is not proposed as a morning moment.")
        MorningUITestNavigation.tapButton("screenTimeProposal.close", in: app)
        closeLearn(in: app)
        assertCurrentRoutine(in: app)
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime.review", in: app)
        MorningUITestNavigation.tapButton("screenTimeProposal.approve", in: app)
        MorningUITestNavigation.openRoutine(in: app)
        let first = app.buttons["routine.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(first.label.contains("Messages"), first.label)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step."))
        XCTAssertFalse(rows.allElementsBoundByIndex.contains { $0.label.hasPrefix("Mail") })
        MorningUITestNavigation.closeRoutine(in: app)
    }

    func testFrenchLargestTextKeepsMorningWindowAndReviewReachable() throws {
        let app = launch(french: true, largestText: true)
        defer { app.terminate() }
        readMorningWindows(in: app)
        assertMorningWindow(in: app, french: true)
        attach("screen-time-french-largest-retained-window", app)
        MorningUITestNavigation.tapButton("learn.screenTime.review", in: app)
        let first = app.staticTexts["screenTimeProposal.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertEqual(first.label, "Messages")
        XCTAssertTrue(app.buttons["screenTimeProposal.approve"].exists)
        XCTAssertTrue(app.buttons["screenTimeProposal.approve"].isEnabled)
        attach("screen-time-french-largest-review", app)
    }

    private func assertMorningWindow(in app: XCUIApplication, french: Bool = false) {
        let window = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "screenTime.window.")).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<12 where !window.isHittable {
            if window.frame.midY > app.frame.midY { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(window.isHittable, "The local morning window remains readable at the chosen text size.")
        XCTAssertTrue(window.label.hasPrefix(french ? "Matin : " : "Morning: "), window.label)
        XCTAssertTrue(window.label.contains("7") && window.label.contains("8") && window.label.contains(":14"), window.label)
        let date = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "screenTime.date.")).firstMatch
        XCTAssertTrue(date.exists && !date.label.isEmpty, "The displayed window belongs to a dated local morning.")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "screenTime.daily.")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["screenTime.app.com.apple.mobilemail"].exists, "The fixture's evening-only Mail use stays out.")
        XCTAssertTrue(app.staticTexts["screenTime.app.com.apple.MobileSMS"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", french ? "Sommeil enregistré :" : "Recorded sleep:")).firstMatch.exists,
                       "An inactivity gap is not displayed as recorded sleep without Health samples.")
    }

    private func readMorningWindows(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime", in: app)
        MorningUITestNavigation.tapButton("learn.screenTime.start", in: app)
        XCTAssertTrue(app.buttons["learn.screenTime.review"].waitForExistence(timeout: 15))
    }

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

    private func launch(french: Bool = false, largestText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "-more.appLanguage", french ? "fr" : "en", "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-approved", "--ui-testing-screen-time-fixture"]
        if largestText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        MorningUITestNavigation.launch(app)
        return app
    }

    private func startLearning(in app: XCUIApplication) {
        readMorningWindows(in: app)
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
