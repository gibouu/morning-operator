import XCTest

/// The preview uses a fixed offer and simulated failures. These journeys never
/// make a purchase, grant a permission, or change the owner's saved routine.
@MainActor
final class MorningWelcomeFlowTests: XCTestCase {
    func testIntroductionSupportsBackSkipAndPurchaseRecoveryWithoutPermissions() {
        let app = launch(french: true)
        let heading = app.staticTexts["onboarding.heading"]
        let firstHeading = heading.label
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding.progress").firstMatch.exists)

        tap("onboarding.next", in: app)
        XCTAssertNotEqual(heading.label, firstHeading)
        tap("onboarding.back", in: app)
        XCTAssertEqual(heading.label, firstHeading)

        var introductions = Set([firstHeading])
        for _ in 0..<2 {
            tap("onboarding.next", in: app)
            introductions.insert(heading.label)
            assertNoPermissionOrHome(in: app)
        }
        XCTAssertEqual(introductions.count, 3, "Each introduction should explain a different part of MORE.")
        tap("onboarding.next", in: app)
        assertOffer(in: app, french: true)

        for (identifier, title) in [("paywall.terms", "Votre abonnement"),
                                    ("paywall.privacy", "Vos données, vos choix.")] {
            tap(identifier, in: app)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), app.debugDescription)
            let close = app.buttons["Fermer"]
            XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
            close.tap()
            assertOffer(in: app, french: true)
        }

        tap("paywall.subscribe", in: app)
        let notice = app.staticTexts["paywall.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(notice.label.isEmpty)
        let purchaseFailure = notice.label
        assertNoPermissionOrHome(in: app)
        XCTAssertTrue(app.buttons["paywall.subscribe"].isEnabled, "A failed purchase must allow another attempt.")
        tap("paywall.subscribe", in: app)
        XCTAssertTrue(notice.exists)
        assertOffer(in: app, french: true)
        assertNoPermissionOrHome(in: app)

        tap("paywall.restore", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(notice.label, purchaseFailure, "Restoring without a purchase needs its own explanation.")
        assertNoPermissionOrHome(in: app)
        attach("onboarding-fr-purchase-recovery", app)
        app.terminate()

        let skipped = launch(french: true)
        for _ in 0..<3 { tap("onboarding.next", in: skipped) }
        assertOffer(in: skipped, french: true)
        assertNoPermissionOrHome(in: skipped)
        skipped.terminate()
    }

    func testNoTrialUnavailableAndPendingOffersStayHonestAndGated() {
        for flag in ["--preview-onboarding-no-trial", "--preview-onboarding-unavailable", "--preview-onboarding-pending"] {
            let app = launch(extra: [flag])
            for _ in 0..<3 { tap("onboarding.next", in: app) }
            let subscribe = app.buttons["paywall.subscribe"]
            XCTAssertTrue(subscribe.waitForExistence(timeout: 5), app.debugDescription)
            switch flag {
            case "--preview-onboarding-no-trial":
                assertOffer(in: app, french: false)
                XCTAssertFalse(subscribe.label.contains("7"), "An ineligible account must not be offered a free trial.")
                XCTAssertTrue(subscribe.isEnabled)
            case "--preview-onboarding-unavailable":
                XCTAssertFalse(app.staticTexts["paywall.price"].exists, "An unavailable product must not display a fabricated price.")
                XCTAssertEqual(subscribe.label, "Try again")
                XCTAssertTrue(subscribe.isEnabled)
                reach(subscribe, in: app)
                reach(app.buttons["paywall.restore"], in: app)
                XCTAssertTrue(app.staticTexts["paywall.notice"].exists)
            default:
                assertOffer(in: app, french: false)
                XCTAssertFalse(subscribe.isEnabled, "A pending purchase keeps the ordinary Subscribe action disabled.")
                let notice = app.staticTexts["paywall.notice"]
                XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertFalse(notice.label.isEmpty)
                attach("onboarding-pending-explicit-recovery", app)
                tap("paywall.retryPending", in: app)
                XCTAssertTrue(subscribe.isEnabled, "A declined request has an explicit recovery action.")
                XCTAssertFalse(notice.exists)
            }
            assertNoPermissionOrHome(in: app)
            attach("onboarding-\(flag.dropFirst(2))", app)
            app.terminate()
        }
    }

    func testIntroductionAndOfferAcrossDayNightAndFrenchEnglish() {
        for phase in ["day", "night"] {
            for french in [false, true] {
                let app = launch(phase: phase, french: french)
                let name = "onboarding-\(phase)-\(french ? "fr" : "en")"
                for page in 1...3 {
                    XCTAssertTrue(app.staticTexts["onboarding.heading"].exists)
                    assertNoPermissionOrHome(in: app)
                    attach("\(name)-intro-\(page)", app)
                    tap("onboarding.next", in: app)
                }
                assertOffer(in: app, french: french)
                for identifier in ["paywall.subscribe", "paywall.restore", "paywall.terms", "paywall.privacy"] {
                    XCTAssertTrue(control(identifier, in: app).exists, "Missing \(identifier): \(app.debugDescription)")
                }
                attach("\(name)-paywall", app)
                assertNoPermissionOrHome(in: app)
                app.terminate()
            }
        }
    }

    func testFirstLaunchUsesThePrimaryLanguageIndependentlyOfRegionAndSecondaryFrench() {
        let cases: [(languages: [String], region: String, french: Bool)] = [
            (["fr", "en"], "en_US", true),
            (["en", "fr"], "fr_FR", false),
            (["es", "fr"], "fr_FR", false),
            (["de", "fr"], "fr_FR", false),
            (["ar", "fr"], "fr_FR", false)
        ]
        for configuration in cases {
            let french = configuration.french
            let app = launch(languages: configuration.languages, localeIdentifier: configuration.region)
            let headings = french
                ? ["Retrouvez\nvotre matin.", "Gardez ce qui\nvous plaît.", "Votre matin,\nles mains libres."]
                : ["Meet your\nmorning.", "Keep what\nyou love.", "Your morning,\nhands free."]
            for (index, title) in headings.enumerated() {
                XCTAssertEqual(app.staticTexts["onboarding.heading"].label, title, app.debugDescription)
                XCTAssertEqual(control("onboarding.progress", in: app).label,
                               french ? "Étape \(index + 1) sur 4" : "Step \(index + 1) of 4")
                XCTAssertEqual(app.buttons["onboarding.next"].label,
                               index == 2 ? (french ? "Découvrir mon offre" : "See my offer") : (french ? "Continuer" : "Continue"))
                assertNoLanguageQuestion(in: app)
                tap("onboarding.next", in: app)
            }
            XCTAssertEqual(app.staticTexts["onboarding.heading"].label,
                           french ? "Un peu plus de\ntemps pour vous." : "A little more\ntime for you.")
            assertOffer(in: app, french: french)
            XCTAssertEqual(app.buttons["paywall.subscribe"].label,
                           french ? "Commencer mes 7 jours gratuits" : "Start my 7 days free")
            XCTAssertEqual(app.buttons["paywall.restore"].label,
                           french ? "Déjà abonné ? Restaurer mes achats" : "Already subscribed? Restore purchases")
            assertNoLanguageQuestion(in: app)
            attach("onboarding-primary-\(configuration.languages[0])-region-\(configuration.region)", app)

            for (identifier, title) in [("paywall.terms", french ? "Votre abonnement" : "Your subscription"),
                                        ("paywall.privacy", french ? "Vos données, vos choix." : "Your data, your choices.")] {
                tap(identifier, in: app)
                XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), app.debugDescription)
                assertNoLanguageQuestion(in: app)
                let close = app.buttons[french ? "Fermer" : "Close"]
                XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
                close.tap()
            }

            tap("paywall.subscribe", in: app)
            let notice = app.staticTexts["paywall.notice"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(notice.label.hasPrefix(french ? "Aperçu :" : "Preview:"), notice.label)
            assertOffer(in: app, french: french)
            tap("paywall.restore", in: app)
            XCTAssertTrue(notice.label.hasPrefix(french ? "Aperçu :" : "Preview:"), notice.label)
            assertNoPermissionOrHome(in: app)
            app.terminate()
        }
    }

    func testFrenchLargestTextKeepsNavigationAndOfferReachableInPortraitAndLandscape() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(phase: "night", french: true, extra: [
            "--ui-testing-reduce-transparency",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        for page in 1...3 {
            XCTAssertTrue(app.staticTexts["onboarding.heading"].exists)
            attach("onboarding-night-fr-largest-intro-\(page)", app)
            tap("onboarding.next", in: app)
        }
        assertOffer(in: app, french: true)
        reach(app.buttons["paywall.subscribe"], in: app)
        attach("onboarding-night-fr-largest-paywall-portrait", app)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.frame
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed, app.debugDescription)
        for identifier in ["paywall.subscribe", "paywall.restore", "paywall.terms", "paywall.privacy"] {
            reach(control(identifier, in: app), in: app)
        }
        attach("onboarding-night-fr-largest-paywall-landscape", app)
        assertNoPermissionOrHome(in: app)
        app.terminate()
    }

    func testExplicitPreviewSkipReturnsToTheSameRealWorkspaceInEnglishAndFrench() {
        for french in [false, true] {
            let app = launch(french: french, extra: ["--ui-testing-real-subscription", "--ui-testing-empty-workspace"])
            let brand = control("onboarding.brand", in: app)
            XCTAssertTrue(brand.exists)
            XCTAssertGreaterThan(brand.frame.midX, app.frame.midX, "Only the M mark belongs in the upper right.")
            XCTAssertEqual(brand.label, "MORE", "The symbol keeps its accessible brand name.")
            for _ in 0..<3 { tap("onboarding.next", in: app) }
            tap("paywall.subscribe", in: app)
            XCTAssertTrue(app.staticTexts["paywall.notice"].waitForExistence(timeout: 5))
            assertNoPermissionOrHome(in: app)
            let skip = app.buttons["onboarding.skipForNow"]
            XCTAssertEqual(skip.label, french ? "Passer pour le moment" : "Skip for now")
            tap("onboarding.skipForNow", in: app)
            XCTAssertTrue(app.buttons["permissions.option.screenTime"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.buttons["permissions.option.calendar"].exists)
            XCTAssertEqual(app.alerts.count, 0, "Opening access choices never grants or requests one automatically.")
            tap("permissions.finish", in: app)
            XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(control("onboarding.preview", in: app).exists)
            XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
            let prefix = "--ui-testing-workspace="
            let workspace = String(app.launchArguments.first { $0.hasPrefix(prefix) }!.dropFirst(prefix.count))
            let marker = app.staticTexts["qa.testWorkspace"]
            XCTAssertEqual((marker.value as? String)?.lowercased(), workspace.lowercased(),
                           "Skipping preview keeps the same workspace and MorningStore.")
            XCTAssertEqual(app.alerts.count, 0, "Debug access is not a system permission grant.")
            app.terminate()
            // Normal entry (without the explicit preview argument) retains Debug
            // access rather than making up a StoreKit entitlement or trial.
            app.launchArguments.removeAll { $0 == "--preview-onboarding" }
            app.launch()
            XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
            app.terminate()
        }
    }

    func testFrenchLargestTextKeepsPreviewSkipReachableWithoutPurchase() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(phase: "night", french: true, extra: [
            "--ui-testing-real-subscription", "--ui-testing-empty-workspace",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        for _ in 0..<3 {
            XCTAssertFalse(app.buttons["onboarding.skipForNow"].exists, "Skip belongs only to the final offer.")
            XCTAssertFalse(app.buttons["onboarding.offer"].exists, "Intro keeps a single Continue action.")
            tap("onboarding.next", in: app)
        }
        let skip = app.buttons["onboarding.skipForNow"]
        reach(skip, in: app)
        XCTAssertEqual(skip.label, "Passer pour le moment")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        reach(skip, in: app)
        XCTAssertGreaterThanOrEqual(skip.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(skip.frame.maxX, app.frame.maxX + 1)
        skip.tap()
        XCTAssertTrue(app.buttons["permissions.option.screenTime"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["permissions.allow"].exists, "Each real access choice remains explicit.")
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate()
    }

    private func launch(phase: String = "day", french: Bool = false, languages: [String]? = nil,
                        localeIdentifier: String? = nil, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        let preferredLanguages = languages ?? [french ? "fr" : "en"]
        // Invalid stored language exercises system resolution without an earlier saved choice.
        app.launchArguments = [
            "--ui-testing", "--preview-onboarding", "--theme-phase=\(phase)",
            "--ui-testing-reduce-motion", "--ui-testing-workspace=\(UUID().uuidString)",
            "-more.appLanguage", languages == nil ? (french ? "fr" : "en") : "unsupported",
            "-AppleLanguages", "(\(preferredLanguages.joined(separator: ", ")))",
            "-AppleLocale", localeIdentifier ?? (french ? "fr_FR" : "en_US")
        ] + extra
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.frame
            return frame.height > frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding.preview").firstMatch
            .waitForExistence(timeout: 10), "This suite requires the nonvisual preview root: \(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["onboarding.preview"].exists, "Preview identification must not create a visible badge.")
        XCTAssertFalse(app.staticTexts["APERÇU · AUCUN ACHAT"].exists)
        XCTAssertFalse(app.staticTexts["PREVIEW · NO PURCHASE"].exists)
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }

    private func assertNoLanguageQuestion(in app: XCUIApplication) {
        XCTAssertEqual(app.pickers.count, 0, "Language should resolve on first launch without asking the person.")
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.secureTextFields.count, 0)
        assertNoPermissionOrHome(in: app)
    }

    private func assertOffer(in app: XCUIApplication, french: Bool) {
        let price = app.staticTexts["paywall.price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(price.label.contains(french ? "4,99" : "4.99"), price.label)
        XCTAssertTrue(app.buttons["paywall.subscribe"].exists)
    }

    private func assertNoPermissionOrHome(in app: XCUIApplication) {
        XCTAssertEqual(app.alerts.count, 0, "The introduction and failed preview purchases must not request access.")
        XCTAssertEqual(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count, 0)
        XCTAssertFalse(app.buttons["morning.actions"].exists, "A failed or absent purchase must keep the paywall visible.")
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
        XCTAssertFalse(app.staticTexts["permissions.title.speech"].exists,
                       "The single voice explanation must stay behind verified subscription access.")
        XCTAssertFalse(app.buttons["permissions.option.speech"].exists,
                       "Optional access choices belong in Settings after the paywall.")
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        reach(button, in: app)
        button.tap()
    }

    private func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reach(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        let scroll = app.scrollViews.firstMatch
        let scrollsTarget = scroll.exists
            && scroll.descendants(matching: .any).matching(identifier: element.identifier).firstMatch.exists
        func viewport() -> CGRect {
            // Ordinary text pins the footer outside the scroll view; accessibility text scrolls it.
            (scrollsTarget ? scroll.frame : app.frame).intersection(app.frame)
        }
        func visibleAndHittable() -> Bool {
            let frame = element.frame
            // XCTest can throw instead of returning false for an offscreen activation point.
            return !frame.isEmpty && viewport().contains(CGPoint(x: frame.midX, y: frame.midY))
                && element.isHittable
        }
        for _ in 0..<10 {
            if visibleAndHittable() { return }
            let bounds = viewport()
            let distance = bounds.midY - element.frame.midY
            let surface: XCUIElement = scrollsTarget ? scroll : app
            if abs(distance) > bounds.height * 2 {
                if distance > 0 { surface.swipeDown() }
                else { surface.swipeUp() }
            } else {
                // A full flick can jump past a control repeatedly in short landscape viewports.
                let step = min(bounds.height * 0.6, max(-bounds.height * 0.6, distance))
                let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: step > 0 ? 0.2 : 0.8))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: step)),
                            withVelocity: .slow, thenHoldForDuration: 0.2)
            }
        }
        XCTAssertTrue(visibleAndHittable(), "The control must remain visible and reachable: \(app.debugDescription)")
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        // XCTest's app crop can stay in portrait after rotation on the iOS 26.5 runtime.
        let screenshot = app.frame.width > app.frame.height ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MO_ONBOARDING_SCREENSHOT_DIR"] {
            do {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"), options: .atomic)
            } catch { XCTFail("Could not save the synthetic onboarding screenshot: \(error)") }
        }
    }
}
