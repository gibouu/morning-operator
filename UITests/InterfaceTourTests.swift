import UIKit
import XCTest

/// A look at the main screens in French and at the largest text size.
/// Synthetic fixture data in an isolated workspace; the screenshots are the
/// evidence. Nothing here asserts wording, so a translation change cannot fail
/// it: it fails only when a screen cannot be reached.
@MainActor
final class InterfaceTourTests: XCTestCase {
    func testFrenchTourOfHomeLearnReviewAndSettings() {
        let french = ["-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        tour(named: "tour-fr-light", arguments: ["--light-preview"] + french)
        // One dark home is enough to see the French text on the dark palette.
        let app = launch(["--dark-preview"] + french, workspace: UUID())
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 15), app.debugDescription)
        attach("tour-fr-dark-home", app)
    }

    func testLargestTextTourOfHomeLearnReviewAndSettings() throws {
        try LargeTextCondition.require()
        tour(named: "tour-largest-text", arguments: ["--light-preview"])
    }

    private func tour(named prefix: String, arguments: [String]) {
        let workspace = UUID()

        var app = launch(arguments, workspace: workspace)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 15), app.debugDescription)
        attach("\(prefix)-home", app)
        MorningUITestNavigation.revealControls(in: app)
        attach("\(prefix)-home-actions", app)
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        XCTAssertTrue(app.buttons["learn.screenTime"].waitForExistence(timeout: 10), app.debugDescription)
        attach("\(prefix)-learn", app)
        app.terminate()

        // A fresh launch per group: closing a sheet would need its localized Done button.
        app = launch(arguments, workspace: workspace)
        MorningUITestNavigation.selectTab("Review", in: app)
        attach("\(prefix)-review", app)
        MorningUITestNavigation.openSettings(in: app)
        XCTAssertTrue(app.buttons["setup.briefing"].waitForExistence(timeout: 10), app.debugDescription)
        attach("\(prefix)-settings", app)
        tapAfterScrolling(app.buttons["setup.briefing"], in: app)
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 10), app.debugDescription)
        attach("\(prefix)-your-day", app)
        MorningUITestNavigation.chooseManualWeatherCity(in: app)
        // The city field is a row of a native list: below the fold it does not exist yet.
        let city = app.textFields["briefing.citySearch"]
        for _ in 0..<12 where !(city.exists && city.isHittable) { app.swipeUp() }
        XCTAssertTrue(city.exists && city.isHittable, app.debugDescription)
        attach("\(prefix)-your-day-city", app)
        app.terminate()

        app = launch(arguments, workspace: workspace)
        MorningUITestNavigation.selectTab("Review", in: app)
        tapAfterScrolling(app.buttons["review.routine"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["routine.step.0"].waitForExistence(timeout: 10), app.debugDescription)
        attach("\(prefix)-routine", app)
        app.terminate()

        // Observed mornings, from the synthetic review fixture in its own workspace:
        // its heading wraps in full (issue #89).
        app = launch(arguments + ["--ui-testing-observation-review"], workspace: UUID())
        MorningUITestNavigation.selectTab("Review", in: app)
        tapAfterScrolling(app.buttons["review.recordedPatterns"], in: app)
        XCTAssertTrue(app.staticTexts["review.recordedPatterns.heading"].waitForExistence(timeout: 10), app.debugDescription)
        attach("\(prefix)-observed-mornings", app)
        app.terminate()

        // Learn with the message a model failure shows, set by a labelled fixture: a plain
        // sentence, never an error code (issue #89).
        app = launch(arguments + ["--ui-testing-model-not-ready"], workspace: UUID())
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 15), app.debugDescription)
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let message = app.descendants(matching: .any)["app.notice"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<12 where !message.isHittable { app.swipeUp() }
        attach("\(prefix)-learn-model-not-ready", app)
        app.terminate()

        // Last, because it starts this workspace's morning: the greeting and
        // current passage stay on the landscape; provenance stays in the editor.
        app = launch(arguments, workspace: workspace)
        MorningUITestNavigation.tapButton("run.start", in: app, keepingOpening: true)
        let caption = app.staticTexts["morning.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(caption.label.isEmpty)
        XCTAssertFalse(app.staticTexts["run.step"].exists)
        XCTAssertFalse(app.buttons["morning.next"].exists)
        attach("\(prefix)-opening", app)
        MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        MorningUITestNavigation.assertSession(state: "running", in: app)
        attach("\(prefix)-opening-routine-started", app)
        MorningUITestNavigation.openRoutine(in: app)
        let source = app.descendants(matching: .any).matching(identifier: "routine.source").firstMatch
        for _ in 0..<12 where !source.exists || !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.exists && source.isHittable)
        attach("\(prefix)-running-routine-provenance", app)
        app.terminate()
    }

    private func launch(_ arguments: [String], workspace: UUID) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The briefing fixture labels itself on screen and makes no Calendar, Maps or Weather request.
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved", "--ui-testing-briefing-fixture",
                               "--ui-testing-workspace=\(workspace.uuidString)"] + arguments
        if !arguments.contains("-more.appLanguage") { app.launchArguments += ["-more.appLanguage", "en"] }
        MorningUITestNavigation.launch(app)
        return app
    }

    /// At the largest text size a row can start far below the fold, so this
    /// scrolls until the row can be tapped instead of assuming a fixed distance.
    private func tapAfterScrolling(_ element: XCUIElement, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<12 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription, file: file, line: line)
        element.tap()
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        // A sheet's controls exist before its presentation animation ends. This
        // bounded pause affects the picture only, never an assertion.
        let settled = expectation(description: "Presentation settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Checks that need the simulator's own text size set to an accessibility size
/// (`xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`).
/// The test runner reads the same system setting as the app under test.
@MainActor
enum LargeTextCondition {
    static func require() throws {
        try XCTSkipUnless(UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "Requires the simulator's text size set to an accessibility size; it is at the standard size. Run after `xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`.")
    }
}
