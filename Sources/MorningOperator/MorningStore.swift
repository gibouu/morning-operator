import Foundation
import Observation
import MorningCore
import MorningApple

enum MorningTab: String, CaseIterable, Identifiable {
    case today = "Morning", review = "Review", captures = "Notes", learn = "Learn", setup = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .review: "chart.bar.xaxis"
        case .captures: "square.and.pencil"
        case .learn: "sparkles"
        case .setup: "slider.horizontal.3"
        }
    }
}

/// Legacy derived output is optional. An unsupported model payload must not make
/// the person's valid routine and original observation impossible to restore.
private struct RecoverableObservationClassification: Codable, Sendable {
    let value: ObservationContextClassification?
    let wasInvalid: Bool
    init(_ value: ObservationContextClassification) { self.value = value; wasInvalid = false }
    init(from decoder: any Decoder) throws {
        do { value = try ObservationContextClassification(from: decoder); wasInvalid = false }
        catch { value = nil; wasInvalid = true }
    }
    func encode(to encoder: any Encoder) throws {
        if let value { try value.encode(to: encoder) }
        else { var container = encoder.singleValueContainer(); try container.encodeNil() }
    }
}

/// A damaged derived suggestion must not strand the current routine or original
/// observations. Restored proposals are also checked against live source revisions.
private struct RecoverableRoutineProposal: Codable, Sendable {
    let value: EvidenceRoutineProposal?
    let wasInvalid: Bool
    init(_ value: EvidenceRoutineProposal) { self.value = value; wasInvalid = false }
    init(from decoder: any Decoder) throws {
        do { value = try EvidenceRoutineProposal(from: decoder); wasInvalid = false }
        catch { value = nil; wasInvalid = true }
    }
    func encode(to encoder: any Encoder) throws {
        if let value { try value.encode(to: encoder) }
        else { var container = encoder.singleValueContainer(); try container.encodeNil() }
    }
}

private struct WorkspaceSnapshot: Codable, Sendable {
    var schemaVersion = 1
    var routine: RoutineVersion?
    var session: RoutineSession?
    var previousRoutine: RoutineVersion?
    var history: MorningHistory?
    var captures: [QuickCapture]?
    var receipts: [String: String]?
    var sessionTimeZone: String?
    var automatic: Bool?
    var readAloud: Bool?
    var showMorningOnLockScreen: Bool?
    var sessionTimingInterrupted: Bool?
    var budgetAndFeedback: RoutineBudgetAndFeedback?
    var pendingCaptures: [String: String]?
    var voiceIdentifier: String?
    var observationNotes: String?
    var observationSource: String?
    var observationVideoEvidence: ObservationVideoEvidence?
    var observationContextClassification: RecoverableObservationClassification?
    var observationArchive: ObservationArchive?
    var selectedObservationID: UUID?
    var pendingRoutineProposal: RecoverableRoutineProposal?
    var consumedMorningEntryIDs: [UUID]?
    var routinePreferences: RecoverableRoutinePreferences?
}

private extension WorkspaceSnapshot {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        routine = try values.decodeIfPresent(RoutineVersion.self, forKey: .routine)
        session = try values.decodeIfPresent(RoutineSession.self, forKey: .session)
        previousRoutine = try values.decodeIfPresent(RoutineVersion.self, forKey: .previousRoutine)
        history = try values.decodeIfPresent(MorningHistory.self, forKey: .history)
        captures = try values.decodeIfPresent([QuickCapture].self, forKey: .captures)
        receipts = try values.decodeIfPresent([String: String].self, forKey: .receipts)
        sessionTimeZone = try values.decodeIfPresent(String.self, forKey: .sessionTimeZone)
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic)
        readAloud = try values.decodeIfPresent(Bool.self, forKey: .readAloud)
        showMorningOnLockScreen = try values.decodeIfPresent(Bool.self, forKey: .showMorningOnLockScreen)
        sessionTimingInterrupted = try values.decodeIfPresent(Bool.self, forKey: .sessionTimingInterrupted)
        budgetAndFeedback = try values.decodeIfPresent(RoutineBudgetAndFeedback.self, forKey: .budgetAndFeedback)
        pendingCaptures = try values.decodeIfPresent([String: String].self, forKey: .pendingCaptures)
        voiceIdentifier = try values.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        observationNotes = try values.decodeIfPresent(String.self, forKey: .observationNotes)
        observationSource = try values.decodeIfPresent(String.self, forKey: .observationSource)
        observationVideoEvidence = try values.decodeIfPresent(ObservationVideoEvidence.self, forKey: .observationVideoEvidence)
        observationContextClassification = try values.decodeIfPresent(RecoverableObservationClassification.self, forKey: .observationContextClassification)
        observationArchive = try values.decodeIfPresent(ObservationArchive.self, forKey: .observationArchive)
        selectedObservationID = try values.decodeIfPresent(UUID.self, forKey: .selectedObservationID)
        pendingRoutineProposal = try values.decodeIfPresent(RecoverableRoutineProposal.self, forKey: .pendingRoutineProposal)
        consumedMorningEntryIDs = try values.decodeIfPresent([UUID].self, forKey: .consumedMorningEntryIDs)
        // Missing is an older workspace. Present-but-null is damaged saved data;
        // keep it unreadable until the user explicitly resets their choices.
        routinePreferences = values.contains(.routinePreferences)
            ? try values.decode(RecoverableRoutinePreferences.self, forKey: .routinePreferences) : nil
    }
}

@MainActor @Observable
final class MorningStore {
    var tab: MorningTab = .today
    private(set) var routine: RoutineVersion?
    private(set) var session: RoutineSession?
    private(set) var previousRoutine: RoutineVersion?
    /// Counts successful approvals in this launch, so feedback can follow each one —
    /// an approved update replaces an approved routine and leaves `isApproved` unchanged.
    private(set) var approvalCount = 0
    /// Counts mornings that began and were saved in this launch; resuming does not count.
    private(set) var morningStartCount = 0
    private(set) var notes = ""
    private(set) var observationVideoEvidence: ObservationVideoEvidence?
    private(set) var observationContextClassification: ObservationContextClassification?
    private(set) var observationSaveIssue: String?
    private(set) var observationArchive = ObservationArchive()
    private(set) var selectedObservationID: UUID?
    private(set) var pendingRoutineProposal: EvidenceRoutineProposal?
    private(set) var routinePreferences = RoutinePreferenceJournal()
    private(set) var routinePreferencesIssue: String?
    private var unreadablePreferences: RecoverableRoutinePreferences?

