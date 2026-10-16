import SwiftUI
import MorningApple
import MorningCore

/// Named provider choices only. Nothing here posts a Slack message or approves a routine.
@MainActor struct SlackRoutineSetupView: View {
    @Bindable var store: MorningStore
    var assignmentContext: RoutineStepAssignmentContext? = nil
    var onUse: ((RoutineStepTarget, String) -> Bool)? = nil
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var connections: [ComposioConnection] = []
    @State private var selectedConnection: ComposioConnection?
    @State private var identity: SlackReplyIdentity?
    @State private var channels: [SlackChannelPage.Channel] = []
    @State private var selectedChannel: SlackChannelPage.Channel?
    @State private var choicesReceivedAt: Date?
    @State private var nextCursor: String?
    @State private var consumedCursors: Set<String> = []
    @State private var channelsLoaded = false
    @State private var loaded = false
    @State private var busy = false
    @State private var added = false
    @State private var message: String?
    @State private var visible = false
    @State private var revision = UUID()
    @State private var operation: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(eyebrow: "Slack", title: text("Slack in your morning", "Slack dans votre matin"),
                    subtitle: text("Choose a workspace and channel. MORE can read its messages and prepare a reply for your review.",
                        "Choisissez un espace et un canal. MORE pourra lire ses messages et préparer une réponse à relire."))
                Text(text("A reply is posted only after your separate, explicit request to send it.",
                    "Une réponse n’est publiée qu’après votre demande explicite et séparée d’envoi."))
                    .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                if !store.composio.isConfigured {
                    Text(text("Slack connections are unavailable in this version.", "La connexion Slack n’est pas disponible dans cette version."))
                } else {
                    if let message { Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("slack.setup.status") }
                    if busy { ProgressView(text("Checking Slack…", "Vérification de Slack…")) }
                    if loaded && connections.isEmpty {
                        Text(text("Connect a Slack account, then return here to choose its channel.",
                            "Connectez un compte Slack, puis revenez ici choisir son canal."))
                            .font(MorningTheme.Typography.note).accessibilityIdentifier("slack.setup.empty")
                    }
                    ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                        Button { choose(connection) } label: {
                            Label(accountName(connection, index: index), systemImage: selectedConnection?.id == connection.id ? "checkmark.circle" : "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                            .accessibilityIdentifier("slack.setup.account.\(index)")
                    }
                    if let identity {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(identity.teamName).font(MorningTheme.Typography.heading)
                                Text(text("As \(identity.userName)", "En tant que \(identity.userName)"))
                                    .font(MorningTheme.Typography.note)
                            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("slack.setup.identity")
                        Text(text("Channels you belong to and can write in", "Canaux dont vous êtes membre et où vous pouvez écrire"))
                            .font(MorningTheme.Typography.heading).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                            Button { selectedChannel = channel; added = false; message = nil } label: {
                                Label("#" + channel.name, systemImage: selectedChannel == channel ? "checkmark.circle.fill" : "number")
                                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                                .accessibilityIdentifier("slack.setup.channel.\(index)")
                        }
                        if channelsLoaded && channels.isEmpty {
                            Text(nextCursor == nil
                                ? text("No eligible channel was returned for this account.", "Aucun canal accessible n’a été renvoyé pour ce compte.")
                                : text("No eligible channel on this page. More channels are available below.", "Aucun canal accessible sur cette page. Vous pouvez charger les suivants."))
                                .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                        }
                        if nextCursor != nil {
                            Button(text("Load more channels", "Charger d’autres canaux")) { loadMore() }
                                .buttonStyle(SecondaryButtonStyle()).disabled(busy).accessibilityIdentifier("slack.setup.more")
                        }
                        if let channel = selectedChannel {
                            Text(text("Read #\(channel.name) in \(identity.teamName), then prepare replies when you ask.",
                                "Lire #\(channel.name) dans \(identity.teamName), puis préparer des réponses à votre demande."))
                                .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Button(actionLabel) { addSelected() }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(busy || added || !choicesAreCurrent(at: context.date) || store.sessionActive || store.busy || !assignmentIsCurrent)
                                    .accessibilityIdentifier(onUse == nil ? "slack.setup.add" : "slack.setup.use")
                                if !choicesAreCurrent(at: context.date) {
                                    Text(text("These choices have expired. Refresh before continuing.", "Ces choix ont expiré. Actualisez avant de continuer."))
                                        .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    Button(text("Refresh accounts and channels", "Actualiser les comptes et canaux")) { refreshAccounts() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(busy).accessibilityIdentifier("slack.setup.refresh")
                    NavigationLink {
                        APIConnectionsView(service: store.composio, serviceID: "slack", privacyBlocked: store.privacyBlocksWork,
                            privacyGeneration: store.dataGeneration)
                    } label: { Text(text("Connect or manage Slack", "Connecter ou gérer Slack")) }
                        .disabled(busy).accessibilityIdentifier("slack.setup.manage")
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(MorningStyle.ink).background(MorningPaper(showsSun: false))
        .navigationTitle("Slack").navigationBarTitleDisplayMode(.inline).disabled(store.privacyBlocksWork)
        .onAppear { visible = true; refreshAccounts() }
        .onDisappear { visible = false; clear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clear() }
            else if phase == .active && visible { refreshAccounts() }
        }
        .onChange(of: store.dataGeneration) { _, _ in clear(); if visible { refreshAccounts() } }
        .onChange(of: store.routine?.id) { _, _ in
            if onUse != nil { clear(); message = RoutineStepAssignmentContext.AssignmentError.changed.errorDescription }
        }
        .onChange(of: store.privacyBlocksWork) { _, blocked in
            if blocked { clear() } else if visible { refreshAccounts() }
        }
    }

    private var assignmentIsCurrent: Bool {
        guard onUse != nil else { return true }
        guard let assignmentContext else { return false }
        return (try? assignmentContext.validate(routine: store.routine, generation: store.dataGeneration)) != nil
    }
    private var actionLabel: String {
        if onUse != nil { return text("Use for this moment", "Utiliser pour ce moment") }
        return added ? text("Added to your routine", "Ajouté à votre routine") : text("Add this Slack moment", "Ajouter ce moment Slack")
    }
    private func accountName(_ connection: ComposioConnection, index: Int) -> String {
        if let label = connection.accountLabel, !label.isEmpty, label != connection.id { return label }
        return text("Slack account \(index + 1)", "Compte Slack \(index + 1)")
    }
    private func choicesAreCurrent(at date: Date) -> Bool {
        choicesReceivedAt.map { (0..<300).contains(date.timeIntervalSince($0)) } == true
    }
    private func refreshAccounts() {
        clear()
        launch { token, generation in
            let fresh = try await store.composio.connections()
            try check(token, generation)
            let active = fresh.filter { $0.service.lowercased() == "slack" && $0.isActive }
            guard Set(active.map(\.id)).count == active.count else { throw SlackReplyError.accountChanged }
            connections = active
            loaded = true
            if let only = connections.first, connections.count == 1 {
                selectedConnection = only
                try await page(for: only, cursor: nil, token: token, generation: generation)
            }
        }
    }
    private func choose(_ connection: ComposioConnection) {
        clearChoices(); selectedConnection = connection
        launch { token, generation in try await page(for: connection, cursor: nil, token: token, generation: generation) }
    }
    private func loadMore() {
        guard let connection = selectedConnection, let cursor = nextCursor else { return }
        guard choicesAreCurrent(at: Date()) else {
            message = text("These choices have expired. Refresh accounts and channels before continuing.", "Ces choix ont expiré. Actualisez les comptes et canaux avant de continuer.")
            return
        }
        launch { token, generation in try await page(for: connection, cursor: cursor, token: token, generation: generation) }
    }
    private func page(for connection: ComposioConnection, cursor: String?, token: UUID, generation: UUID) async throws {
        let current = try await store.composio.slackReplyIdentity(connectionID: connection.id)
        try check(token, generation)
        let verifiedAt = Date()
        if let identity, identity != current { throw SlackReplyError.accountChanged }
        identity = current
        var arguments: [String: ComposioJSONValue] = ["limit": .number(50), "types": .string("public_channel,private_channel"), "exclude_archived": .bool(true)]
        if let cursor { arguments["cursor"] = .string(cursor) }
        let result = try await store.composio.readSlack(tool: "SLACK_LIST_ALL_CHANNELS", arguments: arguments, connectionID: connection.id)
        try check(token, generation)
        guard result.successful, result.resultAvailable != false else { throw SlackReplyError.destinationUnavailable }
        let page = try SlackChannelPage(result: result.data)
        if let next = page.nextCursor, next == cursor || consumedCursors.contains(next) { throw SlackReplyError.destinationUnavailable }
        var combined = channels
        for channel in page.channels {
            if let prior = combined.first(where: { $0.id == channel.id }) {
                guard prior == channel else { throw SlackReplyError.destinationUnavailable }
            } else { combined.append(channel) }
        }
        if let cursor { consumedCursors.insert(cursor) }
        channels = combined; nextCursor = page.nextCursor; channelsLoaded = true
        if choicesReceivedAt == nil { choicesReceivedAt = verifiedAt }
    }
    private func addSelected() {
        guard let connection = selectedConnection, let expected = identity, let channel = selectedChannel,
              choicesAreCurrent(at: Date()), !store.sessionActive else { return }
        launch { token, generation in
            let fresh = try await store.composio.connections()
            try check(token, generation)
            guard let verifiedConnection = fresh.first(where: { $0.id == connection.id && $0.service.lowercased() == "slack" && $0.isActive }) else { throw SlackReplyError.accountChanged }
            let current = try await store.composio.slackReplyIdentity(connectionID: connection.id)
            try check(token, generation)
            guard current == expected, selectedChannel == channel, channels.contains(channel), choicesAreCurrent(at: Date()) else { throw SlackReplyError.accountChanged }
            if let onUse {
                // The selected source only changes the editor's local copy. Save
                // validates this pin again before creating an unapproved version.
                let selection = try store.slackMomentSelection(connection: verifiedConnection, identity: current, channel: channel)
                if onUse(selection.target, selection.summary) { added = true }
                else { message = RoutineStepAssignmentContext.AssignmentError.changed.errorDescription }
            } else if store.addSlackMoment(connection: verifiedConnection, identity: current, channel: channel) {
                added = true
                message = text("Added to your draft routine. Review and approve it in Routine before starting.", "Ajouté au brouillon de votre routine. Relisez et validez-le dans Routine avant de démarrer.")
            } else { message = text("This moment could not be added. Check your routine before trying again.", "Ce moment n’a pas pu être ajouté. Vérifiez votre routine avant de réessayer.") }
        }
    }
    private func launch(_ work: @escaping @MainActor (UUID, UUID) async throws -> Void) {
        guard visible, scenePhase == .active, !store.privacyBlocksWork, store.composio.isConfigured else { return }
        guard assignmentIsCurrent else {
            message = RoutineStepAssignmentContext.AssignmentError.changed.errorDescription; return
        }
        operation?.cancel(); revision = UUID(); busy = true; message = nil
        let token = revision, generation = store.dataGeneration
        operation = Task { @MainActor in
            defer { if revision == token { busy = false; operation = nil } }
            do { try await work(token, generation) }
            catch is CancellationError { }
            catch {
                guard revision == token, visible, scenePhase == .active, !store.privacyBlocksWork,
                      store.dataGeneration == generation else { return }
                if error is RoutineStepAssignmentContext.AssignmentError {
                    clearChoices(); message = error.moreDescription; return
                }
                if error as? SlackReplyError == .accountChanged { clearChoices(); selectedConnection = nil }
                message = error as? SlackReplyError == .serverBindingUnavailable
                    ? text("Slack account verification is unavailable. Manage your connection or try again later.", "La vérification du compte Slack est indisponible. Gérez la connexion ou réessayez plus tard.")
                    : text("Slack could not be verified. Refresh your accounts or check the connection before choosing again.", "Slack n’a pas pu être vérifié. Actualisez vos comptes ou vérifiez la connexion avant de choisir à nouveau.")
            }
        }
    }
    private func check(_ token: UUID, _ generation: UUID) throws {
        try Task.checkCancellation()
        guard revision == token, visible, scenePhase == .active, !store.privacyBlocksWork,
              store.dataGeneration == generation else { throw CancellationError() }
        if onUse != nil {
            guard let assignmentContext else { throw RoutineStepAssignmentContext.AssignmentError.changed }
            try assignmentContext.validate(routine: store.routine, generation: store.dataGeneration)
        }
    }
    private func clearChoices() {
        identity = nil; channels = []; selectedChannel = nil; choicesReceivedAt = nil
        nextCursor = nil; consumedCursors = []; channelsLoaded = false; added = false
    }
    private func clear() {
        revision = UUID(); operation?.cancel(); operation = nil; busy = false
        connections = []; selectedConnection = nil; loaded = false; message = nil; clearChoices()
    }
    private func text(_ english: String, _ french: String) -> String { locale.language.languageCode?.identifier == "fr" ? french : english }
}
