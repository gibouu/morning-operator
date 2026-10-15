import XCTest

/// Explicit checks against MORE QA or the separate persistent Morning Lab app.
/// The Lab uses normal app storage so system intents can cold launch into the
/// same synthetic routine. Account content and system hierarchies are not collected.
@MainActor
final class PlanBSystemDeviceTests: XCTestCase {
    private var isLab: Bool { ProcessInfo.processInfo.environment["MO_SYSTEM_LAB_TEST"] == "1" }
    private var qaBundle: String { isLab ? "com.gibouu.morningoperator.systemqa" : "com.gibouu.morningoperator.qa" }
    private var appName: String { isLab ? "Morning Lab" : "MORE QA" }
    private var urlScheme: String { isLab ? "morelab" : "moreqa" }
    private var firstStepTitle: String { isLab ? "Calendar & weather" : "Your morning" }
    private var secondStepTitle: String { isLab ? "iMessage" : "People and messages" }
    private var runningApp: XCUIApplication?
    private var alarmMayBeScheduled = false
    private var syntheticWorkspaceConfirmed = false
    private var changedLabTarget = false

    private func cleanup() {
        if let app = runningApp {
            if alarmMayBeScheduled { cancelAlarm(in: app) }
            if !alarmMayBeScheduled && syntheticWorkspaceConfirmed {
                stopSyntheticMorning(in: app)
                if changedLabTarget { restoreLabTarget(in: app) }
                // Reconcile only this selected app's process-era activity.
                app.terminate()
                app.launch()
                _ = app.buttons["morning.actions"].waitForExistence(timeout: 10)
                app.terminate()
            } else if !alarmMayBeScheduled {
                app.terminate()
            }
        }
        runningApp = nil
    }

