import XCTest

/// Uses Apple's real ActivityKit service, with synthetic approved routine data
/// and an isolated UUID namespace. These checks do not establish phone locking,
/// actual speech, background execution or control of third-party applications.
@MainActor
final class MorningLiveActivityTests: XCTestCase {
    private var runningApp: XCUIApplication?

    override func tearDown() {
        if let app = runningApp {
            // A relaunch reconciles only this test's process-era activities.
            app.terminate(); app.launch()
            _ = app.buttons["morning.actions"].waitForExistence(timeout: 10)
            app.terminate()
        }
        runningApp = nil
        super.tearDown()
    }

    func testNativeProgressTracksPauseAdvanceAndEndsWhenDisabled() throws {
        let app = try launch()
        openSettings(app)
        assertNative("count:0", in: app)
        setEnabled(true, in: app)
        assertNative("count:0", in: app)
        closeSettings(app)
        tap("run.start", app)
        openSettings(app)
        assertNative("count:1|status:needsAttention|complete:0|total:4|category:briefing", in: app)
        attach("native-activity-started-in-isolated-workspace", app)
        closeSettings(app)
        tap("run.next", app)
        tap("run.pause", app)
        openSettings(app)
        assertNative("count:1|status:paused|complete:1|total:4|category:messages", in: app)
        setEnabled(false, in: app)
        assertNative("count:0", in: app)
        setEnabled(true, in: app)
        assertNative("count:1|status:paused|complete:1|total:4|category:messages", in: app)
        setEnabled(false, in: app)
        assertNative("count:0", in: app)
        closeSettings(app)
        app.terminate(); app.launch()
        openSettings(app)
        XCTAssertEqual(app.switches["activity.enabled"].firstMatch.value as? String, "0")
        assertNative("count:0", in: app)
        attach("native-activity-off-restores-without-recreation", app)
    }

