import XCTest

/// Physical acceptance through the ordinary UI and real selected model. The operator
/// must back up the actual owner container first, then restore it after this test.
/// No workspace, model result, clock, provider response or authorization is injected.
@MainActor
final class OrdinaryRoutineAcceptanceTests: XCTestCase {
    private let bundle = "com.gibouu.morningoperator"
    private let weatherTitle = "MORE QA · Paris weather"
    private let browserTitle = "MORE QA · Public Reddit"
    private let timedTitle = "MORE QA · Getting ready"

    /// Run before the owner backup is frozen. The optional key belongs only to
    /// the private test runner; no app launch environment or fixture is used.
    func testConfigureOrdinarySelectedModelIfRequested() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_MODEL_SETUP"] == "1",
                          "Requires explicit ordinary model setup; private runner logs must be protected.")
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the ordinary physical iPhone.")
        #else
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.terminate()
        app.launch()
        defer { app.terminate() }
        try require(app.wait(for: .runningForeground, timeout: 15), "The ordinary app did not launch for model setup.")
        try refuseFixtures(app)
        try openSettings(app)
        try require(!app.buttons["morning.stop"].exists, "An owner morning is active; its model selection was not changed.")
        let route = try verifySelectedModel(app, configureIfNeeded: true)
        let note = XCTAttachment(string: "Ordinary UI active model verified: \(route). No model request or fixture result was injected. No credential attached; take the owner-state backup after setup.")
        note.name = "ordinary-selected-model-setup"
        note.lifetime = .keepAlways
        add(note)
        #endif
    }

    func testRealLearningApprovalAndAutomaticRoutinePersistTheirRecap() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["MORE_PHYSICAL_ROUTINE_ACCEPTANCE"] == "1",
                          "Requires explicit ordinary physical routine acceptance.")
        try XCTSkipUnless(environment["MORE_PHYSICAL_OWNER_BACKUP_VERIFIED"] == "1",
                          "Requires a verified private backup of the actual owner state and an operator restoration plan.")
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the ordinary physical iPhone.")
        #else
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.terminate()
        app.launch()
        defer { app.terminate() }
        try require(app.wait(for: .runningForeground, timeout: 15), "The ordinary app did not launch.")
        try refuseFixtures(app)
        try openSettings(app)
        try require(!app.buttons["morning.stop"].exists,
                    "An owner morning is active. Stop before changing any plan or settings.")
        let modelRoute = try verifySelectedModel(app)
        try setSwitch("setup.handsFree", on: true, in: app)
        try setSwitch("setup.readAloud", on: true, in: app)
        try configurePublicWeather(app)
        try openLearnFromSettings(app)

        // Clear only a lesson created by this test to obtain a new notes editor.
        // Learn's Clear action deletes its selected observation; it must never be
        // used on the owner's pre-existing selected entry.
        try saveRealRedditLesson(app)
        let source = app.staticTexts["learn.observationSource"]
        try reveal(source, in: app)
        try require(source.label.contains("Reddit"), "The disposable QA browser lesson was not selected.")
        try tap("learn.clear", in: app)
        let notes = app.textViews["learn.notes"]
        try reveal(notes, in: app)
        try require((notes.value as? String ?? "").isEmpty,
                    "The QA lesson was not cleared into a blank observation editor.")
        let intent = "I checked the current weather for Paris, France and scrolled the public Reddit feed in MORE. " +
            "For this short acceptance morning, I want the current Paris weather, one minute browsing Reddit, " +
            "then one minute getting ready. Do not like, send, post or change anything on Reddit."
        notes.tap()
        notes.typeText(intent)
        try tap("input.done", in: app)
        try tap("learn.observationDetails", in: app)
        try choose("observation.originPicker", labels: ["My morning", "Ma matinée"], in: app)
        // The normal date editor opens on today's real date and current zone.
        try require(element("observation.datePicker", in: app).exists,
                    "The actual observed-day editor was unavailable.")
        try tap("observation.saveDate", in: app)
        try require(!app.staticTexts["learn.fixtureMode"].exists, "Synthetic learning cannot establish acceptance.")

        // A separate unedited browser lesson plus typed intent forces the real
        // selected-model branch, rather than structured-evidence-only assembly.
        try saveRealRedditLesson(app)
        try tap("learn.savedObservations", in: app)
        try tap("observations.choose", in: app)
        let selectionSummary = app.staticTexts["observations.selectionSummary"]
        try reveal(selectionSummary, in: app)
        try require(selectionSummary.label.range(of: #"^0 observations? (?:across|sur) 0 (?:dated days?|jours? datés?)$"#, options: .regularExpression) != nil &&
                    !app.buttons["observations.clearSelection"].exists,
                    "The archive must begin with no selected observation. No proposal request was made.")
        let selections = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "observation.select."))
        try reveal(selections.firstMatch, in: app)
        try require(selections.count >= 2, "The two real QA observations were not saved.")
        // Pin identities before scrolling can change the virtualized row order.
        let browserID = selections.element(boundBy: 0).identifier
        let manualID = selections.element(boundBy: 1).identifier
        let browser = app.buttons[browserID]
        let manual = app.buttons[manualID]
        try require(browser.label.contains("Reddit") &&
                    ["Your written observation", "Votre observation écrite"].contains(where: manual.label.contains),
                    "The newest observations were not the QA browser lesson and separate typed intent. No owner source was selected.")
        let manualRowID = manualID.replacingOccurrences(of: "observation.select.", with: "observation.row.")
        try tap(manualRowID, in: app)
        let currentNotes = app.buttons.matching(NSPredicate(format: "label IN %@", ["Current notes", "Notes actuelles"])).firstMatch
        try reveal(currentNotes, in: app); currentNotes.tap()
        let savedIntent = app.staticTexts["observation.currentText"]
        try reveal(savedIntent, in: app)
        try require(savedIntent.label == intent, "The candidate typed source is not the exact public QA intent. No proposal request was made.")
        try back(until: app.buttons["observations.suggestUpdate"], in: app)
        try reveal(browser, in: app); browser.tap()
        try reveal(manual, in: app); manual.tap()
        try require(["Selected", "Sélectionnée", "Sélectionné"].contains(browser.value as? String ?? "") &&
                    ["Selected", "Sélectionnée", "Sélectionné"].contains(manual.value as? String ?? ""),
                    "Both real observations must be explicitly selected.")
        try require(!app.staticTexts["observations.fixtureMode"].exists, "The archive is using synthetic proposal output.")
        let suggest = app.buttons["observations.suggestUpdate"]
        try reveal(suggest, in: app)
        try require(selectionSummary.label.range(of: #"^2 observations (?:across|sur) 1 (?:dated day|jour daté)$"#, options: .regularExpression) != nil,
                    "Exactly the two same-day QA sources must be selected before any model request.")
        try require(suggest.isEnabled, "The selected real observations cannot reach the selected model.")
        suggest.tap()
        try require(app.buttons["proposal.edit"].waitForExistence(timeout: 150),
                    "The selected model did not produce a reviewable proposal. Inspect the ordinary model/provider error; no result was injected.")
        try require(!app.staticTexts["proposal.fixtureMode"].exists, "A synthetic proposal is not real model evidence.")
        let sources = app.staticTexts["proposal.sources"]
        try reveal(sources, in: app)
        try require(sources.label.range(of: #"\b2\b"#, options: .regularExpression) != nil,
                    "The proposal did not retain both selected real sources.")
        try tap("proposal.edit", in: app)
        try require(app.buttons["routine.approve"].waitForExistence(timeout: 10),
                    "Model output must become an editable unapproved draft.")
        try reviewThreeMoments(app)
        try tap("routine.approve", in: app)
        try returnHome(app)
        try revealHomeControls(app)
        try tap("morning.begin", in: app)

        var withoutListening = false
        if app.buttons["voice.access.withoutListening"].waitForExistence(timeout: 5) {
            // This is the ordinary explicit product choice, never an injected mic grant.
            // Button interruption below is verified separately from acoustic input.
            try tap("voice.access.withoutListening", in: app)
            withoutListening = true
        }
        // Hands-free must leave the opening and finish the real spoken briefing
        // before entering Reddit. No opening, Next or skip control is pressed.
        try require(app.buttons["web.pause"].waitForExistence(timeout: 150),
                    "The opening/real briefing did not automatically hand over to the approved Reddit moment.")
        let status = app.staticTexts["web.result"]
        try wait(45, message: "The real public page yielded no observed content; a sign-in/privacy/provider blocker must be resolved.") {
            self.observedCount(status.label) > 0
        }
        try require(app.staticTexts["web.host"].label == "www.reddit.com", "The approved public Reddit page was not the active browser.")
        let observedBeforePause = observedCount(status.label)
        try tap("web.pause", in: app)
        try require(app.buttons["web.resume"].waitForExistence(timeout: 5), "The live browser did not pause.")
        let frozen = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 2)
        try require(app.staticTexts["web.remaining"].label == frozen, "The actual remaining budget changed while paused.")
        try require(observedCount(status.label) == observedBeforePause,
                    "Observed-content progress changed while paused.")
        try tap("web.resume", in: app)
        try require(app.buttons["web.pause"].waitForExistence(timeout: 5), "The same browser moment did not resume.")
        try require(observedCount(status.label) >= observedBeforePause, "Resume lost observed browser progress.")
        try require(MorningUITestNavigation.waitForCompletedMorning(in: app, timeout: 170),
                    "The real one-minute browser and timed moment did not complete automatically. No Next/skip was pressed.")
        try openSettings(app)
        try verifyExecutionSummary(app)
        try tap("setup.history", in: app)
        try verifyRecap(app)

        app.terminate()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        try require(app.wait(for: .runningForeground, timeout: 15), "The ordinary app did not relaunch.")
        try refuseFixtures(app)
        try require(MorningUITestNavigation.waitForCompletedMorning(in: app, timeout: 10), "The completed routine did not survive a cold relaunch.")
        try openSettings(app)
        try verifyExecutionSummary(app)
        try tap("setup.history", in: app)
        try verifyRecap(app)
        let note = XCTAttachment(string: "Ordinary physical UI; real Paris Maps/Weather source, real Reddit gesture learning and separate typed intent; selected \(modelRoute) model produced a two-source editable proposal; three actions reviewed and approved; actual spoken briefing, observed public-feed content, one pause/resume with frozen budget, automatic browser/timed completion without Next, and saved recap after cold launch. " +
            (withoutListening ? "Explicit Begin without listening was used; no acoustic microphone claim." : "Existing listening preparation was retained; this test does not prove acoustic recognition.") +
            " Operator must now restore the verified pre-test owner backup. No private content or credentials attached.")
        note.name = "ordinary-real-routine-acceptance"
        note.lifetime = .keepAlways
        add(note)
        #endif
    }

    private func verifySelectedModel(_ app: XCUIApplication, configureIfNeeded: Bool = false) throws -> String {
        try tap("setup.intelligence", in: app)
        let summary = app.staticTexts["intelligence.status"]
        try require(summary.waitForExistence(timeout: 10), "The active model could not be inspected.")
        let localStatuses = [
            "The Apple model runs on this device. No text is sent to OpenAI.",
            "Le modèle Apple fonctionne sur cet appareil. Aucun texte n’est envoyé à OpenAI."
        ]
        let cloudStatuses = [
            "OpenAI GPT-6 Luna is enabled with high reasoning. Text needed for analysis and conversation is sent to OpenAI. Videos stay on this device.",
            "OpenAI GPT-6 Luna est activé, avec un raisonnement élevé. Les textes utiles à l’analyse et à la conversation sont envoyés à OpenAI. Les vidéos restent sur l’appareil."
        ]
        if configureIfNeeded, !localStatuses.contains(summary.label), !cloudStatuses.contains(summary.label) {
            guard let key = ProcessInfo.processInfo.environment["MORE_PHYSICAL_OPENAI_KEY"],
                  key.hasPrefix("sk-"), (20...512).contains(key.utf8.count),
                  key.utf8.allSatisfy({ (33...126).contains($0) }) else {
                try require(false, "No model is available and no valid private runner credential was supplied. No selection was changed.")
                return "unavailable"
            }
            let field = app.secureTextFields["intelligence.apiKey"]
            try reveal(field, in: app)
            try require(field.exists && field.isHittable && field.isEnabled, "The ordinary secure model configuration field was unavailable.")
            field.tap()
            field.typeText(key)
            try setSwitch("intelligence.consent", on: true, in: app)
            try tap("intelligence.enable", in: app)
            try wait(10, message: "Explicit ordinary OpenAI configuration did not produce the expected selected-model status.") {
                cloudStatuses.contains(summary.label) && !app.staticTexts["intelligence.issue"].exists
            }
        }
        let local = localStatuses.contains(summary.label)
        let cloud = cloudStatuses.contains(summary.label)
        try require(local != cloud, "No unambiguous available model is selected. Configure Apple Intelligence or explicitly enable OpenAI in the ordinary UI before retrying.")
        if cloud {
            // This button changes back to Apple; it never establishes local availability.
            let useLocal = app.buttons["intelligence.local"]
            try reveal(useLocal, in: app)
            try require(useLocal.exists && useLocal.isEnabled && !app.staticTexts["intelligence.issue"].exists,
                        "The explicit OpenAI status does not match an operable selected route.")
        }
        try back(until: app.buttons["setup.intelligence"], in: app)
        return cloud ? "OpenAI GPT-6 Luna (high reasoning)" : "local Apple"
    }

    private func configurePublicWeather(_ app: XCUIApplication) throws {
        try tap("setup.briefing", in: app)
        try require(!app.staticTexts["briefing.synthetic"].exists, "Weather must use the native provider.")
        // The operator restores the exact previous source selections after proof.
        try disableCalendarSelections(app)
        try setSwitch("briefing.healthIncluded", on: false, in: app)
        for kind in ["sleep", "steps", "screenTime", "weatherChange", "calendar", "birthday"] {
            let toggle = app.switches["extras.\(kind)"]
            try reveal(toggle, in: app)
            if toggle.value as? String == "1" { try require(toggle.isEnabled, "An enabled extra could not be turned off for the public-data run."); toggle.tap() }
        }
        try choose("briefing.locationSource", labels: ["Choose a city", "Choisir une ville"], in: app)
        if app.buttons["briefing.removeWeather"].exists { try tap("briefing.removeWeather", in: app) }
        let search = app.textFields["briefing.citySearch"]
        try replace(search, with: "Paris, France", in: app)
        try tap("briefing.searchCities", in: app)
        let paris = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@ AND label CONTAINS[cd] %@",
            "briefing.cityResult.", "Paris", "France")).firstMatch
        try require(paris.waitForExistence(timeout: 30), "Apple Maps did not return the public Paris, France city.")
        try reveal(paris, in: app); paris.tap()
        let attribution = element("weather.sources", in: app)
        try wait(40, message: "Apple Weather did not admit a real attributed Paris snapshot.") { attribution.exists }
        try reveal(attribution, in: app)
        try require(!app.staticTexts["briefing.error"].exists, "The ordinary weather source reported an error.")
        let done = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Terminé"])).firstMatch
        try require(done.exists && done.isHittable, "The ordinary source sheet could not close.")
        done.tap()
        try require(app.buttons["setup.routine"].waitForExistence(timeout: 10), "Settings did not return after source setup.")
    }

    private func disableCalendarSelections(_ app: XCUIApplication) throws {
        let scrolls = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
        guard let scroll = scrolls.first(where: \.isHittable) else {
            try require(false, "The ordinary Calendar source inventory could not be scrolled.")
            return
        }
        // This fresh form starts above Calendar. Small overlapping scrolls visit
        // virtualized switches until the following Health section is reached.
        for _ in 0..<30 {
            let calendars = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "briefing.calendar."))
            for calendar in calendars.allElementsBoundByIndex where calendar.isHittable {
                try require(["0", "1"].contains(calendar.value as? String ?? ""),
                            "A native calendar selection had no readable on/off state.")
                if calendar.value as? String == "1" {
                    try require(calendar.isEnabled, "A selected native calendar could not be disabled for the public-data run.")
                    calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                }
                try wait(6, message: "A native calendar remained selected for the public-data run.") {
                    calendar.value as? String == "0"
                }
            }
            let clearUnavailable = app.buttons.matching(NSPredicate(format: "label IN %@", [
                "Clear calendar selection", "Effacer la sélection de calendriers"
            ])).firstMatch
            if clearUnavailable.exists && clearUnavailable.isHittable {
                try require(clearUnavailable.isEnabled, "Unavailable saved calendar selections could not be cleared.")
                clearUnavailable.tap()
                try require(clearUnavailable.waitForNonExistence(timeout: 5), "Unavailable calendar selections remained saved.")
            }
            let health = app.switches["briefing.healthIncluded"]
            if health.exists && health.isHittable { return }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        try require(false, "The complete Calendar inventory was not traversed; the public-data run must not start.")
    }

    /// Called from Learn; the site session is real and only public browsing is performed.
    private func saveRealRedditLesson(_ app: XCUIApplication) throws {
        try tap("learn.connections", in: app)
        try tap("connections.moreWebsites", in: app)
        try tap("connections.reddit", in: app)
        try require(app.buttons["connections.confirmReady"].waitForExistence(timeout: 20), "The ordinary Reddit setup page did not open.")
        try require(app.staticTexts["web.host"].label == "www.reddit.com", "Reddit setup opened an unexpected site.")
        try tap("connections.confirmReady", in: app)
        let learn = app.buttons.matching(NSPredicate(format: "label IN %@", ["Learn my pace in Reddit", "Apprendre mon rythme sur Reddit"])).firstMatch
        try reveal(learn, in: app)
        try require(learn.exists && learn.isEnabled, "The ordinary Reddit learning entry was unavailable.")
        learn.tap()
        let start = app.buttons["web.learningStart"]
        try wait(35, message: "The real Reddit page could not begin learning; resolve any actual authentication/privacy page.") { start.exists && start.isEnabled }
        start.tap()
        try require(app.buttons["web.learningStop"].waitForExistence(timeout: 8), "Real gesture learning did not start.")
        let page = element("web.page", in: app)
        try require(page.exists && page.isHittable, "The real browser page was not reachable for gestures.")
        page.swipeUp(); Thread.sleep(forTimeInterval: 1)
        page.swipeUp(); Thread.sleep(forTimeInterval: 1)
        try tap("web.learningStop", in: app)
        let trace = element("web.learnedActivities", in: app)
        try require(trace.waitForExistence(timeout: 10), "The gestures yielded no recognized real browser activity.")
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save to Learn", "Garder pour apprendre"])).firstMatch
        try wait(10, message: "The actual browser lesson could not be saved.") { save.exists && save.isEnabled }
        save.tap()
        try require(app.buttons.matching(NSPredicate(format: "label IN %@", ["Saved to Learn", "Enregistré"])).firstMatch.waitForExistence(timeout: 10),
                    "The actual browser lesson was not durably saved.")
        try tap("web.close", in: app)
        try back(until: app.buttons["learn.savedObservations"], in: app)
    }

    private func reviewThreeMoments(_ app: XCUIApplication) throws {
        // The real model may preserve moments from the current plan. Review is an
        // ordinary explicit edit; model output never grants execution authority.
        var count = try routineCount(app)
        while count > 3 {
            let last = app.buttons["routine.step.\(count - 1)"]
            try reveal(last, in: app); last.tap()
            try tap("step.remove", in: app)
            try tap("step.removeDraft", in: app)
            count -= 1
        }
        for index in 0..<3 {
            let row = app.buttons["routine.step.\(index)"]
            if index < count { try reveal(row, in: app); row.tap() }
            else { try tap("routine.add", in: app); count += 1 }
            try replace(app.textFields["step.name"], with: [weatherTitle, browserTitle, timedTitle][index], in: app)
            if index == 1 {
                try choose("step.targetApp", labels: ["Reddit"], in: app)
                try choose("step.webBehavior", labels: ["Browse the feed", "Parcourir le fil"], in: app)
                let likes = app.switches["step.webLikes"]
                if likes.exists { try setSwitch("step.webLikes", on: false, in: app) }
            } else {
                try choose("step.automation", labels: index == 0
                    ? ["Read today's briefing", "Lire le récap du jour"]
                    : ["Keep this time, then continue", "Prendre ce temps, puis continuer"], in: app)
            }
            let publicDetail = [
                "Read the current Apple Weather recap for Paris, France.",
                "Browse the public Reddit feed for one minute without liking, posting or sending anything.",
                "Take one minute to get ready, then continue automatically."
            ][index]
            let fieldTypes = [XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue]
            let detail = app.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@ AND label IN %@",
                fieldTypes, ["Step details", "Détails de l’étape", "Détails de l'étape"])).firstMatch
            try replace(detail, with: publicDetail, in: app)
            try require(detail.value as? String == publicDetail, "The reviewed QA moment retained inherited description text.")
            let duration = app.steppers["step.duration"]
            for _ in 0..<120 {
                if duration.value as? String == "1" { break }
                let decrement = duration.buttons["step.duration-Decrement"]
                try reveal(decrement, in: app)
                try require(decrement.exists && decrement.isHittable, "The ordinary duration decrement was unavailable.")
                decrement.tap()
            }
            try require(duration.value as? String == "1", "Every QA moment must retain the public editor's real one-minute minimum.")
            try tap("step.save", in: app)
            try require(app.buttons["routine.approve"].waitForExistence(timeout: 10), "The reviewed action did not return to an unapproved draft.")
        }
        try require(try routineCount(app) == 3, "The reviewed draft must contain exactly three moments.")
    }

    private func routineCount(_ app: XCUIApplication) throws -> Int {
        let list = app.collectionViews.firstMatch
        let scroll = list.exists ? list : app.scrollViews.firstMatch
        for _ in 0..<4 { scroll.swipeDown() }
        var indices = Set<Int>()
        for _ in 0..<12 {
            for row in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routine.step.")).allElementsBoundByIndex {
                if let index = Int(row.identifier.dropFirst("routine.step.".count)) { indices.insert(index) }
            }
            if app.buttons["routine.add"].exists && app.buttons["routine.add"].isHittable {
                let count = indices.count
                try require((1...10).contains(count) && indices == Set(0..<count),
                            "The complete ordinary draft inventory could not be established.")
                return count
            }
            scroll.swipeUp()
        }
        try require(false, "The ordinary draft's end was not reachable.")
        return 0
    }

    private func verifyExecutionSummary(_ app: XCUIApplication) throws {
        let summary = app.staticTexts["morning.executionSummary"]
        try reveal(summary, in: app)
        try require(summary.exists, "No actual execution summary was saved.")
        try require(["Timed moments finished: 1", "Moments chronométrés terminés : 1"].contains(where: summary.label.contains),
                    "The timer's real completion was not distinguished from verified work.")
        try require(["Verified operations: 2", "Opérations vérifiées : 2"].contains(where: summary.label.contains),
                    "The actual spoken briefing and observed browser budget were not both verified.")
        try require(summary.label.range(of: #"(?:Browser:|Navigateur :) [1-9][0-9]* (?:contents observed|contenus observés), 0 (?:likes confirmed|likes confirmés)"#, options: .regularExpression) != nil,
                    "The saved browser result must contain real observed content and zero confirmed likes.")
        try require(!["Unavailable:", "Indisponibles :", "Results to check:", "Résultats à vérifier :", "Moments passed:", "Moments passés :"].contains(where: summary.label.contains),
                    "The finished routine contains unavailable, uncertain or skipped work.")
    }

    private func verifyRecap(_ app: XCUIApplication) throws {
        let completed = element("recap.completed", in: app)
        try reveal(completed, in: app)
        try require(completed.label.range(of: #"\b3\b"#, options: .regularExpression) != nil, "The actual recap did not contain three completed moments.")
        try require(element("recap.saved", in: app).exists, "The recap does not establish local persistence.")
        try require(!element("recap.skipped", in: app).exists && !element("recap.unfinished", in: app).exists,
                    "The recap contains skipped or unreached moments.")
        try require(!element("recap.sample", in: app).exists, "The completed plan is marked as a sample, not an ordinary learned routine.")
    }

    private func openLearnFromSettings(_ app: XCUIApplication) throws {
        try tap("setup.routine", in: app)
        if element("routine.editor", in: app).exists { try tap("learn.refine", in: app) }
        try reveal(app.textViews["learn.notes"], in: app)
        try require(app.textViews["learn.notes"].waitForExistence(timeout: 10), "The ordinary Learn editor did not open.")
    }

    private func openSettings(_ app: XCUIApplication) throws {
        try revealHomeControls(app)
        try tap("morning.settings", in: app)
        try require(app.buttons["setup.connections"].waitForExistence(timeout: 10),
                    "Ordinary access/setup is incomplete; no gate or authorization was injected.")
    }

    private func revealHomeControls(_ app: XCUIApplication) throws {
        for _ in 0..<3 {
            if app.buttons["morning.settings"].exists && app.buttons["morning.settings"].isHittable { return }
            let landscape = app.buttons["morning.actions"]
            let captions = element("morning.captions", in: app)
            let surface = captions.exists && captions.isHittable ? captions : landscape
            try require(surface.waitForExistence(timeout: 10) && surface.isHittable,
                        "The ordinary Home landscape/playback surface is unavailable.")
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
            if app.buttons["morning.settings"].waitForExistence(timeout: 2) { return }
        }
        try require(false, "Home did not expose its ordinary controls.")
    }

    private func returnHome(_ app: XCUIApplication) throws {
        for _ in 0..<8 {
            if app.buttons["morning.actions"].exists && app.buttons["morning.actions"].isHittable { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            try require(back.exists && back.isHittable, "The ordinary navigation stack could not return Home.")
            back.tap()
        }
        try require(false, "The ordinary Home did not return after approval.")
    }

    private func back(until destination: XCUIElement, in app: XCUIApplication) throws {
        for _ in 0..<6 {
            if destination.exists { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            try require(back.exists && back.isHittable, "The ordinary back control was unavailable.")
            back.tap()
        }
        try require(destination.exists, "The ordinary destination did not return.")
    }

    private func refuseFixtures(_ app: XCUIApplication) throws {
        for id in ["qa.testWorkspace", "onboarding.preview", "briefing.synthetic", "learn.fixtureMode", "proposal.fixtureMode"] {
            try require(!element(id, in: app).exists, "A fixture or preview cannot establish ordinary acceptance.")
        }
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, in app: XCUIApplication) throws {
        let button = app.buttons[id]
        try reveal(button, in: app)
        try require(button.exists && button.isHittable && button.isEnabled, "The ordinary control is unavailable: \(id)")
        button.tap()
    }

    private func choose(_ id: String, labels: [String], in app: XCUIApplication) throws {
        let picker = element(id, in: app)
        try reveal(picker, in: app)
        try require(picker.exists && picker.isHittable, "The ordinary picker was unavailable: \(id)")
        picker.tap()
        let option = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        try require(option.waitForExistence(timeout: 5), "The expected ordinary picker choice was unavailable: \(id)")
        try reveal(option, in: app)
        option.tap()
    }

    private func setSwitch(_ id: String, on: Bool, in app: XCUIApplication) throws {
        let toggle = app.switches[id]
        try reveal(toggle, in: app)
        try require(toggle.exists, "The ordinary setting was unavailable: \(id)")
        if toggle.value as? String != (on ? "1" : "0") {
            try require(toggle.isHittable && toggle.isEnabled, "The ordinary setting cannot change: \(id)")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        try wait(6, message: "The ordinary setting did not save: \(id)") {
            toggle.value as? String == (on ? "1" : "0")
        }
    }

    private func replace(_ field: XCUIElement, with text: String, in app: XCUIApplication) throws {
        try reveal(field, in: app)
        try require(field.exists && field.isHittable, "The ordinary editor field was unavailable.")
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(text)
        let done = app.keyboards.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Terminé"])).firstMatch
        if done.exists && done.isHittable { done.tap() }
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) throws {
        for attempt in 0..<24 {
            if target.exists && target.isHittable { return }
            let scrolls = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let container = scrolls.first(where: \.isHittable) ?? app
            if target.exists && target.frame.height > 0 {
                if target.frame.midY < container.frame.midY { container.swipeDown() }
                else { container.swipeUp() }
            } else if attempt < 12 { container.swipeUp() }
            else { container.swipeDown() }
        }
        try require(false, "An ordinary UI destination was not reachable.")
    }

    private func observedCount(_ text: String) -> Int {
        guard let range = text.range(of: #"[0-9]+(?= (?:contents viewed|contenus parcourus))"#, options: .regularExpression) else { return 0 }
        return Int(text[range]) ?? 0
    }

    private func wait(_ timeout: TimeInterval, message: String, until ready: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if ready() { return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        try require(ready(), message)
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            XCTFail(message)
            throw NSError(domain: "OrdinaryRoutineAcceptanceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Required ordinary routine acceptance check failed."])
        }
    }
}
