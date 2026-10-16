import XCTest

/// Explicit physical acceptance: no test workspace, StoreKit fixture or injected grant.
@MainActor
final class OrdinaryConnectionsAcceptanceTests: XCTestCase {
    private let bundle = "com.gibouu.morningoperator"

    func test01RealAppleOfferWhenOrdinaryAccessIsLocked() throws {
        let app = try ordinaryApp()
        if hasOrdinaryAccess(app) {
            throw XCTSkip("Existing ordinary access can include the approved Debug entry; it does not prove a StoreKit offer.")
        }

        let offer = app.buttons["onboarding.offer"]
        if offer.waitForExistence(timeout: 10) {
            offer.tap()
        } else {
            for _ in 0..<3 {
                let next = app.buttons["onboarding.next"]
                guard next.waitForExistence(timeout: 5) else { break }
                next.tap()
            }
        }

        XCTAssertTrue(app.buttons["paywall.subscribe"].waitForExistence(timeout: 10),
                      "The ordinary app did not expose its real subscription offer.")
        let price = app.staticTexts["paywall.price"]
        let loaded = price.waitForExistence(timeout: 45)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = loaded ? "ordinary-live-apple-offer" : "ordinary-apple-offer-unavailable"
        capture.lifetime = .keepAlways
        add(capture)
        XCTAssertTrue(loaded,
                      "StoreKit did not return the configured product. No purchase or entitlement was simulated.")
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        // A purchase is intentionally separate from this read-only offer check.
    }

