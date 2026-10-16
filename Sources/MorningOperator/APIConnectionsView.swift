import AuthenticationServices
import MorningApple
import MorningCore
import SwiftUI
import UIKit

/// Hosted OAuth sign-in; readiness always comes from a fresh account check.
struct APIConnectionsView: View {
    let service: ComposioService
    var serviceID: String? = nil
    var privacyBlocked = false
    var privacyGeneration = UUID()
    var onAddToRoutine: ((ComposioConnection, ComposioTool, String) -> Bool)?
    @ViewState private var services: [ComposioAvailableService] = []
    @ViewState private var connections: [ComposioConnection] = []
    @ViewState private var selectedConnection: ComposioConnection?
    @ViewState private var busy = false
    @ViewState private var hasLoaded = false
    @ViewState private var message: String?
    @ViewState private var technicalMessage: String?
    @ViewState private var supportCode: String?
    @ViewState private var supportCodeIssue: String?
    @ViewState private var operation: Task<Void, Never>?
    @ViewState private var revision = UUID()
    @ViewState private var signIn = APIHostedSignIn()
    @Environment(\.locale) private var locale
    private var visibleServices: [ComposioAvailableService] { services.filter { serviceID == nil || $0.id == serviceID } }
    private var visibleConnections: [ComposioConnection] { connections.filter { serviceID == nil || $0.service == serviceID } }
    private var serviceName: String {
        if serviceID == nil { return text("Your accounts", "Vos comptes") }
        return visibleServices.first?.name ?? visibleConnections.first?.name ?? APIConnectionPresentation.name(serviceID ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: text("Your connections", "Vos connexions"), title: serviceName,
                    subtitle: text("Choose what MORE can do with your account. Review each action before it runs.",
                                   "Choisissez ce que MORE peut faire avec votre compte. Vérifiez chaque action avant de la lancer."))
                if !service.isConfigured {
                    EmptyMoment(symbol: "link", title: text("Connection unavailable", "Connexion indisponible"),
                        detail: text("This connection isn't available right now. You can come back later.", "Cette connexion n’est pas disponible pour le moment. Vous pourrez revenir plus tard."))
                } else {
                    if let message {
                        Card { Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true) }
                            .accessibilityIdentifier("accounts.notice")
                    }
                    if busy {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                ProgressView(text("Checking your connection…", "Vérification de votre connexion…"))
                                Button(text("Cancel", "Annuler")) { cancelWaiting() }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    if visibleConnections.isEmpty { connectionChoices }
                    if hasLoaded && visibleConnections.isEmpty && !visibleServices.isEmpty {
                        Text(text("No account connected yet. Sign in above, then choose the permissions you want to share.",
                                  "Aucun compte connecté pour le moment. Identifiez-vous ci-dessus, puis choisissez les accès à partager."))
                            .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(visibleConnections) { connection in accountCard(connection) }
                    if !visibleConnections.isEmpty { connectionChoices }
                    if !busy {
                        Button(hasLoaded ? text("Refresh my accounts", "Actualiser mes comptes") : text("Try again", "Réessayer")) {
                            launch { try await refresh() }
                        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("accounts.refresh")
                    }
                }
                Card {
                    DisclosureGroup(text("Shared data", "Données partagées")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("Sign in on the service's official page and choose its permissions. MORE never asks for your password.",
                                      "Identifiez-vous sur la page officielle du service et choisissez ses autorisations. MORE ne vous demande jamais votre mot de passe."))
                            Text(text("Authorizations and requested actions pass through MORE’s connection service and Composio. Results are only shown during this session.",
                                      "Les autorisations et les actions demandées passent par le service de connexion de MORE et Composio. Les résultats restent affichés pendant cette session."))
                            DisclosureGroup(text("Connection details", "Détails de connexion")) {
                                if let technicalMessage {
                                    Text(technicalMessage).font(.raleway(.caption)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                                Button(text("Show installation code", "Afficher le code d’installation")) { showInstallationCode() }
                                    .accessibilityIdentifier("accounts.installationCode.show")
                                if let supportCode {
                                    Text(text("Installation code", "Code d’installation")).font(.caption)
                                    Text(supportCode).font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled).accessibilityIdentifier("accounts.installationCode")
                                    Text(text("This code identifies this installation for MORE support. It does not grant account access.",
                                              "Ce code permet à l’assistance MORE d’identifier cette installation. Il ne donne pas accès à vos comptes."))
                                        .font(.caption)
                                }
                                if let supportCodeIssue { Text(supportCodeIssue).font(.caption) }
                            }
                        }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).padding(.top, 12)
                    }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(MorningPaper(showsSun: false))
        .foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .navigationTitle(serviceName).navigationBarTitleDisplayMode(.inline)
        .disabled(privacyBlocked)
        .task(id: serviceID) {
            clearSession()
            guard service.isConfigured, !privacyBlocked else { return }
            launch { try await refresh() }
        }
        .morningSheet(item: $selectedConnection) { connection in
            NavigationStack {
                APIActionPickerView(service: service, connection: connection, accountName: accountTitle(connection), onAddToRoutine: onAddToRoutine)
            }
        }
        .onChange(of: privacyBlocked) { _, blocked in if blocked { clearSession() } }
        .onChange(of: privacyGeneration) { _, _ in clearSession() }
        .onDisappear { clearSession() }
    }

    @ViewBuilder private var connectionChoices: some View {
        if hasLoaded && visibleServices.isEmpty {
            Card { Text(text("This connection isn't available right now. Try refreshing your accounts later.", "Cette connexion n’est pas disponible pour le moment. Réessayez d’actualiser vos comptes plus tard.")).font(MorningTheme.Typography.note) }
        }
        ForEach(visibleServices) { available in
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text(visibleConnections.isEmpty ? text("Your \(available.name) account", "Votre compte \(available.name)") : text("Another account?", "Un autre compte ?"))
                        .font(MorningTheme.Typography.heading).fixedSize(horizontal: false, vertical: true)
                    if ["instagram", "whatsapp", "facebook"].contains(available.id) {
                        Text(professionalAccountNote(available.id)).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { connect(available) } label: {
                        Text(text("Connect \(available.name)", "Connecter \(available.name)"))
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                        .accessibilityIdentifier("accounts.connect.\(available.id)")
                }
            }
        }
    }
    private func accountCard(_ connection: ComposioConnection) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(accountTitle(connection)).font(MorningTheme.Typography.heading)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Label(statusTitle(connection), systemImage: connection.isActive ? "checkmark.circle" : "clock")
                    .font(.raleway(.subheadline)).foregroundStyle(connection.isActive ? MorningStyle.green : MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if connection.isActive {
                    Button { selectedConnection = connection } label: {
                        Text(text("Choose an action", "Choisir une action")).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                } else {
                    Text(text("Finish sign-in or reconnect this account, then refresh to check its status.",
                              "Terminez l’identification ou reconnectez ce compte, puis actualisez pour vérifier son état."))
                        .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(text("Account settings", "Réglages du compte")) {
                    Button(text("Disconnect this account", "Déconnecter ce compte"), role: .destructive) { disconnect(connection) }
                        .buttonStyle(SecondaryButtonStyle()).disabled(busy).padding(.top, 10)
                }.font(.raleway(.subheadline))
            }
        }
    }
    private func accountTitle(_ connection: ComposioConnection) -> String {
        if let label = connection.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        let matching = visibleConnections.filter { $0.service == connection.service }
        let name = text("\(connection.name) account", "Compte \(connection.name)")
        if matching.count > 1, let index = matching.firstIndex(where: { $0.id == connection.id }) { return "\(name) · \(index + 1)" }
        return name
    }
    private func statusTitle(_ connection: ComposioConnection) -> String {
        if connection.isActive { return text("Connected", "Connecté") }
        switch connection.status.uppercased() {
        case "INITIATED", "INITIALIZING", "PENDING": return text("Sign-in to finish", "Connexion à terminer")
        case "EXPIRED", "FAILED", "INACTIVE", "REVOKED", "DISABLED": return text("Reconnect this account", "Compte à reconnecter")
        default: return text("Connection to check", "Connexion à vérifier")
        }
    }
    private func professionalAccountNote(_ id: String) -> String {
        switch id {
        case "instagram": return text("For an Instagram Business or Creator account you manage.", "Pour un compte Instagram Business ou Creator que vous gérez.")
        case "whatsapp": return text("Requires a WhatsApp Business Platform account (WABA). A personal WhatsApp account cannot connect here.", "Nécessite un compte WhatsApp Business Platform (WABA). Un compte WhatsApp personnel ne peut pas être connecté ici.")
        default: return text("For Facebook Pages you manage.", "Pour les Pages Facebook que vous gérez.")
        }
    }
    private func refresh() async throws {
        let expected = revision
        let freshServices = try await service.services()
        let freshConnections = try await service.connections()
        try Task.checkCancellation()
        guard expected == revision, !privacyBlocked else { return }
        services = freshServices; connections = freshConnections; hasLoaded = true
    }
    private func connect(_ available: ComposioAvailableService) {
        launch {
            let previousActive = Set(connections.filter { $0.service == available.id && $0.isActive }.map(\.id))
            let authorization = try await service.startConnection(service: available.id,
                callbackURL: URL(string: ComposioService.callbackScheme + "://composio/callback")!)
            let sessionURI = try await signIn.start(authorization.authorizationURL)
            try await service.completeConnection(sessionURI: sessionURI)
            try Task.checkCancellation()
            try await refresh()
            guard !Task.isCancelled else { return }
            message = connections.contains(where: { $0.service == available.id && $0.isActive && !previousActive.contains($0.id) })
                ? text("Account connected and verified.", "Compte connecté et vérifié.")
                : text("Sign-in received. Check the updated status of your accounts below.", "Identification reçue. Vérifiez l’état actualisé de vos comptes ci-dessous.")
        }
    }
    private func disconnect(_ connection: ComposioConnection) {
        launch { try await service.disconnect(connectionID: connection.id); try await refresh() }
    }
    private func launch(_ action: @escaping @MainActor () async throws -> Void) {
        guard !privacyBlocked, !busy else { return }
        let expected = revision
        busy = true; message = nil; technicalMessage = nil
        operation = Task { @MainActor in
            defer { if expected == revision { busy = false; operation = nil } }
            do { try await action() }
            catch is CancellationError {
                guard expected == revision, !privacyBlocked else { return }
                message = text("Connection interrupted. Refresh your accounts or sign in again when you're ready.", "Connexion interrompue. Actualisez vos comptes ou reprenez l’identification quand vous le souhaitez.")
            }
            catch {
                guard expected == revision, !Task.isCancelled, !privacyBlocked else { return }
                message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
                technicalMessage = error.moreDescription
            }
        }
    }
    private func cancelWaiting() { operation?.cancel(); signIn.cancel() }
    private func showInstallationCode() {
        supportCode = nil; supportCodeIssue = nil
        do {
            supportCode = try service.existingInstallationSupportCode()
            if supportCode == nil {
                supportCodeIssue = text("No saved installation yet. Refresh your accounts first.",
                                        "Aucune installation enregistrée. Actualisez d’abord vos comptes.")
            }
        } catch { supportCodeIssue = error.moreDescription }
    }
    private func clearSession() {
        revision = UUID(); operation?.cancel(); operation = nil; signIn.cancel()
        selectedConnection = nil; connections = []; services = []; message = nil; technicalMessage = nil; supportCode = nil; supportCodeIssue = nil; busy = false; hasLoaded = false
    }
    private func text(_ en: String, _ fr: String) -> String { locale.language.languageCode?.identifier == "fr" ? fr : en }
}

private struct APIActionPickerView: View {
    let service: ComposioService
    let connection: ComposioConnection
    let accountName: String
    let onAddToRoutine: ((ComposioConnection, ComposioTool, String) -> Bool)?
    @ViewState private var tools: [ComposioTool] = []
    @ViewState private var message: String?
    @ViewState private var loading = true
    @ViewState private var query = ""
    @ViewState private var loadRevision = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private var visibleTools: [ComposioTool] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? tools : tools.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PageHeading(eyebrow: accountName, title: text("What MORE can do", "Ce que MORE peut faire"),
                    subtitle: text("Choose an action, complete its details, then review it before running.",
                                   "Choisissez une action, complétez ses détails, puis vérifiez-la avant de la lancer."))
                Text(text("Action names, field options and technical descriptions are supplied by the service and may use its language.",
                          "Les noms d’actions, options des champs et descriptions techniques sont fournis par le service et peuvent utiliser sa langue."))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                if loading { ProgressView(text("Finding your available actions…", "Recherche des actions disponibles…")) }
                if let message {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            Button(text("Try again", "Réessayer")) { loadRevision = UUID() }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                if tools.isEmpty && !loading && message == nil {
                    EmptyMoment(symbol: "sparkles", title: text("No actions available yet", "Aucune action disponible pour le moment"),
                        detail: text("Check this account's permissions or reconnect it from your accounts.", "Vérifiez les autorisations de ce compte ou reconnectez-le depuis vos comptes."))
                } else if visibleTools.isEmpty && !loading && message == nil {
                    Text(text("No matching action. Try another word.", "Aucune action correspondante. Essayez un autre mot."))
                        .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                }
                ForEach(visibleTools) { tool in
                    NavigationLink {
                        APIActionForm(service: service, connection: connection, accountName: accountName, tool: tool, onAddToRoutine: onAddToRoutine)
                    } label: {
                        Card {
                            LinkRow(title: tool.name, detail: "", symbol: "sparkles")
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(MorningPaper(showsSun: false)).foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .navigationTitle(text("Choose an action", "Choisir une action")).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: text("Find an action", "Rechercher une action"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Done", "Terminer")) { dismiss() } } }
        .task(id: loadRevision) { await load() }
    }
    private func load() async {
        loading = true; message = nil
        do {
            let fresh = try await service.connections()
            guard fresh.contains(where: { $0.id == connection.id && $0.isActive }) else {
                message = text("This account needs to be reconnected before choosing an action.", "Reconnectez ce compte avant de choisir une action.")
                loading = false; return
            }
            let fetched = try await service.tools(service: connection.service)
            try Task.checkCancellation(); tools = fetched; loading = false
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
            loading = false
        }
    }
    private func text(_ en: String, _ fr: String) -> String { locale.language.languageCode?.identifier == "fr" ? fr : en }
}

private struct APIActionForm: View {
    let service: ComposioService
    let connection: ComposioConnection
    let accountName: String
    let tool: ComposioTool
    let onAddToRoutine: ((ComposioConnection, ComposioTool, String) -> Bool)?
    @ViewState private var values: [String: String] = [:]
    @ViewState private var included: Set<String> = []
    @ViewState private var reviewedArguments: String?
    @ViewState private var intention = ""
    @ViewState private var planning = false
    @ViewState private var planner = ConnectedActionPlanner()
    @ViewState private var message: String?
    @ViewState private var result: String?
    @ViewState private var busy = false
    @ViewState private var outcomeUncertain = false
    @ViewState private var uncertainRequestID: UUID?
    @ViewState private var uncertainArguments: String?
    @ViewState private var operation: Task<Void, Never>?
    @Environment(\.locale) private var locale
    private var properties: [String: ComposioJSONValue] { tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:] }
    private var required: Set<String> { Set(tool.inputSchema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []) }
    private var keys: [String] { properties.keys.sorted { (required.contains($0) ? 0 : 1, $0) < (required.contains($1) ? 0 : 1, $1) } }
    private var needsPreparedDetails: Bool {
        keys.contains { (required.contains($0) || included.contains($0)) && !["string", "number", "integer", "boolean"].contains(fieldType(properties[$0]?.objectValue ?? [:])) }
    }

    var body: some View {
        MorningForm {
            Section {
                Text(tool.name).font(MorningTheme.Typography.heading).fixedSize(horizontal: false, vertical: true)
                Text(accountName).font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(text("What would you like MORE to do?", "Que souhaitez-vous confier à MORE ?")) {
                TextField(text("Describe your request in your own words", "Décrivez votre demande avec vos mots"), text: $intention, axis: .vertical)
                    .lineLimit(3...8).disabled(busy)
                    .accessibilityIdentifier("accounts.action.intention")
                Text(text("MORE prepares the details on this device. You review them before anything runs or joins your routine.",
                          "MORE prépare les détails sur cet appareil. Vous les vérifiez avant toute action ou tout ajout à votre routine."))
                    .font(.raleway(.caption)).foregroundStyle(.secondary)
                Button(text("Prepare for review", "Préparer pour vérification")) { prepareFromIntention() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy || outcomeUncertain || intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("accounts.action.prepare")
            }
            Section(text("Or complete the details yourself", "Ou précisez les détails vous-même")) {
                if required.isEmpty { Text(text("You can review this action now. Add any options you need below.", "Vous pouvez vérifier cette action maintenant. Ajoutez les options utiles ci-dessous.")).font(MorningTheme.Typography.note) }
                ForEach(keys.filter { required.contains($0) }, id: \.self) { key in field(key) }
                if keys.contains(where: { !required.contains($0) }) {
                    DisclosureGroup(text("More options", "Autres options")) {
                        ForEach(keys.filter { !required.contains($0) }, id: \.self) { key in field(key) }
                    }
                }
            }
            Section {
                Button(text("Review action", "Vérifier l’action")) { review() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy || outcomeUncertain || needsPreparedDetails)
                if needsPreparedDetails {
                    Text(text("This action needs the details prepared from your request above before it can run.",
                              "Cette action nécessite les détails préparés à partir de votre demande ci-dessus avant de pouvoir être lancée."))
                        .font(.raleway(.caption)).foregroundStyle(.secondary)
                }
            }
            if let reviewedArguments {
                Section(text("Ready to run", "Prêt à exécuter")) {
                    Text(tool.name).font(MorningTheme.Typography.heading)
                    Text(accountName).fixedSize(horizontal: false, vertical: true)
                    reviewedValues(reviewedArguments)
                    Text(text("Only the reviewed values above will be sent to this account.", "Seules les valeurs vérifiées ci-dessus seront envoyées à ce compte."))
                        .font(.raleway(.caption)).foregroundStyle(.secondary)
                    Button(text("Run this action", "Lancer cette action")) { execute(reviewedArguments) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(busy || outcomeUncertain)
                    if ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: connection.service, tool: tool.slug) {
                        Text(ConnectedRoutineActionPolicy.spokenMailSendExplanation).font(.footnote)
                    } else if let onAddToRoutine {
                        Button(text("Add to my routine", "Ajouter à ma routine")) {
                            message = onAddToRoutine(connection, tool, reviewedArguments)
                                ? text("Added to your routine draft. Review and approve it before starting.", "Ajouté au brouillon de votre routine. Vérifiez et approuvez-la avant de démarrer.")
                                : text("The action could not be added. Finish the current morning and check your routine.", "L’action n’a pas pu être ajoutée. Terminez le matin en cours et vérifiez votre routine.")
                        }.buttonStyle(SecondaryButtonStyle()).disabled(busy || outcomeUncertain)
                    }
                }
            }
            if busy { Section { ProgressView(planning ? text("Preparing your request…", "Préparation de votre demande…") : text("Waiting for your account…", "En attente de votre compte…")); Button(text("Cancel waiting", "Arrêter l’attente")) { operation?.cancel() }.buttonStyle(SecondaryButtonStyle()) } }
            if let message { Section { Text(message).font(.raleway(.footnote)).textSelection(.enabled) } }
            if let uncertainRequestID {
                Section(text("Check this action in your account", "Vérifiez cette action dans votre compte")) {
                    Text(tool.name).font(.raleway(.headline))
                    Text(accountName).fixedSize(horizontal: false, vertical: true)
                    if let uncertainArguments { reviewedValues(uncertainArguments) }
                    DisclosureGroup(text("Request reference", "Référence de la demande")) {
                        Text(uncertainRequestID.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Text(text("Open the connected account and check whether this exact action happened before allowing another attempt.", "Ouvrez le compte connecté et vérifiez si cette action précise a eu lieu avant d’autoriser un nouvel essai."))
                        .font(.raleway(.footnote))
                    Button(text("I checked: the action already happened", "J’ai vérifié : l’action a déjà eu lieu")) { reconcile(uncertainRequestID, occurred: true) }.buttonStyle(SecondaryButtonStyle())
                    Button(text("I checked: no action happened", "J’ai vérifié : aucune action n’a eu lieu")) { reconcile(uncertainRequestID, occurred: false) }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if let result { Section(text("Your result", "Votre résultat")) { Text(result).font(MorningTheme.Typography.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
        }
        .foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .navigationTitle(text("Prepare the action", "Préparer l’action")).navigationBarTitleDisplayMode(.inline)
        .onChange(of: values) { _, _ in reviewedArguments = nil }
        .onChange(of: included) { _, _ in reviewedArguments = nil }
        .onChange(of: intention) { _, _ in reviewedArguments = nil }
        .onDisappear { operation?.cancel(); operation = nil; result = nil; message = nil }
    }
    @ViewBuilder private func reviewedValues(_ json: String) -> some View {
        if let review = try? ConnectedActionReview.summary(argumentsJSON: json, schema: tool.inputSchema,
            french: locale.language.languageCode?.identifier == "fr") {
            Text(review).font(MorningTheme.Typography.body).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(ConnectedActionReviewError.unreadable.moreDescription)
                .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
        }
    }
    @ViewBuilder private func field(_ key: String) -> some View {
        let definition = properties[key]?.objectValue ?? [:]
        let label = ConnectedActionReview.label(for: key, definition: .object(definition))
        let type = fieldType(definition)
        let options = definition["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let enabled = required.contains(key) || included.contains(key)
        VStack(alignment: .leading, spacing: 6) {
            if !required.contains(key) { Toggle(text("Include ", "Inclure ") + label, isOn: Binding(get: { included.contains(key) }, set: { if $0 { included.insert(key) } else { included.remove(key) } })) }
            if enabled {
                if type == "boolean" {
                    Toggle(label, isOn: Binding(get: { values[key] == "true" }, set: { values[key] = $0 ? "true" : "false" }))
                } else if type == "string" && !options.isEmpty {
                    Picker(label, selection: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })) {
                        Text(text("Choose", "Choisir")).tag("")
                        ForEach(options, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                    Text(text("Options from the service, shown in its original language.",
                              "Options fournies par le service, affichées dans leur langue d’origine."))
                        .font(.raleway(.caption)).foregroundStyle(.secondary)
                } else if ["string", "number", "integer"].contains(type) {
                    TextField(label, text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }), axis: .vertical)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                } else {
                    Text(label + text(" — describe this in your request above; MORE will prepare it for review.", " — décrivez ce détail dans votre demande ci-dessus ; MORE le préparera pour vérification.")).font(.raleway(.footnote))
                }
                if let description = definition["description"]?.stringValue {
                    DisclosureGroup(text("Service description (original language)", "Description du service (langue d’origine)")) {
                        Text(verbatim: description).font(.raleway(.caption)).foregroundStyle(.secondary)
                    }.font(.raleway(.caption))
                }
            }
        }.padding(.vertical, 3)
    }
    private func review() {
        do {
            let arguments = try simpleArguments(requireAll: true)
            guard required.isSubset(of: Set(arguments.keys)) else { throw ComposioServiceError.invalidArguments }
            let json = try ComposioJSONValue.object(arguments).prettyPrintedJSON()
            _ = try ConnectedActionReview.summary(argumentsJSON: json, schema: tool.inputSchema)
            reviewedArguments = json
            message = nil; result = nil
        } catch {
            reviewedArguments = nil
            message = (error as? ConnectedActionReviewError)?.moreDescription
                ?? APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
        }
    }
    private func simpleArguments(requireAll: Bool) throws -> [String: ComposioJSONValue] {
        var arguments: [String: ComposioJSONValue] = [:]
        for key in keys where required.contains(key) || included.contains(key) {
            let type = fieldType(properties[key]?.objectValue ?? [:])
            let value = values[key] ?? ""
            if !requireAll, value.isEmpty { continue }
            switch type {
            case "boolean": arguments[key] = .bool(value == "true")
            case "number", "integer":
                guard let number = try? JSONDecoder().decode(Decimal.self, from: Data(value.utf8)) else { throw ComposioServiceError.invalidArguments }
                var original = number, rounded = Decimal()
                NSDecimalRound(&rounded, &original, 0, .plain)
                guard type != "integer" || rounded == number else { throw ComposioServiceError.invalidArguments }
                arguments[key] = .number(number)
            case "string":
                guard !required.contains(key) || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ComposioServiceError.invalidArguments }
                let options = properties[key]?.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
                guard options.isEmpty || options.contains(value) else { throw ComposioServiceError.invalidArguments }
                arguments[key] = .string(value)
            default:
                if requireAll { throw ComposioServiceError.invalidArguments }
            }
        }
        return arguments
    }
    private func fieldType(_ definition: [String: ComposioJSONValue]) -> String {
        if let type = definition["type"]?.stringValue { return type }
        if let type = definition["type"]?.arrayValue?.compactMap(\.stringValue).first(where: { $0 != "null" }) { return type }
        if definition["properties"] != nil { return "object" }
        if definition["items"] != nil { return "array" }
        if ["$ref", "anyOf", "oneOf", "allOf"].contains(where: { definition[$0] != nil }) { return "complex" }
        return "string"
    }
    private func prepareFromIntention() {
        guard !busy, !outcomeUncertain else { return }
        let entered: [String: ComposioJSONValue]
        do { entered = try simpleArguments(requireAll: false) }
        catch { message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr"); return }
        let requested = intention, expectedValues = values, expectedIncluded = included
        busy = true; planning = true; message = nil; reviewedArguments = nil; result = nil
        operation = Task { @MainActor in
            defer { busy = false; planning = false; operation = nil }
            do {
                let proposed = try await planner.propose(intention: requested, tool: tool, enteredArguments: entered)
                try Task.checkCancellation()
                guard intention == requested, values == expectedValues, included == expectedIncluded else { return }
                _ = try ConnectedActionReview.summary(argumentsJSON: proposed, schema: tool.inputSchema)
                reviewedArguments = proposed
                message = text("Details prepared on this device. Check every value below before running or adding the action.",
                               "Détails préparés sur cet appareil. Vérifiez chaque valeur ci-dessous avant de lancer ou d’ajouter l’action.")
            } catch is CancellationError {
                message = text("Preparation cancelled. No action ran.", "Préparation annulée. Aucune action n’a été lancée.")
            } catch {
                guard !Task.isCancelled else { return }
                if let error = error as? ConnectedActionPlanningError {
                    switch error {
                    case .needsDetails(let question): message = question
                    case .unavailable:
                        message = needsPreparedDetails
                            ? text("This action needs local preparation, which is unavailable on this device right now. Choose another action or come back when it is ready.", "Cette action nécessite une préparation locale, indisponible sur cet appareil pour le moment. Choisissez une autre action ou revenez lorsqu’elle sera prête.")
                            : text("The local model is unavailable here. You can complete the fields below and review the action yourself.", "Le modèle local n’est pas disponible ici. Vous pouvez compléter les champs ci-dessous et vérifier vous-même l’action.")
                    case .tooLarge: message = text("This action is too complex to prepare locally. Choose a simpler action.", "Cette action est trop complexe pour être préparée localement. Choisissez une action plus simple.")
                    case .invalidProposal: message = text("MORE couldn't prepare valid details. Add more detail to your request, or use the available fields.", "MORE n’a pas pu préparer des détails valides. Précisez votre demande ou utilisez les champs disponibles.")
                    }
                } else {
                    message = (error as? ConnectedActionReviewError)?.moreDescription
                        ?? APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
                }
            }
        }
    }
    private func execute(_ json: String) {
        guard !busy, !outcomeUncertain else { return }
        busy = true; message = nil; result = nil
        operation = Task { @MainActor in
            defer { busy = false; operation = nil }
            do {
                let fresh = try await service.connections()
                guard fresh.contains(where: { $0.id == connection.id && $0.isActive }) else { throw ComposioServiceError.notAuthorized }
                let arguments = try ComposioJSONValue.parseObject(json)
                let receipt = try await service.execute(tool: tool.slug, arguments: arguments, connectionID: connection.id)
                if receipt.resultAvailable == false {
                    message = text("Receipt recovered. Response content is not retained by the service.", "Confirmation récupérée. Le contenu de la réponse n’est pas conservé par le service.")
                } else {
                    message = receipt.successful ? text("Your account service confirmed the request. You can check its response below.", "Le service de votre compte a confirmé la demande. Vous pouvez consulter sa réponse ci-dessous.") : text("The service reported a failure. Check the account before another attempt.", "Le service signale un échec. Vérifiez le compte avant un nouvel essai.")
                }
                if receipt.successful, receipt.resultAvailable != false {
                    do { result = try await ConnectedResultNarrator().summarize(receipt.data, service: connection.name) }
                    catch {
                        result = text("The service replied, but MORE couldn't prepare a readable summary. Check the result in your account.",
                                      "Le service a répondu, mais MORE n’a pas pu préparer de résumé lisible. Consultez le résultat dans votre compte.")
                    }
                }
                if !receipt.successful { outcomeUncertain = true; uncertainRequestID = receipt.requestID; uncertainArguments = json }
                reviewedArguments = nil
            } catch {
                if case ComposioServiceError.executionUncertain(let id) = error { outcomeUncertain = true; uncertainRequestID = id; uncertainArguments = json }
                message = error is CancellationError ? text("Waiting cancelled. If execution had started, check the account before repeating the action.", "Attente annulée. Si l’exécution avait commencé, vérifiez le compte avant de recommencer.") : APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
            }
        }
    }
    private func reconcile(_ id: UUID, occurred: Bool) {
        do {
            try service.reconcileExecution(requestID: id)
            uncertainRequestID = nil; uncertainArguments = nil; reviewedArguments = nil
            outcomeUncertain = occurred
            message = occurred
                ? text("Marked as already completed after your account check. This action will not be repeated here.", "Indiquée comme déjà effectuée après votre vérification. Cette action ne sera pas répétée ici.")
                : text("Account checked. Review the action again before a new attempt.", "Compte vérifié. Vérifiez de nouveau l’action avant un nouvel essai.")
        } catch { message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr") }
    }
    private func text(_ en: String, _ fr: String) -> String { locale.language.languageCode?.identifier == "fr" ? fr : en }
}

private enum APIConnectionPresentation {
    static func name(_ id: String) -> String {
        switch id {
        case "gmail": "Gmail"
        case "outlook": "Outlook"
        case "googlecalendar": "Google Calendar"
        case "googlecontacts": "Google Contacts"
        case "googledrive": "Google Drive"
        case "googledocs": "Google Docs"
        case "googlesheets": "Google Sheets"
        case "instagram": "Instagram"
        case "whatsapp": "WhatsApp"
        case "facebook": "Facebook"
        case "linkedin": "LinkedIn"
        case "discord": "Discord"
        case "youtube": "YouTube"
        case "reddit": "Reddit"
        case "twitter": "X (Twitter)"
        case "tiktok": "TikTok"
        case "slack": "Slack"
        case "notion": "Notion"
        case "calendly": "Calendly"
        default: "MORE"
        }
    }
    static func failureMessage(_ error: any Error, french: Bool) -> String {
        if let issue = error as? ComposioServiceError {
            switch issue {
            case .invalidArguments:
                return french ? "Vérifiez les champs et les options de l’action avant de continuer." : "Check the action's fields and options before continuing."
            case .executionUncertain:
                return french ? "Le résultat est inconnu. Vérifiez ce compte avant de lancer à nouveau cette action." : "The outcome is unknown. Check this account before running this action again."
            case .credentialsUnavailable:
                return french ? "Déverrouillez votre iPhone, puis réessayez." : "Unlock your iPhone, then try again."
            case .notAuthorized:
                return french ? "Cette autorisation n’est plus disponible. Revenez à vos comptes pour vérifier la connexion." : "This authorization is no longer available. Go back to your accounts to check the connection."
            case .notConfigured, .insecureURL:
                return french ? "Cette connexion n’est pas disponible pour le moment. Réessayez plus tard." : "This connection isn't available right now. Try again later."
            case .backend(let failure) where failure.code == "rate_limited":
                return french ? "Un instant, plusieurs demandes sont en cours. Attendez une minute puis réessayez." : "Several requests are in progress. Wait a minute, then try again."
            default: break
            }
        }
        if let issue = error as? URLError, issue.code == .notConnectedToInternet {
            return french ? "Vérifiez votre connexion à Internet, puis réessayez." : "Check your internet connection, then try again."
        }
        return french ? "La demande n’a pas abouti. Vérifiez votre connexion puis réessayez." : "The request couldn't finish. Check your connection, then try again."
    }
}

@MainActor
private final class APIHostedSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var completion: CheckedContinuation<String, any Error>?
    private var attempt = UUID()
    func start(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let expected = UUID()
                attempt = expected; completion = continuation
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: ComposioService.callbackScheme) { callback, error in
                    Task { @MainActor in
                        guard self.attempt == expected else { return }
                        if let error {
                            if let authenticationError = error as? ASWebAuthenticationSessionError, authenticationError.code == .canceledLogin {
                                self.finish(.failure(CancellationError()))
                            } else { self.finish(.failure(error)) }
                            return
                        }
                        guard let callback, callback.scheme == ComposioService.callbackScheme,
                              callback.host == "composio", callback.path == "/callback" else {
                            self.finish(.failure(ComposioServiceError.invalidResponse)); return
                        }
                        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                        let matching = items.filter { $0.name == "session_uri" }
                        guard matching.count == 1, let sessionURI = matching.first?.value, !sessionURI.isEmpty else {
                            self.finish(.failure(ComposioServiceError.invalidResponse)); return
                        }
                        self.finish(.success(sessionURI))
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                // Reuse the owner's browser sign-in; authenticated completion still verifies this installation.
                session.prefersEphemeralWebBrowserSession = false
                if !session.start() { finish(.failure(ComposioServiceError.invalidResponse)) }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    func cancel() {
        attempt = UUID(); session?.cancel()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<String, any Error>) {
        let continuation = completion
        completion = nil; session = nil
        continuation?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
