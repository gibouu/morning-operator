import MorningCore
import SwiftUI

/// One visible sign-in queue, using the same WebKit store as the morning. Readiness
/// is the person's confirmation, never a claim inferred from a cookie or URL.
struct MorningConnectionsView: View {
    @Bindable var store: MorningStore
    @State private var selected: Set<WebMorningSite> = []
    @State private var ready: Set<WebMorningSite> = []
    @State private var queue: [WebMorningSite] = []
    @State private var currentSite: WebMorningSite?
    @State private var learningSite: WebMorningSite?
    @State private var hasLoadedSelection = false
    @Environment(\.locale) private var locale

    private var routineSites: [WebMorningSite] {
        var seen = Set<WebMorningSite>()
        return (store.routine?.steps ?? []).compactMap { step in
            let site: WebMorningSite?
            switch step.target {
            case let .inAppWeb(url): site = WebMorningSite(url: url)
            case .externalApp(.instagram, _): site = .instagram
            case .externalApp(.whatsapp, _): site = .whatsapp
            default: site = nil
            }
            guard let site, seen.insert(site).inserted else { return nil }
            return site
        }
    }
    private var nativeApps: [StepApp] {
        var seen = Set<StepApp>()
        return (store.routine?.steps ?? []).compactMap { step in
            guard case let .externalApp(app, _) = step.target, seen.insert(app).inserted else { return nil }
            return app
        }
    }
    private var selectedSites: [WebMorningSite] {
        WebMorningSite.allCases.filter { selected.contains($0) }
    }

    var body: some View {
        Group {
            if let site = learningSite {
                WebMorningView(site: site, minutes: 1, isStepActive: false, learningOnly: true,
                    onSaveRhythm: { store.saveBrowserRhythmObservation($0) },
                    onClose: { learningSite = nil })
                    .id("learn.\(site.rawValue)")
            } else if let site = currentSite {
                VStack(spacing: 0) {
                    Text(text("\(ready.intersection(selected).count + 1) of \(selected.count)",
                              "\(ready.intersection(selected).count + 1) sur \(selected.count)"))
                        .font(.caption.monospacedDigit()).foregroundStyle(MorningStyle.muted)
                        .padding(.top, 8)
                    WebMorningView(site: site, minutes: 1, isStepActive: false,
                                   onSignInReady: { markReady(site) }, onClose: { currentSite = nil; queue = [] })
                        .id(site)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PageHeading(eyebrow: text("Before your first morning", "Avant le premier matin"),
                                    title: text("A little setup. Then you're home.", "Un instant de préparation. Puis à vous de jouer."),
                                    subtitle: text("Sign in once, here. Your morning uses these same pages.",
                                                   "Connectez-vous ici une fois. Votre matin utilisera ces mêmes pages."))
                        VStack(spacing: 0) {
                            ForEach(WebMorningSite.allCases) { site in siteRow(site) }
                        }
                        Button {
                            queue = selectedSites.filter { !ready.contains($0) }
                            currentSite = queue.first
                        } label: {
                            Text(ready.isSuperset(of: selected) && !selected.isEmpty
                                 ? text("All set for now", "Tout est prêt")
                                 : text("Connect my websites", "Connecter mes sites"))
                        }.buttonStyle(PrimaryButtonStyle())
                            .disabled(selected.isEmpty || ready.isSuperset(of: selected) || store.privacyBlocksWork)
                            .accessibilityIdentifier("connections.begin")
                        if !ready.isEmpty {
                            Text(text("Marked ready by you. Sites may ask you to sign in again.",
                                      "Vous les avez indiqués prêts. Un site peut redemander une connexion."))
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                            ForEach(WebMorningSite.allCases.filter { ready.contains($0) }) { site in
                                Button {
                                    learningSite = site
                                } label: {
                                    Label { Text(text("Learn my pace in \(site.displayName)", "Apprendre mon rythme sur \(site.displayName)")) } icon: {
                                        MorningDottedIcon(systemName: "record.circle").frame(width: 20, height: 20)
                                    }
                                }.buttonStyle(SecondaryButtonStyle()).disabled(store.sessionActive || store.privacyBlocksWork)
                            }
                        }
                        if !nativeApps.isEmpty {
                            DisclosureGroup(text("Your other apps", "Vos autres apps")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(nativeApps.map(\.displayName).joined(separator: ", "))
                                    Text(text("Sign in inside each app. Their sign-ins are separate from MORE’s browser.",
                                              "Connectez-vous dans chaque app. Leurs connexions restent distinctes du navigateur de MORE."))
                                }.font(.footnote).foregroundStyle(MorningStyle.muted).padding(.top, 10)
                            }.tint(MorningStyle.accent)
                        }
                        Text(text("MORE never reads your password. Choose “I'm ready” after signing in, or close a page to leave it for later.",
                                  "MORE ne lit jamais votre mot de passe. Après connexion, choisissez « C’est prêt », ou fermez la page pour plus tard."))
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                    }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundStyle(MorningStyle.ink)
        .background(MorningPaper(showsSun: false))
        .navigationTitle(text("Your websites", "Vos sites"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasLoadedSelection else { return }
            hasLoadedSelection = true
            selected = Set(routineSites)
        }
        .onChange(of: store.dataGeneration) { _, _ in
            currentSite = nil; learningSite = nil; queue = []; selected = []; ready = []
        }
    }

    private func siteRow(_ site: WebMorningSite) -> some View {
        Button {
            if selected.contains(site) { selected.remove(site) }
            else { selected.insert(site) }
        } label: {
            HStack(spacing: 16) {
                MorningDottedIcon(systemName: ready.contains(site) ? "checkmark" : selected.contains(site) ? "circle.fill" : "circle")
                    .frame(width: 25, height: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(site.displayName).font(MorningTheme.Typography.heading)
                    if routineSites.contains(site) {
                        Text(text("In your routine", "Dans votre routine")).font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                }
                Spacer()
                if ready.contains(site) { Text(text("Ready", "Prêt")).font(.caption).foregroundStyle(MorningStyle.muted) }
            }.padding(.vertical, 16).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(site) ? .isSelected : [])
            .accessibilityIdentifier("connections.\(site.rawValue)")
            .overlay(alignment: .bottom) {
                MorningDottedFrame(cornerRadius: 0, spacing: 9).fill(MorningStyle.line).frame(height: 3)
            }
    }

    private func markReady(_ site: WebMorningSite) {
        guard !store.privacyBlocksWork, currentSite == site else { return }
        ready.insert(site)
        queue.removeAll { $0 == site }
        currentSite = queue.first
    }
    private func text(_ english: String, _ french: String) -> String {
        locale.language.languageCode?.identifier == "fr" ? french : english
    }
}
