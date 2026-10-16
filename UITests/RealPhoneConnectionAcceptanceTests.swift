import XCTest

/// Owner-assisted checks of the installed ordinary app, never a seeded workspace.
/// Screenshots may contain private data: keep the resulting xcresult local.
@MainActor
final class RealPhoneConnectionAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var leaveGmailSignInPresented = false

    private func activateOrdinaryApp() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_REAL_PHONE_CONNECTIONS"] == "1" else {
            throw XCTSkip("Requires explicit MO_REAL_PHONE_CONNECTIONS=1; no app was activated.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This acceptance suite requires the owner's physical iPhone.")
        #else
        guard let bundle = environment["MO_REAL_PHONE_BUNDLE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              bundle.hasPrefix("com.gibouu.morningoperator."),
              !bundle.lowercased().contains("fixture"), !bundle.lowercased().contains(".qa") else {
            throw XCTSkip("Provide the explicit installed ordinary MORE bundle in MO_REAL_PHONE_BUNDLE_ID.")
        }
        app = XCUIApplication(bundleIdentifier: bundle)
        // A failed assertion can stop a method before Swift defer runs.
        addTeardownBlock { @MainActor [weak self] () async throws in
            self?.returnToConnections()
        }
        // Activate the existing ordinary app without launch arguments or launch environment.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "The selected ordinary app did not reach the foreground.")
        try refusePermissionOrFixtureScreens()
        #endif
    }

    func testBackendConfiguredAndOptionalExistingGmailAPIAccount() throws {
        try openConnections()
        let gmailActions = app.buttons["connections.gmailActions"]
        XCTAssertTrue(gmailActions.waitForExistence(timeout: 25),
                      "The installed app did not load its configured live service catalogue. No backend readiness is claimed.")
        XCTAssertTrue(app.buttons["connections.account.outlook"].exists,
                      "The live catalogue did not expose the expected configured Outlook service.")
        capture("real-phone-configured-connections")

        guard ProcessInfo.processInfo.environment["MO_REAL_PHONE_EXPECT_GMAIL_ACCOUNT"] == "1" else { return }
        reveal(gmailActions)
        if !gmailAPIConnection.exists { gmailActions.tap() }
        let gmail = gmailAPIConnection
        reveal(gmail)
        gmail.tap()
        defer { returnToConnections() }
        try refusePermissionOrFixtureScreens()
        let loaded = app.buttons["accounts.refresh"]
        XCTAssertTrue(loaded.waitForExistence(timeout: 25), "The Gmail API account check did not finish.")
        XCTAssertFalse(app.descendants(matching: .any)["accounts.notice"].exists,
                       "The Gmail API account check reported a connection problem.")
        let activeAccount = button(labels: ["Choose an action", "Choisir une action"])
        XCTAssertTrue(activeAccount.exists,
                      "No active Gmail API account was verified for this installation. No sign-in was attempted.")
        // Presence of this action chooser proves ACTIVE metadata; never open or run it.
        capture("real-phone-existing-gmail-api-account")
    }

    func testExistingCalendarAccessWithoutChangingSelection() throws {
        try openConnections()
        let calendar = button(containing: ["Your schedule and the weather where you are going.",
                                           "Votre agenda et la météo de la ville de votre choix."])
        reveal(calendar)
        calendar.tap()
        defer { returnToConnections(calendar: true) }
        try refusePermissionOrFixtureScreens()
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists, "Synthetic calendars cannot establish real access.")
        let choices = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "briefing.calendar."))
        let readiness = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier IN %@",
            "briefing.calendar.", ["briefing.calendarConnect", "briefing.error"]))
        XCTAssertTrue(readiness.firstMatch.waitForExistence(timeout: 15), "The calendar connection screen did not become ready.")
        capture("real-phone-existing-calendar-access")
        XCTAssertFalse(app.staticTexts["briefing.error"].exists, "The existing calendar source reported a read error.")
        guard choices.count > 0 else {
            throw XCTSkip("No existing readable calendar inventory was exposed. No permission or calendar selection was changed.")
        }
        // Inventory only: no calendar toggle, event mutation, or speech preview is used.
    }

    func testReadNativeGmailUsingExistingSavedConnection() throws {
        try openConnections()
        let reader = app.buttons["connections.gmailReader"]
        reveal(reader)
        reader.tap()
        defer { returnToConnections() }
        try refusePermissionOrFixtureScreens()

        // Opening this reader restores the existing grant and performs one fresh
        // bounded unread load. Refresh would issue a second load, so never tap it.
        let messages = app.descendants(matching: .any)["gmail.messages"]
        let loaded = messages.waitForExistence(timeout: 45)
        try refusePermissionOrFixtureScreens()
        if !loaded {
            if app.staticTexts["gmail.configuration"].exists {
                capture(app.staticTexts["gmail.error"].exists
                    ? "real-phone-native-gmail-configuration-error-present"
                    : "real-phone-native-gmail-configuration-no-error")
                throw XCTSkip("Native Gmail is not configured in this installed app. No consent was started.")
            }
            if app.buttons["gmail.connect"].exists && !app.buttons["gmail.refresh"].exists {
                capture(app.staticTexts["gmail.error"].exists
                    ? "real-phone-native-gmail-no-saved-connection-error-present"
                    : "real-phone-native-gmail-no-saved-connection-no-error")
                throw XCTSkip("No saved native Gmail connection is available. Connect was not pressed.")
            }
        }
        XCTAssertTrue(loaded, "The saved native Gmail connection did not finish its unread load. No mailbox read success is claimed.")
        XCTAssertTrue(app.staticTexts["gmail.unread"].exists, "The native Gmail INBOX count did not load.")
        XCTAssertTrue(app.buttons["gmail.refresh"].isEnabled, "The native Gmail read has not finished.")
        XCTAssertFalse(app.staticTexts["gmail.error"].exists, "The native Gmail read reported a problem.")
        XCTAssertFalse(app.staticTexts["gmail.messages.partial"].exists, "Some unread headers failed to load; this is not an empty Inbox.")
        let stale = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "This list needs a refresh.", "Cette liste doit être actualisée.",
            "This count needs a refresh."
        ])).firstMatch
        XCTAssertFalse(stale.exists, "The native Gmail result is no longer fresh.")
        let identifiedRows = app.buttons.matching(identifier: "gmail.message.open")
        // SwiftUI can propagate the surrounding VStack's identifier over its
        // CardButtons. It has no other buttons, so these are the same inbox rows.
        let rowCount = identifiedRows.count > 0 ? identifiedRows.count
            : app.buttons.matching(identifier: "gmail.messages").count
        let empty = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "No unread messages in Inbox.", "Aucun message non lu dans la boîte de réception."
        ])).firstMatch.exists
        XCTAssertTrue(rowCount <= 5, "The native unread list exceeded its five-message bound.")
        XCTAssertTrue(rowCount > 0 || empty, "A missing list is not evidence of an empty unread Inbox.")
        XCTAssertFalse(rowCount > 0 && empty, "The native unread list and its empty-state indicator disagree.")
        if ProcessInfo.processInfo.environment["MO_REAL_PHONE_EXPECT_GMAIL_SEND_ACCESS"] == "1" {
            XCTAssertFalse(app.buttons["gmail.enableSending"].exists,
                           "The existing native Gmail session does not expose sending access. No broader consent was started.")
        }
        // No successful mailbox content is explicitly captured or opened.
        // Never inspect or print message labels, subjects, senders, or counts.
    }

    func testInspectExistingRoutineWithoutEditing() throws {
        try openExistingRoutine()
        let inventory = try inspectRoutineRows(name: "real-phone-existing-routine", capturePages: true)
        XCTAssertFalse(inventory.labels.isEmpty, "The existing plan appeared, but no visible routine row could be inventoried.")
    }

    func testConfigureExistingGmailMomentWithoutApproving() throws {
        guard ProcessInfo.processInfo.environment["MO_REAL_PHONE_CONFIGURE_EXISTING_GMAIL_MOMENT"] == "1" else {
            throw XCTSkip("Requires the separate existing-Gmail-moment configuration opt-in; no app was activated.")
        }
        try openExistingRoutine()
        let before = try inspectRoutineRows(name: "real-phone-routine-before-gmail-configuration")
        let expectedIndices = Set(0..<8)
        let gmailDescriptions = [
            "Gmail · Lire vos mails non lus, préparer et corriger une réponse. Envoyer seulement à votre demande.",
            "Gmail · Read unread mail, prepare and edit a reply. Send only when you ask."
        ]
        let manualDescriptions = [
            "Moment personnel. Dites « suivant » lorsque vous avez terminé.",
            "Your own moment. Say “next” when you finish."
        ]
        let mail = before.labels[5] ?? ""
        let expectedMail = mail.range(of: #"^Mail[\s,]+7\s+min(?:\s|[·,])"#, options: .regularExpression) != nil
        guard before.reachedEnd, Set(before.labels.keys) == expectedIndices, expectedMail else {
            throw XCTSkip("The exact eight-moment plan with Mail at index 5 for seven minutes was not verified. Nothing was edited.")
        }
        if gmailDescriptions.contains(where: mail.contains) { return }
        guard before.draft, manualDescriptions.contains(where: mail.contains) else {
            throw XCTSkip("The Mail moment is not the expected user-led draft. Nothing was edited.")
        }

        let row = app.buttons["routine.step.5"]
        try revealRoutineControl(row, towardTopWhenMissing: true)
        row.tap()
        let name = app.textFields.matching(NSPredicate(format: "label IN %@", [
            "Step name", "Nom de l’étape", "Nom de l'étape"
        ])).firstMatch
        let duration = app.steppers["step.duration"]
        try revealRoutineControl(name, towardTopWhenMissing: true)
        let existingName = name.value as? String
        try revealRoutineControl(duration)
        guard existingName == "Mail", duration.value as? String == "7" else {
            throw XCTSkip("The moment editor's name or duration differs. Save was not pressed.")
        }
        let action = app.buttons["step.automation"]
        try revealRoutineControl(action)
        action.tap()
        let gmail = button(labels: ["Read my mail and help me reply", "Lire mes mails et m’aider à répondre"])
        guard gmail.waitForExistence(timeout: 5), gmail.isHittable else {
            throw XCTSkip("The exact Gmail action was not offered. Nothing was selected or saved.")
        }
        gmail.tap()
        try refusePermissionOrFixtureScreens()
        try revealRoutineControl(name, towardTopWhenMissing: true)
        let reviewedName = name.value as? String
        try revealRoutineControl(duration)
        XCTAssertTrue(reviewedName == "Mail" && duration.value as? String == "7",
                      "The moment's title or duration changed before saving.")
        let save = app.buttons["step.save"]
        XCTAssertTrue(save.exists && save.isEnabled && save.isHittable, "The reviewed moment is not ready to save.")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10), "The moment edit was not confirmed saved.")
        XCTAssertFalse(app.staticTexts["step.saveError"].exists, "The moment edit reported a save failure.")

        let after: (labels: [Int: String], draft: Bool, reachedEnd: Bool)
        do { after = try inspectRoutineRows(name: "real-phone-routine-after-gmail-configuration") }
        catch { XCTFail("The edit was saved, but its required post-save inventory could not be verified."); return }
        XCTAssertTrue(after.reachedEnd && Set(after.labels.keys) == expectedIndices,
                      "The original eight-moment structure was not preserved.")
        for index in expectedIndices where index != 5 {
            XCTAssertTrue(after.labels[index] == before.labels[index], "An unrelated moment's title, duration or action changed at index \(index).")
        }
        let updated = after.labels[5] ?? ""
        XCTAssertTrue(updated.range(of: #"^Mail[\s,]+7\s+min(?:\s|[·,])"#, options: .regularExpression) != nil,
                      "The Mail title or seven-minute duration was not preserved.")
        XCTAssertTrue(gmailDescriptions.contains(where: updated.contains), "The Mail moment does not expose the Gmail Inbox action.")
        XCTAssertTrue(after.draft, "The routine must remain a draft; no approval or run was requested.")
        // Only this existing moment's operation is saved. Never approve, start, or send mail.
    }

    func testFinishExistingRoutineWithoutReopeningMail() throws {
        guard ProcessInfo.processInfo.environment["MO_REAL_PHONE_FINISH_EXISTING_ROUTINE"] == "1" else {
            throw XCTSkip("Requires the separate finish-existing-routine opt-in; no app was activated.")
        }
        leaveGmailSignInPresented = true // Preserve the existing session in teardown.
        try activateOrdinaryApp()
        let controls = app.buttons["morning.actions"]
        guard controls.exists else { throw XCTSkip("Leave the existing ordinary morning on Home.") }
        if ["Show controls", "Afficher les commandes"].contains(controls.label) { controls.tap() }
        let current = app.staticTexts["morning.currentStep"]
        guard current.waitForExistence(timeout: 10),
              ["Scroll a little", "A thought for later"].contains(current.label),
              !app.buttons["nativeMoment.cancel"].exists else {
            throw XCTSkip("Only the existing final two moments without a pending native request may finish. Mail was not advanced or changed.")
        }
        let beganAtScroll = current.label == "Scroll a little"
        var pauseResumeObserved = false
        var nextTaps = 0
        if beganAtScroll {
            let playback = app.buttons["morning.playback"]
            try revealRoutineControl(playback)
            // An already-paused final moment first resumes, then gets the same explicit cycle.
            if ["Continue", "Continuer"].contains(playback.label) {
                XCTAssertTrue(current.label == "Scroll a little", "The moment changed before initial resume.")
                playback.tap()
                XCTAssertTrue(selfNoteWait(playback, predicate: NSPredicate(format: "label == %@", "Pause"), timeout: 10),
                              "The existing moment did not resume.")
            }
            XCTAssertTrue(current.label == "Scroll a little" && playback.label == "Pause" && playback.isHittable,
                          "The verified Scroll moment is not running; no pause was pressed.")
            playback.tap()
            XCTAssertTrue(selfNoteWait(playback, predicate: NSPredicate(format: "label IN %@", ["Continue", "Continuer"]), timeout: 10),
                          "Pause did not expose the ordinary Continue control.")
            XCTAssertTrue(current.label == "Scroll a little", "Pause changed the current moment.")
            try refusePermissionOrFixtureScreens()
            XCTAssertTrue(playback.isHittable, "Continue is not reachable; no replacement action was used.")
            playback.tap()
            XCTAssertTrue(selfNoteWait(playback, predicate: NSPredicate(format: "label == %@", "Pause"), timeout: 10),
                          "Continue did not restore the running control.")
            XCTAssertTrue(current.label == "Scroll a little", "Resume changed the current moment.")
            pauseResumeObserved = true
            let next = app.buttons["morning.next"]
            try revealRoutineControl(next)
            XCTAssertTrue(current.label == "Scroll a little" && next.isEnabled, "Scroll changed before its single Next.")
            next.tap(); nextTaps += 1
        }
        XCTAssertTrue(selfNoteWait(current, predicate: NSPredicate(format: "exists == true AND label == %@", "A thought for later"), timeout: 10),
                      "The expected final thought moment was not reached. No further Next was pressed.")
        try refusePermissionOrFixtureScreens()
        let next = app.buttons["morning.next"]
        try revealRoutineControl(next)
        XCTAssertTrue(current.label == "A thought for later" && next.isEnabled, "The last moment changed before its single Next.")
        next.tap(); nextTaps += 1
        XCTAssertTrue(MorningUITestNavigation.waitForCompletedMorning(in: app, timeout: 10), "The existing morning did not reach its completion screen.")
        try refusePermissionOrFixtureScreens()
        XCTAssertTrue(app.staticTexts["morning.completeSummary"].exists, "The completion summary is missing.")
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].exists, "The execution summary is missing.")
        XCTAssertFalse(current.exists, "An active moment remains after the completion screen.")
        XCTAssertFalse(app.buttons["morning.next"].exists, "Next remains after completion.")
        XCTAssertTrue(nextTaps <= 2, "The final-two-moment bound was exceeded.")
        let evidence = XCTAttachment(string: "Began at Scroll: \(beganAtScroll)\nTouch pause/resume with unchanged title observed: \(pauseResumeObserved)\nNext taps: \(nextTaps)\nCompletion and both summaries observed; active moment and Next absent.\nNo Mail action, Send, new session, routine edit or teardown navigation.")
        evidence.name = "real-phone-existing-routine-final-moments"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func openExistingRoutine() throws {
        try activateOrdinaryApp()
        let routine = app.buttons["setup.routine"]
        if !routine.exists || !routine.isHittable {
            let settings = app.buttons["morning.settings"]
            if !settings.exists {
                let controls = app.buttons["morning.actions"]
                guard controls.waitForExistence(timeout: 10), controls.isHittable,
                      ["Show controls", "Afficher les commandes"].contains(controls.label) else {
                    throw XCTSkip("Leave ordinary MORE on Home or Settings. No other screen was dismissed.")
                }
                controls.tap()
            }
            reveal(settings)
            settings.tap()
        }
        reveal(routine)
        routine.tap()
        let editor = app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The existing routine editor did not appear.")
        try refusePermissionOrFixtureScreens()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No existing routine moment was rendered.")
    }

    private func inspectRoutineRows(name: String, capturePages: Bool = false) throws -> (labels: [Int: String], draft: Bool, reachedEnd: Bool) {
        try revealRoutineControl(app.buttons["routine.step.0"], towardTopWhenMissing: true)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step."))
        var labels: [Int: String] = [:]
        var draftApprovalVisible = false
        var reachedEnd = false
        for page in 0..<5 {
            try refusePermissionOrFixtureScreens()
            draftApprovalVisible = draftApprovalVisible || app.buttons["routine.approve"].exists
            for row in rows.allElementsBoundByIndex.prefix(32) where row.exists && row.isHittable {
                guard let index = Int(row.identifier.dropFirst("routine.step.".count)),
                      (0..<32).contains(index) else { continue }
                labels[index] = String(row.label.prefix(4_096)).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            }
            reachedEnd = app.buttons["routine.add"].exists && app.buttons["routine.add"].isHittable
            if capturePages || page == 0 { capture("\(name)-page-\(page + 1)") }
            if reachedEnd || page == 4 { break }
            let scroll = routineScrollSurface
            guard scroll.exists else { break }
            scroll.swipeUp()
        }
        let inventory = ([
            "Local routine row inventory; no provider action executed.",
            "Runner locale: \(Locale.current.identifier)",
            "Preferred languages: \(Locale.preferredLanguages.prefix(3).joined(separator: ", "))",
            "Draft approval control present: \(draftApprovalVisible)",
            "End of moment list observed: \(reachedEnd)",
            "Observed row count: \(labels.count)"
        ] + labels.keys.sorted().map { "routine.step.\($0): \(labels[$0] ?? "")" }).joined(separator: "\n")
        let attachment = XCTAttachment(string: inventory)
        attachment.name = "\(name)-inventory-local-only"
        attachment.lifetime = .keepAlways
        add(attachment)
        // The five-page bound is an inventory limit, not proof that every moment was visible.
        // Never open a row, approve, save, import, change a budget, delete, or begin a run.
        return (labels, draftApprovalVisible, reachedEnd)
    }

    private var routineScrollSurface: XCUIElement {
        if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
        if app.tables.firstMatch.exists { return app.tables.firstMatch }
        return app.scrollViews.firstMatch
    }

    private func revealRoutineControl(_ element: XCUIElement, towardTopWhenMissing: Bool = false) throws {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            let scroll = routineScrollSurface
            guard scroll.exists else { break }
            if (!element.exists && towardTopWhenMissing) || (element.exists && element.frame.midY < scroll.frame.midY) { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        guard element.exists && element.isHittable else {
            throw XCTSkip("A required routine control is not reachable. No replacement plan or fallback action was used.")
        }
    }

    func testPresentNativeGmailReadAndSendSignInForOwner() throws {
        guard ProcessInfo.processInfo.environment["MO_REAL_PHONE_PRESENT_GMAIL_SIGN_IN"] == "read_and_send" else {
            throw XCTSkip("Requires the separate read_and_send sign-in presentation opt-in; no app was activated.")
        }
        try openConnections()
        let reader = app.buttons["connections.gmailReader"]
        reveal(reader)
        reader.tap()
        try refusePermissionOrFixtureScreens()
        let connect = app.buttons["gmail.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "The ordinary reader is not offering a new Gmail connection.")
        reveal(connect)
        guard connect.isEnabled, !app.buttons["gmail.refresh"].exists,
              !app.buttons["gmail.disconnect"].exists,
              !app.staticTexts["gmail.configuration"].exists,
              !app.staticTexts["gmail.error"].exists else {
            throw XCTSkip("A saved connection, retry, configuration problem, or read error requires review. No consent was started.")
        }
        let enableSending = app.buttons["gmail.enableSending"]
        XCTAssertTrue(enableSending.waitForExistence(timeout: 10), "This installed app does not expose the requested read-and-send sign-in.")
        reveal(enableSending)
        XCTAssertTrue(enableSending.isEnabled, "The requested sign-in action is not ready.")
        // Returning to the reader's parent would cancel ASWebAuthenticationSession.
        leaveGmailSignInPresented = true
        enableSending.tap()
        _ = app.webViews.firstMatch.waitForExistence(timeout: 12)
        let presented = app.webViews.allElementsBoundByIndex.contains { $0.isHittable }
            || app.alerts.count > 0
            || XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count > 0
        capture(presented ? "real-phone-gmail-sign-in-presented-owner-handoff" : "real-phone-gmail-sign-in-presentation-unconfirmed")
        XCTAssertTrue(presented, "No system web view or prompt was detected. Authentication success is not claimed.")
        // The owner completes Google consent. Never enter credentials, accept, cancel, or go back here.
    }

    func testReadRemindersOnlyWithPreviouslyGrantedAccess() throws {
        try openConnections()
        let reminders = button(containing: ["Find your upcoming reminders and mark them done.",
                                            "Retrouvez vos prochains rappels et cochez ceux qui sont terminés."])
        reveal(reminders)
        reminders.tap()
        defer { returnToConnections() }
        let read = app.buttons["native.remindersRead"]
        XCTAssertTrue(read.waitForExistence(timeout: 10), "The native Reminders page did not open.")
        try refusePermissionOrFixtureScreens()
        guard ["Show my reminders", "Afficher mes rappels"].contains(read.label) else {
            capture("real-phone-reminders-access-required")
            throw XCTSkip("Reminders access is not already granted. The permission request was not pressed.")
        }
        reveal(read)
        XCTAssertTrue(read.isEnabled, "A reminder read is already in progress; no duplicate request was made.")
        read.tap()
        try refusePermissionOrFixtureScreens()
        let readAt = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Read at ", "Lus à ")).firstMatch
        XCTAssertTrue(readAt.waitForExistence(timeout: 20),
                      "The native Reminders read did not produce its success timestamp. Empty data alone is not success.")
        XCTAssertFalse(app.staticTexts["native.remindersMessage"].exists,
                       "The native Reminders read reported a problem.")
        capture("real-phone-native-reminders-read")
        // Never tap a reminder's completion button, even when the list is nonempty.
    }

    private func openConnections() throws {
        try activateOrdinaryApp()
        try refusePermissionOrFixtureScreens()
        if isConnectionsPage { return }
        if connectionsNavigation.exists && connectionsNavigation.isHittable && app.buttons["connections.gmailReader"].exists {
            reveal(app.buttons["connections.gmailReader"])
            XCTAssertTrue(isConnectionsPage, "The visible Apps & accounts page could not be confirmed.")
            return
        }
        let connections = app.buttons["setup.connections"]
        if !connections.exists || !connections.isHittable {
            let settings = app.buttons["morning.settings"]
            if !settings.exists || !settings.isHittable {
                let controls = app.buttons["morning.actions"]
                guard controls.waitForExistence(timeout: 10), controls.isHittable,
                      ["Show controls", "Afficher les commandes"].contains(controls.label) else {
                    capture("real-phone-navigation-unavailable")
                    throw XCTSkip("Leave ordinary MORE on Home, Settings, or Apps & accounts. No other screen was dismissed.")
                }
                controls.tap()
            }
            reveal(settings)
            settings.tap()
        }
        reveal(connections)
        connections.tap()
        XCTAssertTrue(connectionsNavigation.waitForExistence(timeout: 10), "Apps & accounts did not open.")
        XCTAssertTrue(connectionsNavigation.isHittable, "Apps & accounts is present only in the background navigation stack.")
        try refusePermissionOrFixtureScreens()
    }

    private var connectionsNavigation: XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier IN %@ OR label IN %@",
            ["Apps & accounts", "Apps et comptes"], ["Apps & accounts", "Apps et comptes"])).firstMatch
    }

    private var isConnectionsPage: Bool {
        connectionsNavigation.exists && connectionsNavigation.isHittable && app.buttons["connections.gmailReader"].exists
    }

    private var gmailAPIConnection: XCUIElement {
        let identified = app.buttons["connections.account.gmail"]
        if identified.exists { return identified }
        // DisclosureGroup may propagate its identifier over the child link.
        return button(containing: ["Your email and the actions you choose.",
                                   "Vos e-mails et les actions que vous choisissez."])
    }

    private func returnToConnections(calendar: Bool = false) {
        guard !leaveGmailSignInPresented else { return }
        guard app.alerts.count == 0,
              XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count == 0 else { return }
        if isConnectionsPage { return }
        let calendarPage = app.navigationBars.matching(NSPredicate(format: "label IN %@", ["Your day", "Votre journée"]))
            .allElementsBoundByIndex.contains { $0.isHittable }
        if calendar || calendarPage {
            let done = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Terminé"])).firstMatch
            if done.exists && done.isHittable { done.tap() }
            if isConnectionsPage { return }
        }
        let knownPage = app.navigationBars.matching(NSPredicate(format: "label IN %@", [
            "Gmail", "Reminders", "Rappels", "Your day", "Votre journée"
        ])).allElementsBoundByIndex.contains { $0.isHittable }
        guard knownPage else { return }
        let back = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Apps & accounts", "Apps et comptes", "Back", "Retour"]))
            .allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY < 180 }
        back?.tap()
    }

    private func refusePermissionOrFixtureScreens() throws {
        if app.alerts.count > 0 || XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count > 0 {
            capture("real-phone-permission-or-alert-blocked")
            throw XCTSkip("A system permission or app alert requires the owner. No alert button was pressed.")
        }
        XCTAssertFalse(app.descendants(matching: .any)["qa.testWorkspace"].exists,
                       "An isolated test workspace cannot provide ordinary-data acceptance evidence.")
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists,
                       "Synthetic sources cannot provide real-phone acceptance evidence.")
    }

    private func button(labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func button(containing labels: [String]) -> XCUIElement {
        app.buttons.matching(NSCompoundPredicate(orPredicateWithSubpredicates:
            labels.map { NSPredicate(format: "label CONTAINS %@", $0) })).firstMatch
    }

    private func reveal(_ element: XCUIElement) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            guard scroll.exists else { break }
            if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "The expected read-only navigation control is not reachable.")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// Append this extension to RealPhoneConnectionAcceptanceTests.swift itself.
