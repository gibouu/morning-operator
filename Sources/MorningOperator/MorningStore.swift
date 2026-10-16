import Foundation
import UIKit
import Observation
import MorningCore
import MorningApple
import MorningHealth

enum MorningTab: String, CaseIterable, Identifiable {
    case today = "Morning", review = "Review", captures = "Notes", learn = "Learn", setup = "Settings", routine = "Routine"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .review: "chart.bar.xaxis"
        case .captures: "square.and.pencil"
        case .learn: "sparkles"
        case .setup: "slider.horizontal.3"
        case .routine: "list.bullet"
        }
    }
}

/// Retain privacy outcomes and their original error objects, not translated snapshots.
private enum PrivacyNotice {
    case finishingRemoval, controlsUnreadable(any Error), removalDidNotStart(any Error)
    case removing, removed, removalFailed(any Error), activityLogging(Bool), loggingSaveFailed(any Error)

    var text: String {
        switch self {
        case .finishingRemoval: String(localized: "Finishing the removal you requested. Saved data stays unavailable until cleanup completes.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .controlsUnreadable(let error): String(localized: "The local data controls couldn't be read. Open Privacy to retry removing local data. \(error.moreDescription)", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .removalDidNotStart(let error): String(localized: "Removal couldn't start. No saved data was removed by this attempt. \(error.moreDescription)", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .removing: String(localized: "Stopping work and removing local data…", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .removed: String(localized: "MORE’s local data was removed. App activity logging is off.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .removalFailed(let error): String(localized: "Removal needs another try. Some local data may already be gone; remaining data stays unavailable. \(error.moreDescription)", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .activityLogging(let allowed): allowed
            ? String(localized: "Your configured Shortcuts can save new app activity.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            : String(localized: "New app activity will no longer be saved. Existing activity stays until you remove local data.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .loggingSaveFailed(let error): String(localized: "This setting couldn't be saved. \(error.moreDescription)", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
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
    /// Counts mornings that finished and were saved in this launch (issue #80). A finish
    /// whose save failed, a repeated command and a finished morning read at launch do not count.
    private(set) var morningCompletionCount = 0
    private(set) var notes = ""
    private(set) var observationVideoEvidence: ObservationVideoEvidence?
    private(set) var observationContextClassification: ObservationContextClassification?
    private(set) var observationSaveIssue: String?
    private(set) var observationArchive = ObservationArchive()
    private(set) var selectedObservationID: UUID?
    private(set) var pendingRoutineProposal: EvidenceRoutineProposal?
    /// Built from Screen Time; changes nothing until approved (`approvePendingScreenTimeProposal`).
    private(set) var pendingScreenTimeProposal: ScreenTimeRoutineProposal?
    var screenTimeBusy = false
    var screenTimeMessage: String?
    var screenTimeAccess: ScreenTimeAccess = .notAsked
    var screenTimeLearning: ScreenTimeLearning?
    @ObservationIgnored let screenTimeSource: any ScreenTimeSource = ScreenTimeSources.make()
    @ObservationIgnored var screenTimeTask: Task<Void, Never>?
    @ObservationIgnored var screenTimeTaskID: UUID?
    private(set) var routinePreferences = RoutinePreferenceJournal()
    private(set) var routinePreferencesIssue: String?
    private var unreadablePreferences: RecoverableRoutinePreferences?
    /// Saved elements that could not be read, kept verbatim and written back on every save
    /// until all local data is forgotten (issue #94). Never interpreted.
    private var setAsideWorkspaceElements: [PreservedJSONValue] = []
    var setAsideWorkspaceCount: Int { setAsideWorkspaceElements.count }

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
    var stepTimerRevision = 0
    var pendingWebTarget: URL?
    @ObservationIgnored var stepTimerTask: Task<Void, Never>?
    var calendarBusy: Bool { briefing.isConnectingCalendar }
    var readAloud = true
    var automatic = true
    /// On unless the person turned it off earlier: there is no in-app switch any more,
    /// so iOS's own Live Activities permission decides whether it appears.
    private(set) var showMorningOnLockScreen = true
    private(set) var morningActivityIssue: String?
    private var morningActivityIsForeground = false
    private var morningActivitySaveBlocked = false
    private var morningActivityStartSessionID: UUID?
    private var morningActivityStartRequestID: UUID?
    @ObservationIgnored private lazy var morningActivityNamespace: MorningActivityNamespace = {
        MorningActivityNamespace.workspace(directory: snapshot.url.deletingLastPathComponent(),
            isUITesting: ProcessInfo.processInfo.arguments.contains("--ui-testing"))
            ?? .testing(workspaceID: UUID())
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
    /// The kind the review starts with when a closing question asked for it. The words still
    /// decide: "I dreamed…" stays a dream after the reminder question.
    var captureKindHint: QuickCaptureKind?
    /// The closing questions of the completed morning (memory only). Nil before completion,
    /// after "Not now" and once every question was answered or skipped.
    private(set) var closingQuestions: MorningClosingQuestions?
    /// The question whose answer is in review. Closing the review, saved or not, moves on.
    private var closingQuestionInReview: MorningClosingQuestion?
    /// The short extras for this build, their choices and rotation (Settings → Your day).
    let extras: MorningExtrasProvider
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
    let permissionSetup: MorningPermissionSetup
    let briefing: MorningBriefingController
    let composio = SlackSetupUITestFixture.integratedServiceIfRequested() ?? GmailAttentionUITestFixture.connectionsIfRequested() ?? OutlookInboxUITestFixture.serviceIfRequested() ?? CalendlyDayUITestFixture.serviceIfRequested() ?? GoogleCalendarDayUITestFixture.serviceIfRequested() ?? SlackSetupUITestFixture.serviceIfRequested() ?? ComposioService()
    let nativeConnections = NativeConnectionsService()
    var selectedSlackMessageTS: String?
    @ObservationIgnored var slackReplyTask: Task<Void, Never>?
    @ObservationIgnored lazy var slackReply: SlackThreadReplyConversation = {
        let provider: any SlackThreadReplyProviding
        let drafts: SlackReplyDraftService
        #if DEBUG
        if usesSyntheticSlack { provider = SlackReplyUITestProvider() }
        else { provider = SlackComposioReplyProvider(service: composio) }
        drafts = SlackSetupUITestFixture.integratedDraftsIfRequested()
            ?? SlackReplyDraftService.syntheticClassicJourneyIfRequested() ?? SlackReplyDraftService()
        #else
        provider = SlackComposioReplyProvider(service: composio)
        drafts = SlackReplyDraftService()
        #endif
        return SlackThreadReplyConversation(provider: provider,
            drafts: drafts,
            directory: snapshot.url.deletingLastPathComponent(), speak: { [weak self] text in
            guard let self, !privacyBlocksWork else { throw CancellationError() }
            #if DEBUG
            if usesSyntheticSlack || SlackSetupUITestFixture.integratedJourneyRequested { throw CancellationError() }
            #endif
            try await speech.speakAndWait(text)
        })
    }()
    var nativeActionCountCache: [UUID: (routineVersionID: UUID, generation: UUID, counts: NativeMomentActionCounts)] = [:]
    @ObservationIgnored var nativeMomentTask: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored lazy var nativeUITestProvider = NativeMomentUITestProvider(directory: snapshot.url.deletingLastPathComponent(), context: { [weak self] in
        guard let self, !privacyBlocksWork, sessionActive, let session, let step = currentStep else { return nil }
        let current = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        return nativeMoment.context == current ? current : nil
    })
    #endif
    @ObservationIgnored lazy var nativeMoment: NativeMomentConversation = {
        let provider: any NativeMomentProviding
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(NativeMomentUITestProvider.exactFlag) ||
            (ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-testing-native-actions")) {
            // Even an invalid private activation stays on a refusing local
            // provider; it must never fall back to EventKit.
            provider = nativeUITestProvider
        } else { provider = reminders }
        #else
        provider = reminders
        #endif
        return NativeMomentConversation(provider: provider, directory: snapshot.url.deletingLastPathComponent(), speak: { [weak self] text in
            guard let self, !self.privacyBlocksWork else { throw CancellationError() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(NativeMomentUITestProvider.exactFlag) ||
                (ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-testing-native-actions")) {
                // Synthetic UI fixtures use the explicit screen-review fallback, never fake acoustic success.
                throw CancellationError()
            }
            #endif
            try await self.speech.speakAndWait(text)
        })
    }()
    @ObservationIgnored let connectedMoment = ConnectedMomentState()
    var googleCalendarDayDocument: GoogleCalendarDayDocument?
    var googleCalendarDayContext: MorningExecutionID?
    var googleCalendarDayPrivacyGeneration: UUID?
    @ObservationIgnored var googleCalendarDayFreshnessTask: Task<Void, Never>?
    var calendlyDayDocument: CalendlyDayDocument?
    var calendlyDayContext: MorningExecutionID?
    var calendlyDayPrivacyGeneration: UUID?
    @ObservationIgnored var calendlyDayFreshnessTask: Task<Void, Never>?
    var outlookInboxDocument: OutlookInboxDocument?
    var outlookMessageDocument: OutlookMessageDocument?
    var outlookInboxContext: MorningExecutionID?
    var outlookInboxPrivacyGeneration: UUID?
    @ObservationIgnored var outlookInboxFreshnessTask: Task<Void, Never>?
    @ObservationIgnored let routineWebMoment = RoutineWebMomentRetainer()
    @ObservationIgnored var mailBudgetWork: [UUID: MorningExecutionID] = [:]
    @ObservationIgnored var mailBudgetDeadlinePaused: MorningExecutionID?
    @ObservationIgnored var connectedAPITask: Task<Void, Never>?
    @ObservationIgnored var nativeStepContext: (requestID: UUID, sessionID: UUID, stepID: UUID)?
    var connectedActionStatus: String?
    var executionRecords: [RoutineExecutionRecord] = []
    var webExecutionEvent: WebMorningExecutionEvent?
    @ObservationIgnored var executionSpeechTask: Task<Void, Never>?
    #if MORE_JURY_DEMO
    let juryDemoVoice = JuryDemoVoiceSession()
    let juryDemoBrowser = JuryDemoBrowser()
    var juryDemoCaption = ""
    var juryDemoWebURL: URL?
    var juryDemoPendingWebURL: URL?
    #endif
    let handsFreeVoice = MorningHandsFreeVoiceCoordinator()
    let voiceAccess = MorningVoiceAccess()
    var voiceStartRequest: MorningVoiceStartRequest?
    var voiceStartDecision: MorningVoiceStartDecision?
    var handsFreeListeningSuppressedSessionID: UUID?
    @ObservationIgnored var browserSignInPause: (context: MorningVoiceCommandContext, privacy: UUID, revision: UUID)?
    @ObservationIgnored var handsFreePauseRevision = UUID()
    @ObservationIgnored var voiceLanguageGeneration = UUID()
    @ObservationIgnored var appliedLanguageCode = AppLanguage.code
    @ObservationIgnored var handsFreeUtteranceHandler: (@MainActor (String) async -> Bool)?
    @ObservationIgnored lazy var mailMorning: GmailMorningConversation = {
        let speak: @MainActor (String) async throws -> Void = { [weak self] text in
            guard let self else { throw CancellationError() }
            if self.readAloud { try await self.speech.speakAndWait(text) }
        }
        return GmailAttentionUITestFixture.conversationIfRequested(privacy: privacyControl, speak: speak)
            ?? GmailMorningConversation(attention: GmailAttentionService(), speak: speak)
    }()
    let usesSyntheticBriefing: Bool
    private(set) var consumedMorningEntryIDs: [UUID] = []
    // The opening of a morning (issue #28). The logic is in MorningStore+Opening.swift;
    // only that file writes these four.
    var openingPresentation: MorningOpeningPresentation?
    var greetingState = MorningGreetingState()
    @ObservationIgnored var openingTask: Task<Void, Never>?
    /// How many times the current morning's opening handed over to its routine (one, at most).
    var openingRoutineStarts = 0
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
    @ObservationIgnored private var completionCaptureReviewID: UUID?
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
    private let visualAppRecognizer = ObservationVisualAppRecognizer()
    /// Whether Apple's on-device model can look at sampled images to name apps.
    var canRecognizeAppsInImages: Bool { visualAppRecognizer.isAvailable }
    private var notesSourceLabel = String(localized: "Your written observation", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    private let snapshot: AtomicJSONFile<WorkspaceSnapshot>
    private let recordingRecovery: PendingScreenRecordingStore
    @ObservationIgnored private var snapshotRecoveryError: String?
    @ObservationIgnored private var snapshotRecoveryPart: UnreadableWorkspacePart?
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
    var localPrivacyGeneration: UUID? { (try? privacyControl.status())?.generation }
    private(set) var privacyIsForgetting = false
    private(set) var privacyNeedsCleanup = false
    private(set) var privacyHasInterruptedRemoval = false
    private var privacyNotice: PrivacyNotice?
    var privacyStatus: String? { privacyNotice?.text }
    private(set) var privacyCompletedID: UUID?
    private(set) var activityLoggingAllowed = true
    var privacyBlocksWork: Bool { privacyIsForgetting || privacyNeedsCleanup }
    // Evidence retention and forgetting one observation (#8). Change these through MorningStore+Retention.swift.
    var evidenceRetentionDays: Int?
    var evidenceRemovalStatus: String?
    var evidenceRemovalInProgress = false
    var privacyInventoryIsReadable: Bool { snapshotRecoveryError == nil && !privacyBlocksWork }

    #if DEBUG
    /// Development-only injection of a portable *draft*, never action authority.
    /// The document lives in the UI-test runner; no corpus is bundled in the app.
    private static func parsedUITestRoutine(directory: URL, arguments: [String]) throws -> RoutineVersion {
        let workspacePrefix = "--ui-testing-workspace=", documentPrefix = "--ui-testing-parsed-routine="
        let workspaces = arguments.filter { $0.hasPrefix(workspacePrefix) }
        let documents = arguments.filter { $0.hasPrefix(documentPrefix) }
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard arguments.contains("--ui-testing"), workspaces.count == 1, documents.count == 1,
              let workspace = UUID(uuidString: String(workspaces[0].dropFirst(workspacePrefix.count))),
              directory.standardizedFileURL.resolvingSymlinksInPath() == temporary
                .appendingPathComponent("MorningOperatorUITests-\(workspace.uuidString)", isDirectory: true),
              documents[0].utf8.count <= 65_536,
              let data = Data(base64Encoded: String(documents[0].dropFirst(documentPrefix.count))) else {
            throw PortableRoutineDocumentError.invalidDocument
        }
        let document = try PortableRoutineDocument.decode(data)
        guard document.sourceIsSynthetic, !document.approvalAtExport else {
            throw PortableRoutineDocumentError.invalidDocument
        }
        return try document.importedDraft(replacing: nil)
    }
    #endif
    @ObservationIgnored lazy var cloudVoice = MorningCloudVoiceSession(
        tokenProvider: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.composio.morningVoiceToken()
        }, makeTransport: { UnavailableMorningVoiceTransport() },
        control: { [weak self] action, binding in
            guard let self else { throw CancellationError() }
            return try await self.applyCloudVoiceControl(action, binding: binding)
        }, request: { [weak self] request, binding in
            self?.acceptCloudVoiceRequest(request, binding: binding) ?? false
        })
    @ObservationIgnored var cloudVoiceRequestTask: Task<Void, Never>?
    @ObservationIgnored var cloudVoiceRequestTurnID: UUID?
    @ObservationIgnored var cloudVoiceMemoryTask: Task<Void, Never>?
    @ObservationIgnored var cloudVoiceMemoryTurnID: UUID?
    @ObservationIgnored var cloudVoiceConsentGeneration: UUID?
    @ObservationIgnored var cloudVoiceConsentSession: UUID?
    @ObservationIgnored var cloudVoiceStartAttempt: UUID?
    var cloudVoiceReleasing = false
    var cloudVoiceStartIssue: String?
    var voiceFallbackMessage: String?
    @ObservationIgnored var naturalSpeechConsent: MorningNaturalSpeechConsent?
    @ObservationIgnored var naturalSpeechDeclined: MorningNaturalSpeechConsent?
    @ObservationIgnored var naturalSpeechFailed = false
    @ObservationIgnored var cloudVoiceFallbackTask: Task<Void, Never>?
    @ObservationIgnored var cloudVoiceReleaseTask: Task<Void, Never>?
    @ObservationIgnored var voicePreviewAttempt: UUID?

    init() {
        let fixtureMode = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #if DEBUG
        let parsedRoutineFixtureRequested = ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-testing-parsed-routine=") })
        #else
        let parsedRoutineFixtureRequested = false
        #endif
        let directory = LocalDataControl.defaultDirectory
        permissionSetup = MorningPermissionSetup(directory: directory, isolated: fixtureMode)
        privacyControl = LocalDataControl(directory: directory)
        snapshot = AtomicJSONFile(url: directory.appendingPathComponent("workspace.json"))
        recordingRecovery = PendingScreenRecordingStore(directory: directory)
        invitation = MorningInvitationService(directory: directory)
        extras = Self.makeExtras(directory: directory, testing: fixtureMode)
        #if DEBUG
        let testBriefing = MorningBriefingFixture.makeController(directory: directory)
        usesSyntheticBriefing = testBriefing != nil
        briefing = testBriefing ?? MorningBriefingController(directory: directory,
            sleep: SleepObservationService(provider: HealthKitSleepReader()),
            healthMetrics: HealthMetricsObservationService(provider: HealthKitMetricsReader()))
        #else
        usesSyntheticBriefing = false
        briefing = MorningBriefingController(directory: directory,
            sleep: SleepObservationService(provider: HealthKitSleepReader()),
            healthMetrics: HealthMetricsObservationService(provider: HealthKitMetricsReader()))
        #endif
        #if DEBUG
        if !parsedRoutineFixtureRequested { repairPrivacyFixtureIfRequested(directory: directory) }
        #endif
        defer { if !privacyBlocksWork { connectRecordingRecovery() } }
        do {
            let control = try privacyControl.status()
            if let generation = control.generation { dataGeneration = generation }
            activityLoggingAllowed = control.activityLoggingAllowed
            if control.forgetPending {
                privacyHasInterruptedRemoval = true
                privacyNeedsCleanup = true
                privacyNotice = .finishingRemoval
                return
            }
        } catch {
            privacyNeedsCleanup = true
            privacyNotice = .controlsUnreadable(error)
            return
        }
        do {
            pendingRecordingURL = try recordingRecovery.recover()
            if pendingRecordingURL != nil {
                observationIssue = AppLanguage.localized("Your saved recording is still on this device. Retry understanding it, or discard it.")
                do {
                    let metadata = try recordingRecovery.recoveredMetadata()
                    pendingRecordingInterruption = metadata?.interruptionNote
                    pendingRecordingContext = metadata?.recordingContext
                }
                catch {
                    observationIssue = AppLanguage.localized("Your recording is kept on this device, but its saved information could not be read. It has not been analyzed or discarded. \(error.moreDescription)")
                }
            }
        } catch {
            observationIssue = AppLanguage.localized("Recording recovery needs attention: \(error.moreDescription)")
        }
        let seedFixture = fixtureMode && !ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-workspace")
        if seedFixture && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path) {
            // Display and audio preferences do not grant import approval. Set
            // them before ordinary seeders can persist their own fixture state.
            automatic = ProcessInfo.processInfo.arguments.contains("--ui-testing-hands-free")
            readAloud = ProcessInfo.processInfo.arguments.contains("--ui-testing-read-aloud")
            // Parsed input is an exclusive draft path. Other test seeders must
            // neither approve/replace it nor rescue a malformed payload.
            if parsedRoutineFixtureRequested {
                #if DEBUG
                do { routine = try Self.parsedUITestRoutine(directory: directory, arguments: ProcessInfo.processInfo.arguments) }
                catch {
                    routine = nil
                    notice = "SYNTHETIC QA input refused. No routine was installed."
                }
                #endif
            } else {
            routine = DemoFixtures.candidateRoutine
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-instagram-routing") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — SYNTHETIC saved Instagram routes", steps: [
                    RoutineStep(title: "SYNTHETIC Instagram home", durationMinutes: 5,
                        target: .externalApp(.instagram, detail: nil)),
                    RoutineStep(title: "SYNTHETIC Instagram profile", durationMinutes: 5,
                        target: .externalApp(.instagram, detail: "@nasa"))
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-automation") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic automation journey", steps: [
                    RoutineStep(title: "A quiet moment", detail: "Take a breath.", durationMinutes: 1, automation: .timedMoment),
                    RoutineStep(title: "Get ready", detail: "Your next moment.", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if GmailAttentionUITestFixture.isRequested {
                routine = RoutineVersion(sourceLabel: "Demo fixture — SYNTHETIC Gmail attention", steps: [
                    RoutineStep(title: "SYNTHETIC Gmail attention", detail: "Local invented mail, deterministic test selection. No account, network, or sending.", durationMinutes: 3, automation: .gmailInbox),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-native-unavailable") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — unavailable native calendar", steps: [
                    RoutineStep(title: "Calendar unavailable", kind: .calendar, durationMinutes: 1, automation: .todayCalendar),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-live-news") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — public news navigation test", steps: [
                    RoutineStep(title: "Le Monde", kind: .briefing, durationMinutes: 1,
                        target: .inAppWeb(site: WebMorningSite.news.table.startURL), webBehavior: .readHeadlines),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-public-feed") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — live public Reddit browsing", steps: [
                    RoutineStep(title: "Reddit", kind: .entertainment, durationMinutes: 2,
                        target: .inAppWeb(site: URL(string: "https://www.reddit.com/r/france/")!), webBehavior: .browseFeed),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-slack-reply") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic Slack reply", steps: [
                    RoutineStep(title: "Slack · #synthetic-qa", detail: "SYNTHETIC local fixture. Read three messages; review a reply before sending. No Slack account is used.", durationMinutes: 3,
                        target: .connectedAPI(service: "slack", connectionID: "synthetic-slack", tool: "SLACK_FETCH_CONVERSATION_HISTORY", argumentsJSON: "{\"channel\":\"CSYNTHETIC\",\"limit\":3}")),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-google-calendar-runtime"), GoogleCalendarDayUITestFixture.isRequested,
               let target = try? GoogleCalendarDayTarget(connectionID: "ca_synthetic_google_calendar", calendarID: "synthetic-primary@calendar.invalid", calendarName: "SYNTHETIC calendrier personnel de préparation du matin avec un nom volontairement très long") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic Google Calendar day", steps: [
                    RoutineStep(title: target.calendarName, detail: "SYNTHETIC read-only day, recalculated for this iPhone’s current date and time zone.", kind: .calendar, durationMinutes: 3, target: .googleCalendarDay(target)),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-calendly-runtime"), CalendlyDayUITestFixture.isRequested,
               let target = try? CalendlyDayTarget(connectionID: "ca_synthetic_calendly", userURI: "https://api.calendly.com/users/synthetic-local-owner",
                    userName: "SYNTHETIC Camille, compte de préparation du matin avec un nom volontairement très long") {
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic Calendly day", steps: [
                    RoutineStep(title: target.userName, detail: "SYNTHETIC read-only bookings starting today in this iPhone’s current time zone.", kind: .calendar, durationMinutes: 3, target: .calendlyDay(target)),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-outlook-runtime"), OutlookInboxUITestFixture.isRequested,
               let target = try? OutlookInboxTarget(connectionID: OutlookInboxUITestFixture.connectionID,
                    accountID: OutlookInboxUITestFixture.accountID, displayName: OutlookInboxUITestFixture.displayName,
                    mailboxAddress: OutlookInboxUITestFixture.mailboxAddress) {
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic Outlook Inbox", steps: [
                    RoutineStep(title: "Outlook · \(target.sourceLabel())", detail: "SYNTHETIC read-only Inbox previews, with a separately selected message body. No Outlook account is used.",
                        kind: .messages, durationMinutes: 3, target: .outlookInbox(target)),
                    RoutineStep(title: "A quiet moment", durationMinutes: 1, automation: .timedMoment)
                ])
            }
            #endif
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-ten-moments") {
                let titles = ["Your morning", "The weather", "Today's calendar", "Your reminders", "People and messages",
                              "A little reading", "Make some tea", "A moment to move", "A little time to play", "One thought for later"]
                let kinds: [StepKind] = [.briefing, .briefing, .calendar, .custom, .messages,
                                         .entertainment, .custom, .wellbeing, .entertainment, .custom]
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic ten-moment morning", steps:
                    titles.enumerated().map { index, title in
                        RoutineStep(title: title, detail: "Synthetic layout example.",
                                    kind: kinds[index], durationMinutes: 2,
                                    automation: ProcessInfo.processInfo.arguments.contains("--ui-testing-automation") ? .timedMoment : nil)
                    })
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-approved") { routine = routine?.approved() }
            seedObservationArchiveIfRequested()
            #if DEBUG
            seedPrivacyFixtureIfRequested(directory: directory)
            if let archive = ObservationReviewUITestFixture.archive(directory: directory) {
                observationArchive = archive
            }
            // Synthetic: the message a model failure shows, without asking a model (issue #89).
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-model-not-ready") {
                notice = AppleIntelligenceError.modelDidNotAnswer(.notReady).localizedDescription
            }
            if let retention = EvidenceRetentionUITestFixture.workspace() {
                observationArchive = retention.archive; routine = retention.routine
                session = RoutineSession(routine: retention.routine); pendingRoutineProposal = retention.proposal
                persist()
            }
            // A sample run stopped after its first moment and saved, for the recap screenshots (#10).
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-stopped-run"), let approved = routine?.approved() {
                routine = approved; session = RoutineSession(routine: approved)
                try? session?.start(); try? session?.advance(); try? session?.stop(); archiveTerminalSession(); persist()
            }
            #endif
            }
        } else if FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path) {
            do {
                let saved = try snapshot.load()
                guard saved.schemaVersion == 1 else {
                    snapshotRecoveryError = AppLanguage.localized("This saved routine uses a newer format. Your file has been kept intact.")
                    notice = snapshotRecoveryError
                    return
                }
                routine = saved.routine
                if let proposal = saved.pendingScreenTimeProposal, proposal.baseRoutineID == routine?.id {
                    pendingScreenTimeProposal = proposal
                }
                session = saved.session
                setAsideWorkspaceElements = saved.setAside ?? []
                savedCompletionSessionID = saved.session?.status == .completed ? saved.session?.id : nil
                previousRoutine = saved.previousRoutine
                if let stored = saved.routinePreferences {
                    if let value = stored.value { routinePreferences = value }
                    else {
                        unreadablePreferences = stored
                        routinePreferencesIssue = AppLanguage.localized("Your saved choices couldn't be read. Your routine and observations are intact. Reset them in Settings → Saved choices before making new suggestions.")
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
                        unreadablePreferences = .init(unreadable: AppLanguage.localized("Legacy required choices need explicit repair."))
                        routinePreferencesIssue = AppLanguage.localized("Your previous choices need review. Your routine is intact. Reset saved choices before making new suggestions.")
                    }
                }
                if let proposal = pendingScreenTimeProposal, !proposal.isCurrent(preferences: routinePreferences) {
                    pendingScreenTimeProposal = nil
                }
                history = saved.history ?? MorningHistory()
                budgetAndFeedback = (saved.budgetAndFeedback ?? RoutineBudgetAndFeedback()).droppingAcceptance(unlessFor: routine)
                savedRunEndings = runEndingsInMemory
                captures = saved.captures ?? []
                receipts = saved.receipts ?? [:]
                executionRecords = Array((saved.executionRecords ?? []).suffix(256)).map {
                    var record = $0
                    if record.outcome == .running { record.outcome = .interrupted }
                    return record
                }
                sessionTimeZone = saved.sessionTimeZone ?? TimeZone.current.identifier
                automatic = saved.automatic ?? true
                readAloud = saved.readAloud ?? true
                handsFreeListeningSuppressedSessionID = saved.session?.id == saved.handsFreeListeningSuppressedSessionID
                    ? saved.handsFreeListeningSuppressedSessionID : nil
                showMorningOnLockScreen = saved.showMorningOnLockScreen ?? true
                speech.voiceGender = saved.voiceGender.flatMap(MorningVoiceGender.init(rawValue:))
                    ?? speech.availableVoices.first(where: { $0.id == saved.voiceIdentifier })?.gender ?? .female
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
                if let proposal = saved.pendingScreenTimeProposal, proposal.baseRoutineID == routine?.id {
                    pendingScreenTimeProposal = proposal
                }
                if routinePreferencesIssue == nil, let proposal = saved.pendingRoutineProposal?.value,
                   proposal.isCurrent(archive: observationArchive, baseRoutine: routine, preferences: routinePreferences) {
                    pendingRoutineProposal = proposal
                } else if saved.pendingRoutineProposal != nil {
                    notice = AppLanguage.localized("A saved suggestion no longer matches its sources or routine. Your current morning and observations are intact. Choose mornings to suggest a fresh update.")
                }
                sessionTimingInterrupted = saved.sessionTimingInterrupted ?? false
                pendingCaptures = saved.pendingCaptures ?? [:]
                consumedMorningEntryIDs = saved.consumedMorningEntryIDs ?? []
                greetingState = saved.greeting ?? MorningGreetingState()
                evidenceRetentionDays = saved.evidenceRetentionDays.flatMap { EvidenceRemovalReview.maximumAgeChoices.contains($0) ? $0 : nil }
                if !pendingCaptures.isEmpty { notice = String(localized: "A previous Apple app save was interrupted. Check Calendar or Reminders before adding that item again.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) }
                if session?.status == .running, currentStep?.target == nil || activeStepTimer == nil || currentStep?.webBehavior != nil {
                    sessionTimingInterrupted = true
                    try session?.pause()
                    notice = String(localized: "Your previous morning is paused. Resume when you're ready.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                    persist()
                }
                if saved.observationArchive == nil, !observationArchive.entries.isEmpty {
                    // Save the migration once so its acquisition identity survives
                    // another launch. A write failure leaves the original intact.
                    persist()
                }
                // Last, so an earlier notice on this launch is not replaced. A save above
                // writes the set-aside elements back with everything else.
                if let setAside = SetAsideWorkspacePart.notice(for: saved.newlySetAside) {
                    notice = [notice, setAside].compactMap { $0 }.joined(separator: " ")
                }
            } catch {
                // Name the part that failed, never the raw error, and say what the person can do.
                let part = UnreadableWorkspacePart(error: error)
                snapshotRecoveryPart = part
                snapshotRecoveryError = part.sentence()
                notice = "\(part.sentence()) \(UnreadableWorkspacePart.advice())"
            }
        }
        refreshNativeActionCount()
        // A confirmed removal interrupted before it finished (#8).
        resumeEvidenceRemovalIfNeeded()
        #if MORE_JURY_DEMO
        configureJuryDemo()
        #endif
    }

    /// Unsaved typed notes have no archive entry yet and are never imported evidence.
    var hasImportedObservation: Bool { selectedObservation?.isImportedEvidence ?? false }
    var hasPendingRecording: Bool { pendingRecordingURL != nil }
    var canStartRecording: Bool { storageIsAvailable && !busy && !sessionActive && !hasPendingRecording }

    func refreshStoredPresentationLanguage() {
        if screenTimeMessage != nil { screenTimeMessage = screenTimeAccessExplanation }
        if observationSaveIssue != nil {
            observationSaveIssue = String(localized: "Your observation has unsaved changes. Retry saving before continuing.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        if observationIssue != nil {
            observationIssue = String(localized: "Your saved recording needs attention. Review it before trying again.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        if routinePreferencesIssue != nil {
            routinePreferencesIssue = String(localized: "Your saved choices need review. Your routine is intact. Reset saved choices before making new suggestions.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        if snapshotRecoveryError != nil {
            snapshotRecoveryError = snapshotRecoveryPart.map { "\($0.sentence()) \(UnreadableWorkspacePart.advice())" }
                ?? String(localized: "Your saved workspace could not be restored. Its file is protected from changes.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            notice = snapshotRecoveryError
        }
        if morningActivityIssue != nil {
            morningActivityIssue = String(localized: "Lock Screen progress couldn't update. Open MORE to check your morning.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        if busy { cancelAnalysis() }
    }

    func clearLanguageDependentPlayback() { stepExecutor.clear() }

    var totalMinutes: Int { routine?.steps.reduce(0) { $0 + $1.durationMinutes } ?? 0 }
    var stateLabel: String { session?.status.displayName ?? (routine?.isApproved == true ? String(localized: "Ready", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Review", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) }
    var currentStep: RoutineStep? { session?.currentStep }
    var sessionActive: Bool { session?.status == .running || session?.status == .paused }
    var modelSummary: String { intelligence.capabilitySummary }

    var morningActivityStatusText: String {
        if let morningActivityIssue { return morningActivityIssue }
        if !showMorningOnLockScreen { return AppLanguage.localized("Off. Your morning stays inside MORE.") }
        if !morningActivity.authorizationEnabled { return AppLanguage.localized("Live Activities are unavailable or turned off in iPhone Settings.") }
        if morningActivity.status == .failed { return AppLanguage.localized("Lock Screen progress couldn't update. Turn it off and on to try again.") }
        if morningActivity.status == .dismissed { return AppLanguage.localized("Hidden from the Lock Screen. Your morning is still in MORE.") }
        if morningActivity.status == .stale { return AppLanguage.localized("Progress may be out of date. Open Morning to check.") }
        if let state = morningActivity.currentSnapshot?.state {
            return AppLanguage.localized("\(state.status.displayName) · Moment \(state.completedSteps + 1) of \(state.totalSteps)")
        }
        return AppLanguage.localized("Ready for the next morning you start.")
    }

    #if DEBUG
    var morningActivityTestNamespace: MorningActivityNamespace? {
        let args = ProcessInfo.processInfo.arguments
        if Bundle.main.bundleIdentifier == "com.gibouu.morningoperator.systemqa", args.contains("--qa-system-checks") {
            return .production
        }
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
        if !isForeground { browserSignInPause = nil }
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
            #if MORE_JURY_DEMO
            let needsAttention = self.juryDemoVoice.state == .failed
            #else
            let needsAttention = self.automation.status != .executing
            #endif
            let clock = MorningThemeClock.shared
            let brandClock = MorningActivityBrandClock(solar: clock.solar,
                pinnedAppearance: clock.pinnedPhase == nil ? nil : .resolve(moonOpacity: clock.celestial.moon.opacity))
            let snapshot = MorningActivityProjection.snapshot(session: self.session,
                needsAttention: needsAttention, timer: self.activeStepTimer, brandClock: brandClock)
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
                self.morningActivityIssue = AppLanguage.localized("Lock Screen progress couldn't update. Open MORE to check your morning.")
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
    var canSuggestSavedObservations: Bool {
        routinePreferencesIssue == nil && (intelligence.isAvailable || usesSyntheticProposalFixture ||
            observationArchive.entries.contains {
                $0.correctedText == nil && ($0.browserLearning != nil || $0.screenTimeEvidence?.hasMorningEvidence == true)
            })
    }

    func loadSample() {
        guard !privacyBlocksWork else { return }
        guard !sessionActive, !busy else {
            notice = AppLanguage.localized("Finish or stop this morning before changing the routine.")
            return
        }
        installCandidate(PhoneMorningSample.routine())
        tab = .today
        notice = AppLanguage.localized("Sample routine loaded. Review and edit it before starting. This is demo data, not learned behavior.")
        persist()
    }

    @discardableResult
    func approve() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard let routine, !busy, !sessionActive else { return false }
        guard mayApproveExecution(in: routine) else { return false }
        do {
            for step in routine.steps {
                try step.target?.validateIntegration()
                if case let .connectedAPI(_, _, _, arguments) = step.target { _ = try ConnectedActionReview.summary(argumentsJSON: arguments) }
            }
        }
        catch { notice = error.moreDescription; return false }
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        guard !routine.steps.isEmpty else { notice = AppLanguage.localized("Add at least one step before approving."); return false }
        let savedPrevious = previousRoutine
        let savedSession = session
        self.routine = routine.approved()
        previousRoutine = nil
        session = self.routine.map { RoutineSession(routine: $0) }
        notice = AppLanguage.localized("Routine approved. You're ready for your first morning.")
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

    @discardableResult
    func addConnectedStep(_ step: RoutineStep) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !sessionActive, !busy else { return false }
        guard (routine?.steps.count ?? 0) < 10 else {
            notice = AppLanguage.localized("Keep your routine within ten moments before adding another action.")
            return false
        }
        if let routine { return updateSteps(routine.steps + [step]) }
        self.routine = RoutineVersion(sourceLabel: AppLanguage.localized("Your connected routine"), steps: [step])
        guard persist() else { self.routine = nil; return false }
        return true
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
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        do {
            var preferences = routinePreferences
            try preferences.rememberOrder(of: steps)
            // The common transaction saves both the reviewed order and draft,
            // preserving the approved predecessor and rolling back on failure.
            return saveRoutineEdit(steps: steps, preferences: preferences)
        } catch { notice = error.localizedDescription; return false }
    }

    func savedPreference(for step: RoutineStep) -> RoutinePreference? {
        try? routinePreferences.matchingPreference(for: step)
    }

    @discardableResult
    func saveStep(_ edited: RoutineStep, keepInSuggestions: Bool, keepDuration: Bool,
                  assignmentContext: RoutineStepAssignmentContext? = nil) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        do {
            try assignmentContext?.validate(routine: routine, generation: dataGeneration)
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
            var steps: [RoutineStep]
            if let assignmentContext {
                steps = try assignmentContext.replacing(step, in: routine, generation: dataGeneration)
            } else {
                steps = routine?.steps ?? []
                if let index = steps.firstIndex(where: { $0.id == step.id }) { steps[index] = step }
                else { steps.append(step) }
            }
            return saveRoutineEdit(steps: steps, preferences: preferences)
        } catch { notice = error.moreDescription; return false }
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
        } catch { notice = error.moreDescription; return false }
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
        notice = AppLanguage.localized("Saved choice cleared. Your current routine is unchanged; future suggestions can reconsider it.")
        return true
    }

    @discardableResult
    func clearSavedRoutineOrder() -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive,
              routinePreferencesIssue == nil else { return false }
        let old = routinePreferences
        let oldProposal = pendingRoutineProposal
        guard routinePreferences.clearOrder() else { return true }
        pendingRoutineProposal = nil
        guard persist() else { routinePreferences = old; pendingRoutineProposal = oldProposal; return false }
        notice = AppLanguage.isFrench
            ? "L’ordre enregistré a été oublié. Vos autres choix et la routine actuelle sont conservés."
            : "Saved order forgotten. Your other choices and current routine are unchanged."
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
        notice = AppLanguage.localized("Saved choices reset. Your routine and observations are unchanged.")
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
        notice = AppLanguage.localized("Changes saved as a new draft. Review and approve when ready.")
        return true
    }

    @discardableResult
    func start(entryID: UUID? = nil) -> Bool {
        guard !privacyBlocksWork else { return false }
        guard let routine, !busy, !voiceInputBlocksPlayback, !captureVoicePresented, !hasPendingSpokenCapture else { return false }
        if let entryID, consumedMorningEntryIDs.contains(entryID) { return false }
        // Revealing an already running morning must not dispatch its speech again.
        if session?.status == .running { return true }
        let decision = voiceStartDecision
        if let decision {
            guard decision.request.routineVersionID == routine.id, decision.request.generation == dataGeneration,
                  decision.request.originalSessionID == session?.id, decision.request.originalSessionStatus == session?.status,
                  decision.request.entryID == entryID else { return false }
            if !decision.listen {
                guard !handsFreeVoice.isActive, !handsFreeVoice.needsAudioRelease,
                      !speech.handsFreeAudioSessionIsOwned else { return false }
            }
        }
        #if MORE_JURY_DEMO
        let suppressed = sessionActive && session?.id == handsFreeListeningSuppressedSessionID
        let resumingCloud = session?.status == .paused && cloudVoice.isActive &&
            cloudVoiceConsentSession == session?.id && cloudVoiceConsentGeneration == dataGeneration
        let needsListeningPreparation = automatic && !suppressed && !resumingCloud &&
            !voiceAccess.refresh(language: voicePreparationLanguage).isReady && decision?.listen != false
        // A terminal session's choice cannot cover the new identity created below.
        let keepsSpeechDecision = session?.status == .paused && hasNaturalSpeechDecision
        let needsSpeechConsent = (automatic || readAloud) && !resumingCloud &&
            !keepsSpeechDecision && decision == nil
        if !bypassesVoicePreparationForUITests,
           needsListeningPreparation || needsSpeechConsent || (forcesVoicePreparationReviewForUITests && decision == nil) {
            if voiceStartRequest?.routineVersionID != routine.id || voiceStartRequest?.generation != dataGeneration ||
               voiceStartRequest?.originalSessionID != session?.id || voiceStartRequest?.originalSessionStatus != session?.status ||
                voiceStartRequest?.entryID != entryID || voiceStartRequest == nil {
                voiceStartRequest = MorningVoiceStartRequest(routineVersionID: routine.id, generation: dataGeneration,
                    originalSessionID: session?.id, originalSessionStatus: session?.status, entryID: entryID)
            }
            return false
        }
        #endif
        discardCompletionReflection()
        let previousEntryIDs = consumedMorningEntryIDs
        let previousListeningSuppression = handsFreeListeningSuppressedSessionID
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
            if decision?.listen == false { handsFreeListeningSuppressedSessionID = session?.id }
            notice = nil
            if let entryID { rememberMorningEntry(entryID) }
            // The greeted mark is saved in the same write as the new session, so a
            // relaunch cannot greet this morning a second time.
            let previousGreeting = greetingState
            let mayGreet = beginsMorning && claimOpeningPlayback()
            guard persist() else {
                consumedMorningEntryIDs = previousEntryIDs
                handsFreeListeningSuppressedSessionID = previousListeningSuppression
                greetingState = previousGreeting
                pauseAfterSaveFailure()
                return false
            }
            if let decision {
                naturalSpeechConsent = decision.onlineSpeech ? naturalSpeechScope : nil
                naturalSpeechDeclined = decision.onlineSpeech ? nil : naturalSpeechScope
                naturalSpeechFailed = false; voiceFallbackMessage = nil
            }
            configureNaturalSpeech()
            if beginsMorning {
                morningStartCount += 1
                #if MORE_JURY_DEMO
                _ = mayGreet
                beginJuryDemo()
                #else
                // Approval already delegated these steps. Start goes straight to
                // execution; listening and online voice are prepared in Settings.
                _ = mayGreet
                endOpening()
                openingRoutineStarts = 1
                runCurrentIfEnabled()
                #endif
            } else {
                runCurrentIfEnabled()
            }
            synchronizeMorningActivity(allowStart: true)
            startHandsFreeVoice()
            return true
        } catch {
            handsFreeListeningSuppressedSessionID = previousListeningSuppression
            notice = error.moreDescription; return false
        }
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
        #if MORE_JURY_DEMO
        juryDemoVoice.pause()
        #endif
        handsFreePauseRevision = UUID()
        guard !privacyBlocksWork else { return }
        preserveMailExecutionBeforeInterruption()
        executionSpeechTask?.cancel(); executionSpeechTask = nil
        cancelVoiceCommandTurn()
        endOpening()
        cancelStepPlayback()
        pauseStepTimer()
        do { try session?.pause(); speech.stop(); notice = nil; persist() }
        catch { notice = error.moreDescription }
    }

    func resumeForNext() {
        guard !privacyBlocksWork, !voiceInputBlocksPlayback else { return }
        do { try session?.resume(); if !persist() { pauseAfterSaveFailure() } }
        catch { notice = error.moreDescription }
    }

    func resume() {
        guard !privacyBlocksWork else { return }
        guard !voiceInputBlocksPlayback else { return }
        if webConversationIsActive {
            notice = AppLanguage.isFrench ? "Terminez la réponse ou dites annule avant de reprendre."
                : "Finish the reply or say cancel before resuming."
            return
        }
        if resumeWebArticleIfNeeded() { return }
        guard !slackReply.isActive else {
            notice = AppLanguage.isFrench ? "Terminez la réponse Slack ou fermez cette demande avant de reprendre."
                : "Finish the Slack reply or close this request before resuming."
            return
        }
        #if MORE_JURY_DEMO
        if !bypassesVoicePreparationForUITests, (automatic || readAloud),
           !hasNaturalSpeechDecision, !cloudVoice.isActive {
            _ = start()
            return
        }
        #endif
        do {
            try session?.resume(); notice = nil
            guard persist() else { pauseAfterSaveFailure(); return }
            runCurrentIfEnabled()
            startHandsFreeVoice()
            synchronizeMorningActivity(allowStart: true)
        }
        catch { notice = error.moreDescription }
    }

    func advance(skipping: Bool = false, commandID: UUID = UUID()) {
        guard !privacyBlocksWork else { return }
        #if MORE_JURY_DEMO
        juryDemoVoice.send(text: skipping ? "Passe cette étape" : "Suivant")
        return
        #endif
        guard !voiceInputBlocksPlayback else { return }
        preserveMailExecutionBeforeInterruption()
        finishExecutionIfNeeded(skipping: skipping)
        webExecutionEvent = nil
        mailMorning.cancel()
        executionSpeechTask?.cancel(); executionSpeechTask = nil
        // Pause, Next, Stop and Again take over from the opening. A changed listening
        // choice does not, except that a hands-free morning never waits for the answer.
        endOpening()
        cancelStepPlayback()
        let previousSession = session
        let wasCompleted = session?.status == .completed
        do {
            try session?.advance(skipping: skipping, commandID: commandID)
            guard endStepTimer() else { session = previousSession; return }
            speech.stop()
            notice = nil
            if session?.status == .completed {
                notice = AppLanguage.localized("Morning complete. Your progress is saved on this device.")
            }
            archiveTerminalSession()
            guard persist() else { pauseAfterSaveFailure(); return }
            if session?.status == .completed { stopHandsFreeVoice(); completedMorningSaved(wasCompleted: wasCompleted) }
            else { runCurrentIfEnabled() }
        } catch { notice = error.moreDescription }
    }

    func stop() {
        #if MORE_JURY_DEMO
        juryDemoVoice.stop()
        juryDemoBrowser.close()
        juryDemoWebURL = nil
        juryDemoPendingWebURL = nil
        #endif
        guard !privacyBlocksWork else { return }
        preserveMailExecutionBeforeInterruption()
        if sessionActive, currentExecutionRecord?.outcome == .running || currentExecutionRecord == nil {
            recordExecution(.interrupted)
        }
        stopHandsFreeVoice()
        webExecutionEvent = nil
        mailMorning.cancel()
        executionSpeechTask?.cancel(); executionSpeechTask = nil
        cancelVoiceCommandTurn()
        endOpening()
        cancelStepPlayback()
        speech.stop()
        guard endStepTimer() else { return }
        do { try session?.stop(); archiveTerminalSession(); notice = nil; persist() }
        catch { notice = error.moreDescription }
    }

    /// Reading again never advances the session. A sourced moment reuses its
    /// pinned text, while a moment not yet prepared goes through freshness checks.
    func readCurrent() {
        #if MORE_JURY_DEMO
        guard !privacyBlocksWork else { return }
        juryDemoVoice.send(text: "Répète")
        return
        #endif
        guard !privacyBlocksWork, !voiceInputBlocksPlayback,
              let session, let step = currentStep else { return }
        endOpening()
        cancelStepPlayback()
        if repeatGoogleCalendarDay() { return }
        if repeatCalendlyDay() { return }
        if repeatOutlookReading() { return }
        if repeatConnectedMoment() { return }
        if step.webBehavior != nil {
            if let event = webExecutionEvent, event.sessionID == session.id, event.stepID == step.id,
               !event.contextText.isEmpty {
                speech.speak(event.contextText.joined(separator: ". "))
            } else {
                speech.speak(AppLanguage.isFrench
                    ? "Aucun texte observé n’est disponible pour ce moment. Dites reprends pour retrouver la page, ou suivant pour continuer."
                    : "No observed text is available for this moment. Say resume to return to the page, or next to continue.")
            }
            return
        }
        if step.automation == nil {
            speech.speak(step.executionPresentationText())
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
                case .needsUser(let reason): notice = reason
                case .unavailable(let reason): presentNativeStepFailure(context: context, reason: reason)
                }
            } catch {
                guard repeatAttempt == attempt, !Task.isCancelled, !privacyBlocksWork else { return }
                presentNativeStepFailure(context: context, reason: AppLanguage.localized("This moment could not finish. You can retry or continue your morning."))
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
        guard let document = stepExecutor.pinnedBriefing,
              briefing.permitsPlayback(of: document) else { return nil }
        return document
    }

    func updateCurrentBriefing() {
        guard !privacyBlocksWork, !voiceInputBlocksPlayback, !nativeMoment.isActive, session?.status == .paused,
              let operation = currentStep?.automation,
              operation == .todayCalendar || operation == .morningBriefing else { return }
        cancelStepPlayback()
        stepExecutor.clear()
        briefing.cancelAndClear()
        connectedActionStatus = nil; notice = nil
        readCurrent()
    }

    func prepareDayIfConfigured() async {
        guard !privacyBlocksWork, !permissionSetup.isPresented else { return }
        await briefing.resolveCurrentLocationIfNeeded()
        guard briefing.hasConfiguredSources else { return }
        _ = await briefing.refresh()
    }

    /// Excluding sleep also withdraws any sentence already pinned for this morning.
    func disableHealthInBriefing() {
        do { try briefing.disableHealth() }
        catch { return } // The controller retains the previous choice and reports the failure.
        suspendHandsFreeVoice()
        handsFreePauseRevision = UUID()
        if session?.status == .running { pause() }
        endOpening()
        cancelStepPlayback()
        stepExecutor.clear()
        speech.stop()
        Task { await prepareDayIfConfigured() }
    }

    func refreshHomeWeatherIfNeeded() async {
        guard !privacyBlocksWork, !permissionSetup.isPresented else { return }
        await briefing.refreshForHome()
    }

    @discardableResult
    func addBriefingToRoutine() -> Bool {
        guard let routine, !sessionActive, !privacyBlocksWork else { return false }
        if routine.steps.contains(where: { $0.automation == .morningBriefing }) { return true }
        let step = RoutineStep(title: AppLanguage.localized( "Your day", bundle: .main), detail: AppLanguage.localized( "Hear the recap from the sources you choose in Your day.", bundle: .main),
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
            notice = AppLanguage.localized("This observation changed. Choose the excerpt again before adding it.")
            return false
        }
        guard (routine?.steps.count ?? 0) < 10 else {
            notice = AppLanguage.localized("Adding this excerpt needs room in your routine. Remove a moment in Routine first.")
            return false
        }
        if routine?.steps.contains(where: { $0.automation == .savedObservation && $0.observationReference == prepared.reference }) == true {
            notice = AppLanguage.localized("This excerpt is already in your morning.")
            return false
        }
        let step = RoutineStep(title: AppLanguage.localized("A saved moment"), detail: current.spokenText,
            kind: .briefing, durationMinutes: 1, automation: .savedObservation,
            observationReference: current.reference)
        let containsSample = observationArchive.entry(id: current.reference.acquisitionID)?.origin == .synthetic
        let sourceLabel = containsSample ? AppLanguage.localized("Demo fixture — includes a synthetic saved observation") : nil
        if let routine {
            return saveRoutineEdit(steps: [step] + routine.steps, preferences: routinePreferences, sourceLabel: sourceLabel)
        }
        let oldSession = session
        let oldProposal = pendingRoutineProposal
        self.routine = RoutineVersion(sourceLabel: sourceLabel ?? AppLanguage.localized("Your selected saved observation"), steps: [step])
        session = nil
        pendingRoutineProposal = nil
        guard persist() else {
            self.routine = nil; session = oldSession; pendingRoutineProposal = oldProposal
            return false
        }
        notice = AppLanguage.localized("Saved as a new draft. Review and approve when ready.")
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
        suspendHandsFreeVoice()
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
                try await prepareForManualVoiceInput()
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
                #if MORE_JURY_DEMO
                voiceCommandFeedback = String(localized: "Heard: \(result.transcript)", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                voiceCommandPresented = false
                switch command {
                case .pause: pause()
                case .stop: stop()
                case .resume: resume()
                case .next, .skip, .repeatStep:
                    resume()
                    guard session?.status == .running else { return }
                    juryDemoVoice.send(text: result.transcript)
                }
                #else
                let wasCompleted = session?.status == .completed
                try session?.applyVoiceCommand(command: command, commandID: result.id)
                archiveTerminalSession()
                guard persist() else { pauseAfterSaveFailure(); return }
                if command == .resume { synchronizeMorningActivity(allowStart: true) }
                voiceCommandFeedback = AppLanguage.localized("Heard: \(result.transcript)")
                voiceCommandPresented = false
                if session?.status == .completed { completedMorningSaved(wasCompleted: wasCompleted) }
                if command == .repeatStep { readCurrent() }
                else if session?.status == .running { runCurrentIfEnabled() }
                #endif
            } catch {
                guard voiceCommandAttempt == attempt else { return }
                voiceCommandFeedback = error is CancellationError
                    ? AppLanguage.localized("Listening stopped. Your morning is still paused.") : error.moreDescription
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
                notice = error.moreDescription
                voiceCommandFeedback = error.moreDescription
                completionCaptureFeedback = error.moreDescription
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

    /// A cloud microphone owner must also wait for manual dictation cancellation.
    func waitForVoiceInputRelease() async { await voiceInputReleaseTask?.value }

    /// Called only after the completion transition has been saved successfully.
    /// Restoring a completed session never queues speech or microphone access.
    /// Called only after the finished session was saved. Feedback and the invitation follow
    /// the change to finished, once: a repeated command on a finished morning adds nothing.
    private func completedMorningSaved(wasCompleted: Bool) {
        guard !wasCompleted else { return }
        stopCloudVoice()
        morningCompletionCount += 1
        queueCompletionInvitation()
    }

    private func queueCompletionInvitation() {
        guard hasSavedCompletedSession, let session, lastCompletionOffered != session.id else { return }
        lastCompletionOffered = session.id
        dismissedReflectionSessionID = nil
        completionInvitationSessionID = session.id
        closingQuestions = MorningClosingQuestions()
    }

    func speakQueuedCompletionInvitation() {
        guard !privacyBlocksWork else { return }
        guard let id = completionInvitationSessionID else { return }
        completionInvitationSessionID = nil
        guard readAloud, hasSavedCompletedSession, session?.id == id,
              !voiceInputBlocksPlayback, !capturePresented, !captureVoicePresented else { return }
        let token = UUID(), generation = dataGeneration
        completionInvitationPlaybackID = token
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if completionInvitationPlaybackID == token { completionInvitationPlaybackID = nil } }
            do {
                try await handsFreeVoice.stopAndRelease()
                guard !Task.isCancelled, completionInvitationPlaybackID == token,
                      dataGeneration == generation, !privacyBlocksWork, readAloud,
                      hasSavedCompletedSession, session?.id == id, session?.status == .completed,
                      !handsFreeVoice.isActive, !handsFreeVoice.needsAudioRelease,
                      !voiceInputBlocksPlayback, !capturePresented, !captureVoicePresented,
                      UIApplication.shared.applicationState == .active else { return }
                let french = AppLanguage.isFrench
                let question = closingQuestions?.current ?? .dream
                speech.speak(french
                    ? "Votre matinée est terminée. \(question.prompt(french: true)) Touchez Parler pour répondre, ou Passer."
                    : "Your morning is complete. \(question.prompt(french: false)) Tap Speak to answer, or Skip.")
                completionInvitationPlaybackID = speech.playbackID
            } catch {
                // A failed microphone release must not start a competing player.
                guard completionInvitationPlaybackID == token else { return }
                notice = handsFreeVoice.message
            }
        }
    }

    func stopCompletionInvitation() {
        if let id = completionInvitationPlaybackID, speech.playbackID == id { speech.stop() }
        completionInvitationPlaybackID = nil
    }

    func openCompletionCapture() {
        guard !privacyBlocksWork else { return }
        guard hasSavedCompletedSession, storageIsAvailable, !busy,
              !capturePresented, !voiceInputBlocksPlayback, !voiceCommandPresented else { return }
        completionCaptureReviewID = nil
        completionInvitationSessionID = nil
        suspendHandsFreeVoice()
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
                try await prepareForManualVoiceInput()
                if let question = closingQuestions?.current, readAloud, !usesSyntheticCompletionCapture {
                    // The question is heard before the microphone opens. Stopped or failed
                    // speech still leaves the question on screen.
                    try? await speech.speakAndWait(question.prompt(french: language == .french))
                    try Task.checkCancellation()
                }
                try await speech.stopAndRelease()
                try Task.checkCancellation()
                guard captureVoicePresented, completionCaptureAttempt == attempt,
                      completionVoiceSessionID == id, session?.id == id, session?.status == .completed else { throw CancellationError() }
                let text: String
                #if DEBUG
                if let sample = takeCompletionCaptureTestSample() {
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
                if closingQuestions != nil, MorningClosingQuestions.interpret(text) == .declined {
                    skipClosingQuestionWhileListening(language: language)
                    return
                }
                closingQuestionInReview = closingQuestions?.current
                pendingSpokenCapture = (id, text)
                captureVoicePresented = false
            } catch where closingQuestions != nil && isSilence(error) {
                // Silence skips a closing question, as "no" does.
                guard completionCaptureAttempt == attempt else { return }
                skipClosingQuestionWhileListening(language: language)
            } catch {
                guard completionCaptureAttempt == attempt else { return }
                completionCaptureFeedback = error is CancellationError
                    ? AppLanguage.localized("Listening stopped. Nothing was saved.") : error.moreDescription
            }
        }
    }

    /// No words at all, or none heard before the listening deadline. A deadline after some
    /// words were heard is not silence: the question stays and the person can try again.
    private func isSilence(_ error: any Error) -> Bool {
        if (error as? MorningCaptureTurnError) == .empty { return true }
        return (error as? MorningVoiceListeningError) == .captureTimedOut && !voiceCommands.lastFailedCaptureHeardWords
    }

    /// "No" or silence in the listening sheet: the next question is asked in the same sheet,
    /// once this turn has released the microphone. After the last one the sheet closes.
    private func skipClosingQuestionWhileListening(language: MorningVoiceCommandLanguage) {
        closingQuestions?.advance()
        guard let closingQuestions, !closingQuestions.isFinished else {
            finishClosingQuestions()
            captureVoicePresented = false
            return
        }
        let attempt = completionCaptureAttempt
        Task { [weak self] in
            // Runs after the finished turn's own cleanup.
            guard let self, captureVoicePresented, completionCaptureAttempt == nil || completionCaptureAttempt == attempt else { return }
            listenForCompletionCapture(language: language)
        }
    }

    /// The question on the completed morning's card, or nil when there is none to ask.
    var currentClosingQuestion: MorningClosingQuestion? {
        shouldOfferCompletionReflection ? closingQuestions?.current : nil
    }

    /// "Skip" on the card. After the last question the card says the morning is complete.
    func skipClosingQuestion() {
        guard currentClosingQuestion != nil else { return }
        stopCompletionInvitation()
        completionInvitationSessionID = nil
        closingQuestions?.advance()
        if closingQuestions?.isFinished == true { finishClosingQuestions() }
    }

    /// "Write" on the card: the typed review, starting with the question's kind.
    func answerClosingQuestionInWriting() {
        guard let question = currentClosingQuestion else { openCapture(); return }
        openCapture(kindHint: question.captureKind)
        if capturePresented { closingQuestionInReview = question }
    }

    /// The review of an answer closed, saved or cancelled. The next question becomes current.
    func closingReviewEnded() {
        captureKindHint = nil
        guard let question = closingQuestionInReview else { return }
        closingQuestionInReview = nil
        guard closingQuestions?.current == question else { return }
        closingQuestions?.advance()
        if closingQuestions?.isFinished == true { finishClosingQuestions() }
    }

    private func finishClosingQuestions() {
        closingQuestions = nil
        closingQuestionInReview = nil
        if session?.status == .completed { dismissedReflectionSessionID = session?.id }
    }

    /// Called after the voice sheet has actually left the screen. A canceled,
    /// backgrounded or superseded turn cannot open another sheet with stale text.
    func completionCaptureDismissed(allowReview: Bool) {
        let pending = pendingSpokenCapture
        cancelCompletionCapture()
        let question = closingQuestionInReview
        guard allowReview, let pending, session?.id == pending.sessionID,
              session?.status == .completed, !capturePresented else { return }
        let generation = dataGeneration, reviewID = UUID()
        completionCaptureReviewID = reviewID
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if completionCaptureReviewID == reviewID { completionCaptureReviewID = nil } }
            // A language switch may have cancelled a live dictation. Keep its
            // words for review while the microphone owner finishes releasing.
            await voiceInputReleaseTask?.value
            guard !privacyBlocksWork, dataGeneration == generation,
                  completionCaptureReviewID == reviewID, UIApplication.shared.applicationState == .active,
                  session?.id == pending.sessionID, session?.status == .completed,
                  !capturePresented, !captureVoicePresented, !voiceCommands.isBusy else { return }
            openCapture(text: pending.text, source: .voice, kindHint: question?.captureKind)
            closingQuestionInReview = question
        }
    }

    func suspendCompletionCaptureForLanguageChange() {
        voiceCommandFeedback = nil
        completionCaptureFeedback = nil
        guard captureVoicePresented else { return }
        let sessionID = completionVoiceSessionID
        let heard = voiceCommands.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelCompletionCapture()
        if let sessionID, !heard.isEmpty {
            pendingSpokenCapture = (sessionID, heard)
        }
        captureVoicePresented = false
    }

    func retryCompletionAudioRelease() {
        guard captureVoicePresented, !completionCapturePreparing, !voiceCommands.isBusy,
              voiceCommands.needsAudioRelease else { return }
        releaseVoiceInput()
    }

    func cancelCompletionCapture() {
        completionCaptureReviewID = nil
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
        closingQuestions = nil; closingQuestionInReview = nil
        completionInvitationSessionID = nil
        stopCompletionInvitation()
        cancelCompletionCapture()
        captureVoicePresented = false
    }

    func completionSessionChanged() {
        if cloudVoiceConsentGeneration != nil,
           cloudVoiceConsentSession != session?.id { stopCloudVoice() }
        let current = session?.status == .completed ? session?.id : nil
        if completionInvitationSessionID != current { completionInvitationSessionID = nil; stopCompletionInvitation() }
        if let expected = completionVoiceSessionID, expected != current { discardCompletionReflection() }
    }

    #if DEBUG
    @ObservationIgnored private var closingTestAnswerIndex = 0
    private var completionCaptureTestSample: (text: String, delay: Double)? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"),
              let workspace = args.first(where: { $0.hasPrefix("--ui-testing-workspace=") }),
              UUID(uuidString: String(workspace.dropFirst("--ui-testing-workspace=".count))) != nil else { return nil }
        if args.contains("--ui-testing-capture-late") {
            // Twelve seconds: the test has to open the turn and cancel it (or
            // leave the app) before this returns, and on a slow hosted simulator
            // those few steps alone have taken five.
            return ("I dreamed of a blue garden. SYNTHETIC_LATE_CAPTURE", 12)
        }
        if args.contains("--ui-testing-capture-dream") {
            return ("I dreamed of a blue garden. SYNTHETIC_VOICE_CAPTURE", 1)
        }
        if args.contains("--ui-testing-closing-answers") {
            // One synthetic answer per listening turn: "no" to the dream question, then a
            // reminder with a time. Never a microphone pass and never an EventKit write.
            let answers = ["No", "Remind me at 5 to call the bank. SYNTHETIC_CLOSING_REMINDER"]
            return (answers[min(closingTestAnswerIndex, answers.count - 1)], 1)
        }
        return nil
    }
    private func takeCompletionCaptureTestSample() -> (text: String, delay: Double)? {
        let sample = completionCaptureTestSample
        if sample != nil { closingTestAnswerIndex += 1 }
        return sample
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
            return AppLanguage.localized("Add notes or import a readable observation before suggesting a routine.")
        }
        guard let entry = selectedObservation else {
            return AppLanguage.localized("Save this observation before suggesting a routine.")
        }
        if entry.observedDate == nil {
            return AppLanguage.localized("Confirm the observed day before using this observation. Import time doesn't establish when it happened.")
        }
        if entry.origin == .unknown {
            return AppLanguage.localized("Confirm whether this observation is your morning or a sample before using it.")
        }
        if entry.origin == .automated {
            return AppLanguage.localized("Automated observations aren't used to suggest a personal morning. Choose your own observation or a separate sample.")
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
    func suggestRoutine(from observationIDs: Set<UUID>, screenTimeSelection: ScreenTimeMomentSelection? = nil) {
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return }
        guard !busy, !sessionActive, storageIsAvailable, saveObservationEdits() else { return }
        do {
            let acquisitions = observationArchive.entries.filter { observationIDs.contains($0.id) }
            guard acquisitions.count == observationIDs.count else {
                notice = AppLanguage.localized("An observation was removed. Choose the mornings again.")
                return
            }
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: acquisitions, screenTimeSelection: screenTimeSelection)
            let base = routine
            let preferences = routinePreferences
            let attempt = beginAnalysis()
            analysisStatus = usesSyntheticProposalFixture
                ? AppLanguage.localized("Preparing a synthetic suggestion test…") : AppLanguage.localized("Finding a routine in your saved mornings…")
            analysisTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let proposal: EvidenceRoutineProposal
                    if evidence.hasOnlyStructuredEvidence {
                        proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [],
                            preserving: base, preferences: preferences)
                    } else if usesSyntheticProposalFixture {
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
                                ? AppLanguage.localized("Understanding part \(completed + 1) of \(total)…")
                                : AppLanguage.localized("Bringing your morning together…")
                        }
                    }
                    try Task.checkCancellation()
                    guard acceptsAnalysis(attempt) else { return }
                    guard proposal.isCurrent(archive: observationArchive, baseRoutine: routine, preferences: routinePreferences) else {
                        busy = false
                        notice = AppLanguage.localized("The observations or routine changed while the suggestion was being prepared. Choose mornings to try again.")
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
                    notice = AppLanguage.localized("An update is ready to review. Your current morning is unchanged.")
                } catch { finishAnalysis(error: error, attempt: attempt) }
            }
        } catch { notice = error.moreDescription }
    }

    @discardableResult
    func editPendingRoutineProposal() -> Bool {
        guard !privacyBlocksWork, routinePreferencesIssue == nil, !busy, !sessionActive,
              !voiceInputBlocksPlayback, storageIsAvailable,
              saveObservationEdits(), let proposal = pendingRoutineProposal else { return false }
        let draft: RoutineVersion
        do {
            draft = try proposal.draftForEditing(archive: observationArchive, baseRoutine: routine,
                preferences: routinePreferences, session: session)
        } catch {
            notice = AppLanguage.localized("This suggestion no longer matches the saved observations or routine. Choose mornings to prepare a fresh one.")
            return false
        }
        let oldRoutine = routine
        let oldPrevious = previousRoutine
        let oldSession = session
        let oldHistory = history
        let oldBudget = budgetAndFeedback
        archiveTerminalSession()
        if let oldRoutine, oldRoutine.isApproved { previousRoutine = oldRoutine }
        // Assembly already applies standing keeps, exclusions and timing choices.
        // Copy its exact source-backed wording; editing grants no execution authority.
        routine = draft
        session = nil
        pendingRoutineProposal = nil
        guard persist() else {
            routine = oldRoutine; previousRoutine = oldPrevious; session = oldSession
            history = oldHistory; budgetAndFeedback = oldBudget; pendingRoutineProposal = proposal
            return false
        }
        notice = AppLanguage.isFrench
            ? "Proposition enregistrée comme brouillon. Ajustez-la, puis confiez-la à MORE quand elle vous convient."
            : "Suggestion saved as a draft. Adjust it, then delegate it to MORE when ready."
        return true
    }

    @discardableResult
    func approvePendingRoutineProposal() -> Bool {
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        guard !busy, !sessionActive, !voiceInputBlocksPlayback, storageIsAvailable,
              saveObservationEdits(), let proposal = pendingRoutineProposal else { return false }
        guard proposal.isCurrent(archive: observationArchive, baseRoutine: routine, preferences: routinePreferences) else {
            notice = AppLanguage.localized("This suggestion no longer matches the saved observations or routine. Choose mornings to prepare a fresh one.")
            return false
        }
        guard mayApproveExecution(in: proposal.routine) else { return false }
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
        notice = AppLanguage.localized("Update approved. Your next morning will use this routine.")
        return true
    }

    @discardableResult
    func discardPendingRoutineProposal() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard !busy, let proposal = pendingRoutineProposal else { return false }
        pendingRoutineProposal = nil
        guard persist() else { pendingRoutineProposal = proposal; return false }
        notice = AppLanguage.localized("Suggestion discarded. Your current morning is unchanged.")
        return true
    }

    /// Saves a fresh Screen Time suggestion. It replaces an earlier one, never the routine.
    @discardableResult
    func savePendingScreenTimeProposal(_ proposal: ScreenTimeRoutineProposal) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, proposal.baseRoutineID == routine?.id else { return false }
        let previous = pendingScreenTimeProposal
        pendingScreenTimeProposal = proposal
        guard persist() else { pendingScreenTimeProposal = previous; return false }
        return true
    }

    /// The owner's edits before approval: leave a step out, or change its minutes.
    func editPendingScreenTimeProposal(_ edit: (inout ScreenTimeRoutineProposal) -> Void) {
        guard !privacyBlocksWork, !busy, var proposal = pendingScreenTimeProposal else { return }
        let previous = proposal
        edit(&proposal)
        guard proposal != previous else { return }
        pendingScreenTimeProposal = proposal
        if !persist() { pendingScreenTimeProposal = previous }
    }

    /// Installs the included steps as the routine. Only this explicit approval changes it.
    @discardableResult
    func approvePendingScreenTimeProposal() -> Bool {
        guard !privacyBlocksWork else { return false }
        guard routinePreferencesIssue == nil else { notice = routinePreferencesIssue; return false }
        guard !busy, !screenTimeBusy, !sessionActive, !voiceInputBlocksPlayback, storageIsAvailable,
              let proposal = pendingScreenTimeProposal else { return false }
        guard proposal.baseRoutineID == routine?.id else {
            notice = AppLanguage.localized("Your routine changed since this suggestion was made. Learn from Screen Time again for a fresh one.")
            return false
        }
        guard proposal.isCurrent(preferences: routinePreferences) else {
            notice = AppLanguage.isFrench ? "Vos choix ont changé. Préparez une nouvelle proposition avant de la valider." : "Your choices changed. Prepare a fresh suggestion before approving it."
            return false
        }
        let draft: RoutineVersion
        do { draft = try proposal.draft(preserving: routine) }
        catch { notice = AppLanguage.localized("Keep at least one app to approve this suggestion."); return false }
        guard mayApproveExecution(in: draft) else { return false }
        let oldRoutine = routine
        let oldPrevious = previousRoutine
        let oldSession = session
        let oldHistory = history
        let oldBudget = budgetAndFeedback
        archiveTerminalSession()
        if let oldRoutine, oldRoutine.isApproved { previousRoutine = oldRoutine }
        routine = draft.approved()
        session = routine.map { RoutineSession(routine: $0) }
        pendingScreenTimeProposal = nil
        guard persist() else {
            routine = oldRoutine
            previousRoutine = oldPrevious
            session = oldSession
            history = oldHistory
            budgetAndFeedback = oldBudget
            pendingScreenTimeProposal = proposal
            return false
        }
        approvalCount += 1
        notice = AppLanguage.localized("Update approved. Your next morning will use this routine.")
        return true
    }

    @discardableResult
    func discardPendingScreenTimeProposal() -> Bool {
        // A successful refresh may invalidate this independent derived value
        // while an unrelated observation analysis is running.
        guard !privacyBlocksWork, let proposal = pendingScreenTimeProposal else { return false }
        pendingScreenTimeProposal = nil
        guard persist() else { pendingScreenTimeProposal = proposal; return false }
        notice = AppLanguage.localized("Suggestion discarded. Your current morning is unchanged.")
        return true
    }

    private func syntheticEvidenceProposal(evidence: PreparedLearningEvidence,
                                           preserving base: RoutineVersion?, preferences: RoutinePreferenceJournal) throws -> EvidenceRoutineProposal {
        guard usesSyntheticProposalFixture,
              evidence.sourceSnapshots.allSatisfy({ $0.origin == .synthetic }) else {
            throw AppleIntelligenceError.insufficientActivityEvidence
        }
        var seen = Set<UUID>()
        let citations = evidence.units.filter { $0.sourceLayer != .screenTimeAggregate && seen.insert($0.acquisitionID).inserted }.map {
            RoutineEvidenceCitationInput(unitID: $0.id, quote: String($0.text.prefix(220)))
        }
        return try LearningEvidencePreparation.assemble(evidence: evidence, steps: [
            EvidenceRoutineStepInput(title: AppLanguage.localized("A morning to review"),
                detail: AppLanguage.localized("Synthetic review fixture from the selected observations. No Apple model call."),
                kind: .custom, durationMinutes: 3, citations: citations)
        ], preserving: base, preferences: preferences, at: Date())
    }

    /// Returns true only after accepting ownership or starting an ordinary file import.
    /// The recorder must keep its ready URL until this returns true. Import saves
    /// evidence only and never starts routine inference.
    /// Names the app on each sampled screen while the frames are still in memory:
    /// Shortcuts "opened/closed" times for a recording made in MORE, then Apple's
    /// on-device image model where available. Images are discarded afterward.
    private func recognizeApps(in observation: MediaObservation, recordingContext: ObservationRecordingContext?,
                               attempt: UUID) async throws -> [ObservationFrameAppSignal] {
        guard let evidence = observation.videoEvidence else { return [] }
        var signals: [ObservationFrameAppSignal] = []
        var candidates = ObservedApp.suggested
        if let events = try? await AppTransitionLogStore.shared.events() {
            for app in events.map(\.app) where !candidates.contains(app) { candidates.append(app) }
            if let recordingContext {
                signals += ShortcutAppAlignment.signals(frames: evidence.frames,
                    recordingStartedAt: recordingContext.startedAt, events: events)
            }
        }
        // Frames already named by known apps' interface phrases skip the image model; review
        // recomputes those phrases each time, so they are not saved here.
        let named = Set(evidence.frames.filter {
            $0.outcome == .observed && !ObservationVisualAppRecognizer.screenListsApps($0.text, candidates: candidates)
                && ObservationAppSignatures.app(in: $0.text) != nil
        }.map(\.id))
        try Task.checkCancellation()
        guard acceptsAnalysis(attempt), visualAppRecognizer.isAvailable else { return signals }
        // Skip undecoded frames, frames already named by their text, and screens that list
        // many apps (App Library, an app picker).
        let decoded = Set(evidence.frames.filter {
            $0.outcome != .decodeFailed && !named.contains($0.id)
                && !ObservationVisualAppRecognizer.screenListsApps($0.text, candidates: candidates)
        }.map(\.id))
        let images = observation.frameImages.filter { decoded.contains($0.sampleID) }
        guard !images.isEmpty else { return signals }
        analysisStatus = String(localized: "Recognizing the apps on your screens…")
        let texts = Dictionary(uniqueKeysWithValues: evidence.frames.map { ($0.id, $0.text) })
        signals += try await visualAppRecognizer.recognize(frames: images, candidates: candidates, screenText: texts) { [weak self] done, total in
            guard let self, self.acceptsAnalysis(attempt), total > 0 else { return }
            self.progress = Double(done) / Double(total)
        }
        return signals
    }

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
                observationIssue = AppLanguage.localized("Your recording is saved. Finish the current activity, then retry understanding it.")
                return true
            }
            notice = AppLanguage.localized("Finish the current activity before importing another observation.")
            return false
        }
        // Save current corrections before a new import can replace the latest observation.
        // An app-owned recording has already been retained even if this write fails.
        guard saveObservationEdits() else { return ownedRecording }
        let attempt = beginAnalysis()
        analysisStatus = AppLanguage.localized("Reading your selected observation…")
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
                    notice = AppLanguage.localized("This observation is already saved. Your corrections and its date have been kept. Your routine is unchanged.")
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
                    observationIssue = AppLanguage.localized("No readable text was found in \(sampleCount) samples. Your previous observation is unchanged. ") +
                        (ownedRecording ? AppLanguage.localized("The recording is kept for retry or discard.") : AppLanguage.localized("Try a clearer or shorter recording."))
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
                    observationIssue = AppLanguage.localized("The selected file changed during analysis. Your previous observation is unchanged. Choose the file again.")
                    return
                }
                try Task.checkCancellation()
                guard acceptsAnalysis(attempt) else { return }
                let observedDate = try recordingContext.map {
                    try ObservationObservedDate(date: $0.startedAt, timeZoneIdentifier: $0.timeZoneIdentifier,
                        provenance: .recordingSession)
                }
                let appSignals = try await recognizeApps(in: observation, recordingContext: recordingContext, attempt: attempt)
                guard acceptsAnalysis(attempt) else { return }
                let entry = try ObservationAcquisition(id: recordingContext?.id ?? UUID(),
                    fileSHA256: fingerprint.sha256, observedDate: observedDate,
                    origin: ProcessInfo.processInfo.arguments.contains("--ui-testing") ? .synthetic : .unknown,
                    sourceKind: ObservationAcquisitionSourceKind(rawValue: observation.kind.rawValue) ?? .unknown,
                    sourceLabel: ownedRecording ? AppLanguage.localized("Your explicitly shared screen recording") : String(AppLanguage.localized("Selected file: \(selectedURL.lastPathComponent)").prefix(256)),
                    originalText: extracted, videoEvidence: observation.videoEvidence,
                    recordingContext: recordingContext, appSignals: appSignals)
                let id = try observationArchive.insert(entry)
                projectObservation(id)
                observationEditsNeedSave = true
                progress = 1
                guard persist() else {
                    busy = false
                    observationIssue = notice ?? AppLanguage.localized("The extracted text could not be saved. Your recording is kept for retry.")
                    return
                }
                guard finishOwnedRecordingImport(ownedRecording) else { return }
                busy = false
                notice = AppLanguage.localized("Observation saved. Review the text and its observed day before asking for a routine suggestion. Your routine is unchanged.")
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
            observationIssue = AppLanguage.localized("Retry or discard your saved recording before adding another one.")
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
            observationIssue = AppLanguage.localized("Your recording has not been imported or discarded. \(error.moreDescription)")
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
            notice = AppLanguage.localized("Saved recording discarded. Any previously saved observation text remains available.")
        } catch {
            observationIssue = AppLanguage.localized("The saved recording could not be removed. \(error.moreDescription)")
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
            observationIssue = AppLanguage.localized("Your extracted text is saved, but the temporary recording could not be removed. You can discard it below. \(error.moreDescription)")
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
        } catch { notice = error.moreDescription; return false }
    }

    /// A screen review is a separate user assertion. Never overwrite original OCR or
    /// accept an editor whose source changed while it was open.
    @discardableResult
    func saveFrameReview(_ review: ObservationFrameReview, expected: ObservationAcquisition) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive,
              saveObservationEdits() else { return false }
        guard observationArchive.entry(id: expected.id) == expected else {
            notice = AppLanguage.localized("This observation changed. Reopen the sampled screen before saving its label.")
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
            notice = AppLanguage.localized("This observation changed. Reopen the sampled screen before removing its label.")
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

    /// Save explicitly observed route categories and non-input gestures. A lesson
    /// becomes source-linked evidence; the person still reviews every future action.
    @discardableResult
    func saveBrowserRhythmObservation(_ summary: BrowserRhythmSummary) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive,
              saveObservationEdits(), summary.durationSeconds.isFinite else { return false }
        do {
            let entry = try ObservationAcquisition.browserLesson(summary: summary,
                observedDate: ObservationObservedDate(date: .now, timeZoneIdentifier: TimeZone.current.identifier, provenance: .userAssigned))
            return changeObservationArchive(selecting: entry.id) { _ = try $0.insert(entry) }
        } catch { notice = error.moreDescription; return false }
    }

    /// Evidence retention (#8): the one write MorningStore+Retention.swift makes. It replaces
    /// the parts a confirmed removal changes in a single save; a failed save changes nothing.
    func commitEvidenceRemoval(_ next: EvidenceRetentionWorkspace, removing ids: Set<UUID>) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive else { return false }
        let old = (observationArchive, routine, previousRoutine, session, pendingRoutineProposal)
        let oldSelection = (selectedObservationID, notes, observationVideoEvidence, observationContextClassification,
                            notesSourceLabel, observationEditsNeedSave)
        observationArchive = next.archive
        routine = next.currentRoutine; previousRoutine = next.previousRoutine; session = next.session
        pendingRoutineProposal = next.pendingProposal
        projectObservation(selectedObservationID.flatMap { ids.contains($0) ? nil : $0 })
        observationEditsNeedSave = true
        guard persist() else {
            (observationArchive, routine, previousRoutine, session, pendingRoutineProposal) = old
            (selectedObservationID, notes, observationVideoEvidence, observationContextClassification,
             notesSourceLabel, observationEditsNeedSave) = oldSelection
            return false
        }
        return true
    }

    /// Evidence retention (#8): a removal waits for the running analysis, which may hold an observation.
    func waitForRunningAnalysis() async { await analysisTask?.value }

    /// Evidence retention (#8): saves the "Keep raw evidence for…" choice.
    func saveEvidenceRetentionSetting() -> Bool { persist() }

    private func projectObservation(_ id: UUID?) {
        let entry = id.flatMap { observationArchive.entry(id: $0) }
        selectedObservationID = entry?.id
        notes = entry?.effectiveText ?? ""
        notesSourceLabel = entry?.sourceLabel ?? AppLanguage.localized("Your written observation")
        // Original video evidence remains inspectable in the observation detail.
        // Edited notes must never masquerade as its unmodified OCR interpretation.
        observationVideoEvidence = entry?.correctedText == nil ? entry?.videoEvidence : nil
        observationContextClassification = entry?.correctedText == nil ? entry?.classification : nil
    }

    /// A successful system read refreshes its dated sources atomically. The person's
    /// selected editor, corrections, approved routine and explicit selection stay separate.
    @discardableResult
    func saveScreenTimeEvidence(_ evidence: [ScreenTimeObservationEvidence]) -> Bool {
        guard !privacyBlocksWork, storageIsAvailable, !sessionActive else { return false }
        // A successful empty answer changes no historical source or correction.
        guard !evidence.isEmpty else { return true }
        guard saveObservationEdits() else { return false }
        return changeObservationArchive(selecting: selectedObservationID) { archive in
            for day in evidence { try archive.upsertScreenTime(day) }
        }
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
                notice = AppLanguage.localized("The observation change could not be saved. Your previous observations are unchanged.")
                observationSaveIssue = notice
                return false
            }
            return true
        } catch { notice = error.moreDescription; return false }
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
        #if DEBUG
        let joinFixture = args.contains("--ui-testing-learning-source-join")
        #else
        let joinFixture = false
        #endif
        guard args.contains("--ui-testing"), args.contains("--ui-testing-observation-archive") || joinFixture,
              args.first(where: { $0.hasPrefix("--ui-testing-workspace=") })
                .flatMap({ UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) }) != nil else { return }
        do {
            #if DEBUG
            if joinFixture {
                try seedLearningSourceJoinFixture()
                return
            }
            #endif
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

    #if DEBUG
    /// Only called by the isolated UI-test workspace guard above. All source data
    /// is manufactured and the existing synthetic proposal path discloses no model call.
    private func seedLearningSourceJoinFixture() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let at = { (day: Int, hour: Int) in calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        let readAt = at(14, 14)
        var apps = [ScreenTimeAppHour(bundleIdentifier: "com.burbn.instagram", seconds: 480)]
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-learning-source-many-apps") || arguments.contains("--ui-testing-learning-source-brief-apps") {
            let seconds: Double = arguments.contains("--ui-testing-learning-source-many-apps") ? 60 : 10
            apps += ["net.whatsapp.WhatsApp", "com.apple.mobilecal", "com.apple.mobilemail", "com.apple.mobilesafari",
                "com.apple.weather", "com.apple.Music", "com.apple.Maps", "com.apple.reminders", "com.google.Gmail",
                "com.chess.iphone", "com.google.ios.youtube"].map { ScreenTimeAppHour(bundleIdentifier: $0, seconds: seconds) }
        }
        let hours: [ScreenTimeHour] = [
            .init(interval: .init(start: at(13, 22), duration: 3600), firstPickup: at(13, 22),
                apps: [.init(bundleIdentifier: "com.apple.mobilemail", seconds: 300)]),
            .init(interval: .init(start: at(14, 7), duration: 3600), firstPickup: at(14, 7),
                longestActivity: .init(start: at(14, 7), duration: apps.reduce(0) { $0 + $1.seconds }), apps: apps)]
        let reports = try ScreenTimeObservationEvidence.make(hours: hours, queryStart: at(13, 18), now: readAt, calendar: calendar)
        let report = reports.first { $0.day == at(14, 0) }!
        let unknown = try ScreenTimeObservationEvidence.make(hours: [
            .init(interval: .init(start: at(15, 8), duration: 3600), firstPickup: at(15, 8),
                apps: [.init(bundleIdentifier: "com.burbn.instagram", seconds: 1200)])],
            queryStart: at(15, 0), now: at(15, 14), calendar: calendar)[0]
        let knownID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let unknownID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let browserID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        let videoID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        let observed = try ObservationObservedDate(date: at(14, 7), timeZoneIdentifier: calendar.timeZone.identifier, provenance: .userAssigned)
        var rhythm = BrowserRhythmAccumulator(site: .instagram)
        let segments = [BrowserLearningSegment(behavior: .browseFeed, startSeconds: 0, endSeconds: 10, gestures: 2)!,
                        BrowserLearningSegment(behavior: .watchStories, startSeconds: 20, endSeconds: 100, gestures: 2)!]
        guard rhythm.update(BrowserRhythmTotals(distance: 200, movingSeconds: 5, scrollBursts: 3, clicks: 2)!, segments: segments) else {
            throw ObservationArchiveError.invalidSource
        }
        let browser = try ObservationAcquisition.browserLesson(summary: rhythm.summary(durationSeconds: 110),
            observedDate: observed, importedAt: readAt, origin: .synthetic, id: browserID)
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
            text: "Apple Calendar\nA colleague shared the complete project agenda.")
        let video = try ObservationVideoEvidence(durationSeconds: 2, frames: [frame])
        let clip = try ObservationAcquisition(id: videoID, importedAt: readAt, observedDate: observed, origin: .synthetic,
            sourceKind: .video, sourceLabel: "SYNTHETIC — selected video", originalText: video.renderedText,
            videoEvidence: video, frameReviews: [.init(sampleID: frame.id, label: "Apple Calendar", evidenceQuote: "Apple Calendar", reviewedAt: readAt)])
        observationArchive = try .init(entries: [
            .screenTime(report, origin: .synthetic, id: knownID),
            .screenTime(unknown, origin: .synthetic, id: unknownID), browser, clip])
        projectObservation(nil)
        persist()
    }
    #endif

    func cancelAnalysis() {
        analysisTask?.cancel()
        // Keep the owner so privacy cleanup can await its actual completion.
        // Retain busy until the worker acknowledges cancellation, so a second model run cannot overlap.
        analysisStatus = AppLanguage.localized("Stopping analysis…")
    }

    /// Separate, explicit interpretation of the latest sampled screens. This never treats
    /// OCR order as touch events, grants action authority, or changes the approved routine.
    func recognizeObservationScreens() {
        guard !privacyBlocksWork else { return }
        guard let evidence = observationVideoEvidence, !busy, !sessionActive,
              evidence.frames.contains(where: \.canSupportIdentity), saveObservationEdits() else { return }
        let attempt = beginAnalysis()
        let acquisitionID = selectedObservationID
        analysisStatus = AppLanguage.localized("Recognizing the screens we sampled…")
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
                if persist() { notice = AppLanguage.localized("Screen observations updated. Review what was recognized and what remains unknown.") }
            } catch { finishAnalysis(error: error, attempt: attempt) }
        }
    }

    func useManualRoutine() {
        guard !privacyBlocksWork else { return }
        guard !sessionActive, !busy else { notice = AppLanguage.localized("Stop this morning before creating another routine."); return }
        installCandidate(RoutineVersion(number: 1, sourceLabel: AppLanguage.localized("Created by you"), steps: [
            RoutineStep(title: AppLanguage.localized("Your morning"), detail: AppLanguage.localized("Review what matters today."), kind: .briefing, durationMinutes: 3, isRequired: true, automation: .spokenNote)
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
            notice = AppLanguage.localized("Finish the current activity before importing a routine.")
            return false
        }
        guard routine == expectedBase else {
            notice = AppLanguage.localized("Your routine changed while this file was open. Cancel and open the file again to review it.")
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
                notice = AppLanguage.localized("The imported draft could not be saved. Your current routine is unchanged.")
                return false
            }
            notice = AppLanguage.localized("Imported as a draft. Review and approve it when ready. Your saved choices still apply to future suggestions.")
            return true
        } catch {
            notice = error.moreDescription
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
        notice = AppLanguage.localized("Your previous approved routine is restored. Saved choices still apply to future suggestions.")
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
        analysisStatus = AppLanguage.localized("Finding the meaningful steps…")
        return attempt
    }

    private func acceptsAnalysis(_ attempt: UUID) -> Bool {
        analysisAttempt == attempt && !privacyBlocksWork
    }

    private func finishAnalysis(error: Error, attempt: UUID) {
        guard acceptsAnalysis(attempt) else { return }
        busy = false
        progress = 0
        notice = error is CancellationError ? AppLanguage.localized("Analysis stopped. Your existing routine is unchanged.") : error.moreDescription
        if hasPendingRecording || hasImportedObservation { observationIssue = notice }
    }

    func saveVoicePreference() { persist() }

    func executionPreferencesChanged() {
        guard !privacyBlocksWork else { return }
        #if MORE_JURY_DEMO
        if !automatic || !readAloud { juryDemoVoice.pause() }
        guard persist() else { pauseAfterSaveFailure(); return }
        return
        #endif
        if automatic { startHandsFreeVoice() } else { stopHandsFreeVoice() }
        cancelStepPlayback()
        speech.stop()
        guard persist() else { pauseAfterSaveFailure(); return }
        // The greeting or recap, if one was still being read, has just stopped. A
        // hands-free morning then starts its routine; a normal one keeps waiting.
        if !openingListeningSettingsChanged() { runCurrentIfEnabled() }
    }

    func healthExtraWasDisabled() {
        if session?.status == .running { pause() }
        endOpening()
        speech.stop()
        stopHandsFreeVoice()
    }

    func openCapture(text: String = "", source: QuickCaptureSource = .typed, kindHint: QuickCaptureKind? = nil) {
        guard !privacyBlocksWork else { return }
        completionCaptureReviewID = nil
        completionInvitationSessionID = nil
        stopCompletionInvitation()
        capturePrefill = text
        captureSource = source
        captureKindHint = kindHint
        capturePresented = true
    }

    @discardableResult
    func saveCapture(kind: QuickCaptureKind, text: String, date: Date?, duration: Int = 30,
                     saveToSystem: Bool, id: UUID, source: QuickCaptureSource) async -> Bool {
        guard !privacyBlocksWork, !captureBusy else { return false }
        let generation = dataGeneration
        guard pendingCaptures[id.uuidString] == nil else {
            notice = AppLanguage.localized("This save has an unconfirmed outcome. Check the Apple app before trying again.")
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
                    guard let date else { notice = AppLanguage.localized("Choose a date and time for the calendar event."); return false }
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
                    pendingCaptures[id.uuidString] = AppLanguage.localized("Reminders")
                    upsertCapture(capture)
                    guard persist() else { pendingCaptures[id.uuidString] = nil; return false }
                    receipt = try reminders.createReminder(from: ReminderDraft(title: text, dueDate: date,
                        notifyAtDueTime: date != nil))
                case .calendarIdea:
                    guard let date else { notice = AppLanguage.localized("Choose a date and time for the calendar event."); return false }
                    try await reminders.requestCalendarWriteAccess()
                    guard dataGeneration == generation, !privacyBlocksWork, !Task.isCancelled else { return false }
                    pendingCaptures[id.uuidString] = AppLanguage.localized("Calendar")
                    upsertCapture(capture)
                    guard persist() else { pendingCaptures[id.uuidString] = nil; return false }
                    receipt = try reminders.createCalendarEvent(from: CalendarEventDraft(title: text,
                        startDate: date, endDate: date.addingTimeInterval(Double(duration) * 60)))
                default: notice = AppLanguage.localized("Choose a reminder or calendar event to save to Apple apps."); return false
                }
                receipts[id.uuidString] = receipt.id
                pendingCaptures[id.uuidString] = nil
            }
            upsertCapture(capture)
            notice = saveToSystem ? (kind == .reminder ? AppLanguage.localized("Saved in Apple Reminders and your notes.") : AppLanguage.localized("Saved in Apple Calendar and your notes.")) : AppLanguage.localized("Saved on this device.")
            let saved = persist()
            if !saved && saveToSystem {
                notice = (kind == .reminder ? AppLanguage.localized("Apple saved this item, but the local receipt could not be saved. Check Apple Reminders before trying again.") : AppLanguage.localized("Apple saved this item, but the local receipt could not be saved. Check Apple Calendar before trying again."))
            }
            // A completed external write dismisses the draft even if the local disk write failed.
            return saved || saveToSystem
        } catch {
            guard dataGeneration == generation, !privacyBlocksWork else { return false }
            notice = pendingCaptures[id.uuidString] == nil ? error.moreDescription :
                AppLanguage.localized("The Apple app save could not be confirmed. Check it before retrying. \(error.moreDescription)")
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

    func runCurrentIfEnabled() {
        #if MORE_JURY_DEMO
        guard !privacyBlocksWork, session?.status == .running else { return }
        beginJuryDemo()
        return
        #endif
        guard !privacyBlocksWork else { return }
        guard openingPresentation == nil else { return }
        guard !voiceInputBlocksPlayback else { return }
        guard let session, session.status == .running else { return }
        if currentStep?.automation == .gmailInbox {
            guard beginTargetStep(), self.session?.status == .running, activeStepTimer != nil else { return }
            beginMailMorning(); return
        }
        if beginTargetStep() { return }
        recordExecution(.running)
        if automatic {
            stepExecutor.spokenEnabled = readAloud
            automation.runCurrentStep(in: session, onFailure: { [weak self] context, reason in
                self?.presentNativeStepFailure(context: context, reason: reason)
            }) { [weak self] context in
                guard let self, self.session?.id == context.executionID.sessionID,
                      self.session?.currentStep?.id == context.executionID.stepID,
                      self.session?.status == .running else { return }
                self.completeAutomatedStep(sessionID: context.executionID.sessionID, stepID: context.executionID.stepID)
            }
        } else if readAloud { readCurrent() }
    }

    func handleSpeechInterruption() {
        guard session?.status == .running, speech.state == .paused else { return }
        let message = speech.lastError ?? AppLanguage.localized("Audio was interrupted. Continue when you're ready.")
        pause()
        notice = message
    }

    private func pauseAfterSaveFailure() {
        pauseStepTimer()
        endOpening()
        cancelStepPlayback()
        speech.stop()
        if session?.status == .running { try? session?.pause() }
        synchronizeMorningActivity()
        // Preserve the disk-error message and do not dispatch another action.
    }

    private func archiveTerminalSession() {
        guard let session, session.status == .completed || session.status == .stopped else { return }
        do {
            #if MORE_JURY_DEMO
            let isSynthetic = true
            #else
            let isSynthetic = session.routine.isSynthetic
            #endif
            history.upsert(try MorningRunRecord(session: session, timeZoneIdentifier: sessionTimeZone,
                isSynthetic: isSynthetic,
                timingInterrupted: sessionTimingInterrupted))
        } catch { notice = AppLanguage.localized("This morning could not be added to history: \(error.moreDescription)") }
    }

    @discardableResult
    func persist() -> Bool {
        guard !privacyBlocksWork else { return false }
        if let snapshotRecoveryError {
            morningActivitySaveBlocked = true
            synchronizeMorningActivity()
            notice = AppLanguage.localized("\(snapshotRecoveryError) Your existing file is protected; new changes cannot be saved until it can be restored.")
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
            // A Screen Time suggestion was made against one routine; any other routine makes it stale.
            try privacyControl.withReadyAccess { _ in
                try snapshot.save(WorkspaceSnapshot(routine: routine, session: session, previousRoutine: previousRoutine,
                history: history, captures: captures, receipts: receipts, sessionTimeZone: sessionTimeZone,
                automatic: automatic, readAloud: readAloud, handsFreeListeningSuppressedSessionID: handsFreeListeningSuppressedSessionID,
                showMorningOnLockScreen: showMorningOnLockScreen,
                sessionTimingInterrupted: sessionTimingInterrupted,
                budgetAndFeedback: budgetAndFeedback,
                pendingCaptures: pendingCaptures, voiceIdentifier: nil, voiceGender: speech.voiceGender.rawValue,
                observationNotes: notes.isEmpty ? nil : notes,
                observationSource: notes.isEmpty && observationVideoEvidence == nil ? nil : notesSourceLabel,
                observationVideoEvidence: observationVideoEvidence,
                observationContextClassification: observationContextClassification.map(RecoverableObservationClassification.init),
                observationArchive: observationArchive, selectedObservationID: selectedObservationID,
                pendingRoutineProposal: validProposal.map(RecoverableRoutineProposal.init),
                pendingScreenTimeProposal: pendingScreenTimeProposal.flatMap { $0.baseRoutineID == routine?.id && $0.isCurrent(preferences: routinePreferences) ? $0 : nil },
                consumedMorningEntryIDs: consumedMorningEntryIDs,
                routinePreferences: unreadablePreferences ?? .init(routinePreferences),
                greeting: greetingState, executionRecords: executionRecords, evidenceRetentionDays: evidenceRetentionDays, setAside: setAsideWorkspaceElements))
            }
            pendingRoutineProposal = validProposal
            if let proposal = pendingScreenTimeProposal,
               proposal.baseRoutineID != routine?.id || !proposal.isCurrent(preferences: routinePreferences) { pendingScreenTimeProposal = nil }
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
            notice = AppLanguage.localized("Your change is in memory, but saving failed: \(error.moreDescription)")
            if observationEditsNeedSave { observationSaveIssue = notice }
            return false
        }
    }

    /// The durable marker closes all writers before cleanup begins. Interrupted
    /// removal stays closed on launch and is retried; old snapshots are never
    /// restored as a rollback after any deletion has begun.
    func forgetLocalData() async {
        #if MORE_JURY_DEMO
        juryDemoVoice.stop()
        juryDemoBrowser.close()
        juryDemoCaption = ""
        juryDemoWebURL = nil
        juryDemoPendingWebURL = nil
        #endif
        guard !privacyIsForgetting else { return }
        let control: LocalDataControlState
        do {
            control = try privacyControl.beginForget()
        } catch {
            privacyNotice = .removalDidNotStart(error)
            return
        }
        guard let generation = control.generation else { return }
        #if MORE_JURY_DEMO
        dataGeneration = generation
        do { try JuryDemoReminder.forget(directory: LocalDataControl.defaultDirectory) }
        catch {
            privacyNeedsCleanup = true
            privacyHasInterruptedRemoval = true
            privacyNotice = .removalFailed(error)
            return
        }
        #endif
        permissionSetup.cancelForPrivacy()
        privacyIsForgetting = true
        privacyHasInterruptedRemoval = true
        privacyNeedsCleanup = true
        activityLoggingAllowed = false
        dataGeneration = generation
        MorePersonalMemory.shared.invalidatePendingUpdates()
        privacyNotice = .removing
        showMorningOnLockScreen = false
        morningActivityStartSessionID = nil
        morningActivityStartRequestID = nil
        analysisAttempt = nil
        let oldAnalysis = analysisTask
        oldAnalysis?.cancel()
        cancelScreenTimeRead()
        briefing.cancelAndClear()
        connectedAPITask?.cancel(); connectedAPITask = nil
        connectedActionStatus = nil
        clearNativeMoment(forPrivacy: true)
        clearSlackReply()
        clearGoogleCalendarDay()
        clearCalendlyDay()
        clearOutlookInbox()
        connectedMoment.clear()
        routineWebMoment.clear()
        composio.cancelPendingOperations()
        nativeConnections.cancelPendingWork()
        stepExecutor.clear()
        endOpening()
        cancelStepPlayback()
        speech.stop()
        cancelVoiceCommandTurn()
        stopHandsFreeVoice()
        mailMorning.clear()
        mailBudgetWork = [:]; mailBudgetDeadlinePaused = nil
        executionSpeechTask?.cancel(); executionSpeechTask = nil
        cancelCompletionCapture()
        releaseVoiceInput()
        MorningIntentRouter.shared.resetPendingRequests()
        do {
            await cloudVoice.stopAndRelease()
            try MoreLanguageModel.shared.forget()
            try await handsFreeVoice.stopAndRelease()
            try await morningActivity.endAllForPrivacy()
            // SDK streams may ignore cancellation. Never report successful
            // removal while a private Screen Time query still owns its task.
            for _ in 0..<50 where !screenTimeReadIsQuiescent {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard screenTimeReadIsQuiescent else {
                throw NSError(domain: "MORE.Privacy", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    AppLanguage.localized("Screen Time is still stopping. Try removal again in a moment.")])
            }
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
            await nativeConnections.quiesce()
            try nativeConnections.clearForPrivacy()
            try composio.clearLocalCredentials()
            endStepTimer()
            try MorningAlarmService.shared.forget()
            await WebMorningController.clearAllSignIns()
            try privacyControl.withForgetAccess(expectedGeneration: generation) {
                try GmailCredentialStore.removeSavedConnection()
                try recordingRecovery.removeAllOwnedData()
                // SEGMENTED SESSIONS (#27) ARE NOT FORGOTTEN HERE YET. Nothing in the app
                // creates one today. The change that first constructs a
                // `RecordingSessionStore` in this target must add, right here:
                //   try RecordingSessionStore(directory: <the workspace folder>).forgetAll()
                // which removes `RecordingSessions/<session>/` manifests and segment files.
                // The sessions' observations go with the archive, which this forget clears.
                // A package test (SegmentedSessionForgettingGuardTests) fails if the app
                // starts using the store without calling `forgetAll`.
                for name in ["app-transitions.json", "morning-invitation.json", "briefing-settings.json", "step-timer.json", "morning-alarm.json", "permission-setup.json", "browser-action-journal.json", "browser-reply-journal.json", "personal-memory.json", "gmail-send-journal.json", "gmail-attention-preferences.json", "native-moment-journal.json", "slack-reply-journal.json", EvidenceRemovalMarker.fileName, MorningExtrasPreferencesStore.fileName] {
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
                    automatic: true, readAloud: true, handsFreeListeningSuppressedSessionID: nil, pendingCaptures: [:],
                    observationArchive: ObservationArchive(), consumedMorningEntryIDs: [],
                    routinePreferences: .init(RoutinePreferenceJournal())))
            }
            clearForgottenMemory()
            try privacyControl.finishForget(expectedGeneration: generation)
            try morningActivity.resetAfterPrivacyCleanup()
            briefing.reloadSettings()
            permissionSetup.resetAfterPrivacy()
            extras.reload()
            privacyNeedsCleanup = false
            privacyHasInterruptedRemoval = false
            privacyIsForgetting = false
            privacyNotice = .removed
            privacyCompletedID = UUID()
            connectRecordingRecovery()
        } catch {
            // Cleanup can be partial. Keep the durable marker and do not claim
            // either complete removal or preservation of the original workspace.
            privacyIsForgetting = false
            privacyNotice = .removalFailed(error)
        }
    }

    func setActivityLoggingAllowed(_ allowed: Bool) {
        guard !privacyBlocksWork else { return }
        do {
            try privacyControl.setActivityLoggingAllowed(allowed)
            activityLoggingAllowed = allowed
            privacyNotice = .activityLogging(allowed)
        } catch { privacyNotice = .loggingSaveFailed(error) }
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
        endOpening(); greetingState.reset()
        routine = nil; session = nil; previousRoutine = nil
        notes = ""; notesSourceLabel = AppLanguage.localized("Your written observation")
        observationArchive = ObservationArchive(); selectedObservationID = nil
        observationVideoEvidence = nil; observationContextClassification = nil
        observationSaveIssue = nil; observationEditsNeedSave = false; observationIssue = nil
        pendingRoutineProposal = nil
        pendingScreenTimeProposal = nil
        screenTimeBusy = false; screenTimeMessage = nil; screenTimeAccess = .notAsked
        screenTimeLearning = nil
        evidenceRetentionDays = nil; evidenceRemovalStatus = nil; evidenceRemovalInProgress = false
        setAsideWorkspaceElements = []
        routinePreferences = RoutinePreferenceJournal(); routinePreferencesIssue = nil; unreadablePreferences = nil
        history = MorningHistory(); captures = []; receipts = [:]; pendingCaptures = [:]
        executionRecords = []; webExecutionEvent = nil
        clearNativeMoment(forPrivacy: true)
        clearSlackReply()
        clearGoogleCalendarDay()
        clearCalendlyDay()
        clearOutlookInbox()
        connectedMoment.clear()
        routineWebMoment.clear()
        stopHandsFreeVoice(); mailMorning.clear()
        cancelVoicePreparation(); handsFreeListeningSuppressedSessionID = nil
        mailBudgetWork = [:]; mailBudgetDeadlinePaused = nil
        budgetAndFeedback = RoutineBudgetAndFeedback(); savedRunEndings = []
        pendingRecordingURL = nil; pendingRecordingShouldAutoProcess = false
        pendingRecordingInterruption = nil; pendingRecordingContext = nil
        captureBusy = false; capturePresented = false; capturePrefill = ""; captureSource = .typed
        captureKindHint = nil; closingQuestions = nil; closingQuestionInReview = nil
        voiceCommandPresented = false; captureVoicePresented = false
        voiceCommandFeedback = nil; completionCaptureFeedback = nil
        voiceCommandDeduplicator = MorningVoiceCommandDeduplicator()
        completionInvitationSessionID = nil; lastCompletionOffered = nil; savedCompletionSessionID = nil
        dismissedReflectionSessionID = nil; completionVoiceSessionID = nil; pendingSpokenCapture = nil
        morningDetailPresented = false; observationDetailPresented = false
        observationSelectionPresented = false; routineProposalPresented = false
        consumedMorningEntryIDs = []; sessionTimingInterrupted = false; sessionTimeZone = TimeZone.current.identifier
        setAsideWorkspaceElements = []
        readAloud = true; automatic = true; speech.voiceIdentifier = nil; speech.voiceGender = .female
        naturalSpeechConsent = nil; naturalSpeechDeclined = nil
        naturalSpeechFailed = false; voiceFallbackMessage = nil
        speech.cloudSpeech = nil; speech.externalSpeechFallback = nil
        showMorningOnLockScreen = false; morningActivityIssue = nil; morningActivitySaveBlocked = false
        morningActivityStartSessionID = nil
        morningActivityStartRequestID = nil
        busy = false; progress = 0; analysisStatus = ""; snapshotRecoveryError = nil; snapshotRecoveryPart = nil; notice = nil
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
        } catch { notice = "Synthetic privacy fixture failed: \(error.moreDescription)" }
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

#if MORE_JURY_DEMO
extension MorningStore {
    /// The prepared routine belongs only to this bundle's container. It is never
    /// presented as a learned observation or installed in ordinary MORE.
    private func configureJuryDemo() {
        guard storageIsAvailable else { return }
        let morningLabel = String(localized: "My morning", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        let wakeUpDetail = String(localized: "Sleep, weather and a few tips to start your day.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        if routine == nil {
            routine = RoutineVersion(sourceLabel: morningLabel, steps: [
                RoutineStep(title: "Mon réveil", detail: wakeUpDetail, kind: .wellbeing, durationMinutes: 1),
                RoutineStep(title: "Mes messages", detail: "Conversation et réponse Gmail réelle au destinataire configuré.", kind: .messages, durationMinutes: 2),
                RoutineStep(title: "Mon moment Instagram", detail: "Mon compte dans le navigateur de MORE.", kind: .entertainment, durationMinutes: 1),
                RoutineStep(title: "Prêt à partir", detail: "Retrouver les actions réellement confirmées.", kind: .calendar, durationMinutes: 1)
            ], isApproved: true)
            persist()
        } else if routine?.sourceLabel == "Routine de démonstration préparée" {
            routine?.sourceLabel = morningLabel
            if let index = routine?.steps.firstIndex(where: { $0.detail == "Sommeil et météo préparés pour cette démonstration." }) {
                routine?.steps[index].detail = wakeUpDetail
            }
            persist()
        }
        juryDemoVoice.onText = { [weak self] text in
            guard let self, !privacyBlocksWork, sessionActive else { return }
            juryDemoCaption = text
        }
        juryDemoBrowser.onClose = { [weak self] in self?.juryDemoWebURL = nil }
        juryDemoVoice.onUserRequest = { [weak self] text in
            guard let self, !privacyBlocksWork, session?.status == .running else { return false }
            let context = juryDemoVoice.sessionID, generation = dataGeneration
            return juryDemoBrowser.handle(text) { [weak self] answer in
                guard let self, !privacyBlocksWork, dataGeneration == generation,
                      juryDemoVoice.sessionID == context else { return }
                juryDemoVoice.announce(answer)
            }
        }
        juryDemoVoice.onStateChange = { [weak self] _ in
            Task { @MainActor [weak self] in self?.juryDemoVoiceStateChanged() }
        }
        juryDemoVoice.onResponse = { [weak self] response in
            guard let self, !privacyBlocksWork, sessionActive, response.stage != "stopped" else { return }
            let index: Int
            switch response.stage {
            case "morning": index = 0
            case "mail", "draft": index = 1
            case "social": index = 2
            default: index = 3
            }
            // Stage projection records progress; it never dispatches a second action.
            if session?.status == .running {
                while session?.status == .running, let current = session?.currentStepIndex,
                      current < min(index, max(0, (session?.routine.steps.count ?? 1) - 1)) {
                    try? session?.advance()
                }
                persist()
            }
            if let receipt = response.receipt, receipt.status == "sent" {
                connectedActionStatus = response.text
            }
            if let action = response.action, action.type == "createReminder" {
                let generation = dataGeneration
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let result = await JuryDemoReminder.perform(action, service: reminders,
                        directory: LocalDataControl.defaultDirectory) { [weak self] in
                            guard let self else { return false }
                            return !privacyBlocksWork && dataGeneration == generation &&
                                juryDemoVoice.sessionID == response.sessionID && session?.status == .running
                        }
                    guard !privacyBlocksWork, dataGeneration == generation,
                          juryDemoVoice.sessionID == response.sessionID, let requestID = action.requestID else { return }
                    juryDemoVoice.acknowledgeAction(requestID: requestID, status: result.status, receiptID: result.receiptID)
                }
            }
            if let action = response.action, action.type == "openURL", let address = action.url,
               let url = URL(string: address), ["www.instagram.com", "www.tiktok.com"].contains(url.host ?? "") {
                if UIApplication.shared.applicationState == .active { presentJuryDemoBrowser(url) }
                else { juryDemoPendingWebURL = url }
            }
            synchronizeMorningActivity()
        }
        juryDemoVoice.onCompleted = { [weak self] in
            guard let self, !privacyBlocksWork, sessionActive else { return }
            juryDemoBrowser.close()
            juryDemoWebURL = nil
            juryDemoPendingWebURL = nil
            if session?.status == .paused { try? session?.resume() }
            while session?.status == .running { try? session?.advance() }
            archiveTerminalSession()
            persist()
            synchronizeMorningActivity()
        }
        JuryDemoPlaybackControls.receive = { [weak self] sessionID, command in
            guard let self, self.session?.id.uuidString == sessionID, sessionActive else { return false }
            switch command {
            case "pause": pause()
            case "resume": resume()
            case "stop": stop()
            case "next": advance()
            default: return false
            }
            return true
        }
    }

    func presentJuryDemoBrowser(_ url: URL) {
        guard !privacyBlocksWork, sessionActive else { return }
        juryDemoBrowser.open(url)
        juryDemoWebURL = url
    }

    func juryDemoVoiceStateChanged() {
        guard !privacyBlocksWork, sessionActive else { return }
        switch juryDemoVoice.state {
        case .paused, .failed:
            if session?.status == .running { pause() }
        case .idle:
            if session?.status == .running { stop() }
        default: break
        }
        synchronizeMorningActivity()
    }

    func beginJuryDemo() {
        guard !privacyBlocksWork, session?.status == .running else { return }
        guard naturalSpeechDeclined != naturalSpeechScope else {
            pause()
            juryDemoCaption = String(localized: "Online voice is off for this morning. Stop and start a new morning to change this choice.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            return
        }
        guard handsFreeListeningSuppressedSessionID != session?.id, automatic, readAloud else {
            juryDemoCaption = "L’écoute ou la lecture est désactivée pour ce matin. Vous pouvez les préparer dans les paramètres."
            return
        }
        if juryDemoVoice.state == .paused { juryDemoVoice.resume(language: AppLanguage.isFrench ? .french : .english) }
        else if !juryDemoVoice.isActive {
            juryDemoVoice.start(language: AppLanguage.isFrench ? .french : .english)
        }
    }
}
#endif
