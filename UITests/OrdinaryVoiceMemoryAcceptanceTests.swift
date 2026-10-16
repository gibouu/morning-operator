import XCTest

/// Private, owner-authorized ordinary-phone evidence. This never injects speech or changes saved facts.
@MainActor
final class OrdinaryVoiceMemoryAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    func testOrdinaryVoiceMemoryAcceptance() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_ORDINARY_VOICE_MEMORY"] == "1" else {
            throw XCTSkip("Requires explicit MO_ORDINARY_VOICE_MEMORY=1; no app was activated.")
        }
        let phase = environment["MO_ORDINARY_VOICE_PHASE"] ?? "inspect"
        guard ["inspect", "inspectSettings", "inspectRoutine", "inspectMemory", "weatherRead", "voiceWindow", "memoryCheck"].contains(phase) else {
            throw XCTSkip("Choose inspect, inspectSettings, inspectRoutine, inspectMemory, weatherRead, voiceWindow or memoryCheck before activating the app.")
        }
        let base = "com.gibouu.morningoperator"
        guard let bundle = environment["MO_ORDINARY_VOICE_BUNDLE_ID"],
              bundle == base || bundle == base + ".personal" || bundle.hasPrefix(base + ".personal.") || bundle.hasPrefix(base + ".personal-"),
              !["fixture", "demo", "qa"].contains(where: bundle.lowercased().contains),
              bundle.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else {
            throw XCTSkip("Provide the exact ordinary MORE or personal bundle; fixture, demo and QA bundles are refused.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This acceptance requires a physical iPhone; no simulator app was activated.")
        #else
        app = XCUIApplication(bundleIdentifier: bundle)
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 10) else {
            XCTFail("The selected ordinary app did not become foreground.")
            return
        }
        try requireOrdinaryState()
        switch phase {
        case "inspect":
            capture("ordinary-voice-current")
        case "inspectSettings":
            try openSettings()
            capture("ordinary-voice-settings")
        case "inspectRoutine":
            try inspectRoutine()
        case "inspectMemory":
            try openMemory()
            capture("ordinary-voice-existing-memory")
        case "weatherRead":
            try readWeather()
        case "voiceWindow":
            try observeVoiceWindow()
        case "memoryCheck":
            try openMemory()
            guard try denialIsVisible() else {
                capture("ordinary-voice-memory-denial-missing")
                XCTFail("The existing scooter-denial fact was not visible. No fact was created or changed.")
                return
            }
            capture("ordinary-voice-memory-before-relaunch")
            app.terminate()
            app.activate()
            guard app.wait(for: .runningForeground, timeout: 10) else {
                XCTFail("Ordinary MORE did not return after normal reactivation.")
                return
            }
            try requireOrdinaryState()
            try openMemory()
            let retained = try denialIsVisible()
            capture("ordinary-voice-memory-after-relaunch")
            XCTAssertTrue(retained, "The same scooter-denial fact was not visible after relaunch.")
        default:
            break
        }
        #endif
    }

    private func requireOrdinaryState() throws {
        guard app.state == .runningForeground else {
            throw XCTSkip("MORE left the foreground; no further navigation was attempted.")
        }
        guard app.alerts.count == 0,
              XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count == 0,
              !app.buttons["permissions.allow"].exists else {
            throw XCTSkip("A permission or unexpected alert requires the owner. No permission control was pressed.")
        }
        guard !app.descendants(matching: .any)["qa.testWorkspace"].exists,
              !app.staticTexts["briefing.synthetic"].exists else {
            throw XCTSkip("A synthetic workspace or source cannot provide ordinary-phone acceptance.")
        }
    }

    private func openSettings() throws {
        try requireOrdinaryState()
        if app.descendants(matching: .any)["settings.appearance"].exists || app.buttons["setup.intelligence"].exists { return }
        let settings = app.buttons["morning.settings"]
        if !(settings.exists && settings.isHittable) {
            let captions = app.scrollViews["morning.captions"]
            if captions.exists && captions.isHittable {
                captions.tap()
            } else {
                let controls = app.buttons["morning.actions"]
                guard controls.waitForExistence(timeout: 5), controls.isHittable,
                      ["Show controls", "Afficher les commandes"].contains(controls.label) else {
                    throw XCTSkip("Leave ordinary MORE on Home or Settings. No unrelated screen was dismissed.")
                }
                controls.tap()
            }
        }
        try requireOrdinaryState()
        guard settings.waitForExistence(timeout: 5), settings.isHittable else {
            throw XCTSkip("The ordinary Settings control was not reachable.")
        }
        settings.tap()
        try requireOrdinaryState()
    }

    private func readWeather() throws {
        let refresh = app.buttons["briefing.refresh"]
        let sources = app.descendants(matching: .any).matching(identifier: "weather.sources").firstMatch
        let text = app.staticTexts["briefing.text"]
        let refreshed: Bool
        let attributionVisible: Bool
        let recapVisible: Bool
        do {
            if !refresh.exists {
                try openSettings()
                let briefing = app.buttons["setup.briefing"]
                guard try reveal(briefing) else { throw XCTSkip("The ordinary day settings were not reachable.") }
                briefing.tap()
            }
            try requireOrdinaryState()
            guard try reveal(refresh), refresh.isEnabled else {
                throw XCTSkip("The ordinary recap refresh was not ready. No source configuration was changed.")
            }
            refresh.tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: refresh)
            refreshed = XCTWaiter.wait(for: [ready], timeout: 35) == .completed
            try requireOrdinaryState()
            attributionVisible = try reveal(sources)
            capture("ordinary-voice-weather-attribution")
            recapVisible = try reveal(text)
        } catch {
            capture("ordinary-voice-weather-blocked")
            throw error
        }
        capture("ordinary-voice-weather-reading")
        XCTAssertTrue(refreshed, "The real recap refresh did not finish within 35 seconds.")
        XCTAssertTrue(attributionVisible, "No real provider weather-attribution link was visible.")
        XCTAssertTrue(recapVisible, "No ordinary sourced recap text was visible.")
    }

    private func openMemory() throws {
        if app.staticTexts["intelligence.status"].exists { return }
        try openSettings()
        let memory = app.buttons["setup.intelligence"]
        guard try reveal(memory) else { throw XCTSkip("The Intelligence & memory navigation was not reachable.") }
        memory.tap()
        guard app.staticTexts["intelligence.status"].waitForExistence(timeout: 5) else {
            XCTFail("The ordinary Intelligence & memory screen did not open.")
            return
        }
        try requireOrdinaryState()
    }

    private func inspectRoutine() throws {
        do {
            if !app.descendants(matching: .any)["routine.editor"].exists {
                try openSettings()
                let routine = app.buttons["setup.routine"]
                guard try reveal(routine) else { throw XCTSkip("The ordinary routine navigation was not reachable.") }
                routine.tap()
            }
            try requireOrdinaryState()
            guard app.descendants(matching: .any)["routine.editor"].waitForExistence(timeout: 5) else {
                throw XCTSkip("The ordinary routine editor was not identified. No draft was changed.")
            }
            capture("ordinary-voice-existing-routine")
        } catch {
            capture("ordinary-voice-routine-blocked")
            throw error
        }
    }

    private func observeVoiceWindow() throws {
        guard let seconds = Int(ProcessInfo.processInfo.environment["MO_ORDINARY_VOICE_WINDOW_SECONDS"] ?? "150"),
              (30...180).contains(seconds) else {
            throw XCTSkip("The observation duration must be between 30 and 180 seconds.")
        }
        do {
            let caption = app.staticTexts["morning.caption"]
            // A caption surface belongs only to an active ordinary session. From a
            // known settings page, observe its Stop control without pressing it.
            if !caption.exists {
                for _ in 0..<2 {
                    if app.descendants(matching: .any)["settings.appearance"].exists { break }
                    guard app.staticTexts["intelligence.status"].exists ||
                            app.descendants(matching: .any)["routine.editor"].exists else { break }
                    try normalBack()
                }
                try openSettings()
                guard try reveal(app.buttons["morning.stop"]) else {
                    throw XCTSkip("No existing active morning was identified. Nothing was started or resumed.")
                }
                capture("ordinary-voice-existing-active-session")
                try normalBack()
            }
            try requireOrdinaryState()
            guard caption.waitForExistence(timeout: 5), app.scrollViews["morning.captions"].exists else {
                throw XCTSkip("The existing session's Home caption surface was not reached by ordinary navigation.")
            }
            capture("ordinary-voice-window-initial")
            print("MORE_ORDINARY_VOICE_READY")
            let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
            var previous = ""
            var change = 0
            while ProcessInfo.processInfo.systemUptime < deadline {
                try requireOrdinaryState()
                let voice = app.staticTexts["morning.voiceStatus"]
                let state = (caption.exists ? caption.label : "") + "\n" + (voice.exists ? voice.label : "")
                if state != previous {
                    change += 1
                    capture("ordinary-voice-window-change-\(change)")
                    previous = state
                }
                if !app.scrollViews["morning.captions"].exists { break }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { RunLoop.current.run(until: Date(timeIntervalSinceNow: min(2, remaining))) }
            }
            capture("ordinary-voice-window-ended")
        } catch {
            capture("ordinary-voice-window-blocked")
            throw error
        }
    }

    private func normalBack() throws {
        try requireOrdinaryState()
        let controls = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", [
            "Back", "Retour", "Settings", "Paramètres", "Réglages", "MORE"
        ])).allElementsBoundByIndex.filter(\.isHittable)
        guard controls.count == 1 else {
            throw XCTSkip("No unambiguous ordinary Back control was available. No unrelated screen was dismissed.")
        }
        controls[0].tap()
        try requireOrdinaryState()
    }

    private func denialIsVisible() throws -> Bool {
        let fact = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "Vous n’avez pas de trottinette électrique.", "You do not have an electric scooter."
        ])).firstMatch
        return try reveal(fact)
    }

    private func reveal(_ element: XCUIElement) throws -> Bool {
        let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
            : (app.tables.firstMatch.exists ? app.tables.firstMatch : app.scrollViews.firstMatch)
        for downward in [false, true] {
            for _ in 0..<8 {
                try requireOrdinaryState()
                if element.exists && element.isHittable { return true }
                guard scroll.exists else { return false }
                if downward { scroll.swipeDown() } else { scroll.swipeUp() }
            }
        }
        return element.exists && element.isHittable
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name + "-private-screen"; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-private-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
