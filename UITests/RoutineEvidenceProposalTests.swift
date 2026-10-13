import XCTest

/// Explicit synthetic assembly through the real selection/persistence/approval flow.
/// These tests do not call Foundation Models or prove model accuracy, audio or recording.
@MainActor
final class RoutineEvidenceProposalTests: XCTestCase {
    private let firstID = "11111111-1111-4111-8111-111111111111"
    private let secondID = "22222222-2222-4222-8222-222222222222"
    private let undatedID = "33333333-3333-4333-8333-333333333333"
    private let currentTitle = "Your morning"
    private let proposedTitle = "A morning to review"

    /// Production UTF-8 import with synthetic content, not a simulated recording or model call.
    func testImportSavesObservationWithoutChangingApprovedRoutine() throws {
        let app = launch(["--ui-testing-import-observation"])
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openLearn(in: app)
        waitForNotes(importedObservation, in: app)
        XCTAssertFalse(app.buttons["proposal.approve"].exists,
                       "Saving an import must not start a routine proposal automatically.")
        XCTAssertTrue(app.navigationBars["Learn my morning"].exists,
                      "The imported observation must remain available for review.")
        attach("synthetic-text-import-saved-for-review-only", app)
        closeLearn(in: app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists)
        let originalRows = [firstID, secondID, undatedID]
        let importedRow = try XCTUnwrap(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "observation.row.")).allElementsBoundByIndex.first {
                !originalRows.contains(String($0.identifier.dropFirst("observation.row.".count)))
            })
        let importedIdentifier = importedRow.identifier

        app.launchArguments.removeAll { $0 == "--ui-testing-import-observation" }
        relaunchWithoutSeed(app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openLearn(in: app)
        waitForNotes(importedObservation, in: app)
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        closeLearn(in: app)
        openArchive(in: app)
        XCTAssertTrue(app.buttons[importedIdentifier].exists,
                      "Saved evidence must survive without reimporting or generating a routine.")
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists)
        attach("synthetic-text-import-restored-approved-routine-preserved", app)
    }

    /// Saved imported text can be reviewed independently of native recording support.
    /// This does not start capture, obtain consent or call the local model.
    func testMorningNoticeHandsOffToSavedObservationAfterDismissal() throws {
        let app = launch(["--ui-testing-import-observation"])
        openLearn(in: app)
        waitForNotes(importedObservation, in: app)
        closeLearn(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("morning.attention", in: app)
        let notice = app.navigationBars["Your morning"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        let review = app.buttons["observation.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isHittable,
                      "The saved-observation action must be reachable in the notice sheet.")
        attach("synthetic-import-review-in-morning-notice", app)
        review.tap()
        waitAbsent(notice)
        let learn = app.navigationBars["Learn my morning"]
        XCTAssertTrue(learn.waitForExistence(timeout: 5),
                      "Learn must open after the notice finishes dismissing.")
        XCTAssertTrue(learn.buttons["Done"].isHittable)
        waitForNotes(importedObservation, in: app)
        scrollTo(app.textViews["learn.notes"], in: app)
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach("synthetic-notice-dismissed-before-learn-review", app)
        closeLearn(in: app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists,
                       "Reviewing saved text must not generate or install a routine.")
    }

    /// A real failed external-file import leaves a reviewable prior observation.
    /// Its queued review waits for a paused manual morning to end. This does not
    /// test native capture, owned-recording recovery, speech or model inference.
    func testPausedMorningDefersSavedObservationReviewUntilItEnds() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_BLANK_OBSERVATION_TEST"] == "1",
              let supplied = environment["MO_RECORDED_OBSERVATION_WORKSPACE"],
              let workspaceID = UUID(uuidString: supplied) else {
            throw XCTSkip("Requires an explicitly staged BlankObservation.mov fault-test movie and an isolated workspace UUID.")
        }
        let app = launch(["--ui-testing-import-observation"], workspaceID: workspaceID)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openLearn(in: app)
        waitForNotes(importedObservation, in: app)
        app.terminate()

        // Keep the approved routine and saved text in the same workspace. This
        // hook must reach real blank extraction, never missing-file substitute data.
        app.launchArguments.removeAll {
            $0 == "--ui-testing-import-observation" || $0 == "--ui-testing-observation-archive"
                || $0 == "--ui-testing-approved"
        }
        app.launchArguments.append("--ui-testing-import-blank-video")
        app.launch()
        openLearn(in: app)
        let failure = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "No readable text was found in", "Your previous observation is unchanged.")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 120),
                      "The staged blank movie must reach the actual no-readable-text failure; missing media is not a pass.")
        waitForNotes(importedObservation, in: app)
        XCTAssertFalse(app.staticTexts["learn.videoEvidence"].exists,
                       "The failed video must not replace the saved text observation.")
        closeLearn(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("run.start", in: app)
        assertRun("running", step: currentTitle, in: app)
        tap("run.pause", in: app)
        assertRun("paused", step: currentTitle, in: app)

        tap("morning.attention", in: app)
        let notice = app.navigationBars["Your morning"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        let review = app.buttons["observation.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isHittable)
        review.tap()
        waitAbsent(notice)
        let learn = app.navigationBars["Learn my morning"]
        let prematureReview = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"), object: learn)
        prematureReview.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [prematureReview], timeout: 2), .completed,
                       "A paused morning must continue to block the queued saved-observation review.")
        assertRun("paused", step: currentTitle, in: app)
        XCTAssertTrue(app.buttons["run.resume"].isHittable)
        attach("synthetic-saved-observation-review-deferred-while-paused", app)

        // The automatic sheet handoff can hide the stopped-state label immediately;
        // verify it below once the requested review has been closed.
        stopRun(in: app, verifyStoppedState: false)
        XCTAssertTrue(learn.waitForExistence(timeout: 5),
                      "Ending the paused morning must present the queued review without another tap.")
        XCTAssertTrue(learn.buttons["Done"].isHittable)
        waitForNotes(importedObservation, in: app)
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach("synthetic-saved-observation-review-opened-after-morning-ended", app)
        closeLearn(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        let stopped = app.staticTexts["morning.heading"]
        XCTAssertTrue(stopped.waitForExistence(timeout: 5))
        XCTAssertEqual(stopped.value as? String, "stopped")
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists,
                       "Deferred review must preserve the approved routine without generating a proposal.")
    }

    func testLearnRequiresExplicitProvenanceThenReviewsSingleSourceBeforeApproval() throws {
        let app = launch(["--ui-testing-import-observation"])
        openLearn(in: app)
        waitForNotes(importedObservation, in: app)
        let fixture = app.descendants(matching: .any).matching(identifier: "learn.fixtureMode").firstMatch
        scrollTo(fixture, in: app)
        XCTAssertTrue(fixture.label.contains("no Apple model call"))
        tap("learn.analyze", in: app)
        XCTAssertTrue(app.buttons["observation.saveDate"].waitForExistence(timeout: 5),
                      "An undated import must request provenance instead of generating a draft.")
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        let cancel = app.navigationBars["Observed day"].buttons["Cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        waitAbsent(app.buttons["observation.saveDate"])
        XCTAssertTrue(app.textViews["learn.notes"].exists)
        XCTAssertFalse(app.buttons["proposal.approve"].exists,
                       "Cancelling provenance must not create a suggestion or infer a date.")
        tap("learn.analyze", in: app)
        XCTAssertTrue(app.buttons["observation.saveDate"].waitForExistence(timeout: 5))
        tap("observation.originPicker", in: app)
        tap("Sample or test", in: app)
        tap("observation.saveDate", in: app)
        waitAbsent(app.buttons["observation.saveDate"])
        XCTAssertTrue(app.textViews["learn.notes"].exists)
        XCTAssertFalse(app.buttons["proposal.approve"].exists,
                       "Saving a day and origin must not implicitly start analysis.")
        tap("learn.analyze", in: app)
        assertProposalPresented(in: app)
        let explanation = app.buttons["Why this suggestion?"]
        revealProposalElement(explanation, in: app)
        explanation.tap()
        let quote = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "proposal.quote.", "“\(importedObservation)”")).firstMatch
        revealProposalElement(quote, in: app)
        XCTAssertEqual(quote.label, "“\(importedObservation)”",
                       "The only source quote must come from the selected actual text import.")
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "proposal.source.")).firstMatch
        revealProposalElement(source, in: app)
        let sourceID = source.identifier
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "proposal.source.")).count, 1)
        attach("synthetic-learn-single-source-proposal-with-explicit-provenance", app)
        closeProposal(in: app)
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 5),
                      "Dismissing a suggestion must return to Learn without replacing the current routine.")
        closeLearn(in: app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)

        app.launchArguments.removeAll { $0 == "--ui-testing-import-observation" }
        relaunchWithoutSeed(app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openLearn(in: app)
        waitForNotes(importedObservation, in: app)
        tap("learn.reviewProposal", in: app)
        assertProposalPresented(in: app)
        let restoredExplanation = app.buttons["Why this suggestion?"]
        revealProposalElement(restoredExplanation, in: app)
        restoredExplanation.tap()
        revealProposalElement(app.buttons[sourceID], in: app)
        tap("proposal.approve", in: app)
        waitForProposalToClose(in: app)
        waitAbsent(app.textViews["learn.notes"])
        assertApprovedRoutine(proposedTitle, count: 1, in: app)
        relaunchWithoutSeed(app)
        assertApprovedRoutine(proposedTitle, count: 1, in: app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists)
        XCTAssertTrue(app.buttons[sourceID.replacingOccurrences(of: "proposal.source.", with: "observation.row.")].exists)
        attach("synthetic-learn-proposal-approved-only-after-review", app)
    }

    func testCompactProposalShowsMomentAndBothReviewActions() {
        let app = launch()
        createProposal(from: [firstID, secondID], in: app)
        let moment = app.descendants(matching: .any).matching(identifier: "proposal.step.0").firstMatch
        XCTAssertTrue(moment.isHittable, "The suggested moment must be visible before scrolling.")
        XCTAssertTrue(app.buttons["proposal.keepCurrent"].isHittable,
                      "Keeping the current routine must be immediately reachable.")
        XCTAssertTrue(app.buttons["proposal.approve"].isHittable,
                      "Approval must be immediately reachable.")
        attach("synthetic-proposal-compact-review-actions", app)
        closeProposal(in: app)
    }

    func testReviewAndRelaunchKeepCurrentRoutineUntilExplicitApproval() {
        let app = launch()
        createProposal(from: [firstID, secondID], in: app)
        assertSelectedEvidence(in: app)
        closeProposal(in: app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)

        relaunchWithoutSeed(app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        openPendingProposal(in: app)
        XCTAssertTrue(app.buttons["proposal.approve"].isEnabled)
        attach("synthetic-proposal-restored-current-routine-unchanged", app)
        tap("proposal.approve", in: app)
        waitForProposalToClose(in: app)

        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists)
        XCTAssertTrue(app.buttons["observation.row.\(firstID)"].exists,
                      "Approval must preserve its source observations.")
        XCTAssertTrue(app.buttons["observation.row.\(secondID)"].exists)
        openRoutine(in: app)
        assertRoutineRows(proposedTitle, count: 1, in: app)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertTrue(app.buttons["routine.restore"].exists,
                      "The previous approved routine must remain recoverable after approval and relaunch.")
        tap("routine.restore", in: app)
        assertRoutineRows(currentTitle, count: 4, in: app)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.closeRoutine(in: app)
        relaunchWithoutSeed(app)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        attach("synthetic-proposal-approved-then-previous-routine-restored", app)
    }

    func testKeepCurrentDiscardsOnlyProposalAndCurrentRoutineStillStarts() {
        let app = launch()
        createProposal(from: [firstID, secondID], in: app)
        tap("proposal.keepCurrent", in: app)
        waitForProposalToClose(in: app)
        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists)
        for id in [firstID, secondID, undatedID] {
            XCTAssertTrue(app.buttons["observation.row.\(id)"].exists,
                          "Rejecting a proposal must not delete an observation.")
        }
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("run.start", in: app)
        assertRun("running", step: currentTitle, in: app)
        attach("synthetic-proposal-rejected-current-routine-running", app)
        stopRun(in: app)
    }

    func testCorrectingReferencedNotesInvalidatesProposalAcrossRelaunch() throws {
        let app = launch()
        createProposal(from: [firstID], in: app)
        closeProposal(in: app)
        openObservation(firstID, in: app)
        tap("observation.edit", in: app)
        let editor = app.textViews["learn.notes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        scrollTo(editor, in: app)
        let before = try XCTUnwrap(editor.value as? String)
        editor.tap()
        editor.typeText(" Keep this changed observation.")
        let changed = try XCTUnwrap(editor.value as? String)
        XCTAssertNotEqual(changed, before)
        XCTAssertTrue(changed.contains("Keep this changed observation."))
        let keyboardDone = app.buttons["input.done"]
        if keyboardDone.exists && keyboardDone.isHittable { keyboardDone.tap() }
        let learn = app.navigationBars["Learn my morning"]
        XCTAssertTrue(learn.buttons["Done"].isHittable)
        learn.buttons["Done"].tap()
        waitAbsent(learn)

        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists,
                       "A proposal citing the previous notes must not reappear after relaunch.")
        tap("observation.row.\(firstID)", in: app)
        tap("Current notes", in: app)
        XCTAssertEqual(app.staticTexts["observation.currentText"].label, changed)
        tap("Original extracted text", in: app)
        XCTAssertEqual(app.staticTexts["observation.originalText"].label,
                       "Original sample A: calendar, water, chess.")
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        attach("synthetic-proposal-invalidated-by-correction", app)
    }

    func testRemovingObservedDateAndDeletingSourceInvalidateTheirProposals() {
        let app = launch()
        createProposal(from: [firstID], in: app)
        closeProposal(in: app)
        openObservation(firstID, in: app)
        tap("observation.setDate", in: app)
        tap("observation.removeDate", in: app)
        let dateValue = app.descendants(matching: .any).matching(identifier: "observation.observedDate").firstMatch
        let undated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            dateValue.exists && (dateValue.value as? String) == "Date needed"
        }, object: dateValue)
        XCTAssertEqual(XCTWaiter.wait(for: [undated], timeout: 5), .completed)
        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists,
                       "Changing an observation's date must invalidate the saved proposal.")

        // A separate still-dated source can produce a new explicit synthetic proposal.
        createProposal(from: [secondID], in: app)
        closeProposal(in: app)
        openObservation(secondID, in: app)
        tap("observation.delete", in: app)
        let alert = app.alerts["Delete this observation?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete observation"].tap()
        XCTAssertTrue(app.navigationBars["Observations"].waitForExistence(timeout: 5))
        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists,
                       "A deleted cited observation cannot leave an approvable proposal.")
        XCTAssertFalse(app.buttons["observation.row.\(secondID)"].exists)
        XCTAssertTrue(app.buttons["observation.row.\(firstID)"].exists)
        XCTAssertTrue(app.buttons["observation.row.\(undatedID)"].exists)
        assertApprovedRoutine(currentTitle, count: 4, in: app)
        attach("synthetic-proposals-invalidated-by-date-and-source-deletion", app)
    }

    func testPausedSessionBlocksProposalApprovalWithoutChangingPinnedStep() {
        let app = launch()
        createProposal(from: [firstID, secondID], in: app)
        closeProposal(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("run.start", in: app)
        assertRun("running", step: currentTitle, in: app)
        tap("run.pause", in: app)
        assertRun("paused", step: currentTitle, in: app)
        openPendingProposal(in: app)
        XCTAssertFalse(app.buttons["proposal.approve"].isEnabled,
                       "A paused session is still active and pins its approved version.")
        attach("synthetic-proposal-approval-blocked-by-paused-session", app)
        closeProposal(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        assertRun("paused", step: currentTitle, in: app)
        stopRun(in: app)
        openPendingProposal(in: app)
        XCTAssertTrue(app.buttons["proposal.approve"].isEnabled,
                      "Stopping the pinned run should permit an otherwise current proposal.")
        closeProposal(in: app)
    }

    func testSavedKeepAndDurationSurviveRelaunchThenClearInvalidatesProposal() {
        let app = launch()
        openRoutine(in: app)
        openStep(0, in: app)
        increaseDuration(by: 1, expectedMinutes: 4, in: app)
        setChoice("step.keepFuture", enabled: true, in: app)
        assertChoice("step.keepDuration", enabled: true, in: app)
        saveStep(in: app)
        approveEditedRoutine(in: app)

        relaunchWithoutSeed(app)
        openRoutine(in: app)
        openStep(0, in: app)
        assertChoice("step.keepFuture", enabled: true, in: app)
        assertChoice("step.keepDuration", enabled: true, in: app)
        let duration = app.steppers["step.duration"]
        revealProposalElement(duration, in: app)
        XCTAssertEqual(duration.value as? String, "4")
        app.navigationBars["Make it yours"].buttons["Cancel"].tap()
        waitAbsent(app.navigationBars["Make it yours"])
        tap("routine.preferences", in: app)
        XCTAssertTrue(app.navigationBars["Saved choices"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[currentTitle].exists)
        XCTAssertTrue(app.staticTexts["4 planned minutes, chosen by you"].exists)
        leaveSavedChoices(in: app)
        MorningUITestNavigation.closeRoutine(in: app)

        createProposal(from: [firstID, secondID], in: app)
        let kept = app.descendants(matching: .any).matching(identifier: "proposal.step.1").firstMatch
        revealProposalElement(kept, in: app)
        XCTAssertEqual(kept.value as? String, currentTitle)
        XCTAssertTrue(app.staticTexts["4 minutes planned"].exists)
        XCTAssertTrue(app.staticTexts["Kept by your choice"].exists)
        attach("synthetic-saved-keep-and-duration-applied-after-relaunch", app)
        closeProposal(in: app)

        openRoutine(in: app)
        tap("routine.preferences", in: app)
        let clear = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "preferences.clear.")).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "preferences.empty").firstMatch.waitForExistence(timeout: 5))
        leaveSavedChoices(in: app)
        assertRoutineRows(currentTitle, count: 4, in: app)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("4 min planned"),
                      "Clearing future choices must not rewrite the current approved routine.")
        MorningUITestNavigation.closeRoutine(in: app)

        relaunchWithoutSeed(app)
        openArchive(in: app)
        XCTAssertFalse(app.buttons["observations.reviewProposal"].exists,
                       "A proposal based on the cleared preference revision must be invalidated durably.")
        createProposal(from: [firstID, secondID], in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "proposal.step.1").firstMatch.exists,
                       "An explicitly cleared keep must not return through the old required flag.")
        XCTAssertFalse(app.staticTexts["Kept by your choice"].exists)
        attach("synthetic-cleared-keep-no-longer-retained-in-next-proposal", app)
    }

    func testSavedTimingRetainsCitationsAndRenameCanClearMatchedChoice() {
        let app = launch()
        createProposal(from: [firstID, secondID], in: app)
        tap("proposal.approve", in: app)
        waitForProposalToClose(in: app)
        openRoutine(in: app)
        openStep(0, in: app)
        assertChoice("step.keepFuture", enabled: false, in: app)
        increaseDuration(by: 2, expectedMinutes: 5, in: app)
        assertChoice("step.keepDuration", enabled: true, in: app)
        saveStep(in: app)
        approveEditedRoutine(in: app)

        relaunchWithoutSeed(app)
        openRoutine(in: app)
        tap("routine.preferences", in: app)
        XCTAssertTrue(app.staticTexts["5 planned minutes, chosen by you"].waitForExistence(timeout: 5))
        leaveSavedChoices(in: app)
        MorningUITestNavigation.closeRoutine(in: app)
        createProposal(from: [firstID, secondID], in: app)
        XCTAssertTrue(app.staticTexts["5 minutes planned"].exists,
                      "The saved timing must override the fixture's newly inferred three minutes.")
        let timing = app.descendants(matching: .any).matching(identifier: "proposal.userTiming").firstMatch
        revealProposalElement(timing, in: app)
        XCTAssertTrue(timing.label.contains("Your saved timing choice"))
        assertSelectedEvidence(in: app)
        closeProposal(in: app)
        relaunchWithoutSeed(app)
        openPendingProposal(in: app)
        XCTAssertTrue(app.staticTexts["5 minutes planned"].exists)
        revealProposalElement(timing, in: app)
        tap("proposal.approve", in: app)
        waitForProposalToClose(in: app)

        // Approval installs a fresh model step identity. Rename that row while
        // removing its timing choice: matching must use the original row first.
        relaunchWithoutSeed(app)
        openRoutine(in: app)
        assertRoutineRows(proposedTitle, count: 1, in: app)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("5 min planned"))
        openStep(0, in: app)
        assertChoice("step.keepFuture", enabled: false, in: app)
        setChoice("step.keepDuration", enabled: false, in: app)
        let name = app.textFields["Step name"]
        scrollTo(name, in: app)
        name.tap()
        name.typeText(" renamed choice")
        XCTAssertNotEqual(name.value as? String, proposedTitle)
        saveStep(in: app)
        XCTAssertFalse(app.buttons["routine.preferences"].exists,
                       "Renaming while clearing duration must remove the old matching preference, not strand it.")
        approveEditedRoutine(in: app)
        relaunchWithoutSeed(app)
        createProposal(from: [firstID, secondID], in: app)
        XCTAssertTrue(app.staticTexts["3 minutes planned"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "proposal.userTiming").firstMatch.exists)
        assertSelectedEvidence(in: app)
        attach("synthetic-renamed-row-clears-old-timing-choice-and-preserves-citations", app)
    }

    func testExcludedActivityStaysOutWhenFixtureSuggestsItAgain() {
        let app = launch()
        openRoutine(in: app)
        openStep(0, in: app)
        setChoice("step.keepFuture", enabled: true, in: app)
        saveStep(in: app)
        approveEditedRoutine(in: app)
        createProposal(from: [firstID, secondID], in: app)
        tap("proposal.approve", in: app)
        waitForProposalToClose(in: app)
        openRoutine(in: app)
        assertRoutineRows(proposedTitle, count: 2, in: app)
        openStep(0, in: app)
        let remove = app.buttons["step.remove"]
        revealProposalElement(remove, in: app)
        remove.tap()
        let confirmation = app.sheets["Remove this moment?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let exclude = confirmation.buttons.matching(identifier: "step.exclude").firstMatch
        XCTAssertTrue(exclude.waitForExistence(timeout: 5))
        XCTAssertTrue(exclude.isHittable)
        exclude.tap()
        waitAbsent(app.navigationBars["Make it yours"])
        assertRoutineRows(currentTitle, count: 1, in: app)
        approveEditedRoutine(in: app)

        relaunchWithoutSeed(app)
        openRoutine(in: app)
        tap("routine.preferences", in: app)
        let excluded = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "preferences.title.", proposedTitle)).firstMatch
        scrollTo(excluded, in: app)
        XCTAssertEqual(excluded.label, proposedTitle)
        let exclusion = app.staticTexts["Leave out of future suggestions"]
        scrollTo(exclusion, in: app)
        XCTAssertTrue(exclusion.exists)
        leaveSavedChoices(in: app)
        MorningUITestNavigation.closeRoutine(in: app)

        // The same fixture again submits A morning to review. Its persisted
        // exclusion removes it; the separately chosen ritual is still retained.
        createProposal(from: [firstID, secondID], expectedFirstTitle: currentTitle, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "proposal.step.1").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Kept by your choice"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "proposal.userTiming").firstMatch.exists)
        attach("synthetic-exclusion-removes-returning-fixture-and-retains-chosen-ritual", app)
        tap("proposal.approve", in: app)
        waitForProposalToClose(in: app)
        relaunchWithoutSeed(app)
        assertApprovedRoutine(currentTitle, count: 1, in: app)
        openArchive(in: app)
        for id in [firstID, secondID, undatedID] {
            XCTAssertTrue(app.buttons["observation.row.\(id)"].exists,
                          "Excluding an activity must not delete its source observations.")
        }
    }

    private func openStep(_ index: Int, in app: XCUIApplication) {
        tap("routine.step.\(index)", in: app)
        XCTAssertTrue(app.navigationBars["Make it yours"].waitForExistence(timeout: 5))
    }

    private func assertChoice(_ identifier: String, enabled: Bool, in app: XCUIApplication) {
        let choice = app.switches[identifier]
        revealProposalElement(choice, in: app)
        let expectedValue = enabled ? "1" : "0"
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            choice.exists && (choice.value as? String) == expectedValue
        }, object: choice)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "Unexpected saved choice: \(identifier).\n\(app.debugDescription)")
    }

    private func setChoice(_ identifier: String, enabled: Bool, in app: XCUIApplication) {
        let choice = app.switches[identifier]
        revealProposalElement(choice, in: app)
        if (choice.value as? String) != (enabled ? "1" : "0") {
            // SwiftUI exposes both a full-width row and its native UISwitch.
            // The row's center is text, so operate the nested switch itself.
            let control = choice.switches.firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5),
                          "Missing native switch for \(identifier).\n\(app.debugDescription)")
            XCTAssertTrue(control.isHittable)
            control.tap()
        }
        assertChoice(identifier, enabled: enabled, in: app)
    }

    private func increaseDuration(by count: Int, expectedMinutes: Int, in app: XCUIApplication) {
        let duration = app.steppers["step.duration"]
        revealProposalElement(duration, in: app)
        let increment = duration.buttons["step.duration-Increment"]
        XCTAssertTrue(increment.exists, "Expected the native duration stepper increment control.\n\(app.debugDescription)")
        for _ in 0..<count { increment.tap() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            duration.exists && (duration.value as? String) == String(expectedMinutes)
        }, object: duration)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "The planned duration must reflect the native increment taps.\n\(app.debugDescription)")
    }

    private func saveStep(in app: XCUIApplication) {
        tap("step.save", in: app)
        waitAbsent(app.navigationBars["Make it yours"])
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
    }

    private func approveEditedRoutine(in app: XCUIApplication) {
        tap("routine.approve", in: app)
        waitAbsent(app.navigationBars["Your routine"])
        MorningUITestNavigation.assertMorningAction("run.start", in: app)
    }

    private func leaveSavedChoices(in app: XCUIApplication) {
        let back = app.navigationBars["Saved choices"].buttons["Your routine"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.navigationBars["Your routine"].waitForExistence(timeout: 5))
    }

    private func launch(_ extra: [String] = [], workspaceID: UUID = UUID()) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(workspaceID.uuidString)", "--ui-testing-approved",
            "--ui-testing-observation-archive", "--ui-testing-evidence-proposals"] + extra
        app.launch()
        return app
    }

    private var importedObservation: String {
        "[Synthetic UI-test observation]\nI check my calendar, drink water, and enjoy ten minutes of chess."
    }

    private func openLearn(in app: XCUIApplication) {
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 10))
    }

    private func closeLearn(in app: XCUIApplication) {
        let learn = app.navigationBars["Learn my morning"]
        XCTAssertTrue(learn.buttons["Done"].isHittable)
        learn.buttons["Done"].tap()
        waitAbsent(app.textViews["learn.notes"])
    }

    private func waitForNotes(_ expected: String, in app: XCUIApplication) {
        let editor = app.textViews["learn.notes"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            editor.exists && editor.isEnabled && (editor.value as? String) == expected
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed,
                       "The actual asynchronous importer must finish with the full synthetic source.")
    }

    private func relaunchWithoutSeed(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-observation-archive" || $0 == "--ui-testing-approved" }
        app.launch()
    }

    private func reviewRoot(in app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("morning.date", in: app)
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5))
    }

    private func openArchive(in app: XCUIApplication) {
        reviewRoot(in: app)
        tap("review.observations", in: app)
        XCTAssertTrue(app.navigationBars["Observations"].waitForExistence(timeout: 5))
    }

    private func openObservation(_ id: String, in app: XCUIApplication) {
        openArchive(in: app)
        tap("observation.row.\(id)", in: app)
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 5))
    }

    private func createProposal(from ids: [String], expectedFirstTitle: String = "A morning to review", in app: XCUIApplication) {
        openArchive(in: app)
        tap("observations.choose", in: app)
        for id in ids {
            let choice = app.buttons["observation.select.\(id)"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            XCTAssertTrue(choice.isEnabled)
            if (choice.value as? String) != "Selected" { tap(choice.identifier, in: app) }
            XCTAssertEqual(choice.value as? String, "Selected")
        }
        let fixture = app.descendants(matching: .any).matching(identifier: "observations.fixtureMode").firstMatch
        XCTAssertTrue(fixture.exists)
        XCTAssertTrue(fixture.label.contains("no Apple model call"),
                      "The synthetic path must disclose that it did not invoke the native model.")
        let suggest = app.buttons["observations.suggestUpdate"]
        XCTAssertTrue(suggest.isEnabled)
        tap("observations.suggestUpdate", in: app)
        assertProposalPresented(expectedFirstTitle: expectedFirstTitle, in: app)
    }

    private func openPendingProposal(in app: XCUIApplication) {
        openArchive(in: app)
        tap("observations.reviewProposal", in: app)
        assertProposalPresented(in: app)
    }

    private func assertProposalPresented(expectedFirstTitle: String = "A morning to review", in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["proposal.approve"].waitForExistence(timeout: 15))
        let step = app.descendants(matching: .any).matching(identifier: "proposal.step.0").firstMatch
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(step.value as? String, expectedFirstTitle)
        XCTAssertEqual(app.alerts.count, 0, "Synthetic suggestions must not request external permissions.")
    }

    private func assertSelectedEvidence(in app: XCUIApplication) {
        let explanation = app.buttons["Why this suggestion?"]
        revealProposalElement(explanation, in: app)
        explanation.tap()
        // A has a saved correction; B still uses its original text. Both exact
        // quotations must be reviewable rather than only a count of sources.
        for text in ["Edited sample A: calendar, water, chess and tea.",
                     "Original sample B: weather and a walk."] {
            let quote = app.staticTexts.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "proposal.quote.", "“\(text)”")).firstMatch
            revealProposalElement(quote, in: app)
            XCTAssertEqual(quote.label, "“\(text)”")
        }
        for id in [firstID, secondID] {
            let source = app.buttons["proposal.source.\(id)"]
            revealProposalElement(source, in: app)
            XCTAssertTrue(source.isEnabled, "The cited acquisition must have a reachable source link.")
        }
        attach("synthetic-proposal-exact-corrected-and-original-evidence", app)
    }

    /// A List can instantiate evidence rows only after scrolling. Choose the
    /// visible sheet's list, rather than the hidden Review list underneath it.
    private func revealProposalElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            let collections = app.collectionViews.allElementsBoundByIndex
            let tables = app.tables.allElementsBoundByIndex
            let scrolls = app.scrollViews.allElementsBoundByIndex
            guard let list = (collections + tables + scrolls).first(where: { $0.isHittable }) else {
                XCTFail("No visible suggestion list for the evidence control.")
                return
            }
            if element.exists, element.frame.height > 0, element.frame.midY < list.frame.midY { list.swipeDown() }
            else { list.swipeUp() }
        }
        XCTAssertTrue(element.exists, "Missing suggestion evidence: \(element.identifier)")
        XCTAssertTrue(element.isHittable, "Suggestion evidence must be visible: \(element.identifier)")
    }

    private func closeProposal(in app: XCUIApplication) {
        tap("proposal.close", in: app)
        waitForProposalToClose(in: app)
    }

    private func waitForProposalToClose(in app: XCUIApplication) {
        waitAbsent(app.buttons["proposal.approve"])
    }

    private func openRoutine(in app: XCUIApplication) {
        reviewRoot(in: app)
        tap("review.routine", in: app)
        XCTAssertTrue(app.navigationBars["Your routine"].waitForExistence(timeout: 5))
    }

    private func assertApprovedRoutine(_ title: String, count: Int, in app: XCUIApplication) {
        openRoutine(in: app)
        assertRoutineRows(title, count: count, in: app)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        MorningUITestNavigation.closeRoutine(in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.assertMorningAction("run.start", in: app)
    }

    private func assertRoutineRows(_ title: String, count: Int, in app: XCUIApplication) {
        let first = app.buttons["routine.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains(title))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step.")).count, count)
    }

    private func assertRun(_ state: String, step: String, in app: XCUIApplication) {
        let status = app.staticTexts["run.state"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, state)
        XCTAssertEqual(app.staticTexts["run.step"].label, step)
    }

    private func stopRun(in app: XCUIApplication, verifyStoppedState: Bool = true) {
        tap("run.controls", in: app)
        tap("run.stop", in: app)
        guard verifyStoppedState else { return }
        let stopped = app.staticTexts["morning.heading"]
        XCTAssertTrue(stopped.waitForExistence(timeout: 5))
        XCTAssertEqual(stopped.value as? String, "stopped")
        XCTAssertFalse(app.buttons["run.pause"].exists)
        XCTAssertFalse(app.buttons["run.resume"].exists)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        MorningUITestNavigation.tapButton(identifier, in: app)
    }

    private func waitAbsent(_ element: XCUIElement) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 5), .completed)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            let scroll = app.scrollViews.containing(element.elementType, identifier: element.identifier).firstMatch
            let container = scroll.exists ? scroll : app.collectionViews.firstMatch
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
