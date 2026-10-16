import XCTest

/// Explicit synthetic protocol evidence only: no Gmail account, model, network or send.
@MainActor final class GmailAttentionJourneyTests: XCTestCase {
    func testPreferencesPersistAndIChooseAnotherActuallyReadMessage() {
        let app = launch()
        defer { app.terminate() }
        openPreferences(app)
        let priorities = field("gmail.attention.priorities", app)
        priorities.tap(); priorities.typeText("SYNTHETIC project commitments")
        app.swipeUp()
        tap("gmail.attention.save", app)
        XCTAssertTrue(app.staticTexts["gmail.attention.status"].label.contains("saved"))
        attach("gmail-attention-synthetic-priorities-saved", app)
        app.terminate(); app.launch()
        openPreferences(app)
        XCTAssertEqual(field("gmail.attention.priorities", app).value as? String, "SYNTHETIC project commitments")
        // Relaunch the same isolated workspace, then use ordinary routine playback.
        app.terminate(); app.launch()
        start(app)
        let explanation = app.staticTexts["mail.attention.explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 12))
        XCTAssertTrue(explanation.label.contains("SYNTHETIC") && explanation.label.contains("without a Gmail account or real inference"))
        XCTAssertTrue(app.staticTexts["mail.attention.prioritiesUsed"].label.contains("SYNTHETIC project commitments"))
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        let fourth = button("mail.attention.choose.4", app)
        XCTAssertTrue(fourth.isEnabled); fourth.tap()
        XCTAssertEqual(button("mail.attention.choose.4", app).label, "Selected message")
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        XCTAssertFalse(app.buttons["mail.selfSend"].exists)
        attach("gmail-attention-synthetic-fourth-read-message-chosen", app)
    }

    func testFallbackIsHonestAndNextDoesNotKeepMail() {
        let app = launch(extra: ["--ui-testing-gmail-attention-fallback"])
        defer { app.terminate() }
        start(app)
        let explanation = app.staticTexts["mail.attention.explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 12))
        XCTAssertTrue(explanation.label.contains("Test fallback") && explanation.label.contains("without personalized importance ranking"))
        XCTAssertFalse(app.staticTexts["mail.attention.prioritiesUsed"].exists)
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        attach("gmail-attention-synthetic-honest-fallback", app)
        tap("mail.continue", app)
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: explanation)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["mail.attention.choose.1"].exists)
    }

    func testFrenchLargestTextKeepsPreferencesAndReadMessageChoiceReachable() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openPreferences(app)
        XCTAssertTrue(field("gmail.attention.priorities", app).isHittable)
        XCTAssertTrue(button("gmail.attention.save", app).isHittable)
        attach("gmail-attention-synthetic-french-largest-preferences", app)
        app.terminate(); app.launch()
        start(app)
        XCTAssertTrue(app.staticTexts["mail.attention.explanation"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["mail.attention.explanation"].label.contains("sans compte Gmail ni inférence réelle"))
        button("mail.attention.choose.5", app).tap()
        XCTAssertEqual(button("mail.attention.choose.5", app).label, "Mail choisi")
        attach("gmail-attention-synthetic-french-largest-fifth-message", app)
    }

    private func launch(extra: [String] = [], french: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(), workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-gmail-attention", "--ui-testing-approved", "--ui-testing-hands-free", "--light-preview", "--theme-phase=morning",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US", "-more.appLanguage", french ? "fr" : "en"] + extra
        app.launch()
        if !app.staticTexts["qa.testWorkspace"].waitForExistence(timeout: 5) { app.terminate(); app.launch() }
        XCTAssertEqual(app.staticTexts["qa.testWorkspace"].value as? String, workspace)
        return app
    }
    private func reveal(_ app: XCUIApplication) {
        if !app.buttons["morning.begin"].exists && !app.buttons["morning.playback"].exists { tap("morning.actions", app) }
    }
    private func openPreferences(_ app: XCUIApplication) {
        reveal(app); tap("morning.settings", app); tap("setup.connections", app); tap("connections.gmailReader", app)
        XCTAssertTrue(app.staticTexts["gmail.attention.synthetic"].waitForExistence(timeout: 5))
        tap("gmail.attention.settings", app)
    }
    private func start(_ app: XCUIApplication) {
        reveal(app); tap("morning.begin", app)
        let captions = app.scrollViews["morning.captions"]
        XCTAssertTrue(captions.waitForExistence(timeout: 10))
        if !app.buttons["morning.settings"].exists { captions.coordinate(withNormalizedOffset: .init(dx: 0.25, dy: 0.25)).tap() }
        XCTAssertTrue(app.buttons["morning.playback"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["morning.more"].exists)
        XCTAssertFalse(app.buttons["morning.next"].exists)
        tap("morning.settings", app); tap("morning.details", app)
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForExistence(timeout: 5))
    }
    private func field(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        scroll(element, app); return element
    }
    private func button(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[identifier]; scroll(element, app); return element
    }
    private func tap(_ identifier: String, _ app: XCUIApplication) { button(identifier, app).tap() }
    private func scroll(_ element: XCUIElement, _ app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 6)
        for down in [false, true] {
            for _ in 0..<14 {
                if element.exists && element.isHittable { return }
                let scroll = app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
                    ?? app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app
                if down { scroll.swipeDown() } else { scroll.swipeUp() }
            }
        }
        XCTContext.runActivity(named: "Unreachable \(element.identifier)") { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; activity.add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; activity.add(screenshot)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable control \(element.identifier)")
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
