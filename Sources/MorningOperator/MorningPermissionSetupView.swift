import MorningCore
import SwiftUI

struct MorningPermissionSetupView: View {
    @Bindable var store: MorningStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var detailsExpanded = false
    @AccessibilityFocusState private var headingFocused: Bool

    private var setup: MorningPermissionSetup { store.permissionSetup }
    private var clock: MorningThemeClock { .shared }
    private var night: Bool { clock.celestial.moon.opacity > 0.57 }
    private var ink: Color { MorningStyle.ink }
    private var muted: Color { contrast == .increased ? MorningStyle.ink : MorningStyle.muted }
    private var paper: Color { MorningStyle.background }
    private var scrollingFooter: Bool { typeSize.isAccessibilitySize || verticalSizeClass == .compact }
    private func text(_ english: String, _ french: String) -> String { MorningPermissionSetup.text(english, french) }

    var body: some View {
        VStack(spacing: 0) {
            navigation
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if setup.isRevisiting {
                        MorningQuietLandscape(scene: clock.celestial, weather: clock.weatherScene,
                                          animated: false, active: false,
                                          strongInk: reduceTransparency || contrast == .increased)
                        .frame(height: verticalSizeClass == .compact ? 90 : 130)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    if setup.isRevisiting { choice } else { summary }
                    if let issue = setup.saveIssue {
                        Text(issue).font(MorningTheme.Typography.note).foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("permissions.saveIssue")
                    }
                    if scrollingFooter { actions }
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("permissions.content")
            .id(setup.isRevisiting ? setup.current : nil)
            if !scrollingFooter {
                actions.padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(paper.ignoresSafeArea(edges: .bottom))
            }
        }
        .background { MorningEntryBackdrop() }
        .foregroundStyle(ink).font(MorningTheme.Typography.body).tint(ink)
        .preferredColorScheme(night ? .dark : .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permissions.appearance")
        .interactiveDismissDisabled()
        .task { clock.refresh() }
        .onChange(of: setup.current) { _, _ in
            if setup.isRevisiting {
                detailsExpanded = false
                headingFocused = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { setup.cancelForBackground() }
            if phase == .active { clock.refresh() }
        }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(text("Let's prepare your morning.", "Préparons votre matinée."))
                .font(.system(.largeTitle, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("permissions.title.summary")
            Text(text("Here's what each access is for. Do you agree to enable them?",
                      "Voici à quoi sert chaque accès. Acceptez-vous de les activer ?"))
                .foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            ForEach(setup.supported, id: \.rawValue) { permission in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: permission.accessSymbol)
                        .frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(permission == .speech
                             ? text("Microphone & speech recognition", "Micro et reconnaissance vocale")
                             : permission.accessName)
                            .font(.system(.subheadline, weight: .semibold))
                            .accessibilityIdentifier("permissions.title.\(permission.rawValue)")
                        Text(permission.accessBenefit)
                            .font(MorningTheme.Typography.note).foregroundStyle(muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(text("You can decline any request or choose Not now. MORE will continue with the available features. You can change each access later in Settings.",
                      "Vous pouvez refuser un accès ou choisir Plus tard. MORE continuera avec les fonctions disponibles. Chaque accès reste modifiable dans les réglages."))
                .font(MorningTheme.Typography.note).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("permissions.note")
            if let note = setup.screenTimeUnavailableNote {
                Text(note).font(MorningTheme.Typography.note).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(isExpanded: $detailsExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(setup.supported, id: \.rawValue) { permission in
                        Text(permission.accessExplanation)
                    }
                }
                .font(MorningTheme.Typography.note).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            } label: {
                Text(text("Learn more", "En savoir plus"))
                    .font(.system(.subheadline, weight: .medium)).frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("permissions.details")
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 20) {
            HStack(spacing: 7) {
                MorningBrandMark().frame(width: 24, height: 24)
                Text(verbatim: "MORE").font(.system(.subheadline, weight: .semibold)).tracking(1.5)
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).fixedSize()
                .accessibilityElement(children: .ignore).accessibilityLabel("MORE")
            Spacer(minLength: 12)
            if setup.isRevisiting, setup.current != nil {
                Button(text("All access", "Tous les accès")) { setup.showOverview() }
                    .font(.system(.subheadline, weight: .medium)).frame(minHeight: 44)
                    .disabled(setup.isRequesting).accessibilityIdentifier("permissions.back")
            } else {
                Text(text("At your pace", "À votre rythme"))
                    .font(.system(.caption, weight: .medium)).foregroundStyle(muted)
                    .accessibilityIdentifier("permissions.progress")
            }
        }
        .frame(maxWidth: 480, minHeight: 44)
        .padding(.horizontal, 28).padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(setup.current?.accessHeading ?? text("Connect what matters to you.", "Vos accès, à votre rythme."))
                .font(.system(.largeTitle, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .accessibilityIdentifier(setup.current.map { "permissions.title.\($0.rawValue)" } ?? "permissions.title.ready")
            Text(setup.current?.accessBenefit ?? text("Choose a feature when you need it. Each access stays optional.",
                                                                     "Choisissez une fonction quand elle vous est utile. Chaque accès reste facultatif."))
                .foregroundStyle(muted).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("permissions.benefit")
            if setup.current == .speech {
                Text(text("Two iPhone permissions: speech recognition and microphone. Listening stays off during setup.",
                          "Deux autorisations iPhone : reconnaissance vocale et micro. Aucune écoute ne démarre ici."))
                    .font(MorningTheme.Typography.note).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("permissions.voicePrompts")
            }
            if setup.current == nil {
                ForEach(setup.supported, id: \.rawValue) { permission in
                    Button { setup.choose(permission) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: permission.accessSymbol).frame(width: 24)
                            Text(permission.accessName).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(muted)
                        }
                        .font(.system(.body, weight: .medium))
                        .padding(16).frame(minHeight: 56)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("permissions.option.\(permission.rawValue)")
                }
                if let outcome = setup.lastOutcome {
                    Text(outcome).font(MorningTheme.Typography.note).foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("permissions.lastOutcome")
                }
            } else {
                DisclosureGroup(isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let permission = setup.current {
                            Text(permission.accessExplanation).accessibilityIdentifier("permissions.explanation")
                        }
                        if let outcome = setup.lastOutcome {
                            Text(outcome).accessibilityIdentifier("permissions.lastOutcome")
                        }
                    }
                    .font(MorningTheme.Typography.note).foregroundStyle(muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                } label: {
                    Text(text("Learn more", "En savoir plus"))
                        .font(.system(.subheadline, weight: .medium)).frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("permissions.details")
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            if setup.current != nil {
                Button {
                    if scenePhase == .active { setup.allow(store: store) }
                } label: {
                    primaryLabel(setup.isRevisiting ? setup.current?.accessAction ?? "" : text("Accept", "Accepter"))
                }
                .modifier(MorningEntryPrimaryStyle())
                .disabled(setup.isRequesting || scenePhase != .active)
                .accessibilityIdentifier("permissions.allow")
                Button(text("Not now", "Plus tard")) { setup.skip() }
                    .font(.system(.subheadline, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .disabled(setup.isRequesting)
                    .accessibilityIdentifier("permissions.skip")
            } else if setup.isRevisiting {
                Button { setup.finish() } label: { primaryLabel(text("Done", "Terminer")) }
                    .modifier(MorningEntryPrimaryStyle())
                    .accessibilityIdentifier("permissions.finish")
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 480)
    }

    private func primaryLabel(_ title: String) -> some View {
        HStack(spacing: 12) {
            if setup.isRequesting { ProgressView().tint(MorningStyle.onControl).accessibilityHidden(true) }
            Text(setup.isRequesting ? text("Waiting for your choice…", "En attente de votre choix…") : title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(MorningTheme.Typography.control)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 26)
    }
}

private extension MorningPermission {
    var accessName: String {
        switch self {
        case .location: MorningPermissionSetup.text("Location & weather", "Position et météo")
        case .calendar: MorningPermissionSetup.text("Calendar", "Calendrier")
        case .reminders: MorningPermissionSetup.text("Reminders", "Rappels")
        case .screenTime: MorningPermissionSetup.text("Screen Time", "Temps d’écran")
        case .speech, .microphone: MorningPermissionSetup.text("Voice & microphone", "Voix et micro")
        case .notifications: MorningPermissionSetup.text("Notifications", "Notifications")
        case .alarms: MorningPermissionSetup.text("Alarms", "Réveils")
        }
    }
    var accessSymbol: String {
        switch self {
        case .location: "location"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .screenTime: "hourglass"
        case .speech, .microphone: "waveform"
        case .notifications: "bell"
        case .alarms: "alarm"
        }
    }
    var accessHeading: String {
        switch self {
        case .location: MorningPermissionSetup.text("Your weather, here.", "Votre météo, ici.")
        case .calendar: MorningPermissionSetup.text("Your day, in view.", "Votre journée, en vue.")
        case .reminders: MorningPermissionSetup.text("A thought to keep.", "Une idée à garder.")
        case .screenTime: MorningPermissionSetup.text("Your habits take shape.", "Vos habitudes prennent forme.")
        case .speech: MorningPermissionSetup.text("Talk to MORE.", "Parlez à MORE.")
        case .microphone: MorningPermissionSetup.text("Make your voice heard.", "Faites entendre votre voix.")
        case .notifications: MorningPermissionSetup.text("At the right moment.", "Au bon moment.")
        case .alarms: MorningPermissionSetup.text("Wake up at your pace.", "Un réveil à votre rythme.")
        }
    }
    var accessBenefit: String {
        switch self {
        case .location: MorningPermissionSetup.text("Your location brings local weather and a sky that follows the sun.", "Votre position adapte la météo et le ciel de MORE à l’endroit où vous êtes.")
        case .calendar: MorningPermissionSetup.text("See your upcoming appointments as part of your morning.", "Retrouvez vos prochains rendez-vous dans votre matinée.")
        case .reminders: MorningPermissionSetup.text("Find your reminders and save a thought when you ask.", "Retrouvez vos rappels et enregistrez une idée à votre demande.")
        case .screenTime: MorningPermissionSetup.text("App-use times help MORE propose a routine that fits you.", "Les durées d’utilisation aident MORE à proposer votre routine.")
        case .speech: MorningPermissionSetup.text("Ask a question, pause or move on with your voice. You can also use the buttons.", "Posez une question, mettez en pause ou passez à la suite avec votre voix. Les boutons restent disponibles.")
        case .microphone: MorningPermissionSetup.text("The microphone lets you talk to MORE when you start listening.", "Le micro vous permet de parler à MORE quand vous démarrez une écoute.")
        case .notifications: MorningPermissionSetup.text("Get an invitation to start your morning at the time you choose.", "Recevez une invitation à commencer votre matinée, à l’heure choisie.")
        case .alarms: MorningPermissionSetup.text("The alarm you choose can lead you into your morning with MORE.", "Le réveil que vous choisirez vous invite à commencer votre matinée avec MORE.")
        }
    }
    var accessAction: String {
        switch self {
        case .location: MorningPermissionSetup.text("Allow location", "Autoriser ma position")
        case .calendar: MorningPermissionSetup.text("Allow calendar access", "Autoriser le calendrier")
        case .reminders: MorningPermissionSetup.text("Allow reminders", "Autoriser les rappels")
        case .screenTime: MorningPermissionSetup.text("Allow Screen Time", "Autoriser Temps d’écran")
        case .speech: MorningPermissionSetup.text("Enable voice", "Activer la voix")
        case .microphone: MorningPermissionSetup.text("Allow microphone", "Autoriser le microphone")
        case .notifications: MorningPermissionSetup.text("Allow notifications", "Autoriser les notifications")
        case .alarms: MorningPermissionSetup.text("Allow alarms", "Autoriser les réveils")
        }
    }
    var accessExplanation: String {
        switch self {
        case .location: MorningPermissionSetup.text("While MORE is open, your location brings you local weather and a sky that follows the sun. Your coordinates go to Apple Weather for local conditions and stay out of your saved history. An approximate location is enough; you can choose a city instead.", "Quand MORE est ouvert, votre position apporte la météo locale et un ciel qui suit le soleil. Vos coordonnées sont transmises à Apple Météo pour la météo et ne sont pas enregistrées dans votre historique. Une position approximative suffit ; vous pouvez aussi choisir une ville.")
        case .calendar: MorningPermissionSetup.text("MORE can read your upcoming events for your morning recap. Apple requires full calendar access; you choose which calendars MORE reads in Settings. Saving an event still needs your instruction.", "MORE peut lire vos prochains rendez-vous pour votre récap du matin. Apple exige l’accès complet ; vous choisissez les calendriers à lire dans les réglages. Enregistrer un événement nécessite toujours votre instruction.")
        case .reminders: MorningPermissionSetup.text("MORE can read upcoming reminders and save a thought as a reminder when you ask. Permission alone never creates, changes or completes a reminder.", "MORE peut lire vos rappels à venir et enregistrer une idée en rappel à votre demande. Cette autorisation ne crée, ne modifie et ne termine aucun rappel à elle seule.")
        case .screenTime: MorningPermissionSetup.text("Available app-use times help MORE understand your morning habits and propose a routine for you to review. The available coverage depends on your iPhone and Apple's approval; it doesn't reveal what you read inside other apps.", "Les durées d’utilisation disponibles aident MORE à comprendre vos habitudes et à proposer une routine à relire. La couverture dépend de votre iPhone et de l’autorisation Apple ; elle ne révèle pas ce que vous lisez dans les autres apps.")
        case .speech: MorningPermissionSetup.text("The microphone hears you; on-device speech recognition turns your instructions into text. iPhone may ask for two permissions, one after the other. If you decline one, continue with the buttons and change your choice later in Settings. These permissions do not start listening or enable the optional online conversation.", "Le micro vous entend ; la reconnaissance vocale sur l’appareil transforme vos instructions en texte. L’iPhone peut demander deux autorisations successives. Si vous en refusez une, continuez avec les boutons et changez votre choix plus tard dans les réglages. Ces accès ne démarrent aucune écoute et n’activent pas la conversation en ligne facultative.")
        case .microphone: MorningPermissionSetup.text("The microphone lets MORE hear your instructions during the voice interaction you start. It stays off during this setup. You can stop a listening turn at any time.", "Le microphone permet à MORE d’entendre vos instructions pendant l’interaction vocale que vous démarrez. Il reste éteint pendant cette configuration. Vous pouvez arrêter une écoute à tout moment.")
        case .notifications: MorningPermissionSetup.text("Notifications can invite you to your next morning or remind you to start a recording. Nothing is scheduled by granting access; you choose the time later.", "Les notifications peuvent vous inviter à votre prochaine matinée ou vous rappeler de démarrer un enregistrement. Autoriser cet accès ne programme rien ; vous choisirez l’heure plus tard.")
        case .alarms: MorningPermissionSetup.text("MORE can schedule the morning alarm you choose, with a shortcut into your morning when you stop it. Allowing alarms doesn't create an alarm; you set it later.", "MORE peut programmer le réveil que vous choisissez et ouvrir votre matinée à son arrêt. Autoriser les réveils n’en crée aucun ; vous le réglerez plus tard.")
        }
    }
}
