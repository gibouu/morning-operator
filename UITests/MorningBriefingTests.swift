import XCTest

/// The app injects explicitly synthetic calendar/weather/search values only in a
/// UUID-isolated DEBUG workspace. These checks establish no live Apple source,
/// permission, network or speech audibility. Hands-free checks let the
/// routine progress on its own, from the speech coordinator's completion.
@MainActor
final class MorningBriefingTests: XCTestCase {
    func testHealthIsDirectlyReachableAndDetailsStartCollapsed() {
        let app = launchFixture()
        openSettings(app)
        tap("setup.health", app)
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 5))
        let health = app.switches["briefing.healthIncluded"].firstMatch
        XCTAssertTrue(health.waitForExistence(timeout: 5))
        XCTAssertEqual(health.value as? String, "0")
        XCTAssertFalse(app.staticTexts["Include recorded sleep"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach("health-direct-entry-compact-off", app)
    }

    func testCloudConversationExplainsSharingBeforeOpeningMicrophone() {
        let app = launchFixture()
        openSettings(app)
        tap("setup.conversation", app)
        XCTAssertTrue(app.buttons["cloudVoice.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["cloudVoice.start"].label, "Talk")
        XCTAssertTrue(app.buttons["cloudVoice.start"].isEnabled, "Conversation can be chosen from Settings without starting a morning.")
        XCTAssertFalse(app.buttons["cloudVoice.stop"].exists)
        XCTAssertTrue(app.staticTexts["cloudVoice.consent"].label.contains("processed online"))
        // SwiftUI propagates a DisclosureGroup's identifier to its children.
        // Match the actual disclosure text so this proves content, not an ID.
        let providers = app.staticTexts.containing(NSPredicate(format:
            "label CONTAINS %@ AND label CONTAINS %@", "ElevenLabs", "Google Gemini")).firstMatch
        XCTAssertFalse(providers.exists, "Provider details stay outside the voice choice and start collapsed.")
        let disclosure = app.buttons["cloudVoice.privacy"]
        reveal(disclosure, app)
        disclosure.staticTexts["Privacy"].tap()
        XCTAssertTrue(providers.waitForExistence(timeout: 5))
        reveal(providers, app)
        XCTAssertTrue(providers.label.contains("ElevenLabs") && providers.label.contains("Google Gemini"))
        let details = app.staticTexts.containing(NSPredicate(format:
            "label BEGINSWITH %@", "Previews and recaps you choose to play")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        reveal(details, app)
        XCTAssertTrue(details.label.contains("Previews and recaps you choose to play"))
        XCTAssertEqual(app.alerts.count, 0, "Viewing the choice must not open a microphone permission sheet.")
        attach("cloud-conversation-explicit-sharing-before-start", app)
    }

    func testSleepStartsOffAndUnavailableReaderDoesNotEnableIt() {
        let app = launchFixture()
        openBriefing(app)
        let sleep = app.switches["briefing.healthIncluded"].firstMatch
        reveal(sleep, app)
        XCTAssertEqual(sleep.value as? String, "0")
        attach("synthetic-sleep-off-by-default", app)
        let nativeSwitch = sleep.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { sleep.tap() }
        let issue = app.staticTexts["briefing.healthError"]
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        XCTAssertEqual(sleep.value as? String, "0", "An unavailable reader never saves an enabled choice.")
        XCTAssertEqual(app.alerts.count, 0, "The isolated fixture has no HealthKit reader.")
        attach("synthetic-sleep-reader-unavailable-choice-remains-off", app)
    }

    func testYourDayPreviewShowsSelectedFactsWhileSleepRemainsOff() {
        let app = launchFixture()
        openBriefing(app)
        let sleep = app.switches["briefing.healthIncluded"].firstMatch
        reveal(sleep, app)
        XCTAssertEqual(sleep.value as? String, "0")
        configureSources(app)
        let text = app.staticTexts["briefing.text"]
        reveal(text, app)
        let facts = XCTNSPredicateExpectation(predicate: NSPredicate(format:
            "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "Synthetic quiet reading", "Synthetic clear skies", "18 degrees Celsius"), object: text)
        XCTAssertEqual(XCTWaiter.wait(for: [facts], timeout: 10), .completed)
        XCTAssertFalse(text.label.contains("Sleep recorded:"), "An excluded Health reader contributes no sleep fact.")
        attach("synthetic-your-day-selected-calendar-weather-preview", app)
        XCTAssertEqual(app.alerts.count, 0, "Preparing the preview never requests Health access.")
    }

    func testSelectedSourcesPrepareRecapAndAddingItRequiresApprovalAfterRelaunch() {
        let app = launchFixture()
        MorningUITestNavigation.openRoutine(in: app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.assertMorningAction("run.start", in: app)
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
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", without: "run.start", in: app,
            "Adding a source-backed operation cannot approve the new routine.")
        MorningUITestNavigation.openRoutine(in: app)
        XCTAssertTrue(app.buttons["routine.step.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("Your day"))
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.closeRoutine(in: app)

        app.terminate(); MorningUITestNavigation.launch(app)
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", without: "run.start", in: app)
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
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        let before = app.scrollViews["morning.captions"].value as? String
        XCTAssertFalse(before?.isEmpty ?? true)

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
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        XCTAssertEqual(app.scrollViews["morning.captions"].value as? String, before,
                       "Refreshing source facts must preserve the exact session and step identities.")
        attach("synthetic-preview-refresh-preserves-active-moment", app)
        MorningUITestNavigation.tapButton("run.controls", in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    func testStartingTheRoutineKeepsPreparedRecapInSettingsUntilRequested() {
        let app = launchFixture()
        defer { app.terminate() }
        openBriefing(app)
        configureSources(app)
        assertPreparedSources(app)
        closeBriefingAndSettings(app)
        MorningUITestNavigation.openRoutine(in: app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.tapButton("run.start", in: app, keepingOpening: true)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        let caption = app.staticTexts["morning.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(caption.label.contains("Synthetic"),
                       "A prepared preview must not become an extra moment before the approved routine.")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
        XCTAssertFalse(app.staticTexts["Synthetic weather attribution"].exists)
        XCTAssertFalse(app.buttons["opening.routine"].exists)
        XCTAssertEqual(app.sheets.count, 0)
        let identity = app.scrollViews["morning.captions"].value as? String
        XCTAssertFalse(identity?.isEmpty ?? true)
        attach("synthetic-routine-starts-without-extra-recap", app)

        openBriefing(app)
        assertPreparedSources(app)
        let hear = app.buttons["briefing.hear"]
        reveal(hear, app)
        XCTAssertFalse(hear.isEnabled, "The preview cannot start competing speech during the routine.")
        closeBriefingAndSettings(app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        XCTAssertEqual(app.scrollViews["morning.captions"].value as? String, identity)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
        attach("synthetic-recap-inspection-keeps-running-moment", app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    /// The first approved spoken moment completes on the real speech coordinator;
    /// no greeting or unrequested recap delays the start or hands it over twice.
    func testHandsFreeRoutineStartsOnceAndContinuesWithoutGreetingOrExtraRecap() throws {
        #if !targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing speech on the selected phone.")
        }
        #endif
        let app = launchFixture(["--ui-testing-hands-free", "--ui-testing-read-aloud"])
        defer { app.terminate() }
        openBriefing(app)
        configureSources(app)
        assertPreparedSources(app)
        closeBriefingAndSettings(app)
        MorningUITestNavigation.openRoutine(in: app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.tapButton("run.start", in: app, keepingOpening: true)
        MorningUITestNavigation.assertSession(state: "running", in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["speech"], "")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
        XCTAssertFalse(app.staticTexts["voice.access.status"].exists)
        XCTAssertFalse(app.staticTexts["voice.readingConsent"].exists)
        XCTAssertEqual(app.sheets.count, 0)
        attach("hands-free-routine-starts-directly", app)
        waitForManualMoment(in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["starts"], "routine started 1")
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["opening"], "none")
        attach("hands-free-routine-advanced-without-opening", app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
    }

    private func waitForManualMoment(in app: XCUIApplication) {
        let manual = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.sessionSnapshot(in: app)["step"] == "People and messages"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [manual], timeout: 60), .completed, app.debugDescription)
        MorningUITestNavigation.assertSession(state: "running", step: "People and messages", in: app)
        XCTAssertEqual(MorningUITestNavigation.sessionSnapshot(in: app)["completed"], "1",
                       "The first spoken moment completes by itself and the manual one waits.")
    }

    private func launchFixture(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-briefing-fixture", "-more.appLanguage", "en"] + extra
        MorningUITestNavigation.launch(app)
        return app
    }

    private func openBriefing(_ app: XCUIApplication) {
        openSettings(app)
        tap("setup.briefing", app)
        XCTAssertTrue(app.navigationBars["Your day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 5))
    }

    private func openSettings(_ app: XCUIApplication) {
        MorningUITestNavigation.openSettings(in: app)
    }

    private func configureSources(_ app: XCUIApplication) {
        let calendar = app.switches["briefing.calendar.synthetic-day-calendar"].firstMatch
        reveal(calendar, app)
        XCTAssertEqual(calendar.value as? String, "0")
        // A native Toggle may expose both its labelled row and a nested switch.
        let nativeSwitch = calendar.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { calendar.tap() }
        XCTAssertEqual(calendar.value as? String, "1")
        MorningUITestNavigation.chooseManualWeatherCity(in: app)
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        MorningUITestNavigation.selectTab("Morning", in: app)
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
