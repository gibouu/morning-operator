import Foundation
import Testing
import MorningCore
@testable import MorningApple

@MainActor @Suite("Native moment prepared actions")
struct NativeMomentConversationTests {
    private func context() -> MorningExecutionID { .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID()) }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("native-moment-tests-\(UUID())") }

    @Test func exactReminderUIEditRetainsPayloadAndNeedsSeparateReviewAndConfirmation() async throws {
        let provider = NativeMomentFakeProvider(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let step = RoutineStep(title: "My exact reminder", durationMinutes: 1, automation: .timedMoment)
        var session = RoutineSession(routine: RoutineVersion(sourceLabel: "SYNTHETIC", steps: [step], isApproved: true))
        try session.start()
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let exact = try #require(ISO8601DateFormatter().date(from: "2026-10-16T07:25:00Z"))
        let preciseDraft = exact.addingTimeInterval(37.625)
        let conversation = NativeMomentConversation(provider: provider, directory: path, calendar: paris,
            speak: { _ in throw CancellationError() })
        _ = await conversation.respond("Reminder: Bring the blue notebook to North studio no date", context: context)
        await conversation.edit(title: "Bring the blue notebook to North studio", date: preciseDraft, durationMinutes: 30, context: context)
        #expect(conversation.draftDate == preciseDraft, "The engine does not round an existing source draft.")
        conversation.stageEdit(title: "Edited title", date: preciseDraft, durationMinutes: 30)
        #expect(conversation.draftDate == preciseDraft, "A title-only edit keeps the original precision.")
        let minuteInput = NativeMomentDateInput.editedMinute(preciseDraft, calendar: paris)
        #expect(minuteInput == exact && preciseDraft != exact)
        await conversation.edit(title: "Bring the blue notebook to North studio", date: minuteInput, durationMinutes: 30, context: context)
        #expect(!conversation.canConfirm && provider.writes.isEmpty)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty, "Neither an edit nor interrupted review is permission to write.")
        conversation.acknowledgeScreenReview()
        _ = await conversation.respond("add it", context: context)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.count == 1)
        guard case let .reminder(received, destination) = provider.writes.first else { Issue.record("Expected the actual reminder payload"); return }
        #expect(received.title == "Bring the blue notebook to North studio" && received.notes.isEmpty)
        #expect(received.dueDate == exact && received.timeZoneIdentifier == "Europe/Paris" && received.notifyAtDueTime)
        #expect(destination.id == "list-1" && destination.sourceID == "account-1" && destination.kind == .reminder)
        let counts = try conversation.actionCounts(for: session)
        #expect(counts.confirmed == 1 && counts.unconfirmed == 0)
        let otherSession = RoutineSession(routine: session.routine)
        #expect(try conversation.actionCounts(for: otherSession).confirmed == 0)
    }

    @Test func languagePresentationPreservesActionAndRevokesReviewWithoutWriting() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        let title = conversation.action?.title, destination = conversation.action?.destination
        #expect(conversation.canConfirm)
        conversation.appLanguageDidChange()
        #expect(!conversation.canConfirm && provider.writes.isEmpty)
        #expect(conversation.action?.title == title && conversation.action?.destination == destination)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty)
    }

    @Test func creationNeedsSeparateReviewedConfirmationAndDoubleConfirmDoesNotWrite() async throws {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        let handled = await conversation.respond("Rappelle-moi de boire de l’eau sans date et ajoute", context: context)
        #expect(handled); #expect(provider.writes.isEmpty)
        _ = await conversation.respond("Rappelle-moi de boire de l’eau sans date", context: context)
        #expect(conversation.canConfirm)
        #expect(conversation.action?.destination?.id == "list-1")
        _ = await conversation.respond("oui", context: context)
        #expect(provider.writes.isEmpty)
        _ = await conversation.respond("ajoute", context: context)
        _ = await conversation.respond("ajoute", context: context)
        #expect(provider.writes.count == 1); #expect(conversation.phase == .completed)
        let journal = try String(contentsOf: path.appendingPathComponent("native-moment-journal.json"), encoding: .utf8)
        #expect(!journal.contains("boire")); #expect(!journal.contains("list-1")); #expect(!journal.contains("account-1"))
    }

    @Test func changedDestinationAfterReviewNeverWrites() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        provider.listID = "another-account-list"
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty); #expect(conversation.phase == .unavailable)
    }

    @Test func interruptedReviewAndCorrectionRequireFreshReview() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        var failSpeech = true
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in if failSpeech { throw CancellationError() } })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        #expect(!conversation.canConfirm)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty)
        failSpeech = false
        _ = await conversation.respond("repeat", context: context)
        #expect(conversation.canConfirm)
        failSpeech = true
        _ = await conversation.respond("change the title to call Sam", context: context)
        #expect(conversation.action?.title == "call Sam"); #expect(!conversation.canConfirm)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty)
        conversation.acknowledgeScreenReview()
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.count == 1)
    }

    @Test func calendarCreationRequiresDateAndExplicitDuration() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Planifie café demain matin", context: context)
        #expect(conversation.phase == .needsDetails); #expect(conversation.action == nil)
        _ = await conversation.respond("30 minutes", context: context)
        #expect(conversation.canConfirm)
        guard case .event(let draft, let destination) = conversation.action else { Issue.record("Expected single event draft"); return }
        #expect(draft.endDate.timeIntervalSince(draft.startDate) == 1_800)
        #expect(destination.kind == .calendar)
        #expect(provider.writes.isEmpty)
        _ = await conversation.respond("ajoute", context: context)
        #expect(provider.writes.count == 1)
    }

    @Test func completionNeedsObservedUnambiguousFreshIdentity() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        var now = Date()
        provider.items = [NativeMomentFakeProvider.item("one"), NativeMomentFakeProvider.item("two")]
        let conversation = NativeMomentConversation(provider: provider, directory: path, now: { now }, speak: { _ in })
        _ = await conversation.respond("termine ce rappel", context: context)
        #expect(conversation.action == nil)
        _ = await conversation.respond("lis mes rappels", context: context)
        _ = await conversation.respond("termine ce rappel", context: context)
        #expect(conversation.action == nil)
        now = now.addingTimeInterval(250)
        _ = await conversation.respond("termine le deuxième rappel", context: context)
        guard case .complete(let item) = conversation.action else { Issue.record("Expected observed reminder"); return }
        #expect(item.id == "two")
        now = now.addingTimeInterval(51)
        _ = await conversation.respond("marque terminé", context: context)
        #expect(provider.writes.isEmpty); #expect(conversation.phase == .unavailable)
    }

    @Test func confirmedCompletionPassesExactObservedSnapshotOnly() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let expected = NativeMomentFakeProvider.item("one"); provider.items = [expected]
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("read my reminders", context: context)
        _ = await conversation.respond("complete the first reminder", context: context)
        #expect(provider.writes.isEmpty)
        _ = await conversation.respond("mark complete", context: context)
        #expect(provider.writes == [.complete(expected)])
    }

    @Test func unknownEffectCannotReplayOrBeBypassedByChangedRestoredDraft() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        provider.failWrite = true
        let first = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await first.respond("Reminder: water plants no date", context: context)
        _ = await first.respond("add it", context: context)
        #expect(first.phase == .uncertain); #expect(provider.writes.count == 1)
        _ = await first.respond("add it", context: context)
        first.clear()
        let restored = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await restored.respond("Reminder: a changed title no date", context: context)
        _ = await restored.respond("add it", context: context)
        #expect(restored.phase == .uncertain); #expect(provider.writes.count == 1)
    }

    @Test func successfulWriteIsNotReplayedWhenResultSpeechFails() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        var failSpeech = false
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in if failSpeech { throw CancellationError() } })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        failSpeech = true
        _ = await conversation.respond("add it", context: context)
        #expect(conversation.phase == .completed); #expect(provider.writes.count == 1)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.count == 1)
    }

    @Test func contextChangeCannotConfirmOldDraft() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        let handled = await conversation.respond("add it", context: self.context())
        #expect(!handled); #expect(provider.writes.isEmpty)
    }

    @Test func lateReadAfterClearCannotRestoreSource() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        provider.items = [NativeMomentFakeProvider.item("one")]; provider.holdRead = true
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        let task = Task { await conversation.respond("read my reminders", context: context) }
        while provider.readContinuation == nil { await Task.yield() }
        conversation.clear(); provider.finishRead()
        _ = await task.value
        #expect(conversation.context == nil); #expect(conversation.phase == .idle); #expect(conversation.observedReminders.isEmpty)
    }

    @Test func screenEditAndExpiredReviewCannotConfirmOldValues() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        var now = Date()
        let conversation = NativeMomentConversation(provider: provider, directory: path, now: { now }, speak: { _ in })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        conversation.stageEdit(title: "a corrected title", date: nil, durationMinutes: 30)
        #expect(!conversation.canConfirm); #expect(conversation.action == nil)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty)
        await conversation.review()
        #expect(provider.writes.isEmpty)
        _ = await conversation.respond("repeat", context: context)
        #expect(conversation.action?.title == "a corrected title"); #expect(conversation.canConfirm)
        now = now.addingTimeInterval(301)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty)
    }

    @Test func lateSpeechCompletionCannotRestoreConfirmedDraft() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        var gate: CheckedContinuation<Void, Never>?
        var firstSpeech = true
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in
            if firstSpeech { firstSpeech = false; await withCheckedContinuation { gate = $0 } }
        })
        let preparing = Task { await conversation.respond("Reminder: water plants no date", context: context) }
        while gate == nil { await Task.yield() }
        conversation.acknowledgeScreenReview()
        _ = await conversation.respond("add it", context: context)
        #expect(conversation.phase == .completed); #expect(provider.writes.count == 1)
        gate?.resume(); _ = await preparing.value
        #expect(conversation.phase == .completed); #expect(!conversation.canConfirm)
    }

    @Test func revokedNativePermissionBeforeConfirmDoesNotWrite() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        provider.hasAccess = false
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty); #expect(conversation.phase == .unavailable)
    }

    @Test func missingExplicitOrdinalNeverUsesSoleReminder() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        provider.items = [NativeMomentFakeProvider.item("one")]
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("read my reminders", context: context)
        for request in ["termine le deuxième rappel", "complete the sixth reminder", "termine le 9 rappel", "termine le dixième rappel"] {
            _ = await conversation.respond(request, context: context)
            #expect(conversation.action == nil); #expect(provider.writes.isEmpty)
        }
        _ = await conversation.respond("termine ce rappel", context: context)
        #expect(conversation.action == .complete(provider.items[0]))
    }

    @Test func finalConfirmationMustMatchPreparedEffectKind() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        provider.items = [NativeMomentFakeProvider.item("one")]
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        _ = await conversation.respond("marque terminé", context: context)
        #expect(provider.writes.isEmpty)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.count == 1)
        _ = await conversation.respond("read my reminders", context: context)
        _ = await conversation.respond("complete the first reminder", context: context)
        _ = await conversation.respond("ajoute", context: context)
        #expect(provider.writes.count == 1)
        _ = await conversation.respond("mark complete", context: context)
        #expect(provider.writes.count == 2)
    }

    @Test func supersededReadSuccessOrFailureCannotReplaceNewerDraft() async {
        for needsDetails in [false, true] {
            for fails in [false, true] {
                let provider = NativeMomentFakeProvider(), context = context(), path = directory()
                provider.items = [NativeMomentFakeProvider.item("old")]; provider.holdRead = true
                let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
                let old = Task { await conversation.respond("read my reminders", context: context) }
                while provider.readContinuation == nil { await Task.yield() }
                _ = await conversation.respond(needsDetails ? "Reminder: a new request" : "Reminder: a new request no date", context: context)
                let phase = conversation.phase, action = conversation.action, title = conversation.draftTitle
                provider.finishRead(failing: fails); _ = await old.value
                #expect(conversation.phase == phase); #expect(conversation.action == action)
                #expect(conversation.draftTitle == title); #expect(conversation.observedReminders.isEmpty)
                try? FileManager.default.removeItem(at: path)
            }
        }
    }

    @Test func confirmedJournalCountSurvivesRecreationAndExcludesUnknownAndOtherSessions() throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let journal = NativeMomentJournal(control: LocalDataControl(directory: path)), first = context(), other = context()
        let id = UUID(), pending = UUID(), otherID = UUID()
        let fingerprint = String(repeating: "a", count: 64)
        #expect(try journal.claim(id: id, context: first, fingerprint: fingerprint, generation: nil))
        try journal.confirm(id: id, fingerprint: fingerprint, receipt: "actual-source-id", generation: nil)
        #expect(try journal.claim(id: pending, context: first, fingerprint: String(repeating: "b", count: 64), generation: nil))
        #expect(try journal.claim(id: otherID, context: other, fingerprint: String(repeating: "c", count: 64), generation: nil))
        try journal.confirm(id: otherID, fingerprint: String(repeating: "c", count: 64), receipt: "other-id", generation: nil)
        let restored = NativeMomentJournal(control: LocalDataControl(directory: path))
        #expect(try restored.confirmedCount(contexts: [first], generation: nil) == 1)
        #expect(try restored.confirmedCount(contexts: [other], generation: nil) == 1)
        #expect(try restored.counts(contexts: [first], generation: nil) == NativeMomentActionCounts(confirmed: 1, unconfirmed: 1))
        #expect(try restored.counts(contexts: [other], generation: nil) == NativeMomentActionCounts(confirmed: 1, unconfirmed: 0))
        try restored.confirm(id: pending, fingerprint: String(repeating: "b", count: 64), receipt: "later-confirmed-source", generation: nil)
        let confirmed = NativeMomentJournal(control: LocalDataControl(directory: path))
        #expect(try confirmed.counts(contexts: [first], generation: nil) == NativeMomentActionCounts(confirmed: 2, unconfirmed: 0))
    }

    @Test func uncertainProviderWriteSurvivesClearAndRestorationWithoutCompletingItsMailMoment() async throws {
        let provider = NativeMomentFakeProvider(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        provider.failWrite = true
        let step = RoutineStep(title: "Private current mail moment", automation: .gmailInbox)
        var session = RoutineSession(routine: RoutineVersion(sourceLabel: "Synthetic recap", steps: [step]).approved())
        try session.start()
        try session.pause()
        let before = session
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Reminder: PRIVATE_OWNER_TITLE no date", context: context)
        _ = await conversation.respond("add it", context: context)
        #expect(conversation.phase == .uncertain && provider.writes.count == 1)
        #expect(try conversation.actionCounts(for: session) == NativeMomentActionCounts(confirmed: 0, unconfirmed: 1))
        conversation.clear()
        let restored = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        let journalURL = path.appendingPathComponent("native-moment-journal.json")
        let saved = try Data(contentsOf: journalURL)
        #expect(try restored.actionCounts(for: session) == NativeMomentActionCounts(confirmed: 0, unconfirmed: 1))
        let otherSession = RoutineSession(routine: session.routine)
        #expect(try restored.actionCounts(for: otherSession) == NativeMomentActionCounts(confirmed: 0, unconfirmed: 0))
        #expect(session == before && session.completedStepIDs.isEmpty && session.currentStep?.automation == .gmailInbox)
        #expect(try Data(contentsOf: journalURL) == saved, "Projection reads must not rewrite or resolve the claim.")
        let text = try #require(String(data: saved, encoding: .utf8))
        for privateValue in ["PRIVATE_OWNER_TITLE", step.title, "My list", "My account", "list-1", "account-1", "real-injected-receipt"] {
            #expect(!text.contains(privateValue))
        }
    }

    @Test func projectionRequiresExactVersionStepAndCurrentPrivacyGeneration() throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let control = LocalDataControl(directory: path), context = context()
        let journal = NativeMomentJournal(control: control)
        let claimed = try journal.claim(id: UUID(), context: context, fingerprint: String(repeating: "e", count: 64), generation: nil)
        #expect(claimed)
        let wrongVersion = MorningExecutionID(sessionID: context.sessionID, routineVersionID: UUID(), stepID: context.stepID)
        let wrongStep = MorningExecutionID(sessionID: context.sessionID, routineVersionID: context.routineVersionID, stepID: UUID())
        #expect(try journal.counts(contexts: [wrongVersion, wrongStep], generation: nil) == NativeMomentActionCounts(confirmed: 0, unconfirmed: 0))
        #expect(try journal.counts(contexts: [context, context], generation: nil) == NativeMomentActionCounts(confirmed: 0, unconfirmed: 1))
        #expect(throws: LocalDataControlError.staleGeneration) {
            try journal.counts(contexts: [context], generation: UUID())
        }
    }

    @Test func expiredSourceReviewSpeaksRecoveryInsteadOfOldDetails() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        provider.items = [NativeMomentFakeProvider.item("one")]
        var now = Date(), spoken: [String] = []
        let conversation = NativeMomentConversation(provider: provider, directory: path, now: { now }, speak: { spoken.append($0) })
        _ = await conversation.respond("read my reminders", context: context)
        _ = await conversation.respond("complete this reminder", context: context)
        let before = spoken.count
        now = now.addingTimeInterval(301)
        await conversation.review()
        #expect(conversation.phase == .unavailable); #expect(spoken.count == before + 1)
        #expect(spoken.last == NativeMomentError.staleSource.localizedDescription)
        #expect(provider.writes.isEmpty)
    }

    @Test func confirmedSummaryKeepsExactReviewedFactsEvenWhenSpeechFails() async throws {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        var failSpeech = false
        let conversation = NativeMomentConversation(provider: provider, directory: path, now: { now }, calendar: calendar, speak: { _ in if failSpeech { throw CancellationError() } })
        _ = await conversation.respond("Reminder: call the garage tomorrow morning", context: context)
        guard case .reminder(let draft, let target) = conversation.action, let due = draft.dueDate else { Issue.record("Expected dated reminder"); return }
        failSpeech = true
        _ = await conversation.respond("add it", context: context)
        #expect(conversation.phase == .completed)
        let format = Date.FormatStyle(date: .complete, time: .shortened, locale: AppLanguage.locale, calendar: calendar, timeZone: calendar.timeZone)
        #expect(conversation.message.contains(draft.title)); #expect(conversation.message.contains(target.title))
        #expect(conversation.message.contains(target.sourceTitle)); #expect(conversation.message.contains(due.formatted(format)))
        #expect(conversation.message.contains("Europe/Paris"))
        #expect(!conversation.message.contains("Dites ajoute")); #expect(!conversation.message.contains("Say add it"))
        #expect(provider.writes.count == 1)
    }

    @Test func unsupportedDateCorrectionRevokesReviewAndExplainsUnchangedValues() async {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        var spoken: [String] = []
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { spoken.append($0) })
        _ = await conversation.respond("Reminder: call the garage tomorrow morning", context: context)
        let original = conversation.action
        for correction in ["change la date à vendredi", "30 minutes"] {
            _ = await conversation.respond(correction, context: context)
            #expect(conversation.phase == .needsDetails); #expect(!conversation.canConfirm)
            #expect(conversation.action == original); #expect(spoken.last == conversation.message)
            _ = await conversation.respond("add it", context: context)
            #expect(provider.writes.isEmpty)
        }
        _ = await conversation.respond("repeat", context: context)
        #expect(conversation.action == original); #expect(conversation.canConfirm)
        #expect(provider.writes.isEmpty)
    }

    @Test func confirmedCompletionRetiresWholeReadingAndCannotBeCountedAgain() async throws {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let first = NativeMomentFakeProvider.item("first"), second = NativeMomentFakeProvider.item("second")
        provider.items = [first, second]
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("read my reminders", context: context)
        _ = await conversation.respond("complete the first reminder", context: context)
        _ = await conversation.respond("mark complete", context: context)
        #expect(provider.writes == [.complete(first)]); #expect(conversation.observedReminders.isEmpty)
        let journal = NativeMomentJournal(control: LocalDataControl(directory: path))
        #expect(try journal.confirmedCount(contexts: [context], generation: nil) == 1)
        _ = await conversation.respond("complete the first reminder", context: context)
        _ = await conversation.respond("mark complete", context: context)
        #expect(provider.writes == [.complete(first)]); #expect(conversation.action == nil)
        #expect(try journal.confirmedCount(contexts: [context], generation: nil) == 1)
        provider.items = [second]
        _ = await conversation.respond("read my reminders", context: context)
        _ = await conversation.respond("complete the first reminder", context: context)
        #expect(conversation.action == .complete(second))
        #expect(provider.writes.count == 1)
    }

    @Test func privacyGenerationChangeBeforeConfirmPreventsWrite() async throws {
        let provider = NativeMomentFakeProvider(), context = context(), path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let conversation = NativeMomentConversation(provider: provider, directory: path, speak: { _ in })
        _ = await conversation.respond("Reminder: water plants no date", context: context)
        let control = LocalDataControl(directory: path)
        let state = try control.beginForget(); let generation = try #require(state.generation)
        try control.finishForget(expectedGeneration: generation)
        _ = await conversation.respond("add it", context: context)
        #expect(provider.writes.isEmpty)
    }
}

