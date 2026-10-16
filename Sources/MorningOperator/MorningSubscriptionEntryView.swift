import SwiftUI
import MorningCore

/// Keep setup and its permission requests outside the unpaid presentation tree.
struct MorningSubscriptionEntryView: View {
    @Bindable var store: MorningStore
    @State private var subscription = MorningSubscriptionStore()
    @State private var legalDocument: MorningSubscriptionLegalDocument?
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @AppStorage(MorningDeveloperAccess.preferenceKey) private var developerAccess = false
    #endif

    private var hasDeveloperAccess: Bool {
        #if DEBUG
        return developerAccess
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if hasDeveloperAccess || subscription.hasAccess {
                MorningRootView(store: store)
            } else if !subscription.hasResolvedAccess {
                ZStack {
                    MorningQuietLandscape(scene: MorningThemeClock.shared.celestial, animated: false)
                        .ignoresSafeArea()
                    ProgressView().accessibilityLabel(AppLanguage.isFrench ? "Vérification de l’abonnement" : "Checking your subscription")
                }
            } else {
                welcomeFlow
            }
        }
        .sheet(item: $legalDocument) { document in
            MorningSubscriptionLegalSheet(document: document, store: store)
        }
        .task { await loadSubscription() }
        .onChange(of: store.privacyBlocksWork ? nil : store.briefing.currentWeatherLocation, initial: true) { _, location in
            MorningThemeClock.shared.setLocation(location)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                MorningThemeClock.shared.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        #if DEBUG
        .task(id: scenePhase) {
            guard scenePhase == .active, MorningThemeClock.shared.isRecordingSolarDay else { return }
            while !Task.isCancelled {
                guard MorningThemeClock.shared.refreshRecordingFrame() else { return }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if store.briefing.settings.includesHealth { store.speech.stop() }
                store.briefing.invalidateHealthForForeground()
            }
            if phase == .active {
                MorningThemeClock.shared.refresh()
                Task { await loadSubscription() }
            }
        }
        .onChange(of: subscription.hasAccess) { wasActive, isActive in
            guard wasActive && !isActive && !hasDeveloperAccess else { return }
            store.briefing.cancelAndClear()
            if store.session?.status == .running { store.pause() }
            store.speech.stop()
            store.suspendHandsFreeVoice()
        }
    }

    private var welcomeFlow: MorningWelcomeFlow {
        let flow = MorningWelcomeFlow(offer: subscription.offer, purchaseState: subscription.state,
                                      subscribe: { Task { await subscription.purchase() } },
                                      restore: { Task { await subscription.restore() } },
                                      retry: {
                                          Task {
                                              if subscription.state == .pending { await subscription.retryPendingPurchase() }
                                              else { await subscription.load() }
                                          }
                                      },
                                      showLegal: { legalDocument = $0 })
        #if DEBUG
        var developerFlow = flow
        developerFlow.developerAccess = { developerAccess = true }
        return developerFlow
        #else
        return flow
        #endif
    }

    private func loadSubscription() async {
        guard !hasDeveloperAccess else { return }
        await subscription.load()
    }
}

#if DEBUG
private enum MorningDeveloperAccess {
    static var preferenceKey: String {
        let key = "more.developerAccess.onboardingSkipped"
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return key }
        return key + "." + LocalDataControl.defaultDirectory.lastPathComponent
    }
}
#endif

