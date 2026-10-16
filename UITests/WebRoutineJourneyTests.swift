import XCTest

/// Exercises the saved routine/editor/browser path with synthetic data. It never
/// signs in, reads an account, or opens a third-party native app.
@MainActor
final class WebRoutineJourneyTests: XCTestCase {
    func testSavedInstagramRoutesStartAdvanceAndReopenInsideMOREInBothLanguages() throws {
        continueAfterFailure = false
        for language in ["en", "fr"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
                "--ui-testing-instagram-routing", "--ui-testing-briefing-fixture",
                "--ui-testing-workspace=\(UUID().uuidString)", "--light-preview", "--theme-phase=morning",
                "-more.appLanguage", language, "-AppleLanguages", "(\(language))",
                "-AppleLocale", language == "fr" ? "fr_FR" : "en_US"]
            MorningUITestNavigation.launch(app)
            defer { app.terminate() }
            MorningUITestNavigation.tapButton("run.start", in: app)
            let about = app.buttons["web.aboutDone"]
            if about.waitForExistence(timeout: 5) { about.tap() }
            XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(app.staticTexts["web.host"].label, "www.instagram.com")
            XCTAssertEqual(app.state, .runningForeground)
            app.buttons["web.nextMoment"].tap()
            XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(app.staticTexts["web.host"].label, "www.instagram.com")
            app.buttons["web.close"].tap()
            XCTAssertTrue(app.buttons["web.close"].waitForNonExistence(timeout: 5))
            MorningUITestNavigation.assertSession(state: "running", step: "SYNTHETIC Instagram profile", in: app)
            MorningUITestNavigation.openSettings(in: app)
            MorningUITestNavigation.tapButton("stepTimer.openPage", in: app)
            XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(app.staticTexts["web.host"].label, "www.instagram.com")
            XCTAssertEqual(app.state, .runningForeground)
            attach("instagram-saved-routine-\(language)", app)
        }
    }

    func testWebMomentKeepsItsExtendedBudgetAcrossCloseAndReopen() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
            "--ui-testing-briefing-fixture", "--ui-testing-workspace=\(UUID().uuidString)",
            "--light-preview", "--theme-phase=morning", "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        MorningUITestNavigation.openRoutine(in: app)
        let first = app.buttons["routine.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let target = app.buttons["step.targetApp"]
        reveal(target, in: app)
        target.tap()
        let site = app.buttons["Le Monde"].firstMatch
        XCTAssertTrue(site.waitForExistence(timeout: 5), app.debugDescription)
        site.tap()
        app.buttons["step.save"].tap()
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5), app.debugDescription)
        approve.tap()
        MorningUITestNavigation.tapButton("run.start", in: app)
        let about = app.buttons["web.aboutDone"]
        if about.waitForExistence(timeout: 5) { about.tap() }
        XCTAssertTrue(app.otherElements["web.page"].waitForExistence(timeout: 10)
            || app.webViews["web.page"].exists, app.debugDescription)
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.lemonde.fr")
        let before = try remaining("web.remaining", in: app)
        let beforeEnd = Date().addingTimeInterval(TimeInterval(before))
        app.buttons["web.extend"].tap()
        var increased = false
        for _ in 0..<20 {
            let value = try remaining("web.remaining", in: app)
            if Date().addingTimeInterval(TimeInterval(value)).timeIntervalSince(beforeEnd) > 110 {
                increased = true; break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertTrue(increased)
        let extended = try remaining("web.remaining", in: app)
        let extendedEnd = Date().addingTimeInterval(TimeInterval(extended))
        XCTAssertEqual(extendedEnd.timeIntervalSince(beforeEnd), 120, accuracy: 8)
        app.buttons["web.close"].tap()
        XCTAssertTrue(app.buttons["web.close"].waitForNonExistence(timeout: 5))
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        let closed = try XCTUnwrap(Int(MorningUITestNavigation.sessionSnapshot(in: app)["remaining"] ?? ""),
            "The current routine timer must remain available after closing the browser.")
        let closedEnd = Date().addingTimeInterval(TimeInterval(closed))
        XCTAssertEqual(closedEnd.timeIntervalSince(extendedEnd), 0, accuracy: 8)
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("stepTimer.openPage", in: app)
        XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 5))
        let reopened = try remaining("web.remaining", in: app)
        let reopenedEnd = Date().addingTimeInterval(TimeInterval(reopened))
        XCTAssertEqual(reopenedEnd.timeIntervalSince(closedEnd), 0, accuracy: 8)
        attach("web-routine-extended-and-reopened", app)
        app.buttons["web.nextMoment"].tap()
        XCTAssertTrue(app.buttons["web.nextMoment"].waitForNonExistence(timeout: 5))
        MorningUITestNavigation.assertSession(state: "running", step: "People and messages", in: app)
        MorningUITestNavigation.openSettings(in: app)
        XCTAssertFalse(app.buttons["stepTimer.openPage"].exists,
                       "Advancing must remove the previous web moment's reopening action.")
        attach("web-routine-next-step", app)
    }

    private func remaining(_ identifier: String, in app: XCUIApplication) throws -> Int {
        let value = app.staticTexts[identifier]
        XCTAssertTrue(value.waitForExistence(timeout: 5), app.debugDescription)
        let pieces = value.label.split(separator: ":").compactMap { Int($0) }
        return try XCTUnwrap(pieces.count == 2 ? pieces[0] * 60 + pieces[1] : nil,
            "Expected a minute:second countdown, got \(value.label)")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
