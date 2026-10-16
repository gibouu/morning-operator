import XCTest
import MorningCore

/// Private downstream journeys, separately labelled from video learning. The
/// manual parsed input supplies no action authority. The legacy case preserves
/// its seven time-only moments; the complete case configures actual private web
/// inputs, media, a reviewed mail reply and an exact reminder through ordinary UI.
/// Neither case certifies live services, a microphone or acoustic quality.
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
        try runManualOracle(complete: false, mediaArgument: nil)
    }

    /// Downstream acceptance from an explicitly synthetic parsed draft. Real
    /// app policy, WebKit and media playback; fictional providers and no mic.
    func testCompleteSyntheticRoutineUsesMailNewsFeedVideoReminderAndMusic() async throws {
        let media = try await SyntheticRoutineBrowserMediaFactory.launchArgument()
        try runManualOracle(complete: true, mediaArgument: media)
    }

    private func runManualOracle(complete: Bool, mediaArgument: String?) throws {
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
        if complete {
            app.launchArguments += ["--ui-testing-private-gmail-reply", "--ui-testing-private-news",
                "--ui-testing-private-routine-browser", "--ui-testing-private-exact-reminder", "--ui-testing-native-actions"]
            app.launchArguments.append(try XCTUnwrap(mediaArgument))
        }
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
            detail: complete ? "SYNTHETIC Gmail: review Maïa's request, prepare six blue cards, correct to eight green cards, review, then request one simulated send."
                : "SYNTHETIC read-only Gmail. Choose an available message, then continue. No reply is sent.", in: app)

        // Assign through the existing editor. The imported moment remains the
        // same row; only explicit source selection and Save give it an action.
        tap("routine.step.2", app)
        XCTAssertEqual(element("step.name", app).value as? String, titles[2])
        XCTAssertEqual(element("step.duration", app).value as? String, String(minutes[2]))
        let detailsField = app.textFields["Step details"]
        scroll(detailsField, id: "Step details", in: app)
        let originalNote = detailsField.value as? String
        tap("step.chooseSlack", app)
        XCTAssertTrue(element("slack.setup.identity", app).exists)
        let channel = button("slack.setup.channel.0", app)
        XCTAssertTrue(channel.label.contains("SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"))
        channel.tap()
        XCTAssertFalse(app.buttons["slack.setup.add"].exists, "This route must never append a new moment.")
        tap("slack.setup.use", app)
        let selectedSource = text("step.selectedSlackSource", app)
        XCTAssertTrue(selectedSource.label.contains("SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"))
        XCTAssertEqual(element("step.name", app).value as? String, titles[2])
        XCTAssertEqual(element("step.duration", app).value as? String, String(minutes[2]))
        // API targets display the unchanged note as text instead of a text field.
        XCTAssertNotNil(originalNote)
        if let originalNote {
            let retainedNote = app.staticTexts[originalNote]
            scroll(retainedNote, id: "retained-personal-note", in: app)
            XCTAssertTrue(retainedNote.exists)
        }
        attach("long-ten-slack-source-selected-before-save", app)
        tap("step.save", app)
        XCTAssertTrue(button("routine.step.2", app).label.contains(titles[2]))
        XCTAssertFalse(app.buttons["routine.step.10"].exists)
        XCTAssertTrue(button("routine.approve", app).isEnabled)
        for index in 3..<10 {
            if complete, [3, 4, 5, 8].contains(index) {
                configureBrowser(index, site: index == 3 ? "Le Monde" : index == 4 ? "Reddit" : "YouTube Shorts",
                    behavior: index == 3 ? "Read headlines aloud" : index == 4 ? "Browse the feed" : "Watch videos", in: app)
            } else {
                configureOperation(index, action: "Keep this time, then continue", minutes: minutes[index],
                    detail: complete ? "SYNTHETIC personal time: \(titles[index]). Any reminder is a separately reviewed request; the final budget is an explicitly added closing moment."
                        : "SYNTHETIC time only: \(titles[index]). No browser, video, music, reminder, write or send is performed.",
                    keep: index == 7, in: app)
            }
        }
        for index in 0..<10 {
            let row = button("routine.step.\(index)", app)
            XCTAssertTrue(row.label.contains(titles[index]) && row.label.contains("\(minutes[index]) min"), row.label)
            if index >= 3, !complete || ![3, 4, 5, 8].contains(index) {
                XCTAssertTrue(row.label.contains("Give you this time, then continue automatically."))
            }
        }
        XCTAssertTrue(button("routine.approve", app).isEnabled)
        XCTAssertTrue(text("routine.source", app).label.contains("Sample routine"))
        attach(complete ? "complete-routine-configured-service-browser-and-media-inputs-unapproved"
            : "long-ten-configured-three-simulated-seven-time-only-unapproved", app)
        tap("routine.approve", app)
        home(app); app.terminate()
        app.launchArguments.removeAll { $0.hasPrefix("--ui-testing-parsed-routine=") }
        app.launch(); try requireWorkspace(workspace, app)
        openRoutine(app)
        XCTAssertFalse(app.buttons["routine.approve"].exists, "Saved UI approval, never a launch seeder, authorizes the run.")
        tap("routine.step.2", app)
        XCTAssertTrue(text("step.selectedSlackSource", app).label.contains("SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"),
                      "The human source remains reviewable after Save and relaunch, separately from the note.")
        XCTAssertEqual(element("step.name", app).value as? String, titles[2])
        XCTAssertEqual(element("step.duration", app).value as? String, String(minutes[2]))
        tap("Cancel", app)
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
        if !complete { XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5") }
        if complete {
            try replyToSyntheticMail(app, identity: mail)
        } else {
            tap("mail.attention.choose.4", app)
            XCTAssertEqual(button("mail.attention.choose.4", app).label, "Selected message")
            XCTAssertFalse(app.buttons["mail.selfSend"].exists)
            attach("long-ten-read-only-mail-chosen", app)
            tap("mail.continue", app)
        }
        home(app)
        let slack = try identity(app, index: 2)
        requireSameRun(slack, first)
        XCTAssertEqual(slack.step, originalIDs[2], "Explicit UI source selection configures the original imported moment without replacing its identity.")
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
            if complete {
                switch index {
                case 3: try selectSecondArticleAndReturn(app, identity: current)
                case 4: try verifyFeedPauseAndRestore(app, identity: current, workspace: workspace)
                case 5: try verifyMediaPlayback(app, identity: current, music: false)
                case 6: try createExactReminder(app, identity: current)
                case 8: try verifyMediaPlayback(app, identity: current, music: true)
                default: break
                }
            } else if index == 4 {
                try pauseAndRestoreFifth(current, timer: timer, workspace: workspace, in: app)
            }
            // No Next here: real budgets and ordinary reviewed work drive progression.
        }
        XCTAssertEqual(trace.map(\.index), Array(0..<10))
        XCTAssertEqual(Set(trace.map(\.step)).count, 10)
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: Double(minutes[9] * 60 + 45)))
        try requireRecap(app, trace: trace, titles: titles, complete: complete)
        attach(complete ? "complete-routine-completed-observed-work-and-honest-recap"
            : "long-ten-completed-seven-budgets-two-verified-one-uncertain", app)
        let evidence = try JSONSerialization.data(withJSONObject: [
            "scope": complete
                ? "Synthetic parsed draft downstream: Calendar, Gmail reviewed reply, Slack uncertain, actual WebKit news/feed/video/music, one exact simulated reminder, retained reading and closing budgets. No movie inference, live service, microphone or acoustic-quality claim."
                : "Manual oracle downstream only; Calendar/Gmail simulated reads, Slack one uncertain simulated post, seven real-minute budgets. No video inference, live effect, browser or acoustic proof.",
            "plannedMinutes": 28, "accelerated": false, "workspaceID": workspace,
            "moments": trace.map { ["sessionID": $0.session, "routineVersionID": $0.version, "stepID": $0.step, "index": String($0.index)] },
            "timers": timerTrace
        ], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: evidence, as: UTF8.self))
        attachment.name = "long-ten-actual-session-order-and-budget-instants"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launch(); try requireWorkspace(workspace, app)
        try requireRecap(app, trace: trace, titles: titles, complete: complete)
        attach("long-ten-honest-recap-restored", app)
    }

    private func replyToSyntheticMail(_ app: XCUIApplication, identity: Identity) throws {
        let initial = "SYNTHETIC — I will bring six blue cards at 09:15."
        let corrected = "SYNTHETIC — I will bring eight green cards at 09:15."
        tap("mail.attention.choose.3", app)
        XCTAssertEqual(button("mail.attention.choose.3", app).label, "Selected message")
        tap("mail.reply.begin", app)
        let intention = element("mail.reply.intention", app)
        intention.tap(); intention.typeText("Reply that I will bring six blue cards at 09:15.")
        tap("mail.reply.prepare", app)
        waitLabel(app.staticTexts["mail.reply.body"], contains: initial, timeout: 20)
        XCTAssertEqual(element("mail.reply.body", app).label, initial)
        XCTAssertTrue(element("mail.reply.recipient", app).label.contains("maia@morning-fixture.invalid"))
        XCTAssertFalse(button("mail.reply.send", app).isEnabled)
        let correction = element("mail.reply.correction", app)
        correction.tap(); correction.typeText("Correct it: eight green cards, not six blue ones.")
        XCTAssertFalse(button("mail.reply.send", app).isEnabled)
        tap("mail.reply.revise", app)
        waitLabel(app.staticTexts["mail.reply.body"], contains: corrected, timeout: 20)
        XCTAssertEqual(element("mail.reply.body", app).label, corrected)
        XCTAssertFalse(button("mail.reply.send", app).isEnabled)
        tap("mail.reply.reviewed", app)
        XCTAssertTrue(button("mail.reply.send", app).isEnabled)
        attach("complete-routine-mail-corrected-recipient-and-explicit-review", app)
        tap("mail.reply.send", app)
        home(app); reveal(app); tap("morning.settings", app)
        let receipt = element("qa.gmailReplyReceipt", app)
        XCTAssertTrue(receipt.exists, "The actual received MIME must be revealed in Settings, not assumed in a lazy row.")
        let proof = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(receipt.value as? String).utf8)) as? [String: String])
        XCTAssertEqual(proof["simulatedSendAttempts"], "1")
        XCTAssertEqual(proof["inboxReads"], "1"); XCTAssertEqual(proof["bodyReads"], "5")
        XCTAssertEqual(proof["from"], "owner@morning-fixture.invalid")
        XCTAssertEqual(proof["to"], "maia@morning-fixture.invalid")
        XCTAssertEqual(proof["body"], corrected)
        XCTAssertEqual(proof["threadID"], "synthetic-thread3")
        XCTAssertEqual(proof["inReplyTo"], "<synthetic3@synthetic.invalid>")
        XCTAssertEqual(proof["references"], proof["inReplyTo"])
        XCTAssertEqual(proof["receivedSessionID"], identity.session)
        XCTAssertEqual(proof["receivedRoutineVersionID"], identity.version)
        XCTAssertEqual(proof["receivedStepID"], identity.step)
        let attachment = XCTAttachment(string: String(decoding: try JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self))
        attachment.name = "complete-routine-actual-received-synthetic-mail-MIME"; attachment.lifetime = .keepAlways; add(attachment)
        attach("complete-routine-mail-one-received-simulated-send", app)
        home(app)
    }

    private func configureBrowser(_ index: Int, site: String, behavior: String, in app: XCUIApplication) {
        tap("routine.step.\(index)", app)
        choosePicker("step.targetApp", label: site, in: app)
        choosePicker("step.webBehavior", label: behavior, in: app)
        tap("step.save", app)
    }

    private func choosePicker(_ id: String, label: String, in app: XCUIApplication) {
        let query = app.descendants(matching: .any).matching(identifier: id)
        scroll(query.firstMatch, id: id, in: app)
        guard let value = query.allElementsBoundByIndex.first(where: { $0.isEnabled && $0.isHittable }) else {
            captureFailure("long-complete-picker-unavailable-" + id, app)
            XCTFail("The actual reviewed picker must be reachable: \(id)"); return
        }
        value.tap()
        let options = id == "step.targetApp"
            ? ["None", "Run an installed Shortcut", "Le Monde", "Reddit", "YouTube Shorts", "Instagram", "YouTube"]
            : ["I browse myself", "Read headlines aloud", "Browse the feed", "Watch videos", "Watch stories"]
        chooseNativePopup(label, pickerID: id, options: options, in: app)
    }

    private func browserDiagnostic(_ app: XCUIApplication) throws -> [String: String] {
        let result = app.staticTexts["web.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let value = try XCTUnwrap(result.value as? String)
        return Dictionary(value.split(separator: " ").compactMap { token in
            let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }, uniquingKeysWith: { _, last in last })
    }

    private func requireBrowserContext(_ value: [String: String], identity: Identity) {
        XCTAssertEqual(value["browserContext"] ?? value["newsContext"], "\(identity.session)|\(identity.version)|\(identity.step)")
    }

    private func selectSecondArticleAndReturn(_ app: XCUIApplication, identity: Identity) throws {
        let second = app.buttons["web.article.2"]
        XCTAssertTrue(second.waitForExistence(timeout: 25)); XCTAssertTrue(second.isHittable)
        XCTAssertEqual(second.label, "2. A reading corner at Cedar garden")
        let before = try browserDiagnostic(app); requireBrowserContext(before, identity: identity)
        second.tap()
        XCTAssertTrue(app.buttons["web.articleReturn"].waitForExistence(timeout: 30))
        let paragraph = "Cedar garden opens a reading corner on Saturday. Volunteers placed six benches beside the maples. Registration is free and takes place on site. The project used wood recovered from the nearby workshop. The library will lend books to visitors. This story is entirely invented for the SYNTHETIC test."
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", paragraph)).firstMatch.waitForExistence(timeout: 5))
        let selected = try browserDiagnostic(app); requireBrowserContext(selected, identity: identity)
        XCTAssertEqual(selected["resource"], "/article/two"); XCTAssertEqual(selected["articleParagraphs"], "1")
        XCTAssertEqual(selected["endsAtBits"], before["endsAtBits"])
        XCTAssertNotEqual(selected["pausedAtBits"], "none")
        attach("complete-routine-news-actual-second-body-same-session", app)
        tap("web.articleReturn", app)
        XCTAssertTrue(second.waitForExistence(timeout: 25))
        let returned = try browserDiagnostic(app); requireBrowserContext(returned, identity: identity)
        XCTAssertEqual(returned["resource"], "/headlines")
        for key in ["endsAtBits", "pausedAtBits"] { XCTAssertEqual(returned[key], selected[key]) }
        tap("web.resume", app)
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 8))
        attach("complete-routine-news-return-and-resume", app)
    }

    private func verifyFeedPauseAndRestore(_ app: XCUIApplication, identity: Identity, workspace: String) throws {
        let result = app.staticTexts["web.result"]
        let progressed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value MATCHES %@", ".*observedContents=[2-9][0-9]* .*"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 50), .completed)
        let running = try browserDiagnostic(app); requireBrowserContext(running, identity: identity)
        XCTAssertEqual(running["resource"], "/feed")
        tap("web.pause", app)
        let paused = try browserDiagnostic(app); requireBrowserContext(paused, identity: identity)
        XCTAssertNotEqual(paused["pausedAtBits"], "none")
        XCTAssertEqual(paused["endsAtBits"], running["endsAtBits"])
        attach("complete-routine-feed-observed-then-paused", app)
        app.terminate(); app.launch(); try requireWorkspace(workspace, app)
        reveal(app); tap("morning.settings", app); tap("stepTimer.openPage", app)
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 15))
        let restored = try browserDiagnostic(app); requireBrowserContext(restored, identity: identity)
        for key in ["startedAtBits", "endsAtBits", "pausedAtBits", "observedContents"] { XCTAssertEqual(restored[key], paused[key]) }
        let remaining = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        XCTAssertEqual(try browserDiagnostic(app)["observedContents"], paused["observedContents"], "A cold page load is not another observed content.")
        tap("web.resume", app)
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 8))
        requireBrowserContext(try browserDiagnostic(app), identity: identity)
        attach("complete-routine-feed-same-session-restored-without-inflated-count", app)
    }

    private func verifyMediaPlayback(_ app: XCUIApplication, identity: Identity, music: Bool) throws {
        let result = app.staticTexts["web.result"]
        for item in 1...(music ? 1 : 2) {
            let content = music ? "synthetic-music" : "synthetic-video-\(item)"
            let predicate = NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@ AND value MATCHES %@",
                "mediaContent=\(content)", "mediaPlaying=true", ".*mediaTime=([1-9][0-9]*\\.[0-9]+|0\\.[3-9][0-9]*).*")
            // Use a bounded predicate on the actual WebKit observation, never a
            // timer, tap on a DOM element or fabricated playback receipt.
            let playing = XCTNSPredicateExpectation(predicate: predicate, object: result)
            XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 50), .completed)
            let observed = try browserDiagnostic(app); requireBrowserContext(observed, identity: identity)
            XCTAssertEqual(observed["resource"], music ? "/music" : "/videos")
            XCTAssertEqual(observed["mediaContent"], content)
            XCTAssertEqual(observed["mediaPlaying"], "true")
            XCTAssertGreaterThan(try XCTUnwrap(observed["mediaTime"].flatMap(Double.init)), 0.25)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(observed["observedContents"].flatMap(Int.init)), item)
            attach(music ? "complete-routine-generated-music-actual-player" : "complete-routine-video-\(item)-actual-player", app)
        }
    }

    private func createExactReminder(_ app: XCUIApplication, identity: Identity) throws {
        let title = "Bring the blue notebook to North studio"
        interact(app); tap("nativeMoment.open", app)
        XCTAssertTrue(app.staticTexts["nativeMoment.synthetic"].exists)
        let request = element("nativeMoment.request", app)
        request.tap(); request.typeText("Remind me to " + title)
        tap("nativeMoment.prepare", app)
        XCTAssertEqual(element("nativeMoment.title", app).value as? String, title)
        let dated = app.switches["nativeMoment.hasDate"].firstMatch
        scroll(dated, id: "nativeMoment.hasDate", in: app)
        XCTAssertEqual(dated.value as? String, "0")
        let nativeSwitch = dated.switches.firstMatch
        if nativeSwitch.exists && nativeSwitch.isHittable { nativeSwitch.tap() } else { dated.tap() }
        XCTAssertEqual(dated.value as? String, "1")
        try chooseAbsoluteDate(in: app)
        tap("nativeMoment.editReview", app)
        let status = app.staticTexts["nativeMoment.status"]
        waitLabel(status, contains: title, timeout: 10)
        XCTAssertTrue(status.label.contains("October 16, 2026") && status.label.contains("Europe/Paris") && status.label.contains("with alert"), status.label)
        XCTAssertFalse(button("nativeMoment.confirm", app).isEnabled)
        tap("nativeMoment.reviewed", app)
        XCTAssertTrue(button("nativeMoment.confirm", app).isEnabled)
        tap("nativeMoment.confirm", app)
        waitLabel(status, contains: "was added", timeout: 15)
        let proofElement = element("nativeMoment.exactProof", app)
        let proof = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(proofElement.value as? String).utf8)) as? [String: String])
        XCTAssertEqual(proof["simulatedWrites"], "1"); XCTAssertEqual(proof["confirmed"], "1"); XCTAssertEqual(proof["unconfirmed"], "0")
        XCTAssertEqual(proof["title"], title); XCTAssertEqual(proof["kind"], "reminder"); XCTAssertEqual(proof["notes"], "")
        XCTAssertEqual(proof["receivedSessionID"], identity.session)
        XCTAssertEqual(proof["receivedRoutineVersionID"], identity.version)
        XCTAssertEqual(proof["receivedStepID"], identity.step)
        XCTAssertEqual(proof["nativeContextMatches"], "true")
        let dueBits = try XCTUnwrap(proof["dueReferenceBits"].flatMap { UInt64($0, radix: 16) })
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-16T07:25:00Z"))
        XCTAssertEqual(Double(bitPattern: dueBits), expected.timeIntervalSinceReferenceDate)
        XCTAssertEqual(proof["timeZoneIdentifier"], "Europe/Paris"); XCTAssertEqual(proof["notifyAtDueTime"], "true")
        XCTAssertEqual(proof["destinationID"], "synthetic-list"); XCTAssertEqual(proof["destinationSourceID"], "synthetic-account")
        XCTAssertFalse(app.buttons["nativeMoment.confirm"].exists)
        let receipt = XCTAttachment(string: String(decoding: try JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self))
        receipt.name = "complete-routine-one-actual-received-exact-simulated-reminder"; receipt.lifetime = .keepAlways; add(receipt)
        attach("complete-routine-reminder-one-reviewed-write", app)
        tap("nativeMoment.cancel", app); tap("morning.closeDetails", app); home(app)
        XCTAssertEqual(try self.identity(app, index: 6), identity)
        reveal(app)
        let resume = button("morning.playback", app)
        XCTAssertEqual(resume.label, "Continue"); resume.tap()
    }

    private func chooseAbsoluteDate(in app: XCUIApplication) throws {
        let picker = app.descendants(matching: .any).matching(identifier: "nativeMoment.date").firstMatch
        scroll(picker, id: "nativeMoment.date", in: app)
        let datePattern = ".*[12][0-9]{3}.*"
        guard let dateButton = picker.buttons.allElementsBoundByIndex.first(where: {
            $0.isHittable && ($0.label.range(of: datePattern, options: .regularExpression) != nil || ($0.value as? String ?? "").range(of: datePattern, options: .regularExpression) != nil)
        }) else { captureFailure("exact-reminder-native-date-control-unavailable", app); throw DiagnosticFailure.invalid }
        dateButton.tap()
        let headerPattern = "^(January|February|March|April|May|June|July|August|September|October|November|December) [12][0-9]{3}$"
        let headers = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value MATCHES %@",
                                                       "DatePicker.Show", headerPattern))
        guard headers.firstMatch.waitForExistence(timeout: 5) else {
            captureFailure("exact-reminder-month-year-unavailable", app); throw DiagnosticFailure.invalid
        }
        guard let header = headers.allElementsBoundByIndex.first(where: \.isHittable) else { captureFailure("exact-reminder-month-year-unavailable", app); throw DiagnosticFailure.invalid }
        header.tap()
        let wheels = app.pickerWheels.allElementsBoundByIndex.filter(\.isHittable)
        guard wheels.count == 2 else { captureFailure("exact-reminder-native-month-year-wheels-unavailable", app); throw DiagnosticFailure.invalid }
        wheels[0].adjust(toPickerWheelValue: "October"); wheels[1].adjust(toPickerWheelValue: "2026")
        guard let selectedHeader = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value == %@",
            "DatePicker.Hide", "October 2026")).allElementsBoundByIndex.first(where: \.isHittable) else {
            captureFailure("exact-reminder-absolute-month-year-not-observed", app); throw DiagnosticFailure.invalid
        }
        selectedHeader.tap()
        let days = app.buttons.matching(NSPredicate(format: "label IN %@", ["Friday, October 16, 2026", "Friday, October 16", "Today, Friday, October 16, 2026", "Today, Friday, October 16", "16"]))
        guard let day = days.allElementsBoundByIndex.first(where: \.isHittable) else { captureFailure("exact-reminder-calendar-day-unavailable", app); throw DiagnosticFailure.invalid }
        day.tap()
        closeNativePickerIfNeeded(app)
        scroll(picker, id: "nativeMoment.date", in: app)
        // The aggregate date/time control also includes a time in its value;
        // only the standalone native time button opens the time wheels.
        let timePattern = "^[0-9]{1,2}:[0-9]{2}(?:\\s*[AP]M)?$"
        guard let time = picker.buttons.allElementsBoundByIndex.first(where: {
            $0.isHittable && ($0.label.range(of: timePattern, options: .regularExpression) != nil ||
                ($0.value as? String ?? "").range(of: timePattern, options: .regularExpression) != nil)
        }) else { captureFailure("exact-reminder-native-time-control-unavailable", app); throw DiagnosticFailure.invalid }
        time.tap()
        let timeWheels = app.pickerWheels.allElementsBoundByIndex.filter(\.isHittable)
        guard timeWheels.count == 2 || timeWheels.count == 3 else { captureFailure("exact-reminder-native-time-wheels-unavailable", app); throw DiagnosticFailure.invalid }
        timeWheels[0].adjust(toPickerWheelValue: "9"); timeWheels[1].adjust(toPickerWheelValue: "25")
        if timeWheels.count == 3 { timeWheels[2].adjust(toPickerWheelValue: "AM") }
        closeNativePickerIfNeeded(app)
    }
    private func closeNativePickerIfNeeded(_ app: XCUIApplication) {
        if let dismiss = app.buttons.matching(identifier: "PopoverDismissRegion").allElementsBoundByIndex.first(where: \.isHittable) {
            let rect = dismiss.frame.intersection(app.frame)
            let obstacles = app.datePickers.allElementsBoundByIndex.filter {
                $0.exists && $0.identifier != "nativeMoment.date" && !$0.frame.isEmpty
            }.map(\.frame) + app.pickerWheels.allElementsBoundByIndex.filter(\.exists).map(\.frame)
            let points = [CGPoint(x: rect.minX + rect.width * 0.04, y: rect.midY),
                          CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.midY),
                          CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.04)]
            guard !rect.isNull, !rect.isInfinite, rect.width > 40, rect.height > 40,
                  [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy({ $0.isFinite }),
                  !obstacles.isEmpty, let point = points.first(where: { point in
                      rect.contains(point) && !obstacles.contains(where: { $0.contains(point) })
                  }) else { captureFailure("exact-reminder-native-popup-has-no-dismiss-point", app); return }
            // The system dismiss button spans the screen; its centre is covered
            // by the calendar. Tap only its observed exposed area outside it.
            dismiss.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: point.x - dismiss.frame.minX, dy: point.y - dismiss.frame.minY)).tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dismiss)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
            return
        }
        if let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Close"])).allElementsBoundByIndex.first(where: {
            $0.isHittable && $0.identifier != "morning.closeDetails" && $0.identifier != "destination.close"
        }) { done.tap() }
    }

    private func beginRoutineFromOpening(_ app: XCUIApplication) {
        // This visible greeting is not the Calendar moment, even when it quotes
        // the very same event. Continue is Home's actual chooseOpening(.ritual).
        reveal(app)
        let play = button("morning.playback", app)
        let offered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label IN %@", ["Continue", "Pause"]), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [offered], timeout: 15), .completed)
        if play.label == "Continue" { XCTAssertTrue(play.isHittable); play.tap() }
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
        // A readonly preview is evidence, not a tap target. Its own native
        // sheet must scroll; the Settings list behind it is never a fallback.
        let preview = revealBriefingText(in: app)
        waitLabel(preview, contains: "Synthetic quiet reading", timeout: 15)
        XCTAssertFalse(app.alerts.firstMatch.exists, "No real Calendar or weather permission is requested.")
        attach("long-ten-selected-synthetic-calendar-source", app)
        app.navigationBars["Your day"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Your day"].waitForNonExistence(timeout: 5))
    }

    private func revealBriefingText(in app: XCUIApplication) -> XCUIElement {
        let preview = app.staticTexts["briefing.text"]
        let bar = app.navigationBars["Your day"], done = bar.buttons["Done"]
        let forms = app.collectionViews.allElementsBoundByIndex
        guard done.exists && done.isHittable,
              let index = forms.firstIndex(where: {
                  $0.descendants(matching: .any).matching(identifier: "briefing.synthetic").firstMatch.exists
              }) else {
            captureFailure("long-ten-briefing-sheet-not-observed", app)
            XCTFail("The Your day sheet and its synthetic source must own this scroll."); return preview
        }
        // Keep this exact ancestor index after its lazy header leaves the viewport.
        let form = app.collectionViews.element(boundBy: index)
        for _ in 0..<10 {
            if preview.exists { return preview }
            guard done.exists && done.isHittable, form.exists else { break }
            let viewport = form.frame.intersection(app.frame)
            let top = max(viewport.minY, bar.frame.maxY) + 8
            let bottom = viewport.maxY - 24
            guard !viewport.isNull, !viewport.isInfinite,
                  [viewport.minX, viewport.width, top, bottom].allSatisfy({ $0.isFinite }),
                  viewport.width > 80, bottom - top > 120 else { break }
            let origin = form.coordinate(withNormalizedOffset: .zero)
            let x = viewport.midX - form.frame.minX
            let start = origin.withOffset(CGVector(dx: x, dy: top + (bottom - top) * 0.8 - form.frame.minY))
            let end = origin.withOffset(CGVector(dx: x, dy: top + (bottom - top) * 0.2 - form.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        captureFailure("long-ten-briefing-preview-not-observed", app)
        XCTFail("The actual selected Calendar facts must be observed before approval."); return preview
    }

    private func configureOperation(_ index: Int, action: String, minutes: Int, detail: String,
                                    keep: Bool = false, in app: XCUIApplication) {
        tap("routine.step.\(index)", app)
        replace(app.textFields["Step details"], id: "Step details", with: detail, in: app)
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

    private func replace(_ field: XCUIElement, id: String, with text: String, in app: XCUIApplication) {
        // Lazy Forms may not expose the field yet. Its known locator is safe to
        // name diagnostics before scrolling; querying field.label is not.
        scroll(field, id: id, in: app)
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
    private func requireRecap(_ app: XCUIApplication, trace: [Identity], titles: [String], complete: Bool = false) throws {
        home(app); reveal(app); tap("morning.settings", app)
        XCTAssertTrue(element("morning.completeSummary", app).label.hasPrefix("10 moments"))
        XCTAssertTrue(element("morning.executionSummary", app).label.contains(complete ? "Timed moments finished: 3." : "Timed moments finished: 7."))
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
                XCTAssertTrue(row.label.contains(complete && [3, 4, 5, 8].contains(index)
                    ? "Allocated time finished; no additional action verified." : "Timed budget finished."), row.label)
                XCTAssertFalse(row.label.contains("Operation verified."), "A budget certifies no provider effect.")
                if complete, [3, 4, 5, 8].contains(index) {
                    XCTAssertTrue(row.label.contains("contents observed"), row.label)
                    XCTAssertFalse(row.label.contains("Browser: 0 contents"), row.label)
                }
            }
        }
        XCTAssertEqual(element("recap.slackRepliesUnconfirmed", app).label, "Slack replies to check: 1")
        XCTAssertFalse(app.staticTexts["recap.slackReplies"].exists)
        if complete { XCTAssertEqual(element("recap.nativeActions", app).label, "Apple actions confirmed: 1") }
        else { XCTAssertFalse(app.staticTexts["recap.nativeActions"].exists) }
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
        if app.launchArguments.contains("--ui-testing-private-routine-browser"), [3, 4, 5, 8].contains(index) {
            let expectedStep = String(format: "90000000-0000-4000-8000-%012d", index + 1)
            let result = app.staticTexts["web.result"]
            let pattern = ".*(newsContext|browserContext)=[^ ]+\\|" + NSRegularExpression.escapedPattern(for: expectedStep) + " .*"
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value MATCHES %@", pattern), object: result)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
            let value = try browserDiagnostic(app)
            let fields = try XCTUnwrap(value["newsContext"] ?? value["browserContext"]).components(separatedBy: "|")
            XCTAssertEqual(fields.count, 3)
            guard fields.count == 3 else { throw DiagnosticFailure.invalid }
            for value in fields { XCTAssertNotNil(UUID(uuidString: value)) }
            XCTAssertEqual(fields[2], expectedStep)
            return Identity(session: fields[0], step: fields[2], version: fields[1], index: index)
        }
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
        if app.launchArguments.contains("--ui-testing-private-routine-browser"), app.buttons["web.close"].isHittable {
            let data = try browserDiagnostic(app)
            return TimerSnapshot(startedBits: try XCTUnwrap(data["startedAtBits"].flatMap { UInt64($0, radix: 16) }),
                endsBits: try XCTUnwrap(data["endsAtBits"].flatMap { UInt64($0, radix: 16) }),
                pausedBits: data["pausedAtBits"] == "none" ? nil : try XCTUnwrap(data["pausedAtBits"].flatMap { UInt64($0, radix: 16) }))
        }
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
        try MorningUITestNavigation.requireIsolatedWorkspace(workspace, in: app)
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
        chooseNativePopup(name, pickerID: "step.automation", options: ["User-led moment", "Read this text aloud",
            "Read today's calendar", "Read today's briefing", "Keep this time, then continue", "Read my mail and help me reply"], in: app)
    }
    private func chooseNativePopup(_ name: String, pickerID: String, options: [String], in app: XCUIApplication) {
        let labels = NSPredicate(format: "label IN %@", options + [name])
        guard app.descendants(matching: .any).matching(labels).firstMatch.waitForExistence(timeout: 6) else {
            captureFailure("long-ten-native-popup-not-observed-" + pickerID, app)
            XCTFail("The native Picker must expose its real options."); return
        }
        for _ in 0..<12 {
            let candidates = app.menus.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            guard let popup = candidates.filter({ item in
                item.exists && !["step.editor.form", "routine.editor", "morning.captions"].contains(item.identifier) &&
                    !item.frame.isEmpty && item.frame.intersects(app.frame) &&
                    item.descendants(matching: .any).matching(labels).allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
            }).min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { break }
            let bounds = popup.frame.intersection(app.frame)
            let exact = popup.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name))
            if let choice = exact.allElementsBoundByIndex.first(where: {
                [.button, .menuItem, .staticText].contains($0.elementType) && $0.exists && $0.isEnabled && $0.isHittable &&
                    !$0.frame.isEmpty && bounds.contains($0.frame)
            }) {
                choice.tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(
                    format: "exists == true AND (label CONTAINS %@ OR value CONTAINS %@)", name, name),
                    object: app.descendants(matching: .any).matching(identifier: pickerID).firstMatch)
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                               "The actual Picker must show the selected option before Save.")
                return
            }
            // The native popup's frame may extend beneath the editor. Only an
            // actual wholly visible option may receive a real scroll gesture.
            guard let anchor = popup.descendants(matching: .any).matching(labels).allElementsBoundByIndex.first(where: {
                [.button, .staticText, .menuItem].contains($0.elementType) && $0.exists && $0.isHittable &&
                    !$0.frame.isEmpty && app.frame.contains($0.frame)
            }) else { break }
            anchor.swipeUp()
        }
        captureFailure("long-ten-native-popup-choice-unreachable-" + pickerID, app)
        XCTFail("The exact option must be selected in the foreground native popup: \(name)")
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
    private func tap(_ id: String, _ app: XCUIApplication) {
        if id.hasPrefix("routine.step.") { openStep(id, in: app) }
        else { button(id, app).tap() }
    }
    private func openStep(_ id: String, in app: XCUIApplication) {
        let list = app.collectionViews["routine.editor"].firstMatch
        let row = app.buttons[id].firstMatch
        guard list.waitForExistence(timeout: 6) else {
            captureFailure("long-ten-routine-list-absent", app); XCTFail("The real routine List must be open."); return
        }
        for down in [false, true] {
            for _ in 0..<10 {
                let frame = list.frame.intersection(app.frame)
                // Bars define safe geometry; only the moment row is tapped.
                let nav = app.navigationBars.allElementsBoundByIndex.last(where: {
                    $0.exists && !$0.frame.isEmpty && $0.frame.minY.isFinite && $0.frame.maxY.isFinite && $0.frame.intersects(frame)
                })
                let approval = app.buttons["routine.approve"]
                let top = max(frame.minY, nav?.frame.maxY ?? frame.minY) + 8
                let footer = approval.exists && approval.frame.intersects(frame) ? approval.frame.minY : frame.maxY
                let bottom = min(frame.maxY, footer) - 8
                guard !frame.isNull, !frame.isInfinite,
                      [frame.minX, frame.width, top, bottom].allSatisfy({ $0.isFinite }),
                      frame.width > 100, bottom - top > 120 else {
                    captureFailure("long-ten-routine-no-visible-row-region", app); XCTFail("No safe routine viewport."); return
                }
                let visible = CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
                if row.exists && row.isHittable && !row.frame.isEmpty && visible.contains(row.frame) {
                    row.tap()
                    guard stepEditorForm(app).waitForExistence(timeout: 8) else {
                        captureFailure("long-ten-editor-not-open-after-\(id)", app)
                        XCTFail("Tapping the visible moment must open its real editor before any field is queried."); return
                    }
                    return
                }
                let high = visible.minY + visible.height * 0.2, low = visible.minY + visible.height * 0.8
                let origin = list.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: visible.midX - list.frame.minX, dy: (down ? high : low) - list.frame.minY))
                let end = origin.withOffset(CGVector(dx: visible.midX - list.frame.minX, dy: (down ? low : high) - list.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        captureFailure("long-ten-row-not-fully-visible-\(id)", app)
        XCTFail("The entire moment row must be above the approval footer before tapping it.")
    }
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
        if let bar = app.navigationBars.allElementsBoundByIndex.last(where: {
            $0.exists && !$0.frame.isEmpty && $0.frame.minY.isFinite && $0.frame.maxY.isFinite && $0.frame.intersects(viewport)
        }) {
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
                let owned = ownedScrollRegion(in: app)
                let slack = app.scrollViews["slack.setup.scroll"].firstMatch
                let editor = stepEditorForm(app)
                let slackForeground = owned == nil && slack.exists && slack.isHittable
                let editorForeground = owned == nil && editor.exists && editor.isHittable
                let routine = owned == nil && !slackForeground && !editorForeground ? routineScrollRegion(in: app) : nil
                func visible(_ element: XCUIElement) -> Bool {
                    guard element.exists else { return false }
                    let frame = element.frame
                    guard !frame.isEmpty, !frame.isNull, !frame.isInfinite,
                          [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy({ $0.isFinite }) else { return false }
                    let viewport = owned?.visible ?? routine?.visible ?? app.frame
                    // Readonly text is observed, never tapped. A real exposed
                    // portion is sufficient; exact label/value assertions remain.
                    if element.elementType == .staticText, let region = owned ?? routine {
                        let scoped = region.container.descendants(matching: .staticText).matching(
                            NSPredicate(format: "identifier == %@ OR label == %@", id, id))
                        return region.visible.intersects(frame) && scoped.allElementsBoundByIndex.contains { candidate in
                            candidate.exists && candidate.frame == frame && candidate.label == element.label &&
                                String(describing: candidate.value) == String(describing: element.value)
                        }
                    }
                    guard element.isHittable && app.frame.contains(frame) else { return false }
                    return (owned != nil || id.hasPrefix("routine.step.")) ? viewport.contains(frame) : true
                }
                if visible(value) { return }
                if app.buttons.matching(identifier: id).allElementsBoundByIndex.contains(where: visible) { return }
                if slackForeground {
                    if down { slack.swipeDown() } else { slack.swipeUp() }
                } else if editorForeground {
                    guard dragVisibleEditor(editor, down: down, in: app) else { return }
                } else if let routine {
                    // The List is geometry, not the tap target. Its visible
                    // controls establish foreground ownership even when the
                    // collection itself reports isHittable=false.
                    let frame = routine.container.frame, visible = routine.visible
                    let high = visible.minY + visible.height * 0.2, low = visible.minY + visible.height * 0.8
                    let origin = routine.container.coordinate(withNormalizedOffset: .zero)
                    let start = origin.withOffset(CGVector(dx: visible.midX - frame.minX, dy: (down ? high : low) - frame.minY))
                    let end = origin.withOffset(CGVector(dx: visible.midX - frame.minX, dy: (down ? low : high) - frame.minY))
                    start.press(forDuration: 0.05, thenDragTo: end)
                } else if let owned {
                    let frame = owned.container.frame, area = owned.visible
                    let origin = owned.container.coordinate(withNormalizedOffset: .zero)
                    let high = area.minY + area.height * 0.2, low = area.minY + area.height * 0.8
                    let start = origin.withOffset(CGVector(dx: area.midX - frame.minX, dy: (down ? high : low) - frame.minY))
                    let end = origin.withOffset(CGVector(dx: area.midX - frame.minX, dy: (down ? low : high) - frame.minY))
                    start.press(forDuration: 0.05, thenDragTo: end)
                } else {
                    captureFailure("long-ten-no-foreground-scroll-\(id)", app)
                    XCTFail("No foreground scroll container is available for \(id)."); return
                }
            }
        }
        captureFailure("long-ten-unreachable-\(id)", app)
        XCTFail("Unreachable ordinary UI: \(id)")
    }

    private func ownedScrollRegion(in app: XCUIApplication) -> (container: XCUIElement, visible: CGRect)? {
        guard let bar = app.navigationBars.allElementsBoundByIndex.last(where: {
            $0.exists && !$0.frame.isEmpty && $0.frame.intersects(app.frame)
        }), bar.buttons.allElementsBoundByIndex.contains(where: { $0.exists && $0.isHittable }) else { return nil }
        let container: XCUIElement
        let close = app.buttons["morning.closeDetails"]
        if close.exists && close.isHittable {
            // This marker belongs to the outer, non-lazy Interact ScrollView,
            // never an inner reply editor or Home's captions behind the sheet.
            container = app.scrollViews.containing(.any, identifier: "morning.voiceStatus").firstMatch
        } else {
            switch bar.identifier {
            case "Apps & accounts": container = app.collectionViews["connections.list"].firstMatch
            case "Settings": container = app.collectionViews["settings.appearance"].firstMatch
            case "History": container = app.scrollViews["review.week"].firstMatch
            default: return nil
            }
        }
        guard container.exists else { return nil }
        let viewport = container.frame.intersection(app.frame)
        let top = max(viewport.minY, bar.frame.maxY) + 8
        let keyboard = app.keyboards.firstMatch
        let bottom = min(viewport.maxY - 24, keyboard.exists ? keyboard.frame.minY - 8 : viewport.maxY - 24)
        guard !viewport.isNull, !viewport.isInfinite,
              [viewport.minX, viewport.width, top, bottom].allSatisfy({ $0.isFinite }),
              viewport.width > 80, bottom - top > 120 else { return nil }
        return (container, CGRect(x: viewport.minX + 12, y: top, width: viewport.width - 24, height: bottom - top))
    }

    private func routineScrollRegion(in app: XCUIApplication) -> (container: XCUIElement, visible: CGRect)? {
        let list = app.collectionViews["routine.editor"].firstMatch
        guard list.exists else { return nil }
        let approve = app.buttons["routine.approve"], edit = app.buttons["routine.edit"]
        let visibleChild = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step."))
            .allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
        guard (approve.exists && approve.isHittable) || (edit.exists && edit.isHittable) || visibleChild else { return nil }
        let viewport = list.frame.intersection(app.frame)
        guard !viewport.isNull, !viewport.isInfinite,
              [viewport.minX, viewport.minY, viewport.maxX, viewport.maxY].allSatisfy({ $0.isFinite }) else { return nil }
        // A navigation bar only bounds the gesture; it need not be tappable.
        guard let bar = app.navigationBars.allElementsBoundByIndex.last(where: {
            $0.exists && !$0.frame.isEmpty && $0.frame.minY.isFinite && $0.frame.maxY.isFinite && $0.frame.intersects(viewport)
        }) else { return nil }
        let top = max(viewport.minY, bar.frame.maxY) + 8
        let footer = approve.exists && approve.frame.intersects(viewport) ? approve.frame.minY : viewport.maxY
        let bottom = min(viewport.maxY, footer) - 8
        guard top.isFinite, bottom.isFinite, viewport.width > 100, bottom - top > 120 else { return nil }
        return (list, CGRect(x: viewport.minX + 12, y: top, width: viewport.width - 24, height: bottom - top))
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
