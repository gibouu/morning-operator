import XCTest
import UIKit

/// Isolated permission explanations, persistence and weather-source selection.
/// Synthetic sources never change iOS authorizations or contact weather providers.
@MainActor
final class MorningPermissionSetupTests: XCTestCase {
    func testOneAcceptTapContinuesPastDeniedAccessesAndPersistsWithoutLearningMenu() {
        let app = launchFixture(denied: true)
        assertInitialAccessSummary(in: app)
        XCTAssertEqual(app.buttons["permissions.allow"].label, "Accept")
        XCTAssertEqual(app.staticTexts["permissions.title.speech"].label, "Microphone & speech recognition")
        XCTAssertFalse(app.staticTexts["permissions.saveIssue"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        let allow = app.buttons["permissions.allow"]
        reveal(allow, app); allow.tap()
        XCTAssertTrue(app.staticTexts["routinePreparation.heading"].waitForExistence(timeout: 10),
                      "A single tap must complete the whole fixture sequence despite denied access: \(app.debugDescription)")
        finishInitialRoutinePreparationIfVisible(app)
        assertHomeWithoutFurtherSetup(app)
        app.terminate(); launchConfirmedWorkspace(app)
        XCTAssertFalse(app.buttons["permissions.allow"].waitForExistence(timeout: 2),
                       "Denied access choices must not repeat on the next launch.")
        openPermissionOptions(app)
        selectPermissionOption("speech", in: app)
        reveal(allow, app); allow.tap()
        XCTAssertTrue(app.buttons["permissions.option.speech"].waitForExistence(timeout: 5),
                      "A Settings access choice returns to the list instead of starting the sequence.")
        XCTAssertFalse(app.buttons["permissions.allow"].exists)
    }

    func testSkippingAllAccessesOpensRoutinePreparationAndPersistsAcrossRelaunch() {
        let app = launchFixture()
        assertInitialAccessSummary(in: app)
        let skip = app.buttons["permissions.skip"]
        reveal(skip, app)
        XCTAssertEqual(skip.label, "Not now")
        XCTAssertEqual(app.alerts.count, 0)
        attach("synthetic-single-access-summary", app)
        skip.tap()
        XCTAssertTrue(app.staticTexts["routinePreparation.heading"].waitForExistence(timeout: 5), app.debugDescription)
        finishInitialRoutinePreparationIfVisible(app)
        assertHomeWithoutFurtherSetup(app)
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate(); launchConfirmedWorkspace(app)
        assertHomeWithoutFurtherSetup(app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testFrenchLargestTextKeepsSummaryAndBothChoicesReachableInPortraitAndLandscape() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchFixture(frenchLargestText: true, phase: "night")
        assertInitialAccessSummary(in: app)
        XCTAssertEqual(app.buttons["permissions.allow"].label, "Accepter")
        XCTAssertEqual(app.staticTexts["permissions.title.speech"].label, "Micro et reconnaissance vocale")
        XCTAssertEqual(app.buttons["permissions.skip"].label, "Plus tard")
        XCTAssertFalse(app.staticTexts["permissions.explanation"].exists,
                       "The summary starts with short explanations of each access.")
        for identifier in ["permissions.title.speech", "permissions.note", "permissions.allow", "permissions.skip"] {
            let control = element(identifier, in: app)
            reveal(control, app)
            assertFitsHorizontally(control, app)
        }
        attach("permissions-night-fr-largest-summary-portrait", app)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.frame
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed, app.debugDescription)
        for identifier in ["permissions.note", "permissions.allow", "permissions.skip"] {
            let control = element(identifier, in: app)
            reveal(control, app)
            assertFitsHorizontally(control, app)
        }
        XCTAssertFalse(app.buttons["permissions.learn"].exists)
        XCTAssertFalse(app.buttons["permissions.finish"].exists)
        attach("permissions-night-fr-largest-summary-landscape", app, screenshot: XCUIScreen.main.screenshot())
        skipInitialAccesses(in: app)
        finishInitialRoutinePreparationIfVisible(app)
        assertHomeWithoutFurtherSetup(app)
    }

    func testOneAcceptTapCompletesAllAccessChoicesAndPersistsWithoutRepeatingSetup() {
        let app = launchFixture()
        assertInitialAccessSummary(in: app)
        let allow = app.buttons["permissions.allow"]
        reveal(allow, app); allow.tap()
        XCTAssertTrue(app.staticTexts["routinePreparation.heading"].waitForExistence(timeout: 10),
                      "No extra app permission page may require a second tap: \(app.debugDescription)")
        finishInitialRoutinePreparationIfVisible(app)
        assertHomeWithoutFurtherSetup(app)
        XCTAssertEqual(app.alerts.count, 0, "The isolated access fixture never requests system permissions.")
        app.terminate(); launchConfirmedWorkspace(app)
        assertHomeWithoutFurtherSetup(app)
        XCTAssertFalse(app.buttons["permissions.allow"].exists,
                       "Access choices must stay saved without reopening routine learning.")
    }

    func testBackgroundInterruptsSequenceAndRequiresAnotherAcceptTapToContinue() {
        let app = launchFixture(delayed: true)
        assertInitialAccessSummary(in: app)
        let allow = app.buttons["permissions.allow"]
        reveal(allow, app); allow.tap()
        let requesting = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !allow.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [requesting], timeout: 5), .completed, app.debugDescription)
        XCUIDevice.shared.press(.home)
        app.activate()
        assertInitialAccessSummary(in: app)
        XCTAssertFalse(app.staticTexts["routinePreparation.heading"].waitForExistence(timeout: 2),
                       "Returning to MORE must not resume permission requests automatically.")
        reveal(allow, app)
        XCTAssertTrue(allow.isEnabled, app.debugDescription)
        allow.tap()
        XCTAssertTrue(app.staticTexts["routinePreparation.heading"].waitForExistence(timeout: 20), app.debugDescription)
        finishInitialRoutinePreparationIfVisible(app)
        assertHomeWithoutFurtherSetup(app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testRevisitingOptionalPermissionsReturnsToTheListAndSettingsWithoutOnboarding() {
        let app = launchFixture(french: true)
        skipInitialAccesses(in: app)
        finishInitialRoutinePreparationIfVisible(app)
        assertHomeWithoutFurtherSetup(app)
        openPermissionOptions(app)
        for permission in summaryPermissions {
            XCTAssertTrue(app.buttons["permissions.option.\(permission)"].exists, app.debugDescription)
        }
        XCTAssertFalse(app.buttons["permissions.option.microphone"].exists,
                       "The optional voice choice groups speech recognition and microphone.")
        selectPermissionOption("location", in: app)
        XCTAssertFalse(app.buttons["permissions.learn"].exists)
        let skip = app.buttons["permissions.skip"]
        reveal(skip, app)
        XCTAssertEqual(skip.label, "Plus tard")
        skip.tap()
        XCTAssertTrue(app.buttons["permissions.option.speech"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["permissions.title.calendar"].exists,
                       "Skipping a Settings access returns to the list without requesting another access.")
        let done = app.buttons["permissions.finish"]
        reveal(done, app)
        XCTAssertEqual(done.label, "Terminer")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setup.permissions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
    }

    func testFrenchSummaryUsesDistinctDayAndNightPaperAndSettingsDetailsReset() throws {
        var luminances: [String: Double] = [:]
        for phase in ["day", "night"] {
            let app = launchFixture(french: true, phase: phase)
            assertInitialAccessSummary(in: app)
            XCTAssertFalse(app.staticTexts["permissions.lastOutcome"].exists)
            let screenshot = app.screenshot()
            luminances[phase] = try paperLuminance(screenshot)
            attach("permissions-\(phase)-fr-summary", app, screenshot: screenshot)
            skipInitialAccesses(in: app)
            finishInitialRoutinePreparationIfVisible(app)
            assertHomeWithoutFurtherSetup(app)
            openPermissionOptions(app)
            selectPermissionOption("speech", in: app)
            XCTAssertEqual(app.staticTexts["permissions.title.speech"].label, "Parlez à MORE.")
            XCTAssertFalse(app.staticTexts["permissions.explanation"].exists)
            let details = element("permissions.details", in: app)
            reveal(details, app); details.tap()
            let explanation = app.staticTexts["permissions.explanation"]
            XCTAssertTrue(explanation.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(explanation.label.contains("micro") && explanation.label.contains("reconnaissance vocale"))
            attach("permissions-\(phase)-fr-settings-voice-expanded", app)
            let back = app.buttons["permissions.back"]
            reveal(back, app); back.tap()
            selectPermissionOption("speech", in: app)
            XCTAssertFalse(app.staticTexts["permissions.explanation"].exists,
                           "Reopening a Settings choice resets its disclosure.")
            XCTAssertFalse(app.staticTexts["permissions.lastOutcome"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
        XCTAssertGreaterThan(try XCTUnwrap(luminances["day"]) - XCTUnwrap(luminances["night"]), 0.4,
                             "The rendered paper must visibly darken at night, independently of the artwork.")
    }

    func testManualCitySelectionFromCurrentLocationSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-briefing-fixture",
            "--ui-testing-workspace=\(UUID().uuidString)", "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchConfirmedWorkspace(app)
        openYourDayFromHome(app)
        MorningUITestNavigation.chooseManualWeatherCity(in: app)
        let search = app.textFields["briefing.citySearch"]
        reveal(search, app)
        search.tap(); search.typeText("Synthetic\n")
        let result = app.buttons["briefing.cityResult.48.0,2.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        reveal(result, app); result.tap()
        assertSelectedCity(in: app)
        XCTAssertEqual(app.alerts.count, 0, "Choosing a manual city must not request GPS access.")
        app.terminate(); launchConfirmedWorkspace(app)
        openYourDayFromHome(app)
        assertSelectedCity(in: app)
        // The search row is offered only in manual mode, so its presence also
        // establishes the stored source choice rather than only a cached label.
        reveal(app.textFields["briefing.citySearch"], app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testFirstScreenTimeConnectionOpensReviewWithoutLearnAndLaterPreservesItAcrossRelaunch() {
        let app = launchFixture(screenTime: true)
        skipInitialAccesses(in: app)
        // Fixture starts notAsked, just like a fresh device: choosing Connect is
        // necessary. Permission setup never grants Screen Time on the user's behalf.
        MorningUITestNavigation.tapButton("routinePreparation.connect", in: app)
        let firstStep = app.staticTexts["screenTimeProposal.step.0"]
        XCTAssertTrue(firstStep.waitForExistence(timeout: 15), app.debugDescription)
        let reviewedTitle = firstStep.label
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertTrue(app.buttons["screenTimeProposal.approve"].exists)
        MorningUITestNavigation.tapButton("routinePreparation.later", in: app)
        assertHomeWithoutFurtherSetup(app)
        app.terminate(); launchConfirmedWorkspace(app)
        assertHomeWithoutFurtherSetup(app)
        XCTAssertFalse(app.staticTexts["screenTimeProposal.step.0"].exists,
                       "Finishing onboarding must not reopen review or Learn on launch.")
        app.buttons["morning.actions"].tap()
        MorningUITestNavigation.tapButton("morning.begin", in: app)
        XCTAssertTrue(firstStep.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(firstStep.label, reviewedTitle, "Later keeps the saved proposal for review.")
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists, "Review never starts a session.")
    }

    func testFrenchFirstRoutinePreparationHasAReachableLaterPathWithoutData() {
        let app = launchFixture(french: true)
        skipInitialAccesses(in: app)
        let heading = app.staticTexts["routinePreparation.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(heading.label, "Votre matin prend forme.")
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
        let later = app.buttons["routinePreparation.later"]
        reveal(later, app)
        XCTAssertEqual(later.label, "Continuer pour le moment")
        later.tap()
        app.terminate(); launchConfirmedWorkspace(app)
        assertHomeWithoutFurtherSetup(app)
        XCTAssertFalse(heading.exists)
    }

    private let summaryPermissions = ["location", "calendar", "reminders", "screenTime", "speech", "notifications", "alarms"]

    private func assertInitialAccessSummary(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["permissions.title.summary"].waitForExistence(timeout: 5), app.debugDescription)
        for permission in summaryPermissions {
            let description = app.staticTexts["permissions.title.\(permission)"]
            XCTAssertTrue(description.exists, "The summary must explain \(permission): \(app.debugDescription)")
            XCTAssertFalse(description.label.isEmpty)
            XCTAssertFalse(app.buttons["permissions.option.\(permission)"].exists,
                           "Initial setup presents a single consent action instead of independent pages.")
        }
        XCTAssertFalse(app.staticTexts["permissions.title.microphone"].exists,
                       "Speech recognition and microphone share one summary explanation.")
        XCTAssertTrue(app.staticTexts["permissions.note"].exists, "Declining must remain an explained choice.")
        XCTAssertFalse(app.staticTexts["permissions.note"].label.isEmpty)
        XCTAssertTrue(app.buttons["permissions.allow"].exists)
        XCTAssertTrue(app.buttons["permissions.skip"].exists)
    }

    private func assertFitsHorizontally(_ control: XCUIElement, _ app: XCUIApplication) {
        let frame = control.frame
        XCTAssertGreaterThan(frame.width, 0, control.debugDescription)
        XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX - 1,
                                    "The complete control must fit horizontally: \(control.debugDescription)")
        XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX + 1,
                                 "The complete control must fit horizontally: \(control.debugDescription)")
    }

    private func finishInitialRoutinePreparationIfVisible(_ app: XCUIApplication) {
        // Every initial access decision opens the direct routine destination. An
        // already handled choice on relaunch stays Home instead.
        let later = app.buttons["routinePreparation.later"]
        if later.waitForExistence(timeout: 3) {
            XCTAssertFalse(app.buttons["learn.screenTime"].exists)
            XCTAssertFalse(app.buttons["learn.observations"].exists)
            reveal(later, app); later.tap()
        }
    }

    private func openSettingsFromHome(_ app: XCUIApplication) {
        let actions = app.buttons["morning.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5), app.debugDescription)
        actions.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        XCTAssertTrue(app.buttons["setup.briefing"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func assertSelectedCity(in app: XCUIApplication) {
        let city = app.descendants(matching: .any).matching(identifier: "briefing.city").firstMatch
        reveal(city, app)
        XCTAssertTrue(city.label.contains("Synthetic City") || (city.value as? String)?.contains("Synthetic City") == true,
                      "The saved city must be exposed by its native labeled row: \(city.debugDescription)")
    }

    private func openYourDayFromHome(_ app: XCUIApplication) {
        openSettingsFromHome(app)
        let briefing = app.buttons["setup.briefing"]
        reveal(briefing, app); briefing.tap()
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func launchFixture(denied: Bool = false, frenchLargestText: Bool = false,
                               french: Bool = false, phase: String = "day", screenTime: Bool = false,
                               delayed: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let french = french || frenchLargestText
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-permissions",
            "--ui-testing-workspace=\(UUID().uuidString)", "--theme-phase=\(phase)", "--ui-testing-reduce-motion",
            "-more.appLanguage", french ? "fr" : "en", "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"]
        if frenchLargestText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if denied { app.launchArguments.append("--ui-testing-permissions-denied") }
        if screenTime { app.launchArguments.append("--ui-testing-screen-time-fixture") }
        if delayed { app.launchArguments.append("--ui-testing-permissions-delayed") }
        launchConfirmedWorkspace(app)
        XCTAssertTrue(app.staticTexts["permissions.title.summary"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }

    private func launchConfirmedWorkspace(_ app: XCUIApplication) {
        continueAfterFailure = false
        let prefix = "--ui-testing-workspace="
        let workspace = String(app.launchArguments.first { $0.hasPrefix(prefix) }!.dropFirst(prefix.count))
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) || marker.value as? String != workspace {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(marker.value as? String, workspace, app.debugDescription)
    }

    private func skipInitialAccesses(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["permissions.title.summary"].waitForExistence(timeout: 5), app.debugDescription)
        let skip = app.buttons["permissions.skip"]
        reveal(skip, app); skip.tap()
    }

    private func assertHomeWithoutFurtherSetup(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["permissions.allow"].exists)
        XCTAssertFalse(app.buttons["permissions.finish"].exists)
        XCTAssertFalse(app.buttons["permissions.learn"].exists)
        XCTAssertFalse(app.staticTexts["permissions.title.summary"].exists)
        XCTAssertFalse(app.staticTexts["permissions.title.ready"].exists)
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
    }

    private func openPermissionOptions(_ app: XCUIApplication) {
        openSettingsFromHome(app)
        let revisit = app.buttons["setup.permissions"]
        reveal(revisit, app); revisit.tap()
        XCTAssertTrue(app.buttons["permissions.option.speech"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["permissions.allow"].exists)
        XCTAssertFalse(app.buttons["permissions.learn"].exists)
    }

    private func selectPermissionOption(_ permission: String, in app: XCUIApplication) {
        let option = app.buttons["permissions.option.\(permission)"]
        reveal(option, app); option.tap()
        XCTAssertTrue(app.staticTexts["permissions.title.\(permission)"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        if element.exists, element.isHittable { return }
        let content: XCUIElement
        if app.scrollViews["permissions.content"].exists {
            content = app.scrollViews["permissions.content"]
        } else if app.scrollViews.firstMatch.exists {
            content = app.scrollViews.firstMatch
        } else {
            content = app.collectionViews.firstMatch
        }
        for _ in 0..<10 {
            if element.exists, element.isHittable { break }
            if content.exists {
                if element.exists, element.frame.maxY < content.frame.minY { content.swipeDown() }
                else { content.swipeUp() }
            } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    /// Sample the outer gutter, away from the landscape, text and controls. This
    /// checks actual pixels instead of an appearance value supplied by the app.
    private func paperLuminance(_ screenshot: XCUIScreenshot) throws -> Double {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let patch = try XCTUnwrap(image.cropping(to: CGRect(x: CGFloat(image.width) * 0.02,
            y: CGFloat(image.height) * 0.25, width: 5, height: 5).integral))
        var bytes = [UInt8](repeating: 0, count: 4)
        return try bytes.withUnsafeMutableBytes { (storage: UnsafeMutableRawBufferPointer) in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return (0.2126 * Double(storage[0]) + 0.7152 * Double(storage[1]) + 0.0722 * Double(storage[2])) / 255
        }
    }

    private func attach(_ name: String, _ app: XCUIApplication, screenshot: XCUIScreenshot? = nil) {
        let screenshot = screenshot ?? app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MO_ONBOARDING_SCREENSHOT_DIR"] {
            do {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"), options: .atomic)
            } catch { XCTFail("Could not save the synthetic permission screenshot: \(error)") }
        }
    }
}
