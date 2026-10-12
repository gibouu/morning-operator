import XCTest

/// The app injects explicitly synthetic calendar/weather/search values only in a
/// UUID-isolated DEBUG workspace. These checks establish no live Apple source,
/// permission, network, speech audibility or automatic routine progression.
@MainActor
final class MorningBriefingTests: XCTestCase {
    func testSelectedSourcesPrepareRecapAndAddingItRequiresApprovalAfterRelaunch() {
        let app = launchFixture()
        MorningUITestNavigation.openRoutine(in: app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
        openBriefing(app)
        configureSources(app)
        assertPreparedSources(app)
        attach("synthetic-selected-sources-prepared-recap", app)

        tap("briefing.addToRoutine", app)
        let saved = app.staticTexts["briefing.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains("Added as a draft"))
        closeBriefingAndSettings(app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.start"].exists, "Adding a source-backed operation cannot approve the new routine.")
        MorningUITestNavigation.openRoutine(in: app)
        XCTAssertTrue(app.buttons["routine.step.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("Your day"))
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.closeRoutine(in: app)

        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["run.start"].exists)
        openBriefing(app)
        let calendar = app.switches["briefing.calendar.synthetic-day-calendar"].firstMatch
        reveal(calendar, app)
        XCTAssertEqual(calendar.value as? String, "1", "Only connection choices should be restored.")
        let city = app.descendants(matching: .any).matching(identifier: "briefing.city").firstMatch
        reveal(city, app)
        XCTAssertTrue(city.label.contains("Synthetic City") || (city.value as? String)?.contains("Synthetic City") == true ||
                      app.staticTexts["Synthetic City"].exists)
        assertPreparedSources(app)
        let add = app.buttons["briefing.addToRoutine"]
        reveal(add, app)
        XCTAssertEqual(add.label, "Already in your morning")
        XCTAssertFalse(add.isEnabled)
        XCTAssertEqual(app.alerts.count, 0, "Synthetic sources must not open system permission dialogs.")
        attach("synthetic-briefing-settings-restored-draft-still-unapproved", app)
    }

    func testPreviewRefreshDoesNotAdvanceOrReplaceTheActiveRoutineStep() {
        let app = launchFixture()
        openBriefing(app)
        configureSources(app)
        assertPreparedSources(app)
        closeBriefingAndSettings(app)
        MorningUITestNavigation.openRoutine(in: app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.tapButton("run.start", in: app)
        let state = app.staticTexts["run.state"]
        let step = app.staticTexts["run.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(state.value as? String, "running")
        let before = step.label
        XCTAssertEqual(before, "Your morning")

        openBriefing(app)
        tap("briefing.refresh", app)
        assertPreparedSources(app)
        let add = app.buttons["briefing.addToRoutine"]
        reveal(add, app)
        XCTAssertFalse(add.isEnabled, "An active routine cannot be replaced from the preview.")
        let hear = app.buttons["briefing.hear"]
        reveal(hear, app)
        XCTAssertFalse(hear.isEnabled, "The preview must not interrupt the active run with competing speech.")
        closeBriefingAndSettings(app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(step.label, before)
        XCTAssertEqual(state.value as? String, "running")
        attach("synthetic-preview-refresh-preserves-active-moment", app)
        MorningUITestNavigation.tapButton("run.controls", in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-briefing-fixture"]
        app.launch()
        return app
    }

    private func openBriefing(_ app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        MorningUITestNavigation.tapButton("setup.briefing", in: app)
        XCTAssertTrue(app.navigationBars["Your day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 5))
    }

    private func configureSources(_ app: XCUIApplication) {
        let calendar = app.switches["briefing.calendar.synthetic-day-calendar"].firstMatch
        reveal(calendar, app)
        XCTAssertEqual(calendar.value as? String, "0")
        // A native Toggle may expose both its labelled row and a nested switch.
        let nativeSwitch = calendar.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { calendar.tap() }
        XCTAssertEqual(calendar.value as? String, "1")
        let search = app.textFields["briefing.citySearch"]
        reveal(search, app)
        search.tap(); search.typeText("Synthetic\n")
        let done = app.buttons["input.done"]
        if done.waitForExistence(timeout: 1), done.isHittable { done.tap() }
        tap("briefing.cityResult.48.0,2.0", app)
        if done.exists && done.isHittable { done.tap() }
    }

    private func assertPreparedSources(_ app: XCUIApplication) {
        let text = app.staticTexts["briefing.text"]
        reveal(text, app)
        let hasBoth = XCTNSPredicateExpectation(predicate: NSPredicate(format:
            "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "Synthetic quiet reading", "Synthetic clear skies", "18 degrees Celsius"), object: text)
        XCTAssertEqual(XCTWaiter.wait(for: [hasBoth], timeout: 10), .completed)
        // The same source label also appears inside the calendar-selection toggle.
        // The exact prepared text above remains the assertion about recap facts.
        let calendarSource = app.staticTexts["Synthetic Calendar source"].firstMatch
        reveal(calendarSource, app)
        XCTAssertTrue(calendarSource.exists)
        let weatherSource = app.staticTexts["Synthetic Weather · Synthetic City"]
        reveal(weatherSource, app)
        XCTAssertTrue(weatherSource.exists)
        let preparedAt = app.staticTexts["briefing.preparedAt"]
        reveal(preparedAt, app)
        XCTAssertTrue(preparedAt.exists)
    }

    private func closeBriefingAndSettings(_ app: XCUIApplication) {
        app.navigationBars["Your day"].buttons["Done"].tap()
        let dayDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Your day"])
        XCTAssertEqual(XCTWaiter.wait(for: [dayDismissed], timeout: 5), .completed)
        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.buttons["Done"].tap()
    }

    private func tap(_ identifier: String, _ app: XCUIApplication) {
        let button = app.buttons[identifier].firstMatch
        reveal(button, app)
        XCTAssertTrue(button.isEnabled)
        button.tap()
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let containers = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let container = containers.last(where: { $0.isHittable }) ?? app
            if element.exists, element.frame.height > 0, element.frame.midY < container.frame.midY {
                container.swipeDown()
            } else { container.swipeUp() }
        }
        XCTAssertTrue(element.exists, "Missing visible briefing element: \(element)")
        XCTAssertTrue(element.isHittable)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
