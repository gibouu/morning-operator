import XCTest

/// The controller stages a fixture-app movie and explicitly synthetic session metadata.
/// This exercises real recovery/OCR/persistence, not native capture or a human morning.
@MainActor
final class RecordingProvenanceTests: XCTestCase {
    func testRecoveredMovieKeepsStartAfterObservedDayIsRemoved() throws {
        let app = try launch(workspaceKey: "MO_RECORDING_PROVENANCE_WORKSPACE")
        MorningUITestNavigation.selectTab("Review", in: app)
        MorningUITestNavigation.tapButton("record.retryImport", in: app)
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let editor = app.textViews["learn.notes"]
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = editor.value as? String ?? ""
            return text.contains("Cedar Mail") && text.contains("Lumen Calendar") && editor.isEnabled
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 120), .completed,
                       "Both independent fixture-app headings must be extracted from the staged movie.")
        app.navigationBars["Learn my morning"].buttons["Done"].tap()
        XCTAssertFalse(app.buttons["record.retryImport"].exists)
        openOnlyObservation(in: app)
        reveal(app.buttons["Recording details"], in: app).tap()
        let start = app.descendants(matching: .any).matching(identifier: "observation.recordingStart").firstMatch
        reveal(start, in: app)
        let originalStart = try XCTUnwrap(start.value as? String)
        XCTAssertFalse(originalStart.isEmpty)
        let zone = app.descendants(matching: .any).matching(identifier: "observation.recordingTimeZone").firstMatch
        XCTAssertTrue(zone.exists)
        attach("recording-start-separate-from-observed-day", app)

        MorningUITestNavigation.tapButton("observation.setDate", in: app)
        MorningUITestNavigation.tapButton("observation.removeDate", in: app)
        let day = app.descendants(matching: .any).matching(identifier: "observation.observedDate").firstMatch
        let undated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Date needed"), object: day)
        XCTAssertEqual(XCTWaiter.wait(for: [undated], timeout: 5), .completed)
        app.terminate()
        app.launch()
        openOnlyObservation(in: app)
        XCTAssertEqual(day.value as? String, "Date needed")
        reveal(app.buttons["Recording details"], in: app).tap()
        reveal(start, in: app)
        XCTAssertEqual(start.value as? String, originalStart,
                       "The immutable start must survive removing the review date and relaunching.")
        XCTAssertFalse(app.buttons["record.retryImport"].exists)
        attach("recording-start-restored-without-assigned-day", app)
    }

    func testUnreadableRecoveryMetadataKeepsRecordingAfterRetryAndRelaunch() throws {
        let app = try launch(workspaceKey: "MO_CORRUPT_RECORDING_METADATA_WORKSPACE")
        MorningUITestNavigation.selectTab("Review", in: app)
        let retry = app.buttons["record.retryImport"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        MorningUITestNavigation.tapButton("record.retryImport", in: app)
        let issue = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Your recording has not been imported or discarded.")).firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.exists && retry.isEnabled)
        XCTAssertTrue(app.buttons["record.discardPending"].exists)
        app.terminate()
        app.launch()
        MorningUITestNavigation.selectTab("Review", in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "its saved information could not be read")).firstMatch.exists)
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        XCTAssertTrue(app.staticTexts["No saved observations"].waitForExistence(timeout: 5),
                       "A damaged sidecar must not be silently imported with unknown provenance.")
        attach("unreadable-recording-metadata-preserves-recovery", app)
    }

    private func launch(workspaceKey: String) throws -> XCUIApplication {
        guard let value = ProcessInfo.processInfo.environment[workspaceKey], let id = UUID(uuidString: value) else {
            throw XCTSkip("Requires a controller-staged recording recovery workspace with explicit synthetic provenance.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-empty-workspace",
                               "--light-preview", "--ui-testing-workspace=\(id.uuidString)"]
        app.launch()
        return app
    }

    private func openOnlyObservation(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        reveal(rows.firstMatch, in: app).tap()
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5))
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<8 where !element.isHittable {
            let container = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
            XCTAssertTrue(container.exists)
            if element.exists && element.frame.height > 0 && element.frame.midY < container.frame.midY { container.swipeDown() }
            else { container.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
        return element
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
