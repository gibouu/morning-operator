import XCTest

/// Experimental owner-assisted test. The person confirms Apple's picker; XCTest never grants access.
/// Foreground state and hittability are necessary checks, not proof that the system picker is absent.
/// App screenshots and underlying recording controls cannot establish unobscured system consent.
/// Verify the complete flow manually in the ordinary app before claiming hardware recording works.
@MainActor
final class RecordingLearningTests: XCTestCase {
    func testOwnerApprovedShortRecordingProducesReviewableText() throws {
        guard ProcessInfo.processInfo.environment["MO_RECORDING_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Enable this owner-assisted recording test explicitly; the person must confirm Apple's picker.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()
        try tap("learn.refine", in: app)
        try tap("learn.record", in: app)
        try tap("record.start", in: app)
        // The owner confirms the system capture scope with only harmless content visible.
        // The app currently uses the full-display picker; this test does not narrow its scope.
        let stop = app.buttons["record.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 180), "The owner must confirm Apple's picker, and recording must actually start.")
        try requireForegroundAndHittable(stop, in: app)
        let elapsed = expectation(description: "Record a short visible sample")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 8)
        try requireForegroundAndHittable(stop, in: app)
        stop.tap()
        let review = app.buttons["observation.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 180), "The finalized recording must finish local extraction; no fixture fallback.")
        try requireForegroundAndHittable(review, in: app)
        attach("recording-analysis-finished", app: app)
        review.tap()
        let notes = app.textViews["learn.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        let extracted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let text = notes.value as? String else { return false }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20
        }, object: notes)
        XCTAssertEqual(XCTWaiter.wait(for: [extracted], timeout: 90), .completed,
                       "The actual recording must yield reviewable Vision OCR text; no fixture fallback.")
        attach("recording-extracted-text-needs-review", app: app)
        XCTAssertTrue(app.buttons["learn.analyze"].exists, "The observed text remains available to review after automatic processing.")
    }

    private func tap(_ identifier: String, in app: XCUIApplication) throws {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<5 where !button.isHittable {
            let sheet = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
            if sheet.exists { sheet.swipeUp() } else { app.scrollViews.firstMatch.swipeUp() }
        }
        try requireForegroundAndHittable(button, in: app)
        button.tap()
    }

    private func requireForegroundAndHittable(_ element: XCUIElement, in app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) throws {
        _ = try XCTUnwrap(app.state == .runningForeground ? true : nil,
                         "Refusing a recording-flow tap while Morning Operator is not foreground. Complete the experimental flow manually; recording may still be active.",
                         file: file, line: line)
        _ = try XCTUnwrap(element.isHittable ? true : nil,
                         "Refusing a recording-flow tap because the target is not hittable. This does not validate system consent or picker dismissal; check the device manually.",
                         file: file, line: line)
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
