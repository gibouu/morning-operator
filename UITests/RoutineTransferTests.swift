import XCTest

/// Real native review and bounded file loading with synthetic portable files.
/// Controller-staged file checks never substitute a decoded model. Separate
/// native-panel checks cover cancellation and one synthetic save/reopen journey.
/// No test invokes the Apple model or starts playback.
@MainActor
final class RoutineTransferTests: XCTestCase {
    /// The Files panel runs in another process. On a hosted simulator its first
    /// appearance has taken more than ten seconds while the export sheet waits, disabled.
    private let nativePanelWait: TimeInterval = 40
    private let currentTitle = "Your morning"
    private let importedTitle = "Imported calm"
    private let privateExportNote = "SYNTHETIC_PRIVATE_EXPORT_NOTE"
    private let importedNote = "SYNTHETIC_IMPORTED_TRANSFER_NOTE"
    private let importedSource = "SYNTHETIC_IMPORTED_TRANSFER_SOURCE"

    func testExportPlanOmitsNotesUntilExplicitlyIncluded() {
        let app = launch()
        openRoutine(in: app)
        tap("routine.step.0", in: app)
        let detail = app.textFields["Step details"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        reveal(detail, in: app)
        detail.tap()
        detail.typeText("\n\(privateExportNote)")
        XCTAssertTrue((detail.value as? String)?.contains(privateExportNote) == true)
        tap("step.save", in: app)
        waitAbsent(app.navigationBars["Make it yours"])
        tap("routine.approve", in: app)
        waitAbsent(app.navigationBars["Your routine"])

        openRoutine(in: app)
        tap("routine.export", in: app)
        XCTAssertTrue(app.buttons["export.cancel"].waitForExistence(timeout: 5))
        let firstTitle = app.staticTexts["export.step.0.title"]
        reveal(firstTitle, in: app)
        XCTAssertEqual(firstTitle.label, currentTitle)
        let includeNotes = app.switches["export.includeNotes"]
        reveal(includeNotes, in: app)
        XCTAssertEqual(includeNotes.value as? String, "0")
        XCTAssertFalse(app.staticTexts["export.step.0.notes"].exists,
                       "The default portable preview must omit private step details.")
        XCTAssertFalse(app.staticTexts["export.source"].exists,
                       "The default portable preview must omit the original source label.")
        let nativeSwitch = includeNotes.switches.firstMatch
        XCTAssertTrue(nativeSwitch.waitForExistence(timeout: 5))
        XCTAssertTrue(nativeSwitch.isHittable)
        nativeSwitch.tap()
        waitValue(includeNotes, equals: "1", in: app)
        let source = app.staticTexts["export.source"]
        reveal(source, in: app)
        XCTAssertTrue(source.label.contains("Demo fixture"),
                      "Including notes also deliberately includes the saved source label.")
        let notes = app.staticTexts["export.step.0.notes"]
        reveal(notes, in: app)
        XCTAssertTrue(notes.label.contains(privateExportNote),
                      "Only the deliberate notes option should reveal the private detail.")
        attach("synthetic-portable-export-deliberate-notes-preview", app)
        tap("export.cancel", in: app)
        waitAbsent(app.buttons["export.cancel"])
        assertRoutine(currentTitle, count: 4, approved: true, in: app)

        // Canceling transfer never clears the original private note or changes
        // approval. Reopening also requires a fresh deliberate notes choice.
        tap("routine.step.0", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue((detail.value as? String)?.contains(privateExportNote) == true)
        app.navigationBars["Make it yours"].buttons["Cancel"].tap()
        waitAbsent(app.navigationBars["Make it yours"])
        tap("routine.export", in: app)
        XCTAssertTrue(app.buttons["export.cancel"].waitForExistence(timeout: 5))
        reveal(includeNotes, in: app)
        XCTAssertEqual(includeNotes.value as? String, "0")
        tap("export.cancel", in: app)
        waitAbsent(app.buttons["export.cancel"])
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
    }

    func testPortableFileRequiresReviewAndRestoresPriorRoutineAfterDraftRelaunch() throws {
        let path = try stagedFilePath(environmentKey: "MO_ROUTINE_IMPORT_FILE")
        let app = launch(importPath: path)
        openRoutine(in: app)
        openImport(in: app)
        assertImportedPreview(in: app)
        tap("import.cancel", in: app)
        waitAbsent(app.buttons["import.use"])
        assertRoutine(currentTitle, count: 4, approved: true, in: app)

        openImport(in: app)
        assertImportedPreview(in: app)
        tap("import.use", in: app)
        waitAbsent(app.buttons["import.use"])
        assertImportedDraft(in: app)
        MorningUITestNavigation.closeRoutine(in: app)
        assertCannotStart(in: app)

        relaunchWithoutSeed(app)
        assertCannotStart(in: app)
        openRoutine(in: app)
        assertImportedDraft(in: app)
        // The same real file still carries approvalAtExport=true. Reimporting
        // it is another reviewed draft operation, never approval or execution.
        openImport(in: app)
        assertImportedPreview(in: app)
        tap("import.use", in: app)
        waitAbsent(app.buttons["import.use"])
        assertImportedDraft(in: app)
        MorningUITestNavigation.closeRoutine(in: app)
        assertCannotStart(in: app)
        relaunchWithoutSeed(app)
        openRoutine(in: app)
        assertImportedDraft(in: app)
        XCTAssertTrue(app.buttons["routine.restore"].exists)
        attach("synthetic-portable-import-remains-manual-draft-after-repeat-and-relaunch", app)
        tap("routine.restore", in: app)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        MorningUITestNavigation.closeRoutine(in: app)
        relaunchWithoutSeed(app)
        openRoutine(in: app)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        MorningUITestNavigation.closeRoutine(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("run.start", in: app)
        XCTAssertFalse(app.staticTexts["run.state"].exists,
                       "Restoring an approved plan makes it ready; it must not start it.")
    }

    /// Exercises actual system panel presentation/dismissal only. It does not
    /// save an exported file, select an imported file or establish provider access.
    func testNativeFilePickersCancelWithoutChangingRoutine() {
        let app = launch(savedBaseline: true)
        openRoutine(in: app)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        tap("routine.export", in: app)
        XCTAssertTrue(app.buttons["export.cancel"].waitForExistence(timeout: 5))
        let nativeBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertFalse(nativeBar.exists)
        tap("export.save", in: app)
        XCTAssertTrue(nativeBar.waitForExistence(timeout: nativePanelWait),
                      "Expected the actual native document export panel.\n\(app.debugDescription)")
        attach("native-file-export-panel-before-dismissal-no-file-saved", app)
        // On this iOS 27 panel, AX includes a non-hittable Other named Cancel
        // over More, but the actual visible header has Browse, More and Save.
        // Dismiss the native sheet by dragging its verified header down.
        dragDismissDocumentPanel(nativeBar, in: app)
        let exportDone = app.buttons["export.cancel"]
        let exportReturned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                                       object: exportDone)
        XCTAssertEqual(XCTWaiter.wait(for: [exportReturned], timeout: 5), .completed,
                       "Dismissing the system exporter must return to the reviewed export.\n\(app.debugDescription)")
        XCTAssertTrue(app.navigationBars["Export routine"].exists)
        tap("export.cancel", in: app)
        waitAbsent(app.buttons["export.cancel"])
        assertRoutine(currentTitle, count: 4, approved: true, in: app)

        XCTAssertFalse(nativeBar.exists)
        tap("routine.import", in: app)
        XCTAssertTrue(nativeBar.waitForExistence(timeout: nativePanelWait),
                      "Expected the actual native document import panel.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["import.use"].exists,
                       "Opening a file panel must not create a decoded routine preview.")
        attach("native-file-import-panel-before-dismissal-no-file-selected", app)
        let nativeCancels = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Cancel"))
        if let cancel = nativeCancels.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            cancel.tap()
            waitAbsent(nativeBar)
        } else {
            dragDismissDocumentPanel(nativeBar, in: app)
        }
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        XCTAssertFalse(app.buttons["import.use"].exists)
        MorningUITestNavigation.closeRoutine(in: app)
        relaunchWithoutSeed(app)
        openRoutine(in: app)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        attach("native-file-panel-dismissals-preserve-approved-routine-after-relaunch", app)
    }

    /// Actual native Files save and selection, with no staged-file import hook.
    /// The UI proves that the exported plan is decoded without notes; it does not
    /// independently inspect provider bytes or establish cloud-provider support.
    func testNativeSaveAndSelectPlanOnlyFileCreatesManualDraft() throws {
        let app = launch(savedBaseline: true)
        let filename = "MORE-Transfer-\(UUID().uuidString)"
        openRoutine(in: app)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        tap("routine.export", in: app)
        XCTAssertTrue(app.buttons["export.cancel"].waitForExistence(timeout: 5))
        let includeNotes = app.switches["export.includeNotes"]
        reveal(includeNotes, in: app)
        XCTAssertEqual(includeNotes.value as? String, "0")
        tap("export.save", in: app)
        let nativeBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(nativeBar.waitForExistence(timeout: nativePanelWait),
                      "A real native export panel must appear.\n\(app.debugDescription)")
        let nameField = app.textFields["DOCPicker.filenameTextField"]
        guard nameField.waitForExistence(timeout: 10) else {
            // Issue #95: the iOS 27.0 save panel shows Browse, More, Save and a
            // search field, and no name field. Without a unique name this test
            // could select a file it did not save, so it stops here. It runs in
            // full wherever the panel offers the field.
            let offeredSave = nativeBar.buttons["DOCPicker.actionButton"]
            XCTAssertTrue(offeredSave.exists && offeredSave.isEnabled && offeredSave.isHittable,
                          "The native save panel must at least offer a usable Save action.\n\(app.debugDescription)")
            XCTAssertEqual(offeredSave.label, "Save")
            attach("native-save-panel-without-a-filename-field", app)
            throw XCTSkip("The native save round trip was not run: this system's Files save panel has no filename field, so the test cannot give its file a unique name (issue #95).")
        }
        XCTAssertTrue(nameField.isHittable)
        let oldName = nameField.value as? String ?? ""
        XCTAssertFalse(oldName.isEmpty)
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + filename)
        waitValue(nameField, equals: filename, in: app)
        let save = nativeBar.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.exists && save.isEnabled && save.isHittable,
                      "Expected the native Save action for the unique synthetic filename.\n\(app.debugDescription)")
        XCTAssertEqual(save.label, "Save")
        attach("native-plan-only-file-ready-to-save-unique-synthetic-name", app)
        save.tap()
        waitAbsent(nativeBar)
        let status = app.descendants(matching: .any).matching(identifier: "export.status").firstMatch
        reveal(status, in: app)
        XCTAssertTrue(status.label.contains("Routine exported"),
                      "Only a successful native save callback permits the round-trip check.")
        tap("export.cancel", in: app)
        waitAbsent(app.buttons["export.cancel"])
        assertRoutine(currentTitle, count: 4, approved: true, in: app)

