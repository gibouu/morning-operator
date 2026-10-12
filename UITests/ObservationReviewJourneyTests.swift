import XCTest

/// Synthetic samples exercise review/persistence, never model accuracy or real phone use.
@MainActor
final class ObservationReviewJourneyTests: XCTestCase {
    private let clipSuffix = "000000000101"

    func testWeeklySourcesOpenExactSamplesAndKeepUnknownDays() throws {
        let app = launch()
        MorningUITestNavigation.reviewAction("review.recordedPatterns", in: app)
        XCTAssertTrue(app.navigationBars["Observed mornings"].waitForExistence(timeout: 5))
        let coverage = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "review.recordings.", "2 days with labeled samples · 3 days with observations")).firstMatch
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        XCTAssertTrue(coverage.label.contains("2 days with labeled samples · 3 days with observations"), coverage.label)
        XCTAssertTrue(app.staticTexts["1 observed day has no labeled samples. 4 days have no observation."].exists)
        attach("recorded-week-synthetic-coverage", app)
        let cedar = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "review.recordings.context.", "Cedar")).firstMatch
        tap(cedar, in: app)
        XCTAssertTrue(app.navigationBars["Source moments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Seen on 2 distinct days.")).firstMatch.exists)
        let citation = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.recordings.citation.")).firstMatch
        tap(citation, in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 8), app.debugDescription)
        let quote = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.sample.quote.")).firstMatch
        XCTAssertEqual(quote.label, "Cedar")
        let text = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.sample.originalText.")).firstMatch
        XCTAssertTrue(text.label.contains("Cedar"))
        let actual = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.sample.actualTime.")).firstMatch
        XCTAssertTrue(actual.exists)
        attach("recorded-source-exact-quote", app)
        MorningUITestNavigation.tapButton("observation.sample.close", in: app)
        XCTAssertTrue(app.navigationBars["Source moments"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["review.average"].exists)
    }

    func testClipReturnCorrectionAndOriginalsSurviveRelaunch() throws {
        let app = launch()
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "observation.row.", clipSuffix)).firstMatch
        let id = String(row.identifier.dropFirst("observation.row.".count))
        tap(row, in: app)
        let prefix = "observation.timeline.\(id)"
        let returns = app.staticTexts["\(prefix).returns"]
        reveal(returns, in: app)
        XCTAssertTrue(returns.label.contains("At least 1 visible return"), returns.label)
        let summary = app.staticTexts["\(prefix).summary"]
        XCTAssertEqual(summary.label, "4 of 5 sampled moments labeled · 1 unresolved")
        let disclosure = app.descendants(matching: .any).matching(identifier: "\(prefix).samples").firstMatch
        tap(disclosure, in: app)
        let points = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "\(prefix).point."))
        XCTAssertTrue(points.firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(points.count, 5, app.debugDescription)
        let tied = points.matching(NSPredicate(format: "value CONTAINS %@", "2 samples share this time")).firstMatch
        tap(tied, in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 5))
        // Native List virtualizes the second source. Inspect each actual row,
        // rather than treating an off-screen accessibility count as the data count.
        for suffix in ["010101", "010102"] {
            let sampleID = "00000000-0000-4000-8000-000000" + suffix
            let original = app.staticTexts["observation.sample.originalText.\(sampleID)"]
            reveal(original, in: app)
            XCTAssertTrue(original.label.contains("Cedar"))
        }
        attach("recorded-tied-samples-originals", app)
        MorningUITestNavigation.tapButton("observation.sample.close", in: app)
        MorningUITestNavigation.tapButton("observation.edit", in: app)
        let editor = app.textViews["learn.notes"]
        reveal(editor, in: app)
        editor.tap()
        editor.typeText(" A synthetic correction for review testing.")
        if app.buttons["input.done"].isHittable { app.buttons["input.done"].tap() }
        app.navigationBars["Learn my morning"].buttons["Done"].tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-observation-review" }
        app.launch()
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        tap(app.buttons["observation.row.\(id)"], in: app)
        let status = app.staticTexts["\(prefix).status"]
        reveal(status, in: app)
        XCTAssertTrue(status.label.contains("Notes were corrected"))
        XCTAssertEqual(app.staticTexts["\(prefix).summary"].label, "0 of 5 sampled moments labeled · 5 unresolved")
        XCTAssertFalse(app.staticTexts["\(prefix).returns"].exists)
        tap(app.descendants(matching: .any).matching(identifier: "\(prefix).samples").firstMatch, in: app)
        tap(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "\(prefix).point.")).firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.sample.originalText.")).firstMatch.label.contains("Cedar"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.sample.quote.")).firstMatch.exists)
        attach("recorded-correction-keeps-originals", app)
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-observation-review"]
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 1)
        for _ in 0..<8 where !element.exists || !element.isHittable {
            let container = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
            XCTAssertTrue(container.exists, app.debugDescription)
            if element.exists, element.frame.height > 0, element.frame.midY < container.frame.midY { container.swipeDown() }
            else { container.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
