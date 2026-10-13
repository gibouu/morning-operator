import XCTest

/// Human corrections of manufactured samples through the production save path.
/// No screen capture, OCR, local model request, or app-identity verification occurs.
@MainActor
final class ObservationScreenReviewTests: XCTestCase {
    private let sourceID = "00000000-0000-4000-8000-000000000101"
    private let sampleID = "00000000-0000-4000-8000-000000010103"
    private let correctedLabel = "Morning calendar"
    private let reviewedQuote = "Synthetic fixture only. No app was opened, movie captured, OCR performed or model called."
    private let originalText = "Lumen\nSynthetic fixture only. No app was opened, movie captured, OCR performed or model called."

    func testCorrectedLabelUpdatesWeeklyReviewAndResetSurvivesRelaunch() throws {
        let app = launchFixture()
        openWeeklySource(label: "Lumen", in: app)
        assertOriginalEvidence(in: app)

        openEditor(in: app)
        replaceLabel(with: "An unsaved label", in: app)
        tap("sampleLabel.cancel", in: app)
        assertEditorClosed(in: app)
        XCTAssertFalse(userLabel(in: app).exists, app.debugDescription)
        assertOriginalEvidence(in: app)

        openEditor(in: app)
        let field = app.textFields["sampleLabel.text"]
        XCTAssertEqual(field.value as? String, "Lumen", "Cancel must not change the effective label.")
        replaceLabel(with: correctedLabel, in: app)
        if app.buttons["sampleLabel.keyboardDone"].isHittable {
            app.buttons["sampleLabel.keyboardDone"].tap()
        }
        let supportingQuote = app.buttons["sampleLabel.quote.1"]
        reveal(supportingQuote, in: app)
        XCTAssertTrue(supportingQuote.label.contains(reviewedQuote), supportingQuote.debugDescription)
        tap(supportingQuote, in: app)
        tap("sampleLabel.save", in: app)
        assertEditorClosed(in: app)
        assertUserLabel(correctedLabel, in: app)
        assertReviewedQuote(in: app)
        assertOriginalEvidence(in: app)
        attach("screen-label-correction-keeps-original-quote", app)

        relaunchWithoutSeed(app)
        openWeekly(in: app)
        let corrected = context(correctedLabel, in: app)
        reveal(corrected, in: app)
        XCTAssertTrue(corrected.label.contains("Seen on 1 of 2 days with labeled samples"), corrected.debugDescription)
        let cedar = context("Cedar", in: app)
        reveal(cedar, in: app)
        XCTAssertTrue(cedar.label.contains("Seen on 2 of 2 days with labeled samples"), cedar.debugDescription)
        assertNoWeeklyContext("Lumen", in: app)
        tapContext(correctedLabel, in: app)
        openOnlyCitation(expectedQuote: reviewedQuote, in: app)
        assertUserLabel(correctedLabel, in: app)
        assertReviewedQuote(in: app)
        assertOriginalEvidence(in: app)

        openEditor(in: app)
        tap("sampleLabel.reset", in: app)
        assertEditorClosed(in: app)
        XCTAssertFalse(userLabel(in: app).exists, app.debugDescription)
        assertOriginalEvidence(in: app)
        XCTAssertFalse(app.staticTexts["observation.sample.userQuote.\(sampleID)"].exists, app.debugDescription)

        relaunchWithoutSeed(app)
        openWeekly(in: app)
        let restored = context("Lumen", in: app)
        reveal(restored, in: app)
        XCTAssertTrue(restored.label.contains("Seen on 1 of 2 days with labeled samples"), restored.debugDescription)
        assertNoWeeklyContext(correctedLabel, in: app)
        tapContext("Lumen", in: app)
        openOnlyCitation(in: app)
        XCTAssertFalse(userLabel(in: app).exists, app.debugDescription)
        assertOriginalEvidence(in: app)
        XCTAssertFalse(app.staticTexts["observation.sample.userQuote.\(sampleID)"].exists, app.debugDescription)
        attach("screen-label-reset-restores-proposal-after-relaunch", app)
    }

