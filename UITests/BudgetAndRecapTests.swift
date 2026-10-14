import XCTest

/// The time budget in the routine editor and the recap after a morning (#10), on the
/// synthetic sample routine only: 3 + 5 + 3 + 8 planned minutes, the last moment required.
/// Each launch uses its own temporary workspace with speech and automatic progression off.
@MainActor
final class BudgetAndRecapTests: XCTestCase {
    func testNoTargetShowsNoBudgetAndATargetOffersBothChoicesWithoutChangingSteps() {
        let app = launch()
        MorningUITestNavigation.openRoutine(in: app)
        XCTAssertTrue(app.buttons["budget.setTarget"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("budget.total", in: app).exists, "No target must show no budget report.")
        XCTAssertFalse(app.steppers["budget.target"].exists)
        XCTAssertFalse(app.buttons["budget.choice.acceptLongerPlan"].exists)
        let steps = stepLabels(in: app)
        XCTAssertEqual(steps.count, 4)

        // The first target is one the 19-minute plan already fits: nothing to decide.
        tapAboveInset("budget.setTarget", in: app)
        reveal("budget.within", in: app)
        XCTAssertEqual(element("budget.total", in: app).label, "Planned: 19 minutes")
        XCTAssertFalse(app.buttons["budget.choice.editRoutine"].exists)
        XCTAssertFalse(app.buttons["budget.choice.acceptLongerPlan"].exists)

        lowerTarget(in: app)
        let over = element("budget.over", in: app)
        reveal("budget.over", in: app)
        XCTAssertEqual(over.label, "That is 4 minutes more than your target.")
        XCTAssertFalse(element("budget.requiredOver", in: app).exists)
        XCTAssertTrue(app.buttons["budget.choice.editRoutine"].exists)
        XCTAssertTrue(app.buttons["budget.choice.acceptLongerPlan"].exists)
        XCTAssertEqual(stepLabels(in: app), steps)
        attach("budget-over-target-both-choices", app)

        // Keep editing leaves the note and the routine exactly as they are.
        tapAboveInset("budget.choice.editRoutine", in: app)
        reveal("budget.editHint", in: app)
        XCTAssertTrue(app.buttons["budget.choice.acceptLongerPlan"].exists)
        XCTAssertEqual(stepLabels(in: app), steps)

        // Below the eight required minutes, the report says so. Nothing is trimmed.
        lowerTarget(in: app)
        lowerTarget(in: app)
        reveal("budget.requiredOver", in: app)
        XCTAssertEqual(element("budget.over", in: app).label, "That is 14 minutes more than your target.")
        XCTAssertEqual(stepLabels(in: app), steps)
        attach("budget-required-moments-alone-over-target", app)

        // Keeping the longer plan quiets the choices and still changes no step.
        tapAboveInset("budget.choice.acceptLongerPlan", in: app)
        reveal("budget.accepted", in: app)
        XCTAssertFalse(app.buttons["budget.choice.editRoutine"].exists)
        XCTAssertFalse(app.buttons["budget.choice.acceptLongerPlan"].exists)
        XCTAssertEqual(stepLabels(in: app), steps)
        XCTAssertFalse(app.buttons["routine.step.4"].exists)
        attach("budget-longer-plan-kept", app)

        tapAboveInset("budget.clearTarget", in: app)
        XCTAssertTrue(app.buttons["budget.setTarget"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("budget.total", in: app).exists)
        XCTAssertEqual(stepLabels(in: app), steps)
    }

    func testCompletedMorningShowsItsRecapAndStoresNoFeedbackUntilAnswered() {
        let app = launch(approved: true)
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("run.start", in: app)
        for _ in 0..<4 { advance(in: app) }
        let state = app.staticTexts["run.state"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "completed"), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed)

        MorningUITestNavigation.selectTab("Review", in: app)
        reveal("recap.completed", in: app)
        XCTAssertEqual(element("recap.ending", in: app).label, "You reached the end of the routine.")
        XCTAssertTrue(element("recap.completed", in: app).label.hasPrefix("4 moments completed"))
        XCTAssertFalse(element("recap.skipped", in: app).exists)
        XCTAssertFalse(element("recap.unfinished", in: app).exists)
        XCTAssertTrue(element("recap.saved", in: app).exists)
        XCTAssertFalse(element("recap.notSaved", in: app).exists)
        XCTAssertFalse(app.buttons["recap.retrySave"].exists)
        XCTAssertFalse(element("recap.feedbackSaved", in: app).exists, "Leaving the questions alone must store nothing.")
        attach("recap-completed-morning", app)

        // The recap is rebuilt from the saved run after a relaunch; unanswered questions left nothing.
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-approved" }
        app.launch()
        MorningUITestNavigation.selectTab("Review", in: app)
        reveal("recap.completed", in: app)
        XCTAssertTrue(element("recap.saved", in: app).exists)
        XCTAssertFalse(element("recap.feedbackSaved", in: app).exists)
        XCTAssertFalse(app.buttons["recap.useful.yes"].isSelected)
        XCTAssertFalse(app.buttons["recap.enjoyable.yes"].isSelected)

        // An answer is stored; choosing it again clears it and leaves nothing.
        tap("recap.useful.yes", in: app)
        reveal("recap.feedbackSaved", in: app)
        XCTAssertTrue(app.buttons["recap.useful.yes"].isSelected)
        XCTAssertFalse(app.buttons["recap.enjoyable.yes"].isSelected)
        tap("recap.useful.yes", in: app)
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                object: element("recap.feedbackSaved", in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)

        // Not checked here: the recap on the day's own page. The fixture run is a sample, and
        // sample runs are left out of history days on purpose, so that page shows no run.
        XCTAssertTrue(element("recap.sample", in: app).exists, "A sample run must be labelled as one.")
    }

    func testStoppedMorningRecapNamesWhatWasNotReached() {
        let app = launch(approved: true)
        stopAfterOneMoment(in: app)
        MorningUITestNavigation.selectTab("Review", in: app)
        reveal("recap.unfinished", in: app)
        XCTAssertEqual(element("recap.ending", in: app).label, "You stopped before the end.")
        XCTAssertTrue(element("recap.completed", in: app).label.hasPrefix("1 moment completed"))
        XCTAssertTrue(element("recap.unfinished", in: app).label.hasPrefix("3 moments not reached"))
        XCTAssertFalse(element("recap.skipped", in: app).exists)
        XCTAssertTrue(element("recap.saved", in: app).exists)
        attach("recap-stopped-morning", app)

        // Stopping changed neither the routine nor its approval.
        MorningUITestNavigation.reviewAction("review.routine", in: app)
        XCTAssertTrue(app.buttons["routine.step.3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["routine.step.4"].exists)
        XCTAssertFalse(app.buttons["routine.approve"].exists, "A stopped run must leave the approved routine approved.")
    }

    // Named screenshots of both screens for a visual read; no wording is asserted.
    // Like InterfaceTourTests, each starts from a fresh launch and reaches its screens by
    // scrolling and tapping identified rows, never through the sunrise dock. The ended run
    // is seeded (`--ui-testing-stopped-run`: the sample stopped after its first moment, saved).
    // The largest text size is set for the app alone, so these run in the ordinary pass.
    func testTourEnglish() { tour("en", language: english) }
    func testTourFrench() { tour("fr", language: french) }
    func testTourEnglishLargestText() { tour("en-largest-text", language: english + largestText) }
    func testTourFrenchLargestText() { tour("fr-largest-text", language: french + largestText) }

    private var english: [String] { ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] }
    private var french: [String] { ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"] }
    private var largestText: [String] {
        ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }

    private func tour(_ name: String, language: [String]) {
        let app = launch(approved: true, language: language + ["--ui-testing-stopped-run"])
        MorningUITestNavigation.selectTab("Review", in: app)
        scrollUntilVisible(element("recap.ending", in: app), in: app)
        attachSettled("tour-recap-\(name)", app)
        scrollUntilVisible(element("recap.enjoyable.no", in: app), in: app)
        attachSettled("tour-recap-questions-\(name)", app)

        scrollUntilVisible(app.buttons["review.routine"], in: app)
        app.buttons["review.routine"].tap()
        XCTAssertTrue(element("routine.step.0", in: app).waitForExistence(timeout: 10), app.debugDescription)
        scrollUntilVisible(app.buttons["budget.setTarget"], in: app)
        app.buttons["budget.setTarget"].tap()
        for _ in 0..<3 { lowerTarget(in: app) }
        scrollUntilVisible(element("budget.requiredOver", in: app), in: app)
        attachSettled("tour-budget-\(name)", app)
        scrollUntilVisible(app.buttons["budget.choice.acceptLongerPlan"], in: app)
        attachSettled("tour-budget-choices-\(name)", app)
    }

    /// Swipes up until the element exists and can be tapped; at the largest text size a
    /// row can start far below the fold, and a list row below it is not created yet.
    private func scrollUntilVisible(_ target: XCUIElement, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        _ = target.waitForExistence(timeout: 10)
        for _ in 0..<14 where !(target.exists && target.isHittable) { app.swipeUp() }
        XCTAssertTrue(target.exists && target.isHittable, app.debugDescription, file: file, line: line)
    }

    private func attachSettled(_ name: String, _ app: XCUIApplication) {
        // The picture only: a bounded pause lets a scroll or a sheet come to rest.
        let settled = expectation(description: "Settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        attach(name, app)
    }

    private func launch(approved: Bool = false,
                        language: [String] = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
                               "--ui-testing-workspace=\(UUID().uuidString)"] + language
        if approved { app.launchArguments.append("--ui-testing-approved") }
        app.launch()
        return app
    }

    private func tap(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        MorningUITestNavigation.tapButton(identifier, in: app, file: file, line: line)
    }

    /// Marks the current moment complete and waits for the run to move on.
    private func advance(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let step = app.staticTexts["run.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5), file: file, line: line)
        let before = step.label
        tap("run.next", in: app, file: file, line: line)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: step)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, file: file, line: line)
    }

    private func stopAfterOneMoment(in app: XCUIApplication) {
        MorningUITestNavigation.selectTab("Morning", in: app)
        tap("run.start", in: app)
        advance(in: app)
        tap("run.controls", in: app)
        tap("run.stop", in: app)
        let pause = app.buttons["run.pause"]
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pause)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed)
    }

