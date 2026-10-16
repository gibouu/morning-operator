import XCTest
import MorningCore

/// Explicit synthetic protocol evidence only. Private reply tests use the real
/// mail policy with a closed transport; no live Gmail account or send is used.
@MainActor final class GmailAttentionJourneyTests: XCTestCase {
    /// A standalone responsive-layout gate, separate from the long routine and
    /// movie inference. Language is forced only in this app's argument domain.
    func testFrenchLargestNightReplyIsCorrectedReviewedAndSentOnceFromManualDraft() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        let title = "SYNTHETIC — Mes mails et ma réponse"
        let stepID = "91000000-0000-4000-8000-000000000001"
        let portable = #"{"format":"morning-operator.routine","formatVersion":1,"detail":"includeDetails","sourceRoutineID":"91000000-0000-4000-8000-000000000100","sourceRoutineVersion":1,"sourceCreatedAt":1792129500,"approvalAtExport":false,"sourceIsSynthetic":true,"sourceLabel":"SYNTHETIC — Brouillon manuel privé, sans analyse vidéo","steps":[{"id":"91000000-0000-4000-8000-000000000001","title":"SYNTHETIC — Mes mails et ma réponse","kind":"messages","durationMinutes":5,"isRequired":false,"detail":"SYNTHETIC — Examiner le mail de Maïa, préparer et corriger une réponse, relire puis demander un seul envoi simulé."}]}"#
        let data = Data(portable.utf8)
        let document = try PortableRoutineDocument.decode(data)
        let draft = try document.importedDraft(replacing: nil)
        XCTAssertTrue(document.sourceIsSynthetic && draft.isSynthetic)
        XCTAssertFalse(document.approvalAtExport || draft.isApproved)
        XCTAssertEqual(draft.steps.count, 1)
        XCTAssertNil(draft.steps[0].target); XCTAssertNil(draft.steps[0].automation)
        let app = XCUIApplication(), workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-gmail-attention", "--ui-testing-private-gmail-reply", "--ui-testing-hands-free", "--ui-testing-read-aloud",
            "--dark-preview", "--theme-phase=night", "--ui-testing-reduce-motion",
            "--ui-testing-parsed-routine=" + data.base64EncodedString(),
            "-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        // No approved/automation seeder: the imported moment receives authority
        // only through the Action picker, Save and the ordinary approval UI.
        app.launch(); defer { app.terminate() }
        try MorningUITestNavigation.requireIsolatedWorkspace(workspace, in: app)
        let notice = app.staticTexts["app.notice"]
        if notice.exists { XCTAssertFalse(notice.label.contains("SYNTHETIC QA input refused"), notice.label) }
        revealReplyControls(app); replyTap("morning.settings", app)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "settings.appearance").firstMatch.value as? String, "night")
        replyTap("setup.routine", app)
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(title))
        XCTAssertFalse(app.buttons["routine.step.1"].exists)
        replyTap("routine.step.0", app)
        XCTAssertTrue(app.collectionViews["step.editor.form"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["step.name"].value as? String, title)
        choosePrivateReplyAction(app)
        replyTap("step.save", app)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(title))
        XCTAssertTrue(app.buttons["routine.approve"].isEnabled)
        attach("gmail-reply-french-largest-night-configured-unapproved", app)
        replyTap("routine.approve", app)
        replyHome(app)
        // Prove that approval/configuration were saved, not reinstalled at launch.
        app.terminate()
        app.launchArguments.removeAll { $0.hasPrefix("--ui-testing-parsed-routine=") }
        app.launch(); try MorningUITestNavigation.requireIsolatedWorkspace(workspace, in: app)
        revealReplyControls(app); replyTap("morning.settings", app); replyTap("setup.routine", app)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(title))
        replyHome(app); revealReplyControls(app); replyTap("morning.begin", app)
        revealReplyControls(app)
        let playback = app.buttons["morning.playback"]
        let offered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label IN %@", ["Continuer", "Pause"]), object: playback)
        XCTAssertEqual(XCTWaiter.wait(for: [offered], timeout: 20), .completed)
        if playback.label == "Continuer" { replyControl("morning.playback", app).tap() }
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: playback)
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 10), .completed)
        revealReplyControls(app); replyTap("morning.settings", app); replyTap("morning.details", app)
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["mail.attention.explanation"].waitForExistence(timeout: 20))
        let initialProof = try replyProof("mail.reply.syntheticReceipt", app)
        XCTAssertEqual(initialProof["simulatedSendAttempts"], "0")
        XCTAssertNil(initialProof["body"])
        XCTAssertEqual(initialProof["inboxReads"], "1"); XCTAssertEqual(initialProof["bodyReads"], "5")
        XCTAssertEqual(initialProof["stepID"], stepID)
        for key in ["sessionID", "routineVersionID"] { XCTAssertNotNil(initialProof[key].flatMap(UUID.init(uuidString:))) }
        replyTap("mail.attention.choose.3", app)
        let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Mail choisi"), object: app.buttons["mail.attention.choose.3"])
        XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 10), .completed)
        replyTap("mail.reply.begin", app)
        let intention = "Réponds-lui que j’apporterai six cartes bleues à 09:15."
        let input = replyControl("mail.reply.intention", app)
        input.tap(); input.typeText(intention)
        XCTAssertEqual(input.value as? String, intention)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        replyTap("mail.reply.prepare", app)
        let initial = "SYNTHETIC — Je viendrai avec six cartes bleues à 09:15."
        waitForReplyBody(initial, app)
        XCTAssertFalse(app.buttons["mail.reply.send"].isEnabled)
        assertReplyRecipientAndBody(initial, in: app)
        attach("gmail-reply-french-largest-night-initial-recipient-and-body", app)
        let correction = "Corrige : huit cartes vertes, pas six bleues."
        let correctionInput = replyControl("mail.reply.correction", app)
        correctionInput.tap(); correctionInput.typeText(correction)
        XCTAssertEqual(correctionInput.value as? String, correction)
        XCTAssertFalse(app.buttons["mail.reply.send"].isEnabled)
        XCTAssertFalse(app.buttons["mail.reply.reviewed"].isEnabled)
        replyTap("mail.reply.revise", app)
        let corrected = "SYNTHETIC — Je viendrai avec huit cartes vertes à 09:15."
        waitForReplyBody(corrected, app)
        XCTAssertFalse(app.buttons["mail.reply.send"].isEnabled)
        assertReplyRecipientAndBody(corrected, in: app)
        attach("gmail-reply-french-largest-night-corrected-recipient-and-body", app)
        replyTap("mail.reply.reviewed", app)
        let reviewed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Réponse relue"), object: app.buttons["mail.reply.reviewed"])
        XCTAssertEqual(XCTWaiter.wait(for: [reviewed], timeout: 5), .completed)
        XCTAssertEqual(try replyProof("mail.reply.syntheticReceipt", app)["simulatedSendAttempts"], "0", "Review must not send.")
        let send = replyControl("mail.reply.send", app)
        XCTAssertTrue(send.isEnabled)
        attach("gmail-reply-french-largest-night-reviewed-separate-send", app)
        send.tap()
        // A successful send may complete the one-moment session after ordinary
        // local speech. The private memory receipt remains tied to its exact IDs.
        replyHome(app); revealReplyControls(app); replyTap("morning.settings", app)
        let receipt = app.staticTexts["qa.gmailReplyReceipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 25))
        _ = replyControl("qa.gmailReplyReceipt", app)
        let proof = try replyProof("qa.gmailReplyReceipt", app)
        XCTAssertEqual(proof["simulatedSendAttempts"], "1")
        XCTAssertEqual(proof["inboxReads"], "1"); XCTAssertEqual(proof["bodyReads"], "5")
        XCTAssertEqual(proof["from"], "owner@morning-fixture.invalid")
        XCTAssertEqual(proof["to"], "maia@morning-fixture.invalid")
        XCTAssertEqual(proof["subject"], "Re: SYNTHETIC — Cartes pour l’atelier")
        XCTAssertEqual(proof["body"], corrected)
        XCTAssertEqual(proof["threadID"], "synthetic-thread3")
        XCTAssertEqual(proof["inReplyTo"], "<synthetic3@synthetic.invalid>")
        XCTAssertEqual(proof["references"], proof["inReplyTo"])
        XCTAssertFalse(try XCTUnwrap(proof["messageID"]).isEmpty)
        XCTAssertFalse(try XCTUnwrap(proof["mimeDate"]).isEmpty)
        for (received, original) in [("receivedSessionID", "sessionID"), ("receivedRoutineVersionID", "routineVersionID"), ("receivedStepID", "stepID")] {
            XCTAssertEqual(proof[received], initialProof[original])
            XCTAssertEqual(proof[original], initialProof[original])
        }
        let attachment = XCTAttachment(string: String(decoding: try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        attachment.name = "gmail-reply-french-largest-night-actual-received-MIME"; attachment.lifetime = .keepAlways; add(attachment)
        attach("gmail-reply-french-largest-night-one-simulated-send-receipt", app)
    }

    func testPreferencesPersistAndIChooseAnotherActuallyReadMessage() {
        let app = launch()
        defer { app.terminate() }
        openPreferences(app)
        let priorities = field("gmail.attention.priorities", app)
        priorities.tap(); priorities.typeText("SYNTHETIC project commitments")
        app.swipeUp()
        tap("gmail.attention.save", app)
        XCTAssertTrue(app.staticTexts["gmail.attention.status"].label.contains("saved"))
        attach("gmail-attention-synthetic-priorities-saved", app)
        app.terminate(); app.launch()
        openPreferences(app)
        XCTAssertEqual(field("gmail.attention.priorities", app).value as? String, "SYNTHETIC project commitments")
        // Relaunch the same isolated workspace, then use ordinary routine playback.
        app.terminate(); app.launch()
        start(app)
        let explanation = app.staticTexts["mail.attention.explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 12))
        XCTAssertTrue(explanation.label.contains("SYNTHETIC") && explanation.label.contains("without a Gmail account or real inference"))
        XCTAssertTrue(app.staticTexts["mail.attention.prioritiesUsed"].label.contains("SYNTHETIC project commitments"))
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        let fourth = button("mail.attention.choose.4", app)
        XCTAssertTrue(fourth.isEnabled); fourth.tap()
        XCTAssertEqual(button("mail.attention.choose.4", app).label, "Selected message")
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        XCTAssertFalse(app.buttons["mail.selfSend"].exists)
        attach("gmail-attention-synthetic-fourth-read-message-chosen", app)
    }

    func testFallbackIsHonestAndNextDoesNotKeepMail() {
        let app = launch(extra: ["--ui-testing-gmail-attention-fallback"])
        defer { app.terminate() }
        start(app)
        let explanation = app.staticTexts["mail.attention.explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 12))
        XCTAssertTrue(explanation.label.contains("Test fallback") && explanation.label.contains("without personalized importance ranking"))
        XCTAssertFalse(app.staticTexts["mail.attention.prioritiesUsed"].exists)
        XCTAssertEqual(app.staticTexts["mail.attention.synthetic"].value as? String, "HTTP list reads: 1; body reads: 5")
        attach("gmail-attention-synthetic-honest-fallback", app)
        tap("mail.continue", app)
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: explanation)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["mail.attention.choose.1"].exists)
    }

    func testFrenchLargestTextKeepsPreferencesAndReadMessageChoiceReachable() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        openPreferences(app)
        XCTAssertTrue(field("gmail.attention.priorities", app).isHittable)
        XCTAssertTrue(button("gmail.attention.save", app).isHittable)
        attach("gmail-attention-synthetic-french-largest-preferences", app)
        app.terminate(); app.launch()
        start(app)
        XCTAssertTrue(app.staticTexts["mail.attention.explanation"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["mail.attention.explanation"].label.contains("sans compte Gmail ni inférence réelle"))
        button("mail.attention.choose.5", app).tap()
        XCTAssertEqual(button("mail.attention.choose.5", app).label, "Mail choisi")
        attach("gmail-attention-synthetic-french-largest-fifth-message", app)
    }

    private func launch(extra: [String] = [], french: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(), workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-gmail-attention", "--ui-testing-approved", "--ui-testing-hands-free", "--light-preview", "--theme-phase=morning",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US", "-more.appLanguage", french ? "fr" : "en"] + extra
        app.launch()
        if !app.staticTexts["qa.testWorkspace"].waitForExistence(timeout: 5) { app.terminate(); app.launch() }
        XCTAssertEqual(app.staticTexts["qa.testWorkspace"].value as? String, workspace)
        return app
    }

    private func waitForReplyBody(_ body: String, _ app: XCUIApplication) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", body),
                                              object: app.staticTexts["mail.reply.body"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }
    private func choosePrivateReplyAction(_ app: XCUIApplication) {
        let name = "Lire mes mails et m’aider à répondre"
        replyControl("step.automation", app).tap()
        let labels = ["Moment mené par vous", "Lire ce texte à voix haute", "Lire l’agenda du jour",
                      "Lire le récap du jour", "Prendre ce temps, puis continuer", name]
        let choices = NSPredicate(format: "label IN %@", labels)
        guard app.descendants(matching: .any).matching(choices).firstMatch.waitForExistence(timeout: 6) else {
            replyFailure("gmail-reply-action-popup-not-observed", app)
            XCTFail("The native Action popup must expose its real choices before scrolling."); return
        }
        attach("gmail-reply-french-largest-night-native-action-popup", app)
        for _ in 0..<12 {
            // The menu's own collection can extend under the editor's bars.
            // Its observed choices establish scope; never drag the Form behind it.
            let containers = app.menus.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex +
                app.scrollViews.allElementsBoundByIndex
            guard let popup = containers.filter({ candidate in
                candidate.exists && !["step.editor.form", "routine.editor", "morning.captions"].contains(candidate.identifier) &&
                    !candidate.frame.isEmpty && candidate.frame.intersects(app.frame) &&
                    candidate.descendants(matching: .any).matching(choices).allElementsBoundByIndex
                        .contains { $0.exists && $0.isHittable }
            }).min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                replyFailure("gmail-reply-action-popup-scope-lost", app)
                XCTFail("No native popup containing Action choices is in the foreground."); return
            }
            let visible = popup.frame.intersection(app.frame)
            let exact = popup.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name))
            if let choice = exact.allElementsBoundByIndex.first(where: {
                [.button, .menuItem, .staticText].contains($0.elementType) && $0.exists && $0.isEnabled && $0.isHittable &&
                    !$0.frame.isEmpty && visible.contains($0.frame)
            }) {
                choice.tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(
                    format: "exists == true AND (label CONTAINS %@ OR value CONTAINS %@)", name, name),
                    object: app.buttons["step.automation"])
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                               "The actual Picker must show Gmail selected before Save.")
                return
            }
            // A native popup's collection frame may exceed its clipped surface.
            // Swipe an actual visible option inside it, not that oversized frame
            // and not the editor exposed below the popup (observed in 9s).
            guard let anchor = popup.staticTexts.matching(choices).allElementsBoundByIndex.first(where: {
                $0.exists && $0.isHittable && !$0.frame.isEmpty && app.frame.contains($0.frame)
            }) ?? popup.buttons.matching(choices).allElementsBoundByIndex.first(where: {
                $0.exists && $0.isHittable && !$0.frame.isEmpty && app.frame.contains($0.frame)
            }) else {
                replyFailure("gmail-reply-action-popup-no-visible-option", app)
                XCTFail("No actual visible popup option can receive a normal scroll gesture."); return
            }
            anchor.swipeUp()
        }
        replyFailure("gmail-reply-action-popup-choice-unreachable", app)
        XCTFail("The exact Gmail choice must be visible and hittable inside the native popup.")
    }
    private func assertReplyRecipientAndBody(_ body: String, in app: XCUIApplication) {
        let recipient = replyControl("mail.reply.recipient", app)
        XCTAssertEqual(recipient.label, "À : maia@morning-fixture.invalid")
        let text = replyControl("mail.reply.body", app)
        XCTAssertEqual(text.label, body)
    }
    private func replyProof(_ id: String, _ app: XCUIApplication) throws -> [String: String] {
        let element = app.staticTexts[id]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with:
            Data(try XCTUnwrap(element.value as? String).utf8)) as? [String: String])
    }
    private func replyHome(_ app: XCUIApplication) {
        let close = app.buttons["morning.closeDetails"]
        if close.exists && close.isHittable { close.tap() }
        for _ in 0..<5 {
            if app.navigationBars.count == 0 { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 5), back.isHittable else {
                replyFailure("gmail-reply-back-unavailable", app)
                XCTFail("Use the actual foreground navigation back to Home."); return
            }
            back.tap()
        }
        replyFailure("gmail-reply-home-unreachable", app); XCTFail("Home did not become visible.")
    }
    private func revealReplyControls(_ app: XCUIApplication) {
        let settings = app.buttons["morning.settings"]
        if settings.exists && settings.isHittable { return }
        // Only Home owns this tap; never tap a caption behind a presented sheet.
        let details = app.buttons["morning.closeDetails"]
        XCTAssertFalse(details.exists && details.isHittable)
        XCTAssertEqual(app.navigationBars.count, 0)
        let captions = app.scrollViews["morning.captions"]
        if captions.exists && captions.isHittable { captions.tap() }
        else { replyControl("morning.actions", app).tap() }
        XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5))
    }
    private func replyTap(_ id: String, _ app: XCUIApplication) {
        let control = replyControl(id, app)
        XCTAssertTrue(control.isEnabled, "The visible ordinary action must be enabled: \(id)")
        control.tap()
    }
    private func replyControl(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        if ["morning.settings", "morning.begin", "morning.playback", "morning.actions"].contains(id) {
            // Home controls expire after five seconds. Query the exact button
            // before absent Form probes; never try to reveal it by scrolling.
            let control = app.buttons[id]
            if control.exists && control.isHittable { return control }
            if control.waitForExistence(timeout: 2), control.isHittable { return control }
            replyFailure("gmail-reply-home-control-not-visible-" + id, app)
            XCTFail("Reveal the actual Home control before using it: \(id)"); return control
        }
        let matches = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label == %@", id, id))
        _ = matches.firstMatch.waitForExistence(timeout: 6)
        for down in [false, true] {
            for _ in 0..<14 {
                let detailsButton = app.buttons["morning.closeDetails"]
                let details = detailsButton.exists && detailsButton.isHittable
                let editor = app.collectionViews["step.editor.form"]
                let editorForeground = editor.exists && editor.isHittable
                let routine = app.collectionViews["routine.editor"].firstMatch
                let approval = app.buttons["routine.approve"]
                let edit = app.buttons["routine.edit"]
                let routineForeground = !details && !editorForeground && routine.exists &&
                    ((approval.exists && approval.isHittable) || (edit.exists && edit.isHittable))
                let holder: XCUIElement?
                if details {
                    // Mail is in a non-lazy ScrollView. This ancestry selects the
                    // current Details content, never a Home scroll behind it.
                    holder = app.scrollViews.containing(.any, identifier: "mail.attention.synthetic").allElementsBoundByIndex
                        .first { $0.exists && !$0.frame.isEmpty && $0.frame.intersects(app.frame) }
                } else {
                    // The List supplies geometry; its visible approval/edit
                    // controls establish foreground ownership, not isHittable.
                    holder = editorForeground ? editor : routineForeground ? routine
                        : app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
                            ?? app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable)
                }
                let viewport = (holder?.frame ?? app.frame).intersection(app.frame)
                var top = viewport.minY, bottom = viewport.maxY
                let bars = app.navigationBars.allElementsBoundByIndex.filter {
                    $0.exists && !$0.frame.isEmpty && $0.frame.intersects(viewport)
                }
                if let bar = bars.last { top = max(top, bar.frame.maxY) }
                if routineForeground, approval.exists, approval.frame.intersects(viewport) {
                    bottom = min(bottom, approval.frame.minY - 8)
                }
                let keyboard = app.keyboards.firstMatch
                if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
                let safe = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
                if routineForeground, id.hasPrefix("routine.step.") {
                    let row = routine.buttons[id].firstMatch
                    let title = row.staticTexts.firstMatch
                    // At XXXL a row can exceed the entire free viewport. Tap its
                    // real title only when that child is wholly visible above
                    // the footer; the subsequent Form/name assertions pin the row.
                    if row.exists, row.isEnabled, title.exists, title.isHittable,
                       !title.frame.isEmpty, safe.contains(title.frame) { return title }
                }
                if let control = matches.allElementsBoundByIndex.first(where: { candidate in
                    candidate.exists && candidate.isHittable && !candidate.frame.isEmpty && app.frame.contains(candidate.frame) &&
                        (safe.contains(candidate.frame) || bars.contains { $0.frame.contains(candidate.frame) } ||
                         (routineForeground && id == "routine.approve" && candidate.identifier == id))
                }) { return control }
                guard let holder, !safe.isNull, !safe.isInfinite,
                      [safe.minX, safe.minY, safe.width, safe.height].allSatisfy({ $0.isFinite }),
                      safe.width > 80, safe.height > 120 else {
                    replyFailure("gmail-reply-no-foreground-scroll-" + id, app)
                    XCTFail("No safe foreground content above the keyboard for \(id)."); return matches.firstMatch
                }
                // Real content-relative scrolling also exercises interactive
                // keyboard dismissal. No fixed screen point or hidden control tap.
                let origin = holder.coordinate(withNormalizedOffset: .zero)
                let high = safe.minY + safe.height * 0.2, low = safe.minY + safe.height * 0.8
                let start = origin.withOffset(CGVector(dx: safe.midX - holder.frame.minX, dy: (down ? high : low) - holder.frame.minY))
                let end = origin.withOffset(CGVector(dx: safe.midX - holder.frame.minX, dy: (down ? low : high) - holder.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        replyFailure("gmail-reply-unreachable-" + id, app)
        XCTFail("The complete ordinary control must be visible and hittable: \(id)")
        return matches.firstMatch
    }
    private func replyFailure(_ name: String, _ app: XCUIApplication) {
        attach(name, app)
        let state = XCTAttachment(string: app.debugDescription)
        state.name = name + "-accessibility"; state.lifetime = .keepAlways; add(state)
    }
    private func reveal(_ app: XCUIApplication) {
        if !app.buttons["morning.begin"].exists && !app.buttons["morning.playback"].exists { tap("morning.actions", app) }
    }
    private func openPreferences(_ app: XCUIApplication) {
        reveal(app); tap("morning.settings", app); tap("setup.connections", app); tap("connections.gmailReader", app)
        XCTAssertTrue(app.staticTexts["gmail.attention.synthetic"].waitForExistence(timeout: 5))
        tap("gmail.attention.settings", app)
    }
    private func start(_ app: XCUIApplication) {
        reveal(app); tap("morning.begin", app)
        let captions = app.scrollViews["morning.captions"]
        XCTAssertTrue(captions.waitForExistence(timeout: 10))
        if !app.buttons["morning.settings"].exists { captions.coordinate(withNormalizedOffset: .init(dx: 0.25, dy: 0.25)).tap() }
        XCTAssertTrue(app.buttons["morning.playback"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["morning.more"].exists)
        XCTAssertFalse(app.buttons["morning.next"].exists)
        tap("morning.settings", app); tap("morning.details", app)
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForExistence(timeout: 5))
    }
    private func field(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        scroll(element, app); return element
    }
    private func button(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[identifier]; scroll(element, app); return element
    }
    private func tap(_ identifier: String, _ app: XCUIApplication) { button(identifier, app).tap() }
    private func scroll(_ element: XCUIElement, _ app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 6)
        for down in [false, true] {
            for _ in 0..<14 {
                if element.exists && element.isHittable { return }
                let scroll = app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
                    ?? app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app
                if down { scroll.swipeDown() } else { scroll.swipeUp() }
            }
        }
        XCTContext.runActivity(named: "Unreachable \(element.identifier)") { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; activity.add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; activity.add(screenshot)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable control \(element.identifier)")
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