        // Enter the actual file importer, not the explicit staged-file seam.
        tap("routine.import", in: app)
        XCTAssertTrue(nativeBar.waitForExistence(timeout: nativePanelWait),
                      "A real native import panel must appear.\n\(app.debugDescription)")
        let filenamePredicate = NSPredicate(format: "label CONTAINS %@", filename)
        let cells = app.cells.matching(filenamePredicate)
        let buttons = app.buttons.matching(filenamePredicate)
        let labels = app.staticTexts.matching(filenamePredicate)
        var savedFile: XCUIElement?
        let visibleFile = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            savedFile = (cells.allElementsBoundByIndex + buttons.allElementsBoundByIndex
                         + labels.allElementsBoundByIndex).first(where: { $0.isHittable })
            return savedFile != nil
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleFile], timeout: 10), .completed,
                       "The native importer must offer this test's newly saved file; no other file will be selected.\n\(app.debugDescription)")
        guard let savedFile else { return }
        attach("native-importer-shows-the-new-synthetic-export", app)
        savedFile.tap()
        XCTAssertTrue(app.buttons["import.use"].waitForExistence(timeout: 15),
                      "Actual provider selection must pass the real bounded loader.\n\(app.debugDescription)")
        waitAbsent(nativeBar)
        for (index, title) in [currentTitle, "People and messages", "Make room for the day", "A little time to play"].enumerated() {
            let importedTitle = app.staticTexts["import.step.\(index).title"]
            reveal(importedTitle, in: app)
            XCTAssertEqual(importedTitle.label, title)
            XCTAssertFalse(app.staticTexts["import.step.\(index).notes"].exists,
                           "Default plan-only export must not carry this moment's private details into the imported preview.")
        }
        XCTAssertFalse(app.staticTexts["import.source"].exists)
        attach("native-selected-plan-only-file-reviewed-without-notes", app)
        tap("import.use", in: app)
        waitAbsent(app.buttons["import.use"])
        assertRoutine(currentTitle, count: 4, approved: false, in: app)
        for index in 0..<4 {
            let row = app.buttons["routine.step.\(index)"]
            reveal(row, in: app)
            XCTAssertTrue(row.label.contains("Your own pace"),
                          "Every imported moment must be manual, including formerly spoken/calendar steps.")
        }
        tap("routine.step.0", in: app)
        let detail = app.textFields["Step details"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let detailValue = detail.value as? String ?? ""
        XCTAssertTrue(detailValue.isEmpty || detailValue == detail.placeholderValue,
                      "Plan-only details must remain absent in the actual imported draft; an empty field may expose its placeholder.")
        app.navigationBars["Make it yours"].buttons["Cancel"].tap()
        waitAbsent(app.navigationBars["Make it yours"])
        MorningUITestNavigation.closeRoutine(in: app)
        assertCannotStart(in: app)
        relaunchWithoutSeed(app)
        assertCannotStart(in: app)
        openRoutine(in: app)
        assertRoutine(currentTitle, count: 4, approved: false, in: app)
        XCTAssertTrue(app.buttons["routine.restore"].exists)
        attach("native-file-round-trip-restores-as-manual-unapproved-draft", app)
    }

    func testMalformedPortableFilePreservesApprovedRoutine() throws {
        let path = try stagedFilePath(environmentKey: "MO_ROUTINE_IMPORT_MALFORMED_FILE")
        let app = launch(importPath: path, savedBaseline: true)
        openRoutine(in: app)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        tap("routine.importFixture", in: app)
        let error = app.staticTexts["routine.importError"]
        XCTAssertTrue(error.waitForExistence(timeout: 15),
                      "The real staged malformed file must produce a visible loader failure.")
        reveal(error, in: app)
        XCTAssertTrue(error.label.contains("This routine document could not be read"),
                      "The staged malformed bytes must reach decoding; a missing or unreadable file is not a pass.")
        XCTAssertFalse(app.buttons["import.use"].exists)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        attach("synthetic-malformed-portable-file-visible-error-current-routine-preserved", app)
        MorningUITestNavigation.closeRoutine(in: app)
        relaunchWithoutSeed(app)
        openRoutine(in: app)
        assertRoutine(currentTitle, count: 4, approved: true, in: app)
        XCTAssertFalse(app.buttons["import.use"].exists)
    }

    private func stagedFilePath(environmentKey: String) throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_ROUTINE_IMPORT_TEST"] == "1",
              let path = environment[environmentKey], !path.isEmpty else {
            throw XCTSkip("Requires explicit MO_ROUTINE_IMPORT_TEST=1 and a controller-staged synthetic file in \(environmentKey).")
        }
        return path
    }

    private func dragDismissDocumentPanel(_ nativeBar: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(nativeBar.exists && nativeBar.isHittable,
                      "A visible native document header must anchor the dismissal gesture.\n\(app.debugDescription)")
        let start = nativeBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: nativeBar)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                       "The native document sheet must actually dismiss after the header drag.\n\(app.debugDescription)")
    }

    private func launch(importPath: String? = nil, savedBaseline: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
                               "--ui-testing-workspace=\(UUID().uuidString)"]
        if !savedBaseline { app.launchArguments.append("--ui-testing-approved") }
        if let importPath {
            app.launchEnvironment["MO_ROUTINE_IMPORT_TEST"] = "1"
            app.launchEnvironment["MO_ROUTINE_IMPORT_FILE"] = importPath
        }
        app.launch()
        if savedBaseline {
            // Cancellation and rejected imports perform no workspace mutation.
            // Persist the approved baseline through the normal UI beforehand;
            // the launch-only approval flag is not restoration evidence.
            openRoutine(in: app)
            assertRoutine(currentTitle, count: 4, approved: false, in: app)
            tap("routine.approve", in: app)
            waitAbsent(app.navigationBars["Your routine"])
            MorningUITestNavigation.assertMorningAction("run.start", in: app)
        }
        return app
    }

    private func relaunchWithoutSeed(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-approved" }
        app.launch()
    }

    private func openRoutine(in app: XCUIApplication) {
        MorningUITestNavigation.openRoutine(in: app)
    }

    private func openImport(in app: XCUIApplication) {
        tap("routine.importFixture", in: app)
        XCTAssertTrue(app.buttons["import.use"].waitForExistence(timeout: 15),
                      "The real bounded loader must decode the staged file before showing review.")
    }

    private func assertImportedPreview(in app: XCUIApplication) {
        let source = app.staticTexts["import.source"]
        reveal(source, in: app)
        XCTAssertEqual(source.label, importedSource)
        let title = app.staticTexts["import.step.0.title"]
        reveal(title, in: app)
        XCTAssertEqual(title.label, importedTitle)
        let notes = app.staticTexts["import.step.0.notes"]
        reveal(notes, in: app)
        XCTAssertEqual(notes.label, importedNote)
        XCTAssertTrue(app.buttons["import.use"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0,
                       "Reviewing text must not request execution, calendar, microphone or recording permission.")
    }

    private func assertImportedDraft(in app: XCUIApplication) {
        assertRoutine(importedTitle, count: 1, approved: false, in: app)
        let row = app.buttons["routine.step.0"]
        XCTAssertTrue(row.label.contains("7 min planned"))
        XCTAssertTrue(row.label.contains("Your own pace"),
                      "A portable plan must become manual even when it was approved at export.")
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
    }

    private func assertRoutine(_ title: String, count: Int, approved: Bool, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Your routine"].waitForExistence(timeout: 5))
        let first = app.buttons["routine.step.0"]
        // The list creates its rows as they scroll into view. After a scroll down
        // to Import or Export the first row no longer exists, and reveal() cannot
        // tell which way to go for a row that does not exist: go back up here.
        if !first.waitForExistence(timeout: 3) {
            let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            if let list = lists.first(where: { $0.isHittable }) {
                for _ in 0..<4 where !first.exists { list.swipeDown() }
            }
        }
        reveal(first, in: app)
        XCTAssertTrue(first.label.contains(title))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step.")).count, count)
        XCTAssertEqual(app.buttons["routine.approve"].exists, !approved)
    }

    private func assertCannotStart(in app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("morning.reviewDraft", without: "run.start", in: app)
        XCTAssertFalse(app.staticTexts["run.state"].exists)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        reveal(button, in: app)
        button.tap()
    }

    /// Native sheets can leave the underlying Review list in the AX tree.
    /// Scroll only an actually hittable foreground list, including lazy rows.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<8 where !element.isHittable {
            let lists = app.collectionViews.allElementsBoundByIndex
                + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            guard let list = lists.first(where: { $0.isHittable }) else {
                XCTFail("No visible foreground list for \(element.identifier).\n\(app.debugDescription)")
                return
            }
            if element.exists, element.frame.height > 0, element.frame.midY < list.frame.midY { list.swipeDown() }
            else { list.swipeUp() }
        }
        XCTAssertTrue(element.exists, "Missing control: \(element.identifier).\n\(app.debugDescription)")
        XCTAssertTrue(element.isHittable, "Control must be reachable: \(element.identifier).\n\(app.debugDescription)")
    }

    private func waitValue(_ element: XCUIElement, equals value: String, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && (element.value as? String) == value
        }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Expected value \(value).\n\(app.debugDescription)")
    }

    private func waitAbsent(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
