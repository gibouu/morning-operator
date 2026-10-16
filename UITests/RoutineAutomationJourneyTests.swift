import XCTest

/// Synthetic routine/persisted budgets; live-news explicitly uses a real public page.
@MainActor
final class RoutineAutomationJourneyTests: XCTestCase {
    /// This is the separately authored portable oracle, not OCR/model output or
    /// an executable provider plan. Only the ordinary editor delegates its draft.
    func testParsedSyntheticFrenchRoutineStaysEditableAndApprovedAfterRelaunch() throws {
        // Literal copy of Benchmarks/routine-fixture-v1/oracle-draft-fr.more-routine.json.
        let portable = #"{"format":"morning-operator.routine","formatVersion":1,"detail":"includeDetails","sourceRoutineID":"90000000-0000-4000-8000-000000000100","sourceRoutineVersion":1,"sourceCreatedAt":1792129500.0,"approvalAtExport":false,"sourceIsSynthetic":true,"sourceLabel":"Demo fixture — SYNTHETIC manual oracle; no OCR or model execution","steps":[{"id":"90000000-0000-4000-8000-000000000001","title":"Mon agenda","kind":"calendar","durationMinutes":2,"isRequired":false,"detail":"SYNTHETIC — Consulter le calendrier principal fictif, sans confondre les homonymes."},{"id":"90000000-0000-4000-8000-000000000002","title":"Mes mails et ma réponse","kind":"messages","durationMinutes":5,"isRequired":false,"detail":"SYNTHETIC — Choisir le troisième mail, corriger six cartes bleues en huit cartes vertes, relire puis simuler un seul envoi."},{"id":"90000000-0000-4000-8000-000000000003","title":"Mon équipe","kind":"messages","durationMinutes":3,"isRequired":false,"detail":"SYNTHETIC — Une réponse simulée incertaine ne doit jamais être relancée automatiquement."},{"id":"90000000-0000-4000-8000-000000000004","title":"Deuxième article et retour","kind":"briefing","durationMinutes":4,"isRequired":false,"detail":"SYNTHETIC — Choisir le deuxième lien observé, lire le texte attribué, revenir aux titres avec le budget restant."},{"id":"90000000-0000-4000-8000-000000000005","title":"Mon fil à mon rythme","kind":"entertainment","durationMinutes":3,"isRequired":false,"detail":"SYNTHETIC — Pause puis reprise. La durée personnelle de trois minutes prime sur les quatre minutes observées dans la source réaliste."},{"id":"90000000-0000-4000-8000-000000000006","title":"Mes vidéos","kind":"entertainment","durationMinutes":3,"isRequired":false,"detail":"SYNTHETIC — Deux contenus fictifs successifs. Aucun contrôle de vrai service n’est prouvé."},{"id":"90000000-0000-4000-8000-000000000007","title":"Mon rappel exact","kind":"custom","durationMinutes":1,"isRequired":false,"detail":"SYNTHETIC — Apporter le carnet bleu au studio Nord. 16 octobre 2026 à 09:25 Europe/Paris. Une seule écriture simulée."},{"id":"90000000-0000-4000-8000-000000000008","title":"Lire cinq pages","kind":"wellbeing","durationMinutes":3,"isRequired":true,"detail":"SYNTHETIC — Rituel personnel Garder conservé même si l’inférence l’omet. Le texte d’une page n’autorise aucun choix personnel."},{"id":"90000000-0000-4000-8000-000000000009","title":"Un peu de musique","kind":"wellbeing","durationMinutes":2,"isRequired":false,"detail":"SYNTHETIC — Lecteur fictif. La vidéo de test ne contient aucune piste audio."},{"id":"90000000-0000-4000-8000-000000000010","title":"La fin de mon matin","kind":"briefing","durationMinutes":2,"isRequired":false,"detail":"SYNTHETIC — Récap ajouté explicitement : Gmail et rappel simulés, Slack incertain. Ne pas apprendre ce moment depuis les écrans MORE."}]}"#
        let data = Data(portable.utf8)
        let document = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try XCTUnwrap(document["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 10)
        XCTAssertEqual(steps.compactMap { $0["durationMinutes"] as? Int }.reduce(0, +), 28)
        let titles = try steps.map { try XCTUnwrap($0["title"] as? String) }
        let app = launch(["--ui-testing-approved", "--ui-testing-stopped-run", "--ui-testing-ten-moments",
                          "--ui-testing-parsed-routine=" + data.base64EncodedString()], french: true)
        defer { app.terminate() }
        tapHomeSettings(app)
        let routine = visibleButton("setup.routine", in: app)
        XCTAssertTrue(routine.label.contains("10 moments") && routine.label.contains("28 min"), routine.label)
        routine.tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled,
                      "The parsed plan must remain a draft even with the ordinary approval fixture flag.")
        for index in titles.indices {
            XCTAssertTrue(visibleButton("routine.step.\(index)", in: app).label.contains(titles[index]))
        }
        XCTAssertFalse(app.buttons["routine.step.10"].exists)
        // Label's decorative image shares its identifier with the readable text.
        let synthetic = app.staticTexts["routine.source"]
        scrollTo(synthetic, identifier: "routine.source", in: app)
        XCTAssertFalse(synthetic.label.isEmpty)
        attach("automation-parsed-synthetic-ten-moment-french-draft", app)
        enabledVisibleButton("routine.step.0", in: app).tap()
        let duration = app.steppers["step.duration"]
        scrollTo(duration, identifier: "step.duration", in: app)
        XCTAssertEqual(duration.value as? String, "2")
        let increment = duration.buttons["step.duration-Increment"]
        XCTAssertTrue(increment.isHittable)
        increment.tap()
        XCTAssertEqual(duration.value as? String, "3")
        enabledVisibleButton("step.save", in: app).tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
        _ = visibleButton("routine.step.0", in: app)
        _ = visibleButton("routine.step.1", in: app)
        enabledVisibleButton("routine.edit", in: app).tap()
        let reorder = app.buttons.matching(NSPredicate(format:
            "(label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@) AND label CONTAINS %@",
            "Réorganiser", "Reorder", titles[0])).firstMatch
        guard reorder.waitForExistence(timeout: 5), reorder.isHittable else {
            captureFailure("parsed-routine-native-reorder-handle-unavailable", app)
            XCTFail("The real native editor must expose its reorder handle; no Store mutation substitutes this gesture.")
            return
        }
        let second = app.buttons["routine.step.1"]
        reorder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        enabledVisibleButton("routine.edit", in: app).tap()
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", titles[1]), object: app.buttons["routine.step.0"])
        let reorderedResult = XCTWaiter.wait(for: [reordered], timeout: 5)
        if reorderedResult != .completed { captureFailure("parsed-routine-native-reorder-did-not-save", app) }
        XCTAssertEqual(reorderedResult, .completed)
        XCTAssertTrue(app.buttons["routine.step.1"].label.contains(titles[0]))
        XCTAssertTrue(app.buttons["routine.step.1"].label.contains("3 min"))
        attach("automation-parsed-synthetic-routine-duration-and-order-edited", app)
        enabledVisibleButton("routine.approve", in: app).tap()
        returnHome(app)
        app.terminate()
        app.launchArguments.removeAll {
            $0.hasPrefix("--ui-testing-parsed-routine=") || $0 == "--ui-testing-approved" ||
                $0 == "--ui-testing-stopped-run" || $0 == "--ui-testing-ten-moments" || $0 == "--ui-testing-empty-workspace"
        }
        app.launch()
        let workspace = try XCTUnwrap(app.launchArguments.first { $0.hasPrefix("--ui-testing-workspace=") }
            .map { String($0.dropFirst("--ui-testing-workspace=".count)) })
        XCTAssertTrue(app.staticTexts["qa.testWorkspace"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["qa.testWorkspace"].value as? String, workspace)
        tapHomeSettings(app)
        let saved = visibleButton("setup.routine", in: app)
        XCTAssertTrue(saved.label.contains("10 moments") && saved.label.contains("29 min"), saved.label)
        saved.tap()
        XCTAssertTrue(app.buttons["routine.edit"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["routine.approve"].exists, "Approval must come from the saved review, not a launch flag.")
        var savedTitles = titles
        savedTitles.swapAt(0, 1)
        for index in savedTitles.indices {
            let row = visibleButton("routine.step.\(index)", in: app)
            XCTAssertTrue(row.label.contains(savedTitles[index]), row.label)
            if index == 1 { XCTAssertTrue(row.label.contains("3 min")) }
        }
        XCTAssertFalse(app.buttons["routine.step.10"].exists)
        attach("automation-parsed-synthetic-routine-approved-and-restored", app)
    }

    func testSyntheticSlackUncertainSendReplacesTheOldInstructionOnHome() {
        checkSyntheticSlackUncertainSendOnHome()
    }

    func testFrenchLargestSyntheticSlackUncertainSendKeepsHomeControlsReachable() {
        checkSyntheticSlackUncertainSendOnHome(french: true, largestText: true)
    }

    private func checkSyntheticSlackUncertainSendOnHome(french: Bool = false, largestText: Bool = false) {
        var flags = ["--ui-testing-slack-reply", "--ui-testing-slack-uncertain-send", "--ui-testing-approved", "--ui-testing-hands-free"]
        if largestText { flags += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        let app = launch(flags, french: french)
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        openHomeInteraction(app)
        tapVisible("slackMoment.message.0", in: app)
        let intention = app.descendants(matching: .any).matching(identifier: "slackMoment.intention").firstMatch
        scrollTo(intention, identifier: "slackMoment.intention", in: app)
        intention.tap(); intention.typeText("SYNTHETIC please confirm the meeting")
        dismissSlackKeyboardIfShown(app)
        tapVisible("slackMoment.prepare", in: app)
        XCTAssertTrue(app.buttons["slackMoment.send"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["slackMoment.synthetic"].exists)
        // This fixture interrupts TTS; only an actual complete screen review
        // opens the gate. It never proves acoustic recognition or a provider write.
        tapVisible("slackMoment.reviewed", in: app)
        enabledVisibleButton("slackMoment.send", in: app).tap()
        let status = app.staticTexts["slackMoment.status"]
        let uncertain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", french ? "La publication Slack n’est pas confirmée" : "Slack post is unconfirmed"), object: status)
        let result = XCTWaiter.wait(for: [uncertain], timeout: 10)
        if result != .completed { captureFailure("synthetic-slack-uncertain-not-shown", app) }
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(app.buttons["slackMoment.send"].exists)
        tapVisible("morning.closeDetails", in: app)
        returnHome(app)
        let homeStatus = app.staticTexts["morning.actionStatus"]
        XCTAssertTrue(homeStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(homeStatus.label.contains(french ? "La publication Slack n’est pas confirmée" : "Slack post is unconfirmed"))
        XCTAssertTrue(homeStatus.label.contains(french ? "ne la relance pas" : "will not retry"))
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertFalse(app.staticTexts["morning.previousCaption"].exists)
        XCTAssertFalse(app.staticTexts["morning.currentStep"].exists)
        XCTAssertFalse(app.staticTexts["morning.remaining"].exists)
        XCTAssertFalse(app.buttons["morning.actionDetails"].exists)
        revealHomeControls(app)
        for id in ["morning.playback", "morning.settings"] {
            XCTAssertTrue(app.buttons[id].isHittable, "The revealed Home control must remain reachable at this text size: \(id)")
        }
        attach(largestText ? "automation-synthetic-slack-uncertain-french-largest-home" : "automation-synthetic-slack-uncertain-state-on-home", app)
        for id in ["morning.next", "morning.more", "morning.details", "morning.stop", "morning.extend"] {
            XCTAssertFalse(app.buttons[id].exists, "Additional commands belong in Settings, not on Home: \(id)")
        }
        XCTAssertEqual(app.navigationBars.count, 0)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["morning.settings"])
        let hiddenResult = XCTWaiter.wait(for: [hidden], timeout: 8)
        if hiddenResult != .completed { captureFailure("synthetic-slack-home-controls-did-not-hide", app) }
        XCTAssertEqual(hiddenResult, .completed, "Home commands must leave the landscape after five seconds without interaction.")
        XCTAssertTrue(homeStatus.exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        XCTAssertFalse(app.buttons["morning.next"].exists)
        attach(largestText ? "automation-synthetic-slack-uncertain-french-largest-quiet-home" : "automation-synthetic-slack-uncertain-quiet-home", app)
        openHomeInteraction(app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains(french ? "La publication Slack n’est pas confirmée" : "Slack post is unconfirmed"))
        XCTAssertFalse(app.buttons["slackMoment.send"].exists)
        attach(largestText ? "automation-synthetic-slack-uncertain-french-largest-reopened" : "automation-synthetic-slack-uncertain-reopened-without-retry", app)
    }

    func testFrenchLargestScreenTimeOverflowKeepsTheSourceAndLetsMeChooseEightApps() {
        let app = launch(["--ui-testing-approved", "--ui-testing-learning-source-join", "--ui-testing-evidence-proposals",
                          "--ui-testing-learning-source-many-apps", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openScreenTimeObservationChoices(app)
        enabledVisibleButton("observation.select.44444444-4444-4444-8444-444444444444", in: app).tap()
        enabledVisibleButton("observations.suggestUpdate", in: app).tap()
        let notice = app.staticTexts["observations.notice"]
        scrollTo(notice, identifier: "observations.notice", in: app)
        XCTAssertTrue(notice.label.contains("8"), notice.label)
        XCTAssertTrue(notice.label.contains("Choisissez les apps"), notice.label)
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        XCTAssertTrue(app.buttons["observations.suggestUpdate"].isEnabled)
        attach("automation-learning-many-apps-french-largest-recoverable-limit", app)
        for id in ["net.whatsapp.WhatsApp", "com.google.Gmail", "com.chess.iphone", "com.google.ios.youtube"] {
            let choice = visibleScreenTimeSwitch(id, in: app)
            XCTAssertEqual(choice.value as? String, "1", "The overflow must preserve the choices.")
            let native = choice.switches.firstMatch
            if native.exists && native.isHittable { native.tap() } else { choice.tap() }
            XCTAssertEqual(choice.value as? String, "0")
        }
        enabledVisibleButton("observations.suggestUpdate", in: app).tap()
        XCTAssertTrue(app.buttons["proposal.approve"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["proposal.approve"].isEnabled)
        let omissions = visibleButton("proposal.screenTime.omissions", in: app)
        omissions.tap()
        for name in ["WhatsApp", "Gmail", "Chess.com", "YouTube"] {
            let retained = app.staticTexts[name]
            scrollTo(retained, identifier: "retained-source-\(name)", in: app)
            XCTAssertTrue(retained.exists)
        }
        attach("automation-learning-many-apps-four-not-chosen-retained-in-sources", app)
        for index in 0..<8 {
            let step = app.descendants(matching: .any).matching(identifier: "proposal.step.\(index)").firstMatch
            scrollTo(step, identifier: "proposal.step.\(index)", in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "proposal.step.8").firstMatch.exists)
        enabledVisibleButton("proposal.source.44444444-4444-4444-8444-444444444444", in: app).tap()
        tapVisible("Texte extrait d’origine", in: app)
        let original = app.staticTexts["observation.originalText"]
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        for name in ["Instagram", "WhatsApp", "Calendrier", "Mail", "Safari", "Météo", "Musique", "Plans", "Rappels", "Gmail", "Chess.com", "YouTube"] {
            XCTAssertTrue(original.label.contains(name), "The complete source must retain \(name).")
        }
        attach("automation-learning-many-apps-complete-original-retained", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        enabledVisibleButton("proposal.edit", in: app).tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
        _ = visibleButton("routine.step.7", in: app)
        XCTAssertFalse(app.buttons["routine.step.8"].exists)
        attach("automation-learning-eight-chosen-apps-unapproved-editable-draft", app)
    }

    func testLearningCombinesExplicitScreenTimeBrowserAndVideoSourcesBeforeDelegation() {
        let app = launch(["--ui-testing-approved", "--ui-testing-learning-source-join", "--ui-testing-evidence-proposals"])
        defer { app.terminate() }
        openScreenTimeObservationChoices(app)
        let ids = ["44444444-4444-4444-8444-444444444444", "66666666-6666-4666-8666-666666666666", "77777777-7777-4777-8777-777777777777"]
        for id in ids {
            let choice = visibleButton("observation.select.\(id)", in: app)
            XCTAssertEqual(choice.value as? String, "Not selected", "Source selection must be explicit.")
            choice.tap()
            XCTAssertEqual(choice.value as? String, "Selected")
        }
        let unselectedID = "observation.select.55555555-5555-4555-8555-555555555555"
        let unselected = app.buttons[unselectedID]
        scrollObservationListTo(unselected, identifier: unselectedID, in: app, towardBeginning: true)
        XCTAssertEqual(unselected.value as? String, "Not selected")
        XCTAssertTrue(app.staticTexts["observations.selectionSummary"].label.contains("3 observations"))
        attach("automation-learning-three-source-types-explicit-selection", app)
        enabledVisibleButton("observations.suggestUpdate", in: app).tap()
        XCTAssertTrue(app.buttons["proposal.approve"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["proposal.fixtureMode"].label.contains("no Apple model call"))
        XCTAssertTrue(app.staticTexts["proposal.sources"].label.contains("3 observations"))
        let expected = [("A morning to review", 3), ("1. Instagram · browsing the feed", 1), ("2. Instagram · browsing stories", 2)]
        for (index, moment) in expected.enumerated() {
            let step = app.descendants(matching: .any).matching(identifier: "proposal.step.\(index)").firstMatch
            scrollTo(step, identifier: "proposal.step.\(index)", in: app)
            XCTAssertEqual(step.value as? String, moment.0)
            XCTAssertTrue(app.staticTexts["\(moment.1) minutes planned"].exists)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "proposal.step.3").firstMatch.exists,
                       "Whole-app Screen Time minutes must not invent a separate activity or split the observed sequence.")
        attach("automation-learning-combined-source-proposal-unapproved", app)
        enabledVisibleButton("proposal.edit", in: app).tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled, "Opening the proposal must not delegate it.")
        _ = visibleButton("routine.step.2", in: app)
        XCTAssertFalse(app.buttons["routine.step.3"].exists)
        attach("automation-learning-combined-source-editable-draft", app)
    }

    func testLearningUnknownScreenTimeWindowStaysVisibleWithoutInventingAnActivity() {
        let app = launch(["--ui-testing-approved", "--ui-testing-learning-source-join", "--ui-testing-evidence-proposals"])
        defer { app.terminate() }
        openScreenTimeObservationChoices(app)
        for id in ["55555555-5555-4555-8555-555555555555", "66666666-6666-4666-8666-666666666666"] {
            enabledVisibleButton("observation.select.\(id)", in: app).tap()
        }
        enabledVisibleButton("observations.suggestUpdate", in: app).tap()
        XCTAssertTrue(app.buttons["proposal.approve"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["proposal.sources"].label.contains("2 observations"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "proposal.step.1").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "proposal.step.2").firstMatch.exists)
        let unknown = visibleButton("proposal.source.55555555-5555-4555-8555-555555555555", in: app)
        XCTAssertTrue(unknown.label.contains("Morning window unknown"), unknown.label)
        XCTAssertTrue(app.buttons["proposal.approve"].isEnabled)
        attach("automation-learning-unknown-screen-time-retained-as-unknown", app)
    }

    func testFrenchLargestOutlookSetupShowsNamedMailboxAndAddsAnUnapprovedDraft() {
        let app = launch(["--ui-testing-outlook-inbox", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openOutlookSetup(app)
        let identity = app.staticTexts["outlook.setup.identity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(identity.label.contains("SYNTHETIC Camille, compte Outlook de préparation du matin avec un nom volontairement très long"))
        XCTAssertTrue(identity.label.contains("camille@synthetic.invalid"))
        _ = visibleButton("outlook.setup.account.0", in: app)
        scrollTo(identity, identifier: "outlook.setup.identity", in: app)
        assertNoOutlookTechnicalDetails(app)
        attach("automation-outlook-french-largest-named-mailbox", app)
        enabledVisibleButton("outlook.setup.add", in: app).tap()
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] %@", "ajouté au brouillon"), object: app.staticTexts["outlook.setup.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["outlook.setup.add"].isEnabled)
        assertNoOutlookTechnicalDetails(app)
        attach("automation-outlook-french-largest-added", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        visibleSettingsButton("setup.routine", in: app).tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("SYNTHETIC Camille"))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("camille@synthetic.invalid"))
        _ = visibleButton("routine.step.0", in: app)
        assertNoOutlookTechnicalDetails(app)
        attach("automation-outlook-unapproved-draft", app)
    }

    func testFrenchLargestOutlookEmptyAccountHasHumanRecovery() {
        let app = launch(["--ui-testing-outlook-inbox", "--ui-testing-outlook-empty-account", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openOutlookSetup(app)
        let empty = app.staticTexts["outlook.setup.emptyAccount"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertTrue(empty.label.contains("Connectez un compte Outlook"))
        XCTAssertFalse(app.staticTexts["outlook.setup.identity"].exists)
        XCTAssertFalse(app.buttons["outlook.setup.add"].exists)
        _ = visibleButton("outlook.setup.manage", in: app)
        assertNoOutlookTechnicalDetails(app)
        attach("automation-outlook-french-largest-empty-account", app)
    }

    func testOutlookObservedOrdinalsChooseOneBodyRepeatWithoutReadAndRefreshPreviews() {
        let app = launchOutlookRuntime(["--ui-testing-outlook-duplicate-headers"])
        defer { app.terminate() }
        let summary = app.staticTexts["outlookInbox.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("Previews only"))
        XCTAssertFalse(app.staticTexts["outlookInbox.bodyText"].exists)
        XCTAssertEqual(outlookReads(app), "Inbox reads: 1 · message reads: 0")
        let first = enabledVisibleButton("outlookInbox.message.0", in: app)
        XCTAssertTrue(first.label.contains("Message 1"))
        XCTAssertTrue(first.label.contains("SYNTHETIC même objet reçu le même jour"))
        XCTAssertNotNil(first.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression))
        let second = enabledVisibleButton("outlookInbox.message.1", in: app)
        XCTAssertTrue(second.label.contains("Message 2"))
        XCTAssertTrue(second.label.contains("SYNTHETIC même objet reçu le même jour"))
        XCTAssertNotEqual(first.label, second.label)
        second.tap()
        let body = app.staticTexts["outlookInbox.bodyText"]
        XCTAssertTrue(body.waitForExistence(timeout: 12))
        XCTAssertTrue(body.label.hasPrefix("SYNTHETIC corps du message 2 choisi."), body.label)
        XCTAssertFalse(body.label.contains("SYNTHETIC aperçu"))
        XCTAssertEqual(outlookReads(app), "Inbox reads: 1 · message reads: 1")
        scrollTo(body, identifier: "outlookInbox.bodyText", in: app)
        attach("automation-outlook-second-observed-message-body", app)
        let original = body.label
        enabledVisibleButton("outlookInbox.repeat", in: app).tap()
        _ = enabledVisibleButton("outlookInbox.refresh", in: app)
        XCTAssertEqual(body.label, original)
        XCTAssertEqual(outlookReads(app), "Inbox reads: 1 · message reads: 1")
        enabledVisibleButton("outlookInbox.refresh", in: app).tap()
        waitForOutlookReads("Inbox reads: 2 · message reads: 1", app)
        XCTAssertTrue(summary.exists)
        XCTAssertFalse(app.staticTexts["outlookInbox.bodyText"].exists)
        XCTAssertFalse(app.scrollViews["outlookInbox.body"].exists)
        assertNoOutlookTechnicalDetails(app)
        attach("automation-outlook-refreshed-previews-synthetic", app)
    }

    func testOutlookRuntimeDistinguishesCompleteEmptyPartialAndPartialEmpty() {
        let cases: [([String], String, String)] = [
            (["--ui-testing-outlook-empty"], "No unread messages were found in the Inbox", "complete-empty"),
            (["--ui-testing-outlook-partial"], "More unread messages remain outside these three previews", "partial"),
            (["--ui-testing-outlook-partial", "--ui-testing-outlook-empty"], "This part contains no messages. This reading is partial", "partial-empty")]
        for (flags, expected, name) in cases {
            let app = launchOutlookRuntime(flags)
            defer { app.terminate() }
            let summary = app.staticTexts["outlookInbox.summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 15))
            XCTAssertTrue(summary.label.contains(expected), summary.label)
            if name != "complete-empty" { XCTAssertFalse(summary.label.contains("No unread messages were found in the Inbox")) }
            if name != "partial" { XCTAssertFalse(app.buttons["outlookInbox.message.0"].exists) }
            XCTAssertFalse(app.staticTexts["outlookInbox.unavailable"].exists)
            XCTAssertEqual(outlookReads(app), "Inbox reads: 1 · message reads: 0")
            assertNoOutlookTechnicalDetails(app)
            attach("automation-outlook-\(name)-synthetic", app)
        }
    }

    func testOutlookMissingBodyDoesNotSubstituteThePreviewAndPauses() {
        let app = launchOutlookRuntime(["--ui-testing-outlook-body-missing"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["outlookInbox.summary"].waitForExistence(timeout: 15))
        enabledVisibleButton("outlookInbox.message.0", in: app).tap()
        let body = app.staticTexts["outlookInbox.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 12))
        XCTAssertTrue(body.label.contains("body is unavailable"), body.label)
        XCTAssertTrue(body.label.contains("preview is not a substitute"))
        XCTAssertFalse(app.staticTexts["outlookInbox.bodyText"].exists)
        XCTAssertTrue(app.staticTexts["outlookInbox.bodyIncomplete"].exists)
        assertPaused(in: app)
        XCTAssertEqual(outlookReads(app), "Inbox reads: 1 · message reads: 1")
        scrollTo(body, identifier: "outlookInbox.body", in: app)
        attach("automation-outlook-missing-body-honest-recovery", app)
    }

    func testOutlookUnavailablePausesAndNextKeepsAnHonestRecap() {
        let app = launchOutlookRuntime(["--ui-testing-outlook-unavailable", "--ui-testing-short-budgets"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["outlookInbox.unavailable"].waitForExistence(timeout: 15))
        let status = app.staticTexts["moment.connectedResult"]
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Your morning is paused"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 8), .completed)
        XCTAssertTrue(status.label.contains("Use the buttons Refresh Outlook"), status.label)
        XCTAssertFalse(status.label.lowercased().contains("say "))
        XCTAssertFalse(app.staticTexts["outlookInbox.summary"].exists)
        assertPaused(in: app)
        XCTAssertEqual(outlookReads(app), "Inbox reads: 1 · message reads: 0")
        _ = enabledVisibleButton("outlookInbox.refresh", in: app)
        attach("automation-outlook-unavailable-recovery-synthetic", app)
        tapVisible("morning.next", in: app)
        waitForCompletion(in: app)
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Unavailable: 1"))
        attach("automation-outlook-unavailable-honest-recap", app)
    }

    func testFrenchLargestCalendlySetupShowsNamedIdentityAndAddsAnUnapprovedDraft() {
        let app = launch(["--ui-testing-calendly-day", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openCalendlySetup(app)
        let identity = app.staticTexts["calendly.setup.identity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertEqual(identity.label, "SYNTHETIC Camille, compte de préparation du matin avec un nom volontairement très long")
        _ = visibleButton("calendly.setup.account.0", in: app)
        assertNoCalendlyTechnicalDetails(app)
        attach("automation-calendly-french-largest-named-identity", app)
        enabledVisibleButton("calendly.setup.add", in: app).tap()
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] %@", "ajouté au brouillon"), object: app.staticTexts["calendly.setup.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["calendly.setup.add"].isEnabled)
        assertNoCalendlyTechnicalDetails(app)
        attach("automation-calendly-french-largest-added", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapVisible("setup.routine", in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("SYNTHETIC Camille"))
        assertNoCalendlyTechnicalDetails(app)
        attach("automation-calendly-unapproved-draft", app)
    }

    func testFrenchLargestCalendlyEmptyAccountHasHumanRecovery() {
        let app = launch(["--ui-testing-calendly-day", "--ui-testing-calendly-empty-account", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openCalendlySetup(app)
        let empty = app.staticTexts["calendly.setup.emptyAccount"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertTrue(empty.label.contains("Connectez un compte Calendly"))
        XCTAssertFalse(app.staticTexts["calendly.setup.identity"].exists)
        XCTAssertFalse(app.buttons["calendly.setup.add"].exists)
        _ = visibleButton("calendly.setup.manage", in: app)
        assertNoCalendlyTechnicalDetails(app)
        attach("automation-calendly-french-largest-empty-account", app)
    }

    func testCalendlyRuntimeRepeatsSameReadingAndRefreshesOnlyWhenRequested() {
        let app = launchCalendlyRuntime()
        defer { app.terminate() }
        let summary = app.staticTexts["calendlyDay.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("3 appointments were read"))
        for name in ["SYNTHETIC début de journée", "SYNTHETIC préparer les priorités du matin", "SYNTHETIC échange de fin de journée"] {
            XCTAssertTrue(summary.label.contains(name), summary.label)
        }
        XCTAssertTrue(summary.label.contains("00:00"))
        XCTAssertTrue(summary.label.contains("phone call"))
        let original = summary.label
        XCTAssertEqual(app.staticTexts["calendlyDay.synthetic"].value as? String, "HTTP event reads: 1")
        enabledVisibleButton("calendlyDay.repeat", in: app).tap()
        XCTAssertEqual(summary.label, original)
        XCTAssertEqual(app.staticTexts["calendlyDay.synthetic"].value as? String, "HTTP event reads: 1")
        enabledVisibleButton("calendlyDay.refresh", in: app).tap()
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "HTTP event reads: 2"), object: app.staticTexts["calendlyDay.synthetic"])
        let result = XCTWaiter.wait(for: [refreshed], timeout: 12)
        if result != .completed { captureFailure("calendly-explicit-refresh-failed", app) }
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(summary.label.contains("3 appointments were read"))
        assertNoCalendlyTechnicalDetails(app)
        attach("automation-calendly-refreshed-explicitly-synthetic", app)
    }

    func testCalendlyRuntimeDistinguishesCompleteEmptyPartialAndPartialEmpty() {
        let cases: [([String], String, String)] = [
            (["--ui-testing-calendly-empty-day"], "No Calendly appointments start today", "complete-empty"),
            (["--ui-testing-calendly-partial"], "This reading is partial", "partial"),
            (["--ui-testing-calendly-partial", "--ui-testing-calendly-empty-day"], "This part contains no appointments for today", "partial-empty")]
        for (flags, expected, name) in cases {
            let app = launchCalendlyRuntime(flags)
            defer { app.terminate() }
            let summary = app.staticTexts["calendlyDay.summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 15))
            XCTAssertTrue(summary.label.contains(expected), summary.label)
            if name != "complete-empty" { XCTAssertFalse(summary.label.contains("No Calendly appointments start today")) }
            XCTAssertFalse(app.staticTexts["calendlyDay.unavailable"].exists)
            attach("automation-calendly-\(name)-synthetic", app)
        }
    }

    func testCalendlyUnavailablePausesAndNextKeepsAnHonestRecap() {
        let app = launchCalendlyRuntime(["--ui-testing-calendly-unavailable", "--ui-testing-short-budgets"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["calendlyDay.unavailable"].waitForExistence(timeout: 15))
        let status = app.staticTexts["moment.connectedResult"]
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Your morning is paused"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 8), .completed)
        XCTAssertTrue(status.label.lowercased().contains("refresh my bookings"))
        XCTAssertFalse(app.staticTexts["calendlyDay.summary"].exists)
        assertPaused(in: app)
        attach("automation-calendly-unavailable-recovery-synthetic", app)
        tapVisible("morning.next", in: app)
        waitForCompletion(in: app)
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Unavailable: 1"))
        attach("automation-calendly-unavailable-honest-recap", app)
    }

    func testGoogleCalendarHomonymsRequireCompleteNamesAndKeepThePrimaryDistinct() {
        let app = launch(["--ui-testing-google-calendar-day", "--ui-testing-google-calendar-homonyms", "--ui-testing-empty-workspace"], french: true)
        defer { app.terminate() }
        openGoogleCalendarSetup(app)
        let primary = visibleButton("googleCalendar.setup.calendar.0", in: app)
        XCTAssertTrue(primary.label.contains("SYNTHETIC calendrier partagé du matin"))
        XCTAssertTrue(primary.label.contains("calendrier principal"))
        let secondary = enabledVisibleButton("googleCalendar.setup.calendar.1", in: app)
        XCTAssertFalse(secondary.label.contains("calendrier principal"))
        secondary.tap()
        _ = visibleButton("googleCalendar.setup.add", in: app)
        XCTAssertFalse(app.buttons["googleCalendar.setup.add"].isEnabled)
        XCTAssertTrue(app.staticTexts["googleCalendar.setup.incompleteNames"].exists)
        tapVisible("googleCalendar.setup.more", in: app)
        let ambiguous = app.staticTexts["googleCalendar.setup.ambiguous"]
        XCTAssertTrue(ambiguous.waitForExistence(timeout: 8))
        XCTAssertTrue(ambiguous.label.contains("Renommez-les"))
        XCTAssertTrue(app.buttons["googleCalendar.setup.calendar.2"].exists)
        XCTAssertFalse(app.buttons["googleCalendar.setup.calendar.1"].isEnabled)
        XCTAssertFalse(app.buttons["googleCalendar.setup.calendar.2"].isEnabled)
        XCTAssertFalse(app.buttons["googleCalendar.setup.add"].exists && app.buttons["googleCalendar.setup.add"].isEnabled)
        assertNoGoogleTechnicalDetails(app)
        attach("automation-google-calendar-ambiguous-secondary-choices-blocked", app)
        enabledVisibleButton("googleCalendar.setup.calendar.0", in: app).tap()
        enabledVisibleButton("googleCalendar.setup.add", in: app).tap()
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Ajouté au brouillon"), object: app.staticTexts["googleCalendar.setup.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 8), .completed)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapVisible("setup.routine", in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("calendrier principal"))
        assertNoGoogleTechnicalDetails(app)
        attach("automation-google-calendar-primary-disambiguated-unapproved-draft", app)
    }

    func testFrenchLargestGoogleCalendarSetupLoadsNamedPagesAndAddsAnUnapprovedDraft() {
        let app = launch(["--ui-testing-google-calendar-day", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openGoogleCalendarSetup(app)
        let first = visibleButton("googleCalendar.setup.calendar.0", in: app)
        XCTAssertTrue(first.label.contains("SYNTHETIC calendrier personnel de préparation du matin avec un nom volontairement très long"))
        XCTAssertFalse(app.buttons["googleCalendar.setup.calendar.1"].exists)
        assertNoGoogleTechnicalDetails(app)
        attach("automation-google-calendar-french-largest-first-page", app)
        tapVisible("googleCalendar.setup.more", in: app)
        let second = visibleButton("googleCalendar.setup.calendar.1", in: app)
        XCTAssertTrue(second.label.contains("SYNTHETIC deuxième page calendrier partagé de préparation du matin"))
        XCTAssertFalse(app.buttons["googleCalendar.setup.calendar.2"].exists)
        XCTAssertFalse(app.buttons["googleCalendar.setup.more"].exists)
        second.tap()
        tapVisible("googleCalendar.setup.add", in: app)
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Ajouté au brouillon"), object: app.staticTexts["googleCalendar.setup.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["googleCalendar.setup.add"].isEnabled)
        assertNoGoogleTechnicalDetails(app)
        attach("automation-google-calendar-french-largest-second-page-added", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapVisible("setup.routine", in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("SYNTHETIC deuxième page calendrier partagé"))
        assertNoGoogleTechnicalDetails(app)
        attach("automation-google-calendar-unapproved-draft", app)
    }

    func testFrenchLargestGoogleCalendarEmptyAccountHasHumanRecovery() {
        let app = launch(["--ui-testing-google-calendar-day", "--ui-testing-google-calendar-empty-account", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openGoogleCalendarSetup(app)
        let empty = app.staticTexts["googleCalendar.setup.emptyAccount"]
        XCTAssertTrue(empty.waitForExistence(timeout: 8))
        XCTAssertTrue(empty.label.contains("Connectez un compte Google Calendar"))
        XCTAssertFalse(app.buttons["googleCalendar.setup.calendar.0"].exists)
        XCTAssertFalse(app.buttons["googleCalendar.setup.add"].exists)
        _ = visibleButton("googleCalendar.setup.manage", in: app)
        assertNoGoogleTechnicalDetails(app)
        attach("automation-google-calendar-french-largest-empty-account", app)
    }

    func testGoogleCalendarRuntimeRepeatsSameReadingAndRefreshesOnlyWhenRequested() {
        let app = launchGoogleCalendarRuntime()
        defer { app.terminate() }
        let summary = app.staticTexts["googleCalendarDay.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("3 events read"))
        XCTAssertTrue(summary.label.contains("All day"))
        XCTAssertTrue(summary.label.contains("SYNTHETIC préparer les priorités du matin"))
        XCTAssertTrue(summary.label.contains("SYNTHETIC échange de préparation de la journée"))
        let original = summary.label
        XCTAssertEqual(app.staticTexts["googleCalendarDay.synthetic"].value as? String, "HTTP event reads: 1")
        enabledVisibleButton("googleCalendarDay.repeat", in: app).tap()
        XCTAssertEqual(summary.label, original)
        XCTAssertEqual(app.staticTexts["googleCalendarDay.synthetic"].value as? String, "HTTP event reads: 1")
        enabledVisibleButton("googleCalendarDay.refresh", in: app).tap()
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "HTTP event reads: 2"), object: app.staticTexts["googleCalendarDay.synthetic"])
        let result = XCTWaiter.wait(for: [refreshed], timeout: 12)
        if result != .completed { captureFailure("google-calendar-explicit-refresh-failed", app) }
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(summary.exists)
        XCTAssertTrue(summary.label.contains("3 events read"))
        attach("automation-google-calendar-refreshed-explicitly-synthetic", app)
    }

    /// Uses real wall time. No clock, provider age or production lifetime is replaced.
    func testGoogleCalendarFreshnessExpiresWithControlsClosedWithoutRefetch() async throws {
        let app = launchGoogleCalendarRuntime()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["googleCalendarDay.summary"].waitForExistence(timeout: 15))
        _ = enabledVisibleButton("googleCalendarDay.refresh", in: app)
        tapVisible("morning.extend", in: app)
        tapVisible("morning.extend", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        XCTAssertGreaterThan(Int(MorningUITestNavigation.sessionSnapshot(in: app)["remaining"] ?? "") ?? 0, 390)
        MorningUITestNavigation.tapButton("run.resume", in: app)
        MorningUITestNavigation.assertSession(state: "running", in: app)
        MorningUITestNavigation.closeMorningActions(in: app)
        XCTAssertFalse(app.staticTexts["googleCalendarDay.summary"].exists)
        attach("automation-google-calendar-running-with-controls-closed", app)
        try await Task.sleep(for: .seconds(320))
        // Inspect the actual session before recreating its reading view.
        MorningUITestNavigation.assertSession(state: "paused", in: app)
        attach("automation-google-calendar-expired-with-controls-closed", app)
        reveal(app)
        assertPaused(in: app)
        XCTAssertTrue(app.staticTexts["moment.connectedResult"].label.contains("expired"))
        XCTAssertFalse(app.staticTexts["googleCalendarDay.summary"].exists)
        XCTAssertEqual(app.staticTexts["googleCalendarDay.synthetic"].value as? String, "HTTP event reads: 1")
        enabledVisibleButton("googleCalendarDay.refresh", in: app).tap()
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "HTTP event reads: 2"), object: app.staticTexts["googleCalendarDay.synthetic"])
        let result = await XCTWaiter.fulfillment(of: [refreshed], timeout: 12)
        if result != .completed { captureFailure("google-calendar-expiration-refresh-failed", app) }
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(app.staticTexts["googleCalendarDay.summary"].exists)
        attach("automation-google-calendar-expiration-explicit-refresh", app)
    }

    func testGoogleCalendarWithoutListeningShowsButtonHelpAndCanRepeatTheReading() {
        let app = launchGoogleCalendarRuntime(["--ui-testing-voice-preparation"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["voice.access.status"].waitForExistence(timeout: 8))
        tapVisible("voice.access.withoutListening", in: app)
        openCurrentMoment(in: app)
        let summary = app.staticTexts["googleCalendarDay.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let original = summary.label
        let hint = app.staticTexts["googleCalendarDay.controlsHint"]
        XCTAssertTrue(hint.label.contains("Use the buttons"))
        XCTAssertFalse(hint.label.lowercased().contains("say "))
        XCTAssertFalse(hint.label.contains("Ask a question"))
        XCTAssertTrue(app.staticTexts["morning.voiceStatus"].label.contains("Listening is off for this morning"))
        enabledVisibleButton("googleCalendarDay.repeat", in: app).tap()
        XCTAssertEqual(summary.label, original)
        XCTAssertEqual(app.staticTexts["googleCalendarDay.synthetic"].value as? String, "HTTP event reads: 1")
        let repeatButton = enabledVisibleButton("googleCalendarDay.repeat", in: app)
        // Inspect the settled layout after the reading state transition/scroll.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertLessThanOrEqual(hint.frame.maxY, repeatButton.frame.minY + 1,
                                 "The complete button-help caption must clear the next control.")
        attach("automation-google-calendar-without-listening-button-help", app)
    }

    func testGoogleCalendarUnavailableWithoutListeningOffersButtonRecovery() {
        let app = launchGoogleCalendarRuntime(["--ui-testing-voice-preparation", "--ui-testing-google-calendar-unavailable"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["voice.access.status"].waitForExistence(timeout: 8))
        tapVisible("voice.access.withoutListening", in: app)
        openCurrentMoment(in: app)
        XCTAssertTrue(app.staticTexts["googleCalendarDay.unavailable"].waitForExistence(timeout: 15))
        let status = app.staticTexts["moment.connectedResult"]
        XCTAssertTrue(status.label.contains("Your morning is paused"))
        XCTAssertTrue(status.label.lowercased().contains("refresh"))
        XCTAssertFalse(status.label.lowercased().contains("say "))
        XCTAssertFalse(app.staticTexts["googleCalendarDay.unavailable"].label.lowercased().contains("say "))
        XCTAssertTrue(app.staticTexts["morning.voiceStatus"].label.contains("Listening is off for this morning"))
        _ = enabledVisibleButton("googleCalendarDay.refresh", in: app)
        attach("automation-google-calendar-without-listening-button-recovery", app)
    }

    func testGoogleCalendarRuntimeDistinguishesCompleteEmptyPartialAndPartialEmpty() {
        let cases: [([String], String, String)] = [
            (["--ui-testing-google-calendar-empty-day"], "No events scheduled in this calendar today", "complete-empty"),
            (["--ui-testing-google-calendar-partial"], "Partial reading: more events may follow", "partial"),
            (["--ui-testing-google-calendar-partial", "--ui-testing-google-calendar-empty-day"], "No events in this part of the reading", "partial-empty")]
        for (flags, expected, name) in cases {
            let app = launchGoogleCalendarRuntime(flags)
            defer { app.terminate() }
            let summary = app.staticTexts["googleCalendarDay.summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 15))
            XCTAssertTrue(summary.label.contains(expected), summary.label)
            if name != "complete-empty" { XCTAssertFalse(summary.label.contains("No events scheduled in this calendar today")) }
            XCTAssertFalse(app.staticTexts["googleCalendarDay.unavailable"].exists)
            attach("automation-google-calendar-\(name)-synthetic", app)
        }
    }

    func testGoogleCalendarUnavailablePausesAndNextKeepsAnHonestRecap() {
        let app = launchGoogleCalendarRuntime(["--ui-testing-google-calendar-unavailable", "--ui-testing-short-budgets"])
        defer { app.terminate() }
        let unavailable = app.staticTexts["googleCalendarDay.unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15))
        let status = app.staticTexts["moment.connectedResult"]
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Your morning is paused"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 8), .completed)
        XCTAssertTrue(status.label.lowercased().contains("refresh this calendar"))
        XCTAssertFalse(app.staticTexts["googleCalendarDay.summary"].exists)
        assertPaused(in: app)
        attach("automation-google-calendar-unavailable-recovery-synthetic", app)
        tapVisible("morning.next", in: app)
        waitForCompletion(in: app)
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Unavailable: 1"))
        attach("automation-google-calendar-unavailable-honest-recap", app)
    }

    func testEachNewMorningReviewsReadingConsentButSameSessionCanResume() {
        for french in [true, false] {
            let app = launch(["--ui-testing-automation", "--ui-testing-approved", "--ui-testing-read-aloud",
                              "--ui-testing-natural-voice-consent"], french: french)
            defer { app.terminate() }
            reveal(app)
            app.buttons["morning.begin"].tap()
            let consent = app.staticTexts["voice.readingConsent"]
            XCTAssertTrue(consent.waitForExistence(timeout: 8))
            XCTAssertTrue(consent.label.contains(french ? "traités en ligne" : "processed online"))
            XCTAssertFalse(app.buttons["morning.playback"].exists)
            XCTAssertEqual(app.alerts.count, 0, "Reading consent must not request microphone access.")
            attach(french ? "voice-reading-consent-first-morning-fr" : "voice-reading-consent-first-morning-en", app)
            tapVisible("voice.access.withoutOnlineVoice", in: app)

            let captions = app.scrollViews["morning.captions"]
            XCTAssertTrue(captions.waitForExistence(timeout: 10))
            let identity = captions.value as? String
            let identifiers = identity?.components(separatedBy: "|") ?? []
            XCTAssertEqual(identifiers.count, 2)
            XCTAssertTrue(identifiers.allSatisfy { UUID(uuidString: $0) != nil })
            func playback() -> XCUIElement {
                let control = app.buttons["morning.playback"]
                if !control.exists || !control.isHittable { captions.tap() }
                XCTAssertTrue(control.waitForExistence(timeout: 5))
                XCTAssertTrue(control.isHittable)
                return control
            }
            let control = playback()
            // The opening's Continue starts the first timed moment when needed.
            if control.label != "Pause" { control.tap() }
            let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 10), .completed)
            playback().tap()
            XCTAssertEqual(playback().label, french ? "Continuer" : "Continue")
            playback().tap()
            XCTAssertFalse(consent.waitForExistence(timeout: 1), "Resuming the same morning retains its reading decision.")
            XCTAssertEqual(captions.value as? String, identity, "Resume must preserve the session and current moment.")

            let settings = app.buttons["morning.settings"]
            // Floating controls disappear after five seconds. Reveal them on
            // the landscape rather than scrolling the current caption.
            if !settings.exists || !settings.isHittable { captions.tap() }
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertTrue(settings.isHittable)
            settings.tap()
            tapVisible("morning.stop", in: app)
            XCTAssertTrue(app.buttons["morning.stop"].waitForNonExistence(timeout: 5))
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.exists); back.tap()
            reveal(app)
            XCTAssertTrue(app.buttons["morning.begin"].waitForExistence(timeout: 5))
            app.buttons["morning.begin"].tap()
            XCTAssertTrue(consent.waitForExistence(timeout: 8),
                          "A stopped morning's decision cannot authorize a new morning.")
            XCTAssertTrue(app.buttons["voice.access.withoutOnlineVoice"].exists)
            XCTAssertFalse(app.buttons["morning.playback"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            attach(french ? "voice-reading-consent-new-after-stop-fr" : "voice-reading-consent-new-after-stop-en", app)
            app.terminate()
        }
    }

    func testVoicePreparationCanStartWithoutListeningAndDoesNotReopenAfterForeground() {
        let app = launch(["--ui-testing-automation", "--ui-testing-approved", "--ui-testing-hands-free", "--ui-testing-voice-preparation"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.staticTexts["voice.access.status"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["voice.access.synthetic"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists, "The first moment must not start underneath permission preparation.")
        tapVisible("voice.access.withoutListening", in: app)
        reveal(app)
        XCTAssertTrue(app.buttons["morning.playback"].waitForExistence(timeout: 8))
        openCurrentMoment(in: app)
        XCTAssertTrue(app.staticTexts["morning.voiceStatus"].label.contains("Listening is off for this morning"))
        XCTAssertFalse(app.staticTexts["voice.access.status"].exists)
        XCUIDevice.shared.press(.home); app.activate(); openCurrentMoment(in: app)
        XCTAssertFalse(app.staticTexts["voice.access.status"].exists)
        XCTAssertTrue(app.staticTexts["morning.voiceStatus"].label.contains("Listening is off for this morning"))
        app.terminate(); app.launch(); openCurrentMoment(in: app)
        XCTAssertFalse(app.staticTexts["voice.access.status"].exists)
        XCTAssertTrue(app.staticTexts["morning.voiceStatus"].label.contains("Listening is off for this morning"), "The same restored session must keep the owner's choice not to listen.")
        attach("automation-voice-preparation-explicit-without-listening", app)
    }

    func testBackgroundCancelsVoicePreparationWithoutStartingTheMorning() {
        let app = launch(["--ui-testing-automation", "--ui-testing-approved", "--ui-testing-hands-free", "--ui-testing-voice-preparation"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.staticTexts["voice.access.status"].waitForExistence(timeout: 8))
        attach("automation-voice-preparation-before-any-session", app)
        XCUIDevice.shared.press(.home); app.activate(); reveal(app)
        XCTAssertTrue(app.buttons["morning.begin"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        XCTAssertFalse(app.staticTexts["voice.access.status"].exists)
    }

    func testFrenchLargestSlackSetupLoadsNamedPagesAndAddsAnUnapprovedDraft() {
        let app = launch(["--ui-testing-slack-setup", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openSlackSetup(app)
        let first = visibleButton("slack.setup.channel.0", in: app)
        XCTAssertTrue(first.label.contains("SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"))
        XCTAssertFalse(app.buttons["slack.setup.channel.1"].exists, "Archived, nonmember and read-only channels must be excluded.")
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(labels.contains("SYNTHETIC équipe du matin avec un nom volontairement très long"))
        XCTAssertTrue(labels.contains("SYNTHETIC Camille propriétaire du compte de démonstration"))
        assertNoSlackTechnicalDetails(app)
        attach("automation-slack-setup-french-largest-first-page", app)
        tapVisible("slack.setup.more", in: app)
        let second = visibleButton("slack.setup.channel.1", in: app)
        XCTAssertTrue(second.label.contains("SYNTHETIC-seconde-page-canal-membre"))
        XCTAssertFalse(app.buttons["slack.setup.channel.2"].exists)
        XCTAssertFalse(app.buttons["slack.setup.more"].exists)
        second.tap()
        attach("automation-slack-setup-french-largest-second-page", app)
        tapVisible("slack.setup.add", in: app)
        let status = app.staticTexts["slack.setup.status"]
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Ajouté au brouillon"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["slack.setup.add"].isEnabled)
        assertNoSlackTechnicalDetails(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapVisible("setup.routine", in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled, "Adding a Slack moment creates an unapproved routine for the owner to review.")
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("SYNTHETIC-seconde-page-canal-membre"))
        assertNoSlackTechnicalDetails(app)
        attach("automation-slack-added-unapproved-draft", app)
    }

    func testFrenchLargestSlackSetupEmptyAccountHasAHumanRecovery() {
        let app = launch(["--ui-testing-slack-setup", "--ui-testing-slack-empty", "--ui-testing-empty-workspace",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openSlackSetup(app)
        let empty = app.staticTexts["slack.setup.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 8))
        XCTAssertTrue(empty.label.contains("Connectez un compte Slack"))
        XCTAssertFalse(app.buttons["slack.setup.channel.0"].exists)
        XCTAssertFalse(app.buttons["slack.setup.add"].exists)
        XCTAssertFalse(app.buttons["slack.setup.account.0"].exists)
        _ = visibleButton("slack.setup.manage", in: app)
        assertNoSlackTechnicalDetails(app)
        attach("automation-slack-setup-french-largest-empty-account", app)
    }

    func testFrenchLargestSlackReplyRequiresReviewAndClearsPrivateTextOnBackground() {
        let app = launch(["--ui-testing-slack-reply", "--ui-testing-approved", "--ui-testing-hands-free",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        openCurrentMoment(in: app)
        tapVisible("slackMoment.message.0", in: app)
        XCTAssertTrue(app.staticTexts["slackMoment.synthetic"].exists)
        let intention = app.descendants(matching: .any).matching(identifier: "slackMoment.intention").firstMatch
        scrollTo(intention, identifier: "slackMoment.intention", in: app)
        intention.tap(); intention.typeText("Merci pour le message")
        tapVisible("slackMoment.prepare", in: app)
        let destination = app.staticTexts["slackMoment.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10))
        XCTAssertTrue(destination.label.contains("SYNTHETIC workspace"))
        XCTAssertTrue(destination.label.contains("SYNTHETIC account"))
        XCTAssertTrue(destination.label.contains("#synthetic-qa"))
        let body = app.descendants(matching: .any).matching(identifier: "slackMoment.body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 8))
        scrollTo(body, identifier: "slackMoment.body", in: app)
        body.tap(); body.typeText("Merci, je relis cela ce matin.")
        tapVisible("slackMoment.review", in: app)
        let send = app.buttons["slackMoment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 8))
        XCTAssertFalse(send.isEnabled, "Interrupted synthetic speech requires a complete screen review, never a fabricated acoustic pass.")
        tapVisible("slackMoment.reviewed", in: app)
        XCTAssertTrue(send.isEnabled)
        attach("automation-slack-french-largest-reviewed-synthetic", app)
        tapVisible("slackMoment.send", in: app)
        let status = app.staticTexts["slackMoment.status"]
        let posted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "publiée", "synthetic-qa"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [posted], timeout: 8), .completed)
        XCTAssertFalse(send.exists)
        attach("automation-slack-synthetic-confirmed-once", app)
        XCUIDevice.shared.press(.home); app.activate(); reveal(app)
        XCTAssertFalse(app.staticTexts["slackMoment.destination"].exists)
        XCTAssertFalse(app.staticTexts["slackMoment.source"].exists)
        XCTAssertFalse(app.staticTexts["slackMoment.status"].exists)
        XCTAssertFalse(app.buttons["slackMoment.send"].exists)
        XCTAssertTrue(app.staticTexts["slackMoment.empty"].exists)
    }

    func testNativeCorrectionIsReachableInsideLiveBrowserWithoutLosingTheMoment() {
        let app = launch(["--ui-testing-public-feed", "--ui-testing-native-actions", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 20))
        let status = app.staticTexts["web.result"]
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*· ([2-9]|[1-9][0-9]+) contents viewed.*"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 40), .completed)
        app.buttons["web.extend"].tap()
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let count = observedContents(status.label)
        let viewport = browserDiagnostic(status, key: "viewportY")
        let source = browserDiagnostic(status, key: "sourceIdentity")
        let remaining = app.staticTexts["web.remaining"].label
        app.buttons["web.nativeRequest"].tap()
        let request = app.descendants(matching: .any).matching(identifier: "nativeMoment.request").firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 8))
        request.tap(); request.typeText("Calendar: synthetic coffee Friday at ten")
        tapVisible("nativeMoment.prepare", in: app)
        XCTAssertTrue(app.staticTexts["nativeMoment.synthetic"].exists)
        let titles = app.descendants(matching: .any).matching(identifier: "nativeMoment.title")
        XCTAssertEqual(titles.count, 1, "The visible browser panel must own the only current native editor.")
        let title = titles.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        for _ in 0..<6 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable, title.debugDescription)
        title.tap(); title.typeText(" corrected")
        XCTAssertTrue(app.buttons["nativeMoment.editReview"].exists)
        XCTAssertFalse(app.buttons["nativeMoment.confirm"].exists, "An unsupported date must require details; it cannot prepare an Apple write.")
        attach("automation-native-date-correction-inside-live-browser", app)
        app.buttons["web.nativeClose"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        XCTAssertEqual(observedContents(status.label), count)
        XCTAssertLessThanOrEqual(abs(browserDiagnostic(status, key: "viewportY") - viewport), 2)
        XCTAssertEqual(browserDiagnostic(status, key: "sourceIdentity"), source)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        attach("automation-native-correction-closed-same-browser-moment", app)
        app.buttons["web.resume"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 5))
    }

    func testNativeRequestReviewAndBackgroundPrivacyUseExplicitSyntheticProvider() {
        let app = launch(["--ui-testing-native-actions", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        openCurrentMoment(in: app)
        tapVisible("nativeMoment.open", in: app)
        let request = app.descendants(matching: .any).matching(identifier: "nativeMoment.request").firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 8))
        request.tap(); request.typeText("Private unsubmitted synthetic request")
        XCUIDevice.shared.press(.home)
        app.activate()
        openCurrentMoment(in: app)
        tapVisible("nativeMoment.open", in: app)
        XCTAssertFalse((request.value as? String ?? "").contains("Private unsubmitted"), "Backgrounding must clear even an unsubmitted native request.")
        request.tap(); request.typeText("Reminder: water plants no date")
        tapVisible("nativeMoment.prepare", in: app)
        let confirm = app.buttons["nativeMoment.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["nativeMoment.synthetic"].label.contains("SYNTHETIC"))
        XCTAssertFalse(confirm.isEnabled, "Interrupted spoken review must require explicit screen review before writing.")
        tapVisible("nativeMoment.reviewed", in: app)
        tapVisible("nativeMoment.confirm", in: app)
        let status = app.staticTexts["nativeMoment.status"]
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@", "was added", "water plants", "SYNTHETIC"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 8), .completed)
        XCTAssertFalse(confirm.exists)
        attach("automation-synthetic-native-addition-confirmed", app)
        tapVisible("nativeMoment.cancel", in: app)
        tapVisible("nativeMoment.open", in: app)
        request.tap(); request.typeText("read my reminders")
        tapVisible("nativeMoment.prepare", in: app)
        tapVisible("nativeMoment.reminder.0", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertFalse(confirm.isEnabled)
        tapVisible("nativeMoment.reviewed", in: app)
        tapVisible("nativeMoment.confirm", in: app)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "marked complete", "SYNTHETIC appeler le garage"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 8), .completed)
        XCTAssertFalse(confirm.exists)
        attach("automation-synthetic-observed-reminder-completed", app)
    }

    func testLearnedSuggestionCanBeEditedBeforeDelegationAndRestoresPreviousRoutine() {
        let app = launch(["--ui-testing-approved", "--ui-testing-observation-archive", "--ui-testing-evidence-proposals"])
        defer { app.terminate() }
        MorningUITestNavigation.openRoutine(in: app)
        tapVisible("learn.refine", in: app)
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 8))
        tapVisible("learn.savedObservations", in: app)
        XCTAssertTrue(app.buttons["observations.choose"].waitForExistence(timeout: 8))
        app.buttons["observations.choose"].tap()
        tapVisible("observation.select.11111111-1111-4111-8111-111111111111", in: app)
        tapVisible("observation.select.22222222-2222-4222-8222-222222222222", in: app)
        tapVisible("observations.suggestUpdate", in: app)
        XCTAssertTrue(app.buttons["proposal.edit"].waitForExistence(timeout: 15))
        let reason = app.buttons["Why this suggestion?"]
        for _ in 0..<8 where !reason.exists || !reason.isHittable { app.swipeUp() }
        reason.tap()
        let source = "Edited sample A: calendar, water, chess and tea."
        let quote = app.staticTexts["“\(source)”"]
        for _ in 0..<8 where !quote.exists || !quote.isHittable { app.swipeUp() }
        XCTAssertTrue(quote.exists)
        XCTAssertTrue(app.staticTexts["proposal.sources"].label.contains("2 observations"))
        attach("automation-learned-suggestion-before-edit", app)
        app.buttons["proposal.edit"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        XCTAssertTrue(app.buttons["routine.restore"].exists)
        app.buttons["routine.step.0"].tap()
        XCTAssertTrue(app.buttons["step.save"].waitForExistence(timeout: 8))
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step details")).firstMatch
        XCTAssertTrue((details.value as? String ?? "").contains(source), "Adopting an editable draft must retain the exact source quotation.")
        let duration = app.steppers["step.duration"]
        let increment = duration.buttons["step.duration-Increment"]
        for _ in 0..<8 where !increment.exists || !increment.isHittable { app.swipeUp() }
        increment.tap()
        XCTAssertEqual(duration.value as? String, "4")
        app.buttons["step.save"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("4 min"))
        attach("automation-learned-edited-draft-awaiting-delegation", app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-approved" || $0 == "--ui-testing-observation-archive" }
        app.launch()
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8), "Editing must persist a draft without silently delegating it.")
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("4 min"))
        tapVisible("routine.restore", in: app)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertTrue(app.buttons["routine.step.3"].exists, "The previous approved routine must remain recoverable.")
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("Your morning"))
        attach("automation-learned-draft-previous-approved-restored", app)
    }

    func testUnavailableCalendarPausesWithVisibleRecoveryAndNextPreservesTruth() {
        let app = launch(["--ui-testing-native-unavailable", "--ui-testing-approved", "--ui-testing-hands-free", "--ui-testing-read-aloud", "--ui-testing-short-budgets", "--ui-testing-voice-preparation"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.staticTexts["voice.access.status"].waitForExistence(timeout: 8))
        tapVisible("voice.access.withoutListening", in: app)
        openCurrentMoment(in: app)
        let status = app.staticTexts["moment.connectedResult"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertTrue(status.label.contains("Your day is not ready"), status.label)
        XCTAssertTrue(status.label.contains("Your morning is paused"), status.label)
        XCTAssertTrue(status.label.contains("Update this recap"), status.label)
        XCTAssertFalse(status.label.lowercased().contains("say "), status.label)
        XCTAssertTrue(app.staticTexts["morning.voiceStatus"].label.contains("Listening is off for this morning"))
        enabledVisibleButton("briefing.updateCurrent", in: app).tap()
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertTrue(status.label.contains("Your day is not ready"), status.label)
        XCTAssertTrue(status.label.contains("Your morning is paused"), status.label)
        XCTAssertFalse(status.label.lowercased().contains("say "), status.label)
        assertPaused(in: app)
        XCTAssertTrue(currentStepTitle(in: app).contains("Calendar unavailable"))
        attach("automation-unavailable-calendar-recovery", app)
        tapVisible("morning.next", in: app)
        waitForCompletion(in: app)
        let recap = app.staticTexts["morning.executionSummary"].label
        XCTAssertTrue(recap.contains("Unavailable: 1"), recap)
        XCTAssertTrue(recap.contains("Timed moments finished: 1"), recap)
        XCTAssertFalse(recap.contains("Verified operations: 2"), recap)
        XCTAssertFalse(status.exists)
        attach("automation-unavailable-calendar-honest-recap", app)
    }

    func testFrenchLargestTextKeepsLearnedProposalActionsReachable() {
        let app = launch(["--ui-testing-approved", "--ui-testing-observation-archive", "--ui-testing-evidence-proposals",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        MorningUITestNavigation.openRoutine(in: app)
        tapVisible("learn.refine", in: app)
        tapVisible("learn.savedObservations", in: app)
        XCTAssertTrue(app.buttons["observations.choose"].waitForExistence(timeout: 8))
        app.buttons["observations.choose"].tap()
        tapVisible("observation.select.11111111-1111-4111-8111-111111111111", in: app)
        attach("automation-french-largest-saved-source-selected", app)
        tapVisible("observations.suggestUpdate", in: app)
        XCTAssertTrue(app.buttons["proposal.approve"].waitForExistence(timeout: 15))
        let keep = fullyVisibleProposalButton("proposal.keepCurrent", in: app)
        XCTAssertTrue(keep.isHittable)
        attach("automation-french-largest-keep-current", app)
        let edit = fullyVisibleProposalButton("proposal.edit", in: app)
        attach("automation-french-largest-learned-proposal-actions", app)
        XCTAssertTrue(edit.isHittable)
        XCTAssertTrue(app.buttons["proposal.approve"].isHittable)
        edit.tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isHittable)
        attach("automation-french-largest-learned-draft-editor", app)
    }

    func testFrenchLargestTextKeepsDelegationAndApprovalReachable() {
        let app = launch(["--ui-testing-automation", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 8))
        XCTAssertTrue(approve.isHittable)
        let step = app.buttons["routine.step.0"]
        // XCTest considers a partly visible cell hittable even when its centre
        // falls under the pinned approval button. Bring the whole row into view.
        for _ in 0..<10 where !step.isHittable || step.frame.maxY > approve.frame.minY { app.swipeUp() }
        XCTAssertTrue(step.isHittable)
        XCTAssertLessThan(step.frame.midY, approve.frame.minY)
        XCTAssertTrue(step.label.contains("1 min"))
        attach("automation-french-largest-review", app)
        step.tap()
        let save = app.buttons["step.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isHittable)
        let duration = app.steppers["step.duration"]
        // The Stepper is a composite accessibility element; its native +/-
        // buttons are the touch targets, even while the parent is nonhittable.
        let increment = duration.buttons["step.duration-Increment"]
        for _ in 0..<8 {
            if increment.exists && increment.isHittable { break }
            app.swipeUp()
        }
        attach("automation-french-largest-edit", app)
        guard increment.exists && increment.isHittable else {
            XCTFail("The native duration increment must remain reachable at the largest text size.")
            return
        }
        increment.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2"), object: duration)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(approve.waitForExistence(timeout: 8))
        XCTAssertTrue(approve.isHittable)
        XCTAssertTrue(step.label.contains("2 min"), "The edited duration must be saved in the reviewed routine.")
        attach("automation-french-largest-saved", app)
    }
    func testDraftRequiresExplicitDelegationBeforeStart() {
        let app = launch(["--ui-testing-automation"], french: true)
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["routine.delegation"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("automation-french-review-before-start", app)
        app.buttons["routine.approve"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.begin"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("automation-approved-awaiting-start", app)
    }

    func testTimedRoutineContinuesWithoutNextAndKeepsHonestRecap() {
        let app = launch(["--ui-testing-automation", "--ui-testing-approved", "--ui-testing-hands-free", "--ui-testing-short-budgets"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        waitForCompletion(in: app)
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Timed moments finished: 2"))
        XCTAssertFalse(app.staticTexts["morning.executionSummary"].label.contains("likes"))
        attach("automation-finished-without-next", app)
        app.terminate(); app.launch(); reveal(app)
        waitForCompletion(in: app, timeout: 8)
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Timed moments finished: 2"))
        attach("automation-persisted-recap", app)
    }

    func testPublicNewsObservedArticleReturnsToHeadlinesAndKeepsItsBudget() throws {
        let app = launch(["--ui-testing-live-news", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.close"].waitForExistence(timeout: 20))
        let first = app.buttons["web.article.1"]
        guard first.waitForExistence(timeout: 35) else {
            let state = browserDiagnosticValue(app.staticTexts["web.result"], key: "pageState")
            let refusal = browserDiagnosticValue(app.staticTexts["web.result"], key: "articleRefusal")
            let pageRefusal = browserDiagnosticValue(app.staticTexts["web.result"], key: "pageAccessRefusal")
            captureFailure("automation-live-news-no-observed-public-link", app)
            let observedConsentWall = state == "needsChoice" && pageRefusal == "consentRequired"
            if state == "needsSignIn" || observedConsentWall || refusal == "signInRequired" || refusal == "consentRequired" {
                throw XCTSkip("The live worker observed a verified access block (pageState=\(state ?? "missing"), pageAccessRefusal=\(pageRefusal ?? "missing"), articleRefusal=\(refusal ?? "missing")). The wall is observed; no article was read and no reading or return journey is claimed.")
            }
            XCTFail("No observed article choice was exposed without a verified access block. pageState=\(state ?? "missing"), pageAccessRefusal=\(pageRefusal ?? "missing"), articleRefusal=\(refusal ?? "missing"). Unclassified choices, loading, HTTP, layout or extraction errors must not become an access skip.")
            return
        }
        XCTAssertTrue(first.label.hasPrefix("1. "))
        let observedTitle = String(first.label.dropFirst(3))
        XCTAssertFalse(observedTitle.isEmpty)
        if app.buttons["web.extend"].isEnabled { app.buttons["web.extend"].tap() }
        attach("automation-live-news-observed-numbered-choice", app)
        enabledVisibleButton("web.article.1", in: app).tap()
        let readAgain = app.buttons["web.articleRepeat"]
        guard readAgain.waitForExistence(timeout: 30) else {
            let refusal = browserDiagnosticValue(app.staticTexts["web.result"], key: "articleRefusal")
            captureFailure("automation-live-news-observed-article-body-unavailable", app)
            if refusal == "signInRequired" || refusal == "consentRequired" {
                throw XCTSkip("The selected article has an observed access block (articleRefusal=\(refusal ?? "missing")). No article body or acoustic reading is claimed.")
            }
            XCTFail("The selected article did not become readable. articleRefusal=\(refusal ?? "missing"). Missing body, script, navigation, HTTP or destination errors must fail this journey.")
            return
        }
        XCTAssertTrue(app.buttons["web.articleReturn"].isHittable)
        XCTAssertTrue(app.buttons["web.resume"].exists, "Selecting an article must pause the existing morning.")
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.lemonde.fr")
        XCTAssertTrue(app.staticTexts["web.result"].label.contains("Article opened in MORE"))
        // Read again is exposed only after a matching successful page response
        // and bounded rendered article paragraphs, rather than a title alone.
        let bodyText = app.webViews.staticTexts.allElementsBoundByIndex.map(\.label).filter {
            $0.count > 80 && !$0.contains(observedTitle) && !$0.hasPrefix("1. ")
        }
        XCTAssertFalse(bodyText.isEmpty, "The selected article must also render readable body text in its visible browser.")
        let pausedBudget = app.staticTexts["web.remaining"].label
        attach("automation-live-news-observed-article-readable-body", app)
        readAgain.tap()
        enabledVisibleButton("web.articleReturn", in: app).tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["web.articleReturn"])
        let result = XCTWaiter.wait(for: [returned], timeout: 25)
        if result != .completed { captureFailure("automation-live-news-return-to-headlines-failed", app) }
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(app.buttons["web.article.1"].waitForExistence(timeout: 10))
        XCTAssertFalse(readAgain.exists)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, pausedBudget,
                       "Article selection, repeat and return must preserve the same paused budget.")
        attach("automation-live-news-returned-to-observed-headlines", app)
        enabledVisibleButton("web.resume", in: app).tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 5))
        let resumedBudget = remainingSeconds(app.staticTexts["web.remaining"].label)
        let savedBudget = remainingSeconds(pausedBudget)
        XCTAssertLessThanOrEqual(resumedBudget, savedBudget)
        XCTAssertGreaterThanOrEqual(resumedBudget, savedBudget - 5)
        attach("automation-live-news-same-budget-resumed", app)
    }

    func testNewsPrivacyWallPausesWithoutPretendingContentWasRead() {
        let app = launch(["--ui-testing-live-news", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 35))
        let status = app.staticTexts["web.result"]
        XCTAssertTrue(status.label.contains("privacy"), status.label)
        let remaining = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        attach("automation-real-news-privacy-choice", app)
        app.buttons["web.close"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.playback"].exists)
        XCTAssertTrue(currentStepTitle(in: app).contains("Le Monde"))
        attach("automation-blocked-moment-preserved", app)
    }

    func testPublicFeedBrowsesAndPauseResumesSameMoment() {
        let app = launch(["--ui-testing-public-feed", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 20))
        let status = app.staticTexts["web.result"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*· ([2-9]|[1-9][0-9]+) contents viewed.*"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 40), .completed)
        attach("automation-real-public-feed", app)
        let beforeExtension = remainingSeconds(app.staticTexts["web.remaining"].label)
        app.buttons["web.extend"].tap()
        XCTAssertGreaterThan(remainingSeconds(app.staticTexts["web.remaining"].label), beforeExtension + 110)
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let remaining = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        attach("automation-real-public-feed-paused", app)
        app.buttons["web.resume"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        attach("automation-real-public-feed-resumed", app)
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let countBeforeClosing = observedContents(status.label)
        XCTAssertGreaterThanOrEqual(countBeforeClosing, 2)
        let positionBeforeClosing = browserDiagnostic(status, key: "viewportY")
        let sourceBeforeClosing = browserDiagnostic(status, key: "sourceIdentity")
        XCTAssertGreaterThan(positionBeforeClosing, 0)
        XCTAssertGreaterThan(browserDiagnostic(status, key: "sourceItems"), 0)
        attach("automation-real-public-feed-before-close", app)
        app.buttons["web.close"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.playback"].exists)
        app.buttons["morning.playback"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        XCTAssertEqual(observedContents(app.staticTexts["web.result"].label), countBeforeClosing)
        // Freeze this exact restored viewport before the next legitimate dwell/
        // advance, so accessibility-query latency cannot race the next content.
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        XCTAssertEqual(observedContents(status.label), countBeforeClosing)
        XCTAssertLessThanOrEqual(abs(browserDiagnostic(status, key: "viewportY") - positionBeforeClosing), 2)
        XCTAssertEqual(browserDiagnostic(status, key: "sourceIdentity"), sourceBeforeClosing)
        XCTAssertGreaterThan(browserDiagnostic(status, key: "sourceItems"), 0)
        attach("automation-real-public-feed-reopened", app)
    }

    /// Real public Reddit; a cold process restores progress, not the live document.
    func testPublicFeedColdRelaunchKeepsItsMorningAndDeduplicatesKnownContent() throws {
        let app = launch(["--ui-testing-public-feed", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 20))
        let result = app.staticTexts["web.result"]
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*· ([2-9]|[1-9][0-9]+) contents viewed.*"), object: result)
        let ready = XCTWaiter.wait(for: [observed], timeout: 45)
        if ready != .completed { captureFailure("public-feed-cold-before-no-content", app) }
        XCTAssertEqual(ready, .completed)
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let savedCount = observedContents(result.label)
        let remaining = app.staticTexts["web.remaining"].label
        let workspace = try XCTUnwrap(app.launchArguments.first { $0.hasPrefix("--ui-testing-workspace=") }
            .map { String($0.dropFirst("--ui-testing-workspace=".count)) })
        attach("automation-real-public-feed-before-cold-relaunch", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["qa.testWorkspace"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["qa.testWorkspace"].value as? String, workspace)
        revealHomeControls(app)
        XCTAssertFalse(app.buttons["morning.begin"].exists)
        MorningUITestNavigation.assertSession(state: "paused", in: app)
        XCTAssertTrue(currentStepTitle(in: app).contains("Reddit"))
        XCTAssertEqual(Int(MorningUITestNavigation.sessionSnapshot(in: app)["remaining"] ?? ""), remainingSeconds(remaining),
                       "Cold restoration must keep this paused morning's remaining budget.")
        attach("automation-real-public-feed-cold-morning-restored", app)
        // Home deliberately has no title or timer. Open the same paused page
        // through Settings to inspect the retained budget before resume.
        tapHomeSettings(app)
        enabledVisibleButton("stepTimer.openPage", in: app).tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining,
                       "Cold restoration must keep this paused morning's remaining budget.")
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        attach("automation-real-public-feed-cold-page-paused-budget-restored", app)
        app.buttons["web.resume"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 15))
        let firstObservation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (result.value as? String)?.contains("newContent=") == true
        }, object: result)
        let received = XCTWaiter.wait(for: [firstObservation], timeout: 30)
        if received != .completed { captureFailure("public-feed-cold-observation-unavailable", app) }
        XCTAssertEqual(received, .completed)
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        let restoredCount = observedContents(result.label)
        XCTAssertGreaterThanOrEqual(restoredCount, savedCount)
        XCTAssertEqual(browserDiagnostic(result, key: "savedCount"), restoredCount)
        attach("automation-real-public-feed-first-observation-after-cold-relaunch", app)
        // A provider can change its first post between reads. That cannot prove
        // deduplication of the same content, and is never relabeled a product pass.
        try XCTSkipIf(browserDiagnostic(result, key: "newContent") == 1,
                      "The live feed presented new content after cold launch. Morning/budget/progress restoration was checked; same-content deduplication needs a stable provider observation. No viewport/document continuity is claimed.")
        XCTAssertEqual(restoredCount, savedCount)
    }

    private func launch(_ flags: [String], french: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        let workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--light-preview", "--theme-phase=morning", "-more.appLanguage", french ? "fr" : "en",
            "-AppleLanguages", french ? "(fr)" : "(en)",
            "-AppleLocale", french ? "fr_FR" : "en_US"] + flags
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) {
            // Xcode 27 sometimes prelaunches the first target without the test's
            // arguments. Verify the isolated workspace before touching any UI.
            app.terminate(); app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.value as? String, workspace)
        return app
    }
    private func reveal(_ app: XCUIApplication) {
        MorningUITestNavigation.revealControls(in: app)
    }
    private func revealHomeControls(_ app: XCUIApplication) {
        let settings = app.buttons["morning.settings"]
        if settings.exists && settings.isHittable { return }
        let passages = app.descendants(matching: .any).matching(identifier: "morning.captions").firstMatch
        XCTAssertTrue(passages.waitForExistence(timeout: 10))
        // The ordinary landscape passage receives this tap. Avoid its bottom
        // edge, where a newly revealed command could otherwise be selected.
        passages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: settings)
        let result = XCTWaiter.wait(for: [visible], timeout: 5)
        if result != .completed { captureFailure("home-controls-not-revealed", app) }
        XCTAssertEqual(result, .completed)
    }
    private func tapHomeSettings(_ app: XCUIApplication) {
        reveal(app)
        // Controls expire after five seconds. Select Settings directly after
        // the reveal instead of scrolling Home or waiting on another predicate.
        app.buttons["morning.settings"].tap()
        let form = app.collectionViews["settings.appearance"]
        let opened = form.waitForExistence(timeout: 5)
        if !opened { captureFailure("home-settings-did-not-open", app) }
        XCTAssertTrue(opened, "The actual Settings screen must open from Home.")
    }
    private func tapVisible(_ identifier: String, in app: XCUIApplication) {
        if ["morning.settings", "morning.next", "morning.extend", "morning.stop"].contains(identifier) {
            let close = app.buttons["morning.closeDetails"]
            if close.exists {
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            }
            MorningUITestNavigation.tapButton(identifier, in: app)
        } else {
            visibleButton(identifier, in: app).tap()
        }
    }
    private func openCurrentMoment(in app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Morning", in: app)
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let snapshot = MorningUITestNavigation.sessionSnapshot(in: app)
            return snapshot["opening"] == "none" && ["running", "paused"].contains(snapshot["state"] ?? "")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15), .completed,
                       "The actual moment must start before its interaction is opened.")
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("morning.details", in: app)
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForExistence(timeout: 5))
    }
    private func assertPaused(in app: XCUIApplication) {
        MorningUITestNavigation.assertSession(state: "paused", in: app)
        openCurrentMoment(in: app)
    }
    private func currentStepTitle(in app: XCUIApplication) -> String {
        reveal(app)
        return MorningUITestNavigation.stepTitle(in: app)
    }
    private func waitForCompletion(in app: XCUIApplication, timeout: TimeInterval = 35) {
        MorningUITestNavigation.selectTab("Morning", in: app)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MorningUITestNavigation.sessionSnapshot(in: app)["state"] == "completed"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: timeout), .completed)
        MorningUITestNavigation.openSettings(in: app)
        XCTAssertTrue(app.staticTexts["morning.completeSummary"].waitForExistence(timeout: 5))
    }
    private func fullyVisibleProposalButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        let viewportTop = app.buttons["proposal.close"].frame.maxY + 8
        let viewportBottom = app.buttons["proposal.approve"].frame.minY - 8
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let startY = (viewportTop + viewportBottom) / 2
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: startY))
        for _ in 0..<12 {
            if button.exists, button.isHittable, button.frame.minY >= viewportTop, button.frame.maxY <= viewportBottom { break }
            let requiredShift: CGFloat
            if button.exists, button.frame.height > 0, button.frame.minY < viewportTop {
                requiredShift = viewportTop + 8 - button.frame.minY
            } else if button.exists, button.frame.height > 0 {
                requiredShift = viewportBottom - 8 - button.frame.maxY
            } else { requiredShift = -140 }
            // Tiny drags stay inside UIKit's touch slop and leave a partly
            // clipped control unmoved. Keep enough travel to begin scrolling.
            let shift = requiredShift < 0 ? max(-140, min(-44, requiredShift)) : min(140, max(44, requiredShift))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: startY + shift))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(button.isHittable, "Unreachable proposal control: \(identifier)")
        XCTAssertGreaterThanOrEqual(button.frame.minY, viewportTop, "The full control must clear the navigation bar.")
        XCTAssertLessThanOrEqual(button.frame.maxY, viewportBottom, "The full control must clear the pinned delegation button.")
        return button
    }
    private func visibleButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        scrollTo(button, identifier: identifier, in: app)
        return button
    }
    private func visibleSettingsButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let settings = app.collectionViews["settings.appearance"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let button = settings.buttons[identifier]
        // Returning from Connections preserves the Settings scroll position.
        // Lazy rows above us have no frame, so search the real form both ways.
        for towardBeginning in [true, false] {
            for _ in 0..<24 {
                if button.exists && button.isHittable { return button }
                if towardBeginning { settings.swipeDown() } else { settings.swipeUp() }
            }
        }
        captureFailure("unreachable-settings-\(identifier)", app)
        XCTAssertTrue(button.exists, "Missing Settings control: \(identifier)")
        XCTAssertTrue(button.isHittable, "Unreachable Settings control: \(identifier)")
        return button
    }
    private func enabledVisibleButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = visibleButton(identifier, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        let result = XCTWaiter.wait(for: [enabled], timeout: 8)
        if result != .completed { captureFailure("disabled-\(identifier)", app) }
        XCTAssertEqual(result, .completed, "The control must be ready before it is selected: \(identifier)")
        return button
    }
    private func scrollTo(_ element: XCUIElement, identifier: String, in app: XCUIApplication) {
        let proposalClose = app.buttons["proposal.close"]
        if proposalClose.exists && proposalClose.isHittable {
            scrollProposalTo(element, identifier: identifier, in: app)
            return
        }
        for attempt in 0..<24 where !element.exists || !element.isHittable {
            let scrolls = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let scroll = scrolls.first { $0.isHittable } ?? app
            // UIKit reports a zero frame for an offscreen multiline text field,
            // while its internal scroll indicator retains the correct position.
            // Use that position so a newly shortened form can be found above us.
            let frame = element.exists && element.frame.height > 0 ? element.frame :
                (element.exists ? element.descendants(matching: .any).allElementsBoundByIndex.first(where: { $0.frame.height > 0 })?.frame : nil)
            if let frame, frame.height > 0 {
                if frame.midY < scroll.frame.midY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            } else if attempt < 12 { scroll.swipeUp() }
            else {
                // SwiftUI virtualizes offscreen rows, including rows above a
                // retained Settings position after returning from setup.
                scroll.swipeDown()
            }
        }
        if !element.exists || !element.isHittable { captureFailure("unreachable-\(identifier)", app) }
        XCTAssertTrue(element.exists, "Missing control: \(identifier)")
        XCTAssertTrue(element.isHittable, "Unreachable control: \(identifier)")
    }
    private func scrollProposalTo(_ element: XCUIElement, identifier: String, in app: XCUIApplication) {
        // A virtualized omission may be above the last one just checked.
        // Search the actual proposal both ways, never observations.list behind it.
        for towardBeginning in [true, false] {
            for _ in 0..<24 {
                let close = app.buttons["proposal.close"], approve = app.buttons["proposal.approve"]
                guard close.exists && close.isHittable, approve.exists && approve.isHittable,
                      let list = app.collectionViews.allElementsBoundByIndex.first(where: {
                          $0.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "proposal.")).count > 0
                      }) else {
                    captureFailure("proposal-foreground-list-missing-\(identifier)", app)
                    XCTFail("The real proposal must own the scroll gesture."); return
                }
                let frame = list.frame, viewport = frame.intersection(app.frame)
                guard let bar = app.navigationBars.allElementsBoundByIndex.last(where: {
                    $0.exists && !$0.frame.isEmpty && $0.frame.minY.isFinite && $0.frame.maxY.isFinite && $0.frame.intersects(viewport)
                }) else {
                    captureFailure("proposal-scroll-navigation-missing", app); XCTFail("The proposal navigation geometry is missing."); return
                }
                let top = max(viewport.minY, bar.frame.maxY) + 8
                let bottom = min(viewport.maxY, approve.frame.minY) - 8
                guard !viewport.isNull, !viewport.isInfinite,
                      [frame.minX, frame.minY, viewport.minX, viewport.width, top, bottom].allSatisfy({ $0.isFinite }),
                      viewport.width > 100, bottom - top > 120 else {
                    captureFailure("proposal-scroll-no-safe-viewport", app); XCTFail("No proposal viewport clears the bars and approval control."); return
                }
                let visible = CGRect(x: viewport.minX + 12, y: top, width: viewport.width - 24, height: bottom - top)
                if element.exists && element.isHittable && !element.frame.isEmpty,
                   (identifier == "proposal.approve" || identifier == "proposal.close"
                    ? app.frame.contains(element.frame) : visible.contains(element.frame)) { return }
                let target = element.exists && element.frame.height > 0 ? element.frame : nil
                let down = target.map { $0.minY < visible.minY } ?? towardBeginning
                let high = visible.minY + visible.height * 0.2, low = visible.minY + visible.height * 0.8
                let origin = list.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: visible.midX - frame.minX, dy: (down ? high : low) - frame.minY))
                let end = origin.withOffset(CGVector(dx: visible.midX - frame.minX, dy: (down ? low : high) - frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        captureFailure("unreachable-proposal-\(identifier)", app)
        XCTAssertTrue(element.exists, "Missing proposal control: \(identifier)")
        XCTFail("The full proposal control must be visible and hittable: \(identifier)")
    }
    private func openSlackSetup(_ app: XCUIApplication) {
        tapHomeSettings(app)
        tapVisible("setup.connections", in: app)
        tapVisible("connections.account.slack", in: app)
    }
    private func openScreenTimeObservationChoices(_ app: XCUIApplication) {
        MorningUITestNavigation.openRoutine(in: app)
        tapVisible("learn.refine", in: app)
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 8))
        tapVisible("learn.screenTime", in: app)
        tapVisible("learn.screenTime.observations", in: app)
        XCTAssertTrue(app.buttons["observations.choose"].waitForExistence(timeout: 8))
        app.buttons["observations.choose"].tap()
        XCTAssertTrue(app.buttons["observations.suggestUpdate"].waitForExistence(timeout: 5))
        let synthetic = app.staticTexts["observations.fixtureMode"]
        scrollObservationListTo(synthetic, identifier: "observations.fixtureMode", in: app, towardBeginning: false)
        XCTAssertFalse(synthetic.label.isEmpty)
        XCTAssertFalse(app.buttons["observations.suggestUpdate"].isEnabled)
    }
    private func scrollObservationListTo(_ element: XCUIElement, identifier: String, in app: XCUIApplication,
                                         towardBeginning: Bool) {
        let list = app.collectionViews["observations.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        // List unloads distant rows. Search the actual observation list in both
        // directions rather than reading an absent lazy row's value or frame.
        for backward in [towardBeginning, !towardBeginning] {
            for _ in 0..<24 {
                if element.exists && element.isHittable { return }
                if backward { list.swipeDown() } else { list.swipeUp() }
            }
        }
        captureFailure("unreachable-\(identifier)", app)
        XCTAssertTrue(element.exists, "Missing observation content: \(identifier)")
        XCTAssertTrue(element.isHittable, "Unreachable observation content: \(identifier)")
    }
    private func dismissSlackKeyboardIfShown(_ app: XCUIApplication) {
        let done = app.buttons["slackMoment.keyboardDone"]
        guard done.waitForExistence(timeout: 2) else { return }
        XCTAssertTrue(done.isHittable)
        done.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        let result = XCTWaiter.wait(for: [dismissed], timeout: 5)
        if result != .completed { captureFailure("slack-keyboard-did-not-dismiss", app) }
        XCTAssertEqual(result, .completed)
    }
    private func openHomeInteraction(_ app: XCUIApplication) {
        if app.buttons["morning.closeDetails"].exists { return }
        tapHomeSettings(app)
        _ = visibleButton("morning.next", in: app)
        _ = visibleButton("morning.stop", in: app)
        enabledVisibleButton("morning.details", in: app).tap()
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForExistence(timeout: 5))
    }
    private func returnHome(_ app: XCUIApplication) {
        for _ in 0..<5 {
            let captions = app.scrollViews["morning.captions"]
            let idleLandscape = app.buttons["morning.actions"]
            if app.navigationBars.count == 0 && (captions.isHittable || idleLandscape.isHittable) { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 5) else {
                captureFailure("home-navigation-back-missing", app)
                XCTFail("Expected the real Back route from Settings to Home.")
                return
            }
            back.tap()
        }
        captureFailure("home-navigation-did-not-return", app)
        XCTFail("Expected the landscape without a navigation bar.")
    }
    private func visibleScreenTimeSwitch(_ bundleID: String, in app: XCUIApplication) -> XCUIElement {
        let identifier = "observations.screenTime.app.\(bundleID)"
        let choice = app.switches[identifier]
        // A List may unload distant rows. Search back from the recovery notice,
        // then forward again; never assume an offscreen switch has an AX frame.
        for downward in [true, false] {
            for _ in 0..<24 {
                if choice.exists && choice.isHittable { return choice }
                let candidates = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
                let scroll = candidates.first { $0.isHittable } ?? app
                if downward { scroll.swipeDown() } else { scroll.swipeUp() }
            }
        }
        captureFailure("unreachable-\(identifier)", app)
        XCTAssertTrue(choice.exists); XCTAssertTrue(choice.isHittable)
        return choice
    }
    private func openCalendlySetup(_ app: XCUIApplication) {
        tapHomeSettings(app)
        tapVisible("setup.connections", in: app)
        tapVisible("connections.account.calendly", in: app)
    }
    private func openOutlookSetup(_ app: XCUIApplication) {
        tapHomeSettings(app)
        tapVisible("setup.connections", in: app)
        tapVisible("connections.account.outlook", in: app)
    }
    private func launchOutlookRuntime(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["--ui-testing-outlook-inbox", "--ui-testing-outlook-runtime", "--ui-testing-approved", "--ui-testing-hands-free"] + extra)
        reveal(app); app.buttons["morning.begin"].tap()
        if !extra.contains("--ui-testing-voice-preparation") { openCurrentMoment(in: app) }
        return app
    }
    private func outlookReads(_ app: XCUIApplication) -> String {
        app.staticTexts["outlookInbox.synthetic"].value as? String ?? ""
    }
    private func waitForOutlookReads(_ value: String, _ app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: app.staticTexts["outlookInbox.synthetic"])
        let result = XCTWaiter.wait(for: [expected], timeout: 12)
        if result != .completed { captureFailure("outlook-expected-reads-failed", app) }
        XCTAssertEqual(result, .completed)
    }
    private func assertNoOutlookTechnicalDetails(_ app: XCUIApplication) {
        let labels = (app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex).map(\.label).joined(separator: " ")
        for forbidden in ["OUTLOOK_", "ca_synthetic_outlook", "synthetic-outlook-owner", "synthetic-outlook-message-", "synthetic-change-", "synthetic-inbox", "opaque-not-followed", "{\"", "JSON"] {
            XCTAssertFalse(labels.contains(forbidden), "Technical value exposed: \(forbidden)")
        }
    }
    private func launchCalendlyRuntime(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["--ui-testing-calendly-day", "--ui-testing-calendly-runtime", "--ui-testing-approved", "--ui-testing-hands-free"] + extra)
        reveal(app); app.buttons["morning.begin"].tap()
        if !extra.contains("--ui-testing-voice-preparation") { openCurrentMoment(in: app) }
        return app
    }
    private func assertNoCalendlyTechnicalDetails(_ app: XCUIApplication) {
        let labels = (app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex).map(\.label).joined(separator: " ")
        for forbidden in ["CALENDLY_", "ca_synthetic_calendly", "api.calendly.com", "synthetic-local-owner", "scheduled_events/", "opaque-synthetic", "{\"", "JSON"] {
            XCTAssertFalse(labels.contains(forbidden), "Technical value exposed: \(forbidden)")
        }
    }
    private func openGoogleCalendarSetup(_ app: XCUIApplication) {
        tapHomeSettings(app)
        tapVisible("setup.connections", in: app)
        tapVisible("connections.account.googlecalendar", in: app)
    }
    private func launchGoogleCalendarRuntime(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["--ui-testing-google-calendar-day", "--ui-testing-google-calendar-runtime", "--ui-testing-approved", "--ui-testing-hands-free"] + extra)
        reveal(app); app.buttons["morning.begin"].tap()
        if !extra.contains("--ui-testing-voice-preparation") { openCurrentMoment(in: app) }
        return app
    }
    private func assertNoGoogleTechnicalDetails(_ app: XCUIApplication) {
        let labels = (app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex).map(\.label).joined(separator: " ")
        for forbidden in ["GOOGLECALENDAR_", "ca_synthetic_google_calendar", "@calendar.invalid", "@group.calendar.invalid", "opaque-synthetic", "SYNTHETIC disponibilités seules masquées", "SYNTHETIC calendrier masqué", "SYNTHETIC calendrier supprimé", "{\"", "JSON"] {
            XCTAssertFalse(labels.contains(forbidden), "Technical or ineligible value exposed: \(forbidden)")
        }
    }
    private func assertNoSlackTechnicalDetails(_ app: XCUIApplication) {
        let labels = (app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex).map(\.label).joined(separator: " ")
        for forbidden in ["SLACK_", "ca_slack_synthetic_setup", "C12345678", "C22222222", "T12345678", "U12345678", "opaque-fixture", "SYNTHETIC-archive-masque", "SYNTHETIC-non-membre-masque", "SYNTHETIC-lecture-seule-masque", "{\"", "JSON"] {
            XCTAssertFalse(labels.contains(forbidden), "Technical or ineligible value exposed: \(forbidden)")
        }
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func captureFailure(_ name: String, _ app: XCUIApplication) {
        attach(name, app)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    private func remainingSeconds(_ label: String) -> Int {
        let components = label.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { XCTFail("Unexpected remaining time: \(label)"); return 0 }
        return components[0] * 60 + components[1]
    }
    private func observedContents(_ label: String) -> Int {
        let count = label.components(separatedBy: "·").last?
            .split(separator: " ").first.flatMap { Int($0) }
        guard let count else { XCTFail("Missing observed-content count: \(label)"); return 0 }
        return count
    }
    private func browserDiagnosticValue(_ status: XCUIElement, key: String) -> String? {
        let value = status.value as? String ?? ""
        return value.split(separator: " ").first { $0.hasPrefix(key + "=") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last }.map(String.init)
    }
    private func browserDiagnostic(_ status: XCUIElement, key: String) -> Int {
        let value = status.value as? String ?? ""
        let raw = value.split(separator: " ").first { $0.hasPrefix(key + "=") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last }
        guard let raw, let number = Int(raw) else {
            XCTFail("Missing browser diagnostic \(key): \(value)"); return 0
        }
        return number
    }
}
