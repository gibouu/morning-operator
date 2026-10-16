import XCTest
import MorningCore

/// One manually imported moment and one simulated Apple write. No movie/model
/// learning, EventKit access, real account, acoustic or Long10 claim.
@MainActor final class PrivateExactReminderJourneyTests: XCTestCase {
    func testAbsoluteReminderIsReviewedOnceAndReceivedInItsPinnedSession() throws {
        continueAfterFailure = false
        executionTimeAllowance = 480
        let app = XCUIApplication(), workspace = UUID().uuidString
        let stepID = "90000000-0000-4000-8000-000000000007"
        let title = "Bring the blue notebook to North studio"
        // A separate manual subset of the immutable scenario. The provider
        // receives no expected value and this input grants no action authority.
        let portable: [String: Any] = ["format": "morning-operator.routine", "formatVersion": 1, "detail": "includeDetails",
            "sourceRoutineID": "76000000-0000-4000-8000-000000000100", "sourceRoutineVersion": 1,
            "sourceCreatedAt": 1_792_129_500.0, "approvalAtExport": false, "sourceIsSynthetic": true,
            "sourceLabel": "SYNTHETIC manual reminder subset; no learned or imported operation",
            "steps": [["id": stepID, "title": "My exact reminder", "kind": "custom", "durationMinutes": 1,
                "isRequired": false, "detail": "SYNTHETIC manual moment. Prepare and review the reminder separately."]]]
        let data = try JSONSerialization.data(withJSONObject: portable, options: [.sortedKeys])
        let draft = try PortableRoutineDocument.decode(data).importedDraft(replacing: nil)
        XCTAssertTrue(draft.isSynthetic && !draft.isApproved)
        XCTAssertEqual(draft.steps.count, 1)
        XCTAssertTrue(draft.steps.allSatisfy { $0.target == nil && $0.automation == nil })
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-private-exact-reminder", "--ui-testing-native-actions", "--ui-testing-hands-free",
            // Existing closed mail/Slack composition prevents live transport
            // fallback. No mail/Slack operation is configured or exercised here.
            "--ui-testing-integrated-three-moments", "--ui-testing-gmail-attention", "--ui-testing-slack-setup",
            "--ui-testing-briefing-fixture", "--light-preview", "--theme-phase=morning",
            "--ui-testing-parsed-routine=" + data.base64EncodedString(),
            "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); defer { app.terminate() }
        try requireWorkspace(workspace, in: app)
        let notice = app.staticTexts["app.notice"]
        if notice.exists { XCTAssertFalse(notice.label.contains("SYNTHETIC QA input refused")) }
        reveal(app); tap("morning.settings", in: app); tap("setup.routine", in: app)
        XCTAssertTrue(button("routine.approve", in: app).isEnabled)
        tap("routine.step.0", in: app)
        XCTAssertTrue(app.collectionViews["step.editor.form"].waitForExistence(timeout: 8))
        chooseAction("Keep this time, then continue", in: app)
        tap("step.save", in: app)
        XCTAssertTrue(button("routine.step.0", in: app).label.contains("My exact reminder"))
        XCTAssertTrue(button("routine.approve", in: app).isEnabled)
        tap("routine.approve", in: app)
        home(app); app.terminate()
        app.launchArguments.removeAll { $0.hasPrefix("--ui-testing-parsed-routine=") }
        app.launch(); try requireWorkspace(workspace, in: app)
        reveal(app); tap("morning.settings", in: app); tap("setup.routine", in: app)
        XCTAssertFalse(app.buttons["routine.approve"].exists, "Only the saved UI approval authorizes this session.")
        home(app); reveal(app); tap("morning.begin", in: app)
        wait(app.staticTexts["morning.caption"], predicate: NSPredicate(format: "label CONTAINS %@", "Would you like"), timeout: 20)
        reveal(app)
        let play = button("morning.playback", in: app)
        XCTAssertEqual(play.label, "Continue"); play.tap()
        wait(play, predicate: NSPredicate(format: "label == %@", "Pause"), timeout: 8)
        let pinned = try executionIdentity(in: app)
        XCTAssertEqual(pinned[1], stepID)
        interact(app)
        tap("nativeMoment.open", in: app)
        XCTAssertTrue(app.staticTexts["nativeMoment.synthetic"].exists)
        let empty = try proof(in: app)
        XCTAssertEqual(empty["simulatedWrites"], "0"); XCTAssertEqual(empty["confirmed"], "0")
        let request = app.descendants(matching: .any).matching(identifier: "nativeMoment.request").firstMatch
        visible(request, id: "nativeMoment.request", in: app)
        request.tap(); request.typeText("Remind me to " + title)
        tap("nativeMoment.prepare", in: app)
        let name = app.descendants(matching: .any).matching(identifier: "nativeMoment.title").firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8)); XCTAssertEqual(name.value as? String, title)
        let dated = app.switches["nativeMoment.hasDate"].firstMatch
        visible(dated, id: "nativeMoment.hasDate", in: app)
        XCTAssertEqual(dated.value as? String, "0")
        let nativeSwitch = dated.switches.firstMatch
        if nativeSwitch.exists && nativeSwitch.isHittable { nativeSwitch.tap() } else { dated.tap() }
        XCTAssertEqual(dated.value as? String, "1")
        try chooseAbsoluteDate(in: app)
        tap("nativeMoment.editReview", in: app)
        let status = app.staticTexts["nativeMoment.status"]
        wait(status, predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            title, "October 16, 2026", "Europe/Paris", "with alert"), timeout: 10)
        // The form uses the actual device/calendar time zone. A different zone
        // is a failure, never relabelled or silently changed by this test.
        let confirm = button("nativeMoment.confirm", in: app)
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertEqual(try proof(in: app)["simulatedWrites"], "0")
        attach("exact-reminder-absolute-date-awaiting-explicit-review", app)
        tap("nativeMoment.reviewed", in: app)
        XCTAssertTrue(button("nativeMoment.confirm", in: app).isEnabled)
        tap("nativeMoment.confirm", in: app)
        wait(status, predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "was added", title), timeout: 10)
        let received = try proof(in: app)
        XCTAssertEqual(received["simulatedWrites"], "1")
        XCTAssertEqual(received["kind"], "reminder"); XCTAssertEqual(received["title"], title); XCTAssertEqual(received["notes"], "")
        let dueBits = try XCTUnwrap(received["dueReferenceBits"].flatMap { UInt64($0, radix: 16) })
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-16T07:25:00Z"))
        XCTAssertEqual(Double(bitPattern: dueBits), expected.timeIntervalSinceReferenceDate, "No rounding of actual received timestamps is allowed.")
        XCTAssertEqual(received["timeZoneIdentifier"], "Europe/Paris"); XCTAssertEqual(received["notifyAtDueTime"], "true")
        XCTAssertEqual(received["destinationID"], "synthetic-list"); XCTAssertEqual(received["destinationSourceID"], "synthetic-account")
        XCTAssertEqual(received["destinationTitle"], "SYNTHETIC QA"); XCTAssertEqual(received["destinationSourceTitle"], "SYNTHETIC local fixture")
        XCTAssertEqual(received["destinationKind"], "reminder")
        for (key, expectedID) in [("SessionID", pinned[0]), ("RoutineVersionID", pinned[2]), ("StepID", stepID)] {
            XCTAssertEqual(received["received" + key], expectedID)
        }
        XCTAssertEqual(received["nativeContextMatches"], "true")
        XCTAssertEqual(received["confirmed"], "1"); XCTAssertEqual(received["unconfirmed"], "0")
        XCTAssertFalse(app.buttons["nativeMoment.confirm"].exists, "The completed request cannot expose a second confirmation.")
        attach("exact-reminder-one-received-simulated-payload", app)
        tap("nativeMoment.cancel", in: app)
        tap("nativeMoment.open", in: app)
        XCTAssertEqual(try proof(in: app)["simulatedWrites"], "1", "Closing the result must not repeat it.")
        XCTAssertFalse(app.buttons["nativeMoment.confirm"].exists)
        tap("morning.closeDetails", in: app)
        XCTAssertEqual(try executionIdentity(in: app), pinned)
        // Attach only the actual received dictionary observed before closing.
        let json = try JSONSerialization.data(withJSONObject: received, options: [.sortedKeys, .prettyPrinted])
        let payload = XCTAttachment(string: String(decoding: json, as: UTF8.self))
        payload.name = "exact-reminder-actual-received-payload-and-session"; payload.lifetime = .keepAlways; add(payload)
        app.terminate(); app.launch(); try requireWorkspace(workspace, in: app)
        XCTAssertEqual(try executionIdentity(in: app), pinned)
        interact(app); tap("nativeMoment.open", in: app)
        let restored = try proof(in: app)
        XCTAssertEqual(restored["sessionID"], pinned[0]); XCTAssertEqual(restored["routineVersionID"], pinned[2]); XCTAssertEqual(restored["stepID"], stepID)
        XCTAssertEqual(restored["confirmed"], "1"); XCTAssertEqual(restored["unconfirmed"], "0")
        XCTAssertEqual(restored["simulatedWrites"], "0", "The new in-memory transport must receive no write during relaunch.")
        XCTAssertNil(restored["title"], "The payload is not persisted as a hidden second routine or draft.")
        attach("exact-reminder-same-session-durable-receipt-no-relaunch-write", app)
    }

    private func chooseAbsoluteDate(in app: XCUIApplication) throws {
        let picker = app.descendants(matching: .any).matching(identifier: "nativeMoment.date").firstMatch
        visible(picker, id: "nativeMoment.date", in: app)
        let datePattern = ".*[12][0-9]{3}.*"
        guard let dateButton = picker.buttons.allElementsBoundByIndex.first(where: {
            $0.isHittable && ($0.label.range(of: datePattern, options: .regularExpression) != nil || ($0.value as? String ?? "").range(of: datePattern, options: .regularExpression) != nil)
        }) else { fail("exact-reminder-native-date-control-unavailable", app); throw ProofError.unavailable }
        dateButton.tap()
        let headerPattern = "^(January|February|March|April|May|June|July|August|September|October|November|December) [12][0-9]{3}$"
        let headers = app.buttons.matching(NSPredicate(format: "label MATCHES %@", headerPattern))
        XCTAssertTrue(headers.firstMatch.waitForExistence(timeout: 5))
        guard let header = headers.allElementsBoundByIndex.first(where: \.isHittable) else { fail("exact-reminder-month-year-unavailable", app); throw ProofError.unavailable }
        header.tap()
        let wheels = app.pickerWheels.allElementsBoundByIndex.filter(\.isHittable)
        guard wheels.count == 2 else { fail("exact-reminder-native-month-year-wheels-unavailable", app); throw ProofError.unavailable }
        wheels[0].adjust(toPickerWheelValue: "October"); wheels[1].adjust(toPickerWheelValue: "2026")
        guard let selectedHeader = app.buttons.matching(identifier: "October 2026").allElementsBoundByIndex.first(where: \.isHittable)
            ?? app.buttons.matching(NSPredicate(format: "label == %@", "October 2026")).allElementsBoundByIndex.first(where: \.isHittable) else {
            fail("exact-reminder-absolute-month-year-not-observed", app); throw ProofError.unavailable
        }
        selectedHeader.tap()
        let days = app.buttons.matching(NSPredicate(format: "label IN %@", ["Friday, October 16, 2026", "Friday, October 16", "16"]))
        guard let day = days.allElementsBoundByIndex.first(where: \.isHittable) else { fail("exact-reminder-calendar-day-unavailable", app); throw ProofError.unavailable }
        day.tap()
        closeNativePickerIfNeeded(app)
        visible(picker, id: "nativeMoment.date", in: app)
        guard let time = picker.buttons.allElementsBoundByIndex.first(where: {
            $0.isHittable && ($0.label + " " + ($0.value as? String ?? "")).range(of: "[0-9]{1,2}:[0-9]{2}", options: .regularExpression) != nil
        }) else { fail("exact-reminder-native-time-control-unavailable", app); throw ProofError.unavailable }
        time.tap()
        let timeWheels = app.pickerWheels.allElementsBoundByIndex.filter(\.isHittable)
        guard timeWheels.count == 2 || timeWheels.count == 3 else { fail("exact-reminder-native-time-wheels-unavailable", app); throw ProofError.unavailable }
        timeWheels[0].adjust(toPickerWheelValue: "9"); timeWheels[1].adjust(toPickerWheelValue: "25")
        if timeWheels.count == 3 { timeWheels[2].adjust(toPickerWheelValue: "AM") }
        closeNativePickerIfNeeded(app)
    }
    private func closeNativePickerIfNeeded(_ app: XCUIApplication) {
        if let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Close"])).allElementsBoundByIndex.first(where: {
            $0.isHittable && $0.identifier != "morning.closeDetails" && $0.identifier != "destination.close"
        }) { done.tap() }
    }
    private func proof(in app: XCUIApplication) throws -> [String: String] {
        let marker = app.staticTexts["nativeMoment.exactProof"]
        visible(marker, id: "nativeMoment.exactProof", in: app)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(marker.value as? String).utf8)) as? [String: String])
    }
    private func executionIdentity(in app: XCUIApplication) throws -> [String] {
        let captions = app.scrollViews["morning.captions"]
        XCTAssertTrue(captions.waitForExistence(timeout: 8))
        let parts = try XCTUnwrap(captions.value as? String).components(separatedBy: "|")
        XCTAssertEqual(parts.count, 7)
        for value in parts.prefix(3) { XCTAssertNotNil(UUID(uuidString: value)) }
        return Array(parts.prefix(4))
    }
    private func interact(_ app: XCUIApplication) {
        reveal(app); tap("morning.settings", in: app); tap("morning.details", in: app)
        XCTAssertTrue(app.buttons["morning.closeDetails"].waitForExistence(timeout: 5))
    }
    private func chooseAction(_ name: String, in app: XCUIApplication) {
        let fields = app.descendants(matching: .any).matching(identifier: "step.automation")
        visible(fields.firstMatch, id: "step.automation", in: app)
        guard let field = fields.allElementsBoundByIndex.first(where: { $0.isEnabled && $0.isHittable }) else {
            fail("exact-reminder-action-picker-unreachable", app); return
        }
        field.tap()
        let choice = app.buttons[name].firstMatch
        if choice.waitForExistence(timeout: 2) { visible(choice, id: name, in: app); choice.tap() }
        else { let text = app.staticTexts[name].firstMatch; visible(text, id: name, in: app); text.tap() }
    }
    private func requireWorkspace(_ workspace: String, in app: XCUIApplication) throws {
        try MorningUITestNavigation.requireIsolatedWorkspace(workspace, in: app)
    }
    private func reveal(_ app: XCUIApplication) {
        if app.buttons["morning.settings"].isHittable { return }
        let caption = app.scrollViews["morning.captions"]
        let surface = caption.exists ? caption : app.buttons["morning.actions"]
        guard surface.exists && surface.isHittable else {
            fail("exact-reminder-home-surface-unreachable", app); return
        }
        surface.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5))
    }
    private func home(_ app: XCUIApplication) {
        for _ in 0..<5 {
            guard app.navigationBars.count > 0 else { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.isHittable); back.tap()
        }
        XCTFail("Normal Back must return Home.")
    }
    private func button(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let query = app.buttons.matching(identifier: id)
        if let ready = query.allElementsBoundByIndex.first(where: \.isHittable) { return ready }
        visible(query.firstMatch, id: id, in: app)
        return query.allElementsBoundByIndex.first(where: \.isHittable) ?? query.firstMatch
    }
    private func tap(_ id: String, in app: XCUIApplication) { button(id, in: app).tap() }
    private func visible(_ value: XCUIElement, id: String, in app: XCUIApplication) {
        _ = value.waitForExistence(timeout: 5)
        for down in [false, true] {
            for _ in 0..<8 {
                if value.exists && value.isHittable { return }
                if app.buttons.matching(identifier: id).allElementsBoundByIndex.contains(where: \.isHittable) { return }
                guard let container = app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable)
                    ?? app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable) else {
                    fail("exact-reminder-no-foreground-container-\(id)", app); return
                }
                if down { container.swipeDown() } else { container.swipeUp() }
            }
        }
        fail("exact-reminder-control-unreachable-\(id)", app)
    }
    private func wait(_ value: XCUIElement, predicate: NSPredicate, timeout: TimeInterval) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: value)], timeout: timeout), .completed)
    }
    private func fail(_ name: String, _ app: XCUIApplication) { attach(name, app); XCTFail(name) }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let ax = XCTAttachment(string: app.debugDescription); ax.name = name + "-AX"; ax.lifetime = .keepAlways; add(ax)
    }
    private enum ProofError: Error { case unavailable }
}
