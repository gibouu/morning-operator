import XCTest

/// Isolated sample routines and permission explanations; no external account effects.
@MainActor
final class MorningBrandingTests: XCTestCase {
    func testWordmarkSurvivesNavigationAndVoiceSheetsInEnglishDayAndFrenchNight() {
        for night in [false, true] {
            let app = launchFixture(night: night, french: night, largestText: night)
            let appearance = night ? "night" : "day"
            assertBrand(appearance, in: app)
            attach("brand-\(appearance)-home", app)

            MorningUITestNavigation.openSettings(in: app)
            assertBrand(appearance, in: app)
            let routine = settingsButton("setup.routine", in: app)
            routine.tap()
            XCTAssertTrue(element("routine.editor", in: app).waitForExistence(timeout: 5))
            assertBrand(appearance, in: app)
            attach("brand-\(appearance)-routine", app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(element("settings.appearance", in: app).waitForExistence(timeout: 5))
            assertBrand(appearance, in: app)

            settingsButton("setup.voice", in: app).tap()
            XCTAssertTrue(app.buttons["voice.done"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["voice.gender.female"].exists)
            assertBrand(appearance, in: app)
            attach("brand-\(appearance)-voice-sheet", app)
            app.buttons["voice.done"].tap()
            XCTAssertTrue(element("settings.appearance", in: app).waitForExistence(timeout: 5))
            assertBrand(appearance, in: app)
            MorningUITestNavigation.selectTab("Morning", in: app)
            assertBrand(appearance, in: app)
            app.terminate()
        }
    }

    func testFrenchLargestNightBrandPersistsThroughPauseResumeAndHiddenControls() {
        let app = launchFixture(night: true, french: true, largestText: true)
        defer { app.terminate() }
        MorningUITestNavigation.tapButton("run.start", in: app)
        XCTAssertTrue(app.staticTexts["morning.caption"].waitForExistence(timeout: 8))
        assertBrand("night", in: app)
        let brandFrame = element("brand.wordmark", in: app).frame
        MorningUITestNavigation.revealControls(in: app)
        let playback = app.buttons["morning.playback"]
        XCTAssertTrue(playback.isHittable)
        XCTAssertFalse(brandFrame.intersects(playback.frame))
        playback.tap()
        assertPlaybackLabel("Continuer", in: app)
        assertBrand("night", in: app)
        attach("brand-night-french-largest-paused", app)
        playback.tap()
        assertPlaybackLabel("Pause", in: app)
        assertBrand("night", in: app)
        XCTAssertTrue(playback.waitForNonExistence(timeout: 8), "Playback controls hide after inactivity.")
        XCTAssertFalse(app.buttons["morning.settings"].exists)
        assertBrand("night", in: app)
        XCTAssertEqual(element("brand.wordmark", in: app).frame, brandFrame,
                       "Pausing and hiding controls must not move the logo.")
        attach("brand-night-french-largest-controls-hidden", app)
    }

    func testForegroundReturnRefreshesTheSameBrandInAnOpenSheetSettingsAndHome() {
        let app = launchFixture(extra: ["--ui-testing-brand-night-on-return"])
        defer { app.terminate() }
        assertBrand("day", in: app)
        MorningUITestNavigation.openSettings(in: app)
        settingsButton("setup.voice", in: app).tap()
        XCTAssertTrue(app.buttons["voice.done"].waitForExistence(timeout: 5))
        assertBrand("day", in: app)
        attach("brand-day-before-background-voice-sheet", app)

        XCUIDevice.shared.press(.home)
        let background = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "state == %d", XCUIApplication.State.runningBackground.rawValue), object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 10), .completed)
        app.activate()
        XCTAssertTrue(app.buttons["voice.done"].waitForExistence(timeout: 5),
                      "Returning keeps the current sheet and its controls.")
        assertBrand("night", in: app)
        attach("brand-night-after-foreground-voice-sheet", app)
        app.buttons["voice.done"].tap()
        XCTAssertTrue(element("settings.appearance", in: app).waitForExistence(timeout: 5))
        assertBrand("night", in: app)
        XCTAssertEqual(element("settings.appearance", in: app).value as? String, "night")
        MorningUITestNavigation.selectTab("Morning", in: app)
        assertBrand("night", in: app)
        attach("brand-night-after-foreground-home", app)
    }

    func testOnboardingAndPermissionHeadersUseTheSameDayNightArtwork() {
        for night in [false, true] {
            let appearance = night ? "night" : "day"
            let intro = application(night: night, french: night, largestText: night,
                                    flags: ["--preview-onboarding"])
            intro.launch()
            XCTAssertTrue(intro.staticTexts["onboarding.heading"].waitForExistence(timeout: 10))
            assertBrand(appearance, identifier: "onboarding.brand", in: intro)
            attach("brand-\(appearance)-onboarding", intro)
            settingsButton("onboarding.next", in: intro).tap()
            assertBrand(appearance, identifier: "onboarding.brand", in: intro)
            intro.terminate()

            let permissions = application(night: night, french: night, largestText: night,
                flags: ["--fixture-mode", "--ui-testing-empty-workspace", "--ui-testing-permissions"])
            MorningUITestNavigation.launch(permissions)
            XCTAssertTrue(permissions.staticTexts["permissions.title.summary"].waitForExistence(timeout: 5))
            assertBrand(appearance, identifier: "permissions.brand", in: permissions)
            XCTAssertEqual(permissions.alerts.count, 0, "This journey uses synthetic permission explanations.")
            attach("brand-\(appearance)-permissions", permissions)
            permissions.terminate()
        }
    }

    private func launchFixture(night: Bool = false, french: Bool = false, largestText: Bool = false,
                               extra: [String] = []) -> XCUIApplication {
        let app = application(night: night, french: french, largestText: largestText,
            flags: ["--fixture-mode", "--ui-testing-approved", "--ui-testing-automation", "--ui-testing-hands-free"] + extra)
        MorningUITestNavigation.launch(app)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        return app
    }

    private func application(night: Bool, french: Bool, largestText: Bool,
                             flags: [String]) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--theme-phase=\(night ? "night" : "day")",
            "--ui-testing-reduce-motion", "--ui-testing-workspace=\(UUID().uuidString)",
            "-more.appLanguage", french ? "fr" : "en", "-AppleLanguages", french ? "(fr)" : "(en)",
            "-AppleLocale", french ? "fr_FR" : "en_US"] + flags
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertBrand(_ appearance: String, identifier: String = "brand.wordmark", in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        let brand = element(identifier, in: app)
        XCTAssertTrue(brand.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        let french = app.launchArguments.contains("fr")
        let phaseLabel = appearance == "night" ? (french ? "Nuit" : "Night") : (french ? "Jour" : "Day")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phaseLabel), object: brand)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, file: file, line: line)
        XCTAssertEqual(brand.label, "MORE", file: file, line: line)
        let frame = brand.frame
        XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
        let maximumHeight = identifier == "onboarding.brand" ? 44.5 : 32.5
        XCTAssertLessThanOrEqual(frame.height, maximumHeight, "The logo stays compact at the largest text size.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, app.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, app.frame.maxY, file: file, line: line)
    }

    private func settingsButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<14 where !button.exists || !button.isHittable {
            let form = app.collectionViews.firstMatch
            let scroll = form.exists ? form : app.scrollViews.firstMatch
            scroll.swipeUp()
        }
        XCTAssertTrue(button.exists && button.isHittable, "The control remains reachable: \(identifier)")
        return button
    }

    private func assertPlaybackLabel(_ label: String, in app: XCUIApplication) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label),
                                                object: app.buttons["morning.playback"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MO_BRAND_SCREENSHOT_DIR"] {
            do {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"), options: .atomic)
            } catch { XCTFail("Could not save the isolated branding screenshot: \(error)") }
        }
    }
}