    var selectedObservation: ObservationAcquisition? { selectedObservationID.flatMap { observationArchive.entry(id: $0) } }
    private var observationEditsNeedSave = false
    var notice: String?
    private(set) var busy = false
    private(set) var progress = 0.0
    private(set) var analysisStatus = ""
    private(set) var observationIssue: String?
    private(set) var pendingRecordingURL: URL?
    private(set) var pendingRecordingShouldAutoProcess = false
    private var pendingRecordingInterruption: String?
    private var pendingRecordingContext: ObservationRecordingContext?
    var calendarBusy: Bool { briefing.isConnectingCalendar }
    var readAloud = true
    var automatic = true
    private(set) var showMorningOnLockScreen = false
    private(set) var morningActivityIssue: String?
    private var morningActivityIsForeground = false
    private var morningActivitySaveBlocked = false
    private var morningActivityStartSessionID: UUID?
    private var morningActivityStartRequestID: UUID?
    @ObservationIgnored private lazy var morningActivityNamespace: MorningActivityNamespace = {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return .production }
        // Use the actual isolated workspace, including the generated identifier
        // used by older tests. A test must never clean up a personal activity.
        let name = snapshot.url.deletingLastPathComponent().lastPathComponent
        let id = UUID(uuidString: String(name.dropFirst("MorningOperatorUITests-".count))) ?? UUID()
        return .testing(workspaceID: id)
    }()
    @ObservationIgnored private lazy var morningActivity = MorningLiveActivityCoordinator(
        namespace: morningActivityNamespace,
        canPublish: { [weak self] in
            guard let self, self.storageIsAvailable, self.showMorningOnLockScreen,
                  !self.morningActivitySaveBlocked,
                  let control = try? self.privacyControl.status(), !control.forgetPending else { return false }
            return true
        })
    var capturePresented = false
    var capturePrefill = ""
    var captureSource: QuickCaptureSource = .typed
    private(set) var captureBusy = false
    private(set) var history = MorningHistory()
    private(set) var captures: [QuickCapture] = []
    private(set) var receipts: [String: String] = [:]
    private(set) var pendingCaptures: [String: String] = [:]
    // Time budget, recap and feedback (#10). Change these through MorningStore+Budget.swift.
    var budgetAndFeedback = RoutineBudgetAndFeedback()
    /// The ending event of each ended run that the last successful save wrote to disk.
    private(set) var savedRunEndings: Set<UUID> = []
    func saveBudgetAndFeedback() -> Bool { persist() }
    private var sessionTimingInterrupted = false
    private var sessionTimeZone = TimeZone.current.identifier
    let reminders = ReminderService()
    @ObservationIgnored private lazy var stepExecutor = MorningAppStepExecutor(speech: speech, briefing: briefing,
        resolveObservation: { [weak self] step in
            guard let self, self.storageIsAvailable, let reference = step.observationReference,
                  !self.observationEditsNeedSave,
                  // The approved sentence, not the current interface language, selects the composition.
                  let prepared = try? ObservationNarrationComposer.resolve(reference: reference,
                      archive: self.observationArchive, approvedText: step.detail) else { return nil }
            return prepared.spokenText
        })
    @ObservationIgnored lazy var automation = MorningAutomationCoordinator(executor: stepExecutor)
    let intelligence = AppleIntelligenceService()
    let speech = SpeechCoordinator()
    let voiceCommands = MorningVoiceCommandListener()
    let invitation: MorningInvitationService
    let briefing: MorningBriefingController
    let usesSyntheticBriefing: Bool
    private(set) var consumedMorningEntryIDs: [UUID] = []
    var storageIsAvailable: Bool { snapshotRecoveryError == nil && !privacyBlocksWork }
    var voiceCommandPresented = false
    var morningDetailPresented = false
    var observationDetailPresented = false
    var observationSelectionPresented = false
    var routineProposalPresented = false
    private(set) var voiceCommandPreparing = false
    private(set) var voiceCommandFeedback: String?
    @ObservationIgnored private var voiceCommandTask: Task<Void, Never>?
    @ObservationIgnored private var voiceCommandAttempt: UUID?
    private var voiceCommandDeduplicator = MorningVoiceCommandDeduplicator()
    var captureVoicePresented = false
    private(set) var completionCapturePreparing = false
    private(set) var completionCaptureFeedback: String?
    private(set) var completionInvitationSessionID: UUID?
    private var lastCompletionOffered: UUID?
    private var savedCompletionSessionID: UUID?
    private var hasSavedCompletedSession: Bool {
        session?.status == .completed && savedCompletionSessionID == session?.id
    }
    private(set) var dismissedReflectionSessionID: UUID?
    var shouldOfferCompletionReflection: Bool {
        hasSavedCompletedSession && dismissedReflectionSessionID != session?.id
    }
    private var completionVoiceSessionID: UUID?
    private var pendingSpokenCapture: (sessionID: UUID, text: String)?
    @ObservationIgnored private var completionCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var completionCaptureAttempt: UUID?
    @ObservationIgnored private var completionInvitationPlaybackID: UUID?
    private(set) var voiceInputReleasing = false
    @ObservationIgnored private var voiceInputReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var voiceInputReleaseOwners: [Task<Void, Never>] = []
    var hasPendingSpokenCapture: Bool { pendingSpokenCapture != nil }
    var voiceInputBlocksPlayback: Bool {
        voiceCommandPreparing || completionCapturePreparing || voiceInputReleasing || voiceCommands.isBusy || voiceCommands.needsAudioRelease
    }
    private let media = MediaObservationService()
    private let fingerprintService = ObservationFileFingerprintService()
    private let contextClassifier = ObservationContextClassifier()
    private var notesSourceLabel = String(localized: "Your written observation")
    private let snapshot: AtomicJSONFile<WorkspaceSnapshot>
    private let recordingRecovery: PendingScreenRecordingStore
    @ObservationIgnored private var snapshotRecoveryError: String?
    private var analysisTask: Task<Void, Never>?
    private var analysisAttempt: UUID?
    @ObservationIgnored private var repeatTask: Task<Void, Never>?
    @ObservationIgnored private var repeatAttempt: UUID?
    private let privacyControl: LocalDataControl
    #if DEBUG
    private var privacyTestAnalysisGate: CheckedContinuation<Void, Never>?
    private(set) var privacyTestAnalysisWaiting = false
    #endif
    private(set) var dataGeneration = UUID()
    private(set) var privacyIsForgetting = false
    private(set) var privacyNeedsCleanup = false
    private(set) var privacyHasInterruptedRemoval = false
    private(set) var privacyStatus: String?
    private(set) var privacyCompletedID: UUID?
    private(set) var activityLoggingAllowed = true
    var privacyBlocksWork: Bool { privacyIsForgetting || privacyNeedsCleanup }
    var privacyInventoryIsReadable: Bool { snapshotRecoveryError == nil && !privacyBlocksWork }

    init() {
        let fixtureMode = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let directory = LocalDataControl.defaultDirectory
        privacyControl = LocalDataControl(directory: directory)
        snapshot = AtomicJSONFile(url: directory.appendingPathComponent("workspace.json"))
        recordingRecovery = PendingScreenRecordingStore(directory: directory)
        invitation = MorningInvitationService(directory: directory)
        #if DEBUG
        let testBriefing = MorningBriefingFixture.makeController(directory: directory)
        usesSyntheticBriefing = testBriefing != nil
        briefing = testBriefing ?? MorningBriefingController(directory: directory)
        #else
        usesSyntheticBriefing = false
        briefing = MorningBriefingController(directory: directory)
        #endif
        #if DEBUG
        repairPrivacyFixtureIfRequested(directory: directory)
        #endif
        defer { if !privacyBlocksWork { connectRecordingRecovery() } }
        do {
            let control = try privacyControl.status()
            if let generation = control.generation { dataGeneration = generation }
            activityLoggingAllowed = control.activityLoggingAllowed
            if control.forgetPending {
                privacyHasInterruptedRemoval = true
                privacyNeedsCleanup = true
                privacyStatus = String(localized: "Finishing the removal you requested. Saved data stays unavailable until cleanup completes.")
                return
            }
        } catch {
            privacyNeedsCleanup = true
            privacyStatus = String(localized: "The local data controls couldn't be read. Open Privacy to retry removing local data. \(error.localizedDescription)")
            return
        }
        do {
            pendingRecordingURL = try recordingRecovery.recover()
            if pendingRecordingURL != nil {
                observationIssue = String(localized: "Your saved recording is still on this device. Retry understanding it, or discard it.")
                do {
                    let metadata = try recordingRecovery.recoveredMetadata()
                    pendingRecordingInterruption = metadata?.interruptionNote
                    pendingRecordingContext = metadata?.recordingContext
                }
                catch {
                    observationIssue = String(localized: "Your recording is kept on this device, but its saved information could not be read. It has not been analyzed or discarded. \(error.localizedDescription)")
                }
            }
        } catch {
            observationIssue = String(localized: "Recording recovery needs attention: \(error.localizedDescription)")
        }
        let seedFixture = fixtureMode && !ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-workspace")
        if seedFixture && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path) {
            routine = DemoFixtures.candidateRoutine
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-ten-moments") {
                let titles = ["Your morning", "The weather", "Today's calendar", "Your reminders", "People and messages",
                              "A little reading", "Make some tea", "A moment to move", "A little time to play", "One thought for later"]
                let kinds: [StepKind] = [.briefing, .briefing, .calendar, .custom, .messages,
                                         .entertainment, .custom, .wellbeing, .entertainment, .custom]
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic ten-moment morning", steps:
                    titles.enumerated().map { index, title in
                        RoutineStep(title: title, detail: "Synthetic layout example.",
                                    kind: kinds[index], durationMinutes: 2)
                    })
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-approved") { routine = routine?.approved() }
            automatic = false
            readAloud = false
            seedObservationArchiveIfRequested()
            #if DEBUG
            seedPrivacyFixtureIfRequested(directory: directory)
            if let archive = ObservationReviewUITestFixture.archive(directory: directory) {
                observationArchive = archive
            }
            #endif
        } else if FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path) {
            do {
                let saved = try snapshot.load()
                guard saved.schemaVersion == 1 else {
                    snapshotRecoveryError = String(localized: "This saved routine uses a newer format. Your file has been kept intact.")
                    notice = snapshotRecoveryError
                    return
                }
                routine = saved.routine
                session = saved.session
                savedCompletionSessionID = saved.session?.status == .completed ? saved.session?.id : nil
                previousRoutine = saved.previousRoutine
                if let stored = saved.routinePreferences {
                    if let value = stored.value { routinePreferences = value }
                    else {
                        unreadablePreferences = stored
                        routinePreferencesIssue = String(localized: "Your saved choices couldn't be read. Your routine and observations are intact. Reset saved choices in Review before making new suggestions.")
                    }
                } else {
                    // Only established personal required steps migrate. Durations,
                    // missing activities and demonstration rituals are not inferred choices.
                    do {
                        if let routine, !routine.isSynthetic {
                            for step in routine.steps where step.isRequired {
                                try routinePreferences.upsert(RoutinePreference(target: step, presence: .keep))
                            }
                        }
                    } catch {
                        unreadablePreferences = .init(unreadable: String(localized: "Legacy required choices need explicit repair."))
                        routinePreferencesIssue = String(localized: "Your previous choices need review. Your routine is intact. Reset saved choices before making new suggestions.")
                    }
                }
                history = saved.history ?? MorningHistory()
                budgetAndFeedback = (saved.budgetAndFeedback ?? RoutineBudgetAndFeedback()).droppingAcceptance(unlessFor: routine)
                savedRunEndings = runEndingsInMemory
                captures = saved.captures ?? []
                receipts = saved.receipts ?? [:]
                sessionTimeZone = saved.sessionTimeZone ?? TimeZone.current.identifier
                automatic = saved.automatic ?? true
                readAloud = saved.readAloud ?? true
                showMorningOnLockScreen = saved.showMorningOnLockScreen ?? false
                speech.voiceIdentifier = saved.voiceIdentifier
                if let archive = saved.observationArchive {
                    observationArchive = archive
                    projectObservation(saved.selectedObservationID.flatMap { archive.entry(id: $0)?.id })
                } else {
                    // Old builds retained a single observation with no wall-clock
                    // metadata. Migration deliberately leaves both dates unknown.
                    let original = saved.observationNotes ?? ""
                    if !original.isEmpty || saved.observationVideoEvidence != nil {
                        // Stable legacy marker: this unknown-kind entry is classified by it later.
                        let source = saved.observationSource ?? ObservationAcquisition.legacyWrittenSourceLabel
                        let entry = try ObservationAcquisition(importedAt: nil,
                            sourceKind: saved.observationVideoEvidence == nil ? .unknown : .video,
                            sourceLabel: String(source.prefix(256)), originalText: original,
                            videoEvidence: saved.observationVideoEvidence,
                            classification: saved.observationContextClassification?.value,
                            warnings: saved.observationContextClassification?.wasInvalid == true ? [.invalidClassificationRemoved] : [])
                        let id = try observationArchive.insert(entry)
                        projectObservation(id)
                    }
                }
                let restorationWarnings = Set(observationArchive.entries.flatMap(\.warnings) +
                    (saved.observationContextClassification?.wasInvalid == true ? [.invalidClassificationRemoved] : []))
                if !restorationWarnings.isEmpty {
                    notice = restorationWarnings.sorted { $0.rawValue < $1.rawValue }.map(\.message).joined(separator: " ")
                }
                if routinePreferencesIssue == nil, let proposal = saved.pendingRoutineProposal?.value,
                   proposal.isCurrent(archive: observationArchive, baseRoutine: routine, preferences: routinePreferences) {
                    pendingRoutineProposal = proposal
                } else if saved.pendingRoutineProposal != nil {
                    notice = String(localized: "A saved suggestion no longer matches its sources or routine. Your current morning and observations are intact. Choose mornings to suggest a fresh update.")
                }
                sessionTimingInterrupted = saved.sessionTimingInterrupted ?? false
                pendingCaptures = saved.pendingCaptures ?? [:]
                consumedMorningEntryIDs = saved.consumedMorningEntryIDs ?? []
                if !pendingCaptures.isEmpty { notice = String(localized: "A previous Apple app save was interrupted. Check Calendar or Reminders before adding that item again.") }
                if session?.status == .running {
                    sessionTimingInterrupted = true
                    try session?.pause()
                    notice = String(localized: "Your previous morning is paused. Resume when you're ready.")
                    persist()
                }
                if saved.observationArchive == nil, !observationArchive.entries.isEmpty {
                    // Save the migration once so its acquisition identity survives
                    // another launch. A write failure leaves the original intact.
                    persist()
                }
            } catch {
                let message = String(localized: "Couldn't restore your saved workspace: \(error.localizedDescription)")
                snapshotRecoveryError = message
                notice = String(localized: "\(message) Your existing file is protected from changes.")
            }
        }
    }

    /// Unsaved typed notes have no archive entry yet and are never imported evidence.
    var hasImportedObservation: Bool { selectedObservation?.isImportedEvidence ?? false }
    var hasPendingRecording: Bool { pendingRecordingURL != nil }
    var canStartRecording: Bool { storageIsAvailable && !busy && !sessionActive && !hasPendingRecording }

    var totalMinutes: Int { routine?.steps.reduce(0) { $0 + $1.durationMinutes } ?? 0 }
    var stateLabel: String { session?.status.rawValue ?? (routine?.isApproved == true ? "ready" : "review") }
    var currentStep: RoutineStep? { session?.currentStep }
    var sessionActive: Bool { session?.status == .running || session?.status == .paused }
    var modelSummary: String { intelligence.capabilitySummary }

    var morningActivityStatusText: String {
        if let morningActivityIssue { return morningActivityIssue }
        if !showMorningOnLockScreen { return String(localized: "Off. Your morning stays inside MORE.") }
        if !morningActivity.authorizationEnabled { return String(localized: "Live Activities are unavailable or turned off in iPhone Settings.") }
        if morningActivity.status == .failed { return String(localized: "Lock Screen progress couldn't update. Turn it off and on to try again.") }
        if morningActivity.status == .dismissed { return String(localized: "Hidden from the Lock Screen. Your morning is still in MORE.") }
        if morningActivity.status == .stale { return String(localized: "Progress may be out of date. Open Morning to check.") }
        if let state = morningActivity.currentSnapshot?.state {
            return String(localized: "\(state.status.displayName) · Moment \(state.completedSteps + 1) of \(state.totalSteps)")
        }
        return String(localized: "Ready for the next morning you start.")
    }

    #if DEBUG
    var morningActivityTestNamespace: MorningActivityNamespace? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"), args.contains("--ui-testing-live-activity"),
              let value = args.first(where: { $0.hasPrefix("--ui-testing-workspace=") }),
              let id = UUID(uuidString: String(value.dropFirst("--ui-testing-workspace=".count))),
              snapshot.url.deletingLastPathComponent().lastPathComponent == "MorningOperatorUITests-\(id.uuidString)"
        else { return nil }
        return .testing(workspaceID: id)
    }
    #endif

    func setMorningOnLockScreen(_ enabled: Bool) {
        guard storageIsAvailable else { return }
        let previous = showMorningOnLockScreen
        showMorningOnLockScreen = enabled
        guard persist() else { showMorningOnLockScreen = previous; return }
        if !enabled { morningActivityStartSessionID = nil; morningActivityStartRequestID = nil }
        synchronizeMorningActivity(allowStart: enabled)
    }

    func morningActivitySceneChanged(isForeground: Bool) {
        morningActivityIsForeground = isForeground
        synchronizeMorningActivity()
    }

    /// The Live Activity only projects the accepted session; it cannot advance,
    /// approve, record, speak or modify that session. Every payload is vocabulary
    /// owned by the app, never a user's routine title or captured source content.
    func synchronizeMorningActivity(allowStart: Bool = false) {
        if allowStart { morningActivityStartSessionID = session?.id; morningActivityStartRequestID = UUID() }
        if !sessionActive { morningActivityStartSessionID = nil; morningActivityStartRequestID = nil }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let enabled = self.showMorningOnLockScreen && self.storageIsAvailable && !self.morningActivitySaveBlocked
            let snapshot = MorningActivityProjection.snapshot(session: self.session,
                needsAttention: self.automation.status != .executing)
            let generation = self.dataGeneration
            do {
                try await self.morningActivity.synchronize(snapshot: snapshot, enabled: enabled,
                    isForeground: self.morningActivityIsForeground,
                    allowStart: self.morningActivityStartSessionID != nil && self.morningActivityStartSessionID == self.session?.id,
                    startRequestID: self.morningActivityStartRequestID)
                guard self.dataGeneration == generation else { return }
                self.morningActivityIssue = nil
            } catch {
                guard self.dataGeneration == generation else { return }
                self.morningActivityIssue = String(localized: "Lock Screen progress couldn't update. Open MORE to check your morning.")
            }
        }
    }

    /// Deterministic UI journeys are confined to explicitly isolated synthetic
    /// workspaces. Normal launches never replace an unavailable Apple model.
    var usesSyntheticProposalFixture: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--ui-testing-evidence-proposals") &&
            arguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") })
                .flatMap { UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) } != nil
    }
    var canSuggestSavedObservations: Bool { routinePreferencesIssue == nil && (intelligence.isAvailable || usesSyntheticProposalFixture) }

    func loadSample() {
        guard !privacyBlocksWork else { return }
        guard !sessionActive, !busy else {
            notice = String(localized: "Finish or stop this morning before changing the routine.")
            return
        }
        installCandidate(PhoneMorningSample.routine())
        tab = .today
        notice = String(localized: "Sample routine loaded. Review and edit it before starting. This is demo data, not learned behavior.")
        persist()
    }

    @discardableResult
    func approve() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard let routine, !busy, !sessionActive else { return false }
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        guard !routine.steps.isEmpty else { notice = String(localized: "Add at least one step before approving."); return false }
        let savedPrevious = previousRoutine
        let savedSession = session
        self.routine = routine.approved()
        previousRoutine = nil
        session = self.routine.map { RoutineSession(routine: $0) }
        notice = String(localized: "Routine approved. You're ready for your first morning.")
        guard persist() else {
            self.routine = routine
            previousRoutine = savedPrevious
            session = savedSession
            return false
        }
        approvalCount += 1
        return true
    }

    @discardableResult
    func updateSteps(_ steps: [RoutineStep]) -> Bool {
        guard !privacyBlocksWork else { return false }
        return saveRoutineEdit(steps: steps, preferences: routinePreferences)
    }

    /// Commit one completed drag using the identities captured at drag start.
    /// Moving down lands after the target; moving up lands before it.
    @discardableResult
    func moveStep(_ sourceID: UUID, onto targetID: UUID,
                  expectedRoutineID: UUID, expectedGeneration: UUID) -> Bool {
        guard let current = routine,
              let source = current.steps.firstIndex(where: { $0.id == sourceID }),
              let target = current.steps.firstIndex(where: { $0.id == targetID }) else { return false }
        var orderedIDs = current.steps.map(\.id)
        let moved = orderedIDs.remove(at: source)
        orderedIDs.insert(moved, at: target)
        return reorderSteps(orderedIDs, expectedRoutineID: expectedRoutineID, expectedGeneration: expectedGeneration)
    }

    /// The native reorder control supplies only an exact permutation. Step values
    /// come from the current routine; a drag cannot replace content or approval.
    @discardableResult
    func reorderSteps(_ orderedIDs: [UUID], expectedRoutineID: UUID, expectedGeneration: UUID) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive,
              dataGeneration == expectedGeneration,
              let current = routine, current.id == expectedRoutineID,
              current.number >= 1, current.number < Int.max else { return false }
        let currentIDs = current.steps.map(\.id)
        guard Set(currentIDs).count == currentIDs.count,
              orderedIDs.count == currentIDs.count,
              Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == Set(currentIDs) else { return false }
        guard orderedIDs != currentIDs else { return true }
        let byID = Dictionary(uniqueKeysWithValues: current.steps.map { ($0.id, $0) })
        let steps = orderedIDs.compactMap { byID[$0] }
        guard steps.count == current.steps.count else { return false }
        // The common edit transaction preserves an approved predecessor,
        // invalidates pending proposals, and rolls all routine state back if saving fails.
        return saveRoutineEdit(steps: steps, preferences: routinePreferences)
    }

    func savedPreference(for step: RoutineStep) -> RoutinePreference? {
        try? routinePreferences.matchingPreference(for: step)
    }

    @discardableResult
    func saveStep(_ edited: RoutineStep, keepInSuggestions: Bool, keepDuration: Bool) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        do {
            var preferences = routinePreferences
            // A model row can have a fresh ID matched to an older saved title.
            // Resolve its standing choice before a rename/category edit changes that key.
            let original = routine?.steps.first { $0.id == edited.id } ?? edited
            if let previous = try preferences.matchingPreference(for: original) { preferences.remove(targetID: previous.targetID) }
            preferences.remove(targetID: edited.id)
            var step = edited
            step.isRequired = keepInSuggestions
            if keepInSuggestions || keepDuration {
                try preferences.upsert(RoutinePreference(target: step,
                    presence: keepInSuggestions ? .keep : nil,
                    durationMinutes: keepDuration ? step.durationMinutes : nil))
            }
            var steps = routine?.steps ?? []
            if let index = steps.firstIndex(where: { $0.id == step.id }) { steps[index] = step }
            else { steps.append(step) }
            return saveRoutineEdit(steps: steps, preferences: preferences)
        } catch { notice = error.localizedDescription; return false }
    }

    @discardableResult
    func removeStep(_ step: RoutineStep, excludeFromSuggestions: Bool) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        do {
            var preferences = routinePreferences
            if excludeFromSuggestions {
                if let old = try preferences.matchingPreference(for: step) { preferences.remove(targetID: old.targetID) }
                try preferences.upsert(RoutinePreference(target: step, presence: .exclude))
            }
            // Removing only this draft leaves standing future choices intact.
            return saveRoutineEdit(steps: (routine?.steps ?? []).filter { $0.id != step.id }, preferences: preferences)
        } catch { notice = error.localizedDescription; return false }
    }

    @discardableResult
    func clearRoutinePreference(targetID: UUID) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, !sessionActive, routinePreferencesIssue == nil else { return false }
        let old = routinePreferences
        let oldProposal = pendingRoutineProposal
        guard routinePreferences.remove(targetID: targetID) else { return true }
        pendingRoutineProposal = nil
        guard persist() else { routinePreferences = old; pendingRoutineProposal = oldProposal; return false }
        notice = String(localized: "Saved choice cleared. Your current routine is unchanged; future suggestions can reconsider it.")
        return true
    }

    @discardableResult
    func resetUnreadableRoutinePreferences() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, !sessionActive, routinePreferencesIssue != nil else { return false }
        let old = unreadablePreferences
        let oldIssue = routinePreferencesIssue
        let oldJournal = routinePreferences
        let oldProposal = pendingRoutineProposal
        unreadablePreferences = nil
        routinePreferencesIssue = nil
        routinePreferences = .init()
        pendingRoutineProposal = nil
        guard persist() else {
            unreadablePreferences = old; routinePreferencesIssue = oldIssue
            routinePreferences = oldJournal; pendingRoutineProposal = oldProposal
            return false
        }
        notice = String(localized: "Saved choices reset. Your routine and observations are unchanged.")
        return true
    }

    private func saveRoutineEdit(steps: [RoutineStep], preferences: RoutinePreferenceJournal,
                                 sourceLabel: String? = nil) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard let oldRoutine = routine, !sessionActive, !busy, storageIsAvailable else { return false }
        let oldPrevious = previousRoutine
        let oldSession = session
        let oldPreferences = routinePreferences
        let oldProposal = pendingRoutineProposal
        if oldRoutine.isApproved { previousRoutine = oldRoutine }
        routine = oldRoutine.revised(steps: steps, sourceLabel: sourceLabel ?? oldRoutine.sourceLabel)
        session = nil
        routinePreferences = preferences
        pendingRoutineProposal = nil
        guard persist() else {
            routine = oldRoutine; previousRoutine = oldPrevious; session = oldSession
            routinePreferences = oldPreferences; pendingRoutineProposal = oldProposal
            return false
        }
        notice = String(localized: "Changes saved as a new draft. Review and approve when ready.")
        return true
    }

    @discardableResult
    func start(entryID: UUID? = nil) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard let routine, !busy, !voiceInputBlocksPlayback, !captureVoicePresented, !hasPendingSpokenCapture else { return false }
        if let entryID, consumedMorningEntryIDs.contains(entryID) { return false }
        // Revealing an already running morning must not dispatch its speech again.
        if session?.status == .running { return true }
        discardCompletionReflection()
        let previousEntryIDs = consumedMorningEntryIDs
        let beginsMorning = session?.status != .paused
        do {
            if session?.status == .paused { try session?.resume() }
            else if session?.status != .running {
                archiveTerminalSession()
                sessionTimeZone = TimeZone.current.identifier
                sessionTimingInterrupted = false
                session = RoutineSession(routine: routine)
                try session?.start()
            }
            notice = nil
            if let entryID { rememberMorningEntry(entryID) }
            guard persist() else {
                consumedMorningEntryIDs = previousEntryIDs
                pauseAfterSaveFailure()
                return false
            }
            if beginsMorning { morningStartCount += 1 }
            runCurrentIfEnabled()
            synchronizeMorningActivity(allowStart: true)
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    /// This receipt and a starting/resuming transition share workspace.json. A
    /// notification's separate durable consumption is intentionally at-most-once:
    /// if a save fails after consumption, the person uses the ordinary Start button.
    @discardableResult
    func handleMorningEntry(_ request: MorningEntryRequest, destination: MorningEntryDestination) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard destination != .wait else { return false }
        if destination == .start || destination == .resume { return start(entryID: request.id) }
        guard !consumedMorningEntryIDs.contains(request.id), storageIsAvailable else { return true }
        let previous = consumedMorningEntryIDs
        rememberMorningEntry(request.id)
        guard persist() else { consumedMorningEntryIDs = previous; return false }
        return true
    }

    private func rememberMorningEntry(_ id: UUID) {
        consumedMorningEntryIDs = Array((consumedMorningEntryIDs + [id]).suffix(64))
    }

    func pause() {
        guard !privacyBlocksWork else { return }
        cancelVoiceCommandTurn()
        cancelStepPlayback()
        do { try session?.pause(); speech.stop(); notice = nil; persist() }
        catch { notice = error.localizedDescription }
    }

    func resume() {
        guard !privacyBlocksWork else { return }
        guard !voiceInputBlocksPlayback else { return }
        do {
            try session?.resume(); notice = nil
            guard persist() else { pauseAfterSaveFailure(); return }
            runCurrentIfEnabled()
            synchronizeMorningActivity(allowStart: true)
        }
        catch { notice = error.localizedDescription }
    }

    func advance(skipping: Bool = false, commandID: UUID = UUID()) {
        guard !privacyBlocksWork else { return }
        guard !voiceInputBlocksPlayback else { return }
        cancelStepPlayback()
        do {
            try session?.advance(skipping: skipping, commandID: commandID)
            speech.stop()
            notice = nil
            if session?.status == .completed {
                notice = String(localized: "Morning complete. Your progress is saved on this device.")
            }
            archiveTerminalSession()
            guard persist() else { pauseAfterSaveFailure(); return }
            if session?.status == .completed { queueCompletionInvitation() }
            else { runCurrentIfEnabled() }
        } catch { notice = error.localizedDescription }
    }

    func stop() {
        guard !privacyBlocksWork else { return }
        cancelVoiceCommandTurn()
        cancelStepPlayback()
        speech.stop()
        do { try session?.stop(); archiveTerminalSession(); notice = nil; persist() }
        catch { notice = error.localizedDescription }
    }

    /// Reading again never advances the session. A sourced moment reuses its
    /// pinned text, while a moment not yet prepared goes through freshness checks.
    func readCurrent() {
        guard !privacyBlocksWork, !voiceInputBlocksPlayback,
              let session, let step = currentStep else { return }
        cancelStepPlayback()
        if step.automation == nil {
            speech.speak("\(step.title). \(step.detail)")
            return
        }
        let attempt = UUID()
        repeatAttempt = attempt
        let context = MorningStepContext(executionID: .init(sessionID: session.id,
            routineVersionID: session.routine.id, stepID: step.id))
        stepExecutor.spokenEnabled = true
        repeatTask = Task { [weak self] in
            guard let self else { return }
            defer { if repeatAttempt == attempt { repeatTask = nil; repeatAttempt = nil } }
            do {
                let outcome = try await stepExecutor.execute(step: step, context: context)
                guard repeatAttempt == attempt, !Task.isCancelled, !privacyBlocksWork else { return }
                switch outcome {
                case .completed: break
                case .needsUser(let reason), .unavailable(let reason): notice = reason
                }
            } catch {
                guard repeatAttempt == attempt, !Task.isCancelled, !privacyBlocksWork else { return }
                notice = error.localizedDescription
            }
        }
    }

    private func cancelStepPlayback() {
        repeatAttempt = nil
        repeatTask?.cancel(); repeatTask = nil
        automation.cancel()
        stepExecutor.cancelPlayback()
    }

    func preparedBriefing(for step: RoutineStep) -> PreparedMorningBriefing? {
        guard !privacyBlocksWork, let session,
              stepExecutor.pinnedExecutionID == MorningExecutionID(sessionID: session.id,
                routineVersionID: session.routine.id, stepID: step.id) else { return nil }
        return stepExecutor.pinnedBriefing
    }

    func updateCurrentBriefing() {
        guard !privacyBlocksWork, !voiceInputBlocksPlayback, session?.status == .paused,
              let operation = currentStep?.automation,
              operation == .todayCalendar || operation == .morningBriefing else { return }
        cancelStepPlayback()
        stepExecutor.clear()
        briefing.cancelAndClear()
        readCurrent()
    }

    func prepareDayIfConfigured() async {
        guard !privacyBlocksWork,
              !briefing.settings.calendarIDs.isEmpty || briefing.settings.weatherLocation != nil else { return }
        _ = await briefing.refresh()
    }

    @discardableResult
    func addBriefingToRoutine() -> Bool {
        guard let routine, !sessionActive, !privacyBlocksWork else { return false }
        if routine.steps.contains(where: { $0.automation == .morningBriefing }) { return true }
        let step = RoutineStep(title: String(localized: "Your day"), detail: String(localized: "Hear your selected calendar and current weather."),
            kind: .briefing, durationMinutes: 2, automation: .morningBriefing)
        return updateSteps([step] + routine.steps)
    }

    /// Adds only a user-selected, still-current quotation. This is a new draft,
    /// never permission for the model to execute an inferred external action.
    @discardableResult
    func addObservationNarration(_ prepared: PreparedObservationNarration) -> Bool {
        guard storageIsAvailable, !busy, !sessionActive, saveObservationEdits() else { return false }
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        guard let current = try? ObservationNarrationComposer.resolve(reference: prepared.reference, archive: observationArchive),
              current.spokenText.utf8.elementsEqual(prepared.spokenText.utf8) else {
            notice = String(localized: "This observation changed. Choose the excerpt again before adding it.")
            return false
        }
        guard (routine?.steps.count ?? 0) < 10 else {
            notice = String(localized: "Your morning has ten moments. Remove one in Review before adding another.")
            return false
        }
        if routine?.steps.contains(where: { $0.automation == .savedObservation && $0.observationReference == prepared.reference }) == true {
            notice = String(localized: "This excerpt is already in your morning.")
            return false
        }
        let step = RoutineStep(title: String(localized: "A saved moment"), detail: current.spokenText,
            kind: .briefing, durationMinutes: 1, automation: .savedObservation,
            observationReference: current.reference)
        let containsSample = observationArchive.entry(id: current.reference.acquisitionID)?.origin == .synthetic
        let sourceLabel = containsSample ? String(localized: "Demo fixture — includes a synthetic saved observation") : nil
        if let routine {
            return saveRoutineEdit(steps: [step] + routine.steps, preferences: routinePreferences, sourceLabel: sourceLabel)
        }
        let oldSession = session
        let oldProposal = pendingRoutineProposal
        self.routine = RoutineVersion(sourceLabel: sourceLabel ?? String(localized: "Your selected saved observation"), steps: [step])
        session = nil
        pendingRoutineProposal = nil
        guard persist() else {
            self.routine = nil; session = oldSession; pendingRoutineProposal = oldProposal
            return false
        }
        notice = String(localized: "Saved as a new draft. Review and approve when ready.")
        return true
    }

    func previewObservationNarration(_ prepared: PreparedObservationNarration) -> UUID? {
        guard storageIsAvailable, !busy, !sessionActive, !voiceInputBlocksPlayback,
              speech.state == .idle, saveObservationEdits(),
              let current = try? ObservationNarrationComposer.resolve(reference: prepared.reference, archive: observationArchive),
              current.spokenText.utf8.elementsEqual(prepared.spokenText.utf8) else { return nil }
        speech.speak(current.spokenText)
        return speech.playbackID
    }

    func stopObservationPreview(_ id: UUID?) {
        guard let id, speech.playbackID == id else { return }
        speech.stop()
    }

    func openVoiceCommands() {
        guard !privacyBlocksWork else { return }
        guard sessionActive else { return }
        if session?.status == .running { pause() }
        voiceCommandFeedback = nil
        voiceCommandPresented = true
    }

    private var voiceContext: MorningVoiceCommandContext? {
        guard sessionActive, let session, let step = session.currentStep else { return nil }
        return .init(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
    }

    func listenForCommand(language: MorningVoiceCommandLanguage) {
        guard !privacyBlocksWork else { return }
        guard !voiceInputBlocksPlayback, session?.status == .paused, let context = voiceContext else { return }
        voiceCommandPreparing = true
        voiceCommandFeedback = nil
        let attempt = UUID()
        voiceCommandAttempt = attempt
        voiceCommandTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if voiceCommandAttempt == attempt {
                    voiceCommandPreparing = false
                    voiceCommandAttempt = nil
                    voiceCommandTask = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await speech.stopAndRelease()
                try Task.checkCancellation()
                guard voiceContext == context else { throw CancellationError() }
                let result = try await voiceCommands.listen(context: context, language: language)
                try Task.checkCancellation()
                guard let current = voiceContext,
                      let command = voiceCommandDeduplicator.consume(result, currentContext: current),
                      !voiceCommands.isBusy, !voiceCommands.needsAudioRelease else { throw CancellationError() }
                // Mic release is confirmed before any command can request new speech.
                voiceCommandPreparing = false
                try session?.applyVoiceCommand(command: command, commandID: result.id)
                archiveTerminalSession()
                guard persist() else { pauseAfterSaveFailure(); return }
                if command == .resume { synchronizeMorningActivity(allowStart: true) }
                voiceCommandFeedback = String(localized: "Heard: \(result.transcript)")
                voiceCommandPresented = false
                if session?.status == .completed { queueCompletionInvitation() }
                if command == .repeatStep { readCurrent() }
                else if session?.status == .running { runCurrentIfEnabled() }
            } catch {
                guard voiceCommandAttempt == attempt else { return }
                voiceCommandFeedback = error is CancellationError
                    ? String(localized: "Listening stopped. Your morning is still paused.") : error.localizedDescription
            }
        }
    }

    func cancelVoiceCommandTurn() {
        guard voiceCommandTask != nil || voiceCommandPreparing || voiceCommands.needsAudioRelease else { return }
        let owner = voiceCommandTask
        owner?.cancel()
        releaseVoiceInput(after: owner)
        voiceCommandTask = nil
        voiceCommandAttempt = nil; voiceCommandPreparing = false
    }

    /// A shared release barrier prevents a queued old cancellation from taking
    /// ownership of a newer command or capture turn.
    private func releaseVoiceInput(after owner: Task<Void, Never>? = nil) {
        if let owner { voiceInputReleaseOwners.append(owner) }
        guard voiceInputReleaseTask == nil else { return }
        voiceInputReleasing = true
        voiceInputReleaseTask = Task { [weak self] in
            guard let self else { return }
            defer { voiceInputReleasing = false; voiceInputReleaseTask = nil }
            do { try await voiceCommands.cancel() }
            catch {
                notice = error.localizedDescription
                voiceCommandFeedback = error.localizedDescription
                completionCaptureFeedback = error.localizedDescription
            }
            // A canceled owner may still be returning from a permission or
            // activation continuation. It must settle before a new turn starts.
            while !voiceInputReleaseOwners.isEmpty {
                let owners = voiceInputReleaseOwners
                voiceInputReleaseOwners.removeAll()
                for owner in owners { await owner.value }
            }
        }
    }

    /// Called only after the completion transition has been saved successfully.
    /// Restoring a completed session never queues speech or microphone access.
    private func queueCompletionInvitation() {
        guard hasSavedCompletedSession, let session, lastCompletionOffered != session.id else { return }
        lastCompletionOffered = session.id
        dismissedReflectionSessionID = nil
        completionInvitationSessionID = session.id
    }

    func speakQueuedCompletionInvitation() {
        guard !privacyBlocksWork else { return }
        guard let id = completionInvitationSessionID else { return }
        completionInvitationSessionID = nil
        guard readAloud, hasSavedCompletedSession, session?.id == id,
              !voiceInputBlocksPlayback, !capturePresented, !captureVoicePresented else { return }
        let french = speech.selectedVoice?.language.hasPrefix("fr") == true
        speech.speak(french
            ? "Votre matinée est terminée. Y a-t-il une pensée, un rêve ou un rappel que vous aimeriez garder ? Touchez Parler quand vous voulez."
            : "Your morning is complete. Is there a thought, a dream or a reminder you'd like to keep? Tap Speak whenever you're ready.")
        completionInvitationPlaybackID = speech.playbackID
    }

    func stopCompletionInvitation() {
        if let id = completionInvitationPlaybackID, speech.playbackID == id { speech.stop() }
        completionInvitationPlaybackID = nil
    }

    func openCompletionCapture() {
        guard !privacyBlocksWork else { return }
        guard hasSavedCompletedSession, storageIsAvailable, !busy,
              !capturePresented, !voiceInputBlocksPlayback, !voiceCommandPresented else { return }
        completionInvitationSessionID = nil
        stopCompletionInvitation()
        completionVoiceSessionID = session?.id
        completionCaptureFeedback = nil
        pendingSpokenCapture = nil
        captureVoicePresented = true
    }

    func listenForCompletionCapture(language: MorningVoiceCommandLanguage) {
        guard !privacyBlocksWork else { return }
        guard captureVoicePresented, !voiceInputBlocksPlayback,
              let id = completionVoiceSessionID, session?.id == id, session?.status == .completed else { return }
        let attempt = UUID()
        completionCaptureAttempt = attempt
        completionCapturePreparing = true
        completionCaptureFeedback = nil
        completionCaptureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if completionCaptureAttempt == attempt {
                    completionCapturePreparing = false
                    completionCaptureAttempt = nil
                    completionCaptureTask = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await speech.stopAndRelease()
                try Task.checkCancellation()
                guard captureVoicePresented, completionCaptureAttempt == attempt,
                      completionVoiceSessionID == id, session?.id == id, session?.status == .completed else { throw CancellationError() }
                let text: String
                #if DEBUG
                if let sample = completionCaptureTestSample {
                    // Synthetic UI handoff evidence only; never a microphone pass.
                    // The late fixture deliberately returns after cancellation so
                    // the real ownership guards below must reject it.
                    await withCheckedContinuation { continuation in
                        Task.detached {
                            try? await Task.sleep(for: .seconds(sample.delay))
                            continuation.resume()
                        }
                    }
                    var turn = MorningCaptureTurn()
                    guard let accepted = try turn.accept(transcript: sample.text, isFinal: true) else { throw CancellationError() }
                    text = accepted
                } else { text = try await voiceCommands.dictate(language: language) }
                #else
                text = try await voiceCommands.dictate(language: language)
                #endif
                try Task.checkCancellation()
                guard captureVoicePresented, completionCaptureAttempt == attempt,
                      completionVoiceSessionID == id, session?.id == id, session?.status == .completed,
                      !voiceCommands.isBusy, !voiceCommands.needsAudioRelease else { throw CancellationError() }
                pendingSpokenCapture = (id, text)
                captureVoicePresented = false
            } catch {
                guard completionCaptureAttempt == attempt else { return }
                completionCaptureFeedback = error is CancellationError
                    ? String(localized: "Listening stopped. Nothing was saved.") : error.localizedDescription
            }
        }
    }

    /// Called after the voice sheet has actually left the screen. A canceled,
    /// backgrounded or superseded turn cannot open another sheet with stale text.
    func completionCaptureDismissed(allowReview: Bool) {
        let pending = pendingSpokenCapture
        cancelCompletionCapture()
        guard allowReview, let pending, session?.id == pending.sessionID,
              session?.status == .completed, !voiceCommands.isBusy, !voiceCommands.needsAudioRelease,
              !capturePresented else { return }
        openCapture(text: pending.text, source: .voice)
    }

    func retryCompletionAudioRelease() {
        guard captureVoicePresented, !completionCapturePreparing, !voiceCommands.isBusy,
              voiceCommands.needsAudioRelease else { return }
        releaseVoiceInput()
    }

    func cancelCompletionCapture() {
        let owned = completionCaptureAttempt != nil || completionCapturePreparing
        let owner = completionCaptureTask
        owner?.cancel()
        if owned || voiceCommands.needsAudioRelease { releaseVoiceInput(after: owner) }
        completionCaptureAttempt = nil
        completionCaptureTask = nil
        completionCapturePreparing = false
        completionVoiceSessionID = nil
        pendingSpokenCapture = nil
    }

    func discardCompletionReflection() {
        if session?.status == .completed { dismissedReflectionSessionID = session?.id }
        completionInvitationSessionID = nil
        stopCompletionInvitation()
        cancelCompletionCapture()
        captureVoicePresented = false
    }

    func completionSessionChanged() {
        let current = session?.status == .completed ? session?.id : nil
        if completionInvitationSessionID != current { completionInvitationSessionID = nil; stopCompletionInvitation() }
        if let expected = completionVoiceSessionID, expected != current { discardCompletionReflection() }
    }

    #if DEBUG
    private var completionCaptureTestSample: (text: String, delay: Double)? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"),
              let workspace = args.first(where: { $0.hasPrefix("--ui-testing-workspace=") }),
              UUID(uuidString: String(workspace.dropFirst("--ui-testing-workspace=".count))) != nil else { return nil }
        if args.contains("--ui-testing-capture-late") {
            return ("I dreamed of a blue garden. SYNTHETIC_LATE_CAPTURE", 5)
        }
        if args.contains("--ui-testing-capture-dream") {
            return ("I dreamed of a blue garden. SYNTHETIC_VOICE_CAPTURE", 1)
        }
        return nil
    }
    var usesSyntheticCompletionCapture: Bool { completionCaptureTestSample != nil }
    #else
    var usesSyntheticCompletionCapture: Bool { false }
    #endif

    func refreshCapabilities() { intelligence.refreshCapabilities() }

    /// Written notes and ordinary imports have no inferred observed day or origin.
    /// The UI can present the existing provenance editor after preparation succeeds.
    var currentObservationNeedsProvenance: Bool {
        guard let entry = selectedObservation else {
            return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return entry.observedDate == nil || entry.origin == .unknown
    }

    /// Preliminary requirements for the selected source. Evidence and input-budget
    /// validation still run through the shared preparation policy before inference.
    var currentObservationSuggestionIssue: String? {
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Add notes or import a readable observation before suggesting a routine.")
        }
        guard let entry = selectedObservation else {
            return String(localized: "Save this observation before suggesting a routine.")
        }
        if entry.observedDate == nil {
            return String(localized: "Confirm the observed day before using this observation. Import time doesn't establish when it happened.")
        }
        if entry.origin == .unknown {
            return String(localized: "Confirm whether this observation is your morning or a sample before using it.")
        }
        if entry.origin == .automated {
            return String(localized: "Automated observations aren't used to suggest a personal morning. Choose your own observation or a separate sample.")
        }
        return nil
    }

    /// Saves the current notes and materializes a manual acquisition if needed.
    /// This performs no inference and never changes a routine, session or provenance.
    @discardableResult
    func prepareCurrentObservationForSuggestion() -> Bool {
        guard !busy, !sessionActive, storageIsAvailable else { return false }
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = currentObservationSuggestionIssue
            return false
        }
        guard saveObservationEdits(), selectedObservationID != nil else { return false }
        return true
    }

    /// First routines and updates share the same saved, source-linked review flow.
    /// A generated result becomes pending; only explicit approval installs it.
    func analyzeNotes() {
        guard prepareCurrentObservationForSuggestion() else { return }
        if let issue = currentObservationSuggestionIssue { notice = issue; return }
        guard let id = selectedObservationID else { return }
        suggestRoutine(from: [id])
    }

    /// Selection is independent of the Learn editor. A bounded snapshot goes to
    /// inference; a current, validated result becomes a pending proposal only.
    func suggestRoutine(from observationIDs: Set<UUID>) {
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return }
        guard !busy, !sessionActive, storageIsAvailable, saveObservationEdits() else { return }
        do {
            let acquisitions = observationArchive.entries.filter { observationIDs.contains($0.id) }
            guard acquisitions.count == observationIDs.count else {
                notice = String(localized: "An observation was removed. Choose the mornings again.")
                return
            }
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: acquisitions)
            let base = routine
            let preferences = routinePreferences
            let attempt = beginAnalysis()
            analysisStatus = usesSyntheticProposalFixture
                ? String(localized: "Preparing a synthetic suggestion test…") : String(localized: "Finding a routine in your saved mornings…")
            analysisTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let proposal: EvidenceRoutineProposal
                    if usesSyntheticProposalFixture {
                        // The fixture exercises assembly, stale checks, saving and approval;
                        // it is never evidence that a Foundation Models request succeeded.
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--ui-testing-privacy-delayed-analysis") {
                            // A manually released, noncooperative callback tests reset
                            // ownership without a timing race or a model invocation.
                            await withCheckedContinuation { continuation in
                                privacyTestAnalysisGate = continuation
                                privacyTestAnalysisWaiting = true
                            }
                        } else { try await Task.sleep(for: .seconds(1)) }
                        #else
                        try await Task.sleep(for: .seconds(1))
                        #endif
                        proposal = try syntheticEvidenceProposal(evidence: evidence, preserving: base, preferences: preferences)
                    } else {
                        proposal = try await intelligence.propose(evidence: evidence, preserving: base, preferences: preferences) { [weak self] completed, total in
                            guard let self, self.acceptsAnalysis(attempt), !Task.isCancelled, total > 0 else { return }
                            self.progress = Double(completed) / Double(total)
                            self.analysisStatus = completed < total
                                ? String(localized: "Understanding part \(completed + 1) of \(total)…")
                                : String(localized: "Bringing your morning together…")
                        }
                    }
                    try Task.checkCancellation()
                    guard acceptsAnalysis(attempt) else { return }
                    guard proposal.isCurrent(archive: observationArchive, baseRoutine: routine, preferences: routinePreferences) else {
                        busy = false
                        notice = String(localized: "The observations or routine changed while the suggestion was being prepared. Choose mornings to try again.")
                        return
                    }
                    let previousProposal = pendingRoutineProposal
                    pendingRoutineProposal = proposal
                    guard persist() else {
                        pendingRoutineProposal = previousProposal
                        busy = false
                        return
                    }
                    busy = false
                    progress = 1
                    notice = String(localized: "An update is ready to review. Your current morning is unchanged.")
                } catch { finishAnalysis(error: error, attempt: attempt) }
            }
        } catch { notice = error.localizedDescription }
    }

    @discardableResult
    func approvePendingRoutineProposal() -> Bool {
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        guard !busy, !sessionActive, !voiceInputBlocksPlayback, storageIsAvailable,
              saveObservationEdits(), let proposal = pendingRoutineProposal else { return false }
        guard proposal.isCurrent(archive: observationArchive, baseRoutine: routine, preferences: routinePreferences) else {
            notice = String(localized: "This suggestion no longer matches the saved observations or routine. Choose mornings to prepare a fresh one.")
            return false
        }
        let oldRoutine = routine
        let oldPrevious = previousRoutine
        let oldSession = session
        let oldHistory = history
        archiveTerminalSession()
        if let oldRoutine, oldRoutine.isApproved { previousRoutine = oldRoutine }
        routine = proposal.routine.approved()
        session = routine.map { RoutineSession(routine: $0) }
        pendingRoutineProposal = nil
        guard persist() else {
            routine = oldRoutine
            previousRoutine = oldPrevious
            session = oldSession
            history = oldHistory
            pendingRoutineProposal = proposal
            return false
        }
        approvalCount += 1
        notice = String(localized: "Update approved. Your next morning will use this routine.")
        return true
    }

    @discardableResult
    func discardPendingRoutineProposal() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, let proposal = pendingRoutineProposal else { return false }
        pendingRoutineProposal = nil
        guard persist() else { pendingRoutineProposal = proposal; return false }
        notice = String(localized: "Suggestion discarded. Your current morning is unchanged.")
        return true
    }

    private func syntheticEvidenceProposal(evidence: PreparedLearningEvidence,
                                           preserving base: RoutineVersion?, preferences: RoutinePreferenceJournal) throws -> EvidenceRoutineProposal {
        guard usesSyntheticProposalFixture,
              evidence.sourceSnapshots.allSatisfy({ $0.origin == .synthetic }) else {
            throw AppleIntelligenceError.insufficientActivityEvidence
        }
        var seen = Set<UUID>()
        let citations = evidence.units.filter { seen.insert($0.acquisitionID).inserted }.map {
            RoutineEvidenceCitationInput(unitID: $0.id, quote: String($0.text.prefix(220)))
        }
        return try LearningEvidencePreparation.assemble(evidence: evidence, steps: [
            EvidenceRoutineStepInput(title: String(localized: "A morning to review"),
                detail: String(localized: "Synthetic review fixture from the selected observations. No Apple model call."),
                kind: .custom, durationMinutes: 3, citations: citations)
        ], preserving: base, preferences: preferences, at: Date())
    }

    /// Returns true only after accepting ownership or starting an ordinary file import.
    /// The recorder must keep its ready URL until this returns true. Import saves
    /// evidence only and never starts routine inference.
    /// Suggesting a routine is a separate explicit action after provenance review.
    @discardableResult
    func importObservation(_ url: URL) -> Bool {
        guard !privacyBlocksWork else { return false }
        let ownedRecording = ScreenRecordingFiles.isOwnedRecording(url) || recordingRecovery.owns(url)
        let selectedURL: URL
        if ownedRecording {
            guard retainRecording(url, interruptionNote: nil, recordingContext: nil, automaticallyProcess: false),
                  let retainedURL = pendingRecordingURL else { return false }
            selectedURL = retainedURL
        } else {
            selectedURL = url
        }
        guard !busy, !sessionActive else {
            if ownedRecording {
                observationIssue = String(localized: "Your recording is saved. Finish the current activity, then retry understanding it.")
                return true
            }
            notice = String(localized: "Finish the current activity before importing another observation.")
            return false
        }
        // Save current corrections before a new import can replace the latest observation.
        // An app-owned recording has already been retained even if this write fails.
        guard saveObservationEdits() else { return ownedRecording }
        let attempt = beginAnalysis()
        analysisStatus = String(localized: "Reading your selected observation…")
        let interruptionNote = ownedRecording ? pendingRecordingInterruption : nil
        let recordingContext = ownedRecording ? pendingRecordingContext : nil
        analysisTask = Task { [weak self] in
            guard let self else { return }
            let granted = selectedURL.startAccessingSecurityScopedResource()
            defer { if granted { selectedURL.stopAccessingSecurityScopedResource() } }
            do {
                let fingerprint = try await fingerprintService.fingerprint(of: selectedURL)
                try Task.checkCancellation()
                guard acceptsAnalysis(attempt) else { return }
                if let existing = observationArchive.entries.first(where: { $0.fileSHA256 == fingerprint.sha256 }) {
                    // A retry never overwrites its original, corrections, or assigned day.
                    // Native context may fill a previously missing field only for the
                    // exact same bytes. A second session never replaces the first.
                    if let recordingContext {
                        try observationArchive.attachRecordingContext(recordingContext, to: existing.id,
                            matchingFileSHA256: fingerprint.sha256)
                    }
                    projectObservation(existing.id)
                    observationEditsNeedSave = true
                    guard persist() else { busy = false; observationIssue = notice; return }
                    guard finishOwnedRecordingImport(ownedRecording) else { return }
                    busy = false
                    notice = String(localized: "This observation is already saved. Your corrections and its date have been kept. Your routine is unchanged.")
                    return
                }
                let observation = try await media.extract(from: selectedURL) { [weak self] fraction in
                    guard let self, self.acceptsAnalysis(attempt) else { return }
                    self.progress = fraction
                }
                let visibleText = observation.text
                let extracted = interruptionNote.map { "[Recording coverage: \($0)]\n\n\(visibleText)" } ?? visibleText
                try Task.checkCancellation()
                guard acceptsAnalysis(attempt) else { return }
                let hasReadableText = observation.videoEvidence?.hasRecognizedText ?? !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                guard hasReadableText else {
                    // An unsuccessful import must not erase the previous reviewed observation.
                    // Structured failure samples remain available to the extraction caller;
                    // an owned recording stays in recovery for retry or explicit discard.
                    busy = false
                    let sampleCount = observation.videoEvidence?.frames.count ?? observation.sampledFrameCount
                    observationIssue = String(localized: "No readable text was found in \(sampleCount) samples. Your previous observation is unchanged. ") +
                        (ownedRecording ? String(localized: "The recording is kept for retry or discard.") : String(localized: "Try a clearer or shorter recording."))
                    notice = observationIssue
                    return
                }
                // File-provider content can change while Vision works. Never attach a
                // digest for different bytes to the extracted observation.
                let finalFingerprint = try await fingerprintService.fingerprint(of: selectedURL)
                guard acceptsAnalysis(attempt) else { return }
                guard fingerprint.sha256 == finalFingerprint.sha256,
                      fingerprint.byteCount == finalFingerprint.byteCount else {
                    busy = false
                    observationIssue = String(localized: "The selected file changed during analysis. Your previous observation is unchanged. Choose the file again.")
                    return
                }
                try Task.checkCancellation()
                guard acceptsAnalysis(attempt) else { return }
                let observedDate = try recordingContext.map {
                    try ObservationObservedDate(date: $0.startedAt, timeZoneIdentifier: $0.timeZoneIdentifier,
                        provenance: .recordingSession)
                }
                let entry = try ObservationAcquisition(id: recordingContext?.id ?? UUID(),
                    fileSHA256: fingerprint.sha256, observedDate: observedDate,
                    origin: ProcessInfo.processInfo.arguments.contains("--ui-testing") ? .synthetic : .unknown,
                    sourceKind: ObservationAcquisitionSourceKind(rawValue: observation.kind.rawValue) ?? .unknown,
                    sourceLabel: ownedRecording ? String(localized: "Your explicitly shared screen recording") : String(String(localized: "Selected file: \(selectedURL.lastPathComponent)").prefix(256)),
                    originalText: extracted, videoEvidence: observation.videoEvidence,
                    recordingContext: recordingContext)
                let id = try observationArchive.insert(entry)
                projectObservation(id)
                observationEditsNeedSave = true
                progress = 1
                guard persist() else {
                    busy = false
                    observationIssue = notice ?? String(localized: "The extracted text could not be saved. Your recording is kept for retry.")
                    return
                }
                guard finishOwnedRecordingImport(ownedRecording) else { return }
                busy = false
                notice = String(localized: "Observation saved. Review the text and its observed day before asking for a routine suggestion. Your routine is unchanged.")
            } catch {
                guard acceptsAnalysis(attempt) else { return }
                finishAnalysis(error: error, attempt: attempt)
                observationIssue = notice
            }
        }
        return true
    }

    func retryPendingRecording() {
        guard !privacyBlocksWork else { return }
        guard let pendingRecordingURL, !busy, !sessionActive else { return }
        pendingRecordingShouldAutoProcess = false
        importObservation(pendingRecordingURL)
    }

    /// Stages a finalized clip independently of scene visibility, app work, or routine state.
    /// OCR is started by the foreground coordinator; recovered clips require an explicit Retry.
    @discardableResult
    func retainFinalizedRecording(_ url: URL, interruptionNote: String? = nil,
                                  recordingContext: ObservationRecordingContext? = nil) -> Bool {
        retainRecording(url, interruptionNote: interruptionNote, recordingContext: recordingContext, automaticallyProcess: true)
    }

    private func retainRecording(_ url: URL, interruptionNote: String?, recordingContext: ObservationRecordingContext?,
                                 automaticallyProcess: Bool) -> Bool {
        guard !privacyBlocksWork else { return false }
        if let pendingRecordingURL, pendingRecordingURL.standardizedFileURL != url.standardizedFileURL {
            observationIssue = String(localized: "Retry or discard your saved recording before adding another one.")
            return false
        }
        var readyContext: ObservationRecordingContext?
        var readyInterruption: String?
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            let recorder = ScreenRecordingService.shared
            if recorder.recordedURL?.standardizedFileURL == url.standardizedFileURL {
                readyContext = recorder.recordingContext
                readyInterruption = recorder.recordingInterruption
            }
        }
        #endif
        // Both automatic finalization and a later manual retry carry the same
        // provenance before the recorder releases its ready URL.
        let coverageNote = recordingRecovery.owns(url) ? pendingRecordingInterruption : (interruptionNote ?? readyInterruption)
        let context = recordingRecovery.owns(url) ? pendingRecordingContext : (recordingContext ?? readyContext)
        do {
            let retainedURL = try recordingRecovery.retain(url, interruptionNote: coverageNote, recordingContext: context)
            // Read the persisted handoff afresh. A retry after relaunch must not
            // turn unreadable metadata into a successful undated import.
            pendingRecordingURL = retainedURL
            let metadata = try recordingRecovery.recoveredMetadata()
            pendingRecordingInterruption = metadata?.interruptionNote
            pendingRecordingContext = metadata?.recordingContext
            pendingRecordingShouldAutoProcess = automaticallyProcess
            pendingRecordingURL = retainedURL
            observationIssue = nil
            return true
        } catch {
            observationIssue = String(localized: "Your recording has not been imported or discarded. \(error.localizedDescription)")
            return false
        }
    }

    private func connectRecordingRecovery() {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            let recording = ScreenRecordingService.shared
            recording.onRecordingFinalized = { [weak self] url, interruptionNote in
                self?.retainFinalizedRecording(url, interruptionNote: interruptionNote,
                    recordingContext: recording.recordingContext) ?? false
            }
            if recording.hasRecordingToReview, let url = recording.recordedURL,
               retainFinalizedRecording(url, interruptionNote: recording.recordingInterruption,
                    recordingContext: recording.recordingContext) {
                _ = recording.takeRecording()
            }
        }
        #endif
    }

    func discardPendingRecording() {
        guard !privacyBlocksWork else { return }
        guard !busy, pendingRecordingURL != nil else { return }
        do {
            try recordingRecovery.remove()
            pendingRecordingURL = nil
            pendingRecordingShouldAutoProcess = false
            pendingRecordingInterruption = nil
            pendingRecordingContext = nil
            observationIssue = nil
            notice = String(localized: "Saved recording discarded. Any previously saved observation text remains available.")
        } catch {
            observationIssue = String(localized: "The saved recording could not be removed. \(error.localizedDescription)")
        }
    }

    func dismissObservationIssue() {
        observationIssue = nil
    }

    /// Raw media is removed only after its archive and selection have reached the
    /// same durable workspace. A cleanup failure remains visible and retryable.
    private func finishOwnedRecordingImport(_ owned: Bool) -> Bool {
        guard owned else { return true }
        do {
            try recordingRecovery.remove()
            pendingRecordingURL = nil
            pendingRecordingInterruption = nil
            pendingRecordingContext = nil
            pendingRecordingShouldAutoProcess = false
            return true
        } catch {
            busy = false
            observationIssue = String(localized: "Your extracted text is saved, but the temporary recording could not be removed. You can discard it below. \(error.localizedDescription)")
            return false
        }
    }

    /// Editing keeps the original import/source context. The UI binds to this live value,
    /// so a later lifecycle save cannot restore a stale copy over newly imported text.
    func updateObservationNotes(_ text: String) {
        guard !privacyBlocksWork else { return }
        guard !busy, !sessionActive, !text.utf8.elementsEqual(notes.utf8) else { return }
        notes = text
        if let selectedObservationID,
           pendingRoutineProposal?.sourceSnapshots.contains(where: { $0.acquisitionID == selectedObservationID }) == true {
            pendingRoutineProposal = nil
        }
        // Edited prose cannot remain attached to the unedited video's interpretation.
        observationVideoEvidence = nil
        observationContextClassification = nil
        observationEditsNeedSave = true
    }

    /// Flush on explicit editing/lifecycle boundaries, not on every keystroke or load.
    /// Failed writes keep the current text and dirty state available for retry.
    @discardableResult
    func saveObservationEdits() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard observationEditsNeedSave else { return true }
        return persist()
    }

    func clearObservation() {
        guard !privacyBlocksWork else { return }
        guard !busy, !sessionActive else { return }
        if let id = selectedObservationID { _ = deleteObservation(id: id) }
        else {
            projectObservation(nil)
            observationEditsNeedSave = true
            persist()
        }
    }

    @discardableResult
    func selectObservation(id: UUID) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, !sessionActive, observationArchive.entry(id: id) != nil,
              saveObservationEdits() else { return false }
        return changeObservationArchive(selecting: id) { _ in }
    }

    @discardableResult
    func assignObservationDate(id: UUID, date: Date?, timeZoneIdentifier: String,
                               origin: ObservationAcquisitionOrigin) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, !sessionActive, saveObservationEdits() else { return false }
        do {
            let observed = try date.map {
                try ObservationObservedDate(date: $0, timeZoneIdentifier: timeZoneIdentifier, provenance: .userAssigned)
            }
            return changeObservationArchive(selecting: selectedObservationID) { archive in
                try archive.assignObservedDate(id: id, value: observed, origin: origin)
            }
        } catch { notice = error.localizedDescription; return false }
    }

    /// A screen review is a separate user assertion. Never overwrite original OCR or
    /// accept an editor whose source changed while it was open.
    @discardableResult
    func saveFrameReview(_ review: ObservationFrameReview, expected: ObservationAcquisition) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive,
              saveObservationEdits() else { return false }
        guard observationArchive.entry(id: expected.id) == expected else {
            notice = String(localized: "This observation changed. Reopen the sampled screen before saving its label.")
            return false
        }
        return changeObservationArchive(selecting: selectedObservationID) {
            try $0.reviewFrame(id: expected.id, review: review)
        }
    }

    @discardableResult
    func removeFrameReview(sampleID: UUID, expected: ObservationAcquisition) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive,
              saveObservationEdits() else { return false }
        guard observationArchive.entry(id: expected.id) == expected else {
            notice = String(localized: "This observation changed. Reopen the sampled screen before removing its label.")
            return false
        }
        return changeObservationArchive(selecting: selectedObservationID) {
            try $0.removeFrameReview(id: expected.id, sampleID: sampleID)
        }
    }

    @discardableResult
    func deleteObservation(id: UUID) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, !sessionActive else { return false }
        // Deleting the selected entry intentionally discards its unsaved correction.
        // Edits to a different entry must reach disk before this independent change.
        if selectedObservationID != id, !saveObservationEdits() { return false }
        return changeObservationArchive(selecting: selectedObservationID == id ? nil : selectedObservationID) {
            try $0.delete(id: id)
        }
    }

    @discardableResult
    func clearAllObservations() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, !sessionActive else { return false }
        return changeObservationArchive(selecting: nil) { $0.clear() }
    }

    private func projectObservation(_ id: UUID?) {
        let entry = id.flatMap { observationArchive.entry(id: $0) }
        selectedObservationID = entry?.id
        notes = entry?.effectiveText ?? ""
        notesSourceLabel = entry?.sourceLabel ?? String(localized: "Your written observation")
        // Original video evidence remains inspectable in the observation detail.
        // Edited notes must never masquerade as its unmodified OCR interpretation.
        observationVideoEvidence = entry?.correctedText == nil ? entry?.videoEvidence : nil
        observationContextClassification = entry?.correctedText == nil ? entry?.classification : nil
    }

    private func changeObservationArchive(selecting id: UUID?,
                                          _ mutation: (inout ObservationArchive) throws -> Void) -> Bool {
        guard !privacyBlocksWork else { return false }
        let previousArchive = observationArchive
        let previousID = selectedObservationID
        let previousNotes = notes
        let previousEvidence = observationVideoEvidence
        let previousClassification = observationContextClassification
        let previousSource = notesSourceLabel
        let previousDirty = observationEditsNeedSave
        do {
            var next = observationArchive
            try mutation(&next)
            observationArchive = next
            projectObservation(id)
            observationEditsNeedSave = true
            guard persist() else {
                observationArchive = previousArchive
                selectedObservationID = previousID
                notes = previousNotes
                observationVideoEvidence = previousEvidence
                observationContextClassification = previousClassification
                notesSourceLabel = previousSource
                observationEditsNeedSave = previousDirty
                notice = String(localized: "The observation change could not be saved. Your previous observations are unchanged.")
                observationSaveIssue = notice
                return false
            }
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    private func synchronizeObservationEdits() throws {
        guard observationEditsNeedSave else { return }
        if let entry = selectedObservation {
            if !notes.utf8.elementsEqual(entry.effectiveText.utf8) {
                try observationArchive.correct(id: entry.id,
                    text: notes.utf8.elementsEqual(entry.originalText.utf8) ? nil : notes)
            } else if observationContextClassification != entry.classification {
                try observationArchive.classify(id: entry.id, result: observationContextClassification)
            }
        } else if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let entry = try ObservationAcquisition(sourceKind: .manual,
                sourceLabel: notesSourceLabel, originalText: notes)
            selectedObservationID = try observationArchive.insert(entry)
        }
    }

    /// Explicit isolated fixture data only; never substitutes for a real recording.
    private func seedObservationArchiveIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"), args.contains("--ui-testing-observation-archive"),
              args.first(where: { $0.hasPrefix("--ui-testing-workspace=") })
                .flatMap({ UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) }) != nil else { return }
        do {
            let now = Date()
            let zone = TimeZone.current.identifier
            let today = try ObservationObservedDate(date: now, timeZoneIdentifier: zone, provenance: .userAssigned)
            let yesterday = try ObservationObservedDate(date: Calendar.current.date(byAdding: .day, value: -1, to: now)!,
                timeZoneIdentifier: zone, provenance: .userAssigned)
            let a = try ObservationAcquisition(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                observedDate: today, origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic morning A",
                originalText: "Original sample A: calendar, water, chess.",
                correctedText: "Edited sample A: calendar, water, chess and tea.")
            let b = try ObservationAcquisition(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                observedDate: yesterday, origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic morning B",
                originalText: "Original sample B: weather and a walk.")
            let c = try ObservationAcquisition(id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic import C",
                originalText: "Original sample C: an undated imported recording.")
            observationArchive = try ObservationArchive(entries: [a, b, c])
            projectObservation(a.id)
            persist()
        } catch { notice = "Synthetic archive fixture could not be prepared." }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        // Keep the owner so privacy cleanup can await its actual completion.
        // Retain busy until the worker acknowledges cancellation, so a second model run cannot overlap.
        analysisStatus = String(localized: "Stopping analysis…")
    }

    /// Separate, explicit interpretation of the latest sampled screens. This never treats
    /// OCR order as touch events, grants action authority, or changes the approved routine.
    func recognizeObservationScreens() {
        guard !privacyBlocksWork else { return }
        guard let evidence = observationVideoEvidence, !busy, !sessionActive,
              evidence.frames.contains(where: \.canSupportIdentity), saveObservationEdits() else { return }
        let attempt = beginAnalysis()
        let acquisitionID = selectedObservationID
        analysisStatus = String(localized: "Recognizing the screens we sampled…")
        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await contextClassifier.classify(frames: evidence.frames)
                try Task.checkCancellation()
                guard acceptsAnalysis(attempt) else { return }
                guard observationVideoEvidence?.id == evidence.id,
                      selectedObservationID == acquisitionID else { throw CancellationError() }
                _ = try evidence.makeTrace(decisions: result.decisions)
                observationContextClassification = result
                observationEditsNeedSave = true
                busy = false
                progress = 1
                if persist() { notice = String(localized: "Screen observations updated. Review what was recognized and what remains unknown.") }
            } catch { finishAnalysis(error: error, attempt: attempt) }
        }
    }

    func useManualRoutine() {
        guard !privacyBlocksWork else { return }
        guard !sessionActive, !busy else { notice = String(localized: "Stop this morning before creating another routine."); return }
        installCandidate(RoutineVersion(number: 1, sourceLabel: String(localized: "Created by you"), steps: [
            RoutineStep(title: String(localized: "Your morning"), detail: String(localized: "Review what matters today."), kind: .briefing, durationMinutes: 3, isRequired: true, automation: .spokenNote)
        ], isApproved: false))
        tab = .today
        persist()
    }

    /// Importing is an explicit edit, never approval or execution. The caller
    /// captures the base when opening the file so a stale preview cannot replace
    /// a routine that changed while the file provider was loading.
    @discardableResult
    func useImportedRoutine(_ document: PortableRoutineDocument, replacing expectedBase: RoutineVersion?) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, !sessionActive, !voiceInputBlocksPlayback, storageIsAvailable else {
            notice = String(localized: "Finish the current activity before importing a routine.")
            return false
        }
        guard routine == expectedBase else {
            notice = String(localized: "Your routine changed while this file was open. Cancel and open the file again to review it.")
            return false
        }
        do {
            let draft = try document.importedDraft(replacing: routine)
            let oldRoutine = routine
            let oldPrevious = previousRoutine
            let oldSession = session
            let oldProposal = pendingRoutineProposal
            if let oldRoutine, oldRoutine.isApproved { previousRoutine = oldRoutine }
            routine = draft
            session = nil
            pendingRoutineProposal = nil
            guard persist() else {
                routine = oldRoutine; previousRoutine = oldPrevious; session = oldSession
                pendingRoutineProposal = oldProposal
                notice = String(localized: "The imported draft could not be saved. Your current routine is unchanged.")
                return false
            }
            notice = String(localized: "Imported as a draft. Review and approve it when ready. Your saved choices still apply to future suggestions.")
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func restorePreviousRoutine() {
        guard !privacyBlocksWork else { return }
        guard !busy, !sessionActive, let previousRoutine else { return }
        let oldRoutine = routine
        let oldSession = session
        routine = previousRoutine
        session = RoutineSession(routine: previousRoutine)
        self.previousRoutine = nil
        guard persist() else {
            routine = oldRoutine
            session = oldSession
            self.previousRoutine = previousRoutine
            return
        }
        notice = String(localized: "Your previous approved routine is restored. Saved choices still apply to future suggestions.")
    }

    private func installCandidate(_ candidate: RoutineVersion) {
        if let routine, routine.isApproved { previousRoutine = routine }
        var draft = candidate
        draft.number = routine?.nextNumber ?? 1
        draft.isApproved = false
        routine = draft
        session = nil
    }

    private func beginAnalysis() -> UUID {
        let attempt = UUID()
        analysisAttempt = attempt
        busy = true
        progress = 0
        notice = nil
        observationIssue = nil
        analysisStatus = String(localized: "Finding the meaningful steps…")
        return attempt
    }

    private func acceptsAnalysis(_ attempt: UUID) -> Bool {
        analysisAttempt == attempt && !privacyBlocksWork
    }

    private func finishAnalysis(error: Error, attempt: UUID) {
        guard acceptsAnalysis(attempt) else { return }
        busy = false
        progress = 0
        notice = error is CancellationError ? String(localized: "Analysis stopped. Your existing routine is unchanged.") : error.localizedDescription
        if hasPendingRecording || hasImportedObservation { observationIssue = notice }
    }

    func saveVoicePreference() { persist() }

    func executionPreferencesChanged() {
        guard !privacyBlocksWork else { return }
        cancelStepPlayback()
        speech.stop()
        guard persist() else { pauseAfterSaveFailure(); return }
        runCurrentIfEnabled()
    }

    func openCapture(text: String = "", source: QuickCaptureSource = .typed) {
        guard !privacyBlocksWork else { return }
        completionInvitationSessionID = nil
        stopCompletionInvitation()
        capturePrefill = text
        captureSource = source
        capturePresented = true
    }

    @discardableResult
    func saveCapture(kind: QuickCaptureKind, text: String, date: Date?, duration: Int = 30,
                     saveToSystem: Bool, id: UUID, source: QuickCaptureSource) async -> Bool {
        guard !privacyBlocksWork, !captureBusy else { return false }
        let generation = dataGeneration
        guard pendingCaptures[id.uuidString] == nil else {
            notice = String(localized: "This save has an unconfirmed outcome. Check the Apple app before trying again.")
            return false
        }
        captureBusy = true
        defer { if dataGeneration == generation { captureBusy = false } }
        do {
            let capture = try QuickCapture(id: id, kind: kind, text: text, requestedDate: date, source: source)
            if saveToSystem {
                if kind == .reminder {
                    try ReminderDraft(title: text, dueDate: date, notifyAtDueTime: date != nil).validate()
                } else if kind == .calendarIdea {
                    guard let date else { notice = String(localized: "Choose a date and time for the calendar event."); return false }
                    try CalendarEventDraft(title: text, startDate: date,
                        endDate: date.addingTimeInterval(Double(duration) * 60)).validate()
                }
            }
            // A retry after a known successful write must never create a duplicate system item.
            if saveToSystem && receipts[id.uuidString] == nil {
                let receipt: EventKitWriteReceipt
                switch kind {
                case .reminder:
                    try await reminders.requestReminderAccess()
                    guard dataGeneration == generation, !privacyBlocksWork, !Task.isCancelled else { return false }
                    pendingCaptures[id.uuidString] = String(localized: "Reminders")
                    upsertCapture(capture)
                    guard persist() else { pendingCaptures[id.uuidString] = nil; return false }
                    receipt = try reminders.createReminder(from: ReminderDraft(title: text, dueDate: date,
                        notifyAtDueTime: date != nil))
                case .calendarIdea:
                    guard let date else { notice = String(localized: "Choose a date and time for the calendar event."); return false }
                    try await reminders.requestCalendarWriteAccess()
                    guard dataGeneration == generation, !privacyBlocksWork, !Task.isCancelled else { return false }
                    pendingCaptures[id.uuidString] = String(localized: "Calendar")
                    upsertCapture(capture)
                    guard persist() else { pendingCaptures[id.uuidString] = nil; return false }
                    receipt = try reminders.createCalendarEvent(from: CalendarEventDraft(title: text,
                        startDate: date, endDate: date.addingTimeInterval(Double(duration) * 60)))
                default: notice = String(localized: "Choose a reminder or calendar event to save to Apple apps."); return false
                }
                receipts[id.uuidString] = receipt.id
                pendingCaptures[id.uuidString] = nil
            }
            upsertCapture(capture)
            notice = saveToSystem ? (kind == .reminder ? String(localized: "Saved in Apple Reminders and your notes.") : String(localized: "Saved in Apple Calendar and your notes.")) : String(localized: "Saved on this device.")
            let saved = persist()
            if !saved && saveToSystem {
                notice = (kind == .reminder ? String(localized: "Apple saved this item, but the local receipt could not be saved. Check Apple Reminders before trying again.") : String(localized: "Apple saved this item, but the local receipt could not be saved. Check Apple Calendar before trying again."))
            }
            // A completed external write dismisses the draft even if the local disk write failed.
            return saved || saveToSystem
        } catch {
            guard dataGeneration == generation, !privacyBlocksWork else { return false }
            notice = pendingCaptures[id.uuidString] == nil ? error.localizedDescription :
                String(localized: "The Apple app save could not be confirmed. Check it before retrying. \(error.localizedDescription)")
            return false
        }
    }

    private func upsertCapture(_ capture: QuickCapture) {
        if let index = captures.firstIndex(where: { $0.id == capture.id }) { captures[index] = capture }
        else { captures.insert(capture, at: 0) }
    }

    func daySummary(_ date: Date) -> MorningDaySummary? {
        try? history.day(containing: date)
    }

    var weekSummary: SevenDaySummary? { try? history.sevenDaySummary(endingOn: Date()) }

    private func runCurrentIfEnabled() {
        guard !privacyBlocksWork else { return }
        guard !voiceInputBlocksPlayback else { return }
        guard let session, session.status == .running else { return }
        if automatic {
            stepExecutor.spokenEnabled = readAloud
            automation.runCurrentStep(in: session) { [weak self] context in
                guard let self, self.session?.id == context.executionID.sessionID,
                      self.session?.currentStep?.id == context.executionID.stepID,
                      self.session?.status == .running else { return }
                self.advance(commandID: context.commandID)
            }
        } else if readAloud { readCurrent() }
    }

    func handleSpeechInterruption() {
        guard session?.status == .running, speech.state == .paused else { return }
        let message = speech.lastError ?? String(localized: "Audio was interrupted. Continue when you're ready.")
        pause()
        notice = message
    }

    private func pauseAfterSaveFailure() {
        cancelStepPlayback()
        speech.stop()
        if session?.status == .running { try? session?.pause() }
        synchronizeMorningActivity()
        // Preserve the disk-error message and do not dispatch another action.
    }

    private func archiveTerminalSession() {
        guard let session, session.status == .completed || session.status == .stopped else { return }
        do {
            history.upsert(try MorningRunRecord(session: session, timeZoneIdentifier: sessionTimeZone,
                isSynthetic: session.routine.isSynthetic,
                timingInterrupted: sessionTimingInterrupted))
        } catch { notice = String(localized: "This morning could not be added to history: \(error.localizedDescription)") }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !privacyBlocksWork else { return false }
        if let snapshotRecoveryError {
            morningActivitySaveBlocked = true
            synchronizeMorningActivity()
            notice = String(localized: "\(snapshotRecoveryError) Your existing file is protected; new changes cannot be saved until it can be restored.")
            if observationEditsNeedSave { observationSaveIssue = notice }
            return false
        }
        do {
            // An accepted longer plan ends with any change of routine, whether or not this write succeeds.
            let currentBudget = budgetAndFeedback.droppingAcceptance(unlessFor: routine)
            if currentBudget != budgetAndFeedback { budgetAndFeedback = currentBudget }
            try synchronizeObservationEdits()
            // A proposal is derived from both sources and a full routine revision.
            // Drop stale derived state in the same write as any edit or deletion.
            // Keep the in-memory value intact if the write itself fails.
            let validProposal = routinePreferencesIssue == nil ? pendingRoutineProposal.flatMap {
                $0.isCurrent(archive: observationArchive, baseRoutine: routine, preferences: routinePreferences) ? $0 : nil
            } : nil
            try privacyControl.withReadyAccess { _ in
                try snapshot.save(WorkspaceSnapshot(routine: routine, session: session, previousRoutine: previousRoutine,
                history: history, captures: captures, receipts: receipts, sessionTimeZone: sessionTimeZone,
                automatic: automatic, readAloud: readAloud, showMorningOnLockScreen: showMorningOnLockScreen,
                sessionTimingInterrupted: sessionTimingInterrupted,
                budgetAndFeedback: budgetAndFeedback,
                pendingCaptures: pendingCaptures, voiceIdentifier: speech.voiceIdentifier,
                observationNotes: notes.isEmpty ? nil : notes,
                observationSource: notes.isEmpty && observationVideoEvidence == nil ? nil : notesSourceLabel,
                observationVideoEvidence: observationVideoEvidence,
                observationContextClassification: observationContextClassification.map(RecoverableObservationClassification.init),
                observationArchive: observationArchive, selectedObservationID: selectedObservationID,
                pendingRoutineProposal: validProposal.map(RecoverableRoutineProposal.init),
                consumedMorningEntryIDs: consumedMorningEntryIDs,
                routinePreferences: unreadablePreferences ?? .init(routinePreferences)))
            }
            pendingRoutineProposal = validProposal
            savedCompletionSessionID = session?.status == .completed ? session?.id : nil
            savedRunEndings = runEndingsInMemory
            observationEditsNeedSave = false
            projectObservation(selectedObservationID)
            if let observationSaveIssue, notice == observationSaveIssue { notice = nil }
            observationSaveIssue = nil
            morningActivitySaveBlocked = false
            synchronizeMorningActivity()
            return true
        } catch {
            morningActivitySaveBlocked = true
            synchronizeMorningActivity()
            notice = String(localized: "Your change is in memory, but saving failed: \(error.localizedDescription)")
            if observationEditsNeedSave { observationSaveIssue = notice }
            return false
        }
    }

    /// The durable marker closes all writers before cleanup begins. Interrupted
    /// removal stays closed on launch and is retried; old snapshots are never
    /// restored as a rollback after any deletion has begun.
    func forgetLocalData() async {
        guard !privacyIsForgetting else { return }
        let control: LocalDataControlState
        do {
            control = try privacyControl.beginForget()
        } catch {
            privacyStatus = String(localized: "Removal couldn't start. No saved data was removed by this attempt. \(error.localizedDescription)")
            return
        }
        guard let generation = control.generation else { return }
        privacyIsForgetting = true
        privacyHasInterruptedRemoval = true
        privacyNeedsCleanup = true
        activityLoggingAllowed = false
        dataGeneration = generation
        privacyStatus = String(localized: "Stopping work and removing local data…")
        showMorningOnLockScreen = false
        morningActivityStartSessionID = nil
        morningActivityStartRequestID = nil
        analysisAttempt = nil
        let oldAnalysis = analysisTask
        oldAnalysis?.cancel()
        briefing.cancelAndClear()
        stepExecutor.clear()
        cancelStepPlayback()
        speech.stop()
        cancelVoiceCommandTurn()
        cancelCompletionCapture()
        releaseVoiceInput()
        MorningIntentRouter.shared.resetPendingRequests()
        do {
            try await morningActivity.endAllForPrivacy()
            // Vision/file-provider work must finish before its source is removed.
            // Delayed callbacks are independently rejected by the attempt/epoch.
            await oldAnalysis?.value
            analysisTask = nil
            await voiceInputReleaseTask?.value
            try await voiceCommands.cancel()
            try await speech.stopAndRelease()
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *) {
                try await ScreenRecordingService.shared.discardAndWait()
            } else {
                try ScreenRecordingFiles.removeAllOwnedRecordings()
            }
            #else
            try ScreenRecordingFiles.removeAllOwnedRecordings()
            #endif
            try await invitation.forget()
            try privacyControl.withForgetAccess(expectedGeneration: generation) {
                try recordingRecovery.removeAllOwnedData()
                // SEGMENTED SESSIONS (#27) ARE NOT FORGOTTEN HERE YET. Nothing in the app
                // creates one today. The change that first constructs a
                // `RecordingSessionStore` in this target must add, right here:
                //   try RecordingSessionStore(directory: <the workspace folder>).forgetAll()
                // which removes `RecordingSessions/<session>/` manifests and segment files.
                // The sessions' observations go with the archive, which this forget clears.
                // A package test (SegmentedSessionForgettingGuardTests) fails if the app
                // starts using the store without calling `forgetAll`.
                for name in ["app-transitions.json", "morning-invitation.json", "briefing-settings.json"] {
                    try removeOwnedPayload(snapshot.url.deletingLastPathComponent().appendingPathComponent(name))
                }
                let directory = snapshot.url.deletingLastPathComponent()
                // Interrupted AtomicJSONFile staging writes may contain the full
                // old workspace. The namespace is reserved for this app's writes.
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where url.lastPathComponent.hasPrefix(".morning-save-") {
                    try removeOwnedPayload(url)
                }
                // An explicit empty archive/choice journal prevents legacy
                // migration and isolated demo seeding from restoring content.
                try snapshot.save(WorkspaceSnapshot(history: MorningHistory(), captures: [], receipts: [:],
                    automatic: true, readAloud: true, pendingCaptures: [:],
                    observationArchive: ObservationArchive(), consumedMorningEntryIDs: [],
                    routinePreferences: .init(RoutinePreferenceJournal())))
            }
            clearForgottenMemory()
            try privacyControl.finishForget(expectedGeneration: generation)
            try morningActivity.resetAfterPrivacyCleanup()
            briefing.reloadSettings()
            privacyNeedsCleanup = false
            privacyHasInterruptedRemoval = false
            privacyIsForgetting = false
            privacyStatus = String(localized: "MORE’s local data was removed. App activity logging is off.")
            privacyCompletedID = UUID()
            connectRecordingRecovery()
        } catch {
            // Cleanup can be partial. Keep the durable marker and do not claim
            // either complete removal or preservation of the original workspace.
            privacyIsForgetting = false
            privacyStatus = String(localized: "Removal needs another try. Some local data may already be gone; remaining data stays unavailable. \(error.localizedDescription)")
        }
    }

    func setActivityLoggingAllowed(_ allowed: Bool) {
        guard !privacyBlocksWork else { return }
        do {
            try privacyControl.setActivityLoggingAllowed(allowed)
            activityLoggingAllowed = allowed
            privacyStatus = allowed ? String(localized: "Your configured Shortcuts can save new app activity.") : String(localized: "New app activity will no longer be saved. Existing activity stays until you remove local data.")
        } catch { privacyStatus = String(localized: "This setting couldn't be saved. \(error.localizedDescription)") }
    }

    private func removeOwnedPayload(_ url: URL) throws {
        // Unlink a known symlink itself, never its target. Unexpected directories
        // are left in place and reported rather than recursively removed.
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
        guard let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular || type == .typeSymbolicLink else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: url)
    }

    private func clearForgottenMemory() {
        routine = nil; session = nil; previousRoutine = nil
        notes = ""; notesSourceLabel = String(localized: "Your written observation")
        observationArchive = ObservationArchive(); selectedObservationID = nil
        observationVideoEvidence = nil; observationContextClassification = nil
        observationSaveIssue = nil; observationEditsNeedSave = false; observationIssue = nil
        pendingRoutineProposal = nil
        routinePreferences = RoutinePreferenceJournal(); routinePreferencesIssue = nil; unreadablePreferences = nil
        history = MorningHistory(); captures = []; receipts = [:]; pendingCaptures = [:]
        budgetAndFeedback = RoutineBudgetAndFeedback(); savedRunEndings = []
        pendingRecordingURL = nil; pendingRecordingShouldAutoProcess = false
        pendingRecordingInterruption = nil; pendingRecordingContext = nil
        captureBusy = false; capturePresented = false; capturePrefill = ""; captureSource = .typed
        voiceCommandPresented = false; captureVoicePresented = false
        voiceCommandFeedback = nil; completionCaptureFeedback = nil
        voiceCommandDeduplicator = MorningVoiceCommandDeduplicator()
        completionInvitationSessionID = nil; lastCompletionOffered = nil; savedCompletionSessionID = nil
        dismissedReflectionSessionID = nil; completionVoiceSessionID = nil; pendingSpokenCapture = nil
        morningDetailPresented = false; observationDetailPresented = false
        observationSelectionPresented = false; routineProposalPresented = false
        consumedMorningEntryIDs = []; sessionTimingInterrupted = false; sessionTimeZone = TimeZone.current.identifier
        readAloud = true; automatic = true; speech.voiceIdentifier = nil
        showMorningOnLockScreen = false; morningActivityIssue = nil; morningActivitySaveBlocked = false
        morningActivityStartSessionID = nil
        morningActivityStartRequestID = nil
        busy = false; progress = 0; analysisStatus = ""; snapshotRecoveryError = nil; notice = nil
        MorningIntentRouter.shared.resetPendingRequests()
        tab = .today
    }


    #if DEBUG
    private var usesPrivacyFixture: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--ui-testing-privacy-fixture") &&
            args.first(where: { $0.hasPrefix("--ui-testing-workspace=") })
                .flatMap { UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) } != nil
    }

    private func seedPrivacyFixtureIfRequested(directory: URL) {
        guard usesPrivacyFixture else { return }
        do {
            captures = [try QuickCapture(kind: .dream, text: "SYNTHETIC_PRIVACY_DREAM", source: .typed)]
            if let step = routine?.steps.first { try routinePreferences.upsert(RoutinePreference(target: step, presence: .keep)) }
            let recovery = directory.appendingPathComponent("RecordingRecovery", isDirectory: true)
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            for name in ["pending-screen-recording.mp4", "recording-info.json"] {
                try Data("SYNTHETIC_PRIVACY_RECOVERY".utf8).write(to: recovery.appendingPathComponent(name))
            }
            try Data("SYNTHETIC_PRIVACY_SNAPSHOT_LEFTOVER".utf8)
                .write(to: directory.appendingPathComponent(".morning-save-privacy-fixture"))
            // A deliberately unreadable settings payload exercises full removal
            // without configuring a live Calendar or Weather request.
            try Data("SYNTHETIC_PRIVACY_BRIEFING_SETTINGS".utf8)
                .write(to: directory.appendingPathComponent("briefing-settings.json"))
            try Data("SYNTHETIC_IMPORTED_ORIGINAL_KEEP".utf8)
                .write(to: directory.appendingPathComponent("imported-original-sentinel.txt"))
            try Data("SYNTHETIC_EXPORTED_COPY_KEEP".utf8)
                .write(to: directory.appendingPathComponent("exported-copy-sentinel.json"))
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-privacy-cleanup-failure") {
                let barrier = directory.appendingPathComponent("app-transitions.json", isDirectory: true)
                try FileManager.default.createDirectory(at: barrier, withIntermediateDirectories: true)
                try Data("SYNTHETIC_PRIVACY_FAILURE_ONLY".utf8).write(to: barrier.appendingPathComponent("test-only-barrier"))
            } else {
                try Data("SYNTHETIC_PRIVACY_ACTIVITY_CORRUPT".utf8).write(to: directory.appendingPathComponent("app-transitions.json"))
            }
            persist()
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-privacy-delayed-analysis"), let id = selectedObservationID {
                suggestRoutine(from: [id])
            }
        } catch { notice = "Synthetic privacy fixture failed: \(error.localizedDescription)" }
    }

    private func repairPrivacyFixtureIfRequested(directory: URL) {
        guard usesPrivacyFixture, ProcessInfo.processInfo.arguments.contains("--ui-testing-privacy-repair") else { return }
        let barrier = directory.appendingPathComponent("app-transitions.json", isDirectory: true)
        let marker = barrier.appendingPathComponent("test-only-barrier")
        guard (try? Data(contentsOf: marker)) == Data("SYNTHETIC_PRIVACY_FAILURE_ONLY".utf8),
              (try? FileManager.default.contentsOfDirectory(atPath: barrier.path)) == ["test-only-barrier"] else { return }
        // Repair only the exact deliberate test barrier; never a production file.
        try? FileManager.default.removeItem(at: marker)
        try? FileManager.default.removeItem(at: barrier)
    }

    func releasePrivacyTestAnalysis() {
        privacyTestAnalysisWaiting = false
        let continuation = privacyTestAnalysisGate
        privacyTestAnalysisGate = nil
        continuation?.resume()
    }
    #endif

}