    /// The stepper's own decrement button: five minutes less.
    private func lowerTarget(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let stepper = app.steppers["budget.target"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), file: file, line: line)
        let before = stepper.value as? String ?? ""
        reveal("budget.target-Decrement", in: app, file: file, line: line)
        element("budget.target-Decrement", in: app).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: stepper)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, file: file, line: line)
    }

    /// A draft's "Approve this routine" bar covers the bottom of the routine list, and the
    /// accessibility frame of a row under it still reads as hittable. Scroll the row above
    /// the bar first, so the tap reaches the row and never the approval.
    private func tapAboveInset(_ identifier: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        reveal(identifier, in: app, file: file, line: line)
        let target = element(identifier, in: app)
        let approve = app.buttons["routine.approve"]
        let list = app.collectionViews.containing(.any, identifier: identifier).firstMatch
        for _ in 0..<6 where approve.exists && target.frame.maxY > approve.frame.minY - 8 && list.exists {
            list.swipeUp()
        }
        if approve.exists {
            XCTAssertLessThan(target.frame.maxY, approve.frame.minY, "\(identifier) is still under the approval bar",
                              file: file, line: line)
        }
        XCTAssertTrue(target.isHittable, "Not visible: \(identifier)", file: file, line: line)
        target.tap()
    }

    /// Any element with this identifier, whatever kind the system reports for it.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls the list or page that holds the element until it can be seen.
    private func reveal(_ identifier: String, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing: \(identifier)", file: file, line: line)
        for _ in 0..<8 where !target.isHittable {
            let collection = app.collectionViews.containing(.any, identifier: identifier).firstMatch
            let scroll = app.scrollViews.containing(.any, identifier: identifier).firstMatch
            let container = collection.exists ? collection : scroll
            guard container.exists else { break }
            if target.frame.height > 0, target.frame.midY < container.frame.midY { container.swipeDown() }
            else { container.swipeUp() }
        }
        XCTAssertTrue(target.isHittable, "Not visible: \(identifier)", file: file, line: line)
    }

    /// The routine's rows, read from the top of the list: a native list creates only the rows
    /// near the screen, so after scrolling down to the budget the first rows may not exist.
    private func stepLabels(in app: XCUIApplication) -> [String] {
        let first = app.buttons["routine.step.0"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 where !(first.exists && first.isHittable) && list.exists { list.swipeDown() }
        XCTAssertTrue(first.exists, "The routine list did not return to its first row.")
        return (0..<8).map { app.buttons["routine.step.\($0)"] }.filter(\.exists).map(\.label)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
