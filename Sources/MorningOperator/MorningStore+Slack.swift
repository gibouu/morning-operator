import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    @discardableResult
    func addSlackMoment(connection: ComposioConnection, identity: SlackReplyIdentity, channel: SlackChannelPage.Channel) -> Bool {
        guard !privacyBlocksWork, !sessionActive, !busy, connection.isActive,
              connection.service == "slack", identity.connectionID == connection.id else { return false }
        do {
            let arguments = try ComposioJSONValue.object(["channel": .string(channel.id), "limit": .number(3)]).prettyPrintedJSON()
            let target = RoutineStepTarget.connectedAPI(service: "slack", connectionID: connection.id,
                tool: "SLACK_FETCH_CONVERSATION_HISTORY", argumentsJSON: arguments)
            try target.validateIntegration()
            let detail = AppLanguage.isFrench
                ? "Lire les trois derniers messages disponibles dans #\(channel.name), espace \(identity.teamName), avec \(identity.userName). Vous pourrez choisir un message, demander une réponse et la corriger. Aucun message ne sera publié sans relecture puis votre instruction « envoie »."
                : "Read the latest three available messages in #\(channel.name), workspace \(identity.teamName), as \(identity.userName). You can choose a message, ask for a reply and revise it. Nothing is posted without review followed by your instruction to send."
            let step = RoutineStep(title: "Slack · #\(channel.name)", detail: detail, durationMinutes: 3, target: target)
            guard addConnectedStep(step) else { return false }
            notice = AppLanguage.isFrench ? "Moment Slack ajouté au brouillon. Relisez et validez votre routine."
                : "Slack moment added to your draft. Review and approve your routine."
            return true
        } catch { notice = error.moreDescription; return false }
    }

    var currentSlackContext: MorningExecutionID? {
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep,
              case let .connectedAPI(service, _, tool, _) = step.target, service == "slack",
              ["SLACK_FETCH_CONVERSATION_HISTORY", "SLACK_FETCH_MESSAGE_THREAD_FROM_A_CONVERSATION"].contains(tool) else { return nil }
        return MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
    }

    var slackReplySources: [SlackReplySource] {
        guard let context = currentSlackContext, let document = connectedMoment.document,
              document.executionID == context, document.origin?.privacyGeneration == localPrivacyGeneration else { return [] }
        return (try? SlackReplySource.sources(in: document)) ?? []
    }

    func prepareSlackReply(to source: SlackReplySource, intention: String) {
        guard slackReplySources.contains(source), !intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        selectedSlackMessageTS = source.messageTS
        performSlackReply { reply, context in await reply.prepare(intention: intention, source: source, context: context) }
    }

    func performSlackReply(_ action: @escaping @MainActor (SlackThreadReplyConversation, MorningExecutionID) async -> Void) {
        guard let context = currentSlackContext else { return }
        clearNativeMoment()
        if session?.status == .running { pause() }
        handsFreeVoice.interruptedRunningSession = false
        slackReplyTask?.cancel()
        let generation = dataGeneration
        slackReplyTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, generation == dataGeneration, currentSlackContext == context else { return }
            await action(slackReply, context)
            guard !Task.isCancelled, generation == dataGeneration, currentSlackContext == context else { return }
            slackReplyTask = nil
            synchronizeMorningActivity()
        }
    }

    /// Routing only chooses an observed source. The local model receives reply text guidance only.
    func handleSlackUtterance(_ text: String) async -> Bool {
        guard let context = currentSlackContext, !Task.isCancelled else { return false }
        let words = MorningHandsFreeVoicePolicy.normalized(text)
        if ["actualise slack", "actualise les messages", "refresh slack", "refresh messages"].contains(words) {
            refreshSlackMessages(); return true
        }
        if slackReply.context == context, slackReply.isActive {
            if ["annule", "annuler", "non", "cancel", "no", "continue", "continuer"].contains(words) {
                clearSlackReply()
                if words == "continue" || words == "continuer" { resume() }
                return true
            }
            if await slackReply.respond(text, context: context) { return true }
            if ["oui", "yes"].contains(words) {
                speech.speak(AppLanguage.isFrench ? "Dites ce que vous souhaitez répondre. Dites envoie seulement après la relecture."
                    : "Say what you want to reply. Say send only after the review.")
                return true
            }
        }
        let prefixes = ["repond", "reponse", "reply", "respond", "dis lui", "tell them", "change", "corrige", "revise", "make it"]
        let requestsReply = prefixes.contains { words.hasPrefix($0) }
        guard requestsReply else { return false }
        clearNativeMoment()
        if session?.status == .running { pause() }
        handsFreeVoice.interruptedRunningSession = false
        let sources = slackReplySources
        let groups = [["premier message", "premiere message", "first message", "message 1", "reponds au premier", "repond au premier"],
                      ["deuxieme message", "second message", "message 2", "reponds au deuxieme", "repond au deuxieme"],
                      ["troisieme message", "third message", "message 3", "reponds au troisieme", "repond au troisieme"]]
        let ordinal = groups.firstIndex { $0.contains { words.contains($0) } }
        if ordinal == nil, slackReply.context == context, !slackReply.body.isEmpty,
           ![.completed, .uncertain].contains(slackReply.phase) {
            await slackReply.revise(intention: text)
            return true
        }
        let selected: SlackReplySource?
        if let ordinal { selected = sources.indices.contains(ordinal) ? sources[ordinal] : nil }
        else { selected = sources.first { $0.messageTS == selectedSlackMessageTS } ?? (sources.count == 1 ? sources.first : nil) }
        guard let source = selected else {
            speech.speak(sources.isEmpty
                ? (AppLanguage.isFrench ? "Aucun message Slack récent n’est disponible. Actualisez la lecture ou dites suivant."
                    : "No recent Slack message is available. Refresh the reading or say next.")
                : (AppLanguage.isFrench ? "Précisez le premier, le deuxième ou le troisième message et ce que vous souhaitez répondre."
                    : "Choose the first, second or third message and say what you want to reply."))
            return true
        }
        selectedSlackMessageTS = source.messageTS
        await slackReply.prepare(intention: text, source: source, context: context)
        return true
    }

    func clearSlackReply() {
        slackReplyTask?.cancel(); slackReplyTask = nil
        if slackReply.context != nil { speech.stop() }
        slackReply.clear(); selectedSlackMessageTS = nil
    }

    var usesSyntheticSlack: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-testing-slack-reply")
        #else
        return false
        #endif
    }

    func slackActionCounts(for session: RoutineSession, stepID: UUID? = nil) -> SlackReplyActionCounts? {
        guard !privacyBlocksWork else { return nil }
        _ = slackReply.phase
        return try? slackReply.actionCounts(for: session, stepID: stepID)
    }
}