    func test02ExistingNativeGmailReadsInsideTheOrdinaryApp() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let reader = app.buttons["connections.gmailReader"]
        try reveal(reader, in: app)
        reader.tap()
        let messages = app.descendants(matching: .any).matching(identifier: "gmail.messages").firstMatch
        let loaded = messages.waitForExistence(timeout: 45)
        if !loaded, app.buttons["gmail.connect"].exists,
           !app.staticTexts["gmail.error"].exists, !app.staticTexts["gmail.configuration"].exists {
            throw XCTSkip("This ordinary installation has no saved native Gmail grant. No new Google consent was initiated.")
        }
        XCTAssertTrue(loaded,
                      "No fresh native Gmail result was obtained from the ordinary app's existing credential.")
        XCTAssertTrue(app.staticTexts["gmail.unread"].exists)
        XCTAssertFalse(app.staticTexts["gmail.error"].exists)
        XCTAssertFalse(app.staticTexts["gmail.messages.partial"].exists)
        // Do not inspect or export message labels, addresses, bodies or counts.
    }

    func test03ExistingCalendarGrantExposesTheRealInventory() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let calendar = app.buttons["connections.calendar"]
        try reveal(calendar, in: app)
        calendar.tap()
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists)
        let calendars = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "briefing.calendar."))
        guard calendars.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("No existing native Calendar inventory was obtained; no grant or calendar selection was changed.")
        }
        XCTAssertGreaterThan(calendars.count, 0)
        XCTAssertFalse(app.staticTexts["briefing.error"].exists)
        // Inventory establishes readable calendars, not a selected-calendar event result.
    }

    func test04ExistingRemindersGrantReturnsAFreshRead() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let reminders = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
            "Find your upcoming reminders", "Retrouvez vos prochains rappels")).firstMatch
        try reveal(reminders, in: app)
        reminders.tap()
        let read = app.buttons["native.remindersRead"]
        try reveal(read, in: app)
        guard ["Show my reminders", "Afficher mes rappels"].contains(read.label) else {
            throw XCTSkip("This ordinary installation has no existing Reminders grant; no permission was requested.")
        }
        read.tap()
        let timestamp = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Read at ", "Lus à ")).firstMatch
        XCTAssertTrue(timestamp.waitForExistence(timeout: 30), "No fresh native Reminders read timestamp appeared.")
        XCTAssertFalse(app.staticTexts["native.remindersMessage"].exists)
        // Empty dated results are valid. Never inspect titles or mark anything complete.
    }

    func test05PublicCityMapsAndWeatherReadRestoresUnconfiguredWeather() throws {
        let previousFailurePolicy = continueAfterFailure
        defer { continueAfterFailure = previousFailurePolicy }
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let calendar = app.buttons["connections.calendar"]
        try reveal(calendar, in: app)
        calendar.tap()
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists)

        let source = app.descendants(matching: .any).matching(identifier: "briefing.locationSource").firstMatch
        try reveal(source, in: app)
        let knownSources = ["Current location", "Position actuelle", "Choose a city", "Choisir une ville"]
        func readSource() -> String? {
            let children = source.descendants(matching: .staticText).allElementsBoundByIndex +
                source.descendants(matching: .button).allElementsBoundByIndex
            let pickerElements = [source] + children
            let texts = pickerElements.flatMap { [$0.label, $0.value as? String ?? ""] }
            let choices = knownSources.filter { choice in
                texts.contains { $0.localizedCaseInsensitiveContains(choice) }
            }
            guard choices.count == 1 else {
                let metadata = pickerElements.map {
                    "type=\($0.elementType.rawValue); label=\($0.label); value=\($0.value as? String ?? "<nil>")"
                }.joined(separator: "\n")
                let attachment = XCTAttachment(string: metadata)
                attachment.name = "ordinary-weather-picker-selection-only"
                attachment.lifetime = .keepAlways
                add(attachment)
                return nil
            }
            return choices[0]
        }
        guard let originalSource = readSource() else {
            XCTFail("The ordinary weather picker did not expose its original selection; no setting was changed.")
            return
        }
        if app.descendants(matching: .any).matching(identifier: "briefing.currentLocation").firstMatch.exists ||
            app.buttons["briefing.removeWeather"].exists {
            throw XCTSkip("Existing weather is configured; no weather selection was changed.")
        }
        let city = app.descendants(matching: .any).matching(identifier: "briefing.city").firstMatch
        var attemptedOurCity = false

        func require(_ condition: Bool, _ message: String) throws {
            guard condition else {
                XCTFail(message)
                throw NSError(domain: "OrdinaryConnectionsAcceptanceTests", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Required public-city UI check failed."])
            }
        }
        func selectSource(_ labels: [String]) -> Bool {
            if let selection = readSource(), labels.contains(selection) { return true }
            try? reveal(source, in: app)
            guard source.exists && source.isHittable else { return false }
            source.tap()
            let option = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
            guard option.waitForExistence(timeout: 5), option.isHittable else { return false }
            option.tap()
            guard let selection = readSource() else { return false }
            return labels.contains(selection)
        }
        func showsOurCity() -> Bool {
            guard city.exists else { return false }
            let text = ([city.label, city.value as? String ?? ""] +
                city.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label)).joined(separator: " ")
            return text.localizedCaseInsensitiveContains("Paris") && text.localizedCaseInsensitiveContains("France")
        }

        // The picker saves immediately. Verify city removal before hiding it with another source.
        continueAfterFailure = true
        defer {
            var canRestoreSource = !attemptedOurCity
            if attemptedOurCity {
                try? reveal(city, in: app)
                var removalVerified = true
                if city.exists {
                    removalVerified = false
                    if showsOurCity() {
                        let remove = app.buttons["briefing.removeWeather"]
                        try? reveal(remove, in: app)
                        let tappedRemove = remove.exists && remove.isHittable
                        if tappedRemove { remove.tap() }
                        else { try? require(false, "The temporary city's Remove weather control was unavailable.") }
                        let removed = city.waitForNonExistence(timeout: 5)
                        try? require(removed, "The temporary public city must be removed.")
                        removalVerified = tappedRemove && removed
                    } else {
                        try? require(false, "An unexpected city is present; it was preserved rather than removed.")
                    }
                }
                let emptySearch = app.textFields["briefing.citySearch"]
                try? reveal(emptySearch, in: app)
                let choosingCity = ["Choose a city", "Choisir une ville"].contains(readSource() ?? "")
                // Check the empty city UI before Current location can hide a saved fallback.
                let noResidue = choosingCity && emptySearch.exists && emptySearch.isHittable &&
                    !city.exists && !showsOurCity() && !app.buttons["briefing.removeWeather"].exists
                try? require(noResidue, "The temporary city must be absent in Choose a city mode before restoring the source.")
                canRestoreSource = removalVerified && noResidue
            }
            if canRestoreSource {
                let restored = selectSource([originalSource])
                try? require(restored, "The original weather-source selection must be restored.")
                let matchesOriginal = readSource() == originalSource
                try? require(matchesOriginal, "The original weather-source selection must match exactly.")
                if restored && matchesOriginal {
                    let done = app.navigationBars.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Terminé")).firstMatch
                    if done.exists && done.isHittable { done.tap() }
                }
            } else {
                try? require(false, "Weather cleanup could not be verified; the city and its source were left visible for reconciliation.")
            }
        }

        try require(selectSource(["Choose a city", "Choisir une ville"]), "The ordinary picker did not select Choose a city.")
        let search = app.textFields["briefing.citySearch"]
        try reveal(search, in: app)
        try require(search.exists && search.isHittable, "The public city search field was unavailable.")
        // Current-location mode can hide a saved fallback city; inspect after switching modes.
        guard !city.exists, !app.buttons["briefing.removeWeather"].exists else {
            throw XCTSkip("An existing weather city is configured; its value and the original picker were preserved.")
        }
        search.tap()
        search.typeText("Paris, France")
        let searchButton = app.buttons["briefing.searchCities"]
        try reveal(searchButton, in: app)
        try require(searchButton.exists && searchButton.isHittable && searchButton.isEnabled,
                    "The explicit city-search action was unavailable.")
        searchButton.tap()
        let result = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@ AND label CONTAINS[cd] %@",
            "briefing.cityResult.", "Paris", "France")).firstMatch
        try require(result.waitForExistence(timeout: 25), "Apple Maps did not return Paris, France.")
        try reveal(result, in: app)
        try require(result.exists && result.isHittable, "The real Paris, France result was not reachable.")
        attemptedOurCity = true
        result.tap()
        try require(city.waitForExistence(timeout: 5), "The selected public city did not appear.")
        try require(showsOurCity(), "The selected public city must be Paris, France.")

        let attribution = app.descendants(matching: .any).matching(identifier: "weather.sources").firstMatch
        try reveal(attribution, in: app)
        try require(attribution.exists && attribution.isHittable, "No admitted native Apple Weather snapshot appeared.")
        let wind = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "km/h")).firstMatch
        try reveal(wind, in: app)
        try require(wind.exists && wind.isHittable, "The native snapshot must contain a measured wind value.")
        try require(!app.staticTexts["briefing.error"].exists, "The ordinary briefing reported an error.")
        try require(!app.staticTexts["briefing.synthetic"].exists, "A synthetic source cannot establish provider acceptance.")
        let note = XCTAttachment(string: "Real Apple Maps result selected for public Paris, France; admitted Apple Weather attribution and measured wind present. No location permission or owner content was requested. Cleanup assertions run in defer.")
        note.name = "ordinary-public-city-provider-evidence"
        note.lifetime = .keepAlways
        add(note)
    }

    func test06OrdinaryWorkerLoadsFreshNotionServiceAndEmptyInventory() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let notion = app.buttons["connections.account.notion"]
        try reveal(notion, in: app)
        XCTAssertTrue(notion.exists && notion.isHittable, "The ordinary Worker service list did not expose Notion.")
        notion.tap()
        XCTAssertTrue(app.navigationBars["Notion"].waitForExistence(timeout: 10))

        // Both labels require hasLoaded, set only after services and connections succeed.
        let refresh = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label IN %@",
            "accounts.refresh", ["Refresh my accounts", "Actualiser mes comptes"])).firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 45), "No successful fresh Worker services/connections read appeared.")
        try reveal(refresh, in: app)
        XCTAssertTrue(refresh.isHittable && refresh.isEnabled)
        let empty = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "No account connected yet. Sign in above, then choose the permissions you want to share.",
            "Aucun compte connecté pour le moment. Identifiez-vous ci-dessus, puis choisissez les accès à partager."
        ])).firstMatch
        XCTAssertTrue(empty.exists, "The fresh Notion inventory did not report an empty account state.")
        XCTAssertTrue(app.buttons["accounts.connect.notion"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "accounts.notice").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Connection unavailable"].exists)
        XCTAssertFalse(app.staticTexts["Connexion indisponible"].exists)
        let note = XCTAttachment(string: "The ordinary iPhone app completed installation-authenticated Worker services and connections reads and displayed the fresh empty Notion inventory. No sign-in, tool-catalog read or Notion action was initiated.")
        note.name = "ordinary-worker-services-and-connections-evidence"
        note.lifetime = .keepAlways
        add(note)
    }

    func test07RequestNativeCalendarAccessAndReadFreshSelectedDay() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_REQUEST_NATIVE_ACCESS"] == "1",
                          "Requires explicit permission-request acceptance opt-in.")
        let previousFailurePolicy = continueAfterFailure
        defer { continueAfterFailure = previousFailurePolicy }
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let calendar = app.buttons["connections.calendar"]
        try reveal(calendar, in: app)
        calendar.tap()
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists)
        let calendars = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "briefing.calendar."))
        if !calendars.firstMatch.exists {
            let connect = app.buttons["briefing.calendarConnect"]
            try reveal(connect, in: app)
            XCTAssertTrue(connect.exists && connect.isHittable)
            connect.tap()
        }
        try waitForNativePermissionAndRead(app, permission: .calendar) { calendars.firstMatch.exists }
        XCTAssertFalse(app.staticTexts["briefing.error"].exists)

        // Only one known-off switch may change. Other saved selections stay untouched.
        let hasSelection = calendars.allElementsBoundByIndex.contains { ($0.value as? String) == "1" }
        var temporaryCalendar: XCUIElement?
        func attachSelectionDiagnostic(_ element: XCUIElement) {
            let issue = app.staticTexts["briefing.error"]
            let value = element.exists ? element.value as? String ?? "<unknown>" : "<missing>"
            let state = element.exists
                ? "type=\(element.elementType.rawValue),frame=\(element.frame),value=\(["0", "1"].contains(value) ? value : "<unknown>")"
                : "switch=<missing>"
            let attachment = XCTAttachment(string: state + "\nbriefing.error=" + (issue.exists ? issue.label : "<not present>"))
            attachment.name = "ordinary-native-calendar-selection-diagnostic"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        continueAfterFailure = true
        defer {
            var selectionRestored = true
            if let temporaryCalendar {
                try? reveal(temporaryCalendar, in: app)
                if temporaryCalendar.exists && temporaryCalendar.isHittable && temporaryCalendar.isEnabled,
                   temporaryCalendar.value as? String == "1" {
                    temporaryCalendar.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                }
                let restored = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == true AND value == %@", "0"), object: temporaryCalendar)
                selectionRestored = XCTWaiter.wait(for: [restored], timeout: 8) == .completed
                if !selectionRestored { attachSelectionDiagnostic(temporaryCalendar) }
                try? requirePhysicalNative(selectionRestored,
                    "The temporarily selected calendar must return to its original off state.")
            }
            let done = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Terminé"])).firstMatch
            if selectionRestored && done.exists && done.isHittable { done.tap() }
        }
        if !hasSelection {
            let first = calendars.element(boundBy: 0)
            try reveal(first, in: app)
            let selectable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true AND value == %@", "0"), object: first)
            let ready = XCTWaiter.wait(for: [selectable], timeout: 10) == .completed
            if !ready { attachSelectionDiagnostic(first) }
            try requirePhysicalNative(ready,
                "The known-off native calendar selection did not become ready.")
            try requirePhysicalNative(first.exists && first.isHittable && first.isEnabled && first.value as? String == "0",
                "A known-off native calendar selection was not available.")
            temporaryCalendar = first
            first.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND value == %@", "1"), object: first)
            let saved = XCTWaiter.wait(for: [selected], timeout: 10) == .completed
            if !saved { attachSelectionDiagnostic(first) }
            try requirePhysicalNative(saved,
                "The native calendar selection did not save.")
        }
        let refresh = app.buttons["briefing.refresh"]
        try reveal(refresh, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: refresh)
        try requirePhysicalNative(XCTWaiter.wait(for: [enabled], timeout: 15) == .completed,
            "The ordinary recap was still preparing before the explicit refresh.")
        try requirePhysicalNative(refresh.exists && refresh.isHittable && refresh.isEnabled,
            "The ordinary recap could not be refreshed.")
        refresh.tap()
        let readAt = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Local read at ", "Lu localement à ")).firstMatch
        try reveal(readAt, in: app)
        try requirePhysicalNative(readAt.exists, "No fresh native Calendar read timestamp appeared.")
        let fresh = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
            "Read from your selected calendars.", "Lu depuis les calendriers sélectionnés.")).firstMatch
        try requirePhysicalNative(fresh.exists, "The selected-calendar result was not admitted as fresh.")
        try requirePhysicalNative(!app.staticTexts["briefing.error"].exists, "The native Calendar read reported an error.")
        let note = XCTAttachment(string: "Native Calendar permission path completed; real inventory, selected-calendar fresh status and local-read timestamp appeared. Calendar names, event contents and identifiers were not exported. Temporary selection is restored in defer.")
        note.name = "ordinary-native-calendar-permission-and-read"
        note.lifetime = .keepAlways
        add(note)
    }

    func test08RequestNativeRemindersAccessAndReadFreshInventory() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_REQUEST_NATIVE_ACCESS"] == "1",
                          "Requires explicit permission-request acceptance opt-in.")
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let reminders = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
            "Find your upcoming reminders", "Retrouvez vos prochains rappels")).firstMatch
        try reveal(reminders, in: app)
        reminders.tap()
        let read = app.buttons["native.remindersRead"]
        try reveal(read, in: app)
        XCTAssertTrue(read.exists && read.isHittable && read.isEnabled)
        try inspectRemindersSettingsRecoveryIfPresented(app)
        read.tap()
        let timestamp = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Read at ", "Lus à ")).firstMatch
        try waitForNativePermissionAndRead(app, permission: .reminders) { timestamp.exists }
        XCTAssertTrue(timestamp.exists, "No fresh native Reminders read timestamp appeared.")
        XCTAssertFalse(app.staticTexts["native.remindersMessage"].exists)
        let note = XCTAttachment(string: "Native Reminders permission path completed and a fresh local-store read timestamp appeared. Empty results are valid; no reminder titles, counts, completion changes or synthetic items were exported or created.")
        note.name = "ordinary-native-reminders-permission-and-read"
        note.lifetime = .keepAlways
        add(note)
    }

    func test12ReadPrivateInstallationSupportCodeFromOrdinaryApp() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let notion = app.buttons["connections.account.notion"]
        try reveal(notion, in: app)
        notion.tap()
        let refresh = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label IN %@",
            "accounts.refresh", ["Refresh my accounts", "Actualiser mes comptes"])).firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 45), "No fresh ordinary Worker account state appeared.")
        let shared = app.buttons.matching(NSPredicate(format: "label IN %@", ["Shared data", "Données partagées"])).firstMatch
        try reveal(shared, in: app)
        shared.tap()
        let details = app.buttons.matching(NSPredicate(format: "label IN %@", ["Connection details", "Détails de connexion"])).firstMatch
        try reveal(details, in: app)
        details.tap()
        let show = app.buttons["accounts.installationCode.show"]
        try reveal(show, in: app)
        XCTAssertTrue(show.exists && show.isHittable && show.isEnabled)
        show.tap()
        let codeElement = app.staticTexts["accounts.installationCode"]
        XCTAssertTrue(codeElement.waitForExistence(timeout: 15), "The ordinary installation support code did not appear.")
        let code = codeElement.label
        XCTAssertTrue(code.range(of: "^[a-f0-9]{24}$", options: .regularExpression) != nil,
                      "The private installation support code has an unexpected format.")
        let attachment = XCTAttachment(string: code)
        attachment.name = "ordinary-installation-support-code"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test09RequestHealthReadAccessAndRequireFreshSamples() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_REQUEST_NATIVE_ACCESS"] == "1",
                          "Requires explicit permission-request acceptance opt-in.")
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openOrdinarySettingsDestination("setup.health", in: app)
        let included = app.switches["briefing.healthIncluded"]
        try reveal(included, in: app)
        XCTAssertTrue(["0", "1"].contains(included.value as? String ?? ""),
                      "The ordinary Health choice did not expose a known state.")
        if included.value as? String == "0" { included.tap() }
        else {
            let expand = app.buttons["briefing.expandHealth"]
            if expand.exists && expand.isHittable { expand.tap() }
        }

        var deadline = Date().addingTimeInterval(45)
        var ownerGateReported = false
        var healthConsentRecognized = false
        let allowedTypes = ["Sleep", "Sleep Analysis", "Sommeil", "Analyse du sommeil",
                            "Heart Rate Variability", "Heart Rate Variability (SDNN)",
                            "Variabilité de la fréquence cardiaque", "Variabilité de la fréquence cardiaque (SDNN)",
                            "Resting Heart Rate", "Fréquence cardiaque au repos",
                            "Respiratory Rate", "Fréquence respiratoire"]
        repeat {
            if protectedAuthenticationVisible(in: app) {
                if !ownerGateReported {
                    recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_HEALTH_AUTHENTICATION")
                    deadline = Date().addingTimeInterval(180)
                    ownerGateReported = true
                }
            } else {
                let typeSwitches = app.switches.matching(NSPredicate(format: "label IN %@", allowedTypes))
                    .allElementsBoundByIndex
                let turnOnAll = app.buttons.matching(NSPredicate(format: "label IN %@",
                    ["Turn On All", "Turn On All Categories", "Activer tout", "Tout activer"])).firstMatch
                let matchingApp = app.navigationBars["MORE"].exists ||
                    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "MORE")).firstMatch.exists
                // These controls belong to Apple's read sheet, not the single product inclusion toggle.
                if matchingApp && (typeSwitches.count >= 2 || turnOnAll.exists) {
                    healthConsentRecognized = true
                    if turnOnAll.exists && turnOnAll.isHittable { turnOnAll.tap() }
                    else if let off = typeSwitches.first(where: { $0.isHittable && $0.value as? String == "0" }) { off.tap() }
                    else {
                        let allow = app.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Autoriser"])).firstMatch
                        if allow.exists && allow.isHittable && allow.isEnabled { allow.tap() }
                    }
                } else if healthConsentRecognized {
                    let allow = app.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Autoriser"])).firstMatch
                    if allow.exists && allow.isHittable && allow.isEnabled { allow.tap() }
                }
            }
            if included.exists, included.value as? String == "1",
               app.buttons["briefing.refreshSleep"].exists { break }
            if app.staticTexts["briefing.healthError"].exists { break }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        if protectedAuthenticationVisible(in: app) {
            recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_HEALTH_AUTHENTICATION")
            throw XCTSkip("A protected Health authorization step remains presented for the owner.")
        }
        XCTAssertTrue(included.value as? String == "1", "The ordinary Health authorization flow did not complete.")
        XCTAssertFalse(app.staticTexts["briefing.healthError"].exists)
        let refresh = app.buttons["briefing.refreshSleep"]
        try reveal(refresh, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 20), .completed)
        refresh.tap()
        let metrics = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "briefing.health."))
        let sleepSources = app.descendants(matching: .any).matching(identifier: "briefing.sleepSources").firstMatch
        let readDeadline = Date().addingTimeInterval(45)
        var expanded = false
        repeat {
            if metrics.firstMatch.exists || sleepSources.exists { break }
            if !expanded {
                let details = app.buttons.matching(NSPredicate(format: "label IN %@", ["Sources and access", "Sources et accès"])).firstMatch
                if details.exists {
                    try reveal(details, in: app)
                    if details.isHittable { details.tap(); expanded = true }
                }
            }
            if app.staticTexts["briefing.healthError"].exists { break }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < readDeadline
        let actualSamples = metrics.firstMatch.exists || sleepSources.exists
        if !actualSamples { recordPrivateNativeStage("HEALTH_FRESH_SAMPLES_NOT_CONFIRMED") }
        XCTAssertTrue(actualSamples, "No fresh Health sample output was obtained; an empty result cannot prove read access.")
        XCTAssertFalse(app.staticTexts["briefing.healthError"].exists)
        recordPrivateNativeStage("HEALTH_FRESH_SAMPLE_OUTPUT_CONFIRMED")
    }

    func test10RequestScreenTimeDataAccessAndRequireFreshAppUse() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_REQUEST_NATIVE_ACCESS"] == "1",
                          "Requires explicit permission-request acceptance opt-in.")
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openOrdinarySettingsDestination("setup.screenTime", in: app)
        let daily = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "screenTime.daily."))
        XCTAssertFalse(daily.firstMatch.exists, "A prior in-memory result cannot establish this read.")
        let start = app.buttons["learn.screenTime.start"]
        try reveal(start, in: app)
        XCTAssertTrue(start.exists && start.isHittable && start.isEnabled)
        start.tap()
        var deadline = Date().addingTimeInterval(75)
        var ownerGateReported = false
        repeat {
            if daily.firstMatch.exists { break }
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let system = springboard.alerts.firstMatch
            let alert = system.exists ? system : app.alerts.firstMatch
            if alert.exists {
                let words = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ").lowercased()
                let recognized = (words.contains("more") || words.contains("morningoperator")) &&
                    ["screen time", "temps d’écran", "temps d'écran", "app and website", "activité"].contains(where: words.contains)
                let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "Continuer", "Allow", "Autoriser"])).firstMatch
                if recognized && allow.exists && allow.isHittable && allow.isEnabled {
                    allow.tap()
                    continue
                }
            }
            if protectedAuthenticationVisible(in: app) {
                if !ownerGateReported {
                    recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_SCREEN_TIME_AUTHENTICATION")
                    deadline = Date().addingTimeInterval(180)
                    ownerGateReported = true
                }
            } else {
                if alert.exists {
                    try requirePhysicalNative(false, "An unrecognized Screen Time prompt needs local review; no control was pressed.")
                }
            }
            let empty = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label IN %@",
                "learn.screenTime.message", [
                    "Screen Time returned no app-use data for this period. You can also add your videos or learn in the browser.",
                    "Screen Time n’a fourni aucune donnée d’usage pour cette période. Vous pouvez aussi ajouter vos vidéos ou apprendre dans le navigateur."
                ])).firstMatch
            if empty.exists { recordPrivateNativeStage("SCREEN_TIME_RETURNED_EMPTY_DATA"); break }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        if protectedAuthenticationVisible(in: app) {
            recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_SCREEN_TIME_AUTHENTICATION")
            throw XCTSkip("A protected Screen Time authorization step remains presented for the owner.")
        }
        XCTAssertTrue(daily.firstMatch.exists, "No fresh Screen Time app-use output was obtained; approval or an old proposal is insufficient.")
        XCTAssertTrue(["Refresh app use", "Actualiser l’usage des apps"].contains(start.label),
                      "The data-access authorization state was not confirmed.")
        recordPrivateNativeStage("SCREEN_TIME_FRESH_APP_USE_CONFIRMED")
        // The resulting local observation/proposal is retained; nothing is approved or executed here.
    }

    func test11NativeGmailStartConsentAndRequireFreshInbox() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_REQUEST_NATIVE_ACCESS"] == "1",
                          "Requires explicit permission-request acceptance opt-in.")
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let reader = app.buttons["connections.gmailReader"]
        try reveal(reader, in: app)
        reader.tap()
        let messages = app.descendants(matching: .any).matching(identifier: "gmail.messages").firstMatch
        if messages.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.staticTexts["gmail.unread"].exists)
            XCTAssertFalse(app.staticTexts["gmail.error"].exists)
            XCTAssertFalse(app.staticTexts["gmail.messages.partial"].exists)
            recordPrivateNativeStage("NATIVE_GMAIL_FRESH_READ_EXISTING_GRANT")
            return
        }
        XCTAssertFalse(app.staticTexts["gmail.configuration"].exists, "The ordinary native Google client is not configured.")
        let connect = app.buttons["gmail.connect"]
        try reveal(connect, in: app)
        XCTAssertTrue(connect.exists && connect.isHittable && connect.isEnabled)
        let approvedAccount = ProcessInfo.processInfo.environment["MORE_PHYSICAL_GOOGLE_ACCOUNT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(approvedAccount.isEmpty, "The approved Google account was not supplied to the runner.")
        connect.tap()
        recordPrivateNativeStage("NATIVE_GMAIL_CONNECT_DISPATCHED")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(180)
        var enteredAccount = false
        var selectedAccount = false
        var announcedHumanGate = false
        var humanGateCurrentlyVisible = false
        var connectionErrorPresented = false
        var missingApprovedAccountSince: Date?
        var googleSystemConsentSeen = false
        repeat {
            humanGateCurrentlyVisible = false
            if messages.exists {
                XCTAssertTrue(app.staticTexts["gmail.unread"].exists)
                XCTAssertFalse(app.staticTexts["gmail.error"].exists)
                XCTAssertFalse(app.staticTexts["gmail.messages.partial"].exists)
                recordPrivateNativeStage("NATIVE_GMAIL_FRESH_READ_AFTER_REAL_CONSENT")
                return
            }
            let system = springboard.alerts.firstMatch
            let alert = system.exists ? system : app.alerts.firstMatch
            if alert.exists {
                let words = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ").lowercased()
                if words.contains("google.com"), words.contains("more") || words.contains("morningoperator") {
                    let proceed = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "Continuer"])).firstMatch
                    if proceed.exists && proceed.isHittable {
                        proceed.tap()
                        googleSystemConsentSeen = true
                        recordPrivateNativeStage("NATIVE_GMAIL_GOOGLE_SYSTEM_CONTINUE_ACCEPTED")
                    }
                }
            }
            let web = app.webViews.firstMatch
            if web.exists {
                let blockedTitles = [
                    "Access blocked", "Accès bloqué", "This app is blocked", "Cette application est bloquée",
                    "Google hasn’t verified this app", "Google hasn't verified this app",
                    "Google n’a pas validé cette application", "Google n'a pas validé cette application",
                    "This browser or app may not be secure",
                    "Ce navigateur ou cette application ne sont peut-être pas sécurisés"
                ]
                let blocked = web.staticTexts.allElementsBoundByIndex.contains { element in
                    blockedTitles.contains { element.label.localizedCaseInsensitiveContains($0) }
                }
                if blocked {
                    recordPrivateNativeStage("NATIVE_GMAIL_PROVIDER_BLOCK_PRESENTED")
                    try requirePhysicalNative(false, "Google presented a provider block; the page was left intact for local review.")
                }
                let googleDomain = app.descendants(matching: .any).matching(NSPredicate(format:
                    "label CONTAINS %@ OR label == %@", "accounts.google.com", "google.com")).firstMatch.exists
                let googleContext = googleDomain || googleSystemConsentSeen
                if googleContext {
                    let choosing = web.staticTexts.matching(NSPredicate(format: "label IN %@",
                        ["Choose an account", "Choisir un compte", "Sélectionner un compte"])).firstMatch.exists
                    if choosing && !selectedAccount {
                        let options = web.buttons.allElementsBoundByIndex + web.links.allElementsBoundByIndex +
                            web.staticTexts.allElementsBoundByIndex
                        if let accountOption = options.first(where: {
                            $0.isHittable && $0.label.split(whereSeparator: {
                                $0.isWhitespace || "<>()[],;".contains($0)
                            }).contains { String($0).caseInsensitiveCompare(approvedAccount) == .orderedSame }
                        }) {
                            // Tap a coordinate so the chosen identity is not echoed as a tap label.
                            let frame = accountOption.frame
                            app.coordinate(withNormalizedOffset: .zero)
                                .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
                            selectedAccount = true
                            missingApprovedAccountSince = nil
                            recordPrivateNativeStage("NATIVE_GMAIL_APPROVED_ACCOUNT_SELECTED")
                        } else {
                            if missingApprovedAccountSince == nil { missingApprovedAccountSince = Date() }
                            if let missingApprovedAccountSince, Date().timeIntervalSince(missingApprovedAccountSince) >= 3 {
                                humanGateCurrentlyVisible = true
                                if !announcedHumanGate {
                                    recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_GOOGLE_ACCOUNT_SELECTION")
                                    announcedHumanGate = true
                                }
                            }
                        }
                    }
                    let emailField = web.textFields.matching(NSPredicate(format: "identifier == %@ OR label IN %@",
                        "identifierId", ["Email or phone", "Adresse e-mail ou téléphone"])).firstMatch
                    if emailField.exists && emailField.isHittable && !enteredAccount {
                        let value = emailField.value as? String ?? ""
                        let empty = value.isEmpty || ["Email or phone", "Adresse e-mail ou téléphone"].contains(value)
                        if empty {
                            emailField.tap()
                            emailField.typeText(approvedAccount)
                        }
                        if empty || value.caseInsensitiveCompare(approvedAccount) == .orderedSame {
                            let next = web.buttons.matching(NSPredicate(format: "label IN %@", ["Next", "Suivant"])).firstMatch
                            if next.exists && next.isHittable && next.isEnabled {
                                next.tap()
                                enteredAccount = true
                                recordPrivateNativeStage("NATIVE_GMAIL_APPROVED_ACCOUNT_ENTERED")
                            }
                        } else {
                            humanGateCurrentlyVisible = true
                            if !announcedHumanGate {
                                recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_GOOGLE_ACCOUNT_SELECTION")
                                announcedHumanGate = true
                            }
                        }
                    }
                    let requestedByMORE = web.staticTexts.matching(NSPredicate(format:
                        "label CONTAINS[cd] %@ AND (label CONTAINS[cd] %@ OR label CONTAINS[cd] %@ OR label CONTAINS[cd] %@ OR label CONTAINS[cd] %@)",
                        "MORE", "Google Account", "compte Google", "Sign in to", "Se connecter à")).firstMatch.exists
                    if requestedByMORE {
                        let proceed = web.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "Continuer"])).firstMatch
                        if proceed.exists && proceed.isHittable && proceed.isEnabled {
                            proceed.tap()
                            recordPrivateNativeStage("NATIVE_GMAIL_MORE_GOOGLE_SCOPE_CONTINUE_ACCEPTED")
                        }
                    }
                    let challenge = web.staticTexts.matching(NSPredicate(format: "label IN %@", [
                        "Verify it’s you", "Verify it's you", "Confirmez votre identité",
                        "2-Step Verification", "Validation en deux étapes",
                        "Enter your password", "Saisissez votre mot de passe",
                        "Use your passkey", "Utiliser votre clé d’accès", "Utiliser votre clé d'accès",
                        "Check your phone", "Consultez votre téléphone"
                    ])).firstMatch.exists
                    if web.secureTextFields.firstMatch.exists || challenge {
                        humanGateCurrentlyVisible = true
                        if !announcedHumanGate {
                            recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_GOOGLE_AUTHENTICATION")
                            announcedHumanGate = true
                        }
                    }
                }
            }
            if protectedAuthenticationVisible(in: app) {
                humanGateCurrentlyVisible = true
                if !announcedHumanGate {
                    recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_GOOGLE_AUTHENTICATION")
                    announcedHumanGate = true
                }
            }
            if app.staticTexts["gmail.error"].exists {
                recordPrivateNativeStage("NATIVE_GMAIL_REPORTED_CONNECTION_ERROR")
                connectionErrorPresented = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        // No cancellation, Back, termination or teardown dismissal: preserve actual auth.
        if humanGateCurrentlyVisible && !connectionErrorPresented {
            throw XCTSkip("The actual Google account/authentication gate remains presented for the owner; no mailbox success is claimed.")
        }
        try requirePhysicalNative(false, "The real Google consent route did not produce a verified fresh native Inbox read.")
    }

    private func openOrdinarySettingsDestination(_ identifier: String, in app: XCUIApplication) throws {
        try openConnections(app)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.exists && back.isHittable)
        back.tap()
        let destination = app.buttons[identifier]
        try reveal(destination, in: app)
        XCTAssertTrue(destination.exists && destination.isHittable)
        destination.tap()
    }

    private func protectedAuthenticationVisible(in app: XCUIApplication) -> Bool {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let titles = ["Face ID", "Touch ID", "Enter Passcode", "Enter iPhone Passcode",
                      "Saisir le code", "Saisir le code de l’iPhone", "Saisir le code de l'iPhone"]
        return system.secureTextFields.firstMatch.exists ||
            app.secureTextFields.firstMatch.exists ||
            system.staticTexts.matching(NSPredicate(format: "label IN %@", titles)).firstMatch.exists ||
            app.staticTexts.matching(NSPredicate(format: "label IN %@", titles)).firstMatch.exists
    }

    private func recordPrivateNativeStage(_ stage: String) {
        print(stage)
        let attachment = XCTAttachment(string: stage)
        attachment.name = "ordinary-native-acceptance-stage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum NativeReadPermission: Equatable { case calendar, reminders }

    private func waitForNativePermissionAndRead(_ app: XCUIApplication, permission: NativeReadPermission,
                                                ready: () -> Bool) throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let purpose = permission == .calendar ? ["calendar", "calendrier"] : ["reminder", "rappel"]
        let allowLabels = ["Allow Full Access", "Allow Full Access to Calendars", "Allow",
                           "Autoriser l’accès complet", "Autoriser l'accès complet", "Accès complet", "Autoriser"]
        let deadline = Date().addingTimeInterval(45)
        repeat {
            if ready() { return }
            let systemAlert = springboard.alerts.firstMatch
            let alert = systemAlert.exists ? systemAlert : app.alerts.firstMatch
            if alert.exists {
                let text = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label))
                    .joined(separator: " ").lowercased()
                let recognized = (text.contains("more") || text.contains("morningoperator")) &&
                    purpose.contains(where: text.contains)
                if !recognized && permission == .reminders { attachRemindersReadDiagnostic(app) }
                try requirePhysicalNative(recognized,
                    "An unrecognized or authentication prompt needs owner action; no control was pressed.")
                let matches = alert.buttons.matching(NSPredicate(format: "label IN %@", allowLabels))
                    .allElementsBoundByIndex.filter(\.isHittable)
                guard let allow = matches.first,
                      matches.allSatisfy({ $0.label == allow.label && $0.identifier == allow.identifier && $0.frame == allow.frame }) else {
                    if permission == .reminders { attachRemindersReadDiagnostic(app) }
                    try requirePhysicalNative(false, "The matching native access prompt exposed no unambiguous known Allow action.")
                    return
                }
                allow.tap()
            }
            if permission == .reminders && app.staticTexts["native.remindersMessage"].exists {
                try inspectRemindersSettingsRecoveryIfPresented(app)
                attachRemindersReadDiagnostic(app)
                try requirePhysicalNative(false, "The real native Reminders read reported an app-owned diagnostic.")
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        if !ready() && permission == .reminders { attachRemindersReadDiagnostic(app) }
        try requirePhysicalNative(ready(), "Native permission/read did not complete; inspect the local result for the required owner or provider action.")
    }

    private func attachRemindersReadDiagnostic(_ app: XCUIApplication) {
        // Only product-owned status is retained, never reminder content or the app tree.
        let message = app.staticTexts["native.remindersMessage"]
        let read = app.buttons["native.remindersRead"]
        let status = "native.remindersMessage=" + (message.exists ? message.label : "<not present>") +
            "\nreadControlEnabled=" + String(read.exists && read.isEnabled)
        let attachment = XCTAttachment(string: status)
        attachment.name = "ordinary-native-reminders-read-diagnostic"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func inspectRemindersSettingsRecoveryIfPresented(_ app: XCUIApplication) throws {
        let link = app.descendants(matching: .any).matching(identifier: "native.remindersSettings").firstMatch
        guard link.exists else { return }
        try reveal(link, in: app)
        try requirePhysicalNative(link.exists && link.isHittable,
            "The ordinary Reminders Settings recovery link was not reachable.")
        link.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let foreground = settings.wait(for: .runningForeground, timeout: 15)
        let moreHeader = settings.navigationBars.matching(NSPredicate(format: "identifier IN %@ OR label IN %@",
            ["MORE", "MorningOperator"], ["MORE", "MorningOperator"])).firstMatch
        let hasMoreHeader = foreground && moreHeader.waitForExistence(timeout: 10)
        let allowedLabels = ["MORE", "MorningOperator", "Reminders", "Rappels", "Full Access", "Accès complet",
                             "Allow Full Access", "Autoriser l’accès complet", "Autoriser l'accès complet",
                             "None", "Aucun", "Add Reminders Only", "Ajouter des rappels uniquement"]
        var metadata = ["settingsForeground=\(foreground)", "moreAppHeader=\(hasMoreHeader)"]
        for element in settings.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", allowedLabels))
            .allElementsBoundByIndex.prefix(30) {
            let knownValue = ["0", "1"].contains(element.value as? String ?? "") ? element.value as? String ?? "" : "<not exported>"
            metadata.append("type=\(element.elementType.rawValue),label=\(element.label),value=\(knownValue)")
        }
        let attachment = XCTAttachment(string: metadata.joined(separator: "\n"))
        attachment.name = "ordinary-reminders-settings-public-controls"
        attachment.lifetime = .keepAlways
        add(attachment)
        try requirePhysicalNative(hasMoreHeader,
            "The recovery route did not establish MORE’s own iPhone Settings page; no setting was changed.")
        recordPrivateNativeStage("HUMAN_ACTION_REQUIRED_REMINDERS_SETTINGS_REVIEW")
        // First observe the real Settings AX; do not guess a system permission control.
        throw XCTSkip("MORE’s Reminders Settings page remains open for exact-control review; access and fresh read are not yet proven.")
    }

    private func requirePhysicalNative(_ condition: Bool, _ message: String) throws {
        guard condition else {
            XCTFail(message)
            throw NSError(domain: "OrdinaryConnectionsAcceptanceTests", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Required ordinary native-access check failed."])
        }
    }

    private func ordinaryApp() throws -> XCUIApplication {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_CONNECTIONS_ACCEPTANCE"] == "1",
                          "Requires an explicit physical acceptance opt-in.")
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the ordinary physical iPhone.")
        #else
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        for identifier in ["qa.testWorkspace", "onboarding.preview", "briefing.synthetic"] {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists,
                           "A preview or fixture cannot establish ordinary acceptance.")
        }
        return app
        #endif
    }

    private func hasOrdinaryAccess(_ app: XCUIApplication) -> Bool {
        app.buttons["morning.actions"].exists || app.buttons["permissions.allow"].exists
    }

    private func enterDeveloperAccessIfRequested(_ app: XCUIApplication) throws {
        guard ProcessInfo.processInfo.environment["MORE_PHYSICAL_DEVELOPER_ACCESS"] == "1" else { return }
        if !hasOrdinaryAccess(app) {
            let intro = app.buttons["onboarding.developerAccess"]
            let paywall = app.buttons["paywall.developerAccess"]
            _ = intro.waitForExistence(timeout: 10)
            let entry = intro.exists ? intro : paywall
            XCTAssertTrue(entry.exists && entry.isHittable,
                          "The product's explicit Debug developer entry is unavailable.")
            entry.tap()
            let note = XCTAttachment(string: "Official Debug developer entry selected through the ordinary UI. No StoreKit entitlement was asserted.")
            note.name = "ordinary-debug-access-route"
            note.lifetime = .keepAlways
            add(note)
        }
        // Defer optional setup prompts; each real service permission is checked separately.
        for _ in 0..<12 {
            let skip = app.buttons["permissions.skip"]
            let finish = app.buttons["permissions.finish"]
            if skip.exists && skip.isHittable { skip.tap() }
            else if finish.exists && finish.isHittable { finish.tap() }
            else if app.buttons["morning.actions"].waitForExistence(timeout: 2), app.buttons["morning.actions"].isHittable { return }
        }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
    }

    private func openConnections(_ app: XCUIApplication) throws {
        let landscape = app.buttons["morning.actions"]
        guard landscape.waitForExistence(timeout: 8) else {
            throw XCTSkip("Ordinary access/setup is incomplete. No fixture or system permission was injected.")
        }
        let settings = app.buttons["morning.settings"]
        for _ in 0..<3 {
            if settings.exists && settings.isHittable { break }
            // Controls auto-hide; observe each attempt before tapping the landscape again.
            landscape.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
            if settings.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(settings.exists && settings.isHittable, "The ordinary Home controls did not expose Settings.")
        settings.tap()
        let connections = app.buttons["setup.connections"]
        for _ in 0..<3 {
            if app.buttons["connections.instagram"].exists { break }
            guard connections.exists else { break }
            try reveal(connections, in: app)
            connections.tap()
            if app.buttons["connections.instagram"].waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(app.buttons["connections.instagram"].waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        for direction in [true, false] {
            for _ in 0..<14 {
                if element.exists && element.isHittable { return }
                let list = app.collectionViews.firstMatch
                let container = list.exists ? list : app.scrollViews.firstMatch
                if direction { container.swipeUp() } else { container.swipeDown() }
            }
        }
        XCTFail("The ordinary destination was not reachable.")
    }
}
