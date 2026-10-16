import XCTest
import MorningCore

/// A closed WebKit document, ordinary UI delegation and the ordinary browser
/// executor. No video inference, live service, microphone or acoustic claim.
@MainActor final class PrivateNewsReadingJourneyTests: XCTestCase {
    func testSecondObservedArticleReturnsToItsPausedBudgetEnglish() throws { try journey(french: false) }
    func testSecondObservedArticleReturnsToItsPausedBudgetFrench() throws { try journey(french: true) }

    private func journey(french: Bool) throws {
        continueAfterFailure = false
        executionTimeAllowance = 360
        let workspace = UUID().uuidString, stepID = "74000000-0000-4000-8000-000000000002"
        // Manual input is independent of page observations. It imports no URL,
        // operation or approval, and never enters the learning/model pipeline.
        let portable: [String: Any] = ["format": "morning-operator.routine", "formatVersion": 1, "detail": "includeDetails",
            "sourceRoutineID": "74000000-0000-4000-8000-000000000100", "sourceRoutineVersion": 1,
            "sourceCreatedAt": 1_792_129_500.0, "approvalAtExport": false, "sourceIsSynthetic": true,
            "sourceLabel": "SYNTHETIC manual news reading; no learned or imported authority",
            "steps": [["id": stepID, "title": "SYNTHETIC Cedar news", "kind": "briefing", "durationMinutes": 4,
                       "isRequired": false, "detail": "SYNTHETIC manual reading. Choose the browser behavior in the editor."]]]
        let data = try JSONSerialization.data(withJSONObject: portable, options: [.sortedKeys])
        let draft = try PortableRoutineDocument.decode(data).importedDraft(replacing: nil)
        XCTAssertTrue(draft.isSynthetic && !draft.isApproved)
        XCTAssertEqual(draft.steps.count, 1)
        XCTAssertTrue(draft.steps.allSatisfy { $0.target == nil && $0.automation == nil && $0.webBehavior == nil })
        let app = XCUIApplication(), language = french ? "fr" : "en"
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-private-news", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-hands-free", "--ui-testing-briefing-fixture", "--light-preview", "--theme-phase=morning",
            "--ui-testing-parsed-routine=" + data.base64EncodedString(),
            "-more.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", french ? "fr_FR" : "en_US"]
        app.launch(); defer { app.terminate() }
        let marker = app.staticTexts["qa.testWorkspace"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10)); XCTAssertEqual(marker.value as? String, workspace)
        XCTAssertFalse(app.staticTexts["app.notice"].label.contains("SYNTHETIC QA input refused"))
        reveal(app); tap("morning.settings", app); tap("setup.routine", app)
        XCTAssertTrue(button("routine.approve", app).isEnabled)
        tap("routine.step.0", app)
        choosePicker("step.targetApp", label: "Le Monde", app: app)
        choosePicker("step.webBehavior", label: french ? "Lire les titres à voix haute" : "Read headlines aloud", app: app)
        tap("step.save", app)
        XCTAssertTrue(button("routine.approve", app).isEnabled, "Choosing a page and behavior must still leave a draft.")
        attach("private-news-configured-unapproved-\(language)", app)
        tap("routine.approve", app)
        home(app)
        // Approval, selected target and behavior must survive without the import payload.
        app.terminate(); app.launchArguments.removeAll { $0.hasPrefix("--ui-testing-parsed-routine=") }; app.launch()
        XCTAssertTrue(marker.waitForExistence(timeout: 10)); XCTAssertEqual(marker.value as? String, workspace)
        reveal(app); tap("morning.settings", app); tap("setup.routine", app)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        home(app); reveal(app); tap("morning.begin", app)
        // The first Play continues the ordinary opening; it is not an article action.
        let continuation = app.buttons["morning.playback"]
        reveal(app)
        wait(continuation, predicate: NSPredicate(format: "label == %@", french ? "Continuer" : "Continue"), timeout: 20)
        continuation.tap()
        XCTAssertTrue(app.buttons["web.close"].waitForExistence(timeout: 25))
        let secondTitle = french ? "Un coin lecture au jardin Cèdre" : "A reading corner at Cedar garden"
        let second = app.buttons["web.article.2"]
        XCTAssertTrue(second.waitForExistence(timeout: 20)); XCTAssertEqual(second.label, "2. " + secondTitle)
        XCTAssertEqual(app.staticTexts["web.host"].label, "SYNTHETIC Cedar News")
        let running = try diagnostic(app)
        let context = try XCTUnwrap(running["newsContext"])
        let fields = context.components(separatedBy: "|")
        XCTAssertEqual(fields.count, 3); XCTAssertEqual(fields.last, stepID)
        for field in fields { XCTAssertNotNil(UUID(uuidString: field)) }
        XCTAssertEqual(running["resource"], "/headlines"); XCTAssertEqual(running["pausedAtBits"], "none")
        Thread.sleep(forTimeInterval: 5)
        // This product ordinal button conveys the user's intention through
        // handleWebReadingUtterance. XCTest never taps a link inside the DOM.
        XCTAssertTrue(second.isHittable); second.tap()
        XCTAssertTrue(app.buttons["web.articleRepeat"].waitForExistence(timeout: 25))
        let paragraph = french
            ? "Le jardin Cèdre ouvre un coin lecture samedi. Des bénévoles ont placé six bancs près des érables. Les inscriptions sont gratuites et se font sur place. Le chantier a utilisé du bois récupéré dans l’atelier voisin. La bibliothèque prêtera des livres aux visiteurs. Ce récit est entièrement inventé pour le test SYNTHETIC."
            : "Cedar garden opens a reading corner on Saturday. Volunteers placed six benches beside the maples. Registration is free and takes place on site. The project used wood recovered from the nearby workshop. The library will lend books to visitors. This story is entirely invented for the SYNTHETIC test."
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", paragraph)).firstMatch.waitForExistence(timeout: 5),
                      "The actual second document must render its exact independent source paragraph.")
        let paused = try diagnostic(app)
        let localLoads = try XCTUnwrap(paused["localLoads"].flatMap(Int.init))
        XCTAssertGreaterThanOrEqual(localLoads, 2, "The list and chosen article must actually be delivered by the local handler.")
        XCTAssertEqual(paused["newsContext"], context); XCTAssertEqual(paused["resource"], "/article/two")
        XCTAssertEqual(paused["articleParagraphs"], "1"); XCTAssertEqual(paused["endsAtBits"], running["endsAtBits"])
        XCTAssertNotEqual(paused["pausedAtBits"], "none")
        let budget = app.staticTexts["web.remaining"].label
        attach("private-news-second-observed-body-\(language)", app)
        tap("web.articleRepeat", app)
        XCTAssertEqual(try diagnostic(app)["localLoads"], String(localLoads), "Repeat reads the retained body, without another document request.")
        tap("web.articleReturn", app)
        XCTAssertTrue(app.buttons["web.articleReturn"].waitForNonExistence(timeout: 25))
        XCTAssertTrue(second.waitForExistence(timeout: 10)); XCTAssertEqual(second.label, "2. " + secondTitle)
        let returned = try diagnostic(app)
        for key in ["newsContext", "endsAtBits", "pausedAtBits"] { XCTAssertEqual(returned[key], paused[key]) }
        XCTAssertEqual(returned["resource"], "/headlines"); XCTAssertEqual(app.staticTexts["web.remaining"].label, budget)
        XCTAssertFalse(app.buttons["web.articleRepeat"].exists)
        attach("private-news-return-same-paused-budget-\(language)", app)
        let pausedAt = try instant(paused, "pausedAtBits"), end = try instant(paused, "endsAtBits")
        let beforeResume = Date().timeIntervalSinceReferenceDate
        tap("web.resume", app)
        let afterResume = Date().timeIntervalSinceReferenceDate
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 5))
        let resumed = try diagnostic(app), resumedEnd = try instant(resumed, "endsAtBits")
        XCTAssertEqual(resumed["newsContext"], context); XCTAssertEqual(resumed["pausedAtBits"], "none")
        XCTAssertGreaterThanOrEqual(resumedEnd, beforeResume + end - pausedAt - 0.1)
        XCTAssertLessThanOrEqual(resumedEnd, afterResume + end - pausedAt + 0.1)
        attach("private-news-explicit-resume-same-session-\(language)", app)
    }

    private func diagnostic(_ app: XCUIApplication) throws -> [String: String] {
        let result = app.staticTexts["web.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let text = try XCTUnwrap(result.value as? String)
        return Dictionary(text.split(separator: " ").compactMap { token in
            let pair = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { _, last in last })
    }
    private func instant(_ value: [String: String], _ key: String) throws -> Double {
        let bits = try XCTUnwrap(value[key].flatMap { UInt64($0, radix: 16) })
        let date = Double(bitPattern: bits); XCTAssertTrue(date.isFinite); return date
    }
    private func choosePicker(_ id: String, label: String, app: XCUIApplication) {
        let query = app.descendants(matching: .any).matching(identifier: id)
        visible(query.firstMatch, in: app)
        guard let picker = query.allElementsBoundByIndex.first(where: { $0.isEnabled && $0.isHittable }) else {
            XCTFail("The ordinary picker must be tappable: \(id)"); return
        }
        picker.tap()
        let choice = app.buttons[label].firstMatch
        if choice.waitForExistence(timeout: 2) { visible(choice, in: app); choice.tap() }
        else { let row = app.staticTexts[label].firstMatch; visible(row, in: app); row.tap() }
    }
    private func button(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let query = app.buttons.matching(identifier: id)
        if let found = query.allElementsBoundByIndex.first(where: \.isHittable) { return found }
        visible(query.firstMatch, in: app)
        return query.allElementsBoundByIndex.first(where: \.isHittable) ?? query.firstMatch
    }
    private func tap(_ id: String, _ app: XCUIApplication) { button(id, app).tap() }
    private func visible(_ value: XCUIElement, in app: XCUIApplication) {
        _ = value.waitForExistence(timeout: 5)
        for down in [false, true] {
            for _ in 0..<8 {
                if value.exists && value.isHittable { return }
                let editor = app.collectionViews["step.editor.form"].firstMatch
                let container = editor.exists ? editor : app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable)
                    ?? app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app
                if down { container.swipeDown() } else { container.swipeUp() }
            }
        }
        attach("private-news-unreachable", app); XCTFail("The ordinary UI control must be hittable: \(value.label)")
    }
    private func home(_ app: XCUIApplication) {
        for _ in 0..<5 {
            guard app.navigationBars.count > 0 else { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.isHittable); back.tap()
        }
        XCTFail("Ordinary Back must return Home.")
    }
    private func reveal(_ app: XCUIApplication) {
        if app.buttons["morning.settings"].isHittable { return }
        let captions = app.scrollViews["morning.captions"]
        if captions.exists { captions.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25)).tap() }
        else { tap("morning.actions", app) }
        XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5))
    }
    private func wait(_ value: XCUIElement, predicate: NSPredicate, timeout: TimeInterval) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: value)], timeout: timeout), .completed)
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let state = XCTAttachment(string: app.debugDescription); state.name = name + "-AX"; state.lifetime = .keepAlways; add(state)
    }
}
