import StoreKit
import StoreKitTest
import XCTest

/// Real StoreKit 2 calls against a local Xcode store, with no App Store payment.
@MainActor
final class MorningSubscriptionPurchaseTests: XCTestCase {
    private let productID = "com.gibouu.more.monthly"
    nonisolated(unsafe) private var sessionForCleanup: SKTestSession?

    override func tearDown() {
        let app = XCUIApplication()
        if app.state != .notRunning { app.terminate() }
        if let sessionForCleanup {
            attachTransactions(sessionForCleanup, name: "local-store-before-cleanup")
        }
        sessionForCleanup?.clearTransactions()
        sessionForCleanup?.resetToDefaultState()
        sessionForCleanup = nil
        super.tearDown()
    }

    /// Run against the ordinary Release executable with a clean simulator app
    /// container. The test runner's opt-in never reaches the application.
    func testOrdinaryReleaseFreeEntryAndOnboardingPersist() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_RUN_RELEASE_ENTRY_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Opt in with an ordinary Release target app and a clean simulator install.")
        }
        continueAfterFailure = false
        let french = environment["MO_RELEASE_ENTRY_LANGUAGE"] == "fr"
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", french ? "(fr)" : "(en)",
                               "-AppleLocale", french ? "fr_FR" : "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["entry.continueFree"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["onboarding.developerAccess"].exists)
        XCTAssertFalse(app.staticTexts["qa.testWorkspace"].exists)
        if environment["MO_RELEASE_ENTRY_OFFER"] == "1" { showOffer(in: app) }
        continueFree(in: app, french: french)
        let overview = app.staticTexts["permissions.title.summary"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons["permissions.allow"].label, french ? "Accepter" : "Accept")
        XCTAssertEqual(app.alerts.count, 0)
        tap("permissions.skip", in: app)
        tap("routinePreparation.later", in: app)
        assertHome(app)
        app.terminate()
        app.launch()
        assertHome(app)
        XCTAssertFalse(overview.exists, "A saved setup choice must not repeat after free entry.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ordinary-release-free-entry-\(french ? "fr" : "en")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Each native case has one language and route so cold launches do not
    // exhaust the per-test time budget before a result can be recorded.
    func testEnglishIntroductionFreeEntryPersistsWithinItsWorkspace() {
        verifyFreeEntry(french: false, paywall: false)
        let separateWorkspace = launch(french: false)
        XCTAssertTrue(separateWorkspace.buttons["entry.continueFree"].waitForExistence(timeout: 15),
                      "A saved entry choice must stay within its test workspace.")
        XCTAssertFalse(separateWorkspace.buttons["morning.actions"].exists)
        separateWorkspace.terminate()
    }

    func testEnglishOfferFreeEntryPersists() { verifyFreeEntry(french: false, paywall: true) }
    func testFrenchIntroductionFreeEntryPersistsAtLargestText() { verifyFreeEntry(french: true, paywall: false) }
    func testFrenchOfferFreeEntryPersistsAtLargestText() { verifyFreeEntry(french: true, paywall: true) }
    func testEnglishOptionalAccessAndRoutineSetupPersistsAfterFreeEntry() { verifyOptionalSetup(french: false) }
    func testFrenchOptionalAccessAndRoutineSetupPersistsAfterFreeEntry() { verifyOptionalSetup(french: true) }
    func testEnglishFreeUserCanReopenMembershipAndReturnToSettings() { verifyMembership(french: false) }
    func testFrenchFreeUserCanReopenMembershipAndReturnToSettings() { verifyMembership(french: true) }

    private func verifyFreeEntry(french: Bool, paywall: Bool) {
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

    private func verifyOptionalSetup(french: Bool) {
        let app = launch(french: french, extra: ["--ui-testing-permissions"])
        continueFree(in: app, french: french)
        let overview = app.staticTexts["permissions.title.summary"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons["permissions.allow"].label, french ? "Accepter" : "Accept")
        XCTAssertTrue(app.staticTexts["permissions.title.calendar"].exists)
        XCTAssertTrue(app.staticTexts["permissions.title.speech"].exists)
        XCTAssertEqual(app.alerts.count, 0)
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

    private func verifyMembership(french: Bool) {
        let app = launch(french: french)
        continueFree(in: app, french: french)
        assertHome(app)
        tap("morning.actions", in: app)
        tap("morning.settings", in: app)
        tap("setup.membership", in: app)
        XCTAssertTrue(app.buttons["paywall.subscribe"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        continueFree(in: app, french: french)
        XCTAssertTrue(app.buttons["paywall.subscribe"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["setup.membership"].waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
    }

    func testEmptyRestoreStillAllowsFreeEntryWithoutCreatingATransaction() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        XCTAssertTrue(app.staticTexts["paywall.price"].label.contains("4,99"))
        XCTAssertTrue(app.staticTexts["paywall.price"].label.contains("€"))
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
        // Cancel the accepted local store's sheet, as a user does. An injected
        // generic error does not exercise Product.PurchaseResult.userCancelled.
        session.disableDialogs = false
        let app = launch(french: false)
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancellations = [app.buttons["Cancel"], app.buttons["Annuler"],
                             springboard.buttons["Cancel"], springboard.buttons["Annuler"]]
        let sheet = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            cancellations.contains { $0.exists && $0.isHittable }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [sheet], timeout: 20), .completed,
                       "The local purchase must expose a cancel action: \(app.debugDescription)")
        let cancel = try XCTUnwrap(cancellations.first { $0.exists && $0.isHittable })
        cancel.tap()
        let button = app.buttons["paywall.subscribe"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        XCTAssertTrue(app.staticTexts["paywall.notice"].waitForNonExistence(timeout: 5), app.debugDescription)
        let beforeFreeEntry = session.allTransactions()
        XCTAssertFalse(beforeFreeEntry.contains { $0.state == .purchased || $0.state == .restored })
        let transactionIDs = Set(beforeFreeEntry.map(\.identifier))
        continueFree(in: app, french: false)
        assertHome(app)
        let afterFreeEntry = session.allTransactions()
        XCTAssertFalse(afterFreeEntry.contains { $0.state == .purchased || $0.state == .restored })
        XCTAssertEqual(Set(afterFreeEntry.map(\.identifier)), transactionIDs)
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
        let beforeFreeEntry = session.allTransactions()
        XCTAssertFalse(beforeFreeEntry.contains { $0.state == .purchased || $0.state == .restored })
        let transactionIDs = Set(beforeFreeEntry.map(\.identifier))
        continueFree(in: app)
        assertHome(app)
        let afterFreeEntry = session.allTransactions()
        XCTAssertFalse(afterFreeEntry.contains { $0.state == .purchased || $0.state == .restored })
        XCTAssertEqual(Set(afterFreeEntry.map(\.identifier)), transactionIDs,
                       "Free entry must not add or replace a StoreKit transaction.")
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
        attachTransactions(session, name: "ask-to-buy-after-decline")
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

    nonisolated private func attachTransactions(_ session: SKTestSession, name: String) {
        let details = session.allTransactions().map {
            "id=\($0.identifier) state=\($0.state.rawValue) pending=\($0.pendingAskToBuyConfirmation) expires=\(String(describing: $0.expirationDate))"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: details.isEmpty ? "No local transactions." : details)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeSession() throws -> SKTestSession {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion == 26 && version.minorVersion == 5 {
            throw XCTSkip("iOS 26.5 Simulator cannot connect SKTestSession to its local store (Apple FB22237318 / FB22500243). Run MORESubscriptions on iOS 26.6 or later; native purchases remain unverified here.")
        }
        #endif
        // On a fresh CLI simulator, XCTest installs the target lazily at its
        // first launch. StoreKit needs its registered bundle before loading a
        // test configuration. This launch never starts a purchase or restore.
        let registration = launch()
        registration.terminate()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MORE", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        sessionForCleanup = session
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
        let actions = app.buttons["morning.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 15), app.debugDescription)
        let usable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: actions)
        XCTAssertEqual(XCTWaiter.wait(for: [usable], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
        XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
        XCTAssertFalse(app.buttons["routinePreparation.later"].exists)
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
        let collection = app.collectionViews.firstMatch
        // Form rows become accessible only when the collection reveals them.
        if collection.exists {
            for _ in 0..<10 where !button.exists { collection.swipeUp() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        let scroll = collection.exists ? collection : app.scrollViews.firstMatch
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
