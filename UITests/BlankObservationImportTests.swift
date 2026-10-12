import XCTest

/// Fault injection only: the controller stages a synthesized all-blank movie.
/// This proves failed-import preservation, not screen capture or activity recognition.
@MainActor
final class BlankObservationImportTests: XCTestCase {
    func testBlankMoviePreservesPreviousObservationAcrossRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_BLANK_OBSERVATION_TEST"] == "1",
              let supplied = environment["MO_RECORDED_OBSERVATION_WORKSPACE"],
              let workspaceID = UUID(uuidString: supplied) else {
            throw XCTSkip("Requires an explicitly staged BlankObservation.mov fault-test movie and an isolated workspace UUID.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        let baseArguments = ["--ui-testing", "--fixture-mode",
                             "--ui-testing-workspace=\(workspaceID.uuidString)"]
        let expected = "[Synthetic UI-test observation]\nI check my calendar, drink water, and enjoy ten minutes of chess."

        // Seed the last successful observation through the ordinary asynchronous importer.
        app.launchArguments = baseArguments + ["--ui-testing-import-observation"]
        app.launch()
        openLearn(in: app)
        assertNotes(expected, in: app)
        app.terminate()

        // Reuse the same workspace. The blank path must never inject substitute text.
        app.launchArguments = baseArguments + ["--ui-testing-import-blank-video"]
        app.launch()
        openLearn(in: app)
        let failure = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "No readable text was found in", "Your previous observation is unchanged.")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 120),
                      "The staged blank movie must reach the no-readable-text failure; missing media is not a pass.")
        assertNotes(expected, in: app)
        XCTAssertFalse(app.staticTexts["learn.videoEvidence"].exists,
                       "Failed video evidence must not replace the prior text observation.")
        reveal(failure, in: app)
        attach(app, name: "blank-movie-failure-keeps-previous-observation")
        app.terminate()

        // No import hook remains: the preserved observation must come from durable storage.
        app.launchArguments = baseArguments
        app.launch()
        openLearn(in: app)
        assertNotes(expected, in: app)
        XCTAssertFalse(app.staticTexts["learn.videoEvidence"].exists)
        reveal(app.textViews["learn.notes"], in: app)
        attach(app, name: "previous-observation-restored-after-blank-import")
    }

    private func openLearn(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 10))
    }

    private func assertNotes(_ expected: String, in app: XCUIApplication) {
        let editor = app.textViews["learn.notes"]
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            editor.value as? String == expected && editor.isEnabled
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed,
                       "The complete previous observation must remain editable and unchanged.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        for _ in 0..<6 where !element.isHittable { scroll.swipeUp() }
        if !element.isHittable {
            for _ in 0..<6 where !element.isHittable { scroll.swipeDown() }
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
