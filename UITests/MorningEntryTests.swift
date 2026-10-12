import XCTest

/// An injected foreground request in an isolated workspace. These checks do not
/// establish Siri recognition, lock-screen behavior or notification delivery.
@MainActor
final class MorningEntryUITests: XCTestCase {
    func testRealLocalInvitationStartsApprovedMorningFromBackground() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_NOTIFICATION_TEST_ENABLED"] == "1",
                          "Opt in on the dedicated simulator; this schedules a real local notification.")
        let app = launch(["--ui-testing-approved", "--ui-testing-near-invitation"])
        MorningUITestNavigation.selectTab("Review", in: app)
        let settings = app.buttons["navigation.setup"]
        for _ in 0..<5 where !settings.isHittable { app.swipeUp() }
        settings.tap()
        app.buttons["setup.invitation"].tap()
        XCTAssertTrue(app.buttons["invitation.schedule"].waitForExistence(timeout: 5))
        app.buttons["invitation.schedule"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let scheduled = app.staticTexts["invitation.status"]
        let registered = NSPredicate(format: "label BEGINSWITH %@", "One-time invitation scheduled")
        expectation(for: registered, evaluatedWith: scheduled)
        waitForExpectations(timeout: 10)
        app.navigationBars["Your next morning"].buttons["Done"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        MorningUITestNavigation.selectTab("Morning", in: app)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let notification = springboard.staticTexts["Ready for your morning?"]
        XCTAssertTrue(notification.waitForExistence(timeout: 60), "Wait for a real local invitation, not an injected push.")
        let delivered = XCTAttachment(screenshot: springboard.screenshot())
        delivered.name = "more-real-simulator-local-invitation"
        delivered.lifetime = .keepAlways
        add(delivered)
        notification.tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
    }

    func testApprovedEntryStartsOnceWithoutAnotherTap() {
        let app = launch(["--ui-testing-approved", "--ui-testing-start-entry"])
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        app.buttons["run.next"].tap()
        XCTAssertEqual(app.staticTexts["run.step"].label, "People and messages")
    }

    func testDraftEntryOpensReviewWithoutStartingOrApproving() {
        let app = launch(["--ui-testing-start-entry"])
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Your routine"].exists)
        XCTAssertFalse(app.buttons["run.pause"].exists)
    }

    func testMissingRoutineEntryOpensLearning() {
        let app = launch(["--ui-testing-empty-workspace", "--ui-testing-start-entry"])
        XCTAssertTrue(app.navigationBars["Learn my morning"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["run.pause"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Opening learning must not start recording or request its permission.")
    }

    func testInvitationSettingsExplainOneTimeEntryBeforePermission() {
        let app = launch([])
        MorningUITestNavigation.selectTab("Review", in: app)
        let settings = app.buttons["navigation.setup"]
        for _ in 0..<5 where !settings.isHittable { app.swipeUp() }
        settings.tap()
        app.buttons["setup.invitation"].tap()
        XCTAssertTrue(app.buttons["invitation.schedule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["invitation.schedule"].isHittable)
        XCTAssertTrue(app.staticTexts["invitation.status"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Reading invitation settings must not request permission.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "more-next-morning-invitation-before-permission"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDeferredEntryWaitsForMorningDetailsToClose() {
        let app = launch(["--ui-testing-approved", "--ui-testing-start-entry-on-return"])
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        MorningUITestNavigation.tapButton("run.start", in: app)
        app.buttons["run.controls"].tap()
        app.buttons["run.about"].tap()
        XCTAssertTrue(app.navigationBars["This moment"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["This moment"].waitForExistence(timeout: 5))
        // Backgrounding pauses the run. A fresh injected entry must remain queued
        // behind these details, rather than resuming behind the presentation.
        XCTAssertTrue(app.staticTexts["run.detailPaused"].waitForExistence(timeout: 5))
        let done = app.navigationBars["This moment"].buttons["Done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5), "The deferred entry resumes once the sheet closes.")
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--light-preview", "--fixture-mode"] + arguments
        app.launch()
        return app
    }
}
