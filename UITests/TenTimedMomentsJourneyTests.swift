import XCTest

/// Ten real session/timer transitions in an isolated DEBUG workspace. No source
/// movie, inference, speech recognition, browser action or provider effect runs.
/// The existing short-budget fixture allocates about five seconds per moment;
/// this is neither the 28-minute source nor its independent 120-second QA plan.
@MainActor
final class TenTimedMomentsJourneyTests: XCTestCase {
    func testTenTimedMomentsFinishInOrderAfterFifthMomentPauseAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--ui-testing-ten-moments", "--ui-testing-automation", "--ui-testing-short-budgets",
            "--ui-testing-approved", "--ui-testing-hands-free", "--light-preview", "--theme-phase=morning",
            "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        try requireWorkspace(workspace, app)
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 8))
        landscape.tap()
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()

        var observed: [Snapshot] = []
        let first = try waitForMoment(0, in: app)
        observed.append(first)
        for index in 1..<10 {
            let current = try waitForMoment(index, in: app, session: first.sessionID)
            XCTAssertEqual(current.routineID, first.routineID, "The approved version stays pinned.")
            observed.append(current)
            guard index == 4 else { continue }

            revealControls(app)
            let playback = app.buttons["morning.playback"]
            XCTAssertEqual(playback.label, "Pause")
            playback.tap()
            XCTAssertTrue(playback.waitForExistence(timeout: 3))
            XCTAssertEqual(playback.label, "Continue")
            let paused = try snapshot(app)
            XCTAssertEqual(paused, current, "Pause cannot move to a different moment.")
            attach("ten-timed-fifth-moment-paused", app)

            app.terminate()
            // Removing the seed approval flag ensures the saved session supplies
            // approval; all three diagnostic flags remain for read-only identity.
            app.launchArguments.removeAll { $0 == "--ui-testing-approved" }
            app.launch()
            try requireWorkspace(workspace, app)
            let restored = try waitForMoment(4, in: app, session: first.sessionID)
            XCTAssertEqual(restored, paused)
            let captions = app.scrollViews["morning.captions"]
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(
                format: "exists == false OR value != %@", paused.raw), object: captions)
            changed.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 7), .completed,
                           "A restored pause must outlast a full short budget without advancing.")
            XCTAssertEqual(try snapshot(app), paused)
            revealControls(app)
            XCTAssertEqual(app.buttons["morning.playback"].label, "Continue")
            app.buttons["morning.playback"].tap()
        }
        XCTAssertEqual(observed.map(\.index), Array(0..<10))
        XCTAssertEqual(Set(observed.map(\.stepID)).count, 10)
        XCTAssertTrue(observed.allSatisfy { $0.sessionID == first.sessionID && $0.routineID == first.routineID })
        XCTAssertTrue(MorningUITestNavigation.waitForCompletedMorning(in: app, timeout: 15))
        try requireTimedRecap(app)
        attach("ten-timed-completed-recap-no-provider-effect", app)

        let trace = try JSONSerialization.data(withJSONObject: [
            "scope": "Observed AX identities and timed recap only; no provider, browser, OCR, model or acoustic proof.",
            "workspaceID": workspace,
            "moments": observed.map { ["sessionID": $0.sessionID, "stepID": $0.stepID,
                                      "routineVersionID": $0.routineID, "index": String($0.index)] }
        ], options: [.prettyPrinted, .sortedKeys])
        let evidence = XCTAttachment(string: String(decoding: trace, as: UTF8.self))
        evidence.name = "ten-timed-actual-session-order-ax"
        evidence.lifetime = .keepAlways
        add(evidence)
        app.terminate(); app.launch()
        try requireWorkspace(workspace, app)
        try requireTimedRecap(app)
        attach("ten-timed-recap-restored-no-provider-effect", app)
    }

    private struct Snapshot: Equatable {
        let sessionID: String, stepID: String, routineID: String
        let index: Int
        var raw: String { "\(sessionID)|\(stepID)|\(routineID)|\(index)" }
    }

    private func snapshot(_ app: XCUIApplication) throws -> Snapshot {
        let raw = try XCTUnwrap(app.scrollViews["morning.captions"].value as? String)
        let fields = raw.components(separatedBy: "|")
        XCTAssertEqual(fields.count, 4, "Expected only the explicitly enabled DEBUG identity diagnostic.")
        guard fields.count == 4 else { throw InvalidDiagnostic.fields }
        for value in fields.prefix(3) { XCTAssertNotNil(UUID(uuidString: value)) }
        let index = try XCTUnwrap(Int(fields[3]))
        XCTAssertTrue((0..<10).contains(index))
        return Snapshot(sessionID: fields[0], stepID: fields[1], routineID: fields[2], index: index)
    }

    private func waitForMoment(_ index: Int, in app: XCUIApplication, session: String? = nil) throws -> Snapshot {
        let captions = app.scrollViews["morning.captions"]
        let predicate = session.map { NSPredicate(format: "exists == true AND value BEGINSWITH %@ AND value ENDSWITH %@",
            $0 + "|", "|\(index)") } ?? NSPredicate(format: "exists == true AND value ENDSWITH %@", "|\(index)")
        let reached = XCTNSPredicateExpectation(predicate: predicate, object: captions)
        XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: 20), .completed,
                       "Each actual moment must be observed; a skipped index cannot be inferred from the final count.")
        let current = try snapshot(app)
        XCTAssertEqual(current.index, index)
        return current
    }

    private func requireWorkspace(_ workspace: String, _ app: XCUIApplication) throws {
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) { app.terminate(); app.launch() }
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(try XCTUnwrap(marker.value as? String), workspace)
    }

    private func revealControls(_ app: XCUIApplication) {
        if app.buttons["morning.settings"].exists && app.buttons["morning.playback"].isHittable { return }
        let captions = app.scrollViews["morning.captions"]
        XCTAssertTrue(captions.waitForExistence(timeout: 5))
        captions.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        XCTAssertTrue(app.buttons["morning.playback"].waitForExistence(timeout: 5))
    }

    private func requireTimedRecap(_ app: XCUIApplication) throws {
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 8))
        landscape.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let completed = app.staticTexts["morning.completeSummary"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.hasPrefix("10 moments"))
        let summary = app.staticTexts["morning.executionSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Timed moments finished: 10.",
                       "Elapsed budgets must not claim operations, sends, writes, likes or browser observations.")
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = name; evidence.lifetime = .keepAlways
        add(evidence)
    }

    private enum InvalidDiagnostic: Error { case fields }
}
