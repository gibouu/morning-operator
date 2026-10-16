import Foundation
import MorningCore
import Observation
import StoreKit
import UIKit

/// StoreKit is the only source of subscription rights, including the free trial.
/// Ordinary app entry is independent of this entitlement state.
@MainActor @Observable
final class MorningSubscriptionStore {
    private(set) var offer: MorningSubscriptionOffer?
    private(set) var state: MorningPurchasePresentation = .loading
    private(set) var hasAccess = false
    private(set) var hasResolvedAccess = false

    @ObservationIgnored private let productID: String
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var foreground: Task<Void, Never>?
    @ObservationIgnored private var expiration: Task<Void, Never>?

    init(productID: String = MorningSubscriptionStore.configuredProductID) {
        self.productID = productID
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.receive(result)
            }
        }
        foreground = Task { [weak self] in
            let activations = NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification)
                .map { _ in true }
            for await _ in activations {
                guard !Task.isCancelled else { return }
                await self?.refreshAccess()
            }
        }
    }

    deinit {
        updates?.cancel()
        foreground?.cancel()
        expiration?.cancel()
    }

    func load() async {
        guard !isBusy else { return }
        let wasPending = state == .pending
        isBusy = true
        state = .loading
        defer { isBusy = false }
        await refreshAccess()
        do {
            guard let (_, loadedOffer) = try await loadProduct() else {
                if !wasPending { offer = nil }
                state = wasPending && !hasAccess ? .pending : .unavailable
                return
            }
            offer = loadedOffer
            state = wasPending && !hasAccess ? .pending : .ready
        } catch {
            if !wasPending { offer = nil }
            state = wasPending && !hasAccess ? .pending : .failed(text("The subscription could not be loaded. Please try again.", "L’abonnement n’a pas pu être chargé. Réessayez dans un instant."))
        }
    }

    func purchase() async {
        guard !isBusy, state != .pending, let presentedOffer = offer, !hasAccess else { return }
        isBusy = true
        state = .purchasing
        defer { isBusy = false }
        do {
            guard let (product, currentOffer) = try await loadProduct() else {
                offer = nil
                state = .unavailable
                return
            }
            offer = currentOffer
            guard !hasAccess else { state = .ready; return }
            // A changed price or trial needs a fresh tap after the terms update.
            guard presentedOffer.monthlyPrice == currentOffer.monthlyPrice,
                  presentedOffer.includesFreeTrial == currentOffer.includesFreeTrial else {
                state = .failed(text("Your offer has changed. Review the updated terms, then continue.", "Votre offre a changé. Vérifiez les nouvelles conditions, puis continuez."))
                return
            }
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result,
                      isActive(transaction) else {
                    state = .failed(verificationMessage)
                    return
                }
                await transaction.finish()
                await refreshAccess()
                state = hasAccess ? .ready : .failed(verificationMessage)
            case .pending:
                state = .pending
            case .userCancelled:
                state = .ready
            @unknown default:
                await refreshAccess()
                state = hasAccess ? .ready : .failed(purchaseMessage)
            }
        } catch StoreKitError.userCancelled {
            state = .ready
        } catch {
            await refreshAccess()
            state = hasAccess ? .ready : .failed(purchaseMessage)
        }
    }

    /// Ask to Buy declines have no transaction callback; recovery needs a new tap.
    func retryPendingPurchase() async {
        guard !isBusy, state == .pending else { return }
        isBusy = true
        state = .purchasing
        await refreshAccess()
        isBusy = false
        state = .ready
        guard !hasAccess else { return }
        await purchase()
    }

    func restore() async {
        guard !isBusy else { return }
        let wasPending = state == .pending
        isBusy = true
        state = .restoring
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshAccess()
            state = hasAccess ? .ready : wasPending ? .pending : .failed(text(
                "No active MORE subscription was found for this Apple Account.",
                "Aucun abonnement MORE actif n’a été trouvé pour ce compte Apple."
            ))
        } catch StoreKitError.userCancelled {
            state = wasPending ? .pending : offer == nil ? .unavailable : .ready
        } catch {
            state = wasPending ? .pending : .failed(text("Purchases could not be restored. Please try again.", "Les achats n’ont pas pu être restaurés. Réessayez dans un instant."))
        }
    }

    private func loadProduct() async throws -> (Product, MorningSubscriptionOffer)? {
        guard let product = try await Product.products(for: [productID]).first(where: { $0.id == productID }),
              product.type == .autoRenewable,
              let subscription = product.subscription,
              subscription.subscriptionPeriod.unit == .month,
              subscription.subscriptionPeriod.value == 1 else { return nil }
        let trial = subscription.introductoryOffer
        let hasWeekTrial = trial?.paymentMode == .freeTrial
            && trial?.periodCount == 1
            && ((trial?.period.unit == .week && trial?.period.value == 1)
                || (trial?.period.unit == .day && trial?.period.value == 7))
        let isEligible = hasWeekTrial ? await subscription.isEligibleForIntroOffer : false
        return (product, MorningSubscriptionOffer(monthlyPrice: product.displayPrice, includesFreeTrial: isEligible))
    }

    @discardableResult
    private func refreshAccess() async -> Bool {
        let token = UUID()
        refreshID = token
        var expiresAt: Date?
        var graceTransactions: [Transaction] = []
        for await result in Transaction.currentEntitlements(for: productID) {
            guard case .verified(let transaction) = result, isMatching(transaction),
                  let date = transaction.expirationDate else { continue }
            if date > Date() { expiresAt = max(expiresAt ?? date, date) }
            else { graceTransactions.append(transaction) }
        }
        for transaction in graceTransactions {
            guard let groupID = transaction.subscriptionGroupID,
                  let statuses = try? await Product.SubscriptionInfo.status(for: groupID) else { continue }
            for status in statuses where status.state == .inGracePeriod {
                guard case .verified(let current) = status.transaction,
                      current.id == transaction.id, isMatching(current),
                      case .verified(let renewal) = status.renewalInfo,
                      let date = renewal.gracePeriodExpirationDate, date > Date() else { continue }
                expiresAt = max(expiresAt ?? date, date)
            }
        }
        guard refreshID == token else { return hasAccess }
        expiration?.cancel()
        hasAccess = expiresAt.map { $0 > Date() } ?? false
        hasResolvedAccess = true
        if let expiresAt, hasAccess {
            expiration = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow))) }
                catch { return }
                await self?.refreshAccess()
            }
        }
        return hasAccess
    }

    private func receive(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == productID else { return }
            await transaction.finish()
            await refreshAccess()
            if !isBusy { state = offer == nil ? .unavailable : .ready }
        case .unverified(let transaction, _):
            guard transaction.productID == productID else { return }
            await refreshAccess()
            if !isBusy { state = .failed(verificationMessage) }
        }
    }

    private func isActive(_ transaction: Transaction) -> Bool {
        isMatching(transaction)
            && (transaction.expirationDate.map { $0 > Date() } ?? false)
    }

    private func isMatching(_ transaction: Transaction) -> Bool {
        transaction.productID == productID
            && transaction.productType == .autoRenewable
            && transaction.revocationDate == nil
            && !transaction.isUpgraded
    }

    private static var configuredProductID: String {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "MORESubscriptionProductID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.flatMap { $0.isEmpty ? nil : $0 } ?? "com.gibouu.more.monthly"
    }

    private var verificationMessage: String {
        text("Your subscription could not be verified. Restore purchases or try again.", "Votre abonnement n’a pas pu être vérifié. Restaurez vos achats ou réessayez.")
    }

    private var purchaseMessage: String {
        text("The purchase could not be completed. Please try again.", "L’achat n’a pas pu être finalisé. Réessayez dans un instant.")
    }

    private func text(_ english: String, _ french: String) -> String {
        AppLanguage.isFrench ? french : english
    }
}
