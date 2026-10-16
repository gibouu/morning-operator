import XCTest
import MorningCore

/// Private downstream journey, not video learning or ten provider actions. The
/// immutable manual oracle supplies no authority. Ordinary UI configuration and
/// approval delegate Calendar, read-only Gmail and the closed Slack transport;
/// the other seven moments only consume their original, real-minute budgets.
/// Local TTS and ordinary connected-result narration may run or be unavailable;
/// acoustic quality, live accounts, web actions and MORE §10 are not certified.
@MainActor final class ImportedLongRoutineJourneyTests: XCTestCase {
    /// Exercises real native formatting and TTS caption callbacks only. This is
    /// neither a local-language-model verdict nor proof that a person heard it.
    func testSingleCalendarMomentShowsItsNativeSpokenFacts() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let portable = #"{"format":"morning-operator.routine","formatVersion":1,"detail":"includeDetails","sourceRoutineID":"91000000-0000-4000-8000-000000000100","sourceRoutineVersion":1,"sourceCreatedAt":1792129500.0,"approvalAtExport":false,"sourceIsSynthetic":true,"sourceLabel":"SYNTHETIC manual Calendar speech smoke; no inferred operation","steps":[{"id":"91000000-0000-4000-8000-000000000001","title":"SYNTHETIC my calendar","kind":"calendar","durationMinutes":2,"isRequired":false,"detail":"SYNTHETIC manual Calendar moment. Select its source and operation in the app."}]}"#
        let data = Data(portable.utf8), document = try PortableRoutineDocument.decode(data)
        let draft = try document.importedDraft(replacing: nil)
        XCTAssertTrue(draft.isSynthetic && !draft.isApproved && !document.approvalAtExport)
        XCTAssertEqual(draft.steps.count, 1)
        XCTAssertTrue(draft.steps.allSatisfy { $0.automation == nil && $0.target == nil })
        let app = XCUIApplication(), workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-briefing-fixture", "--ui-testing-hands-free", "--ui-testing-read-aloud",
            "--light-preview", "--theme-phase=morning", "--ui-testing-parsed-routine=" + data.base64EncodedString(),
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-more.appLanguage", "en"]
        app.launch(); defer { app.terminate() }
        try requireWorkspace(workspace, app); try requireAcceptedImport(app)
        openRoutine(app)
        XCTAssertTrue(button("routine.approve", app).isEnabled)
        XCTAssertTrue(button("routine.step.0", app).label.contains("Your own moment"))
        XCTAssertFalse(app.buttons["routine.step.1"].exists)
        back(app); configureCalendar(app); tap("setup.routine", app)
        configureOperation(0, action: "Read today's calendar", minutes: 2,
            detail: "SYNTHETIC selected Calendar reading. No model-generated recap or event write.", in: app)
        XCTAssertTrue(button("routine.step.0", app).label.contains("2 min"))
        attach("calendar-direct-configured-through-ui-unapproved", app)
        tap("routine.approve", app)
        home(app); reveal(app); tap("morning.begin", app)
        beginRoutineFromOpening(app)
        let pinned = try XCTUnwrap(app.scrollViews["morning.captions"].value as? String)
        let fields = pinned.components(separatedBy: "|")
        XCTAssertEqual(fields.count, 2, "This smoke uses the ordinary two-field QA identity, not a fake timer or model.")
        XCTAssertEqual(fields.last, document.steps[0].id.uuidString)
        waitForNativeCalendarPassage(app)
        XCTAssertEqual(app.scrollViews["morning.captions"].value as? String, pinned)
        attach("calendar-direct-native-facts-actual-caption-no-model-proof", app)
        // No Next, clock override, shortened budget or completion claim.
    }

    func testManualOracleThroughUIConfigurationRunsTenMomentsInOnePinnedSession() throws {
        continueAfterFailure = false
        executionTimeAllowance = 2_700
        // Literal copy of the frozen English portable oracle, not an inference
        // result. The phone runner cannot read a host-only #filePath fixture.
        let portable = #"{"format":"morning-operator.routine","formatVersion":1,"detail":"includeDetails","sourceRoutineID":"90000000-0000-4000-8000-000000000100","sourceRoutineVersion":1,"sourceCreatedAt":1792129500.0,"approvalAtExport":false,"sourceIsSynthetic":true,"sourceLabel":"Demo fixture — SYNTHETIC manual oracle; no OCR or model execution","steps":[{"id":"90000000-0000-4000-8000-000000000001","title":"My agenda","kind":"calendar","durationMinutes":2,"isRequired":false,"detail":"SYNTHETIC — Read the invented primary calendar without confusing namesakes."},{"id":"90000000-0000-4000-8000-000000000002","title":"My mail and reply","kind":"messages","durationMinutes":5,"isRequired":false,"detail":"SYNTHETIC — Choose the third mail, correct six blue cards to eight green cards, review, then simulate exactly one send."},{"id":"90000000-0000-4000-8000-000000000003","title":"My team","kind":"messages","durationMinutes":3,"isRequired":false,"detail":"SYNTHETIC — An uncertain simulated reply must never be retried automatically."},{"id":"90000000-0000-4000-8000-000000000004","title":"Second article and return","kind":"briefing","durationMinutes":4,"isRequired":false,"detail":"SYNTHETIC — Select the second observed link, read attributed text, return to the headlines with remaining budget."},{"id":"90000000-0000-4000-8000-000000000005","title":"My feed at my pace","kind":"entertainment","durationMinutes":3,"isRequired":false,"detail":"SYNTHETIC — Pause, then resume. The personal three-minute choice overrides four minutes observed in the realistic source."},{"id":"90000000-0000-4000-8000-000000000006","title":"My videos","kind":"entertainment","durationMinutes":3,"isRequired":false,"detail":"SYNTHETIC — Two successive invented items. No real service control is proven."},{"id":"90000000-0000-4000-8000-000000000007","title":"My exact reminder","kind":"custom","durationMinutes":1,"isRequired":false,"detail":"SYNTHETIC — Bring the blue notebook to North studio. 16 October 2026 at 09:25 Europe/Paris. One simulated write."},{"id":"90000000-0000-4000-8000-000000000008","title":"Read five pages","kind":"wellbeing","durationMinutes":3,"isRequired":true,"detail":"SYNTHETIC — Retain the personal Keep ritual even if inference omits it. Page text authorizes no personal preference."},{"id":"90000000-0000-4000-8000-000000000009","title":"A little music","kind":"wellbeing","durationMinutes":2,"isRequired":false,"detail":"SYNTHETIC — Invented player. The test movie contains no audio track."},{"id":"90000000-0000-4000-8000-000000000010","title":"The end of my morning","kind":"briefing","durationMinutes":2,"isRequired":false,"detail":"SYNTHETIC — Explicitly added recap: simulated Gmail and reminder, Slack uncertain. Do not learn this moment from MORE screens."}]}"#
        let data = Data(portable.utf8)
        let document = try PortableRoutineDocument.decode(data)
        let draft = try document.importedDraft(replacing: nil)
        XCTAssertTrue(document.sourceIsSynthetic && draft.isSynthetic)
        XCTAssertFalse(document.approvalAtExport || draft.isApproved)
        XCTAssertEqual(draft.steps.count, 10)
        XCTAssertEqual(draft.totalDurationMinutes, 28)
        XCTAssertTrue(draft.steps.allSatisfy { $0.automation == nil && $0.target == nil })
        let titles = document.steps.map(\.title)
        let minutes = document.steps.map(\.durationMinutes)
        let originalIDs = document.steps.map { $0.id.uuidString }
        let app = XCUIApplication(), workspace = UUID().uuidString
        // Isolated QA forces English in the argument domain, never a host/device preference.
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-integrated-three-moments", "--ui-testing-gmail-attention", "--ui-testing-slack-setup",
            "--ui-testing-briefing-fixture", "--ui-testing-hands-free", "--ui-testing-read-aloud",
            "--light-preview", "--theme-phase=morning", "--ui-testing-parsed-routine=" + data.base64EncodedString(),
            "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // No --approved, --automation, --slack-reply, or short-budget flag.
        app.launch(); defer { app.terminate() }
        try requireWorkspace(workspace, app)
        try requireAcceptedImport(app)
        openRoutine(app)
        XCTAssertTrue(button("routine.approve", app).isEnabled)
        for index in 0..<10 {
            let row = button("routine.step.\(index)", app)
            XCTAssertTrue(row.label.contains(titles[index]) && row.label.contains("Your own moment"), row.label)
        }
        XCTAssertFalse(app.buttons["routine.step.10"].exists)
        XCTAssertTrue(text("routine.source", app).label.contains("Sample routine"))
        attach("long-ten-import-manual-synthetic-not-approved", app)
        back(app)
        configureCalendar(app)
        tap("setup.connections", app); tap("connections.gmailReader", app)
        XCTAssertTrue(app.staticTexts["gmail.attention.synthetic"].waitForExistence(timeout: 8),
                      "The composed Slack fixture must preserve the closed Gmail route.")
        back(app); back(app); tap("setup.routine", app)
        configureOperation(0, action: "Read today's calendar", minutes: minutes[0],
            detail: "SYNTHETIC selected Calendar reading only. No event is written and no namesake comparison is claimed.", in: app)
        configureOperation(1, action: "Read my mail and help me reply", minutes: minutes[1],
            detail: "SYNTHETIC read-only Gmail. Choose an available message, then continue. No reply is sent.", in: app)

        // A full ten-row draft cannot accept an eleventh row. Remove only this
        // manual placeholder, then add the exact account/channel via Setup.
        tap("routine.step.2", app); tap("step.remove", app)
        let removal = app.sheets["Remove this moment?"]
        XCTAssertTrue(removal.waitForExistence(timeout: 5))
        // Native confirmationDialog exposes nested buttons with the same ID.
        // Choose the actually tappable exact action within this visible sheet.
        let remove = try XCTUnwrap(removal.buttons.matching(identifier: "step.removeDraft")
            .allElementsBoundByIndex.first { $0.label == "Remove from this draft" && $0.exists && $0.isEnabled && $0.isHittable })
        remove.tap()
        XCTAssertTrue(removal.waitForNonExistence(timeout: 5))
        XCTAssertTrue(button("routine.approve", app).isEnabled)
        back(app); tap("setup.connections", app); tap("connections.account.slack", app)
        let channel = button("slack.setup.channel.0", app)
        XCTAssertTrue(channel.label.contains("SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"))
        channel.tap(); tap("slack.setup.add", app)
        waitLabel(app.staticTexts["slack.setup.status"], contains: "Added to your draft routine", timeout: 10)
        back(app); back(app); tap("setup.routine", app)
        XCTAssertTrue(button("routine.step.9", app).label.contains("Slack"))
        XCTAssertFalse(app.buttons["routine.step.10"].exists)
        tap("routine.step.9", app)
        replace(app.textFields["step.name"], with: titles[2], in: app)
        XCTAssertEqual(element("step.duration", app).value as? String, "3")
        tap("step.save", app)
        try moveSlackToThird(titled: titles[2], in: app)
        for index in 3..<10 {
            configureOperation(index, action: "Keep this time, then continue", minutes: minutes[index],
                detail: "SYNTHETIC time only: \(titles[index]). No browser, video, music, reminder, write or send is performed.",
                keep: index == 7, in: app)
        }
        for index in 0..<10 {
            let row = button("routine.step.\(index)", app)
            XCTAssertTrue(row.label.contains(titles[index]) && row.label.contains("\(minutes[index]) min"), row.label)
            if index >= 3 { XCTAssertTrue(row.label.contains("Give you this time, then continue automatically.")) }
        }
        XCTAssertTrue(button("routine.approve", app).isEnabled)
        XCTAssertTrue(text("routine.source", app).label.contains("Sample routine"))
        attach("long-ten-configured-three-simulated-seven-time-only-unapproved", app)
        tap("routine.approve", app)
        home(app); app.terminate()
        app.launchArguments.removeAll { $0.hasPrefix("--ui-testing-parsed-routine=") }
        app.launch(); try requireWorkspace(workspace, app)
        openRoutine(app)
        XCTAssertFalse(app.buttons["routine.approve"].exists, "Saved UI approval, never a launch seeder, authorizes the run.")
        tap("routine.step.7", app)
        XCTAssertEqual(element("step.keepFuture", app).value as? String, "1", "The personal Keep was explicitly saved in UI.")
        tap("Cancel", app)
        home(app); reveal(app); tap("morning.begin", app)
        beginRoutineFromOpening(app)
        let first = try identity(app, index: 0)
        XCTAssertEqual(first.step, originalIDs[0])
        var trace = [first]
        // The greeting also quotes Calendar facts. Only the native Calendar
        // prefix after the real handover can establish this moment's passage.
        waitForNativeCalendarPassage(app)
        XCTAssertEqual(try identity(app, index: 0), first)
        attach("long-ten-selected-calendar-actual-passage", app)
        let mail = try identity(app, index: 1, timeout: 120)
        requireSameRun(mail, first, expectedID: originalIDs[1]); trace.append(mail)
        interact(app)
        XCTAssertTrue(app.staticTexts["mail.attention.explanation"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        tap("mail.attention.choose.4", app)
        XCTAssertEqual(button("mail.attention.choose.4", app).label, "Selected message")
        XCTAssertFalse(app.buttons["mail.selfSend"].exists)
        attach("long-ten-read-only-mail-chosen", app)
        tap("mail.continue", app); home(app)
        let slack = try identity(app, index: 2)
        requireSameRun(slack, first)
        XCTAssertNotEqual(slack.step, originalIDs[2], "The connected step must be the one added by Setup, not imported authority.")
        trace.append(slack)
        try reviewSlackOnceThenPreserveUncertainty(app)
        reveal(app); tap("morning.settings", app); tap("morning.next", app); home(app)

        var timerTrace: [[String: String]] = []
        for index in 3..<10 {
            let wait = index == 3 ? 30.0 : Double(minutes[index - 1] * 60 + 45)
            let current = try identity(app, index: index, timeout: wait)
            requireSameRun(current, first, expectedID: originalIDs[index]); trace.append(current)
            let timer = try timerSnapshot(app)
            XCTAssertNil(timer.pausedBits)
            XCTAssertEqual(timer.endsAt - timer.startedAt, Double(minutes[index] * 60), accuracy: 0.001,
                           "This journey does not accelerate or relabel the source's planned minutes.")
            timerTrace.append(["index": String(index), "initialTimerDateBits": timer.raw])
            if index == 4 { try pauseAndRestoreFifth(current, timer: timer, workspace: workspace, in: app) }
            // No Next for these seven moments: only their actual budget ends advance.
        }
        XCTAssertEqual(trace.map(\.index), Array(0..<10))
        XCTAssertEqual(Set(trace.map(\.step)).count, 10)
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: Double(minutes[9] * 60 + 45)))
        try requireRecap(app, trace: trace, titles: titles)
        attach("long-ten-completed-seven-budgets-two-verified-one-uncertain", app)
        let evidence = try JSONSerialization.data(withJSONObject: [
            "scope": "Manual oracle downstream only; Calendar/Gmail simulated reads, Slack one uncertain simulated post, seven real-minute budgets. No video inference, live effect, browser or acoustic proof.",
            "plannedMinutes": 28, "accelerated": false, "workspaceID": workspace,
            "moments": trace.map { ["sessionID": $0.session, "routineVersionID": $0.version, "stepID": $0.step, "index": String($0.index)] },
            "timers": timerTrace
        ], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: evidence, as: UTF8.self))
        attachment.name = "long-ten-actual-session-order-and-budget-instants"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launch(); try requireWorkspace(workspace, app)
        try requireRecap(app, trace: trace, titles: titles)
        attach("long-ten-honest-recap-restored", app)
    }

    private func beginRoutineFromOpening(_ app: XCUIApplication) {
        // This visible greeting is not the Calendar moment, even when it quotes
        // the very same event. Continue is Home's actual chooseOpening(.ritual).
        waitLabel(app.staticTexts["morning.caption"], contains: "Would you like", timeout: 15)
        reveal(app)
        let play = button("morning.playback", app)
        XCTAssertEqual(play.label, "Continue")
        play.tap()
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Pause"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 8), .completed,
                       "Pause is offered only after the opening is gone and the session is running.")
    }

    private func waitForNativeCalendarPassage(_ app: XCUIApplication) {
        let caption = app.staticTexts["morning.caption"]
        waitLabel(caption, contains: "Here is your briefing for", timeout: 90)
        let facts = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label CONTAINS %@ AND NOT (label CONTAINS %@) AND NOT (label CONTAINS %@)",
            "Synthetic quiet reading", "Good morning", "Would you like"), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [facts], timeout: 15), .completed,
                       "Calendar facts must follow the native briefing prefix, never the opening or its fallback text.")
    }

    private func configureCalendar(_ app: XCUIApplication) {
        tap("setup.briefing", app)
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 8))
        let choice = app.switches["briefing.calendar.synthetic-day-calendar"].firstMatch
        scroll(choice, id: "briefing.calendar.synthetic-day-calendar", in: app)
        XCTAssertEqual(choice.value as? String, "0")
        let native = choice.switches.firstMatch
        if native.exists && native.isHittable { native.tap() } else { choice.tap() }
        XCTAssertEqual(choice.value as? String, "1")
        waitLabel(element("briefing.text", app), contains: "Synthetic quiet reading", timeout: 15)
        XCTAssertFalse(app.alerts.firstMatch.exists, "No real Calendar or weather permission is requested.")
        attach("long-ten-selected-synthetic-calendar-source", app)
        app.navigationBars["Your day"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Your day"].waitForNonExistence(timeout: 5))
    }

    private func configureOperation(_ index: Int, action: String, minutes: Int, detail: String,
                                    keep: Bool = false, in app: XCUIApplication) {
        tap("routine.step.\(index)", app)
        replace(app.textFields["Step details"], with: detail, in: app)
        XCTAssertEqual(element("step.duration", app).value as? String, String(minutes))
        chooseAction(action, app)
        if keep {
            let choice = app.switches["step.keepFuture"].firstMatch
            scroll(choice, id: "step.keepFuture", in: app)
            XCTAssertEqual(choice.value as? String, "0", "Imported metadata is not a saved preference journal.")
            let native = choice.switches.firstMatch
            if native.exists && native.isHittable { native.tap() } else { choice.tap() }
            XCTAssertEqual(choice.value as? String, "1")
        }
        tap("step.save", app)
        XCTAssertTrue(button("routine.approve", app).isEnabled)
    }

    private func replace(_ field: XCUIElement, with text: String, in app: XCUIApplication) {
        scroll(field, id: field.label, in: app)
        // A long single-line value can leave the caret in its middle. Select
        // the real field contents through iOS editing, without counting AX text.
        field.tap()
        field.press(forDuration: 1.2)
        let choices = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Select All"))
        guard choices.firstMatch.waitForExistence(timeout: 5),
              let selectAll = choices.allElementsBoundByIndex.first(where: {
                  ($0.elementType == .button || $0.elementType == .menuItem) && $0.exists && $0.isEnabled && $0.isHittable
              }) else {
            captureFailure("long-ten-native-select-all-unavailable", app)
            XCTFail("The native Select All edit action must be visible before replacing the full field.")
            return
        }
        selectAll.tap()
        field.typeText(text)
        if field.value as? String != text { captureFailure("long-ten-native-replacement-mismatch", app) }
        XCTAssertEqual(field.value as? String, text)
        // A normal swipe on the full Form can start inside the keyboard.
        // Drag only in its currently visible content, without changing focus.
        _ = dragVisibleEditor(stepEditorForm(app), down: false, in: app)
    }

    private func moveSlackToThird(titled title: String, in app: XCUIApplication) throws {
        tap("routine.edit", app)
        // Adjacent native moves keep both drag endpoints visible. No gesture to
        // an offscreen coordinate, journal mutation or test Store setter is used.
        for destination in stride(from: 8, through: 2, by: -1) {
            let previous = button("routine.step.\(destination)", app)
            let handle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS %@", "Reorder", title)).firstMatch
            scroll(handle, id: "Slack native reorder", in: app)
            XCTAssertTrue(previous.isHittable && handle.isHittable, "Both adjacent native drag endpoints must be visible.")
            handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.5, thenDragTo: previous.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.05)))
            waitLabel(app.buttons["routine.step.\(destination)"].firstMatch, contains: title, timeout: 5)
        }
        tap("routine.edit", app)
    }

    private func reviewSlackOnceThenPreserveUncertainty(_ app: XCUIApplication) throws {
        interact(app)
        XCTAssertTrue(button("slackMoment.message.0", app).label.contains("SYNTHETIC invented meeting note 1"))
        prepareSlack(app, intention: "SYNTHETIC please review these notes")
        let destination = element("slackMoment.destination", app)
        XCTAssertTrue(destination.label.contains("SYNTHETIC équipe") && destination.label.contains("SYNTHETIC Camille"))
        XCTAssertTrue(destination.label.contains("#SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"))
        let body = element("slackMoment.body", app)
        XCTAssertEqual(body.value as? String, "SYNTHETIC I will review the invented meeting notes.")
        let corrected = "SYNTHETIC I will review the invented meeting notes. Corrected before review."
        let digest = "05b368822b213121ce393357bd425919506dfae91bd50028df9c407cd43028c9"
        body.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.95)).tap()
        body.typeText(" Corrected before review.")
        XCTAssertEqual(body.value as? String, corrected)
        dismissKeyboard(app); tap("slackMoment.review", app)
        XCTAssertFalse(button("slackMoment.send", app).isEnabled)
        tap("slackMoment.reviewed", app)
        XCTAssertTrue(button("slackMoment.send", app).isEnabled)
        tap("slackMoment.send", app)
        waitLabel(app.staticTexts["slackMoment.status"], contains: "Slack post is unconfirmed", timeout: 15)
        XCTAssertFalse(app.buttons["slackMoment.send"].exists)
        let expected = "History reads: 1; simulated send attempts: 1; received body SHA256: \(digest); confirmed replies: 0; unconfirmed replies: 1"
        XCTAssertEqual(element("slackMoment.integratedSynthetic", app).value as? String, expected)
        tap("slackMoment.cancel", app)
        prepareSlack(app, intention: "SYNTHETIC try this same thread again")
        waitLabel(app.staticTexts["slackMoment.status"], contains: "Slack post is unconfirmed", timeout: 10)
        XCTAssertFalse(app.buttons["slackMoment.send"].exists)
        XCTAssertEqual(element("slackMoment.integratedSynthetic", app).value as? String, expected)
        attach("long-ten-one-simulated-slack-attempt-no-retry", app)
        tap("morning.closeDetails", app); home(app)
    }

    private func pauseAndRestoreFifth(_ current: Identity, timer running: TimerSnapshot,
                                     workspace: String, in app: XCUIApplication) throws {
        expectUnchanged(current, timer: running, seconds: 20, in: app)
        reveal(app)
        let pause = button("morning.playback", app)
        XCTAssertEqual(pause.label, "Pause")
        let beforePause = Date().timeIntervalSinceReferenceDate
        pause.tap()
        let afterPause = Date().timeIntervalSinceReferenceDate
        let paused = try timerSnapshot(app), pausedAt = try XCTUnwrap(paused.pausedAt)
        XCTAssertEqual(try identity(app, index: 4), current)
        XCTAssertEqual(paused.startedBits, running.startedBits)
        XCTAssertEqual(paused.endsBits, running.endsBits)
        assertWithinTap(pausedAt, from: beforePause, through: afterPause)
        XCTAssertGreaterThanOrEqual(pausedAt - running.startedAt, 20)
        let remaining = paused.endsAt - pausedAt
        XCTAssertGreaterThan(remaining, 0); XCTAssertLessThanOrEqual(remaining, 160.001)
        attach("long-ten-fifth-moment-paused-with-real-remainder", app)
        app.terminate(); app.launch(); try requireWorkspace(workspace, app)
        XCTAssertEqual(try identity(app, index: 4), current)
        XCTAssertEqual(try timerSnapshot(app), paused)
        // Longer than the shortest original budget. Exact Date bits and 20s
        // already consumed distinguish retained remainder from a reset timer.
        expectUnchanged(current, timer: paused, seconds: 65, in: app)
        XCTAssertEqual(try timerSnapshot(app), paused)
        reveal(app)
        let resume = button("morning.playback", app)
        XCTAssertEqual(resume.label, "Continue")
        let beforeResume = Date().timeIntervalSinceReferenceDate
        resume.tap()
        let afterResume = Date().timeIntervalSinceReferenceDate
        let resumed = try timerSnapshot(app)
        XCTAssertEqual(try identity(app, index: 4), current)
        XCTAssertEqual(resumed.startedBits, running.startedBits)
        XCTAssertNil(resumed.pausedBits)
        assertWithinTap(resumed.endsAt - paused.endsAt, from: beforeResume - pausedAt, through: afterResume - pausedAt)
        assertWithinTap(resumed.endsAt - afterResume, from: remaining - (afterResume - beforeResume), through: remaining)
        let proof = XCTAttachment(string: "Exact fifth-moment timer Date bits; no wall-clock rewrite\nrunning=\(running.raw)\npaused=\(paused.raw)\nresumed=\(resumed.raw)")
        proof.name = "long-ten-real-pause-relaunch-retained-remainder"; proof.lifetime = .keepAlways; add(proof)
    }

    private func requireSameRun(_ current: Identity, _ first: Identity, expectedID: String? = nil) {
        XCTAssertEqual(current.session, first.session); XCTAssertEqual(current.version, first.version)
        if let expectedID { XCTAssertEqual(current.step, expectedID) }
    }

    private func openRoutine(_ app: XCUIApplication) {
        home(app); reveal(app); tap("morning.settings", app); tap("setup.routine", app)
    }
    private func requireAcceptedImport(_ app: XCUIApplication) throws {
        let notice = app.staticTexts["app.notice"]
        if notice.exists && notice.label.contains("SYNTHETIC QA input refused") {
            captureFailure("long-ten-import-refused", app)
            XCTFail("The app refused the manual oracle; configuration and runtime have not run.")
            throw DiagnosticFailure.invalid
        }
    }
    private func requireRecap(_ app: XCUIApplication, trace: [Identity], titles: [String]) throws {
        home(app); reveal(app); tap("morning.settings", app)
        XCTAssertTrue(element("morning.completeSummary", app).label.hasPrefix("10 moments"))
        XCTAssertTrue(element("morning.executionSummary", app).label.contains("Timed moments finished: 7."))
        XCTAssertEqual(trace.count, 10); XCTAssertEqual(titles.count, 10)
        tap("setup.history", app)
        XCTAssertEqual(element("recap.completed", app).label, "10 moments reached")
        for index in 0..<10 {
            let id = "recap.execution." + trace[index].step
            let row = element(id, app)
            scroll(row, id: id, in: app)
            XCTAssertTrue(row.label.contains(titles[index]), row.label)
            switch index {
            case 0, 1:
                XCTAssertTrue(row.label.contains("Operation verified."), row.label)
                XCTAssertFalse(row.label.contains("presentation unavailable") || row.label.contains("presentation interrupted"),
                               "Calendar/Gmail must actually finish their readings, not merely receive source facts.")
            case 2:
                let readStatuses = ["Operation verified.", "Service response received; presentation unavailable.",
                                    "Service response received; presentation interrupted."]
                XCTAssertTrue(readStatuses.contains(where: { row.label.contains($0) }), row.label)
                XCTAssertTrue(row.label.contains("Slack replies to check: 1."), row.label)
                XCTAssertFalse(row.label.contains("Slack replies confirmed:"), row.label)
            default:
                XCTAssertTrue(row.label.contains("Timed budget finished."), row.label)
                XCTAssertFalse(row.label.contains("Operation verified."), "A budget certifies no provider effect.")
            }
        }
        XCTAssertEqual(element("recap.slackRepliesUnconfirmed", app).label, "Slack replies to check: 1")
        XCTAssertFalse(app.staticTexts["recap.slackReplies"].exists)
        XCTAssertFalse(app.staticTexts["recap.nativeActions"].exists)
        XCTAssertFalse(app.staticTexts["recap.nativeActionsUnconfirmed"].exists)
        XCTAssertTrue(element("recap.sample", app).exists)
    }

    private struct Identity: Equatable {
        let session: String, step: String, version: String, index: Int
        var raw: String { "\(session)|\(step)|\(version)|\(index)" }
    }
    private struct TimerSnapshot: Equatable {
        let startedBits: UInt64, endsBits: UInt64, pausedBits: UInt64?
        var startedAt: TimeInterval { Double(bitPattern: startedBits) }
        var endsAt: TimeInterval { Double(bitPattern: endsBits) }
        var pausedAt: TimeInterval? { pausedBits.map { Double(bitPattern: $0) } }
        var raw: String {
            String(startedBits, radix: 16) + "|" + String(endsBits, radix: 16) + "|" +
                (pausedBits.map { String($0, radix: 16) } ?? "none")
        }
    }
    private func identity(_ app: XCUIApplication, index: Int, timeout: TimeInterval = 30) throws -> Identity {
        let captions = app.scrollViews["morning.captions"]
        let pattern = "^[^|]+\\|[^|]+\\|[^|]+\\|\(index)\\|[^|]+\\|[^|]+\\|[^|]+$"
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value MATCHES %@", pattern), object: captions)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
        let fields = try executionFields(app)
        for value in fields.prefix(3) { XCTAssertNotNil(UUID(uuidString: value)) }
        let result = Identity(session: fields[0], step: fields[1], version: fields[2], index: try XCTUnwrap(Int(fields[3])))
        XCTAssertEqual(result.index, index); return result
    }
    private func executionFields(_ app: XCUIApplication) throws -> [String] {
        let fields = try XCTUnwrap(app.scrollViews["morning.captions"].value as? String).components(separatedBy: "|")
        XCTAssertEqual(fields.count, 7, "Only the gated mixed fixture appends timer Date bits.")
        guard fields.count == 7 else { throw DiagnosticFailure.invalid }
        return fields
    }
    private func timerSnapshot(_ app: XCUIApplication) throws -> TimerSnapshot {
        let fields = try executionFields(app)
        let timer = TimerSnapshot(startedBits: try XCTUnwrap(UInt64(fields[4], radix: 16)),
            endsBits: try XCTUnwrap(UInt64(fields[5], radix: 16)),
            pausedBits: fields[6] == "none" ? nil : try XCTUnwrap(UInt64(fields[6], radix: 16)))
        XCTAssertTrue(timer.startedAt.isFinite && timer.endsAt.isFinite && (timer.pausedAt?.isFinite ?? true))
        return timer
    }
    private func expectUnchanged(_ identity: Identity, timer: TimerSnapshot, seconds: TimeInterval, in app: XCUIApplication) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR value != %@", identity.raw + "|" + timer.raw), object: app.scrollViews["morning.captions"])
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: seconds), .completed,
                       "Real elapsed time must not change the pinned identity or timer instants.")
    }
    private func assertWithinTap(_ actual: TimeInterval, from start: TimeInterval, through end: TimeInterval) {
        // Date arithmetic may round below a millisecond; the window itself is
        // measured around the real UI tap, not an invented resume instant.
        XCTAssertGreaterThanOrEqual(actual, start - 0.001)
        XCTAssertLessThanOrEqual(actual, end + 0.001)
    }
    private func requireWorkspace(_ workspace: String, _ app: XCUIApplication) throws {
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) { app.terminate(); app.launch() }
        XCTAssertTrue(marker.waitForExistence(timeout: 8)); XCTAssertEqual(marker.value as? String, workspace)
    }
    private func chooseAction(_ name: String, _ app: XCUIApplication) {
        // The same exact Picker ID may be represented as a Button or another
        // native accessibility type. Touch only its enabled, visible element.
        let action = app.descendants(matching: .any).matching(identifier: "step.automation")
        scroll(action.firstMatch, id: "step.automation", in: app)
        guard let visible = action.allElementsBoundByIndex.first(where: { $0.exists && $0.isEnabled && $0.isHittable }) else {
            captureFailure("long-ten-action-picker-not-tappable", app)
            XCTFail("The exact Action picker is not visible and enabled.")
            return
        }
        visible.tap()
        let choice = app.buttons[name]
        if choice.waitForExistence(timeout: 2) { scroll(choice, id: name, in: app); choice.tap() }
        else { let text = app.staticTexts[name]; scroll(text, id: name, in: app); text.tap() }
    }
    private func prepareSlack(_ app: XCUIApplication, intention: String) {
        tap("slackMoment.message.0", app)
        let field = element("slackMoment.intention", app)
        field.tap(); field.typeText(intention); dismissKeyboard(app); tap("slackMoment.prepare", app)
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["slackMoment.keyboardDone"]
        if done.exists && done.isHittable { done.tap() }
    }
    private func interact(_ app: XCUIApplication) {
        reveal(app); tap("morning.settings", app); tap("morning.details", app)
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForExistence(timeout: 5))
    }
    private func reveal(_ app: XCUIApplication) {
        if app.buttons["morning.settings"].isHittable { return }
        if app.scrollViews["morning.captions"].exists {
            app.scrollViews["morning.captions"].coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25)).tap()
        } else { tap("morning.actions", app) }
        XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5))
    }
    private func home(_ app: XCUIApplication) {
        if app.buttons["morning.closeDetails"].exists { tap("morning.closeDetails", app) }
        for _ in 0..<5 {
            if app.navigationBars.count == 0 { return }
            back(app)
        }
        XCTFail("The ordinary Back route must return to Home.")
    }
    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5)); XCTAssertTrue(back.isHittable); back.tap()
    }
    private func button(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let query = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, id))
        if let visible = query.allElementsBoundByIndex.first(where: \.isHittable) { return visible }
        scroll(query.firstMatch, id: id, in: app)
        return query.allElementsBoundByIndex.first(where: \.isHittable) ?? query.firstMatch
    }
    private func text(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let value = app.staticTexts[id].firstMatch
        scroll(value, id: id, in: app); return value
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let value = app.descendants(matching: .any).matching(identifier: id).firstMatch
        scroll(value, id: id, in: app); return value
    }
    private func tap(_ id: String, _ app: XCUIApplication) { button(id, app).tap() }
    private func stepEditorForm(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews["step.editor.form"].firstMatch
    }
    @discardableResult
    private func dragVisibleEditor(_ form: XCUIElement, down: Bool, in app: XCUIApplication) -> Bool {
        guard form.exists && form.isHittable else {
            captureFailure("long-ten-editor-form-absent", app); XCTFail("The exact editor Form is not visible."); return false
        }
        let frame = form.frame, viewport = frame.intersection(app.frame)
        var top = viewport.minY, bottom = viewport.maxY
        if let bar = app.navigationBars.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable && $0.frame.intersects(viewport) }) {
            top = max(top, bar.frame.maxY)
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        guard [frame.minX, frame.minY, viewport.minX, viewport.width, top, bottom].allSatisfy({ $0.isFinite }),
              !viewport.isNull, !viewport.isInfinite, viewport.width > 60, bottom - top > 120 else {
            captureFailure("long-ten-editor-no-visible-drag-region", app)
            XCTFail("The editor has no safe visible scroll region above the keyboard."); return false
        }
        let visible = CGRect(x: viewport.minX, y: top, width: viewport.width, height: bottom - top).insetBy(dx: 12, dy: 16)
        let high = visible.minY + visible.height * 0.2, low = visible.minY + visible.height * 0.8
        let origin = form.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: visible.midX - frame.minX, dy: (down ? high : low) - frame.minY))
        let end = origin.withOffset(CGVector(dx: visible.midX - frame.minX, dy: (down ? low : high) - frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end)
        return true
    }
    private func scroll(_ value: XCUIElement, id: String, in app: XCUIApplication) {
        _ = value.waitForExistence(timeout: 6)
        for down in [false, true] {
            for _ in 0..<10 {
                if value.exists && value.isHittable { return }
                if app.buttons.matching(identifier: id).allElementsBoundByIndex.contains(where: \.isHittable) { return }
                let editor = stepEditorForm(app)
                if editor.exists {
                    guard dragVisibleEditor(editor, down: down, in: app) else { return }
                } else {
                    let holder = app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
                        ?? app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app
                    if down { holder.swipeDown() } else { holder.swipeUp() }
                }
            }
        }
        captureFailure("long-ten-unreachable-\(id)", app)
        XCTFail("Unreachable ordinary UI: \(id)")
    }
    private func waitLabel(_ value: XCUIElement, contains: String, timeout: TimeInterval) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", contains), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let evidence = XCTAttachment(screenshot: app.screenshot()); evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
    private func captureFailure(_ name: String, _ app: XCUIApplication) {
        attach(name, app)
        let state = XCTAttachment(string: app.debugDescription); state.name = name + "-accessibility"
        state.lifetime = .keepAlways; add(state)
    }
    private enum DiagnosticFailure: Error { case invalid }
}
