import XCTest

/// Isolated synthetic data; no personal recording or external-account access.
@MainActor
final class QuietMorningTests: XCTestCase {
    func testFirstUseKeepsLearningAndSunriseWithoutPermanentTabs() {
        let app = launch(["--ui-testing-empty-workspace"])
        assertQuietHome(app)
        XCTAssertEqual(app.scrollViews.count, 0)
        attach("more-first-use-one-screen", app)
        MorningUITestNavigation.tapButton("morning.begin", in: app)
        XCTAssertTrue(app.buttons["learn.screenTime"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertFalse(app.scrollViews["morning.captions"].exists)
    }

    func testTryPhoneSampleKeepsSeparateAppsManualAndPersistsAsDraft() {
        let app = launch(["--ui-testing-empty-workspace"])
        loadPhoneSample(in: app)
        let expected: [(String, Int)] = [
            ("Calendar & weather", 5), ("iMessage", 5), ("WhatsApp", 6),
            ("WhatsApp Business", 5), ("Messenger", 4), ("Mail", 7),
            ("Scroll a little", 10), ("A thought for later", 3)
        ]
        assertSample(expected, in: app)
        let messages = routineRow(1, in: app)
        XCTAssertTrue(messages.label.contains("Your own moment"), messages.label)
        messages.tap()
        XCTAssertTrue(app.textFields["step.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["step.name"].value as? String, "iMessage")
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step details")).firstMatch
        XCTAssertEqual(details.value as? String,
            "Open Messages and choose the conversations you want to catch up on. MORE is not connected to this inbox and does not read or reply for you.")
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("more-phone-sample-manual-source-details", app)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        attach("more-phone-sample-eight-manual-moments", app)
        app.terminate()
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.openRoutine(in: app)
        assertSample(expected, in: app)
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        XCTAssertFalse(app.scrollViews["morning.captions"].exists)
        attach("more-phone-sample-persists-unapproved", app)
        MorningUITestNavigation.assertSession(state: "none", in: app)
    }

    func testFrenchSampleUsesBonjourAndKeepsReadyStartExplicit() {
        let app = launch(["--ui-testing-empty-workspace", "--dark-preview", "-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"])
        loadPhoneSample(in: app)
        assertTitle("Calendrier et météo", on: routineRow(0, in: app), in: app)
        assertTitle("Une pensée pour plus tard", on: routineRow(7, in: app), in: app)
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        XCTAssertFalse(app.scrollViews["morning.captions"].exists)
        attach("more-french-sunset-sample", app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.revealControls(in: app)
        let start = app.buttons["morning.begin"]
        XCTAssertEqual(start.label, "Commencer mon matin")
        XCTAssertFalse(app.staticTexts["morning.readyQuestion"].exists)
        attach("more-french-sunset-actions", app)
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Calendrier et météo", in: app)
        XCTAssertFalse(app.buttons["morning.confirmStart"].exists)
        attach("more-french-sunset-started", app)
    }

    func testHomeClockOpensInvitationWithoutSchedulingAndReturnsHome() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        openInvitation(in: app)
        XCTAssertTrue(app.datePickers["invitation.date"].exists)
        XCTAssertTrue(app.buttons["invitation.schedule"].isHittable)
        XCTAssertEqual(app.staticTexts["invitation.status"].label, "No invitation is scheduled.")
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertEqual(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count, 0)
        XCTAssertFalse(app.buttons["invitation.cancel"].exists)
        attach("more-settings-invitation-editor", app)
        app.navigationBars["Your next morning"].buttons["Done"].tap()
        MorningUITestNavigation.selectTab("Morning", in: app)
        assertQuietHome(app)
        openInvitation(in: app)
        XCTAssertEqual(app.staticTexts["invitation.status"].label, "No invitation is scheduled.")
        XCTAssertFalse(app.buttons["invitation.cancel"].exists)
    }

    func testPendingStartWaitsForHomeInvitationEditorToClose() {
        let app = launch(["--ui-testing-approved", "--fixture-mode", "--ui-testing-start-entry-on-return"])
        openInvitation(in: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["Your next morning"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["morning.captions"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        app.navigationBars["Your next morning"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["setup.routine"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["morning.captions"].exists, "Settings still owns presentation while the entry waits.")
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        XCTAssertFalse(app.navigationBars["Your next morning"].exists)
    }

    func testTenMomentTilesAndSunriseActionsFitWithoutScrolling() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        assertQuietHome(app)
        XCTAssertEqual(app.scrollViews.count, 0, "Ten moments must not add a permanent list to Home.")
        attach("more-ten-moments-quiet-home", app)
        MorningUITestNavigation.revealControls(in: app)
        for identifier in ["morning.begin", "morning.settings"] { XCTAssertTrue(app.buttons[identifier].isHittable) }
        XCTAssertFalse(app.buttons["morning.step.9"].exists)
        attach("more-expanded-sunrise-actions", app)
        MorningUITestNavigation.openRoutine(in: app)
        assertTitle("One thought for later", on: routineRow(9, in: app), in: app)
        routineRow(9, in: app).tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step details")).firstMatch.value as? String, "Synthetic layout example.")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testDraftApprovalBelongsToReviewAndDateOpensHistory() {
        let app = launch([])
        assertQuietHome(app)
        MorningUITestNavigation.tapButton("morning.begin", in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["morning.captions"].exists, "Play on a draft opens review without starting it.")
        XCTAssertTrue(app.buttons["routine.step.0"].exists)
        attach("more-review-routine-editor", app)
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "none", in: app)
        MorningUITestNavigation.selectTab("Review", in: app)
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5))
        attach("more-weekly-review", app)
    }

    func testActiveMomentKeepsInstructionsAvailableWithoutEditing() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("morning.details", in: app)
        let instructions = app.staticTexts["moment.instructions"]
        XCTAssertTrue(instructions.waitForExistence(timeout: 5))
        XCTAssertEqual(instructions.label, "Good morning. Let’s see what’s ahead.")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        attach("more-compact-moment-commands", app)
        MorningUITestNavigation.tapButton("morning.closeDetails", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "paused", step: "Your morning", in: app)
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("morning.details", in: app)
        XCTAssertEqual(instructions.label, "Good morning. Let’s see what’s ahead.")
        MorningUITestNavigation.tapButton("morning.closeDetails", in: app)
        MorningUITestNavigation.tapButton("run.resume", in: app)
        MorningUITestNavigation.tapButton("morning.next", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "People and messages", in: app)
    }

    func testDarkTenMomentMorningRemainsOneScreen() {
        let app = launch(["--dark-preview", "--ui-testing-ten-moments", "--ui-testing-approved"])
        assertQuietHome(app)
        XCTAssertEqual(app.scrollViews.count, 0)
        attach("more-ten-moments-dark", app)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertTrue(app.buttons["morning.begin"].isHittable)
        XCTAssertTrue(app.buttons["morning.settings"].isHittable)
        attach("more-expanded-sunrise-dark", app)
    }

    func testSunriseMenuRemainsReachableInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        MorningUITestNavigation.revealControls(in: app)
        for identifier in ["morning.begin", "morning.settings"] { XCTAssertTrue(app.buttons[identifier].isHittable) }
        XCTAssertFalse(app.buttons["morning.review"].exists)
        XCTAssertFalse(app.buttons["morning.closeActions"].exists)
        attach("more-sunrise-landscape", app)
        app.buttons["morning.actions"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        XCTAssertTrue(app.buttons["morning.settings"].waitForNonExistence(timeout: 5))
        assertQuietHome(app)
    }

    func testSunriseDockDismissesOutsideAndStoppedMorningStaysQuiet() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        MorningUITestNavigation.revealControls(in: app)
        app.buttons["morning.actions"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        XCTAssertTrue(app.buttons["morning.settings"].waitForNonExistence(timeout: 5))
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "stopped", in: app)
        assertQuietHome(app)
        attach("more-compact-stopped-morning", app)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertTrue(app.buttons["morning.begin"].isHittable)
    }

    func testTenActiveMomentsKeepPauseAndLastItemOnOneScreen() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertTrue(app.buttons["morning.playback"].isHittable)
        XCTAssertFalse(app.buttons["morning.step.9"].exists)
        XCTAssertFalse(app.buttons["morning.next"].exists)
        attach("more-ten-active-moments-one-screen", app)
        MorningUITestNavigation.openRoutine(in: app)
        let last = routineRow(9, in: app)
        assertTitle("One thought for later", on: last, in: app)
        XCTAssertFalse(last.isEnabled, "A running session locks the saved routine's rows.")
    }

    func testAppleVoiceBetaKeepsPausedMorningAndTouchFallback() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.tapButton("run.pause", in: app)
        MorningUITestNavigation.openSettings(in: app)
        let unavailable = app.staticTexts["setup.conversationUnavailable"]
        scrollTo(unavailable, in: app)
        XCTAssertTrue(unavailable.label.contains("Local voice commands and reading aloud remain available."))
        XCTAssertFalse(app.buttons["setup.conversation"].exists)
        XCTAssertFalse(app.buttons["cloudVoice.start"].exists)
        XCTAssertFalse(app.buttons["cloudVoice.stop"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Reading the beta limit must not request microphone access.")
        attach("more-apple-voice-beta-touch-fallback", app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "paused", step: "Your morning", in: app)
        MorningUITestNavigation.tapButton("run.resume", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
    }

    func testTileReorderCreatesPersistentDraftAndActiveOrderIsLocked() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        MorningUITestNavigation.openRoutine(in: app)
        moveMoment(from: 1, to: 0, in: app)
        assertTitle("The weather", on: routineRow(0, in: app), in: app)
        XCTAssertTrue(app.buttons["routine.approve"].exists, "A new order needs renewed approval.")
        attach("more-routine-reorder-needs-approval", app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-ten-moments" || $0 == "--ui-testing-approved" }
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.openRoutine(in: app)
        assertTitle("The weather", on: routineRow(0, in: app), in: app)
        assertTitle("Your morning", on: routineRow(1, in: app), in: app)
        let restore = app.buttons["routine.restore"]
        scrollTo(restore, in: app)
        XCTAssertTrue(restore.isEnabled, "The earlier approved order remains recoverable.")
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "The weather", in: app)
        MorningUITestNavigation.openRoutine(in: app)
        for index in [0, 1] { XCTAssertFalse(routineRow(index, in: app).isEnabled) }
        XCTAssertFalse(app.buttons["routine.edit"].isEnabled)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.tapButton("run.pause", in: app)
        MorningUITestNavigation.openRoutine(in: app)
        for index in [0, 1] { XCTAssertFalse(routineRow(index, in: app).isEnabled) }
        XCTAssertFalse(app.buttons["routine.edit"].isEnabled)
        attach("more-paused-routine-order-locked", app)
    }

    func testNativeDragChangesOrderAndPersists() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        MorningUITestNavigation.openRoutine(in: app)
        attach("more-native-drag-before", app)
        moveMoment(from: 0, to: 2, in: app)
        let expected = ["The weather", "Today's calendar", "Your morning", "Your reminders", "People and messages",
                        "A little reading", "Make some tea", "A moment to move", "A little time to play", "One thought for later"]
        for (index, title) in expected.enumerated() { assertTitle(title, on: routineRow(index, in: app), in: app) }
        XCTAssertFalse(app.textFields["step.name"].exists, "Dragging must not open the moment editor.")
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        attach("more-native-drag-changed-order", app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-ten-moments" || $0 == "--ui-testing-approved" }
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.openRoutine(in: app)
        for (index, title) in expected.enumerated() { assertTitle(title, on: routineRow(index, in: app), in: app) }
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        attach("more-native-drag-order-after-relaunch", app)
    }

    private func loadPhoneSample(in app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Review", in: app)
        MorningUITestNavigation.tapButton("review.routine", in: app)
        MorningUITestNavigation.tapButton("routine.sample", in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
    }

    private func assertSample(_ expected: [(String, Int)], in app: XCUIApplication) {
        for (index, item) in expected.enumerated() {
            let row = routineRow(index, in: app)
            assertTitle(item.0, on: row, in: app)
            XCTAssertTrue(row.label.contains("\(item.1) min"), row.label)
            XCTAssertFalse(row.label.contains("+"))
        }
        XCTAssertFalse(app.buttons["routine.step.8"].exists)
        let source = app.descendants(matching: .any).matching(identifier: "routine.source").firstMatch
        scrollTo(source, in: app)
        XCTAssertTrue(source.label.contains("Sample routine · not observed behavior"), source.label)
        XCTAssertTrue(app.buttons["routine.approve"].exists)
    }

    private func routineRow(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["routine.step.\(index)"]
        scrollTo(row, index: index, in: app)
        return row
    }

    private func moveMoment(from source: Int, to destination: Int, in app: XCUIApplication) {
        MorningUITestNavigation.tapButton("routine.edit", in: app)
        let first = routineRow(source, in: app)
        let last = routineRow(destination, in: app)
        let lift = first.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let drop = last.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: destination > source ? 0.85 : 0.15))
        lift.press(forDuration: 1.2, thenDragTo: drop, withVelocity: .slow, thenHoldForDuration: 0.6)
        MorningUITestNavigation.tapButton("routine.edit", in: app)
    }

    private func openInvitation(in app: XCUIApplication) {
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("setup.invitation", in: app)
        XCTAssertTrue(app.navigationBars["Your next morning"].waitForExistence(timeout: 5))
    }

    private func assertQuietHome(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["routine.step.0"].exists)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertFalse(app.buttons["morning.step.0"].exists)
        XCTAssertFalse(app.buttons["morning.review"].exists)
        XCTAssertFalse(app.staticTexts["morning.heading"].exists)
        XCTAssertEqual(app.tabBars.count, 0)
    }

