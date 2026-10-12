import XCTest

/// Isolated synthetic routine only. These checks do not start recording or grant permissions.
@MainActor
final class SunriseDockTests: XCTestCase {
    func testCenteredSunriseExpandsToFourActionsAndBackgroundDismisses() {
        let app = launch(approved: true)
        let sunrise = app.buttons["morning.actions"]
        XCTAssertTrue(sunrise.waitForExistence(timeout: 10))
        XCTAssertEqual(sunrise.frame.midX, app.frame.midX, accuracy: 3)
        XCTAssertGreaterThanOrEqual(sunrise.frame.width, 64)
        XCTAssertGreaterThanOrEqual(sunrise.frame.height, 64)
        XCTAssertGreaterThan(sunrise.frame.minY, app.frame.height * 0.65)
        XCTAssertFalse(app.buttons["run.start"].exists)
        attach("more-centered-sunrise", app)
        sunrise.tap()
        let identifiers = ["run.start", "morning.learn", "morning.review", "morning.settings"]
        let actions = identifiers.map { app.buttons[$0] }
        for action in actions { XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(action.isHittable) }
        XCTAssertEqual(actions.map(\.label), ["Play", "Learn", "History", "Settings"])
        XCTAssertFalse(app.buttons["morning.update"].exists)
        XCTAssertEqual(app.popovers.count, 0, "The dock expands in place, without a popover.")
        for action in actions.dropFirst() { XCTAssertEqual(action.frame.midY, actions[0].frame.midY, accuracy: 3) }
        XCTAssertLessThan(actions[0].frame.midX, actions[1].frame.midX)
        XCTAssertLessThan(actions[1].frame.midX, actions[2].frame.midX)
        XCTAssertLessThan(actions[2].frame.midX, actions[3].frame.midX)
        assertCompactActions(in: app)
        attach("more-horizontal-sunrise-actions", app)
        app.buttons["morning.closeActions"].tap()
        XCTAssertTrue(sunrise.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.start"].exists)
        XCTAssertTrue(app.buttons["morning.date"].isHittable)
    }

    func testDockPlayPauseContinueAndLearnSettingsRoutes() {
        let app = launch(approved: true)
        reveal("morning.learn", in: app)
        app.buttons["morning.learn"].tap()
        XCTAssertTrue(app.navigationBars["Learn my morning"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        app.navigationBars["Learn my morning"].buttons["Done"].tap()
        reveal("morning.settings", in: app)
        app.buttons["morning.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Done"].tap()
        reveal("run.start", in: app)
        app.buttons["run.start"].tap()
        XCTAssertTrue(app.staticTexts["morning.ready"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.pause"].exists, "Play opens a ready state; it must not begin automatically.")
        app.buttons["morning.cancelStart"].tap()
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
        app.buttons["run.start"].tap()
        XCTAssertTrue(app.buttons["morning.confirmStart"].waitForExistence(timeout: 5))
        app.buttons["morning.confirmStart"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        reveal("morning.playback", in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Pause")
        XCTAssertFalse(app.buttons["morning.learn"].isEnabled)
        app.buttons["morning.playback"].tap()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 5))
        reveal("morning.playback", in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Continue")
        app.buttons["morning.playback"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testDraftDockOpensReviewWithoutStartingOrApproving() {
        let app = launch(approved: false)
        reveal("morning.reviewDraft", in: app)
        XCTAssertEqual(app.buttons["morning.reviewDraft"].label, "Review")
        XCTAssertFalse(app.buttons["run.start"].exists)
        app.buttons["morning.reviewDraft"].tap()
        XCTAssertTrue(app.navigationBars["Your routine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        XCTAssertFalse(app.buttons["run.pause"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testSunriseDesignOptions() {
        continueAfterFailure = false
        let workspaceID = UUID()
        let app = XCUIApplication()
        let designs = ["horizon", "halo", "radiance", "ember"]

        // One real, approved sample is reused across every appearance. The
        // workspace UUID isolates this from the owner's data and other tests.
        for (index, design) in designs.enumerated() {
            for dark in [false, true] {
                app.launchArguments = [
                    "--ui-testing", "--ui-testing-empty-workspace", "--fixture-mode",
                    "--ui-testing-workspace=\(workspaceID.uuidString)",
                    "--sunrise-design=\(design)", dark ? "--dark-preview" : "--light-preview",
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
                ]
                app.launch()
                if index == 0 && !dark {
                    let sample = app.buttons["routine.sample"]
                    XCTAssertTrue(sample.waitForExistence(timeout: 10), app.debugDescription)
                    sample.tap()
                    MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
                    app.buttons["morning.reviewDraft"].tap()
                    let approve = app.buttons["routine.approve"]
                    XCTAssertTrue(approve.waitForExistence(timeout: 5), app.debugDescription)
                    approve.tap()
                    MorningUITestNavigation.selectTab("Morning", in: app)
                }

                let sunrise = app.buttons["morning.actions"]
                XCTAssertTrue(sunrise.waitForExistence(timeout: 10), app.debugDescription)
                XCTAssertTrue(sunrise.isHittable, app.debugDescription)
                XCTAssertGreaterThanOrEqual(sunrise.frame.width, 64)
                XCTAssertGreaterThanOrEqual(sunrise.frame.height, 64)
                XCTAssertEqual(sunrise.frame.midX, app.frame.midX, accuracy: 3)
                let first = app.buttons["morning.step.0"]
                XCTAssertTrue(first.label.contains("Calendar & weather"), app.debugDescription)
                XCTAssertTrue(app.buttons["morning.step.7"].label.contains("A thought for later"), app.debugDescription)
                XCTAssertFalse(app.buttons["morning.step.8"].exists)
                XCTAssertFalse(app.staticTexts["morning.draft"].exists)
                XCTAssertFalse(app.buttons["run.pause"].exists)
                let appearance = dark ? "dark" : "light"
                attach("more-sunrise-\(design)-\(appearance)-closed", app)

                sunrise.tap()
                assertCompactActions(in: app)
                XCTAssertEqual(app.buttons["run.start"].label, "Play")
                XCTAssertFalse(app.buttons["morning.confirmStart"].exists,
                               "Opening the dock must not open Ready or start the sample.")
                attach("more-sunrise-\(design)-\(appearance)-expanded", app)
                app.buttons["morning.closeActions"].tap()
                XCTAssertTrue(sunrise.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertFalse(app.buttons["run.start"].exists)
                XCTAssertFalse(app.buttons["run.pause"].exists)
                app.terminate()
            }
        }
    }

    /// This union measures the controls, not a decorative glass/shadow pixel box.
    /// Run at the simulator's normal text size; accessibility layouts may scroll.
    private func assertCompactActions(in app: XCUIApplication,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let identifiers = ["run.start", "morning.learn", "morning.review", "morning.settings"]
        var bounds = CGRect.null
        var previousCenterX: CGFloat?
        var centerY: CGFloat?
        for identifier in identifiers {
            let action = app.buttons[identifier]
            XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
            XCTAssertTrue(action.isHittable, app.debugDescription, file: file, line: line)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44, identifier, file: file, line: line)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44, identifier, file: file, line: line)
            if let previousCenterX { XCTAssertGreaterThan(action.frame.midX, previousCenterX, identifier, file: file, line: line) }
            if let centerY { XCTAssertEqual(action.frame.midY, centerY, accuracy: 3, identifier, file: file, line: line) }
            previousCenterX = action.frame.midX
            centerY = action.frame.midY
            bounds = bounds.union(action.frame)
        }
        XCTAssertLessThanOrEqual(bounds.width, 300, "The normal-size control row should stay compact.", file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.height, 64, "Controls preserve touch targets without a tall bar.", file: file, line: line)
        XCTAssertEqual(bounds.midX, app.frame.midX, accuracy: 3, file: file, line: line)
    }

    private func launch(approved: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
                               "--ui-testing-workspace=\(UUID().uuidString)"]
        if approved { app.launchArguments.append("--ui-testing-approved") }
        app.launch()
        return app
    }

    private func reveal(_ identifier: String, in app: XCUIApplication) {
        let sunrise = app.buttons["morning.actions"]
        XCTAssertTrue(sunrise.waitForExistence(timeout: 5))
        sunrise.tap()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[identifier].isHittable)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            // Independent copies survive the known xcresult attachment-export
            // issue. This is the test runner's container, never the app's store.
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let directory = documents.appendingPathComponent("MORESunriseDesignScreenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        } catch { XCTFail("Could not retain the synthetic dock screenshot: \(error)") }
    }
}