@MainActor private final class NativeMomentFakeProvider: NativeMomentProviding {
    var listID = "list-1"
    var writes: [NativeMomentAction] = []
    var items: [ReminderSummary] = []
    var failWrite = false
    var hasAccess = true
    var holdRead = false
    var readContinuation: CheckedContinuation<[ReminderSummary], Error>?
    static func item(_ id: String) -> ReminderSummary { .init(id: id, title: "Reminder \(id)", notes: "observed note", dueDate: Date(timeIntervalSince1970: 1_900_000_000), listTitle: "My list", listID: "list-1", sourceID: "account-1", sourceTitle: "My account") }
    func destination(for kind: CaptureDestination) throws -> NativeMomentDestination {
        guard hasAccess else { throw ReminderServiceError.remindersNotAuthorized }
        return .init(id: listID, sourceID: "account-1", title: "My list", sourceTitle: "My account", kind: kind) }
    func validateDestination(_ destination: NativeMomentDestination) throws { guard try self.destination(for: destination.kind) == destination else { throw NativeMomentError.destinationChanged } }
    func upcomingReminders() async throws -> [ReminderSummary] {
        if holdRead { return try await withCheckedThrowingContinuation { readContinuation = $0 } }
        return items
    }
    func finishRead(failing: Bool = false) {
        if failing { readContinuation?.resume(throwing: NativeMomentError.staleSource) } else { readContinuation?.resume(returning: items) }
        readContinuation = nil
    }
    func perform(_ action: NativeMomentAction) throws -> String { writes.append(action); if failWrite { throw NativeMomentError.unavailableJournal }; return "real-injected-receipt" }
}