// It uses that file's existing private helpers; do not add it as a separate target source.
extension RealPhoneConnectionAcceptanceTests {
    func testPrepareReviewedSelfNoteForOwnerWithoutSending() throws {
        guard ProcessInfo.processInfo.environment["MO_REAL_PHONE_PREPARE_SELF_NOTE"] == "1" else {
            throw XCTSkip("Requires MO_REAL_PHONE_PREPARE_SELF_NOTE=1; no app was activated.")
        }
        // Existing no-navigation handoff guard: teardown must leave this live session alone.
        leaveGmailSignInPresented = true
        try activateOrdinaryApp()
        let homeControls = app.buttons["morning.actions"]
        guard homeControls.waitForExistence(timeout: 10), homeControls.isHittable else {
            throw XCTSkip("Leave ordinary MORE on Home before this reviewed-plan run.")
        }
        if ["Show controls", "Afficher les commandes"].contains(homeControls.label) { homeControls.tap() }
        let plan = app.buttons["morning.review"]
        try revealRoutineControl(plan)
        plan.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.waitForExistence(timeout: 10))
        let inventory = try inspectRoutineRows(name: "real-phone-self-note-plan-preflight")
        guard inventory.reachedEnd, Set(inventory.labels.keys) == Set(0..<8) else {
            throw XCTSkip("Exactly eight existing moments were not verified. No approval or run was started.")
        }
        let regex = try NSRegularExpression(pattern: #"^(.+?)[,\s]+(\d+)\s+min\s*·\s*(.+)$"#)
        var titles: [String] = []
        var durations: [Int] = []
        let manual = ["Moment personnel. Dites « suivant » lorsque vous avez terminé.", "Your own moment. Say “next” when you finish."]
        let gmail = ["Gmail · Lire vos mails non lus, préparer et corriger une réponse. Envoyer seulement à votre demande.", "Gmail · Read unread mail, prepare and edit a reply. Send only when you ask."]
        for index in 0..<8 {
            let label = inventory.labels[index] ?? ""
            guard let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
                  let titleRange = Range(match.range(at: 1), in: label),
                  let minutesRange = Range(match.range(at: 2), in: label),
                  let minutes = Int(label[minutesRange]) else {
                throw XCTSkip("A routine row could not be classified. No approval or run was started.")
            }
            titles.append(String(label[titleRange])); durations.append(minutes)
            guard (index == 5 ? gmail : manual).contains(where: label.contains) else {
                throw XCTSkip("An unexpected operation would run. The existing plan was not changed or started.")
            }
        }
        guard titles[5] == "Mail", durations[5] == 7, durations.reduce(0, +) == 45 else {
            throw XCTSkip("The expected Mail/seven-minute/45-minute plan was not verified.")
        }
        let approve = app.buttons["routine.approve"]
        if inventory.draft {
            try revealRoutineControl(approve)
            guard approve.isEnabled else { throw XCTSkip("Approval is unavailable; no run was started.") }
            approve.tap()
            XCTAssertTrue(approve.waitForNonExistence(timeout: 10), "The reviewed plan was not confirmed approved.")
        }

        // The Home entry uses the ordinary routine sheet, preserving Home behind it.
        if !inventory.draft {
            let close = app.buttons["destination.close"]
            guard close.exists && close.isHittable else { throw XCTSkip("The reviewed routine sheet cannot close normally.") }
            close.tap()
        }
        let controls = app.buttons["morning.actions"]
        guard controls.waitForExistence(timeout: 10), controls.isHittable else {
            throw XCTSkip("Ordinary Home did not return. No run was started.")
        }
        if ["Show controls", "Afficher les commandes"].contains(controls.label) { controls.tap() }
        let begin = app.buttons["morning.begin"]
        try revealRoutineControl(begin)
        guard begin.isEnabled else { throw XCTSkip("The approved morning is not ready to begin.") }
        begin.tap()
        try refusePermissionOrFixtureScreens()
        try prepareSelfNoteInActiveMorning(titles: titles)
    }

