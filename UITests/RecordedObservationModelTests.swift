import XCTest

/// Attempts real on-device screen-context inference on a separately recorded fixture movie.
/// Completion is not an accuracy score; unknown classifications remain valid model output.
@MainActor
final class RecordedObservationModelTests: XCTestCase {
    func testRecordedMovieScreenRecognitionCompletesWhenModelIsAvailable() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_RECORDED_OBSERVATION_MODEL"] == "1",
              let supplied = environment["MO_RECORDED_OBSERVATION_WORKSPACE"],
              let workspaceID = UUID(uuidString: supplied) else {
            throw XCTSkip("Requires explicit model-test opt-in, a staged real fixture-app recording, and an isolated workspace UUID.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode",
            "--ui-testing-workspace=\(workspaceID.uuidString)", "--ui-testing-import-recorded-video"]
        app.launch()
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let editor = app.textViews["learn.notes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = editor.value as? String ?? ""
            return text.contains("Cedar Mail") && text.contains("Lumen Calendar") && editor.isEnabled
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 120), .completed,
                       "Both fixture headings must come from OCR of the staged movie, with no substitute notes.")

        let details = app.buttons["See sampled screens"]
        reveal(details, in: app)
        details.tap()
        let recognize = app.buttons["learn.recognizeScreens"]
        reveal(recognize, in: app)
        XCTAssertTrue(recognize.isEnabled, "The real imported samples must be eligible for an explicit recognition attempt.")
        // No catalog, expected identities, or action-truth log is supplied to the app.
        recognize.tap()
        let status = app.staticTexts["learn.contextStatus"]
        let finished = status.waitForExistence(timeout: 180)
        if finished { reveal(status, in: app) }
        attach(app, name: "recorded-movie-screen-recognition-outcome")
        XCTAssertTrue(finished, "The actual recognition attempt must report its outcome within 180 seconds.")
        let outcome = status.label
        let text = XCTAttachment(string: outcome)
        text.name = "recorded-movie-screen-recognition-status"
        text.lifetime = .keepAlways
        add(text)
        XCTAssertFalse(app.buttons["learn.retrySave"].exists,
                       "Recognition output must be saved before the workspace is inspected.")

        if outcome == "On-device screen recognition is unavailable. The saved samples are still here." {
            throw XCTSkip("The attempted recording classification reported local model unavailability. Saved unknown output is retained for inspection; no inference completion is claimed.")
        }
        XCTAssertEqual(outcome, "On-device recognition finished. Unclear screens remain unknown.",
                       "Failed, partially failed, or ineligible analysis is a failure, not an unavailable-model skip.")
        // Leave the complete observation and classifier result intact for independent review.
        // Even all-unknown output can satisfy completion; accuracy is evaluated separately.
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        for _ in 0..<8 where !element.isHittable { scroll.swipeUp() }
        if !element.isHittable {
            for _ in 0..<8 where !element.isHittable { scroll.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
