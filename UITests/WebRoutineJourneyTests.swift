import XCTest

/// Exercises the saved routine/editor/browser path with synthetic data. It never
/// signs in, reads an account, or opens a third-party native app.
@MainActor
final class WebRoutineJourneyTests: XCTestCase {
    func testMessagingMomentsOpenDirectlyWithoutAConnectionChecklist() throws {
        continueAfterFailure = false
        for (language, service, host) in [("en", "LinkedIn", "www.linkedin.com"), ("fr", "Slack", "app.slack.com")] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
                "--ui-testing-briefing-fixture", "--ui-testing-workspace=\(UUID().uuidString)",
                "--light-preview", "--theme-phase=morning", "-more.appLanguage", language,
                "-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US"]
            MorningUITestNavigation.launch(app)
            defer { app.terminate() }
            MorningUITestNavigation.openRoutine(in: app)
            let first = app.buttons["routine.step.0"]
            XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
            first.tap()
            let target = app.buttons["step.targetApp"]
            reveal(target, in: app)
            target.tap()
            let site = app.buttons[service].firstMatch
            XCTAssertTrue(site.waitForExistence(timeout: 5), app.debugDescription)
            site.tap()
            app.buttons["step.save"].tap()
            let approve = app.buttons["routine.approve"]
            XCTAssertTrue(approve.waitForExistence(timeout: 5), app.debugDescription)
            approve.tap()
            MorningUITestNavigation.tapButton("run.start", in: app)
            XCTAssertTrue(app.buttons["web.close"].waitForExistence(timeout: 15), app.debugDescription)
            // This asserts the ordinary route before any provider-specific redirect.
            // No account is signed in and no external message is sent by this test.
            XCTAssertTrue(app.staticTexts["web.host"].exists)
            XCTAssertTrue((service == "LinkedIn" ? ["www.linkedin.com", "linkedin.com"] : ["app.slack.com", "slack.com", "www.slack.com"]).contains(app.staticTexts["web.host"].label), app.debugDescription)
            XCTAssertTrue(app.otherElements["web.conversation"].exists || app.scrollViews["web.conversation"].exists, app.debugDescription)
            XCTAssertFalse(app.buttons["connections.confirmReady"].exists)
            attach("browser-first-\(service)-\(language)-\(host)", app)
        }
    }

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
            SubmissionRoutineUITestNavigation.startSavedInstagram(in: app)
            XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(app.buttons["web.aboutDone"].exists, "Starting a saved routine must open its moment directly.")
            XCTAssertTrue(app.buttons["web.nextMoment"].isHittable)
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
        XCTAssertTrue(app.otherElements["web.page"].waitForExistence(timeout: 10)
            || app.webViews["web.page"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["web.aboutDone"].exists, "A routine must not open an extra introduction over its page.")
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

/// Opt-in acceptance of the real ActivityKit surface. Synthetic routine data is
/// isolated; the system supplies the island mask and runs the widget's actions.
@MainActor
final class MorningNativeIslandSubmissionTests: XCTestCase {
    func testExpandedInstagramIslandKeepsLocalizedContentInsideSystemMask() throws {
        try exerciseIsland(testActions: false)
    }

    func testNativeIslandActionsExtendAndAdvanceTheSavedRoutine() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_SUBMISSION_ACTIVITY_ACTIONS_TEST_ENABLED"] == "1",
                          "Native intent execution is a separate acceptance check from the system mask.")
        try exerciseIsland(testActions: true)
    }

    private func exerciseIsland(testActions: Bool) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_SUBMISSION_ACTIVITY_TEST_ENABLED"] == "1",
                          "Run explicitly on the dedicated submission simulator; this uses native ActivityKit.")
        continueAfterFailure = false
        for language in ["en", "fr"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
                "--ui-testing-instagram-routing", "--ui-testing-briefing-fixture", "--ui-testing-live-activity",
                "--ui-testing-workspace=\(UUID().uuidString)", "--light-preview", "--theme-phase=morning",
                "-more.appLanguage", language, "-AppleLanguages", "(\(language))",
                "-AppleLocale", language == "fr" ? "fr_FR" : "en_US"]
            MorningUITestNavigation.launch(app)
            defer {
                // Reconcile only this UUID workspace's process-era activity.
                app.terminate()
                MorningUITestNavigation.launch(app)
                app.terminate()
            }
            SubmissionRoutineUITestNavigation.startSavedInstagram(in: app)
            let about = app.buttons["web.aboutDone"]
            if about.waitForExistence(timeout: 5) { about.tap() }
            XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(app.staticTexts["web.host"].label, "www.instagram.com")
            let before = try countdown(app.staticTexts["web.remaining"])
            let beforeEnd = Date().addingTimeInterval(TimeInterval(before))
            XCUIDevice.shared.press(.home)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let surface = springboard.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@", "MORE.", "Instagram")).firstMatch
            // The compact summary contains the closed activity category, which
            // need not be Instagram; use the app-owned MORE prefix if necessary.
            let compact = surface.waitForExistence(timeout: 3) ? surface : springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "MORE.")).firstMatch
            XCTAssertTrue(compact.waitForExistence(timeout: 10), springboard.debugDescription)
            compact.press(forDuration: 1)
            let extend = springboard.buttons["stepActivity.more.extend"]
            let next = springboard.descendants(matching: .any).matching(identifier: "stepActivity.more.next").firstMatch
            let timer = springboard.staticTexts["stepActivity.more.remaining"]
            XCTAssertTrue(extend.waitForExistence(timeout: 5), springboard.debugDescription)
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "native-instagram-expanded-island-\(language)"; capture.lifetime = .keepAlways; add(capture)
            let hierarchy = XCTAttachment(string: springboard.debugDescription)
            hierarchy.name = "native-instagram-expanded-hierarchy-\(language)"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            XCTAssertTrue(next.exists, springboard.debugDescription)
            XCTAssertTrue(timer.exists, springboard.debugDescription)
            let destination = springboard.staticTexts[language == "fr" ? "Instagram dans MORE" : "Instagram in MORE"]
            let status = springboard.staticTexts[language == "fr" ? "À vous" : "Your turn"]
            XCTAssertTrue(destination.exists, springboard.debugDescription)
            XCTAssertTrue(status.exists, springboard.debugDescription)
            let bounds = springboard.frame
            for element in [extend, next, timer, destination, status] {
                XCTAssertFalse(element.frame.isEmpty, "The native Island must lay out its full content: \(element)")
                XCTAssertTrue(bounds.contains(element.frame), "A native Island control must remain on screen: \(element)")
            }
            if !testActions { continue }
            // iOS may collapse an expanded Island while the assertions and
            // screenshot run. Reopen the observed native surface before acting.
            if !extend.isHittable { compact.press(forDuration: 1) }
            XCTAssertTrue(extend.isHittable, "The expanded native Island must expose its +2 control.")
            extend.tap()
            app.activate()
            XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 10), app.debugDescription)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let values = app.staticTexts["web.remaining"].label.split(separator: ":").compactMap { Int($0) }
                guard values.count == 2 else { return false }
                let end = Date().addingTimeInterval(TimeInterval(values[0] * 60 + values[1]))
                return end.timeIntervalSince(beforeEnd) > 110
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed,
                           "The native +2 intent must finish updating the same routine budget.")
            let extended = try countdown(app.staticTexts["web.remaining"])
            let extendedEnd = Date().addingTimeInterval(TimeInterval(extended))
            XCTAssertEqual(extendedEnd.timeIntervalSince(beforeEnd), 120, accuracy: 8,
                           "The native +2 intent must update the same routine budget.")
            XCUIDevice.shared.press(.home)
            let updated = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "MORE.")).firstMatch
            XCTAssertTrue(updated.waitForExistence(timeout: 10), springboard.debugDescription)
            updated.press(forDuration: 1)
            XCTAssertTrue(next.waitForExistence(timeout: 5), springboard.debugDescription)
            XCTAssertTrue(next.isHittable, "The expanded native Island must expose its Next control.")
            next.tap()
            XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertEqual(app.staticTexts["web.host"].label, "www.instagram.com")
            app.buttons["web.close"].tap()
            MorningUITestNavigation.assertSession(state: "running", step: "SYNTHETIC Instagram profile", in: app)
        }
    }

    private func countdown(_ value: XCUIElement) throws -> Int {
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        let parts = value.label.split(separator: ":").compactMap { Int($0) }
        return try XCTUnwrap(parts.count == 2 ? parts[0] * 60 + parts[1] : nil,
                             "Expected the live minute:second countdown, got \(value.label)")
    }
}

/// Home deliberately hides its controls after five seconds. Tap the requested
/// control directly after revealing it; unrelated frame queries can outlast that
/// interval on a busy simulator and must not be mistaken for an app failure.
@MainActor
private enum SubmissionRoutineUITestNavigation {
    static func startSavedInstagram(in app: XCUIApplication) {
        let begin = app.buttons["morning.begin"]
        for _ in 0..<3 {
            if begin.exists { break }
            app.buttons["morning.actions"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
            if begin.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(begin.exists, app.debugDescription)
        begin.tap()
        XCTAssertTrue(app.buttons["web.nextMoment"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["web.aboutDone"].exists, "The saved moment starts directly.")

    }
}
