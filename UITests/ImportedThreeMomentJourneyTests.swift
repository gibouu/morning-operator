import XCTest

/// Private downstream seam only: imported manual plan, ordinary configuration,
/// approval, then one session. No movie learning, microphone, browser, real account,
/// network or real send runs. Ordinary local connected-result narration may run
/// or be unavailable; this test does not validate it. Gmail is read-only. Slack's transport loses its
/// one simulated post response. Planned QA budgets are 3 + 3 + 1 real minutes;
/// explicit Continue/Next end the first two moments, not a fabricated deadline.
@MainActor final class ImportedThreeMomentJourneyTests: XCTestCase {
    func testImportedManualDraftBecomesOneReviewedGmailSlackAndTimedMorning() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), workspace = UUID().uuidString
        let gmailID = "62000000-0000-4000-8000-000000000001"
        let placeholderID = "62000000-0000-4000-8000-000000000002"
        let timedID = "62000000-0000-4000-8000-000000000003"
        let portable: [String: Any] = [
            "format": "morning-operator.routine", "formatVersion": 1, "detail": "includeDetails",
            "sourceRoutineID": "62000000-0000-4000-8000-000000000100", "sourceRoutineVersion": 1,
            "sourceCreatedAt": 1_792_129_500.0, "approvalAtExport": false, "sourceIsSynthetic": true,
            "sourceLabel": "SYNTHETIC three-moment manual import; no video/model result or operation authority",
            "steps": [
                ["id": gmailID, "title": "SYNTHETIC mail review", "kind": "messages", "durationMinutes": 2, "isRequired": false],
                ["id": placeholderID, "title": "SYNTHETIC team placeholder", "kind": "messages", "durationMinutes": 1, "isRequired": false],
                ["id": timedID, "title": "SYNTHETIC quiet finish", "kind": "wellbeing", "durationMinutes": 1, "isRequired": false]
            ]]
        let data = try JSONSerialization.data(withJSONObject: portable, options: [.sortedKeys])
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-integrated-three-moments", "--ui-testing-gmail-attention", "--ui-testing-slack-setup",
            "--ui-testing-hands-free", "--light-preview", "--theme-phase=morning",
            "--ui-testing-parsed-routine=" + data.base64EncodedString(),
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        try requireWorkspace(workspace, app)
        reveal(app); tap("morning.settings", app); tap("setup.routine", app)
        XCTAssertTrue(button("routine.approve", app).isEnabled, "Import is never approval.")
        for index in 0..<3 {
            XCTAssertTrue(button("routine.step.\(index)", app).label.contains("Your own moment"),
                          "No imported title/category may install an executable action.")
        }
        let provenance = app.staticTexts["routine.source"]
        scroll(provenance, app)
        XCTAssertTrue(provenance.label.contains("Sample routine"))

        tap("routine.step.0", app)
        chooseAction("Read my mail and help me reply", app)
        let duration = app.steppers["step.duration"]
        scroll(duration, app)
        XCTAssertEqual(duration.value as? String, "2")
        duration.buttons["step.duration-Increment"].tap()
        XCTAssertEqual(duration.value as? String, "3")
        tap("step.save", app)
        tap("routine.step.1", app); tap("step.remove", app); tap("step.removeDraft", app)
        tap("routine.step.1", app)
        chooseAction("Keep this time, then continue", app); tap("step.save", app)
        back(app)
        tap("setup.connections", app); tap("connections.gmailReader", app)
        XCTAssertTrue(app.staticTexts["gmail.attention.synthetic"].waitForExistence(timeout: 8),
                      "Slack transport composition must keep the isolated Gmail route.")
        back(app); tap("connections.account.slack", app)
        let channel = button("slack.setup.channel.0", app)
        XCTAssertTrue(channel.label.contains("SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"))
        channel.tap(); tap("slack.setup.add", app)
        waitLabel(app.staticTexts["slack.setup.status"], contains: "Added to your draft routine", timeout: 10)
        back(app); back(app); tap("setup.routine", app)
        XCTAssertTrue(button("routine.step.2", app).label.contains("Slack"))
        XCTAssertFalse(app.buttons["routine.step.3"].exists)
        XCTAssertTrue(button("routine.approve", app).isEnabled, "Choosing a service still leaves a draft.")
        tap("routine.edit", app)
        let handle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS %@", "Reorder", "Slack")).firstMatch
        scroll(handle, app)
        let second = button("routine.step.1", app)
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: second.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.05)))
        tap("routine.edit", app)
        XCTAssertTrue(button("routine.step.1", app).label.contains("Slack"))
        XCTAssertTrue(button("routine.step.2", app).label.contains("SYNTHETIC quiet finish"))
        attach("three-moments-configured-through-editor-and-account-choice-unapproved", app)
        tap("routine.approve", app)
        home(app)
        app.terminate()
        app.launchArguments.removeAll { $0.hasPrefix("--ui-testing-parsed-routine=") }
        app.launch(); try requireWorkspace(workspace, app)
        reveal(app); tap("morning.settings", app); tap("setup.routine", app)
        XCTAssertFalse(app.buttons["routine.approve"].exists, "The saved UI approval supplies authority, not a launch flag.")
        XCTAssertTrue(button("routine.step.0", app).label.contains("3 min"))
        home(app); reveal(app); tap("morning.begin", app)
        let first = try identity(app, index: 0)
        XCTAssertEqual(first.step, gmailID)
        interact(app)
        XCTAssertTrue(app.staticTexts["mail.attention.explanation"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        tap("mail.attention.choose.4", app)
        XCTAssertEqual(button("mail.attention.choose.4", app).label, "Selected message")
        XCTAssertFalse(app.buttons["mail.selfSend"].exists, "The fixture grants reading only.")
        attach("three-moments-gmail-read-and-chosen-no-send", app)
        tap("mail.continue", app)
        home(app)
        let slack = try identity(app, index: 1)
        XCTAssertEqual(slack.session, first.session); XCTAssertEqual(slack.version, first.version)
        XCTAssertNotEqual(slack.step, placeholderID, "The exact connected moment was added through the ordinary setup.")
        interact(app)
        XCTAssertTrue(button("slackMoment.message.0", app).label.contains("SYNTHETIC invented meeting note 1"))
        XCTAssertEqual(element("slackMoment.integratedSynthetic", app).value as? String,
            "History reads: 1; simulated send attempts: 0; received body SHA256: none; confirmed replies: 0; unconfirmed replies: 0")
        prepareSlack(app, intention: "SYNTHETIC please review these notes")
        let destination = app.staticTexts["slackMoment.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10))
        XCTAssertTrue(destination.label.contains("SYNTHETIC équipe") && destination.label.contains("SYNTHETIC Camille"))
        XCTAssertTrue(destination.label.contains("#SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"))
        let body = element("slackMoment.body", app)
        XCTAssertEqual(body.value as? String, "SYNTHETIC I will review the invented meeting notes.")
        let correctedBody = "SYNTHETIC I will review the invented meeting notes. Corrected before review."
        // Independent UTF-8 sample digest, never computed from the editor or
        // returned by the transport under test.
        let correctedBodySHA256 = "05b368822b213121ce393357bd425919506dfae91bd50028df9c407cd43028c9"
        body.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.95)).tap()
        body.typeText(" Corrected before review.")
        XCTAssertEqual(body.value as? String, correctedBody)
        dismissKeyboard(app)
        tap("slackMoment.review", app)
        XCTAssertFalse(button("slackMoment.send", app).isEnabled, "The interrupted synthetic speech is not a completed review.")
        tap("slackMoment.reviewed", app)
        XCTAssertTrue(button("slackMoment.send", app).isEnabled)
        tap("slackMoment.send", app)
        waitLabel(app.staticTexts["slackMoment.status"], contains: "Slack post is unconfirmed", timeout: 15)
        XCTAssertFalse(app.buttons["slackMoment.send"].exists)
        let diagnostic = "History reads: 1; simulated send attempts: 1; received body SHA256: \(correctedBodySHA256); confirmed replies: 0; unconfirmed replies: 1"
        XCTAssertEqual(element("slackMoment.integratedSynthetic", app).value as? String, diagnostic)
        // A new UI prepare after closing the failed request must hit the existing
        // durable claim, not dispatch a second simulated post.
        tap("slackMoment.cancel", app)
        prepareSlack(app, intention: "SYNTHETIC try this same thread again")
        waitLabel(app.staticTexts["slackMoment.status"], contains: "Slack post is unconfirmed", timeout: 10)
        XCTAssertFalse(app.buttons["slackMoment.send"].exists)
        XCTAssertEqual(element("slackMoment.integratedSynthetic", app).value as? String, diagnostic)
        attach("three-moments-slack-one-simulated-attempt-durable-uncertainty", app)
        tap("morning.closeDetails", app); home(app)
        reveal(app); tap("morning.settings", app); tap("morning.next", app)
        home(app)
        let timed = try identity(app, index: 2)
        XCTAssertEqual(timed.step, timedID)
        XCTAssertEqual(timed.session, first.session); XCTAssertEqual(timed.version, first.version)
        XCTAssertEqual(Set([first.step, slack.step, timed.step]).count, 3)
        let runningTimer = try timerSnapshot(app)
        XCTAssertNil(runningTimer.pausedBits)
        XCTAssertEqual(runningTimer.endsAt - runningTimer.startedAt, 60, accuracy: 0.001)
        // Let an actual part of this real minute elapse. A fresh 60-second
        // timer at resume must no longer satisfy the remainder assertions.
        expectUnchanged(timed, timer: runningTimer, seconds: 20, in: app)
        reveal(app)
        let pause = button("morning.playback", app)
        XCTAssertEqual(pause.label, "Pause")
        let pauseTapStart = Date().timeIntervalSinceReferenceDate
        pause.tap()
        let pauseTapEnd = Date().timeIntervalSinceReferenceDate
        XCTAssertEqual(button("morning.playback", app).label, "Continue")
        XCTAssertEqual(try identity(app, index: 2), timed)
        let pausedTimer = try timerSnapshot(app)
        let pausedAt = try XCTUnwrap(pausedTimer.pausedAt)
        XCTAssertEqual(pausedTimer.startedBits, runningTimer.startedBits)
        XCTAssertEqual(pausedTimer.endsBits, runningTimer.endsBits)
        assertWithinTap(pausedAt, from: pauseTapStart, through: pauseTapEnd)
        XCTAssertGreaterThanOrEqual(pausedAt - pausedTimer.startedAt, 20)
        let remaining = pausedTimer.endsAt - pausedAt
        XCTAssertGreaterThan(remaining, 0)
        XCTAssertLessThanOrEqual(remaining, 40.001)
        app.terminate(); app.launch(); try requireWorkspace(workspace, app)
        XCTAssertEqual(try identity(app, index: 2), timed)
        XCTAssertEqual(try timerSnapshot(app), pausedTimer, "Relaunch must preserve all three exact timer instants.")
        expectUnchanged(timed, timer: pausedTimer, seconds: 65, in: app)
        XCTAssertEqual(try identity(app, index: 2), timed)
        XCTAssertEqual(try timerSnapshot(app), pausedTimer, "A pause longer than the full budget cannot consume or reset its remainder.")
        reveal(app)
        let resume = button("morning.playback", app)
        XCTAssertEqual(resume.label, "Continue")
        let resumeTapStart = Date().timeIntervalSinceReferenceDate
        resume.tap()
        let resumeTapEnd = Date().timeIntervalSinceReferenceDate
        let resumedTimer = try timerSnapshot(app)
        XCTAssertEqual(try identity(app, index: 2), timed)
        XCTAssertEqual(resumedTimer.startedBits, runningTimer.startedBits)
        XCTAssertNil(resumedTimer.pausedBits)
        let endShift = resumedTimer.endsAt - pausedTimer.endsAt
        assertWithinTap(endShift, from: resumeTapStart - pausedAt, through: resumeTapEnd - pausedAt)
        assertWithinTap(resumedTimer.endsAt - resumeTapEnd,
            from: remaining - (resumeTapEnd - resumeTapStart), through: remaining)
        let proof = XCTAttachment(string: "started/ends/paused exact Date bits only\nrunning=\(runningTimer.raw)\npaused=\(pausedTimer.raw)\nresumed=\(resumedTimer.raw)\nreceived simulated body SHA256=\(correctedBodySHA256)")
        proof.name = "three-moments-retained-timer-and-received-body-digest"
        proof.lifetime = .keepAlways; add(proof)
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 90))
        try requireRecap(app)
        attach("three-moments-one-session-honest-recap", app)
        app.terminate(); app.launch(); try requireWorkspace(workspace, app)
        try requireRecap(app)
        attach("three-moments-one-session-recap-restored", app)
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
    private func identity(_ app: XCUIApplication, index: Int) throws -> Identity {
        let captions = app.scrollViews["morning.captions"]
        let pattern = "^[^|]+\\|[^|]+\\|[^|]+\\|\(index)\\|[^|]+\\|[^|]+\\|[^|]+$"
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value MATCHES %@", pattern), object: captions)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
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
    private func requireRecap(_ app: XCUIApplication) throws {
        home(app); reveal(app); tap("morning.settings", app)
        XCTAssertTrue(element("morning.completeSummary", app).label.hasPrefix("3 moments"))
        XCTAssertTrue(element("morning.executionSummary", app).label.contains("Timed moments finished: 1."))
        tap("setup.history", app)
        XCTAssertEqual(element("recap.slackRepliesUnconfirmed", app).label, "Slack replies to check: 1")
        XCTAssertFalse(app.staticTexts["recap.slackReplies"].exists)
        XCTAssertTrue(element("recap.sample", app).exists)
        XCTAssertFalse(app.staticTexts["recap.nativeActions"].exists)
    }
    private func chooseAction(_ name: String, _ app: XCUIApplication) {
        tap("step.automation", app)
        let choice = app.buttons[name]
        if choice.waitForExistence(timeout: 2) { scroll(choice, app); choice.tap() }
        else { let text = app.staticTexts[name]; scroll(text, app); text.tap() }
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
        let value = app.buttons[id]; scroll(value, app); return value
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let value = app.descendants(matching: .any).matching(identifier: id).firstMatch
        scroll(value, app); return value
    }
    private func tap(_ id: String, _ app: XCUIApplication) { button(id, app).tap() }
    private func scroll(_ value: XCUIElement, _ app: XCUIApplication) {
        _ = value.waitForExistence(timeout: 6)
        for down in [false, true] {
            for _ in 0..<10 {
                if value.exists && value.isHittable { return }
                let scroll = app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
                    ?? app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app
                if down { scroll.swipeDown() } else { scroll.swipeUp() }
            }
        }
        attach("three-moments-unreachable-\(value.identifier)", app)
        let state = XCTAttachment(string: app.debugDescription); state.lifetime = .keepAlways; add(state)
        XCTFail("Unreachable ordinary UI: \(value.identifier)")
    }
    private func waitLabel(_ value: XCUIElement, contains: String, timeout: TimeInterval) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", contains), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let evidence = XCTAttachment(screenshot: app.screenshot()); evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
    private enum DiagnosticFailure: Error { case invalid }
}