/// Readable before subscribing; local privacy controls never depend on payment.
struct MorningSubscriptionLegalSheet: View {
    let document: MorningSubscriptionLegalDocument
    var store: MorningStore? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingData = false
    @State private var exportSnapshot: RoutineVersion?
    private var french: Bool { AppLanguage.isFrench }
    private func text(_ fr: String, _ en: String) -> String { french ? fr : en }
    private var night: Bool { MorningThemeClock.shared.celestial.moon.opacity > 0.57 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(document == .terms ? text("Votre abonnement", "Your subscription") : text("Vos données, vos choix.", "Your data, your choices."))
                        .font(MorningTheme.Typography.display).accessibilityAddTraits(.isHeader)
                    if document == .terms {
                        Text(text("L’offre affichée avant l’achat indique le prix, la durée et l’essai auquel votre compte est éligible. L’App Store confirme ces conditions avant toute souscription.",
                                  "The offer shown before purchase includes the price, duration and trial your account is eligible for. The App Store confirms these terms before you subscribe."))
                        Text(text("Vous pouvez gérer ou résilier votre abonnement dans les réglages de votre compte App Store. La résiliation prend effet à la fin de la période en cours.",
                                  "Manage or cancel your subscription in your App Store account settings. Cancellation takes effect at the end of the current period."))
                        Link(text("Lire les conditions d’utilisation Apple", "Read Apple’s terms of use"),
                             destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    } else {
                        Text(text("Vous choisissez les sources à partager avec MORE. Les autorisations et les connexions seront expliquées une par une, après l’abonnement.",
                                  "You choose which sources to share with MORE. Permissions and connections will be explained one by one after subscribing."))
                        Text(text("L’analyse des vidéos et les apprentissages restent sur cet iPhone par défaut. Les services que vous connectez peuvent traiter les informations nécessaires à leurs fonctions, selon leurs propres conditions.",
                                  "Video analysis and learning stay on this iPhone by default. Services you connect may process the information needed for their features under their own terms."))
                        Text(text("Les achats sont gérés par Apple. MORE n’a pas accès aux coordonnées de votre carte bancaire.",
                                  "Apple manages purchases. MORE does not have access to your payment card details."))
                        if store != nil {
                            Button(text("Gérer mes données sur cet iPhone", "Manage my data on this iPhone")) { showingData = true }
                                .frame(minHeight: 44).accessibilityIdentifier("paywall.manageData")
                        }
                        if let store, let routine = store.routine {
                            Button(text("Exporter ma routine", "Export my routine")) { exportSnapshot = routine }
                                .frame(minHeight: 44).disabled(store.privacyBlocksWork)
                                .accessibilityIdentifier("paywall.exportData")
                        }
                    }
                }
                .font(MorningTheme.Typography.body).lineSpacing(5)
                .frame(maxWidth: 520, alignment: .leading).padding(28).frame(maxWidth: .infinity)
            }
            .background(MorningStyle.background.ignoresSafeArea())
            .foregroundStyle(MorningStyle.ink).tint(MorningStyle.ink)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(text("Fermer", "Close")) { dismiss() }.font(.system(.body, weight: .semibold))
                }
            }
            .navigationDestination(isPresented: $showingData) {
                if let store {
                    MorningPrivacyView(store: store)
                        .preferredColorScheme(night ? .dark : .light).foregroundStyle(MorningStyle.ink)
                }
            }
        }
        .preferredColorScheme(night ? .dark : .light)
        .sheet(item: $exportSnapshot) { RoutineExportView(routine: $0) }
    }
}

#if DEBUG
/// An explicit preview can never buy a product or unlock the permission flow.
struct MorningWelcomePreview: View {
    @State private var state: MorningPurchasePresentation = ProcessInfo.processInfo.arguments.contains("--preview-onboarding-unavailable")
        ? .unavailable : ProcessInfo.processInfo.arguments.contains("--preview-onboarding-pending") ? .pending : .ready
    @State private var legalDocument: MorningSubscriptionLegalDocument?
    private var french: Bool { AppLanguage.isFrench }
    private var offer: MorningSubscriptionOffer? {
        guard !ProcessInfo.processInfo.arguments.contains("--preview-onboarding-unavailable") else { return nil }
        return .init(monthlyPrice: french ? "4,99 €" : "€4.99",
                     includesFreeTrial: !ProcessInfo.processInfo.arguments.contains("--preview-onboarding-no-trial"))
    }
    var body: some View {
        MorningWelcomeFlow(offer: offer,
                           purchaseState: state,
                           subscribe: { state = .failed(french ? "Aperçu : aucun achat effectué. Vous pouvez réessayer."
                                                       : "Preview: no purchase made. You can try again.") },
                           restore: { state = .failed(french ? "Aperçu : aucun abonnement à restaurer."
                                                     : "Preview: no subscription to restore.") },
                           retry: { state = .ready }, showLegal: { legalDocument = $0 })
            .sheet(item: $legalDocument) { MorningSubscriptionLegalSheet(document: $0) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.preview")
    }
}
#endif
