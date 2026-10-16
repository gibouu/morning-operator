import XCTest

/// An injected foreground request in an isolated workspace. These checks do not
/// establish Siri recognition, lock-screen behavior or notification delivery.
@MainActor
final class MorningEntryUITests: XCTestCase {
    func testRealLocalInvitationStartsApprovedMorningFromBackground() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_NOTIFICATION_TEST_ENABLED"] == "1",
                          "Opt in on the dedicated simulator; this schedules a real local notification.")
        let app = launch(["--ui-testing-approved", "--ui-testing-near-invitation"])
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("setup.invitation", in: app)
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
        XCTAssertTrue(app.staticTexts["morning.caption"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.state, .runningForeground)
        MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
    }

    func testApprovedEntryStartsOnceWithoutAnotherTap() {
        let app = launch(["--ui-testing-approved", "--ui-testing-start-entry"])
        XCTAssertTrue(app.staticTexts["morning.caption"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["morning.begin"].exists)
        MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.tapButton("morning.next", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "People and messages", in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
    }

    func testDraftEntryOpensReviewWithoutStartingOrApproving() {
        let app = launch(["--ui-testing-start-entry"])
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.exists)
        XCTAssertFalse(app.scrollViews["morning.captions"].exists)
    }

    func testMissingRoutineEntryOpensLearning() {
        let app = launch(["--ui-testing-empty-workspace", "--ui-testing-start-entry"])
        XCTAssertTrue(app.buttons["learn.screenTime"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.scrollViews["morning.captions"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Opening learning must not start recording or request its permission.")
    }

    func testInvitationSettingsExplainOneTimeEntryBeforePermission() {
        let app = launch([])
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("setup.invitation", in: app)
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
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("morning.details", in: app)
        XCTAssertTrue(app.staticTexts["moment.instructions"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        // Current interaction sheets close when the app backgrounds. Settings
        // still owns navigation and keeps the injected entry from resuming.
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForNonExistence(timeout: 5))
        let playback = app.buttons["morning.playback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 5))
        XCTAssertEqual(playback.label, "Continue")
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--light-preview", "--fixture-mode", "--ui-testing-workspace=\(UUID().uuidString)"] + arguments
        MorningUITestNavigation.launch(app)
        return app
    }
}