    func testRelaunchReconcilesOldActivityAndExplicitResumeStartsOne() throws {
        let app = try launch()
        openSettings(app); setEnabled(true, in: app); closeSettings(app)
        tap("run.start", app)
        openSettings(app)
        assertNative("count:1|status:needsAttention|complete:0|total:4|category:briefing", in: app)
        closeSettings(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10))
        openSettings(app)
        XCTAssertEqual(app.switches["activity.enabled"].firstMatch.value as? String, "1")
        assertNative("count:0", in: app)
        closeSettings(app)
        tap("run.resume", app)
        openSettings(app)
        assertNative("count:1|status:needsAttention|complete:0|total:4|category:briefing", in: app)
        closeSettings(app)
        tap("run.controls", app); tap("run.stop", app)
        openSettings(app); assertNative("count:0", in: app)
    }

    func testBackgroundPausesTheNativeActivityAndReturningDoesNotResume() throws {
        let app = try launch()
        openSettings(app); setEnabled(true, in: app); closeSettings(app)
        tap("run.start", app)
        openSettings(app)
        assertNative("count:1|status:needsAttention|complete:0|total:4|category:briefing", in: app)
        closeSettings(app)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let background = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d", XCUIApplication.State.runningBackground.rawValue), object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 10), .completed)
        attach("native-activity-springboard-after-background", springboard)
        app.activate()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10))
        openSettings(app)
        assertNative("count:1|status:paused|complete:0|total:4|category:briefing", in: app)
        setEnabled(false, in: app)
        assertNative("count:0", in: app)
    }

    func testForgetRemovesNativeActivityAndRestoresOff() throws {
        let app = try launch()
        openSettings(app); setEnabled(true, in: app); closeSettings(app)
        tap("run.start", app)
        openSettings(app)
        assertNative("count:1|status:needsAttention|complete:0|total:4|category:briefing", in: app)
        closeSettings(app)
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        tap("setup.privacy", app)
        let forget = app.buttons["privacy.forget"]
        for _ in 0..<8 where !forget.isHittable {
            let list = app.collectionViews.firstMatch
            if list.exists { list.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(forget.isHittable)
        forget.tap()
        XCTAssertTrue(app.buttons["privacy.confirmForget"].waitForExistence(timeout: 5))
        app.buttons["privacy.confirmForget"].tap()
        XCTAssertTrue(app.buttons["learn.begin"].waitForExistence(timeout: 20))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["learn.begin"].waitForExistence(timeout: 10))
        openSettings(app)
        XCTAssertEqual(app.switches["activity.enabled"].firstMatch.value as? String, "0")
        assertNative("count:0", in: app)
        attach("native-activity-forgotten-with-opt-in-off", app)
    }

    func testNativeIslandPresentationOpensMorningWithoutResuming() throws {
        let app = try launch()
        openSettings(app); setEnabled(true, in: app); closeSettings(app)
        tap("run.start", app)
        openSettings(app)
        assertNative("count:1|status:needsAttention|complete:0|total:4|category:briefing", in: app)
        closeSettings(app)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let surface = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "MORE.", "moments passed")).firstMatch
        if !surface.waitForExistence(timeout: 10) {
            attach("native-island-surface-not-found", springboard)
            let tree = XCTAttachment(string: springboard.debugDescription)
            tree.name = "native-island-observed-hierarchy"; tree.lifetime = .keepAlways; add(tree)
            XCTFail("Native ActivityKit state exists, but the actual Island surface was not found.")
            return
        }
        surface.press(forDuration: 1)
        let paused = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "MORE.", "Paused", "moments passed")).firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 5))
        attachExpandedPresentation("native-expanded-island-paused-morning", springboard)
        // Observe the actual OS stale-date presentation, not a rendered preview
        // or an injected stale flag. The app remains in the background throughout.
        let stale = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "MORE.", "Update needed")).firstMatch
        // Native logs on iOS 27 show the requested 60-second stale date is
        // retained, but its nonwaking presentation task may run about 120
        // seconds after an update. Wait for that real transition, with margin;
        // this is not a promise that any OS renders exactly at either deadline.
        XCTAssertTrue(stale.waitForExistence(timeout: 150))
        stale.press(forDuration: 1)
        attachExpandedPresentation("native-island-stale-progress", springboard)
        stale.tap()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
        XCTAssertFalse(app.buttons["run.pause"].exists, "A reveal-only tap must not resume the run.")
        openSettings(app); setEnabled(false, in: app); assertNative("count:0", in: app)
    }

    private func launch() throws -> XCUIApplication {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_LIVE_ACTIVITY_TEST_ENABLED"] == "1",
            "Run explicitly on the dedicated simulator; this uses native ActivityKit.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--light-preview", "--fixture-mode", "--ui-testing-approved",
            "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-live-activity"]
        runningApp = app
        app.launch()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        tap("setup.activity", app)
        XCTAssertTrue(app.navigationBars["Lock Screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["activity.nativeDiagnostic"].waitForExistence(timeout: 5))
    }

    private func closeSettings(_ app: XCUIApplication) {
        app.navigationBars["Lock Screen"].buttons["Done"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        MorningUITestNavigation.selectTab("Morning", in: app)
    }

    private func setEnabled(_ enabled: Bool, in app: XCUIApplication) {
        let toggle = app.switches["activity.enabled"].firstMatch
        XCTAssertEqual(toggle.value as? String, enabled ? "0" : "1")
        let nativeSwitch = toggle.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
    }

    private func assertNative(_ summary: String, in app: XCUIApplication) {
        let label = app.staticTexts["activity.nativeDiagnostic"]
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", summary), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 12), .completed,
            "Expected native ActivityKit state \(summary), got \(label.label). \(app.staticTexts["activity.status"].label)")
    }

    private func tap(_ identifier: String, _ app: XCUIApplication) {
        MorningUITestNavigation.tapButton(identifier, in: app)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func attachExpandedPresentation(_ name: String, _ app: XCUIApplication) {
        // Accessibility appears before the system's expansion animation settles.
        // This bounded delay affects visual evidence only, never state assertions.
        let settled = expectation(description: "Native expansion presentation settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        attach(name, app)
    }
}