    private func scrollTo(_ element: XCUIElement, index: Int? = nil, in app: XCUIApplication) {
        let containers = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
        guard let list = containers.first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("No visible routine list.\n\(app.debugDescription)"); return
        }
        for _ in 0..<14 where !element.exists || !element.isHittable {
            let visibleIndices = (0..<10).filter { app.buttons["routine.step.\($0)"].exists && app.buttons["routine.step.\($0)"].isHittable }
            if element.exists, element.frame.height > 0, element.frame.midY < list.frame.midY { list.swipeDown() }
            else if let index, let first = visibleIndices.min(), index < first { list.swipeDown() }
            else { list.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func assertTitle(_ title: String, on element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", title), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed, app.debugDescription)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (arguments.contains("--dark-preview") ? [] : ["--light-preview"]) + arguments
        if !arguments.contains("-more.appLanguage") { app.launchArguments += ["-more.appLanguage", "en"] }
        if !arguments.contains(where: { $0.hasPrefix("--ui-testing-workspace=") }) { app.launchArguments.append("--ui-testing-workspace=\(UUID().uuidString)") }
        MorningUITestNavigation.launch(app)
        return app
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

/// Run separately with the simulator's content_size set to an accessibility size.
/// At the standard size it skips itself: the layout under test does not exist there.
@MainActor
final class QuietMorningAccessibilityTests: XCTestCase {
    func testLargeTextKeepsStartAndFullMomentDetailsReachable() throws {
        try LargeTextCondition.require()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-approved", "--fixture-mode", "-more.appLanguage", "en",
                               "--ui-testing-workspace=\(UUID().uuidString)"]
        MorningUITestNavigation.launch(app)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertTrue(app.buttons["morning.begin"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "more-accessibility-start-reachable"; screenshot.lifetime = .keepAlways; add(screenshot)
        MorningUITestNavigation.tapButton("run.start", in: app)
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("morning.details", in: app)
        XCTAssertTrue(app.staticTexts["moment.instructions"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["moment.instructions"].label, "Good morning. Let’s see what’s ahead.")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertTrue(app.buttons["morning.closeDetails"].isHittable)
        MorningUITestNavigation.tapButton("morning.closeDetails", in: app)
        MorningUITestNavigation.tapButton("run.stop", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.revealControls(in: app)
        XCTAssertTrue(app.buttons["morning.begin"].isHittable)
    }
}