    func testContinueExistingMorningAndPrepareSelfNoteWithoutSending() throws {
        guard ProcessInfo.processInfo.environment["MO_REAL_PHONE_PREPARE_SELF_NOTE"] == "1" else {
            throw XCTSkip("Requires the separate self-note preparation opt-in; no app was activated.")
        }
        leaveGmailSignInPresented = true
        try activateOrdinaryApp()
        let controls = app.buttons["morning.actions"]
        guard controls.exists else { throw XCTSkip("The current ordinary session is not on Home.") }
        if ["Show controls", "Afficher les commandes"].contains(controls.label) { controls.tap() }
        XCTAssertTrue(app.staticTexts["morning.currentStep"].waitForExistence(timeout: 10), "No active morning was resumed; Start was not pressed.")
        try prepareSelfNoteInActiveMorning(titles: ["Calendar & weather", "iMessage", "WhatsApp", "WhatsApp Business", "Messenger", "Mail", "Scroll a little", "A thought for later"])
    }

    private func prepareSelfNoteInActiveMorning(titles: [String]) throws {
        let current = app.staticTexts["morning.currentStep"]
        let startingTitle = current.label
        guard startingTitle == titles[0] || startingTitle == "Mail" else {
            throw XCTSkip("The existing active morning is not at its verified first or Mail moment. It was not advanced.")
        }
        for index in (startingTitle == "Mail" ? 5 : 0)..<5 {
            XCTAssertTrue(selfNoteWait(current, predicate: NSPredicate(format: "exists == true AND label == %@", titles[index]), timeout: 15),
                          "The next title did not match the reviewed moment at index \(index). No extra Next was pressed.")
            try refusePermissionOrFixtureScreens()
            let next = app.buttons["morning.next"]
            try revealRoutineControl(next)
            next.tap()
        }
        XCTAssertTrue(selfNoteWait(current, predicate: NSPredicate(format: "exists == true AND label == %@", "Mail"), timeout: 15),
                      "Five Next actions did not reach the reviewed Mail moment.")
        guard !app.buttons["nativeMoment.cancel"].exists else {
            throw XCTSkip("A native request is still active. The mail dialogue was not changed.")
        }
        let unresolved = app.staticTexts.matching(NSPredicate(format:
            "identifier == %@ AND (label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@)",
            "moment.connectedResult", "L’envoi n’est pas confirmé", "Gmail a refusé l’envoi", "Une autre réponse a déjà été tentée")).firstMatch
        guard !unresolved.exists else { throw XCTSkip("An existing send requires reconciliation; no draft or retry was prepared.") }
        if !app.textFields["mail.selfSubject"].exists {
            // Foreground restoration preserves the paused moment while clearing
            // private mail text. Continue resumes that same moment, never Start.
            let remaining = app.staticTexts["morning.remaining"]
            if remaining.exists && remaining.label.range(of: #"^0+:00$"#, options: .regularExpression) != nil {
                let extend = app.buttons["morning.extend"]
                try revealRoutineControl(extend)
                extend.tap() // One ordinary +2 minute extension for this acceptance window.
            }
            let playback = app.buttons["morning.playback"]
            if playback.exists && (playback.label.contains("Continue") || playback.label.contains("Continuer")) {
                try revealRoutineControl(playback)
                playback.tap()
            }
            let compose = app.buttons["mail.composeSelf"]
            guard selfNoteWait(compose, predicate: NSPredicate(format: "exists == true AND enabled == true"), timeout: 45) else {
                try refusePermissionOrFixtureScreens()
                throw XCTSkip("The existing Gmail session did not offer self-note preparation. Session left in place.")
            }
            try revealRoutineControl(compose)
            compose.tap()
        }
        let recipient = app.staticTexts["mail.selfRecipient"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 20), "The own-profile recipient did not load.")
        let fixedRecipient = recipient.label
        XCTAssertTrue((fixedRecipient.hasPrefix("À vous-même : ") || fixedRecipient.hasPrefix("To yourself: ")) && fixedRecipient.contains("@"),
                      "A fixed own-profile recipient was not presented.")
        XCTAssertFalse(app.textFields["mail.selfRecipient"].exists, "The self-recipient must not be editable.")
        let subject = app.textFields["mail.selfSubject"]
        let body = app.textViews["mail.selfBody"]
        let send = app.buttons["mail.selfSend"]
        let exactSubject = "Test MORE"
        let exactBody = "Test d’automatisation MORE, vous pouvez ignorer ce message"
        XCTAssertTrue(selfNoteWait(subject, predicate: NSPredicate(format: "exists == true AND enabled == true"), timeout: 20), "Self-note fields did not become editable.")
        let priorSubject = subject.value as? String ?? ""
        let priorBody = body.value as? String ?? ""
        guard ["", "Subject", "Objet", exactSubject].contains(priorSubject),
              ["", exactBody].contains(priorBody), send.exists else {
            throw XCTSkip("The existing draft is edited or ambiguous. It was not overwritten or sent.")
        }
        if priorSubject == exactSubject && priorBody == exactBody && send.isEnabled {
            let ready = XCTAttachment(string: "Exact own-profile draft retained; completed review remains enabled. No edit or Send pressed.")
            ready.name = "real-phone-reviewed-self-note-retained-without-editing"
            ready.lifetime = .keepAlways; add(ready)
            return
        }
        guard !send.isEnabled else { throw XCTSkip("A different reviewed draft was not edited or sent.") }
        if priorSubject != exactSubject || priorBody != exactBody {
            try revealRoutineControl(subject, towardTopWhenMissing: true)
            subject.tap()
            if priorSubject != exactSubject { subject.typeText(exactSubject) }
            subject.typeText("\n")
            XCTAssertTrue(subject.value as? String == exactSubject, "Submitting Subject changed its exact text.")
            try revealRoutineControl(body)
            body.tap()
            if priorBody.isEmpty { body.typeText(exactBody) }
            routineScrollSurface.swipeDown()
        }
        XCTAssertTrue(subject.value as? String == exactSubject && body.value as? String == exactBody,
                      "The exact authorized subject and body were not entered. Nothing was sent.")
        XCTAssertTrue(recipient.label == fixedRecipient && !send.isEnabled, "The recipient changed or Send enabled before review.")
        let review = app.buttons["mail.selfReview"]
        try revealRoutineControl(review)
        review.tap()
        let ready = waitForReviewedSelfNote(send)
        guard ready else {
            throw XCTSkip("Reviewed-send readiness was not confirmed; the app/session was preserved and no Send was pressed.")
        }
        try refusePermissionOrFixtureScreens()
        XCTAssertTrue(recipient.label == fixedRecipient && subject.value as? String == exactSubject && body.value as? String == exactBody,
                      "The recipient or exact draft changed during review. Nothing was sent.")
        let voice = app.staticTexts["morning.voiceStatus"]
        let readiness = XCTAttachment(string: "Reviewed draft Send enabled: \(ready)\nVoice status: \(voice.exists ? String(voice.label.prefix(256)) : "not exposed")\nNo Send pressed. Ordinary app/session preserved for the owner.")
        readiness.name = "real-phone-self-note-owner-handoff-readiness-only"
        readiness.lifetime = .keepAlways
        add(readiness)
        guard ready else { throw XCTSkip("The exact draft is prepared, but completed review was not confirmed. Session left in place for the owner.") }
        // STOP HERE. Do not tap Send, type a send command, advance, pause, stop or relaunch.
        // The owner separately says “send” once for acoustic acceptance.
    }

    private func waitForReviewedSelfNote(_ send: XCUIElement) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 45
        var reopenedHomePanel = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard app.state == .runningForeground else { return false }
            if send.exists && send.isEnabled { return true }
            let controls = app.buttons["morning.actions"]
            if !reopenedHomePanel, controls.exists, controls.isHittable,
               ["Show controls", "Afficher les commandes"].contains(controls.label) {
                controls.tap(); reopenedHomePanel = true
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        return false
    }

    private func selfNoteWait(_ element: XCUIElement, predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

import XCTest

/// Explicitly opted-in ordinary-phone acceptance; never use fixtures.
/// This test creates and completes exactly its own dated QA item.
/// No screenshots, attachments, mailbox data, or other reminder labels are logged.
@MainActor
final class RealPhoneDisposableReminderEffectTests: XCTestCase {
    private let qaTitle = "MORE QA 2026-10-15 2244 8C6F1A"
    private var app: XCUIApplication!
    private var currentMoment: String?
    private var additionTapped = false
    private var completionTapped = false

    func testOneDisposableReminderThroughExistingNativeMoment() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_REAL_PHONE_CONNECTIONS"] == "1",
              environment["MO_REAL_PHONE_DISPOSABLE_REMINDER"] == "1" else {
            throw XCTSkip("Explicit physical-phone and disposable-reminder opt-ins are required.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the owner's existing ordinary physical-phone session.")
        #else
        guard let bundle = environment["MO_REAL_PHONE_BUNDLE_ID"],
              bundle.hasPrefix("com.gibouu.morningoperator."),
              !bundle.lowercased().contains("fixture"), !bundle.lowercased().contains(".qa") else {
            throw XCTSkip("Requires the explicit installed personal MORE bundle.")
        }
        app = XCUIApplication(bundleIdentifier: bundle)
        app.activate() // No launch, termination, launch arguments, or environment injection.
        try require(app.wait(for: .runningForeground, timeout: 10), "Ordinary MORE did not become foreground.")
        try guardOrdinaryState()
        let moment = app.staticTexts["morning.currentStep"]
        if moment.exists { currentMoment = moment.label } // Kept in memory; never printed.

        // An existing web moment exposes this same native panel in a sheet. Do
        // not close the browser, start a routine, advance a moment, or resume it.
        if !native("nativeMoment.open").exists {
            let open = app.buttons["web.nativeRequest"]
            guard open.exists && open.isHittable else {
                throw XCTSkip("Leave the existing active morning on Home or its native-request control.")
            }
            open.tap()
            try require(native("nativeMoment.request").waitForExistence(timeout: 10), "The current native-request panel did not open.")
        }
        if !native("nativeMoment.request").exists {
            let open = native("nativeMoment.open")
            try revealInNativePanel(open)
            open.tap()
        }
        try require(native("nativeMoment.request").waitForExistence(timeout: 10), "No active native-moment editor is available.")
        try guardOrdinaryState()
        // Never replace an owner's pending action, or retry a prior ambiguous QA
        // action. Close/reconcile it manually before deliberately running again.
        try require(!app.buttons["nativeMoment.cancel"].exists && !native("nativeMoment.status").exists,
                    "A native request already exists. Stop and reconcile it; no new request was submitted.")

        try prepare("Rappelle-moi de \(qaTitle) dans deux heures")
        try require(native("nativeMoment.title").waitForExistence(timeout: 20), "No QA draft appeared; no addition was pressed.")
        try require(native("nativeMoment.title").value as? String == qaTitle, "The proposed title is not exactly the unique QA title.")
        let dated = app.switches.matching(NSPredicate(format: "label IN %@", ["Date et heure", "Date and time"])).firstMatch
        try require(dated.exists && dated.value as? String == "1" && native("nativeMoment.date").exists,
                    "The QA reminder is not visibly dated; no addition was pressed.")
        try require(reviewMatchesQA(creation: true), "The QA date, alert, destination, and title review is incomplete.")
        try acknowledgeAndConfirm(creation: true)
        try waitForStatus(NSPredicate(format:
            "label CONTAINS %@ AND (label CONTAINS %@ OR label CONTAINS %@)",
            qaTitle, "a été ajouté dans Rappels Apple", "was added to Apple Reminders"),
            failure: "Addition was pressed once but its receipt is unconfirmed. Check only this QA item manually; do not retry.")

        try completeCreatedQAReminder()
        #endif
    }

    func testCompleteOnlyPreviouslyCreatedQAAfterFreshReading() throws {
        continueAfterFailure = false
        let e = ProcessInfo.processInfo.environment
        guard e["MO_REAL_PHONE_CONNECTIONS"] == "1", e["MO_REAL_PHONE_COMPLETE_EXISTING_QA_REMINDER"] == "1",
              let bundle = e["MO_REAL_PHONE_BUNDLE_ID"], bundle.hasPrefix("com.gibouu.morningoperator."),
              !bundle.lowercased().contains(".qa"), !bundle.lowercased().contains("fixture") else {
            throw XCTSkip("Explicit physical-phone and existing-QA-only completion opt-ins required.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the existing ordinary physical phone.")
        #else
        app = XCUIApplication(bundleIdentifier: bundle)
        app.activate()
        try require(app.wait(for: .runningForeground, timeout: 10), "Ordinary MORE did not become foreground.")
        try guardOrdinaryState()
        let moment = app.staticTexts["morning.currentStep"]
        try require(moment.exists && moment.label == "Mail", "The original Mail moment is no longer current.")
        currentMoment = moment.label
        let status = native("nativeMoment.status")
        try require(status.exists && status.label.contains(qaTitle) &&
            (status.label.contains("was added to Apple Reminders") || status.label.contains("a été ajouté dans Rappels Apple")),
            "The original QA creation receipt is absent. No creation or completion was repeated.")
        // The existing receipt identifies the one QA item created by the prior run.
        additionTapped = true
        try completeCreatedQAReminder()
        #endif
    }

    private func completeCreatedQAReminder() throws {
        try readReminders()
        let qa = qaReminderButtons
        try require(qa.count == 1,
                    "The fresh first-five reading does not expose exactly one QA item. No completion was pressed; inspect this QA item manually.")
        let selected = qa.firstMatch
        try revealInNativePanel(selected)
        try guardOrdinaryState()
        // Re-evaluate the exact-title query immediately before selection.
        try require(qaReminderButtons.count == 1 && selected.isHittable,
                    "The unique QA selection changed; no completion was pressed.")
        selected.tap()
        try require(app.buttons["nativeMoment.confirm"].waitForExistence(timeout: 15), "No completion review appeared.")
        try require(reviewMatchesQA(creation: false), "The completion review does not name exactly the QA item.")
        try acknowledgeAndConfirm(creation: false)
        try waitForStatus(NSPredicate(format:
            "label CONTAINS %@ AND (label CONTAINS %@ OR label CONTAINS %@)",
            qaTitle, "a été marqué comme terminé", "was marked complete"),
            failure: "Completion was pressed once but its receipt is unconfirmed. Stop; do not retry or select another reminder.")

        try readReminders()
        try require(qaReminderButtons.count == 0, "The freshly read QA item is still incomplete. Do not retry completion.")
        try guardOrdinaryState()
        // Close only the request created by this test; keep the same morning
        // paused so its existing mail draft can be reviewed again separately.
        let close = app.buttons["nativeMoment.cancel"]
        try revealInNativePanel(close)
        try require(close.exists && close.isHittable, "The completed QA request cannot close normally.")
        close.tap()
        try require(native("nativeMoment.status").waitForNonExistence(timeout: 10), "The owned QA request did not close.")
    }

    private func native(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var qaReminderButtons: XCUIElementQuery {
        let exact = "^[1-5]\\. " + NSRegularExpression.escapedPattern(for: qaTitle) + "$"
        return app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label MATCHES %@", "nativeMoment.reminder.", exact))
    }

    private func prepare(_ text: String) throws {
        try guardOrdinaryState()
        let field = native("nativeMoment.request")
        try require(app.descendants(matching: .any).matching(identifier: "nativeMoment.request").count == 1,
                    "The current native editor is ambiguous.")
        try revealInNativePanel(field)
        let value = field.value as? String ?? ""
        try require(["", "Votre demande", "Your request"].contains(value), "An existing unsubmitted request must not be overwritten.")
        field.tap()
        field.typeText(text)
        try require(field.value as? String == text, "The exact QA command was not entered; it was not submitted.")
        let button = app.buttons["nativeMoment.prepare"]
        try revealInNativePanel(button)
        try require(button.isEnabled, "The native request is not ready to prepare.")
        button.tap() // Preparation/read only: never a write confirmation.
        try guardOrdinaryState()
    }

    private func readReminders() throws {
        try prepare("lis mes rappels")
        try waitForStatus(NSPredicate(format:
            "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Voici les cinq premiers rappels au maximum,", "Here are up to the first five reminders",
            "Aucun rappel incomplet et daté dans les sept prochains jours", "No incomplete dated reminders in the next seven days"),
            failure: "A fresh reminder reading was not confirmed. Stop without selecting any reminder.")
        try require(!app.buttons["nativeMoment.confirm"].exists, "The reader unexpectedly still offers an old write confirmation.")
    }

    private func reviewMatchesQA(creation: Bool) -> Bool {
        let status = native("nativeMoment.status")
        guard status.exists else { return false }
        let text = status.label
        guard text.contains("« \(qaTitle) »") || text.contains("“\(qaTitle)”") else { return false }
        if creation {
            return (text.hasPrefix("Ajouter le rappel") || text.hasPrefix("Add reminder")) &&
                (text.contains("Échéance ") || text.contains("Due ")) &&
                (text.contains("fuseau ") || text.contains("time zone ")) &&
                (text.contains("avec alerte") || text.contains("with alert")) &&
                (text.contains(", compte ") || text.contains(", account "))
        }
        return (text.hasPrefix("Marquer ") || text.hasPrefix("Mark ")) &&
            (text.contains("comme terminé") || text.contains("complete in")) &&
            (text.contains(", compte ") || text.contains(", account "))
    }

    private func acknowledgeAndConfirm(creation: Bool) throws {
        try guardOrdinaryState()
        let confirm = app.buttons["nativeMoment.confirm"]
        try require(confirm.waitForExistence(timeout: 15), "No explicit QA confirmation is available.")
        if !confirm.isEnabled {
            let reviewed = app.buttons["nativeMoment.reviewed"]
            try require(reviewed.waitForExistence(timeout: 10), "The QA review has not completed and cannot be acknowledged.")
            try revealInNativePanel(reviewed)
            try require(reviewMatchesQA(creation: creation), "The reviewed QA action changed before screen acknowledgement.")
            reviewed.tap() // Explicit screen review; no write yet.
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        try require(XCTWaiter.wait(for: [ready], timeout: 10) == .completed, "The explicit QA confirmation stayed disabled.")
        try revealInNativePanel(confirm)
        try guardOrdinaryState()
        try require(reviewMatchesQA(creation: creation), "The reviewed QA action changed before committing.")
        let allowed = creation ? ["Confirmer l’ajout", "Confirm addition"] : ["Confirmer : marquer terminé", "Confirm: mark complete"]
        try require(allowed.contains(confirm.label), "The confirmation is for the wrong effect.")
        if creation {
            try require(!additionTapped, "A second addition is forbidden.")
            additionTapped = true
        } else {
            try require(additionTapped && !completionTapped, "Only one completion of this created QA item is permitted.")
            completionTapped = true
        }
        confirm.tap() // Exactly one tap for this effect. No retry under any outcome.
    }

    private func waitForStatus(_ predicate: NSPredicate, failure: String) throws {
        let observed = XCTNSPredicateExpectation(predicate: predicate, object: native("nativeMoment.status"))
        try require(XCTWaiter.wait(for: [observed], timeout: 30) == .completed, failure)
        try guardOrdinaryState()
    }

    /// Scroll only an ancestor of this native panel, never the app or an
    /// unrelated first scroll view. No swipe can activate a write control.
    private func revealInNativePanel(_ element: XCUIElement) throws {
        for _ in 0..<18 {
            if element.exists && element.isHittable { return }
            let candidates = app.scrollViews.containing(.any, identifier: "nativeMoment.open").allElementsBoundByIndex
            guard let panel = candidates.filter({ $0.exists && $0.frame.width > 0 && $0.frame.height > 0 })
                .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { break }
            let towardTop = element.exists && element.frame.midY < panel.frame.midY
            let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: towardTop ? 0.35 : 0.65))
            let end = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: towardTop ? 0.65 : 0.35))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        try require(element.exists && element.isHittable, "The current native-panel control is not reachable; no global navigation was attempted.")
    }

    private func guardOrdinaryState() throws {
        try require(app.state == .runningForeground, "MORE left the foreground; stop without retrying an effect.")
        try require(app.alerts.count == 0 && XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count == 0,
                    "A permission or alert requires the owner. No alert control was pressed.")
        try require(!native("qa.testWorkspace").exists && !native("nativeMoment.synthetic").exists,
                    "Synthetic workspaces cannot establish a real Apple effect.")
        if let currentMoment {
            try require(app.staticTexts["morning.currentStep"].exists && app.staticTexts["morning.currentStep"].label == currentMoment,
                        "The current moment changed; stop without advancing or creating another action.")
        }
    }

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ReminderEffectStopped(message: message) }
    }
}

