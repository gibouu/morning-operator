import XCTest

/// Imports an actual, separately recorded fixture-app movie through the ordinary importer.
/// The recorder/controller must stage the movie first. No action log is passed to the app.
@MainActor
final class RecordedObservationImportTests: XCTestCase {
    func testRecordedMovieEvidencePersistsAndEditingInvalidatesIt() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_RECORDED_OBSERVATION_TEST"] == "1",
              let supplied = environment["MO_RECORDED_OBSERVATION_WORKSPACE"],
              let workspaceID = UUID(uuidString: supplied) else {
            throw XCTSkip("Requires an explicitly staged, real fixture-app recording and an isolated workspace UUID.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode",
            "--ui-testing-workspace=\(workspaceID.uuidString)", "--ui-testing-import-recorded-video"]
        app.launch()
        openLearn(in: app)
        let editor = app.textViews["learn.notes"]
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = editor.value as? String ?? ""
            return text.contains("Cedar Mail") && text.contains("Lumen Calendar") && editor.isEnabled
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 120), .completed,
                       "Both independent fixture-app headings must be extracted from the actual movie.")
        let original = try XCTUnwrap(editor.value as? String)
        let summary = app.staticTexts["learn.videoEvidence"]
        reveal(summary, in: app)
        XCTAssertTrue(summary.exists)
        XCTAssertTrue(summary.label.contains("samples"))
        let originalSummary = summary.label
        attach(app, name: "recorded-movie-evidence-imported")

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-import-recorded-video" }
        app.launch()
        openLearn(in: app)
        XCTAssertEqual(editor.value as? String, original)
        reveal(summary, in: app)
        XCTAssertEqual(summary.label, originalSummary, "Frame metadata must survive without reimporting the movie.")

        reveal(editor, in: app)
        editor.tap()
        editor.typeText(" User correction.")
        let edited = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(edited.contains("User correction."))
        XCTAssertFalse(summary.exists, "Edited prose must lose the original sampled-frame association.")
        if app.buttons["input.done"].exists { app.buttons["input.done"].tap() }
        app.navigationBars["Learn my morning"].buttons["Done"].tap()
        app.terminate()
        app.launch()
        openLearn(in: app)
        XCTAssertEqual(editor.value as? String, edited)
        XCTAssertFalse(summary.exists)
        let clear = app.buttons["learn.clear"]
        reveal(clear, in: app)
        clear.tap()
        app.terminate()
        app.launch()
        openLearn(in: app)
        XCTAssertEqual(editor.value as? String ?? "", "")
        XCTAssertFalse(summary.exists)
        XCTAssertFalse(clear.exists)
        attach(app, name: "recorded-movie-evidence-cleared-after-relaunch")
    }

    private func openLearn(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        for _ in 0..<5 where !element.isHittable { scroll.swipeUp() }
        if !element.isHittable {
            for _ in 0..<5 where !element.isHittable { scroll.swipeDown() }
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
