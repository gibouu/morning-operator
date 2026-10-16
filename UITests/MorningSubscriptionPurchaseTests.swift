import StoreKit
import StoreKitTest
import XCTest

/// Real StoreKit 2 calls against a local Xcode store, with no App Store payment.
@MainActor
final class MorningSubscriptionPurchaseTests: XCTestCase {
    private let productID = "com.gibouu.more.monthly"

    func testNoPurchaseAndEmptyRestoreKeepThePaywallClosedToHome() throws {
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

    func testRefundRevokesAccessWhileTheAppIsOpen() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        try session.refundTransaction(identifier: UInt(transaction.id))
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
    }

    func testExpirationRemovesAccessOnForegroundRefresh() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        XCUIDevice.shared.press(.home)
        try session.expireSubscription(productIdentifier: productID)
        app.activate()
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
    }

    func testUnverifiedSubscriptionDoesNotUnlockHome() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
    }

    func testCancelledPurchaseLeavesTheOfferReadyWithoutAnError() async throws {
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

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-real-subscription", "--ui-testing-empty-workspace",
            "--ui-testing-workspace=\(UUID().uuidString)", "--theme-phase=day", "--ui-testing-reduce-motion",
            "-more.appLanguage", "fr",
            "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"
        ]
        app.launch()
        return app
    }

    private func showPaywall(in app: XCUIApplication) {
        for _ in 0..<3 { tap("onboarding.next", in: app) }
        XCTAssertTrue(app.staticTexts["paywall.price"].waitForExistence(timeout: 20), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["paywall.subscribe"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription)
        button.tap()
    }
}