    func testAlarmAuthorizationScheduleAndImmediateCancellation() throws {
        let app = try launch()
        openSettings(in: app)
        tap("setup.alarm", in: app)
        let status = app.staticTexts["alarm.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        // AlarmManager's records are app scoped, rather than workspace scoped.
        // Refuse to touch any pre-existing QA alarm, even in this fresh workspace.
        guard diagnostic(status, includes: ["scheduled:0", "recorded:0", "owned:0"]) else {
            XCTFail("QA already has an alarm or its real AlarmKit state is unavailable. No alarm was changed.")
            return
        }
        let toggle = app.switches["alarm.enabled"].firstMatch
        guard toggle.waitForExistence(timeout: 5), toggle.value as? String == "0" else {
            XCTFail("The fresh synthetic workspace must start with its alarm off.")
            return
        }
        set(toggle, enabled: true)
        let desired = Calendar.current.dateComponents([.hour, .minute], from: Date().addingTimeInterval(6 * 60 * 60))
        try setAlarmTime(hour: try XCTUnwrap(desired.hour), minute: try XCTUnwrap(desired.minute), in: app)

        // Accept only the explicitly selected test app's alarm prompt.
        let expectedAppName = appName
        let monitor = addUIInterruptionMonitor(withDescription: "\(expectedAppName) AlarmKit authorization") { alert in
            let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            guard text.localizedCaseInsensitiveContains(expectedAppName),
                  text.localizedCaseInsensitiveContains("alarm") else { return false }
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(monitor) }
        alarmMayBeScheduled = true
        tap("alarm.save", in: app)
        allowQAAlarmPromptIfPresent()
        // A second safe interaction lets XCTest dispatch its interruption monitor
        // when the system owns a separate permission window.
        if !waitUntil(timeout: 2, { self.diagnostic(status, includes: ["auth:authorized", "scheduled:1", "recorded:1", "owned:1"]) }) {
            app.tap()
        }
        let scheduled = waitUntil(timeout: 15) {
            self.diagnostic(status, includes: ["auth:authorized", "scheduled:1", "recorded:1", "owned:1"])
        }
        // Cancel before recording the assertion, so a failure cannot intentionally
        // leave the temporary daily alarm enabled. Its next time is six hours away.
        cancelAlarm(in: app)
        XCTAssertTrue(scheduled, "The real AlarmKit service did not confirm the scheduled QA alarm; authorization may need owner action.")
        XCTAssertFalse(alarmMayBeScheduled, "QA alarm cleanup must be confirmed before leaving this check.")
    }

    /// Run only while the owner is present and can stop the test app's alarm if iOS
    /// does not expose a scoped presentation to XCTest. This observes the actual
    /// alarm alert and its action, rather than assuming that scheduling means it rang.
    func testAlarmFiresAndStartMOREOpensSyntheticMorning() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_QA_ALARM_RING_TEST_ENABLED"] == "1",
            "Separate opt-in required with the owner present to stop and disable \(appName)'s alarm if system UI cleanup is blocked.")
        let app = try launch()
        openSettings(in: app)
        tap("setup.alarm", in: app)
        let status = app.staticTexts["alarm.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        guard diagnostic(status, includes: ["scheduled:0", "recorded:0", "owned:0"]) else {
            XCTFail("QA already has an alarm or its real AlarmKit state is unavailable. No firing alarm was scheduled.")
            return
        }
        let toggle = app.switches["alarm.enabled"].firstMatch
        guard toggle.waitForExistence(timeout: 5), toggle.value as? String == "0" else {
            XCTFail("The fresh synthetic workspace must start with its alarm off.")
            return
        }
        set(toggle, enabled: true)
        // Rounding now +3 minutes down to a whole minute leaves 120–180
        // seconds for the attended device check, including across midnight.
        let fireAt = Date(timeIntervalSince1970: floor(Date().addingTimeInterval(180).timeIntervalSince1970 / 60) * 60)
        let desired = Calendar.current.dateComponents([.hour, .minute], from: fireAt)
        try setAlarmTime(hour: try XCTUnwrap(desired.hour), minute: try XCTUnwrap(desired.minute), in: app)
        alarmMayBeScheduled = true
        tap("alarm.save", in: app)
        allowQAAlarmPromptIfPresent()
        guard waitUntil(timeout: 15, {
            self.diagnostic(status, includes: ["auth:authorized", "scheduled:1", "recorded:1", "owned:1"])
        }) else {
            cancelAlarm(in: app)
            XCTFail("The real QA alarm was not confirmed scheduled; no firing result is established.")
            return
        }
        closeSettings(in: app)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // A native alert boundary plus the exact QA app, title and action are
        // mandatory. Never tap a generic Start MORE button elsewhere on screen.
        let presentation = springboard.alerts
            .containing(.staticText, identifier: appName)
            .containing(.staticText, identifier: "Good morning")
            .containing(.button, identifier: "Start MORE")
        let observed = waitUntil(timeout: max(1, fireAt.timeIntervalSinceNow + 45)) {
            presentation.count == 1
        }
        guard observed else {
            cancelAlarm(in: app)
            XCTFail("A uniquely scoped \(appName) alarm alert/action was not exposed. No Start action was tapped. If system UI blocks cleanup, the owner must stop \(appName)'s alarm and disable it; this check has not passed.")
            return
        }
        presentation.firstMatch.buttons["Start MORE"].tap()
        let routed = waitUntil(timeout: 20) {
            app.state == .runningForeground && app.buttons["opening.routine"].exists
        }
        if routed {
            MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        }
        let started = app.staticTexts["run.step"].exists && app.staticTexts["run.step"].label == firstStepTitle
        cancelAlarm(in: app)
        XCTAssertTrue(routed && started,
            "The actual test alarm action must reach \(appName)'s normal approved synthetic morning opening.")
        XCTAssertFalse(alarmMayBeScheduled, "The attended QA firing alarm must be disabled and absent afterward.")
        // An accessible ringing presentation does not measure its sound level or
        // silent-mode behavior. Those observations must come from the owner.
    }

    func testSiriAppShortcutStartsAndAdvancesSyntheticMorning() throws {
        let app = try launch()
        XCTAssertFalse(app.staticTexts["run.step"].exists)
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: "Start my morning with \(appName)")
        guard app.buttons["opening.routine"].waitForExistence(timeout: 20) else {
            XCTFail("Siri did not deliver \(appName)'s Start App Shortcut. Siri setup, language and shortcut discovery require an owner check.")
            return
        }
        app.activate()
        MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        XCTAssertEqual(app.staticTexts["run.step"].label, firstStepTitle)
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: "Next step in \(appName)")
        let advanced = waitUntil(timeout: 20) {
            app.staticTexts["run.step"].exists && app.staticTexts["run.step"].label == self.secondStepTitle
        }
        XCTAssertTrue(advanced, "Siri did not deliver \(appName)'s Next App Shortcut to the synthetic session.")
        // This uses textual recognized-speech injection into the real Siri service;
        // it does not establish microphone recognition or hands-free invocation.
    }

    func testNotificationCenterStepControlsExtendAndAdvanceQAOnly() throws {
        let app = try launch(nativeActivity: true)
        openRoutine(in: app)
        tap("routine.step.0", in: app)
        let target = app.buttons["step.targetApp"]
        reveal(target, in: app)
        target.tap()
        let site = app.buttons["Le Monde"].firstMatch
        XCTAssertTrue(site.waitForExistence(timeout: 5))
        site.tap()
        changedLabTarget = isLab
        tap("step.save", in: app)
        tap("routine.approve", in: app)

        openSettings(in: app)
        tap("setup.activity", in: app)
        let enabled = app.switches["activity.enabled"].firstMatch
        guard enabled.waitForExistence(timeout: 8) else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "qa-synthetic-settings-navigation-failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print("QA_SETTINGS_ROUTE settingsVisible=\(app.buttons["setup.activity"].exists) activityTitle=\(app.navigationBars["Lock Screen"].exists) openingVisible=\(app.buttons["opening.routine"].exists)")
            XCTFail("The synthetic Settings page did not open its Lock Screen controls.")
            return
        }
        set(enabled, enabled: true)
        closeSettings(in: app)
        MorningUITestNavigation.tapButton("run.start", in: app)
        let about = app.buttons["web.aboutDone"]
        if about.waitForExistence(timeout: 5) { about.tap() }
        tap("web.close", in: app)
        let beforeEnd = Date().addingTimeInterval(TimeInterval(try remaining("stepTimer.remaining", in: app)))
        openSettings(in: app)
        tap("setup.activity", in: app)
        let native = app.staticTexts["activity.nativeDiagnostic"]
        XCTAssertTrue(waitUntil(timeout: 10) { native.exists && native.label.hasPrefix("count:1|") },
            "The real isolated ActivityKit record must exist before opening its OS presentation.")
        closeSettings(in: app)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        showNotificationCenter()
        let extend = springboard.buttons.matching(identifier: "stepActivity.\(urlScheme).extend")
        guard extend.firstMatch.waitForExistence(timeout: 10), extend.count == 1 else {
            XCTFail("The QA widget's uniquely identified +2 control is not exposed. No system control was tapped.")
            return
        }
        extend.firstMatch.tap()
        // iOS can replace the timer's accessibility element during a render.
        // Measure the intent's saved deadline and the actual Next link here;
        // rendered countdown and physical locking need a separate owner check.
        print("QA_STEP_NATIVE renderedCountdown=notMeasured ownerVisualCheck=required")
        app.activate()
        let savedRemaining = try remaining("stepTimer.remaining", in: app)
        let extendedEnd = Date().addingTimeInterval(TimeInterval(savedRemaining))
        let savedDeadlineShift = extendedEnd.timeIntervalSince(beforeEnd)
        let pausedAfterExtension = app.buttons["run.resume"].exists
        let runningAfterExtension = app.buttons["run.pause"].exists
        let intentOutcome = app.staticTexts["stepTimer.remaining"].value as? String ?? "noIntentResult"
        print("QA_STEP_SAVED savedRemaining=\(savedRemaining) savedDeadlineShift=\(savedDeadlineShift) paused=\(pausedAfterExtension) running=\(runningAfterExtension) intent=\(intentOutcome)")
        let savedTimerMatches = abs(savedDeadlineShift - 120) <= 10
        guard savedTimerMatches && runningAfterExtension && !pausedAfterExtension else {
            XCTFail("The native +2 control did not leave the expected saved running timer. Next was not tapped. See QA_STEP_NATIVE and QA_STEP_SAVED scalar diagnostics.")
            return
        }

        showNotificationCenter()
        let next = springboard.descendants(matching: .any).matching(identifier: "stepActivity.\(urlScheme).next")
        guard next.firstMatch.waitForExistence(timeout: 10), next.count == 1 else {
            XCTFail("The QA widget's uniquely identified Next link is not exposed. No system link was tapped.")
            return
        }
        next.firstMatch.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.state == .runningForeground },
            "The widget must route its \(urlScheme) URL to \(appName), rather than the original MORE app.")
        XCTAssertTrue(waitUntil(timeout: 10) {
            app.staticTexts["run.step"].exists && app.staticTexts["run.step"].label == self.secondStepTitle
        })
        XCTAssertFalse(app.buttons["stepTimer.openPage"].exists)
        // Notification Center uses the lock-screen widget presentation while the
        // phone stays unlocked. Physical lock/unlock remains an owner-run check.
    }

    private func launch(nativeActivity: Bool = false) throws -> XCUIApplication {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_SYSTEM_DEVICE_TEST_ENABLED"] == "1",
            "Explicit physical test-app opt-in required; this can request alarm authorization and invoke Siri.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: qaBundle)
        if isLab {
            app.launchArguments = ["--qa-system-checks", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchEnvironment.removeValue(forKey: "MORNING_OPERATOR_DATA_DIR")
        } else {
            app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
                "--ui-testing-briefing-fixture", "--ui-testing-workspace=\(UUID().uuidString)",
                "--qa-system-checks", "--light-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            if nativeActivity { app.launchArguments.append("--ui-testing-live-activity") }
        }
        runningApp = app
        // XCTest's synchronous tearDown override is nonisolated in Swift 6.
        // Its async teardown block may explicitly hop to the UI's main actor.
        addTeardownBlock { @MainActor [weak self] () async throws in
            self?.cleanup()
        }
        app.launch()
        let identity = app.staticTexts["system.qaIdentity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10), "The QA-only guard must exist before system interaction.")
        XCTAssertEqual(identity.label, "\(qaBundle)|\(urlScheme)", "System checks must never target the original MORE bundle or URL scheme.")
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        if isLab {
            prepareLabSample(in: app)
        } else {
            syntheticWorkspaceConfirmed = true
        }
        return app
    }

    private func prepareLabSample(in app: XCUIApplication) {
        let source = app.staticTexts["routine.source"].firstMatch
        if !source.waitForExistence(timeout: 3) {
            let sample = app.buttons["routine.sample"]
            guard sample.exists && sample.isHittable,
                  !app.buttons["run.pause"].exists, !app.buttons["run.resume"].exists else {
                XCTFail("Morning Lab must be empty or contain its visible Sample morning. No routine was replaced.")
                return
            }
            sample.tap()
        }
        guard source.waitForExistence(timeout: 5), source.label.hasPrefix("Sample morning") else {
            XCTFail("Morning Lab's routine is not explicitly labelled Sample morning. No existing data was replaced.")
            return
        }
        syntheticWorkspaceConfirmed = true
        guard !app.buttons["run.pause"].exists, !app.buttons["run.resume"].exists,
              !app.buttons["opening.routine"].exists else {
            XCTFail("Finish Morning Lab's existing synthetic run before beginning another system check. No sample was reseeded.")
            return
        }
        openRoutine(in: app)
        let approve = app.buttons["routine.approve"]
        if approve.waitForExistence(timeout: 2) {
            approve.tap()
        } else {
            let close = app.buttons["destination.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
        }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5))
    }

    private func restoreLabTarget(in app: XCUIApplication) {
        openRoutine(in: app)
        tap("routine.step.0", in: app)
        let target = app.buttons["step.targetApp"]
        reveal(target, in: app)
        target.tap()
        let none = app.buttons["None"].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5))
        none.tap()
        tap("step.save", in: app)
        tap("routine.approve", in: app)
        changedLabTarget = false
    }

    private func openSettings(in app: XCUIApplication) {
        MorningUITestNavigation.revealMorningAction("morning.settings", in: app)
        tap("morning.settings", in: app)
        XCTAssertTrue(app.buttons["setup.alarm"].waitForExistence(timeout: 5))
    }

    private func closeSettings(in app: XCUIApplication) {
        for title in ["Lock Screen", "Morning alarm"] {
            let done = app.navigationBars[title].buttons["Done"]
            if done.exists && done.isHittable { done.tap() }
        }
        let close = app.buttons["destination.close"]
        if close.exists && close.isHittable { close.tap() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5))
    }

    private func openRoutine(in app: XCUIApplication) {
        MorningUITestNavigation.revealMorningAction("morning.review", in: app)
        tap("morning.review", in: app)
        if !app.buttons["routine.step.0"].waitForExistence(timeout: 3) {
            tap("review.routine", in: app)
        }
        XCTAssertTrue(app.buttons["routine.step.0"].waitForExistence(timeout: 5))
    }

    private func setAlarmTime(hour: Int, minute: Int, in app: XCUIApplication) throws {
        let picker = app.datePickers["alarm.time"]
        reveal(picker, in: app)
        let wheels = picker.pickerWheels
        guard wheels.count == 2 || wheels.count == 3 else {
            XCTFail("The native alarm picker must expose two or three wheels before an alarm can be scheduled.")
            return
        }
        if wheels.count == 3 {
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: String(hour % 12 == 0 ? 12 : hour % 12))
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", minute))
            wheels.element(boundBy: 2).adjust(toPickerWheelValue: hour < 12 ? "AM" : "PM")
        } else {
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: String(hour))
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", minute))
        }
    }

    private func allowQAAlarmPromptIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        guard text.localizedCaseInsensitiveContains(appName), text.localizedCaseInsensitiveContains("alarm") else { return }
        let allow = alert.buttons["Allow"]
        if allow.exists { allow.tap() }
    }

    private func cancelAlarm(in app: XCUIApplication) {
        app.activate()
        if !app.buttons["alarm.save"].exists {
            closeSettings(in: app)
            openSettings(in: app)
            tap("setup.alarm", in: app)
        }
        let toggle = app.switches["alarm.enabled"].firstMatch
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Test alarm cleanup could not reach its toggle. Disable \(appName)'s alarm immediately.")
            return
        }
        set(toggle, enabled: false)
        tap("alarm.save", in: app)
        let status = app.staticTexts["alarm.status"]
        let removed = waitUntil(timeout: 15) {
            self.diagnostic(status, includes: ["scheduled:0", "recorded:0", "owned:0"]) && status.label == "Off"
        }
        alarmMayBeScheduled = !removed
        XCTAssertTrue(removed, "The real test alarm must be absent after cancellation. If this fails, disable \(appName)'s alarm immediately.")
    }

    private func stopSyntheticMorning(in app: XCUIApplication) {
        app.activate()
        for title in ["Lock Screen", "Morning alarm"] {
            let done = app.navigationBars[title].buttons["Done"]
            if done.exists && done.isHittable { done.tap() }
        }
        let close = app.buttons["destination.close"]
        if close.exists && close.isHittable { close.tap() }
        let webClose = app.buttons["web.close"]
        if webClose.exists && webClose.isHittable { webClose.tap() }
        let controls = app.buttons["run.controls"]
        if controls.exists && controls.isHittable {
            controls.tap()
            let stop = app.buttons["run.stop"]
            if stop.exists && stop.isHittable { stop.tap() }
        }
    }

    private func showNotificationCenter() {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.75)))
    }

    private func diagnostic(_ status: XCUIElement, includes expected: [String]) -> Bool {
        guard status.exists, let value = status.value as? String else { return false }
        let fields = Set(value.split(separator: "|").map(String.init))
        return expected.allSatisfy(fields.contains)
    }

    private func set(_ toggle: XCUIElement, enabled: Bool) {
        guard toggle.value as? String != (enabled ? "1" : "0") else { return }
        let native = toggle.switches.firstMatch
        if native.exists { native.tap() } else { toggle.tap() }
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        reveal(button, in: app)
        button.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<12 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "A synthetic check control must be visible before it is used.")
    }

    private func remaining(_ identifier: String, in app: XCUIApplication) throws -> Int {
        let label = app.staticTexts[identifier]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        return try XCTUnwrap(seconds(label.label), "Expected the synthetic step's minute:second timer.")
    }

    private func seconds(_ text: String) -> Int? {
        let values = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if text.contains(":"), values.count == 2 { return values[0] * 60 + values[1] }
        if text.localizedCaseInsensitiveContains("minute"), values.count == 2 { return values[0] * 60 + values[1] }
        if text.localizedCaseInsensitiveContains("minute"), values.count == 1 { return values[0] * 60 }
        if text.localizedCaseInsensitiveContains("second"), values.count == 1 { return values[0] }
        return nil
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expected], timeout: timeout) == .completed
    }
}
