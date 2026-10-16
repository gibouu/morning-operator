import XCTest

/// Attended physical-device evidence from the installed app, with its existing data and grants.
/// Attachments can contain personal information and must stay in the local xcresult.
@MainActor
final class OrdinaryWeatherAcceptanceTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.gibouu.morningoperator")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let permissions = ["location", "calendar", "reminders", "screenTime", "speech", "microphone", "notifications", "alarms"]
    private var outcome: [String] = []

    func test01RecordOrdinaryPermissionRequests() throws {
        try launchOrdinaryApp()
        defer { attachText(outcome.joined(separator: "\n"), named: "ordinary-acceptance-outcome") }

        if !waitUntil(5, { self.currentPermission != nil || self.app.buttons["permissions.option.speech"].exists || self.app.buttons["morning.actions"].isHittable }) {
            throw XCTSkip("The ordinary app has another presentation; inspect ordinary-opening without resetting its data.")
        }
        if currentPermission == nil, visibleAlert != nil {
            throw XCTSkip("An existing system prompt has no matching access explanation; owner action is required.")
        }
        let revisiting = currentPermission == nil
        if revisiting {
            outcome.append("EXISTING_PERMISSION_PROGRESS: reviewing the optional voice explanation; first-opening presentation is not re-proved.")
            if !app.buttons["permissions.option.speech"].exists {
                try openSettings()
                try tap("setup.permissions")
            }
            XCTAssertTrue(app.buttons["permissions.option.speech"].waitForExistence(timeout: 5))
            try tap("permissions.option.speech")
        }
        guard currentPermission == "speech" else {
            throw XCTSkip("The installed app is not showing the grouped voice explanation; no other permission was requested.")
        }
        if !revisiting {
            outcome.append("INITIAL_VOICE_PREPARATION_PRESENTED: existing app data and system grants retained.")
        }
        attach("ordinary-explanation-voice")
        var acceptedPrompts = 0
        if let alert = visibleAlert {
            guard allowScopedPrompt(alert, permission: "speech") else {
                throw XCTSkip("An existing authentication or unrecognized sheet needs the owner.")
            }
            acceptedPrompts += 1
            outcome.append("RESUMED_PENDING_VOICE: matching existing prompt accepted; explanation order is not re-proved for this resumed choice.")
        } else {
            XCTAssertEqual(app.alerts.count + springboard.alerts.count, 0,
                "The grouped voice explanation must precede speech and microphone requests.")
            try tap("permissions.allow")
        }
        let deadline = Date().addingTimeInterval(50)
        while Date() < deadline, currentPermission == "speech" {
            if let alert = visibleAlert {
                guard allowScopedPrompt(alert, permission: "speech") else {
                    attach("ordinary-owner-action-voice")
                    throw XCTSkip("An authentication or unrecognized permission sheet needs the owner; no unrelated control was pressed.")
                }
                acceptedPrompts += 1
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard currentPermission == nil else {
            attach("ordinary-permission-waiting-voice")
            throw XCTSkip("The real grouped voice request has not completed; no other permission was requested.")
        }
        let last = app.staticTexts["permissions.lastOutcome"]
        outcome.append("VOICE_ONLY: speech/microphone prompts accepted=\(acceptedPrompts); \(last.exists ? last.label : "see resulting-screen attachment")")
        attach("ordinary-voice-choice-completed")
        if revisiting {
            XCTAssertTrue(app.buttons["permissions.option.speech"].waitForExistence(timeout: 10),
                "Reviewing voice access must return to the optional access list.")
            XCTAssertFalse(app.buttons["permissions.allow"].exists)
            try tap("permissions.finish")
            XCTAssertTrue(app.buttons["setup.permissions"].waitForExistence(timeout: 10),
                "Closing the optional list must return to Settings.")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            try reveal(back)
            back.tap()
        }
        XCTAssertFalse(app.buttons["permissions.finish"].exists,
                       "The initial voice choice returns directly Home without a completion page.")
        XCTAssertFalse(app.buttons["permissions.learn"].exists)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["permissions.allow"].waitForExistence(timeout: 2),
            "The voice choice must stay complete across an ordinary relaunch.")
        outcome.append("VOICE_PROGRESS_PERSISTED_AFTER_ORDINARY_RELAUNCH: no optional access was requested.")
    }

    func test02RecordOrdinaryCurrentLocationAndWeather() throws {
        try launchOrdinaryApp()
        defer { attachText(outcome.joined(separator: "\n"), named: "ordinary-acceptance-outcome") }
        if app.buttons["permissions.allow"].waitForExistence(timeout: 2) {
            throw XCTSkip("The permission-preparation flow still needs completion; no progress or system grant was reset.")
        }
        if app.buttons["permissions.finish"].exists { try tap("permissions.finish") }
        try openSettings()
        try tap("setup.briefing")
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists)
        attach("ordinary-your-day-before-location")
        let source = element("briefing.locationSource")
        try reveal(source)
        source.tap()
        let current = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Current location", "Position actuelle")).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.tap()
        try tap("briefing.useCurrentLocation")
        if let alert = visibleAlert,
           alert.staticTexts["The weather, where you are"].exists || alert.staticTexts["La météo, là où vous êtes"].exists {
            let allow = alert.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Allow location", "Autoriser la localisation")).firstMatch
            XCTAssertTrue(allow.exists)
            allow.tap()
        }
        let locationDeadline = Date().addingTimeInterval(20)
        while Date() < locationDeadline, !element("briefing.currentLocation").exists {
            if let alert = visibleAlert {
                guard allowScopedPrompt(alert, permission: "location") else {
                    attach("ordinary-location-owner-action")
                    throw XCTSkip("The current-location prompt needs owner action.")
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        attach("ordinary-current-location-and-weather-details")
        let resolved = element("briefing.currentLocation").exists
        outcome.append(resolved ? "CURRENT_LOCATION_RESOLVED_BY_NATIVE_PROVIDER" : "CURRENT_LOCATION_UNAVAILABLE: inspect native issue in attachment.")
        let weatherLink = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "Weather data · Apple Weather", "Données météo · Apple Météo")).firstMatch
        _ = waitUntil(25) { weatherLink.exists }
        var measuredRows = false
        for index in 1...5 {
            app.swipeUp()
            attach("ordinary-measured-weather-details-\(index)")
            measuredRows = measuredRows || app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "km/h")).firstMatch.exists
            if weatherLink.isHittable { break }
        }
        let nativeAttribution = weatherLink.exists
        outcome.append("YOUR_DAY_LIVE_ATTRIBUTION=\(nativeAttribution); MEASURED_WIND_ROWS=\(measuredRows)")
        outcome.append(resolved && nativeAttribution && measuredRows
            ? "NATIVE_CURRENT_LOCATION_WEATHER_ADMITTED: native attribution and measured rows present; no fixture or storage override."
            : "LIVE_LOCATION_WEATHER_NOT_FULLY_CONFIRMED: inspect captured native outcomes; a recording test pass is not provider acceptance.")
        try dismissSheet()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        _ = waitUntil(25) {
            let value = self.app.buttons["morning.actions"].value as? String ?? ""
            return value.contains("Current location:") || value.contains("Position actuelle:")
        }
        attach("ordinary-home-weather-status")
        outcome.append("HOME_WEATHER_STATUS_AFTER_RELAUNCH: \(app.buttons["morning.actions"].value ?? "not exposed")")
        XCTAssertEqual(app.state, .runningForeground, "Another device operation must not replace this live-weather check.")
        attach("ordinary-live-sky-0s")
        for index in 1...4 {
            Thread.sleep(forTimeInterval: 3)
            XCTAssertEqual(app.state, .runningForeground, "The ordinary app must remain foreground throughout animation capture.")
            attach("ordinary-live-sky-\(index * 3)s")
        }
        outcome.append("ANIMATION_FRAMES_RECORDED: visual review must relate movement to the measured weather; frame differences alone do not prove wind.")
    }

    func test03RecordExistingLiveSky() throws {
        try launchOrdinaryApp()
        defer { attachText(outcome.joined(separator: "\n"), named: "ordinary-acceptance-outcome") }
        XCTAssertFalse(app.buttons["permissions.allow"].waitForExistence(timeout: 2),
            "The existing app must have completed access preparation before this read-only smoke.")
        XCTAssertFalse(app.buttons["permissions.finish"].exists)
        let admitted = waitUntil(25) {
            let value = self.app.buttons["morning.actions"].value as? String ?? ""
            return value.contains("Current location:") || value.contains("Position actuelle:")
        }
        attach("ordinary-existing-sky-weather-admission")
        XCTAssertTrue(admitted,
            "Fresh native current-location weather is not admitted: \(app.buttons["morning.actions"].value ?? "not exposed")")
        for index in 0...4 {
            if index > 0 { Thread.sleep(forTimeInterval: 3) }
            XCTAssertEqual(app.state, .runningForeground, "The ordinary app must remain foreground throughout animation capture.")
            attach("ordinary-existing-live-sky-\(index * 3)s")
            outcome.append("SKY_\(index * 3)s: \(app.buttons["morning.actions"].value ?? "not exposed")")
        }
    }

    private var currentPermission: String? {
        permissions.first { app.staticTexts["permissions.title.\($0)"].exists }
    }

    private var visibleAlert: XCUIElement? {
        if springboard.alerts.firstMatch.exists { return springboard.alerts.firstMatch }
        if app.alerts.firstMatch.exists { return app.alerts.firstMatch }
        return nil
    }

    private func allowScopedPrompt(_ alert: XCUIElement, permission: String) -> Bool {
        let text = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ").lowercased()
        let purpose: [String] = switch permission {
        case "location": ["location", "position", "localisation"]
        case "calendar": ["calendar", "calendrier"]
        case "reminders": ["reminder", "rappel"]
        case "screenTime": ["screen time", "temps d’écran", "temps d'écran", "app and website", "activité"]
        case "speech": ["speech", "reconnaissance", "recognition", "microphone"]
        case "microphone": ["microphone"]
        case "notifications": ["notification"]
        case "alarms": ["alarm", "alarme"]
        default: []
        }
        guard (text.contains("more") || text.contains("morningoperator")), purpose.contains(where: text.contains) else { return false }
        let labels: [String] = switch permission {
        case "location": ["Allow While Using App", "Allow While Using the App", "Autoriser lorsque l’app est active", "Autoriser lorsque l'app est active", "Lorsque l’app est active", "Lorsque l'app est active"]
        case "calendar", "reminders": ["Allow", "Autoriser", "Allow Full Access", "Autoriser l’accès complet", "Autoriser l'accès complet", "Accès complet", "Allow Access", "Autoriser l’accès", "Autoriser l'accès"]
        case "screenTime": ["Continue", "Continuer", "Allow", "Autoriser"]
        default: ["Allow", "Autoriser", "OK"]
        }
        let candidates = alert.buttons.matching(NSPredicate(format: "label IN %@", labels)).allElementsBoundByIndex
        guard let target = candidates.first(where: \.isHittable),
              candidates.allSatisfy({ $0.label == target.label && $0.identifier == target.identifier && $0.frame == target.frame })
        else { return false }
        attach("ordinary-native-prompt-\(permission)")
        target.tap()
        return true
    }

    private func openSettings() throws {
        try tap("morning.actions")
        try tap("morning.settings")
    }

    private func launchOrdinaryApp() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This acceptance check requires the owner's physical iPhone.")
        #endif
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MO_ORDINARY_WEATHER_ACCEPTANCE"] == "1",
            "Explicit attended ordinary-app acceptance opt-in is required.")
        continueAfterFailure = false
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        attach("ordinary-opening")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ identifier: String) throws {
        let button = app.buttons[identifier]
        try reveal(button)
        button.tap()
    }

    private func reveal(_ target: XCUIElement) throws {
        for _ in 0..<8 where !target.exists || !target.isHittable { app.swipeUp() }
        guard target.waitForExistence(timeout: 5), target.isHittable else {
            attach("ordinary-missing-control")
            XCTFail("Required ordinary-app control is unavailable: \(target.identifier)")
            throw DriverStop.missingControl
        }
    }

    private func dismissSheet() throws {
        let done = app.navigationBars.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Terminé")).firstMatch
        try reveal(done)
        done.tap()
    }

    private func waitUntil(_ seconds: TimeInterval, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return predicate()
    }

    private func attach(_ name: String) {
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = name; screen.lifetime = .keepAlways; add(screen)
        attachText("Captured at \(Date().ISO8601Format())\n\(app.debugDescription)\n\(springboard.debugDescription)", named: "\(name)-tree")
    }

    private func attachText(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private enum DriverStop: Error { case missingControl }
}
