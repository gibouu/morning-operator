import StoreKit
import StoreKitTest
import XCTest

/// Real StoreKit 2 calls against a local Xcode store, with no App Store payment.
@MainActor
final class MorningSubscriptionPurchaseTests: XCTestCase {
    private let productID = "com.gibouu.more.monthly"

    // These entry tests do not need a working StoreKit test service. They exercise
    // the ordinary app entry, including while StoreKit is still loading.
    func testFreeContinueFromIntroductionAndOfferPersistsInEnglishAndFrench() {
        for french in [false, true] {
            for paywall in [false, true] {
                let workspace = UUID()
                let extra = french ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []
                let app = launch(workspace: workspace, french: french, extra: extra)
                if paywall { showOffer(in: app) }
                continueFree(in: app, french: french)
                assertHome(app)
                app.terminate()
                app.launch()
                assertHome(app)
                let marker = app.staticTexts["qa.testWorkspace"]
                XCTAssertEqual((marker.value as? String)?.lowercased(), workspace.uuidString.lowercased())
                app.terminate()
            }
        }
        let separateWorkspace = launch(french: false)
        XCTAssertTrue(separateWorkspace.buttons["entry.continueFree"].waitForExistence(timeout: 15),
                      "A saved entry choice must stay within its test workspace.")
        XCTAssertFalse(separateWorkspace.buttons["morning.actions"].exists)
        separateWorkspace.terminate()
    }