#if DEBUG
extension MorningStore {
    /// An explicit local fixture, used only by the UI-test workspace. No provider call or speech success is simulated.
    func presentSyntheticSlack(context: MorningExecutionID) {
        guard usesSyntheticSlack, currentSlackContext == context else { return }
        if connectedMoment.document?.executionID == context { return }
        connectedMoment.clear()
        guard let attempt = connectedMoment.begin(executionID: context, record: nil),
              connectedMoment.markDispatched(attempt, executionID: context) else { return }
        let messages: [ComposioJSONValue] = ["Can we meet tomorrow?", "The draft is ready to review.", "Thanks for the update."].enumerated().map { index, text in
            .object(["type": .string("message"), "ts": .string("179210000\(index).000001"),
                     "user": .string("USYNTHETIC"), "text": .string("SYNTHETIC: " + text)])
        }
        let result: ComposioJSONValue = .object(["ok": .bool(true), "messages": .array(messages)])
        _ = connectedMoment.receive(attempt, executionID: context, service: "slack", result: result,
            origin: ConnectedMomentOrigin(tool: "SLACK_FETCH_CONVERSATION_HISTORY", connectionID: "synthetic-slack",
                arguments: ["channel": .string("CSYNTHETIC"), "limit": .number(3)], privacyGeneration: localPrivacyGeneration))
        _ = connectedMoment.present("SYNTHETIC local fixture: three messages. No Slack account is used.", token: attempt, executionID: context)
        connectedActionStatus = "SYNTHETIC local fixture: three messages. No Slack account is used."
        recordExecution(.completed, confirmedExternalEffect: true)
    }
}

@MainActor final class SlackReplyUITestProvider: SlackThreadReplyProviding {
    func destination(for source: SlackReplySource) async throws -> SlackReplyDestination {
        let identity = try SlackReplyIdentity(connectionID: source.origin.connectionID, revision: String(repeating: "a", count: 64),
            teamID: "TSYNTHETIC", userID: "USYNTHETIC", teamName: "SYNTHETIC workspace", userName: "SYNTHETIC account")
        return try SlackReplyDestination(identity: identity, channelID: source.channelID, channelName: "synthetic-qa")
    }
    func validate(_ reply: SlackPreparedReply) async throws {
        guard try await destination(for: reply.source) == reply.destination else { throw SlackReplyError.accountChanged }
    }
    func send(_ reply: SlackPreparedReply, operationID: UUID) async throws -> SlackReplyReceipt {
        try await validate(reply)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--ui-testing-slack-reply"),
           ProcessInfo.processInfo.arguments.contains("--ui-testing-slack-uncertain-send") {
            // The conversation already durably claimed this synthetic dispatch.
            // A lost response after its simulated dispatch is ambiguous, not a
            // guaranteed pre-dispatch rejection. No provider/network is used.
            throw URLError(.timedOut)
        }
        #endif
        let ts = "1792100999.000001"
        let data: ComposioJSONValue = .object(["ok": .bool(true), "channel": .string(reply.source.channelID), "ts": .string(ts),
            "message": .object(["ts": .string(ts), "thread_ts": .string(reply.source.threadTS), "user": .string(reply.destination.userID),
                "blocks": reply.arguments(operationID: operationID)["blocks"]!])])
        let encoded = try JSONEncoder().encode(ComposioJSONValue.object(["requestID": .string(operationID.uuidString),
            "successful": .bool(true), "resultAvailable": .bool(true), "data": data]))
        let result = try JSONDecoder().decode(ComposioExecutionResult.self, from: encoded)
        return try SlackReplyReceipt.verified(result: result, reply: reply, operationID: operationID)
    }
}
#endif
