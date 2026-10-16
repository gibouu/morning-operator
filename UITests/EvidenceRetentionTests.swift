import XCTest

/// Evidence retention and forgetting one observation (issue #8), on an isolated
/// synthetic workspace: two observations imported 40 days ago (one quoted by the
/// approved routine, one the source of a pending suggestion), one imported today and
/// one with no import date. No capture, model request or device permission is used.
@MainActor
final class EvidenceRetentionTests: XCTestCase {
    private let expiredSuggestionID = "8A000000-0000-4000-8000-000000000001"
    private let expiredQuotedID = "8A000000-0000-4000-8000-000000000002"
    private let freshID = "8A000000-0000-4000-8000-000000000003"
    private let unknownAgeID = "8A000000-0000-4000-8000-000000000004"

    func testSettingIsOffByDefaultAndListsNothing() {
        let app = launch()
        openPrivacy(app)
        let off = element("privacy.retention.option.off", in: app)
        XCTAssertTrue(off.isSelected, "Keeping raw evidence must default to Off.")
        XCTAssertFalse(element("privacy.retention.option.30", in: app).isSelected)
        XCTAssertFalse(app.buttons["privacy.retention.review"].exists)
        XCTAssertFalse(element("privacy.retention.dueCount", in: app, wait: 1).exists)
        attach("retention-en-off-by-default", app)
    }

