import XCTest
import WeatherKit
import UIKit

/// Synthetic workspaces only. These checks never access an account, grant a
/// permission, record the screen, or replace the owner's saved morning.
@MainActor
final class SunriseDockTests: XCTestCase {
    func testArrivalShowsOnlyLandscapeAndTapRevealsReachableControls() {
        let app = launch()
        assertQuietArrival(in: app)
        attach("quiet-solar-day-arrival", app)

        reveal(in: app)
        for identifier in ["morning.settings", "morning.begin"] {
            assertReachable(identifier, in: app)
        }
        XCTAssertFalse(app.buttons["morning.playback"].exists,
                       "Revealing controls must not start the saved morning.")
        XCTAssertEqual(app.tabBars.count, 0)
        attach("quiet-solar-day-controls", app)

        hideControls(in: app)
        assertQuietArrival(in: app)
        app.buttons["morning.actions"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.17)).tap()
        assertReachable("morning.begin", in: app)
        app.buttons["morning.actions"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.17)).tap()
        assertQuietArrival(in: app)
    }

    func testRevealedSettingsAndSavedRoutineOpenTheirDestinations() {
        var app = launch(phase: "night")
        reveal(in: app)
        app.buttons["morning.settings"].tap()
        XCTAssertTrue(app.buttons["setup.briefing"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("quiet-solar-night-settings", app)
        app.terminate()

        app = launch()
        reveal(in: app)
        app.buttons["morning.settings"].tap()
        MorningUITestNavigation.tapButton("setup.routine", in: app)
        let editor = app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testEmptyWorkspaceRemainsQuietAndBothEntryActionsOpenLearning() {
        for throughSettings in [false, true] {
            let app = launch(empty: true)
            assertQuietArrival(in: app)
            reveal(in: app)
            if throughSettings {
                app.buttons["morning.settings"].tap()
                MorningUITestNavigation.tapButton("setup.routine", in: app)
            } else {
                app.buttons["morning.begin"].tap()
            }
            XCTAssertTrue(app.buttons["learn.screenTime"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.buttons["morning.playback"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
    }

    func testSavedMorningCanBeginPauseContinueAndHideItsControls() {
        let app = launch()
        reveal(in: app)
        app.buttons["morning.begin"].tap()
        MorningUITestNavigation.chooseRoutineAtOpening(in: app)
        MorningUITestNavigation.assertSession(state: "running", step: "Your morning", in: app)
        MorningUITestNavigation.revealControls(in: app)
        let playback = app.buttons["morning.playback"]
        XCTAssertEqual(playback.label, "Pause")
        XCTAssertFalse(app.buttons["morning.next"].exists, "Additional commands belong in Settings.")
        playback.tap()
        XCTAssertEqual(playback.label, "Continue")
        playback.tap()
        XCTAssertEqual(playback.label, "Pause")
        attach("quiet-solar-running-controls", app)
        app.scrollViews["morning.captions"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        XCTAssertTrue(playback.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["morning.settings"].exists)
        MorningUITestNavigation.revealControls(in: app)
        assertReachable("morning.playback", in: app)
        app.buttons["morning.settings"].tap()
        assertReachable("morning.next", in: app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testLandscapeAndControlsAcrossLocalDayPhases() {
        for phase in ["dawn", "morning", "day", "evening", "night"] {
            let app = launch(phase: phase)
            assertQuietArrival(in: app)
            attach("quiet-solar-\(phase)-arrival", app)
            reveal(in: app)
            for identifier in ["morning.settings", "morning.begin"] {
                assertReachable(identifier, in: app)
            }
            attach("quiet-solar-\(phase)-controls", app)
            app.terminate()
        }
    }

    func testLandscapeOrientationKeepsTheWholeSkyAndMenuReachable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(weather: "partlyCloudy", extra: ["--ui-testing-reduce-motion"])
        assertQuietArrival(in: app)
        XCTAssertGreaterThan(app.frame.width, app.frame.height, app.debugDescription)
        attach("weather-partlyCloudy-day-landscape", app)
        reveal(in: app)
        for identifier in ["morning.settings", "morning.begin"] {
            assertReachable(identifier, in: app)
        }
        attach("weather-partlyCloudy-day-landscape-controls", app)
        hideControls(in: app)
        assertQuietArrival(in: app)
    }

    func testEveryAppleWeatherConditionHasADayAndNightLandscape() {
        // Use Apple's SDK cases so a new supported condition cannot silently miss
        // the native visual matrix. The launch argument injects synthetic weather
        // only; this suite never makes a WeatherKit or location request.
        for condition in WeatherCondition.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            for phase in ["day", "night"] {
                let app = launch(phase: phase, weather: condition.rawValue,
                                 extra: ["--ui-testing-reduce-motion"])
                assertQuietArrival(in: app)
                let landscape = app.buttons["morning.actions"]
                XCTAssertTrue(String(describing: landscape.value ?? "").contains(condition.rawValue),
                              "The rendered fixture must identify \(condition.rawValue): \(app.debugDescription)")
                attach("weather-\(condition.rawValue)-\(phase)", app)
                app.terminate()
            }
        }
    }

    func testCloudRainSnowAndStormFollowEveryLocalDayPhase() {
        for weather in ["cloudy", "heavyRain", "snow", "thunderstorms"] {
            for phase in ["dawn", "morning", "day", "evening", "night"] {
                let app = launch(phase: phase, weather: weather,
                                 extra: ["--ui-testing-reduce-motion"])
                assertQuietArrival(in: app)
                attach("weather-\(weather)-\(phase)", app)
                app.terminate()
            }
        }
    }

    func testRainAndSnowKeepTheSkyAndMenuUsable() {
        for (weather, phase) in [("heavyRain", "day"), ("snow", "night")] {
            let app = launch(phase: phase, weather: weather)
            assertQuietArrival(in: app)
            attach("weather-\(weather)-\(phase)-interactive", app)
            reveal(in: app)
            assertReachable("morning.begin", in: app)
            assertReachable("morning.settings", in: app)
            hideControls(in: app)
            assertQuietArrival(in: app)
            app.terminate()
        }
    }

    func testUnavailableWeatherDoesNotPretendToBeAClearForecast() {
        for weather in ["unknown", "unavailable"] {
            for phase in ["day", "night"] {
                let app = launch(phase: phase, weather: weather)
                assertQuietArrival(in: app)
                let value = String(describing: app.buttons["morning.actions"].value ?? "").lowercased()
                XCTAssertTrue(value.contains(weather), app.debugDescription)
                attach("weather-\(weather)-\(phase)", app)
                reveal(in: app)
                assertReachable("morning.settings", in: app)
                app.terminate()
            }
        }
    }

    func testWithoutWeatherSelectionKeepsQuietArrivalAndOffersCitySetup() {
        let app = launch(weather: nil)
        assertQuietArrival(in: app)
        attach("weather-not-selected", app)
        reveal(in: app)
        app.buttons["morning.settings"].tap()
        MorningUITestNavigation.tapButton("setup.briefing", in: app)
        XCTAssertTrue(app.navigationBars["Your day"].waitForExistence(timeout: 5), app.debugDescription)
        MorningUITestNavigation.chooseManualWeatherCity(in: app)
        let city = app.textFields["briefing.citySearch"]
        for _ in 0..<8 where !city.exists || !city.isHittable { app.swipeUp() }
        XCTAssertTrue(city.exists && city.isHittable)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testBothTopAndBottomOfSkyRevealAndDismissTheMenu() {
        let app = launch(weather: "cloudy")
        for point in [CGVector(dx: 0.1, dy: 0.17), CGVector(dx: 0.9, dy: 0.85)] {
            assertQuietArrival(in: app)
            app.buttons["morning.actions"].coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5), app.debugDescription)
            hideControls(in: app)
        }
        assertQuietArrival(in: app)
    }

    func testFrenchLargestTextAndReducedMotionKeepControlsReachable() {
        let app = launch(phase: "night", extra: [
            "--ui-testing-reduce-motion", "--ui-testing-reduce-transparency",
            "-more.appLanguage", "fr", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        assertQuietArrival(in: app)
        attach("quiet-solar-night-fr-largest-reduced-motion", app)
        reveal(in: app)
        for identifier in ["morning.settings", "morning.begin"] {
            assertReachable(identifier, in: app)
        }
        attach("quiet-solar-night-fr-largest-controls", app)
        app.buttons["morning.settings"].tap()
        MorningUITestNavigation.tapButton("setup.routine", in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch.waitForExistence(timeout: 5))
        attach("quiet-solar-night-fr-largest-routine", app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.openSettings(in: app)
        MorningUITestNavigation.tapButton("setup.briefing", in: app)
        MorningUITestNavigation.chooseManualWeatherCity(in: app)
        let city = app.textFields["briefing.citySearch"]
        for _ in 0..<12 where !city.exists || !city.isHittable { app.swipeUp() }
        XCTAssertTrue(city.exists && city.isHittable)
        attach("quiet-solar-night-fr-largest-city", app)
    }

    func testNightTwinklesAndReducedMotionLeavesTheLandscapeStill() {
        for still in [false, true] {
            let app = launch(phase: "night", extra: still ? ["--ui-testing-reduce-motion"] : [])
            assertQuietArrival(in: app)
            let landscape = app.buttons["morning.actions"]
            let before = landscape.screenshot()
            let elapsed = expectation(description: "Observe a second of the night sky")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { elapsed.fulfill() }
            wait(for: [elapsed], timeout: 3)
            let after = landscape.screenshot()
            // Home now fills the display. Compare just the sky, excluding the
            // status bar clock/battery and the controls' touch feedback.
            let beforeSky = skyPixels(before)
            let afterSky = skyPixels(after)
            XCTAssertNotNil(beforeSky)
            XCTAssertNotNil(afterSky)
            if still { XCTAssertEqual(beforeSky, afterSky, "Reduce Motion must leave the landscape still.") }
            else { XCTAssertNotEqual(beforeSky, afterSky, "The night stars should gently change brightness.") }
            attach("quiet-solar-night-\(still ? "still" : "twinkle")-before", before)
            attach("quiet-solar-night-\(still ? "still" : "twinkle")-after", after)
            app.terminate()
        }
    }

    func testWeatherMotionChangesRepresentativeSkies() {
        for (weather, phase) in movingSkies {
            let app = launch(phase: phase, weather: weather)
            assertQuietArrival(in: app)
            let (before, after) = observeSky(in: app)
            XCTAssertNotEqual(scenePixels(before), scenePixels(after),
                              "\(weather)/\(phase) should show gentle atmospheric motion.")
            attach("motion-\(weather)-\(phase)-before", before)
            attach("motion-\(weather)-\(phase)-after", after)
            app.terminate()
        }
    }

    func testMeasuredWindChangesAClearSkyAndFollowsItsDirection() {
        var poses: [String: Data] = [:]
        for weather in ["calm", "breeze", "gustOnly", "strongWind", "westWind", "eastWind", "humid"] {
            let app = launch(weather: weather, extra: ["--theme-motion-time=3.2"])
            assertQuietArrival(in: app)
            let screenshot = app.buttons["morning.actions"].screenshot()
            poses[weather] = scenePixels(screenshot)
            attach("measured-weather-\(weather)-t3.2", screenshot)
            reveal(in: app)
            assertReachable("morning.settings", in: app)
            assertReachable("morning.settings", in: app)
            app.terminate()
        }
        for (first, second) in [("calm", "breeze"), ("calm", "gustOnly"), ("breeze", "strongWind"), ("westWind", "eastWind"), ("calm", "humid")] {
            XCTAssertNotNil(poses[first])
            XCTAssertNotNil(poses[second])
            XCTAssertNotEqual(poses[first], poses[second],
                              "Measured \(first)/\(second) must change the atmosphere even when the condition is similar.")
        }
    }

    func testMeasuredWindAndHumidityStayStillWithReducedMotion() {
        for weather in ["breeze", "gustOnly", "strongWind", "eastWind", "humid"] {
            var firstPose: Data?
            for seconds in [3.2, 12.0] {
                let app = launch(weather: weather, extra: ["--ui-testing-reduce-motion", "--theme-motion-time=\(seconds)"])
                assertQuietArrival(in: app)
                let screenshot = app.buttons["morning.actions"].screenshot()
                let pixels = scenePixels(screenshot)
                if let firstPose {
                    XCTAssertEqual(firstPose, pixels,
                                   "Reduce Motion must freeze breaths, tree movement and visibility bands for \(weather).")
                } else { firstPose = pixels }
                attach("measured-weather-\(weather)-reduced-t\(seconds)", screenshot)
                app.terminate()
            }
            XCTAssertNotNil(firstPose)
        }
    }

    func testReduceMotionKeepsAllRepresentativeWeatherStill() {
        for (weather, phase) in movingSkies {
            let app = launch(phase: phase, weather: weather, extra: ["--ui-testing-reduce-motion"])
            assertQuietArrival(in: app)
            let (before, after) = observeSky(in: app)
            XCTAssertEqual(scenePixels(before), scenePixels(after),
                           "Reduce Motion must freeze \(weather)/\(phase), including precipitation and shooting stars.")
            attach("motion-reduced-\(weather)-\(phase)-before", before)
            attach("motion-reduced-\(weather)-\(phase)-after", after)
            app.terminate()
        }
    }

    func testFrozenWeatherTimeChangesPoseWithoutRestartingAtTheMenu() {
        var firstPose: Data?
        var laterPose: Data?
        for seconds in [0, 8] {
            let app = launch(weather: "cloudy", extra: ["--theme-motion-time=\(seconds)"])
            assertQuietArrival(in: app)
            let before = app.buttons["morning.actions"].screenshot()
            let pixels = scenePixels(before)
            if seconds == 0 { firstPose = pixels }
            else { laterPose = pixels }
            attach("motion-cloudy-day-t\(seconds)", before)

            reveal(in: app)
            assertReachable("morning.settings", in: app)
            hideControls(in: app)
            assertQuietArrival(in: app)
            let after = app.buttons["morning.actions"].screenshot()
            XCTAssertEqual(pixels, scenePixels(after),
                           "Opening and closing the menu must preserve the atmospheric clock and seeded scene.")
            attach("motion-cloudy-day-t\(seconds)-after-menu", after)
            app.terminate()
        }
        XCTAssertNotNil(firstPose)
        XCTAssertNotNil(laterPose)
        XCTAssertNotEqual(firstPose, laterPose, "Clouds must advance between the two sampled weather times.")
    }

    func testWeatherAnimationTimeDoesNotAdvanceTheSunOrWallpaper() {
        var firstPose: Data?
        for seconds in [0, 600] {
            let app = launch(weather: "clear", extra: ["--theme-motion-time=\(seconds)"])
            assertQuietArrival(in: app)
            let screenshot = app.buttons["morning.actions"].screenshot()
            let pixels = scenePixels(screenshot)
            if seconds == 0 { firstPose = pixels }
            else {
                XCTAssertEqual(firstPose, pixels,
                               "The atmospheric clock must never move the solar clock or animate the dotted wallpaper.")
            }
            attach("motion-clear-day-t\(seconds)", screenshot)
            app.terminate()
        }
        XCTAssertNotNil(firstPose)
    }

    func testWeatherAnimationTimeDoesNotAdvanceTheMoon() throws {
        var firstBounds: CGRect?
        for seconds in [0, 600] {
            let app = launch(phase: "night", weather: "clear", extra: ["--theme-motion-time=\(seconds)"])
            assertQuietArrival(in: app)
            let screenshot = app.buttons["morning.actions"].screenshot()
            let bounds = try XCTUnwrap(brightMoonBounds(screenshot), "The night sky must retain its central moon.")
            if let firstBounds {
                XCTAssertEqual(firstBounds.minX, bounds.minX, accuracy: 1.5)
                XCTAssertEqual(firstBounds.minY, bounds.minY, accuracy: 1.5)
                XCTAssertEqual(firstBounds.maxX, bounds.maxX, accuracy: 1.5)
                XCTAssertEqual(firstBounds.maxY, bounds.maxY, accuracy: 1.5)
            } else { firstBounds = bounds }
            attach("motion-clear-night-t\(seconds)", screenshot)
            app.terminate()
        }
    }

    func testShootingStarPreviewAndReduceMotionAtTheSameWeatherTimes() {
        var stillPose: Data?
        for reduced in [false, true] {
            for seconds in reduced ? [16.0, 18.9] : [16.0, 18.9, 21.0] {
                var arguments = ["--theme-motion-time=\(seconds)"]
                if reduced { arguments.append("--ui-testing-reduce-motion") }
                let app = launch(phase: "night", weather: "clear", extra: arguments)
                assertQuietArrival(in: app)
                let screenshot = app.buttons["morning.actions"].screenshot()
                let pixels = scenePixels(screenshot)
                if reduced {
                    if stillPose == nil { stillPose = pixels }
                    else {
                        XCTAssertEqual(stillPose, pixels,
                                       "Reduce Motion must suppress a shooting star even at its sampled peak.")
                    }
                }
                attach("motion-meteor-\(reduced ? "reduced" : "sample")-t\(seconds)", screenshot)
                app.terminate()
            }
        }
        XCTAssertNotNil(stillPose)
    }

    private var movingSkies: [(String, String)] {
        [("clear", "night"), ("cloudy", "day"), ("rain", "day"), ("snow", "night"), ("windy", "day")]
    }

    private func observeSky(in app: XCUIApplication) -> (XCUIScreenshot, XCUIScreenshot) {
        let before = app.buttons["morning.actions"].screenshot()
        let elapsed = expectation(description: "Observe gentle weather motion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 5)
        return (before, app.buttons["morning.actions"].screenshot())
    }

    private func launch(phase: String = "day", weather: String? = "clear", empty: Bool = false,
                        extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--fixture-mode", "--ui-testing-briefing-fixture", "--theme-phase=\(phase)",
            "--ui-testing-workspace=\(UUID().uuidString)",
            empty ? "--ui-testing-empty-workspace" : "--ui-testing-approved"
        ] + extra
        if let weather { app.launchArguments.append("--theme-weather=\(weather)") }
        if !extra.contains("-AppleLanguages") {
            app.launchArguments += ["-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        }
        MorningUITestNavigation.launch(app)
        return app
    }

    private func assertQuietArrival(in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(landscape.isHittable, app.debugDescription, file: file, line: line)
        XCTAssertGreaterThanOrEqual(landscape.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(landscape.frame.height, 44, file: file, line: line)
        XCTAssertEqual(landscape.frame.midX, app.frame.midX, accuracy: 3, file: file, line: line)
        XCTAssertGreaterThanOrEqual(landscape.frame.width, app.frame.width * 0.98, file: file, line: line)
        XCTAssertGreaterThanOrEqual(landscape.frame.height, app.frame.height * 0.85,
                                    "The sky must fill Home instead of remaining a small footer.", file: file, line: line)
        for identifier in ["morning.settings", "morning.review", "morning.begin", "morning.closeActions",
                           "morning.playback", "morning.next", "morning.date"] {
            XCTAssertFalse(app.buttons[identifier].exists, identifier, file: file, line: line)
        }
        XCTAssertFalse(app.staticTexts["morning.readyQuestion"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["morning.currentStep"].exists, file: file, line: line)
        XCTAssertEqual(app.tabBars.count, 0, file: file, line: line)
    }

    private func reveal(in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10), file: file, line: line)
        landscape.tap()
        XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5),
                      app.debugDescription, file: file, line: line)
    }

    private func hideControls(in app: XCUIApplication) {
        app.buttons["morning.actions"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.17)).tap()
        XCTAssertTrue(app.buttons["morning.settings"].waitForNonExistence(timeout: 5), app.debugDescription)
    }

    private func assertReachable(_ identifier: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        let controls = app.scrollViews.firstMatch
        func fullyVisible() -> Bool {
            button.isHittable && (!controls.exists || controls.frame.insetBy(dx: -1, dy: -1).contains(button.frame))
        }
        for _ in 0..<6 where !fullyVisible() && controls.exists {
            if button.frame.midY < controls.frame.midY { controls.swipeDown() }
            else { controls.swipeUp() }
        }
        XCTAssertTrue(fullyVisible(), app.debugDescription, file: file, line: line)
        // Native transformed coordinates can report 43.99999999999994 for a
        // 44-point target. Preserve the minimum while allowing floating-point noise.
        XCTAssertGreaterThanOrEqual(button.frame.width + 0.001, 44, identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44, identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.minX, 0, identifier, file: file, line: line)
        XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX, identifier, file: file, line: line)
        XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY, identifier, file: file, line: line)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        // On this simulator SDK app.screenshot() crops landscape frames into a
        // portrait bitmap. The screen capture preserves the real rendered view.
        attach(name, app.frame.width > app.frame.height ? XCUIScreen.main.screenshot() : app.screenshot())
    }

    private func skyPixels(_ screenshot: XCUIScreenshot) -> Data? {
        guard let image = screenshot.image.cgImage,
              let cropped = image.cropping(to: CGRect(x: Double(image.width) * 0.05,
                                                     y: Double(image.height) * 0.13,
                                                     width: Double(image.width) * 0.90,
                                                     height: Double(image.height) * 0.18)) else { return nil }
        return UIImage(cgImage: cropped).pngData()
    }

    private func scenePixels(_ screenshot: XCUIScreenshot) -> Data? {
        guard let image = screenshot.image.cgImage,
              let cropped = image.cropping(to: CGRect(x: Double(image.width) * 0.03,
                                                     y: Double(image.height) * 0.12,
                                                     width: Double(image.width) * 0.94,
                                                     height: Double(image.height) * 0.74)) else {
            XCTFail("The native sky screenshot could not be cropped.")
            return nil
        }
        return UIImage(cgImage: cropped).pngData()
    }

    private func brightMoonBounds(_ screenshot: XCUIScreenshot) -> CGRect? {
        guard let image = screenshot.image.cgImage,
              let moon = image.cropping(to: CGRect(x: Double(image.width) * 0.15,
                                                  y: Double(image.height) * 0.28,
                                                  width: Double(image.width) * 0.50,
                                                  height: Double(image.height) * 0.32)) else { return nil }
        var pixels = [UInt8](repeating: 0, count: moon.width * moon.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: moon.width, height: moon.height,
                bitsPerComponent: 8, bytesPerRow: moon.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(moon, in: CGRect(x: 0, y: 0, width: CGFloat(moon.width), height: CGFloat(moon.height)))
            return true
        }
        guard drawn else { return nil }
        var minX = moon.width, minY = moon.height, maxX = -1, maxY = -1
        for y in 0..<moon.height {
            for x in 0..<moon.width {
                let index = (y * moon.width + x) * 4
                // Full moon ink is brighter than the twinkling stars; ignore
                // their changing opacity when measuring the celestial silhouette.
                if pixels[index] > 220 && pixels[index + 1] > 215 && pixels[index + 2] > 190 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
    }

    private func attach(_ name: String, _ screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            // Runner-local copies survive xcresult attachment export failures.
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let directory = documents.appendingPathComponent("MOREQuietSolarScreenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        } catch { XCTFail("Could not retain the synthetic home screenshot: \(error)") }
    }
}