    func testExplicitUnknownSuppressesWeeklyLabelWithoutErasingSource() throws {
        let app = launchFixture()
        openWeeklySource(label: "Lumen", in: app)
        assertOriginalEvidence(in: app)
        openEditor(in: app)
        tap("sampleLabel.unknown", in: app)
        assertEditorClosed(in: app)
        assertUserLabel("Unknown screen", in: app)
        assertOriginalEvidence(in: app)

        relaunchWithoutSeed(app)
        openWeekly(in: app)
        let cedar = context("Cedar", in: app)
        reveal(cedar, in: app)
        XCTAssertTrue(cedar.label.contains("Seen on 2 of 2 days with labeled samples"), cedar.debugDescription)
        assertNoWeeklyContext("Lumen", in: app)

        // The suppressed label no longer has a recurrence link. Open its still-
        // retained sample through the ordinary observation archive instead.
        relaunchWithoutSeed(app)
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        tap(app.buttons["observation.row.\(sourceID)"], in: app)
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5), app.debugDescription)
        let prefix = "observation.timeline.\(sourceID)"
        let summary = app.staticTexts["\(prefix).summary"]
        reveal(summary, in: app)
        XCTAssertEqual(summary.label, "3 of 5 sampled moments labeled · 2 unresolved")
        tap(app.descendants(matching: .any).matching(identifier: "\(prefix).samples").firstMatch, in: app)
        let point = app.descendants(matching: .any).matching(identifier: "\(prefix).point.\(sampleID)").firstMatch
        reveal(point, in: app)
        XCTAssertTrue(point.label.contains("Unknown screen"), point.debugDescription)
        tap(point, in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 5), app.debugDescription)
        assertUserLabel("Unknown screen", in: app)
        assertOriginalEvidence(in: app)
        attach("screen-marked-unknown-keeps-originals-after-relaunch", app)
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-observation-review"]
        app.launch()
        return app
    }

    private func relaunchWithoutSeed(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-observation-review" }
        app.launch()
    }

    private func openWeekly(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.recordedPatterns", in: app)
        XCTAssertTrue(app.navigationBars["Observed mornings"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func context(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "review.recordings.context.", label)).firstMatch
    }

    private func openWeeklySource(label: String, in app: XCUIApplication) {
        openWeekly(in: app)
        tapContext(label, in: app)
        openOnlyCitation(in: app)
    }

    private func tapContext(_ label: String, in app: XCUIApplication) {
        tap(context(label, in: app), in: app)
        XCTAssertTrue(app.navigationBars["Source moments"].waitForExistence(timeout: 5), app.debugDescription)
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Seen on 1 distinct day.")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func openOnlyCitation(expectedQuote: String? = nil, in app: XCUIApplication) {
        let citationID = "review.recordings.citation.\(sourceID)|\(sampleID)"
        let citation = app.buttons.matching(identifier: citationID).firstMatch
        reveal(citation, in: app)
        if let expectedQuote {
            XCTAssertTrue(citation.label.contains(expectedQuote),
                          "The weekly source must show the user's chosen exact excerpt.\n\(citation.debugDescription)")
        }
        tap(citation, in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func openEditor(in app: XCUIApplication) {
        tap("observation.sample.correctLabel.\(sampleID)", in: app)
        XCTAssertTrue(app.navigationBars["Screen label"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.textFields["sampleLabel.text"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func replaceLabel(with text: String, in app: XCUIApplication) {
        let field = app.textFields["sampleLabel.text"]
        reveal(field, in: app)
        let oldValue = field.value as? String ?? ""
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + text)
        wait(field, predicate: NSPredicate(format: "value == %@", text), in: app)
    }

    private func assertEditorClosed(in app: XCUIApplication) {
        wait(app.navigationBars["Screen label"], predicate: NSPredicate(format: "exists == false"), in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func userLabel(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "observation.sample.userLabel.\(sampleID)").firstMatch
    }

    private func assertUserLabel(_ label: String, in app: XCUIApplication) {
        let value = userLabel(in: app)
        reveal(value, in: app)
        wait(value, predicate: NSPredicate(format: "value == %@", label), in: app)
    }

    private func assertOriginalEvidence(in app: XCUIApplication) {
        let quote = app.staticTexts["observation.sample.quote.\(sampleID)"]
        reveal(quote, in: app)
        XCTAssertEqual(quote.label, "Lumen", "A correction must not rewrite the original classifier quotation.")
        let original = app.staticTexts["observation.sample.originalText.\(sampleID)"]
        reveal(original, in: app)
        XCTAssertTrue(original.label.utf8.elementsEqual(originalText.utf8),
                      "Original OCR must stay byte-for-byte visible after review.\n\(original.debugDescription)")
    }

    private func assertReviewedQuote(in app: XCUIApplication) {
        let quote = app.staticTexts["observation.sample.userQuote.\(sampleID)"]
        reveal(quote, in: app)
        XCTAssertTrue(quote.label.utf8.elementsEqual(reviewedQuote.utf8), quote.debugDescription)
    }

    private func assertNoWeeklyContext(_ label: String, in app: XCUIApplication) {
        // The fixture has three bounded, collapsed partitions. Scan the list in
        // both directions so a virtualized off-screen row cannot appear absent.
        for direction in [false, true] {
            for _ in 0..<6 {
                XCTAssertFalse(context(label, in: app).exists, app.debugDescription)
                let list = visibleList(in: app)
                if direction { list.swipeDown() } else { list.swipeUp() }
            }
        }
        XCTAssertFalse(context(label, in: app).exists, app.debugDescription)
    }

    private func visibleList(in app: XCUIApplication) -> XCUIElement {
        // A list that is still sliding in exists but cannot be touched yet.
        // Wait for the screen to settle before deciding that none is visible.
        func candidates() -> [XCUIElement] {
            app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
                + app.scrollViews.allElementsBoundByIndex
        }
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            candidates().contains { $0.exists && $0.isHittable }
        }, object: nil)
        _ = XCTWaiter.wait(for: [settled], timeout: 5)
        guard let list = candidates().first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("No visible native list.\n\(app.debugDescription)")
            return app.collectionViews.firstMatch
        }
        return list
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 1)
        for _ in 0..<10 where !element.exists || !element.isHittable {
            let list = visibleList(in: app)
            if element.exists, element.frame.height > 0, element.frame.midY < list.frame.midY { list.swipeDown() }
            else { list.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        tap(app.buttons.matching(identifier: identifier).firstMatch, in: app)
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    private func wait(_ element: XCUIElement, predicate: NSPredicate, in app: XCUIApplication) {
        let condition = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 5), .completed, app.debugDescription)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        // Keep the synthetic visual check inspectable if Xcode's high-level
        // attachment report drops its references. This stays in the test runner.
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MOREScreenReviewScreenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        } catch {
            XCTFail("Could not retain the synthetic visual check: \(error)")
        }
    }
}
