import XCTest

/// Production review and persistence over the existing, explicitly synthetic archive.
/// No capture, OCR, inference, microphone, or native speech request occurs in these tests.
@MainActor
final class ObservedMorningOverviewTests: XCTestCase {
    private let sourceA = "00000000-0000-4000-8000-000000000101"
    private let sourceC = "00000000-0000-4000-8000-000000000103"
    private let lumenSample = "00000000-0000-4000-8000-000000010103"
    private let unknownSample = "00000000-0000-4000-8000-000000010301"
    private let fixtureLine = "Synthetic fixture only. No app was opened, movie captured, OCR performed or model called."

    func testObservedOverviewKeepsUnknownsAndPartitionsAndUpdatesAfterCorrection() throws {
        let app = launchFixture()
        approveBaseline(in: app)
        relaunchWithoutSeed(app)
        openReview(in: app)
        let heading = element("review.observedOverview", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(heading.isHittable, "Observed mornings should be reachable before opening another screen.\n\(app.debugDescription)")
        attach("observed-overview-first-review-screen", app)
        let timing = element("review.routineTiming", in: app)
        reveal(timing, in: app)
        wait(timing, matching: NSPredicate(format: "value == %@", "Collapsed"), in: app)
        XCTAssertFalse(app.staticTexts["review.average"].exists, "Routine timing stays separate from observed screens.")

        let zone = TimeZone.current.identifier
        let alternateZone = zone == "Pacific/Honolulu" ? "Asia/Tokyo" : "Pacific/Honolulu"
        assertPartition(zone: zone, origin: "synthetic", title: "Samples & tests",
                        coverage: "2 days with labeled samples · 3 days with observations", in: app)
        assertPartition(zone: zone, origin: "human", title: "Synthetic fixture · personal branch",
                        coverage: "1 day with labeled samples · 1 day with observations", in: app)
        assertPartition(zone: alternateZone, origin: "synthetic", title: "Samples & tests",
                        coverage: "1 day with labeled samples · 1 day with observations", in: app)
        attach("observed-overview-separate-origins-and-zones", app)

        openDay(offset: 0, in: app)
        let unresolved = element("review.observedClip.sequence.\(sourceC)", in: app)
        reveal(unresolved, in: app)
        XCTAssertEqual(unresolved.label, "Unknown screen → Unknown screen → Unknown screen")
        attach("observed-day-keeps-unknown-screens", app)
        openSample(sourceID: sourceC, sampleID: unknownSample, in: app)
        let originalUnknown = app.staticTexts["observation.sample.originalText.\(unknownSample)"]
        reveal(originalUnknown, in: app)
        XCTAssertEqual(originalUnknown.label, "Undecided scene\n\(fixtureLine)")
        XCTAssertFalse(app.staticTexts["observation.sample.quote.\(unknownSample)"].exists,
                       "An unknown sample cannot gain a fabricated recognition quote.")

        // Relaunch only to return to the root navigation; the existing archive is
        // loaded without its fixture flag, so navigation cannot silently reseed it.
        relaunchWithoutSeed(app)
        openReview(in: app)
        openDay(offset: -2, in: app)
        assertSequence("Cedar → Lumen → Cedar → Unknown screen → Cedar", sourceID: sourceA, in: app)
        openSample(sourceID: sourceA, sampleID: lumenSample, in: app)
        assertOriginalLumen(in: app)
        tap("observation.sample.correctLabel.\(lumenSample)", in: app)
        XCTAssertTrue(app.navigationBars["Screen label"].waitForExistence(timeout: 5), app.debugDescription)
        let field = app.textFields["sampleLabel.text"]
        reveal(field, in: app)
        let oldValue = field.value as? String ?? ""
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "Morning calendar")
        wait(field, matching: NSPredicate(format: "value == %@", "Morning calendar"), in: app)
        if app.buttons["sampleLabel.keyboardDone"].isHittable { app.buttons["sampleLabel.keyboardDone"].tap() }
        tap("sampleLabel.save", in: app)
        waitForAbsence(app.navigationBars["Screen label"], in: app)
        assertOriginalLumen(in: app)

        relaunchWithoutSeed(app)
        openReview(in: app)
        let recurrence = app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label CONTAINS %@", "review.observed.", "Morning calendar")).firstMatch
        // The week overview and day sequence must derive the persisted correction,
        // not a detached copy of the old classifier result.
        reveal(recurrence, in: app)
        openDay(offset: -2, in: app)
        assertSequence("Cedar → Morning calendar → Cedar → Unknown screen → Cedar", sourceID: sourceA, in: app)
        attach("observed-day-correction-after-relaunch", app)
        openSample(sourceID: sourceA, sampleID: lumenSample, in: app)
        let reviewed = element("observation.sample.userLabel.\(lumenSample)", in: app)
        reveal(reviewed, in: app)
        wait(reviewed, matching: NSPredicate(format: "value == %@", "Morning calendar"), in: app)
        assertOriginalLumen(in: app)
        attach("observed-day-correction-original-quote-intact", app)
    }

