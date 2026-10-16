import MorningApple
import MorningCore
import SwiftUI

/// People choose an app; its supported connection route stays behind that choice.
struct MorningConnectionsView: View {
    @Bindable var store: MorningStore
    @State private var services: [ComposioAvailableService] = []
    @State private var connections: [ComposioConnection] = []
    @State private var website: WebMorningSite?
    @State private var learningWebsite = false
    @State private var readySites: Set<WebMorningSite> = []
    @State private var loading = false
    @State private var loadFailed = false
    @State private var whatsAppUnavailable = false
    @State private var choosingBriefing = false
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    private let everydayServices = ["outlook", "googlecalendar", "googledrive", "googledocs", "googlesheets", "notion", "calendly", "discord", "youtube", "reddit"]
    private let professionalServices = ["instagram", "whatsapp", "facebook"]

    var body: some View {
        MorningList {
            connectionSection(text("Messages & your feed", "Messages et fil d’actualité")) {
                Text(text("You can sign in when a service first opens during learning or your routine. MORE keeps that browser session on this iPhone for your next mornings. You can also open a service here.",
                    "Vous pouvez vous connecter quand un service s’ouvre pour la première fois pendant l’apprentissage ou votre routine. MORE conserve cette session sur cet iPhone pour vos prochains matins. Vous pouvez aussi ouvrir un service ici."))
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("connections.inlineSignIn")
                websiteButton(.linkedin, detail: text("Open LinkedIn conversations in MORE. Sign in on the page when needed.", "Retrouvez vos conversations LinkedIn dans MORE. Connectez-vous sur la page si nécessaire."), symbol: "person.crop.rectangle")
                websiteButton(.slack, detail: text("Open your Slack workspace in MORE. Sign in on the page when needed.", "Retrouvez votre espace Slack dans MORE. Connectez-vous sur la page si nécessaire."), symbol: "number")
                websiteButton(.instagram, detail: text("Your messages, stories and feed, in MORE.", "Vos messages, vos stories et votre fil, dans MORE."), symbol: "camera")
                websiteButton(.tiktok, detail: text("Watch and scroll through TikTok in MORE.", "Retrouvez TikTok et faites défiler ses vidéos dans MORE."), symbol: "play.rectangle")
                websiteButton(.twitter, detail: text("Read and scroll through X in MORE.", "Retrouvez X et faites défiler votre fil dans MORE."), symbol: "text.bubble")
                websiteButton(.whatsapp, detail: text("Link WhatsApp Web to find your personal conversations in MORE.", "Associez WhatsApp Web pour retrouver vos conversations personnelles dans MORE."), symbol: "bubble.left.and.bubble.right")
                whatsAppHelp
                DisclosureGroup(text("More places to explore", "D’autres réseaux à retrouver")) {
                    VStack(alignment: .leading, spacing: 12) {
                        websiteButton(.reddit, detail: text("Browse your communities on Reddit’s website.", "Parcourez vos communautés sur le site de Reddit."), symbol: "bubble.left.and.bubble.right")
                        websiteButton(.facebook, detail: text("Your personal Facebook feed, in MORE.", "Votre fil Facebook personnel, dans MORE."), symbol: "person.2")
                        websiteButton(.threads, detail: text("Follow conversations on Threads, in MORE.", "Retrouvez les conversations Threads dans MORE."), symbol: "at")
                    }.padding(.top, 12)
                }.tint(MorningStyle.ink).accessibilityIdentifier("connections.moreWebsites")
            }

            connectionSection(text("Your day", "Votre journée")) {
                Button { choosingBriefing = true } label: {
                    connectionRow(title: text("Calendar, weather & sleep", "Calendrier, météo et sommeil"),
                        detail: text("Your schedule, local weather and optional sleep from Apple Health.", "Votre agenda, la météo locale et le sommeil facultatif de Santé Apple."),
                        symbol: "sun.max.fill", action: text("iPhone access · Choose", "Accès iPhone · Choisir"))
                }.accessibilityIdentifier("connections.calendar")
                NavigationLink {
                    NativeConnectionsView(store: store, service: store.nativeConnections, focus: .reminders)
                } label: {
                    connectionRow(title: text("Reminders", "Rappels"),
                        detail: text("Find your upcoming reminders and mark them done.", "Retrouvez vos prochains rappels et cochez ceux qui sont terminés."),
                        symbol: "checklist", action: store.nativeConnections.hasReminderAccess ? text("Access allowed · Open", "Accès autorisé · Ouvrir") : text("iPhone access · Allow", "Accès iPhone · Autoriser"))
                }
            }

            connectionSection(text("Your accounts", "Vos comptes")) {
                NavigationLink {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            PageHeading(eyebrow: text("Your email", "Vos e-mails"), title: text("Read Gmail in MORE", "Lire Gmail dans MORE"),
                                subtitle: text("Read unread messages and prepare an editable reply.", "Lisez vos messages non lus et préparez une réponse à modifier."))
                            GmailConnectionView(allowsReading: !store.privacyBlocksWork).id(store.dataGeneration)
                        }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    }.background(MorningPaper(showsSun: false))
                        .navigationTitle("Gmail").navigationBarTitleDisplayMode(.inline)
                } label: {
                    connectionRow(title: "Gmail",
                        detail: text("Read your unread email and prepare replies.", "Lisez vos e-mails non lus et préparez vos réponses."),
                        symbol: "envelope", action: text("Direct connection · Open", "Connexion directe · Ouvrir"), serviceID: "gmail")
                }.accessibilityIdentifier("connections.gmailReader")
                if isAvailable("gmail") {
                    DisclosureGroup(text("More Gmail actions", "D’autres actions avec Gmail")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("These account actions use a separate connection through Composio. They do not connect the reader above.",
                                "Ces actions utilisent une connexion distincte via Composio. Elles ne connectent pas le lecteur ci-dessus."))
                                .font(.footnote).foregroundStyle(MorningStyle.muted)
                            providerRow("gmail")
                        }.padding(.top, 12)
                    }.tint(MorningStyle.ink).accessibilityIdentifier("connections.gmailActions")
                }
                if loading { ProgressView(text("Loading your accounts…", "Chargement de vos comptes…")).padding(.vertical, 8) }
                if !store.composio.isConfigured {
                    Text(text("Account connections are not available in this version yet.", "La connexion à ces comptes n’est pas encore disponible dans cette version."))
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                } else if loadFailed {
                    Text(text("Your accounts could not be loaded. Please try again in a moment.", "Impossible de charger vos comptes. Réessayez dans un instant."))
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    Button(text("Try again", "Réessayer")) { Task { await refresh() } }
                        .buttonStyle(SecondaryButtonStyle()).disabled(loading)
                }
                ForEach(everydayServices.filter(isAvailable), id: \.self) { providerRow($0) }
                if ["slack", "linkedin"].contains(where: isAvailable) {
                    DisclosureGroup(text("Additional Slack & LinkedIn account actions", "Actions supplémentaires des comptes Slack et LinkedIn")) {
                        Text(text("These optional account connections offer additional actions. You can use the websites above without setting them up.",
                            "Ces connexions de compte facultatives proposent d’autres actions. Vous pouvez utiliser les sites ci-dessus sans les configurer."))
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                        ForEach(["slack", "linkedin"].filter(isAvailable), id: \.self) { providerRow($0) }
                    }.accessibilityIdentifier("connections.additionalMessagingActions")
                }
                if !loading && !loadFailed && services.isEmpty && store.composio.isConfigured {
                    Text(text("More account connections will appear here when they are available.", "Les comptes disponibles à connecter apparaîtront ici."))
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                }
            }

            connectionSection(text("A little more", "Pour aller plus loin")) {
                NavigationLink {
                    NativeConnectionsView(store: store, service: store.nativeConnections, focus: .shortcuts)
                } label: {
                    connectionRow(title: text("Messages, Notes & other iPhone apps", "Messages, Notes et autres apps iPhone"),
                        detail: text("Use a shortcut you have prepared on your iPhone.", "Utilisez un raccourci que vous avez préparé sur votre iPhone."),
                        symbol: "square.stack.3d.up", action: text("iPhone shortcut · Set up", "Raccourci iPhone · Configurer"))
                }
                websiteButton(.youtube, detail: text("Watch a few videos at your own pace.", "Quelques vidéos, à votre rythme."), symbol: "play.rectangle")
                websiteButton(.news, detail: text("Keep a moment for the news.", "Gardez un moment pour l’actualité."), symbol: "newspaper")
                if professionalServices.contains(where: isAvailable) {
                    DisclosureGroup(text("Professional accounts", "Comptes professionnels")) {
                        Text(text("For publishing and professional tools. Instagram requires a professional account; WhatsApp requires a Business Cloud account; Facebook uses your Pages.",
                            "Pour les publications et outils professionnels. Instagram demande un compte professionnel, WhatsApp un compte Business Cloud et Facebook une Page."))
                            .font(.footnote).foregroundStyle(MorningStyle.muted).padding(.top, 12)
                        // Each NavigationLink needs its own list row to open its own account.
                        ForEach(professionalServices.filter(isAvailable), id: \.self) { providerRow($0) }
                    }.tint(MorningStyle.ink).accessibilityIdentifier("connections.professional")
                }
            }

            DisclosureGroup(text("How connections work", "Comment fonctionnent les connexions")) {
                Text(text("You choose what to authorize on each service’s sign-in page. Website sign-ins stay in MORE’s browser. Connected accounts use our connection service and Composio. You can disconnect an account from its page in MORE; website sessions can be cleared in Settings.",
                    "Vous choisissez les accès sur la page de connexion de chaque service. Les sessions des sites restent dans le navigateur de MORE. Les comptes connectés passent par notre service de connexion et Composio. Vous pouvez déconnecter un compte depuis sa page dans MORE et effacer les sessions des sites dans Réglages."))
                    .font(.footnote).foregroundStyle(MorningStyle.muted).padding(.top, 8)
            }.tint(MorningStyle.ink)
        }
        .listStyle(.insetGrouped)
        .font(.body)
        .buttonStyle(.plain)
        .foregroundStyle(MorningStyle.ink)
        .background(MorningPaper(showsSun: false))
        .navigationTitle(text("Apps & accounts", "Apps et comptes"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(store.privacyBlocksWork)
        .sheet(isPresented: $choosingBriefing) { MorningBriefingView(store: store) }
        .navigationDestination(item: $website) { site in
            WebMorningView(site: site, minutes: 1, isStepActive: false,
                onSignInReady: learningWebsite ? nil : {
                    guard !store.privacyBlocksWork, website == site else { return }
                    readySites.insert(site); website = nil
                }, learningOnly: learningWebsite,
                onSaveRhythm: { store.saveBrowserRhythmObservation($0) },
                onClose: { website = nil })
                .id("\(site.rawValue).\(learningWebsite)")
        }
        .task(id: store.dataGeneration) { await refresh() }
        .onChange(of: website) { _, _ in
            // Independent setup shares website cookies with the routine. An
            // account switch must never resume the old account's DOM or speech.
            if store.currentStep?.webBehavior != nil, store.session?.status == .running { store.pause() }
            store.routineWebMoment.clear()
            store.webExecutionEvent = nil
        }
        .onChange(of: store.dataGeneration) { _, _ in
            website = nil; learningWebsite = false; readySites = []; services = []; connections = []; whatsAppUnavailable = false; choosingBriefing = false
        }
        .onChange(of: store.privacyBlocksWork) { _, blocked in
            if blocked { website = nil; learningWebsite = false; readySites = []; services = []; connections = []; whatsAppUnavailable = false; choosingBriefing = false }
        }
    }

    private func connectionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section { content() } header: { Text(title) }
    }

    private func connectionRow(title: String, detail: String, symbol: String, action: String,
                               serviceID: String = "") -> some View {
        HStack(alignment: .center, spacing: 12) {
            MorningConnectionIcon(serviceID: serviceID, fallbackSymbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text(action).font(.caption).foregroundStyle(.tint)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func websiteButton(_ site: WebMorningSite, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { learningWebsite = false; website = site } label: {
                connectionRow(title: site.displayName, detail: detail, symbol: symbol,
                    action: readySites.contains(site) ? text("Confirmed by you · Open website", "Confirmé par vous · Ouvrir le site") : text("Website · Sign in", "Site web · Se connecter"),
                    serviceID: site.rawValue)
                    .padding(.trailing, 18)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
            }.accessibilityIdentifier("connections.\(site.rawValue)")
            if readySites.contains(site) {
                Text(text("Your confirmation keeps this session available in MORE. Choose the actions in your routine to use the browser hands-free; MORE asks for your instruction before sending a reply. A sign-in alone does not verify that every page works.",
                    "Votre confirmation garde cette session disponible dans MORE. Choisissez les actions dans votre routine pour utiliser le navigateur mains libres ; MORE attend votre demande avant d’envoyer une réponse. Une connexion seule ne vérifie pas le fonctionnement de chaque page."))
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("connections.\(site.rawValue).handsFree")
                Button(text("Learn my pace in \(site.displayName)", "Apprendre mon rythme sur \(site.displayName)")) {
                    learningWebsite = true; website = site
                }.buttonStyle(SecondaryButtonStyle()).disabled(store.sessionActive || store.busy)
            }
        }
    }

    private var whatsAppHelp: some View {
        DisclosureGroup(text("Already using WhatsApp on this iPhone?", "WhatsApp est déjà installé sur cet iPhone ?")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(text("To keep your conversations inside MORE, link WhatsApp Web as an additional device. Being signed in to the WhatsApp app does not share its conversations with MORE.",
                    "Pour retrouver vos conversations dans MORE, associez WhatsApp Web comme appareil supplémentaire. La connexion à l’app WhatsApp ne partage pas ses conversations avec MORE."))
                Text(text("On WhatsApp Web, choose phone-number linking if offered. In WhatsApp, open Settings → Linked devices and enter the code shown. QR linking needs another screen. Availability depends on WhatsApp; this iPhone browser may not be supported.",
                    "Sur WhatsApp Web, choisissez l’association par numéro si elle est proposée. Dans WhatsApp, ouvrez Réglages → Appareils connectés et saisissez le code affiché. L’association par QR code nécessite un autre écran. WhatsApp peut limiter l’accès à ce navigateur iPhone."))
                Button(text("Open the WhatsApp app", "Ouvrir l’app WhatsApp")) {
                    let generation = store.dataGeneration
                    openURL(URL(string: "whatsapp://")!) { accepted in
                        guard generation == store.dataGeneration, !store.privacyBlocksWork else { return }
                        whatsAppUnavailable = !accepted
                    }
                }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("connections.openWhatsApp")
                if whatsAppUnavailable {
                    Text(text("WhatsApp could not be opened. Check that it is installed on this iPhone.", "Impossible d’ouvrir WhatsApp. Vérifiez que l’app est installée sur cet iPhone."))
                }
                Text(text("Composio connects WhatsApp Business Platform accounts for professional actions. A personal WhatsApp account uses the website or the WhatsApp app.",
                    "Composio connecte les comptes WhatsApp Business Platform pour leurs actions professionnelles. Pour un compte personnel, utilisez le site ou l’app WhatsApp."))
                if isAvailable("whatsapp") { providerRow("whatsapp") }
            }.font(.footnote).foregroundStyle(MorningStyle.muted).padding(.top, 12)
        }.tint(MorningStyle.ink).accessibilityIdentifier("connections.whatsappHelp")
    }

    private func isAvailable(_ id: String) -> Bool { services.contains { $0.id == id } }

    private func providerRow(_ id: String) -> some View {
        let info = providerInfo(id)
        let connected = connections.contains { $0.service == id && $0.isActive }
        return NavigationLink {
            if id == "slack" {
                SlackRoutineSetupView(store: store)
            } else if id == "googlecalendar" {
                GoogleCalendarDaySetupView(store: store)
            } else if id == "calendly" {
                CalendlyDaySetupView(store: store)
            } else if id == "outlook" {
                OutlookInboxSetupView(store: store)
            } else {
                APIConnectionsView(service: store.composio, serviceID: id, privacyBlocked: store.privacyBlocksWork,
                    privacyGeneration: store.dataGeneration, onAddToRoutine: { connection, tool, arguments in
                        store.addAPIAction(connection: connection, tool: tool, argumentsJSON: arguments)
                    })
            }
        } label: {
            connectionRow(title: info.name, detail: info.detail, symbol: info.symbol,
                action: connected ? text("Account connected · Manage", "Compte connecté · Gérer") : text("Account · Sign in", "Compte · Se connecter"), serviceID: id)
        }.accessibilityIdentifier("connections.account.\(id)")
    }

    private func providerInfo(_ id: String) -> (name: String, detail: String, symbol: String) {
        switch id {
        case "gmail": ("Gmail", text("Your email and the actions you choose.", "Vos e-mails et les actions que vous choisissez."), "envelope")
        case "outlook": ("Outlook", text("Your Microsoft email.", "Vos e-mails Microsoft."), "envelope.badge")
        case "googlecalendar": ("Google Calendar", text("Your events, connected to your morning.", "Vos événements, au fil de votre matin."), "calendar")
        case "googledrive": ("Google Drive", text("Find the files you need.", "Retrouvez les fichiers dont vous avez besoin."), "folder")
        case "googledocs": ("Google Docs", text("Your documents, close at hand.", "Vos documents, à portée de main."), "doc.text")
        case "googlesheets": ("Google Sheets", text("Find and use your spreadsheets.", "Retrouvez et utilisez vos feuilles de calcul."), "tablecells")
        case "notion": ("Notion", text("Your pages, notes and plans.", "Vos pages, vos notes et vos projets."), "note.text")
        case "slack": ("Slack", text("Your workspace conversations.", "Les conversations de votre espace de travail."), "number")
        case "calendly": ("Calendly", text("Keep track of your bookings.", "Gardez un œil sur vos rendez-vous."), "calendar.badge.clock")
        case "linkedin": ("LinkedIn", text("Your profile and publications.", "Votre profil et vos publications."), "person.crop.square")
        case "discord": ("Discord", text("Your profile and communities.", "Votre profil et vos communautés."), "person.2")
        case "youtube": ("YouTube", text("Your channel, playlists and available account actions.", "Votre chaîne, vos playlists et les actions disponibles pour votre compte."), "play.rectangle")
        case "reddit": ("Reddit", text("Your communities, posts and available account actions.", "Vos communautés, vos publications et les actions disponibles pour votre compte."), "bubble.left.and.bubble.right")
        case "twitter": ("X (Twitter)", text("Your posts and the account actions you authorize.", "Vos publications et les actions que vous autorisez sur votre compte."), "text.bubble")
        case "tiktok": ("TikTok", text("Your profile, videos and available account actions.", "Votre profil, vos vidéos et les actions disponibles pour votre compte."), "play.rectangle")
        case "instagram": (text("Instagram professional", "Instagram professionnel"), text("Publishing and professional account tools.", "Publications et outils de compte professionnel."), "camera")
        case "whatsapp": ("WhatsApp Business Cloud", text("Messaging for your business account.", "Les messages de votre compte professionnel."), "bubble.left.and.bubble.right")
        case "facebook": ("Facebook Pages", text("Your Pages and their professional conversations.", "Vos Pages et leurs conversations professionnelles."), "flag")
        default: (services.first { $0.id == id }?.name ?? id, "", "link")
        }
    }

    @MainActor private func refresh() async {
        guard store.composio.isConfigured, !store.privacyBlocksWork else { return }
        let generation = store.dataGeneration
        loading = true; loadFailed = false
        defer { if store.dataGeneration == generation { loading = false } }
        do {
            let freshServices = try await store.composio.services()
            let freshConnections = try await store.composio.connections()
            try Task.checkCancellation()
            guard store.dataGeneration == generation, !store.privacyBlocksWork else { return }
            services = freshServices; connections = freshConnections
        } catch is CancellationError { }
        catch {
            guard store.dataGeneration == generation, !store.privacyBlocksWork else { return }
            loadFailed = true
        }
    }
    private func text(_ english: String, _ french: String) -> String { locale.language.languageCode?.identifier == "fr" ? french : english }
}
