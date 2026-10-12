import XCTest

/// Explicitly opted-in, read-only navigation in Apple's Clock. Never touches alarm rows,
/// switches, edit/add/delete buttons, timers, or the stopwatch. Evidence stays in XCTest.
@MainActor
final class ClockObservationTests: XCTestCase {
    func testClockTabsAndReadOnlyAlarmScroll() throws {
        guard ProcessInfo.processInfo.environment["MO_CLOCK_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Clock navigation requires MO_CLOCK_TEST_ENABLED=1. No external app was opened.")
        }
        continueAfterFailure = false
        let clock = XCUIApplication(bundleIdentifier: "com.apple.mobiletimer")
        clock.launch()
        XCTAssertTrue(clock.wait(for: .runningForeground, timeout: 8), "Clock did not enter the foreground.")
        try requireNoPrompt(in: clock)
        let alarmLabel = try observedAlarmTabLabel(in: clock)
        _ = try exactTab("World Clock", in: clock)

        try selectTab("World Clock", other: alarmLabel, in: clock)
        attachScreen(clock, named: "clock-world-clock-selected")
        try selectTab(alarmLabel, other: "World Clock", in: clock)
        attachScreen(clock, named: "clock-alarms-selected-before-scroll")

        // Query only a visible scrolling container. Never use a cell, switch, or screen coordinate.
        if let list = alarmList(in: clock) {
            let before = visibleRows(in: list)
            try requireNoPrompt(in: clock)
            guard clock.state == .runningForeground,
                  try exactTab(alarmLabel, in: clock).isSelected,
                  list.exists, list.isHittable else {
                throw XCTSkip("Clock's selected Alarms list changed before the gesture; no scroll was issued.")
            }
            list.swipeUp()
            try requireNoPrompt(in: clock)
            XCTAssertTrue(try exactTab(alarmLabel, in: clock).isSelected,
                          "The read-only scroll must leave Alarms selected.")
            let changed = before != visibleRows(in: list)
            attachNote(changed
                ? "One upward gesture changed the visible alarm-list rows or their frames. No alarm control was tapped."
                : "One upward gesture was issued to the alarms list, but row movement was not observable (the list may fit on screen). No scrolling-distance claim is made.",
                named: "clock-scroll-observation")
            attachScreen(clock, named: "clock-alarms-after-scroll")
        } else {
            attachNote("Clock tab navigation was verified. No unique visible alarms table or scroll view was exposed, so no scrolling gesture was attempted.",
                       named: "clock-scroll-unavailable")
        }

        try selectTab("World Clock", other: alarmLabel, in: clock)
        attachScreen(clock, named: "clock-returned-to-world-clock")
        // Leave the read-only World Clock page visible for the developer's review.
    }

    private func observedAlarmTabLabel(in app: XCUIApplication) throws -> String {
        let observed = ["Alarms", "Alarm"].filter { label in
            app.tabBars.buttons.matching(NSPredicate(format: "label == %@", label)).count == 1
        }
        guard observed.count == 1, let label = observed.first else {
            throw XCTSkip("Clock did not expose exactly one English Alarms/Alarm tab. No guessed or localized control was tapped.")
        }
        return label
    }

    private func exactTab(_ label: String, in app: XCUIApplication) throws -> XCUIElement {
        let matches = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", label))
        guard matches.count == 1 else {
            throw XCTSkip("Clock did not expose a unique English '\(label)' tab. No fallback tap was attempted.")
        }
        let tab = matches.element(boundBy: 0)
        guard tab.exists, tab.isHittable else {
            throw XCTSkip("Clock's '\(label)' tab is not visible and tappable.")
        }
        return tab
    }

    private func selectTab(_ label: String, other: String, in app: XCUIApplication) throws {
        try requireNoPrompt(in: app)
        guard app.state == .runningForeground else { throw XCTSkip("Clock is no longer in the foreground.") }
        let target = try exactTab(label, in: app)
        let frame = target.frame
        let refreshed = try exactTab(label, in: app)
        guard refreshed.frame == frame else { throw XCTSkip("Clock tab layout changed before navigation.") }
        refreshed.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: refreshed)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed,
                       "The requested Clock tab was not selected.")
        XCTAssertFalse(try exactTab(other, in: app).isSelected,
                       "Two different tabs cannot both satisfy the navigation postcondition.")
        try requireNoPrompt(in: app)
    }

    private func alarmList(in app: XCUIApplication) -> XCUIElement? {
        let tables = app.tables.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        if tables.count == 1 { return tables[0] }
        if !tables.isEmpty { return nil }
        let scrollViews = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        return scrollViews.count == 1 ? scrollViews[0] : nil
    }

    private struct RowObservation: Equatable {
        let label: String
        let frame: CGRect
    }

    private func visibleRows(in list: XCUIElement) -> [RowObservation] {
        // Kept only in process for before/after comparison; alarm labels are never printed/exported.
        list.cells.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            .map { RowObservation(label: $0.label, frame: $0.frame) }
    }

    private func requireNoPrompt(in app: XCUIApplication) throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard app.alerts.count == 0, app.sheets.count == 0, springboard.alerts.count == 0 else {
            throw XCTSkip("An unexpected prompt is visible. No prompt was accepted or dismissed.")
        }
    }

    private func attachScreen(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if ProcessInfo.processInfo.environment["MO_CAPTURE_UI_TREE"] == "1" {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(name)-accessibility-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    private func attachNote(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