    func testFreeContinueKeepsOptionalAccessOverviewAndRoutineSetupInEnglishAndFrench() {
        for french in [false, true] {
            let app = launch(french: french, extra: ["--ui-testing-permissions"])
            continueFree(in: app, french: french)
            let overview = app.staticTexts["permissions.title.summary"]
            XCTAssertTrue(overview.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(app.buttons["permissions.allow"].label, french ? "Accepter" : "Accept")
            XCTAssertTrue(app.staticTexts["permissions.title.calendar"].exists)
            XCTAssertTrue(app.staticTexts["permissions.title.speech"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            // An interrupted first setup must resume without returning to the offer.
            app.terminate()
            app.launch()
            XCTAssertTrue(overview.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(app.buttons["permissions.allow"].label, french ? "Accepter" : "Accept")
            XCTAssertFalse(app.buttons["entry.continueFree"].exists)
            tap("permissions.skip", in: app)
            let later = app.buttons["routinePreparation.later"]
            XCTAssertTrue(later.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(later.label, french ? "Continuer pour le moment" : "Continue for now")
            tap("routinePreparation.later", in: app)
            assertHome(app)
            app.terminate()
            app.launch()
            assertHome(app)
            XCTAssertFalse(overview.exists, "A saved setup choice must not repeat after free entry.")
            XCTAssertFalse(later.exists)
            app.terminate()
        }
    }

    func testFreeUserCanReopenMembershipAndReturnToSettingsInEnglishAndFrench() {
        for french in [false, true] {
            let app = launch(french: french)
            continueFree(in: app, french: french)
            assertHome(app)
            tap("morning.actions", in: app)
            tap("morning.settings", in: app)
            tap("setup.membership", in: app)
            XCTAssertTrue(app.buttons["paywall.subscribe"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.buttons["paywall.restore"].exists)
            continueFree(in: app, french: french)
            XCTAssertTrue(app.buttons["setup.membership"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
            app.terminate()
        }
    }

    func testEmptyRestoreStillAllowsFreeEntryWithoutCreatingATransaction() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        XCTAssertTrue(app.staticTexts["paywall.price"].label.contains("4,99"))
        XCTAssertTrue(app.staticTexts["paywall.price"].label.contains("€"))
        XCTAssertTrue(app.buttons["paywall.subscribe"].label.contains("7"), "The fixture offers one free week.")
        tap("paywall.restore", in: app)
        XCTAssertTrue(app.staticTexts["paywall.notice"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Restoring must not request routine permissions.")
        continueFree(in: app)
        assertHome(app)
        XCTAssertTrue(session.allTransactions().isEmpty, "Free entry must not create a purchase or trial.")
    }

    func testPurchaseThroughPaywallUnlocksHome() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
        XCTAssertEqual(session.allTransactions().count, 1)
    }

    func testExistingVerifiedSubscriptionOpensHome() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
    }

    func testRefundKeepsAppEntryAcrossRelaunch() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        try session.refundTransaction(identifier: UInt(transaction.id))
        XCTAssertFalse(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 2),
                       "A refund must not interrupt app access.")
        assertHome(app)
        app.terminate()
        app.launch()
        assertHome(app)
    }

    func testExpirationKeepsAppEntryOnForegroundAndRelaunch() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        XCUIDevice.shared.press(.home)
        try session.expireSubscription(productIdentifier: productID)
        app.activate()
        assertHome(app)
        app.terminate()
        app.launch()
        assertHome(app)
    }

    func testUnverifiedSubscriptionRequiresAnEntryChoiceAndAllowsFreeContinue() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        continueFree(in: app)
        assertHome(app)
    }

    func testCancelledPurchaseLeavesTheOfferReadyAndAllowsFreeContinue() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        let button = app.buttons["paywall.subscribe"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND label CONTAINS '7'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        XCTAssertFalse(app.staticTexts["paywall.notice"].exists)
        XCTAssertTrue(session.allTransactions().isEmpty)
        continueFree(in: app)
        assertHome(app)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testFailedPurchaseAllowsFreeContinueWithoutATransaction() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        XCTAssertTrue(app.staticTexts["paywall.notice"].waitForExistence(timeout: 15), app.debugDescription)
        continueFree(in: app)
        assertHome(app)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testProductLoadFailureAllowsFreeContinueWithoutAFabricatedOffer() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.setSimulatedError(.generic(.notAvailableInStorefront), forAPI: .loadProducts)
        let app = launch(french: false)
        defer { app.terminate() }
        showOffer(in: app)
        XCTAssertTrue(app.staticTexts["paywall.notice"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["paywall.price"].exists)
        continueFree(in: app, french: false)
        assertHome(app)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testPendingPurchaseAllowsFreeContinueAndRelaunchWithoutApproval() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        let pending = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == false AND label CONTAINS 'attente'"),
            object: app.buttons["paywall.subscribe"])
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 15), .completed)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        XCTAssertTrue(transaction.pendingAskToBuyConfirmation)
        continueFree(in: app)
        assertHome(app)
        app.terminate()
        app.launch()
        assertHome(app)
        XCTAssertEqual(session.allTransactions().map(\.identifier), [transaction.identifier])
        XCTAssertTrue(try XCTUnwrap(session.allTransactions().first).pendingAskToBuyConfirmation,
                      "Free entry must not approve or replace the pending StoreKit transaction.")
    }

    func testPendingPurchaseSurvivesForegroundUntilStoreKitApprovesIt() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        let button = app.buttons["paywall.subscribe"]
        let pending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false AND label CONTAINS 'attente'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 15), .completed)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["paywall.price"].waitForExistence(timeout: 10))
        let stillPending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false AND label CONTAINS 'attente'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [stillPending], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
    }

    func testDeclinedPendingPurchaseNeedsExplicitRetryBeforeAnotherRequest() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        let button = app.buttons["paywall.subscribe"]
        let pending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false AND label CONTAINS 'attente'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 15), .completed)
        let declined = try XCTUnwrap(session.allTransactions().first)
        try session.declineAskToBuyTransaction(identifier: declined.identifier)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        XCTAssertFalse(button.isEnabled, "A decline must not automatically request another purchase.")
        tap("paywall.retryPending", in: app)
        let newRequest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            session.allTransactions().contains { $0.identifier != declined.identifier }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [newRequest], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        let retryPending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false AND label CONTAINS 'attente'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [retryPending], timeout: 15), .completed)
        let retried = try XCTUnwrap(session.allTransactions().first { $0.identifier != declined.identifier })
        try session.approveAskToBuyTransaction(identifier: retried.identifier)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
    }

    private func makeSession() throws -> SKTestSession {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion == 26 && version.minorVersion == 5 {
            throw XCTSkip("iOS 26.5 Simulator cannot connect SKTestSession to its local store (Apple FB22237318 / FB22500243). Run MORESubscriptions on iOS 26.6 or later; native purchases remain unverified here.")
        }
        #endif
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MORE", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "FRA"
        session.locale = Locale(identifier: "fr_FR")
        session.timeRate = .realTime
        XCTAssertTrue(session.disableDialogs, "The local StoreKit test configuration was not accepted. Do not launch an App Store purchase flow.")
        return session
    }

    private func launch(workspace: UUID = UUID(), french: Bool = true, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-real-subscription", "--ui-testing-empty-workspace",
            "--ui-testing-workspace=\(workspace.uuidString)", "--theme-phase=day", "--ui-testing-reduce-motion",
            "-more.appLanguage", french ? "fr" : "en",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"
        ] + extra
        app.launch()
        return app
    }

    private func showOffer(in app: XCUIApplication) {
        for _ in 0..<3 { tap("onboarding.next", in: app) }
        XCTAssertTrue(app.buttons["paywall.subscribe"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func continueFree(in app: XCUIApplication, french: Bool = true) {
        let button = app.buttons["entry.continueFree"]
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(button.label, french ? "Continuer gratuitement" : "Continue for free")
        XCTAssertTrue(button.isEnabled, "StoreKit state must never disable free entry.")
        tap("entry.continueFree", in: app)
    }

    private func assertHome(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
        XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func showPaywall(in app: XCUIApplication) {
        showOffer(in: app)
        XCTAssertTrue(app.staticTexts["paywall.price"].waitForExistence(timeout: 20), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["paywall.subscribe"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        let scroll = app.scrollViews.firstMatch
        let scrollsButton = scroll.exists
            && scroll.descendants(matching: .button).matching(identifier: identifier).firstMatch.exists
        func visibleAndHittable() -> Bool {
            let frame = button.frame
            let viewport = (scrollsButton ? scroll.frame : app.frame).intersection(app.frame)
            return !frame.isEmpty && viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) && button.isHittable
        }
        for _ in 0..<10 where !visibleAndHittable() {
            if scrollsButton { scroll.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(visibleAndHittable(), app.debugDescription)
        button.tap()
    }
}
