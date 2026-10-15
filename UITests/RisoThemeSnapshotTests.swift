import XCTest

/// Synthetic visual checks. Attachments contain only the isolated sample workspace.
/// Run on a phone or installed simulator; compiling these does not execute them.
@MainActor
final class RisoThemeSnapshotTests: XCTestCase {
    func testMorningAndRunningRoutineAcrossAllDayPhases() {
        for phase in ["dawn", "morning", "day", "evening", "night"] {
            let app = launch(phase: phase, dark: phase == "night")
            XCTAssertTrue(app.buttons["morning.step.0"].waitForExistence(timeout: 10))
            attach("riso-\(phase)-home", app)
            MorningUITestNavigation.revealMorningAction("run.start", in: app)
            app.buttons["run.start"].tap()
            XCTAssertTrue(app.buttons["morning.confirmStart"].waitForExistence(timeout: 5))
            app.buttons["morning.confirmStart"].tap()
            MorningUITestNavigation.chooseRoutineAtOpening(in: app)
            XCTAssertTrue(app.staticTexts["run.step"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 10))
            attach("riso-\(phase)-running", app)
            app.terminate()
        }
    }

    func testMainScreensInLightAndFrenchDarkAppearance() {
        for dark in [false, true] {
            let name = dark ? "night-fr-dark" : "day-en-light"
            let app = launch(phase: dark ? "night" : "day", dark: dark, empty: true, french: dark)
            XCTAssertTrue(app.buttons["learn.begin"].waitForExistence(timeout: 10))
            attach("riso-\(name)-first-use", app)
            MorningUITestNavigation.revealMorningAction("morning.learn", in: app)
            app.buttons["morning.learn"].tap()
            XCTAssertTrue(app.buttons["learn.import"].waitForExistence(timeout: 5))
            attach("riso-\(name)-learn", app)
            app.terminate()

            app.launchArguments.removeAll { $0 == "--ui-testing-empty-workspace" }
            app.launchArguments.append("--ui-testing-approved")
            app.launch()
            MorningUITestNavigation.revealMorningAction("morning.settings", in: app)
            app.buttons["morning.settings"].tap()
            XCTAssertTrue(app.buttons["setup.briefing"].waitForExistence(timeout: 5))
            attach("riso-\(name)-settings", app)
            app.buttons["setup.briefing"].tap()
            let city = app.textFields["briefing.citySearch"]
            for _ in 0..<12 where !(city.exists && city.isHittable) { app.swipeUp() }
            XCTAssertTrue(city.exists && city.isHittable)
            attach("riso-\(name)-brief", app)
            app.terminate()
            app.launch()
            MorningUITestNavigation.revealMorningAction("morning.settings", in: app)
            app.buttons["morning.settings"].tap()
            let privacy = app.buttons["setup.privacy"]
            for _ in 0..<6 where !privacy.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(privacy.isHittable)
            privacy.tap()
            // The destructive control is a lazily created row far below the fold.
            // Verify the inventory that this screenshot actually shows.
            let inventory = app.descendants(matching: .any).matching(identifier: "privacy.observations").firstMatch
            XCTAssertTrue(inventory.waitForExistence(timeout: 5))
            attach("riso-\(name)-privacy", app)
            app.terminate()
            app.launch()
            app.buttons["morning.date"].tap()
            XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5))
            attach("riso-\(name)-review", app)
            app.terminate()
        }
    }

    private func launch(phase: String, dark: Bool, empty: Bool = false, french: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-briefing-fixture", "--theme-phase=\(phase)",
            dark ? "--dark-preview" : "--light-preview",
            empty ? "--ui-testing-empty-workspace" : "--ui-testing-approved",
            "--ui-testing-workspace=\(UUID().uuidString)",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"]
        app.launch()
        return app
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let settled = expectation(description: "Theme presentation settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MO_THEME_SCREENSHOT_DIR"] {
            do {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"), options: .atomic)
            } catch { XCTFail("Could not save synthetic theme screenshot: \(error)") }
        }
    }
}
