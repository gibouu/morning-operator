import XCTest

/// Exercises the ordinary entry without buying or fabricating a StoreKit entitlement.
@MainActor
final class MorningDeveloperAccessTests: XCTestCase {
    func testIntroductionCrossPersistsForTheWorkspaceOnly() {
        let workspace = UUID()
        let app = launch(workspace: workspace)
        let access = app.buttons["onboarding.developerAccess"]
        assertDeveloperButton(access, label: "Accès développeur")
        attach("developer-access-introduction-fr", app)
        access.tap()
        assertHome(app)
        app.terminate()

        let relaunched = launch(workspace: workspace)
        assertHome(relaunched)
        relaunched.terminate()

        let otherWorkspace = launch(workspace: UUID())
        assertDeveloperButton(otherWorkspace.buttons["onboarding.developerAccess"], label: "Accès développeur")
        XCTAssertFalse(otherWorkspace.buttons["morning.actions"].exists)
        otherWorkspace.terminate()
    }

    func testPaywallCrossIsReachableWithLargestTextAndPersists() {
        let workspace = UUID()
        let app = launch(workspace: workspace, french: false, largestText: true)
        for _ in 0..<3 { MorningUITestNavigation.tapButton("onboarding.next", in: app) }
        let access = app.buttons["paywall.developerAccess"]
        assertDeveloperButton(access, label: "Developer access")
        attach("developer-access-paywall-en-largest-text", app)
        access.tap()
        assertHome(app)
        app.terminate()

        let relaunched = launch(workspace: workspace, french: false)
        assertHome(relaunched)
        relaunched.terminate()
    }

    private func launch(workspace: UUID, french: Bool = true, largestText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-real-subscription", "--ui-testing-empty-workspace",
            "--ui-testing-workspace=\(workspace.uuidString)", "--theme-phase=night", "--ui-testing-reduce-motion",
            "-more.appLanguage", french ? "fr" : "en",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"
        ]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func assertDeveloperButton(_ button: XCUIElement, label: String) {
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        XCTAssertEqual(button.label, label)
        XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.width, 44)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertHome(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
        XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