    func testSourceQuotePreselectsExactNarrationAndOnlyExplicitAddCreatesDraft() throws {
        let app = launchFixture()
        // Persist the baseline through the real approval action. A launch-only
        // approved fixture would not establish a saved routine for the cancel check.
        approveBaseline(in: app)

        openReview(in: app)
        openDay(offset: -2, in: app)
        openSample(sourceID: sourceA, sampleID: lumenSample, in: app)
        assertOriginalLumen(in: app)
        let preparedText = openPreselectedNarration(in: app)
        attach("source-quote-exact-preselected-narration", app)
        tap("narration.done", in: app)
        waitForAbsence(app.navigationBars["A saved moment"], in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 5), app.debugDescription)

        relaunchWithoutSeed(app)
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5), "Cancel must leave the saved approval unchanged.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["morning.reviewDraft"].exists)
        MorningUITestNavigation.openRoutine(in: app)
        let baseline = app.buttons["routine.step.0"]
        XCTAssertTrue(baseline.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(baseline.label.contains("Your morning"), baseline.debugDescription)
        MorningUITestNavigation.closeRoutine(in: app)

        openDay(offset: -2, in: app)
        openSample(sourceID: sourceA, sampleID: lumenSample, in: app)
        XCTAssertEqual(openPreselectedNarration(in: app), preparedText)
        tap("narration.add", in: app)
        let message = app.staticTexts["narration.message"]
        reveal(message, in: app)
        wait(message, matching: NSPredicate(format: "label == %@", "Review and approve your updated morning before running it."), in: app)
        tap("narration.done", in: app)
        waitForAbsence(app.navigationBars["A saved moment"], in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["run.start"].exists, "Reading source evidence cannot authorize automatic execution.")

        relaunchWithoutSeed(app)
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["run.start"].exists)
        MorningUITestNavigation.openRoutine(in: app)
        let added = app.buttons["routine.step.0"]
        XCTAssertTrue(added.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(added.label.contains("A saved moment"), added.debugDescription)
        tap(added, in: app)
        XCTAssertTrue(app.navigationBars["Make it yours"].waitForExistence(timeout: 5), app.debugDescription)
        let exactText = app.staticTexts.matching(NSPredicate(format: "label == %@", preparedText)).firstMatch
        reveal(exactText, in: app)
        XCTAssertTrue(exactText.label.utf8.elementsEqual(preparedText.utf8), exactText.debugDescription)
        attach("source-quote-saved-draft-keeps-exact-preview", app)
    }

    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
            "--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-observation-review"]
        app.launch()
        return app
    }

    private func relaunchWithoutSeed(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-observation-review" }
        app.launch()
    }

    private func approveBaseline(in app: XCUIApplication) {
        MorningUITestNavigation.openRoutine(in: app)
        tap("routine.approve", in: app)
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["morning.actions"].tap()
    }

    private func openReview(in app: XCUIApplication) {
        // The home date is the intended direct route into review. It remains
        // available when native tab minimization hides the other tab buttons.
        tap("morning.date", in: app)
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("review.week", in: app).waitForExistence(timeout: 5), app.debugDescription)
    }

    private func openDay(offset: Int, in app: XCUIApplication) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let day = app.buttons["review.day.\(formatter.string(from: date))"]
        if !day.exists { tap("review.period", in: app) }
        tap(day, in: app)
        XCTAssertTrue(element("review.dayDetail", in: app).waitForExistence(timeout: 5), app.debugDescription)
    }

    private func assertPartition(zone: String, origin: String, title: String, coverage: String, in app: XCUIApplication) {
        let key = "\(zone)|\(origin)"
        let group = element("review.observed.group.\(key)", in: app)
        reveal(group, in: app)
        XCTAssertTrue(group.label.contains(title), group.debugDescription)
        let count = element("review.observed.coverage.\(key)", in: app)
        reveal(count, in: app)
        XCTAssertEqual(count.label, coverage, "Origins and zones must have independent denominators.\n\(count.debugDescription)")
    }

    private func assertSequence(_ expected: String, sourceID: String, in app: XCUIApplication) {
        let sequence = element("review.observedClip.sequence.\(sourceID)", in: app)
        reveal(sequence, in: app)
        XCTAssertEqual(sequence.label, expected, sequence.debugDescription)
    }

    private func openSample(sourceID: String, sampleID: String, in app: XCUIApplication) {
        tap(element("review.observedClip.samples.\(sourceID)", in: app), in: app)
        tap(element("review.observedClip.sample.\(sourceID).\(sampleID)", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Sampled moment"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func assertOriginalLumen(in app: XCUIApplication) {
        let quote = app.staticTexts["observation.sample.quote.\(lumenSample)"]
        reveal(quote, in: app)
        XCTAssertEqual(quote.label, "Lumen")
        let original = app.staticTexts["observation.sample.originalText.\(lumenSample)"]
        reveal(original, in: app)
        XCTAssertTrue(original.label.utf8.elementsEqual("Lumen\n\(fixtureLine)".utf8), original.debugDescription)
    }

    private func openPreselectedNarration(in app: XCUIApplication) -> String {
        tap("observation.sample.readMoment.\(lumenSample)", in: app)
        XCTAssertTrue(app.navigationBars["A saved moment"].waitForExistence(timeout: 5), app.debugDescription)
        let preview = app.staticTexts["narration.text"]
        reveal(preview, in: app)
        XCTAssertTrue(preview.label.hasSuffix("Lumen"), "The displayed quote must already be selected without choosing a different candidate.\n\(preview.debugDescription)")
        XCTAssertTrue(preview.label.contains("synthetic sample"), preview.debugDescription)
        XCTAssertFalse(preview.label.contains(fixtureLine), "Preselection must preserve this frame's displayed header, not its other line.")
        let playback = element("narration.playback", in: app)
        reveal(playback, in: app)
        wait(playback, matching: NSPredicate(format: "value == %@", "idle"), in: app)
        return preview.label
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func visibleList(in app: XCUIApplication) -> XCUIElement {
        let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            + app.scrollViews.allElementsBoundByIndex
        guard let list = lists.first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("No visible native list.\n\(app.debugDescription)")
            return app.collectionViews.firstMatch
        }
        return list
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 1)
        for _ in 0..<10 where !element.exists || !element.isHittable {
            let list = visibleList(in: app)
            if element.exists, element.frame.height > 0, element.frame.midY < list.frame.midY { list.swipeDown() }
            else { list.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) { tap(app.buttons[identifier], in: app) }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    private func wait(_ element: XCUIElement, matching predicate: NSPredicate, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, app.debugDescription)
    }

    private func waitForAbsence(_ element: XCUIElement, in app: XCUIApplication) {
        wait(element, matching: NSPredicate(format: "exists == false"), in: app)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MOREObservedMorningOverviewScreenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        } catch {
            XCTFail("Could not retain the synthetic visual check: \(error)")
        }
    }
}
