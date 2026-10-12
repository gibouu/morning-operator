import XCTest

/// An isolated synthetic archive. No personal recording, model call or external app.
@MainActor
final class ObservationArchiveTests: XCTestCase {
    private let firstID = "11111111-1111-4111-8111-111111111111"
    private let secondID = "22222222-2222-4222-8222-222222222222"
    private let undatedID = "33333333-3333-4333-8333-333333333333"
    private let originalA = "Original sample A: calendar, water, chess."
    private let correctedA = "Edited sample A: calendar, water, chess and tea."

    func testArchiveRestoresOriginalAndCorrectionsAndDeletesOnlyChosenEvidence() throws {
        let app = launch()
        openArchive(in: app)
        open(firstID, in: app)
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5))
        expand("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label, originalA)
        expand("Current notes", in: app)
        XCTAssertEqual(app.staticTexts["observation.currentText"].label, correctedA)
        MorningUITestNavigation.tapButton("observation.edit", in: app)
        let editor = app.textViews["learn.notes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        scrollTo(editor, in: app)
        XCTAssertEqual(editor.value as? String, correctedA)
        editor.tap()
        editor.typeText(" A small correction.")
        let edited = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(edited.contains("A small correction."))
        app.navigationBars["Learn my morning"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5))

        // Removing the seed flag ensures restoration is from the durable workspace.
        relaunchWithoutSeed(app)
        openArchive(in: app)
        open(firstID, in: app)
        expand("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label, originalA)
        expand("Current notes", in: app)
        XCTAssertEqual(app.staticTexts["observation.currentText"].label, edited)
        attach("archive-original-and-correction-restored", app)

        MorningUITestNavigation.tapButton("observation.delete", in: app)
        XCTAssertTrue(app.alerts["Delete this observation?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Observation"].exists)
        MorningUITestNavigation.tapButton("observation.delete", in: app)
        app.alerts.buttons["Delete observation"].tap()
        XCTAssertTrue(app.navigationBars["Observations"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["observation.row.\(firstID)"].exists)
        XCTAssertTrue(app.buttons["observation.row.\(secondID)"].exists)
        XCTAssertTrue(app.buttons["observation.row.\(undatedID)"].exists)

        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observation.row.\(firstID)"].exists)
        XCTAssertTrue(app.buttons["observation.row.\(secondID)"].exists)
        MorningUITestNavigation.tapButton("observations.deleteAll", in: app)
        XCTAssertTrue(app.alerts["Delete all observations?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Delete all"].tap()
        XCTAssertTrue(app.staticTexts["No saved observations"].waitForExistence(timeout: 5))

        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertTrue(app.staticTexts["No saved observations"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["observation.row.\(secondID)"].exists)
        MorningUITestNavigation.selectTab("Morning", in: app)
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5),
                      "Deleting observations must preserve the independently saved routine.")
    }

    func testUndatedImportNeedsExplicitDayAndOriginBeforeAppearingInDayHistory() {
        let app = launch()
        MorningUITestNavigation.reviewAction("review.undatedObservations", in: app)
        XCTAssertTrue(app.buttons["observation.row.\(undatedID)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["observation.row.\(firstID)"].exists)
        open(undatedID, in: app)
        assertDetailValue("observation.observedDate", equals: "Date needed", in: app)
        MorningUITestNavigation.tapButton("observation.setDate", in: app)
        XCTAssertTrue(app.buttons["observation.saveDate"].waitForExistence(timeout: 5))
        // Provenance is an explicit choice, never inferred from the imported text.
        MorningUITestNavigation.tapButton("observation.originPicker", in: app)
        app.buttons["Unsure"].tap()
        let assignedDay = displayedDay(Date())
        app.buttons["observation.saveDate"].tap()
        waitForDetail(in: app)
        assertDetailValue("observation.origin", equals: "Origin unsure", in: app)
        assertDetailValue("observation.observedDate", equals: assignedDay, in: app)

        relaunchWithoutSeed(app)
        MorningUITestNavigation.selectTab("Review", in: app)
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.undatedObservations"].exists)
        XCTAssertFalse(app.staticTexts["review.average"].exists,
                       "Dated observations must not create measured routine or phone-use time.")
        MorningUITestNavigation.tapButton("review.period", in: app)
        let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.day.")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        scrollTo(day, in: app)
        day.tap()
        XCTAssertTrue(app.buttons["observation.row.\(undatedID)"].waitForExistence(timeout: 5),
                      "The explicitly assigned current day must include the saved observation.")
        XCTAssertTrue(app.staticTexts["No routine saved for this day."].waitForExistence(timeout: 5))
        open(undatedID, in: app)
        MorningUITestNavigation.tapButton("observation.setDate", in: app)
        MorningUITestNavigation.tapButton("observation.removeDate", in: app)
        waitForDetail(in: app)
        assertDetailValue("observation.observedDate", equals: "Date needed", in: app)
        relaunchWithoutSeed(app)
        MorningUITestNavigation.reviewAction("review.undatedObservations", in: app)
        XCTAssertTrue(app.buttons["observation.row.\(undatedID)"].waitForExistence(timeout: 5))
        attach("archive-undated-import-restored", app)
    }

    func testIdenticalImportPreservesCorrectionsAndOlderAcquisitionsAcrossRelaunch() throws {
        let app = launch(["--ui-testing-import-observation"])
        let imported = "[Synthetic UI-test observation]\nI check my calendar, drink water, and enjoy ten minutes of chess."
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let editor = app.textViews["learn.notes"]
        waitForNotes(imported, in: app)
        scrollTo(editor, in: app)
        editor.tap()
        editor.typeText(" Keep this correction after importing again.")
        let corrected = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(corrected.contains("Keep this correction after importing again."))
        closeLearn(in: app)
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 4)
        let olderIDs = Set([firstID, secondID, undatedID].map { "observation.row.\($0)" })
        let importedID = try XCTUnwrap(archiveRows(in: app).allElementsBoundByIndex.first { !olderIDs.contains($0.identifier) }?.identifier)

        // The same file is imported again through the production importer after restart.
        relaunchWithoutSeed(app)
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let keptNotice = app.staticTexts["This observation is already saved. Your corrections and its date have been kept."]
        XCTAssertTrue(keptNotice.waitForExistence(timeout: 15), "The duplicate import must finish before assertions.")
        waitForNotes(corrected, in: app)
        closeLearn(in: app)
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 4, "Identical bytes must not create a fifth acquisition.")
        XCTAssertTrue(app.buttons[importedID].exists, "The existing acquisition ID must survive reimport.")
        MorningUITestNavigation.tapButton(importedID, in: app)
        expand("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label, imported)
        MorningUITestNavigation.tapButton("observation.edit", in: app)
        waitForNotes(corrected, in: app)
        MorningUITestNavigation.tapButton("learn.clear", in: app)
        waitForNotes("", in: app)
        closeLearn(in: app)

        // Stop the hook before relaunch so deleted evidence is not deliberately reimported.
        app.launchArguments.removeAll { $0 == "--ui-testing-import-observation" }
        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 3)
        XCTAssertFalse(app.buttons[importedID].exists)
        for id in [firstID, secondID, undatedID] {
            XCTAssertTrue(app.buttons["observation.row.\(id)"].exists)
        }
        attach("archive-duplicate-import-keeps-older-observations", app)
    }

    func testLegacyLatestObservationMigratesWithoutInventedDates() throws {
        let raw = ProcessInfo.processInfo.environment["MO_LEGACY_OBSERVATION_WORKSPACE"] ?? ""
        guard let workspaceID = UUID(uuidString: raw) else {
            throw XCTSkip("Requires an explicitly staged legacy workspace UUID; this test does not create migration evidence.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview", "--ui-testing-workspace=\(workspaceID.uuidString)"]
        app.launch()
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 1)
        let row = archiveRows(in: app).firstMatch
        XCTAssertTrue(row.exists)
        row.tap()
        waitForDetail(in: app)
        assertDetailValue("observation.importedDate", equals: "Import date unknown", in: app)
        assertDetailValue("observation.observedDate", equals: "Date needed", in: app)
        expand("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label, "Legacy saved observation: calendar and tea.")
        // Selection persists the migrated archive without assigning either missing date.
        MorningUITestNavigation.tapButton("observation.edit", in: app)
        waitForNotes("Legacy saved observation: calendar and tea.", in: app)
        closeLearn(in: app)
        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 1)
        archiveRows(in: app).firstMatch.tap()
        waitForDetail(in: app)
        assertDetailValue("observation.importedDate", equals: "Import date unknown", in: app)
        assertDetailValue("observation.observedDate", equals: "Date needed", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5)
                      || app.buttons["run.start"].waitForExistence(timeout: 5), "Legacy routine must survive migration.")
        attach("archive-legacy-migration-keeps-unknown-dates", app)
    }

    /// The controller stages a valid synthetic workspace whose preference field is
    /// explicitly null. This test never creates or substitutes a recovery fixture.
    func testUnreadablePreferencesSurviveAnUnrelatedSaveUntilExplicitReset() throws {
        let raw = ProcessInfo.processInfo.environment["MO_PREFERENCE_RECOVERY_WORKSPACE"] ?? ""
        guard let workspaceID = UUID(uuidString: raw) else {
            throw XCTSkip("Requires an explicitly staged workspace with null routinePreferences, a draft routine and synthetic observation.")
        }
        continueAfterFailure = false
        let original = "Recovery saved observation: calendar and tea."
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
                               "--ui-testing-workspace=\(workspaceID.uuidString)"]
        app.launch()

        MorningUITestNavigation.openRoutine(in: app)
        assertRecoveryRoutine(in: app)
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        XCTAssertFalse(approve.isEnabled, "Unreadable saved choices must block approval until explicit recovery.")
        MorningUITestNavigation.tapButton("routine.preferences", in: app)
        let issue = app.staticTexts["preferences.issue"]
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        attach("preferences-null-payload-needs-explicit-recovery", app)

        // Reopen without any seed or import hook, then save only an observation
        // correction through the ordinary Learn editor and workspace writer.
        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 1)
        let observationRowID = archiveRows(in: app).firstMatch.identifier
        MorningUITestNavigation.tapButton(observationRowID, in: app)
        waitForDetail(in: app)
        expand("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label, original)
        MorningUITestNavigation.tapButton("observation.edit", in: app)
        waitForNotes(original, in: app)
        let editor = app.textViews["learn.notes"]
        scrollTo(editor, in: app)
        editor.tap()
        editor.typeText(" A correction kept while choices need repair.")
        let corrected = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(corrected.contains("A correction kept while choices need repair."))
        if app.buttons["input.done"].isHittable { app.buttons["input.done"].tap() }
        closeLearn(in: app)

        relaunchWithoutSeed(app)
        MorningUITestNavigation.openRoutine(in: app)
        assertRecoveryRoutine(in: app)
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        XCTAssertFalse(approve.isEnabled, "An unrelated save must not silently replace null preferences with an empty journal.")
        MorningUITestNavigation.tapButton("routine.preferences", in: app)
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        attach("preferences-recovery-survives-observation-save-and-relaunch", app)
        MorningUITestNavigation.tapButton("preferences.reset", in: app)
        let confirmation = app.sheets["Reset unreadable choices?"]
            .buttons.matching(identifier: "preferences.confirmReset").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.staticTexts["No saved choices"].waitForExistence(timeout: 5))
        XCTAssertFalse(issue.exists)

        // Reset must be durable and scoped to preferences. Original extraction,
        // the correction and acquisition identity survive the next launch.
        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 1)
        XCTAssertTrue(app.buttons[observationRowID].exists)
        MorningUITestNavigation.tapButton(observationRowID, in: app)
        waitForDetail(in: app)
        expand("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label, original)
        expand("Current notes", in: app)
        XCTAssertEqual(app.staticTexts["observation.currentText"].label, corrected)

        relaunchWithoutSeed(app)
        MorningUITestNavigation.openRoutine(in: app)
        assertRecoveryRoutine(in: app)
        XCTAssertFalse(app.buttons["routine.preferences"].exists,
                       "After reset, the durable explicit-empty journal must not re-enter recovery.")
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        XCTAssertTrue(approve.isEnabled)
        approve.tap()
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5),
                      "The preserved draft can be approved after explicit reset; this test does not start it.")
        attach("preferences-explicit-reset-keeps-routine-and-observation", app)
    }

    func testUnreadablePreferencesCanBeResetBeforeTheFirstRoutineExists() throws {
        let raw = ProcessInfo.processInfo.environment["MO_EMPTY_PREFERENCE_RECOVERY_WORKSPACE"] ?? ""
        guard let workspaceID = UUID(uuidString: raw) else {
            throw XCTSkip("Requires an explicitly staged workspace with null routinePreferences, no routine and one synthetic observation.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview", "--ui-testing-empty-workspace",
                               "--ui-testing-workspace=\(workspaceID.uuidString)"]
        app.launch()
        MorningUITestNavigation.openRoutine(in: app)
        XCTAssertTrue(app.buttons["Build it myself"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["routine.step.0"].exists)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.tapButton("routine.preferences", in: app)
        XCTAssertTrue(app.staticTexts["preferences.issue"].waitForExistence(timeout: 5),
                      "Recovery must be reachable without creating a routine first.")
        attach("preferences-recovery-reachable-before-first-routine", app)
        MorningUITestNavigation.tapButton("preferences.reset", in: app)
        let confirmation = app.sheets["Reset unreadable choices?"]
            .buttons.matching(identifier: "preferences.confirmReset").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.staticTexts["No saved choices"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["preferences.issue"].exists)

        relaunchWithoutSeed(app)
        MorningUITestNavigation.openRoutine(in: app)
        XCTAssertTrue(app.buttons["Build it myself"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["routine.preferences"].exists)
        XCTAssertFalse(app.buttons["routine.step.0"].exists)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.closeRoutine(in: app)
        openArchive(in: app)
        XCTAssertEqual(archiveRows(in: app).count, 1)
        archiveRows(in: app).firstMatch.tap()
        waitForDetail(in: app)
        expand("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label,
                       "Recovery saved observation: calendar and tea.")
        attach("preferences-reset-before-first-routine-keeps-observation", app)
    }

    private func assertRecoveryRoutine(in app: XCUIApplication) {
        let step = app.buttons["routine.step.0"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertTrue(step.label.contains("Recovery fixture morning"), "The staged routine must remain intact.")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step.")).count, 1)
    }

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
                               "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-observation-archive"] + extraArguments
        app.launch()
        return app
    }

    private func relaunchWithoutSeed(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-observation-archive" }
        app.launch()
    }

    private func openArchive(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.observations", in: app)
        XCTAssertTrue(app.navigationBars["Observations"].waitForExistence(timeout: 5))
    }

    private func open(_ id: String, in app: XCUIApplication) {
        MorningUITestNavigation.tapButton("observation.row.\(id)", in: app)
        waitForDetail(in: app)
    }

    private func waitForDetail(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5))
        let dateControl = app.buttons["observation.setDate"]
        XCTAssertTrue(dateControl.waitForExistence(timeout: 5))
        let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: dateControl)
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 5), .completed,
                       "Wait for the detail navigation or date-sheet dismissal before checking its labels.")
    }

    private func assertDetailValue(_ identifier: String, equals expected: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && (element.value as? String) == expected
        }, object: element)
        let result = XCTWaiter.wait(for: [ready], timeout: 5)
        if result != .completed {
            let actual = element.exists ? String(describing: element.value) : "element missing"
            XCTFail("Expected \(identifier) value \(expected), got \(actual).\n\(app.debugDescription)",
                    file: file, line: line)
        }
    }

    private func displayedDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func archiveRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.row."))
    }

    private func waitForNotes(_ expected: String, in app: XCUIApplication) {
        let editor = app.textViews["learn.notes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (editor.value as? String ?? "") == expected && editor.isEnabled
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }

    private func closeLearn(in app: XCUIApplication) {
        let navigation = app.navigationBars["Learn my morning"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        navigation.buttons["Done"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: navigation)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    private func expand(_ title: String, in app: XCUIApplication) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        scrollTo(button, in: app)
        button.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            let scroll = app.scrollViews.containing(element.elementType, identifier: element.identifier).firstMatch
            let collection = app.collectionViews.firstMatch
            let table = app.tables.firstMatch
            let container = scroll.exists ? scroll : collection.exists ? collection : table
            XCTAssertTrue(container.exists)
            if element.frame.height > 0, element.frame.midY < container.frame.midY { container.swipeDown() }
            else { container.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