private struct ReminderEffectStopped: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Observation only: no tap, typing, screenshot, provider call, explicit launch or termination.
extension RealPhoneConnectionAcceptanceTests {
    func testObserveOwnerSelfSendWithoutInteracting() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_REAL_PHONE_OBSERVE_SELF_SEND"] == "1",
              environment["MO_REAL_PHONE_CONNECTIONS"] == "1" else {
            throw XCTSkip("Explicit ordinary-phone/self-send observation opt-ins are required.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical ordinary iPhone only.")
        #else
        guard let bundle = environment["MO_REAL_PHONE_BUNDLE_ID"],
              bundle.hasPrefix("com.gibouu.morningoperator."),
              !bundle.lowercased().contains("fixture"), !bundle.lowercased().contains(".qa") else {
            throw XCTSkip("The explicit ordinary installed bundle is required.")
        }
        leaveGmailSignInPresented = true // Existing no-navigation teardown handoff guard.
        let deadline = ProcessInfo.processInfo.systemUptime + 55
        app = XCUIApplication(bundleIdentifier: bundle)
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 10) else {
            throw XCTSkip("The existing ordinary app did not become foreground.")
        }
        guard !app.descendants(matching: .any)["qa.testWorkspace"].exists,
              !app.staticTexts["briefing.synthetic"].exists else {
            throw XCTSkip("A synthetic workspace cannot establish owner-send evidence.")
        }

