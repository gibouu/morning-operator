import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    @discardableResult
    func handleNativeMomentUtterance(_ text: String) async -> Bool {
        guard !Task.isCancelled, !privacyBlocksWork, sessionActive, let session, let step = currentStep else { return false }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        guard nativeMoment.accepts(text, context: context) else { return false }
        clearSlackReply()
        mailMorning.revokeReviewPreservingDraft(context: context)
        let generation = dataGeneration
        if session.status == .running { pause() }
        handsFreeVoice.interruptedRunningSession = false
        _ = await nativeMoment.respond(text, context: context)
        guard !Task.isCancelled, !privacyBlocksWork, dataGeneration == generation,
              self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return true }
        refreshNativeActionCount()
        synchronizeMorningActivity()
        return true
    }

    func performNativeMoment(_ action: @escaping @MainActor (NativeMomentConversation, MorningExecutionID) async -> Void) {
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep else { return }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        clearSlackReply()
        mailMorning.revokeReviewPreservingDraft(context: context)
        if session.status == .running { pause() }
        nativeMomentTask?.cancel()
        let generation = dataGeneration
        nativeMomentTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                  self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return }
            await action(nativeMoment, context)
            guard !Task.isCancelled, dataGeneration == generation, self.session?.id == context.sessionID,
                  currentStep?.id == context.stepID else { return }
            nativeMomentTask = nil
            refreshNativeActionCount()
            synchronizeMorningActivity()
        }
    }

    func nativeActionCounts(for session: RoutineSession) -> NativeMomentActionCounts? {
        guard !privacyBlocksWork else { return nil }
        if let cached = nativeActionCountCache[session.id], cached.routineVersionID == session.routine.id,
           cached.generation == dataGeneration { return cached.counts }
        return try? nativeMoment.actionCounts(for: session)
    }

    func refreshNativeActionCount(for expected: RoutineSession? = nil) {
        guard !privacyBlocksWork, let session = expected ?? session,
              let counts = try? nativeMoment.actionCounts(for: session) else { return }
        nativeActionCountCache[session.id] = (session.routine.id, dataGeneration, counts)
    }

    func clearNativeMoment(forPrivacy: Bool = false) {
        if forPrivacy { nativeActionCountCache = [:] } else { refreshNativeActionCount() }
        #if DEBUG
        if forPrivacy, ProcessInfo.processInfo.arguments.contains(NativeMomentUITestProvider.exactFlag) { nativeUITestProvider.clear() }
        #endif
        if nativeMoment.context != nil { speech.stop() }
        nativeMomentTask?.cancel(); nativeMomentTask = nil
        nativeMoment.clear()
    }

    #if DEBUG
    var exactReminderUITestDiagnostic: String? {
        guard !privacyBlocksWork,
              NativeMomentUITestProvider.exactWorkspace(directory: snapshot.url.deletingLastPathComponent()) != nil,
              sessionActive, let session, let step = currentStep else { return nil }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        var proof = nativeUITestProvider.diagnostic
        proof["sessionID"] = context.sessionID.uuidString
        proof["routineVersionID"] = context.routineVersionID.uuidString
        proof["stepID"] = context.stepID.uuidString
        proof["nativeContextMatches"] = String(nativeMoment.context == context)
        if let counts = nativeActionCounts(for: session) {
            proof["confirmed"] = String(counts.confirmed); proof["unconfirmed"] = String(counts.unconfirmed)
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
    #endif
}

#if DEBUG
/// Explicit simulator fixture: no EventKit permission request or Apple write is performed.
@MainActor final class NativeMomentUITestProvider: NativeMomentProviding {
    static let exactFlag = "--ui-testing-private-exact-reminder"
    static func exactWorkspace(directory: URL, arguments: [String] = ProcessInfo.processInfo.arguments) -> UUID? {
        let workspaces = arguments.filter { $0.hasPrefix("--ui-testing-workspace=") }
        guard arguments.contains("--ui-testing"), arguments.contains("--fixture-mode"), arguments.contains(exactFlag),
              arguments.contains("--ui-testing-native-actions"), workspaces.count == 1,
              let id = UUID(uuidString: String(workspaces[0].dropFirst("--ui-testing-workspace=".count))) else { return nil }
        let expected = FileManager.default.temporaryDirectory.appendingPathComponent("MorningOperatorUITests-\(id.uuidString)", isDirectory: true)
        return directory.standardizedFileURL == expected.standardizedFileURL ? id : nil
    }
    private var writes = 0
    private var received: [String: String] = [:]
    private let exactRequested: Bool
    private let exactEnabled: Bool
    private let context: @MainActor () -> MorningExecutionID?
    init(directory: URL, context: @escaping @MainActor () -> MorningExecutionID?) {
        exactRequested = ProcessInfo.processInfo.arguments.contains(Self.exactFlag)
        exactEnabled = Self.exactWorkspace(directory: directory) != nil
        self.context = context
    }
    var diagnostic: [String: String] {
        var result = received; result["simulatedWrites"] = String(writes); return result
    }
    func clear() { received = [:]; writes = 0 }
    func destination(for kind: CaptureDestination) throws -> NativeMomentDestination {
        guard !exactRequested || exactEnabled && kind == .reminder else { throw NativeMomentError.destinationChanged }
        return .init(id: "synthetic-list", sourceID: "synthetic-account", title: "SYNTHETIC QA", sourceTitle: "SYNTHETIC local fixture", kind: kind)
    }
    func validateDestination(_ destination: NativeMomentDestination) throws {
        guard try self.destination(for: destination.kind) == destination else { throw NativeMomentError.destinationChanged }
    }
    func upcomingReminders() async throws -> [ReminderSummary] {
        guard !exactRequested else { throw NativeMomentError.staleSource }
        return [.init(id: "synthetic-reminder", title: (AppLanguage.isFrench ? "EXEMPLE SIMULÉ : appeler le garage" : "SYNTHETIC: call the garage"), notes: "", dueDate: Date().addingTimeInterval(3_600), listTitle: "SYNTHETIC QA", listID: "synthetic-list", sourceID: "synthetic-account", sourceTitle: "SYNTHETIC local fixture")]
    }
    func perform(_ action: NativeMomentAction) throws -> String {
        guard writes < 24 else { throw NativeMomentError.unavailableJournal }
        if exactRequested {
            guard exactEnabled, let current = context(), case let .reminder(draft, destination) = action else { throw NativeMomentError.destinationChanged }
            try draft.validate(); try validateDestination(destination)
            // Actual received values only. No expected title, date or oracle is
            // present in the provider, and this bounded record stays in memory.
            received = ["kind": "reminder", "title": draft.title, "notes": draft.notes,
                "dueReferenceBits": draft.dueDate.map { String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16) } ?? "none",
                "timeZoneIdentifier": draft.timeZoneIdentifier, "notifyAtDueTime": String(draft.notifyAtDueTime),
                "destinationID": destination.id, "destinationSourceID": destination.sourceID,
                "destinationTitle": destination.title, "destinationSourceTitle": destination.sourceTitle,
                "destinationKind": destination.kind.rawValue, "receivedSessionID": current.sessionID.uuidString,
                "receivedRoutineVersionID": current.routineVersionID.uuidString, "receivedStepID": current.stepID.uuidString]
        }
        writes += 1
        return "synthetic-receipt-\(writes)"
    }
}
#endif
