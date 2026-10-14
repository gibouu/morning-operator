import XCTest

/// Real local removal on isolated synthetic workspaces. No device permission,
/// microphone, native capture, model request or Apple-app write is made here.
@MainActor
final class PrivacyTests: XCTestCase {
    func testCancelPreservesDataThenForgetRemainsEmptyAfterRelaunch() {
        let app = launch()
        openPrivacy(app)
        attach("privacy-inventory-before-removal", app)
        confirmSheet(app)
        app.buttons["privacy.cancelForget"].tap()
        XCTAssertTrue(app.navigationBars["Privacy"].exists)
        relaunch(app)
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", in: app)
        openPrivacy(app)
        assertCount("privacy.observations", value: "3", in: app)
        assertCount("privacy.captures", value: "1", in: app)
        assertCount("privacy.choices", value: "1", in: app)
        confirmSheet(app)
        app.buttons["privacy.confirmForget"].tap()
        assertEmptyMorning(app)
        relaunch(app)
        assertEmptyMorning(app)
        openPrivacy(app)
        assertCount("privacy.observations", value: "0", in: app)
        assertCount("privacy.captures", value: "0", in: app)
        assertCount("privacy.choices", value: "0", in: app)
        let activity = app.switches["privacy.activityLogging"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        XCTAssertEqual(activity.value as? String, "0")
        XCTAssertEqual(app.alerts.count, 0)
        attach("privacy-empty-workspace-after-relaunch", app)
    }

    func testDelayedAnalysisCannotRestoreForgottenData() {
        let app = launch(["--ui-testing-evidence-proposals", "--ui-testing-privacy-delayed-analysis"])
        openPrivacy(app)
        scrollTo("privacy.releaseTestAnalysis", in: app)
        confirmSheet(app)
        app.buttons["privacy.confirmForget"].tap()
        XCTAssertTrue(app.otherElements["privacy.removing"].waitForExistence(timeout: 5) ||
                      app.staticTexts["Removing local data…"].exists)
        // The worker is manually held, deliberately ignoring cancellation.
        // Releasing only after removal starts avoids a duration-dependent race.
        scrollTo("privacy.releaseTestAnalysis", in: app)
        app.buttons["privacy.releaseTestAnalysis"].tap()
        assertEmptyMorning(app)
        relaunch(app)
        assertEmptyMorning(app)
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        XCTAssertTrue(app.staticTexts["No saved observations"].waitForExistence(timeout: 5))
        attach("privacy-late-synthetic-analysis-cannot-return", app)
    }

    func testPartialCleanupStaysClosedAndResumesAfterRelaunch() {
        let app = launch(["--ui-testing-privacy-cleanup-failure"])
        openPrivacy(app)
        confirmSheet(app)
        app.buttons["privacy.confirmForget"].tap()
        let status = app.staticTexts["privacy.status"]
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Some local data may already be gone"), object: status)
        let result = XCTWaiter.wait(for: [failed], timeout: 20)
        if result != .completed {
            attach("privacy-unexpected-cleanup-presentation", app)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "privacy-unexpected-cleanup-hierarchy"; tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(app.navigationBars["Privacy"].exists)
        let done = app.navigationBars.buttons["Done"]
        XCTAssertFalse(done.exists && done.isEnabled)
        attach("privacy-partial-cleanup-is-visible-and-retryable", app)
        // Only the exact synthetic barrier is repaired by this debug fixture.
        // Relaunch then follows the production pending-marker recovery path.
        app.terminate()
        app.launchArguments.append("--ui-testing-privacy-repair")
        app.launch()
        assertEmptyMorning(app)
        relaunch(app)
        assertEmptyMorning(app)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        let workspace = UUID().uuidString
        print("PRIVACY_TEST_WORKSPACE=\(workspace)")
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(workspace)", "--ui-testing-observation-archive",
            "--ui-testing-privacy-fixture"] + extra
        app.launch()
        return app
    }

    private func openPrivacy(_ app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        MorningUITestNavigation.tapButton("setup.privacy", in: app)
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
    }

    private func confirmSheet(_ app: XCUIApplication) {
        scrollTo("privacy.forget", in: app)
        app.buttons["privacy.forget"].tap()
        XCTAssertTrue(app.navigationBars["Forget local data?"].waitForExistence(timeout: 5))
    }

    private func assertCount(_ identifier: String, value: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, value)
    }

    private func scrollTo(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        for _ in 0..<8 where !button.exists || !button.isHittable {
            let list = app.collectionViews.firstMatch
            if list.exists { list.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing privacy control: \(identifier)")
        XCTAssertTrue(button.isHittable)
    }

    private func assertEmptyMorning(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["learn.begin"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["morning.reviewDraft"].exists)
        XCTAssertFalse(app.buttons["run.start"].exists)
        XCTAssertFalse(app.buttons["review.proposal"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-observation-archive" || $0 == "--ui-testing-privacy-delayed-analysis" }
        app.launch()
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways
        add(image)
    }
}