        let current = app.staticTexts["morning.currentStep"]
        let subject = app.textFields["mail.selfSubject"]
        let body = app.textViews["mail.selfBody"]
        let draftExact = current.exists && current.label == "Mail" && subject.exists && body.exists
            && subject.value as? String == "Test MORE"
            && body.value as? String == "Test d’automatisation MORE, vous pouvez ignorer ce message"
        let fixedRecipientControl = app.staticTexts["mail.selfRecipient"].exists
            && !app.textFields["mail.selfRecipient"].exists
        let receipt = app.staticTexts.matching(NSPredicate(format:
            "identifier == %@ AND label BEGINSWITH %@", "moment.connectedResult", "Gmail confirme l’envoi de votre mail à ")).firstMatch
        let unresolved = app.staticTexts.matching(NSPredicate(format:
            "identifier == %@ AND (label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@)",
            "moment.connectedResult", "L’envoi n’est pas confirmé", "Gmail a refusé l’envoi", "Une autre réponse a déjà été tentée")).firstMatch
        var providerReceiptObserved = false
        var uncertainOrRefusedObserved = false
        var advancedAwayFromMail = current.exists && current.label != "Mail"
        var alertObserved = app.alerts.count > 0 || XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count > 0
        var voiceStatus = "not_sampled"
        // A completed/skipped moment or an aggregate recap cannot establish a provider send.
        while draftExact && fixedRecipientControl && ProcessInfo.processInfo.systemUptime < deadline {
            alertObserved = app.alerts.count > 0 || XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count > 0
            if alertObserved { break } // Never capture or accept the alert.
            if receipt.exists { providerReceiptObserved = true; break }
            uncertainOrRefusedObserved = unresolved.exists
            let voice = app.staticTexts["morning.voiceStatus"]
            if voice.exists {
                let status = voice.label.lowercased() // Classified in memory; raw text is never retained.
                if status.contains("autorisation") || status.contains("permission") { voiceStatus = "permission_status" }
                else if status.contains("écoute") || status.contains("listening") { voiceStatus = "listening_status" }
                else { voiceStatus = "other_status" }
            }
            advancedAwayFromMail = current.exists && current.label != "Mail"
            if uncertainOrRefusedObserved || advancedAwayFromMail { break }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { RunLoop.current.run(until: Date(timeIntervalSinceNow: min(1, remaining))) }
        }
        let evidence = XCTAttachment(string: [
            "Exact authorized self-note observed: \(draftExact)",
            "Fixed read-only recipient control observed: \(fixedRecipientControl)",
            "Explicit Gmail provider receipt observed: \(providerReceiptObserved)",
            "Uncertain/refused state observed: \(uncertainOrRefusedObserved)",
            "Already advanced or advanced away from Mail: \(advancedAwayFromMail)",
            "Alert observed: \(alertObserved)",
            "Public voice-status classification: \(voiceStatus)",
            "No tap, typing, Send, retry, advance, new session or receipt-text retention."
        ].joined(separator: "\n"))
        evidence.name = "real-phone-acoustic-self-send-observation-booleans-only"
        evidence.lifetime = .keepAlways
        add(evidence)
        guard providerReceiptObserved else {
            throw XCTSkip("No explicit Gmail provider receipt was observed for the verified draft. UI sending remains unproven; inspect the existing receipt journal separately without retrying.")
        }
        #endif
    }
}