    func testCancelRemovesNothingAndConfirmKeepsTheApprovedQuotation() {
        let app = launch()
        openPrivacy(app)
        tap("privacy.retention.option.30", in: app)
        XCTAssertTrue(element("privacy.retention.option.30", in: app).isSelected)
        assertValue("privacy.retention.dueCount", "2", in: app)
        XCTAssertTrue(element("privacy.retention.unknownAge", in: app).exists)
        attach("retention-en-privacy-due", app)

        tap("privacy.retention.review", in: app)
        XCTAssertTrue(app.buttons["retention.confirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["retention.title"].label, "Remove old observations?", "The question is a heading in the sheet, not a bar title.")
        assertValue("retention.count.observations", "2", in: app)
        assertValue("retention.count.removed", "0", in: app)
        XCTAssertNotEqual(value("retention.count.invalidated", in: app), "0")
        XCTAssertNotEqual(value("retention.count.retained", in: app), "0")
        attach("retention-en-review", app)
        XCTAssertTrue(element("retention.suggestion", in: app).exists, "The pending suggestion must be listed as set aside.")
        XCTAssertTrue(element("retention.retained.0", in: app).exists, "The approved quotation must be listed as kept.")
        attach("retention-en-review-details", app)

        // Cancel changes nothing, including after a relaunch.
        app.buttons["retention.cancel"].tap()
        XCTAssertTrue(app.buttons["retention.confirm"].waitForNonExistence(timeout: 5))
        relaunch(app)
        openArchive(app)
        for id in [expiredSuggestionID, expiredQuotedID, freshID, unknownAgeID] {
            XCTAssertTrue(app.buttons["observation.row.\(id)"].waitForExistence(timeout: 5), "Cancel removed \(id).")
        }
        relaunch(app)
        openPrivacy(app)
        XCTAssertTrue(element("privacy.retention.option.30", in: app).isSelected, "The choice must survive a relaunch.")
        tap("privacy.retention.review", in: app)
        XCTAssertTrue(app.buttons["retention.confirm"].waitForExistence(timeout: 5))
        tap("retention.confirm", in: app)
        XCTAssertTrue(app.buttons["retention.confirm"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(element("privacy.retention.nothingDue", in: app).waitForExistence(timeout: 5))
        attach("retention-en-after-removal", app)

        relaunch(app)
        openArchive(app)
        XCTAssertTrue(app.buttons["observation.row.\(freshID)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["observation.row.\(unknownAgeID)"].exists, "An unknown age is never removed.")
        XCTAssertFalse(app.buttons["observation.row.\(expiredSuggestionID)"].exists)
        XCTAssertFalse(app.buttons["observation.row.\(expiredQuotedID)"].exists)
        relaunch(app)
        MorningUITestNavigation.openRoutine(in: app)
        tap("routine.step.0", in: app)
        let quote = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Tea by the window")).firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 5), "The approved routine must keep its quotation.")
        attach("retention-en-approved-quotation-kept", app)
    }

    func testForgetOneObservationFromItsDetail() {
        let app = launch()
        openArchive(app)
        tap("observation.row.\(freshID)", in: app)
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5))
        tap("observation.forget", in: app)
        XCTAssertTrue(app.buttons["retention.confirm"].waitForExistence(timeout: 5))
        assertValue("retention.count.observations", "1", in: app)
        attach("retention-en-forget-one", app)
        app.buttons["retention.cancel"].tap()
        XCTAssertTrue(app.buttons["retention.confirm"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Observation"].exists, "Cancel keeps the observation open.")
        tap("observation.forget", in: app)
        XCTAssertTrue(app.buttons["retention.confirm"].waitForExistence(timeout: 5))
        tap("retention.confirm", in: app)
        XCTAssertTrue(app.navigationBars["Observations"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["observation.row.\(freshID)"].exists)
        relaunch(app)
        openArchive(app)
        XCTAssertTrue(app.buttons["observation.row.\(expiredQuotedID)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["observation.row.\(freshID)"].exists)
    }

    func testFrenchScreens() {
        let app = launch(["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"])
        screens(prefix: "retention-fr", app)
    }

    func testLargestTextScreens() throws {
        try LargeTextCondition.require()
        screens(prefix: "retention-largest-text", launch())
    }

    /// Identifiers only, so the wording of any language cannot fail it.
    private func screens(prefix: String, _ app: XCUIApplication) {
        openPrivacy(app)
        attach("\(prefix)-privacy-off", app)
        tap("privacy.retention.option.30", in: app)
        XCTAssertTrue(element("privacy.retention.dueCount", in: app).exists)
        attach("\(prefix)-privacy-due", app)
        tap("privacy.retention.review", in: app)
        XCTAssertTrue(app.buttons["retention.confirm"].waitForExistence(timeout: 5))
        attach("\(prefix)-review", app)
        let list = app.collectionViews.firstMatch
        for index in 1...3 where list.exists {
            list.swipeUp()
            attach("\(prefix)-review-\(index)", app)
        }
        app.buttons["retention.cancel"].tap()
        XCTAssertTrue(app.buttons["retention.confirm"].waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        MorningUITestNavigation.selectTab("Review", in: app)
        tap("review.observations", in: app)
        tap("observation.row.\(freshID)", in: app)
        tap("observation.forget", in: app)
        XCTAssertTrue(app.buttons["retention.confirm"].waitForExistence(timeout: 5))
        attach("\(prefix)-forget-one", app)
    }

    // MARK: - Helpers

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-retention-fixture"] + extra
        MorningUITestNavigation.launch(app)
        return app
    }

    /// The workspace already exists, so nothing is seeded again: what shows was saved.
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    private func openPrivacy(_ app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Review", in: app)
        tap("navigation.setup", in: app)
        tap("setup.privacy", in: app)
        XCTAssertTrue(element("privacy.retention.option.off", in: app).waitForExistence(timeout: 10))
    }

    private func openArchive(_ app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Review", in: app)
        tap("review.observations", in: app)
        XCTAssertTrue(app.navigationBars["Observations"].waitForExistence(timeout: 5))
    }

    /// At the largest text size a row can start far above or below the fold, so this
    /// scrolls toward it until it can be tapped instead of assuming a fixed distance.
    private func tap(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        _ = button.waitForExistence(timeout: 10)
        for _ in 0..<12 where !(button.exists && button.isHittable) {
            if button.exists, button.frame.height > 0, button.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(button.exists && button.isHittable, "Control is not hittable: \(identifier)", file: file, line: line)
        button.tap()
    }

    /// Scrolls the list until the element exists; native lists create rows as they appear.
    private func element(_ identifier: String, in app: XCUIApplication, wait: TimeInterval = 5) -> XCUIElement {
        let target = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if target.waitForExistence(timeout: wait) { return target }
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 where !target.exists && list.exists { list.swipeUp() }
        return target
    }

    private func value(_ identifier: String, in app: XCUIApplication) -> String? {
        let row = element(identifier, in: app)
        XCTAssertTrue(row.exists, "Missing \(identifier)")
        return row.value as? String
    }

    private func assertValue(_ identifier: String, _ expected: String, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value(identifier, in: app), expected, identifier, file: file, line: line)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        // A sheet's controls exist before its presentation ends. This pause affects the picture only.
        let settled = expectation(description: "Presentation settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
