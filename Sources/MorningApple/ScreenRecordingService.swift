import Foundation
import MorningCore
import Observation

/// The importer owns a handed-off recording until extraction finishes. Cleanup
/// accepts only this app's recording namespace, never a selected source elsewhere.
public enum ScreenRecordingFiles {
    public static var directory: URL {
        recordingDirectory(arguments: ProcessInfo.processInfo.arguments,
            workspaceDirectory: LocalDataControl.defaultDirectory,
            temporaryDirectory: FileManager.default.temporaryDirectory)
    }

    static func recordingDirectory(arguments: [String], workspaceDirectory: URL,
                                   temporaryDirectory: URL) -> URL {
        // Even an invalid test launch never falls back to the person's normal
        // recording namespace. Admission and sweep additionally reject that launch.
        let base = arguments.contains("--ui-testing") ? workspaceDirectory : temporaryDirectory
        return base.appendingPathComponent("MorningOperatorRecordings", isDirectory: true)
    }

    static func validateTestNamespace(arguments: [String] = ProcessInfo.processInfo.arguments) throws {
        guard arguments.contains("--ui-testing") else { return }
        guard let value = arguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") }),
              UUID(uuidString: String(value.dropFirst("--ui-testing-workspace=".count))) != nil else {
            throw RecordingCleanupError.invalidTestWorkspace
        }
    }

    static func isRecordingFilename(_ name: String) -> Bool {
        guard name.hasPrefix("morning-"), name.hasSuffix(".mp4") else { return false }
        return UUID(uuidString: String(name.dropFirst("morning-".count).dropLast(".mp4".count))) != nil
    }

    public static func isOwnedRecording(_ url: URL) -> Bool {
        url.isFileURL && isRecordingFilename(url.lastPathComponent)
            && url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
    }

    @discardableResult
    public static func removeIfOwned(_ url: URL) throws -> Bool {
        guard isOwnedRecording(url) else { return false }
        try validateTestNamespace()
        try RecordingFileCleanup.remove(in: directory, names: [url.lastPathComponent])
        return true
    }

    /// Call only after all native capture/writer operations have stopped. The
    /// caller owns lifecycle serialization; this function never follows symlinks
    /// or deletes unrelated filenames or unexpected directories.
    public static func removeAllOwnedRecordings() throws {
        try validateTestNamespace()
        try RecordingFileCleanup.removeRecordings(in: directory)
    }
}

public enum ScreenRecordingState: String, Sendable, Equatable {
    case idle, choosing, starting, recording, stopping, ready, failed
}

/// An elapsed recording limit, not a measurement of device or user inactivity.
public enum ScreenRecordingDuration: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case fiveMinutes = 300
    case tenMinutes = 600
    case twentyMinutes = 1_200
    case thirtyMinutes = 1_800

    public var id: Int { rawValue }
    public var displayName: String { String(localized: "\(rawValue / 60) minutes", bundle: .module) }
}

/// The writer's deadline is a waiting state, not a terminal error. This is the
/// native service's authoritative completion policy, shared with deterministic
/// tests. File validation and durable recovery ownership still follow retention.
struct ScreenRecordingFinalizationState: Sendable {
    enum Disposition: Equatable { case waiting, retain, discard }

    private(set) var writerFinished = false
    private(set) var discardRequested = false
    private(set) var failureDetail: String?
    private(set) var deadlineExceeded = false

    mutating func requestDiscard() { discardRequested = true }

    mutating func fail(_ detail: String) {
        failureDetail = failureDetail ?? detail
        discardRequested = true
    }

    mutating func writerDidFinish(error: String?) {
        writerFinished = true
        if let error { fail(error) }
    }

    mutating func finalizationTimedOut() {
        // No discard/failure mutation: a later successful close stays recoverable.
        deadlineExceeded = true
    }

    func disposition(streamStopped: Bool, startPending: Bool) -> Disposition {
        guard streamStopped, writerFinished, !startPending else { return .waiting }
        return discardRequested || failureDetail != nil ? .discard : .retain
    }
}

/// The service's provenance lifecycle is independent of capture-resource cleanup: a
/// finalized URL keeps its context until durable handoff succeeds or it is discarded.
/// Stale or duplicate native callbacks cannot replace the current session's first start.
struct ScreenRecordingContextState {
    private var sessionID: UUID?
    private(set) var context: ObservationRecordingContext?

    mutating func begin(sessionID: UUID) {
        self.sessionID = sessionID
        context = nil
    }

    mutating func recordingDidStart(sessionID: UUID, startedAt: Date, timeZoneIdentifier: String) {
        guard self.sessionID == sessionID, context == nil else { return }
        // Invalid metadata stays unknown; it must not turn a valid capture into a failure.
        context = try? ObservationRecordingContext(id: sessionID, startedAt: startedAt,
                                                  timeZoneIdentifier: timeZoneIdentifier)
    }

    mutating func clear() {
        sessionID = nil
        context = nil
    }
}

/// A stopped stream alone is insufficient: late starts and an attached writer
/// still own capture resources. This policy is shared by the native cleanup and
/// deterministic lifecycle tests, which do not claim to exercise ScreenCaptureKit.
struct ScreenRecordingCleanupStatus: Sendable {
    var startPending = false
    var stopPending = false
    var resourcesAttached = false
    var captureMayBeActive = false
    var needsStopRetry = false
    var isStopped: Bool { !startPending && !stopPending && !resourcesAttached && !captureMayBeActive }
}

@MainActor
enum ScreenRecordingCleanupBarrier {
    static func wait(timeout: Duration = .seconds(90),
                     status: @MainActor () -> ScreenRecordingCleanupStatus,
                     pause: @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }) async throws {
        let end = ContinuousClock.now.advanced(by: timeout)
        while true {
            let current = status()
            if current.isStopped { return }
            guard !current.needsStopRetry, ContinuousClock.now < end else {
                throw RecordingCleanupError.captureStopUnconfirmed
            }
            try await pause()
        }
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
import AVFoundation

/// Screen-only iOS 27 recording. No microphone, camera, Photos write, or automatic capture.
/// See Apple's `capturing-screen-content-on-ios` sample and SCStream.h's stop semantics.
@available(iOS 27.0, *)
@MainActor @Observable
public final class ScreenRecordingService {
    /// App-wide ownership lets recording survive dismissal of the recording sheet.
    /// Dismissing UI does not call `discard()`; the app retains a Stop/status control.
    public static let shared = ScreenRecordingService()

    // The picker is process-wide. An older cancelled request may finish after a new sheet
    // has taken ownership; its cleanup must never deactivate the new request's picker.
    private static var pickerOwnerID: UUID?
    public private(set) var state: ScreenRecordingState = .idle
    public private(set) var message = String(localized: "Choose what to share using Apple's screen-recording picker.", bundle: .module)
    public private(set) var elapsedSeconds = 0
    public private(set) var recordedURL: URL?
    public private(set) var recordingInterruption: String?
    /// Read this before accepting/taking the finalized URL. The time is captured at the
    /// recording-output start callback, before any main-actor scheduling delay.
    public var recordingContext: ObservationRecordingContext? { recordingProvenance.context }
    private var recordingProvenance = ScreenRecordingContextState()
    /// Called directly on finalization, including while the app is backgrounded. Return true
    /// only after durable ownership is accepted; false keeps the recorder's ready URL intact.
    /// `recordingContext` remains available throughout this callback; taking clears it.
    @ObservationIgnored public var onRecordingFinalized: (@MainActor (URL, String?) -> Bool)?
    public private(set) var needsStopRetry = false
    /// Remains true after failed Forget cleanup, preventing a new capture until retry.
    public private(set) var isDiscardingForForget = false
    @ObservationIgnored private var forgetCleanupTask: Task<Void, any Error>?
    public private(set) var selectedDuration: ScreenRecordingDuration = .tenMinutes
    public var maximumDurationSeconds: Int { selectedDuration.rawValue }
    public var remainingSeconds: Int { max(0, maximumDurationSeconds - elapsedSeconds) }

    public var isBusy: Bool { [.choosing, .starting, .recording, .stopping].contains(state) }
    /// Conservative lifecycle signal: a start, active capture, or shutdown may still be pending.
    /// `.recording` separately means the recording output acknowledged its start.
    public var captureMayBeActive: Bool { [.starting, .recording, .stopping].contains(state) }
    /// True only after stream stop and recording-output finalization have both completed.
    public var hasRecordingToReview: Bool { state == .ready && recordedURL != nil }
    public var isAvailable: Bool { SCContentSharingPicker.shared.isAvailable }
    /// A cancelled, still-unresolved start can outlive its sheet. The start completion retains
    /// this service and stops any late successful start. An active capture cannot be dismissed.
    public var canDismiss: Bool {
        !isBusy || (finalization.discardRequested && startPending && stream?.isCapturing == false)
    }

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: SCRecordingOutput?
    @ObservationIgnored private var bridge: ScreenRecordingDelegateBridge?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var temporaryURL: URL?
    @ObservationIgnored private var monitoring: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var startPending = false
    @ObservationIgnored private var startSucceeded = false
    @ObservationIgnored private var outputStarted = false
    @ObservationIgnored private var stopPending = false
    @ObservationIgnored private var stopAttemptID: UUID?
    @ObservationIgnored private var streamStopped = false
    @ObservationIgnored private var finalization = ScreenRecordingFinalizationState()
    @ObservationIgnored private var stopReason: String?
    // Only an acknowledged active capture takes this lease. Start/stop completion closures
    // retain their own operation until it returns, including if the sheet has gone away.
    @ObservationIgnored private var activeLifetime: ScreenRecordingService?

    private enum DeadlineKind { case start, stop, finalization }

    public init() {}

    /// Presents Apple's picker only in response to the user's Start recording button.
    public func presentPicker(duration: ScreenRecordingDuration = .tenMinutes) {
        guard !isBusy, state != .ready else { return }
        guard temporaryURL == nil else {
            message = String(localized: "Discard the remaining recording before starting another one.", bundle: .module)
            return
        }
        if let issue = recordingAdmissionIssue() {
            state = .failed; message = issue; return
        }
        guard isAvailable else {
            fail(String(localized: "Screen recording isn't available on this device or is restricted by its settings.", bundle: .module))
            return
        }
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        guard modes.contains("screen-capture") else {
            fail(String(localized: "This build needs the screen-capture background mode before it can record across apps.", bundle: .module))
            return
        }
        let token = UUID()
        sessionID = token
        recordingProvenance.begin(sessionID: token)
        selectedDuration = duration
        elapsedSeconds = 0
        recordedURL = nil
        recordingInterruption = nil
        startPending = false
        startSucceeded = false
        outputStarted = false
        stopPending = false
        stopAttemptID = nil
        finalization = ScreenRecordingFinalizationState()
        streamStopped = false
        needsStopRetry = false
        stopReason = nil
        let delegate = ScreenRecordingDelegateBridge(owner: self, sessionID: token)
        bridge = delegate
        let picker = SCContentSharingPicker.shared
        Self.pickerOwnerID = token
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(delegate)
        picker.isActive = true
        state = .choosing
        message = String(localized: "Confirm screen sharing in the system picker to begin.", bundle: .module)
        picker.present()
    }

    /// Also retries a stop after a recoverable stop error or timeout.
    public func stopRecording() {
        guard state == .starting || state == .recording || state == .stopping else { return }
        requestShutdown(reason: String(localized: "Your recording is ready to review.", bundle: .module))
    }

    public func discard() {
        finalization.requestDiscard()
        if state == .choosing {
            detachPicker()
            releaseStoppedResources()
            recordingProvenance.clear()
            state = .idle
        } else if isBusy {
            requestShutdown(reason: String(localized: "Recording discarded.", bundle: .module))
        } else {
            if removeTemporaryFile() {
                state = .idle
                elapsedSeconds = 0
            }
        }
    }

    /// Forget owns cleanup once started, even if its calling UI disappears. A
    /// timeout or native stop error keeps ownership and suppression intact for
    /// retry; neither is evidence that capture ended. Native callbacks retain
    /// their existing late-start/stop safety and never hand off a forgotten clip.
    public func discardAndWait() async throws {
        if let task = forgetCleanupTask { try await task.value; return }
        isDiscardingForForget = true
        finalization.requestDiscard()
        let task = Task { @MainActor [self] in
            defer { forgetCleanupTask = nil }
            discard()
            try await ScreenRecordingCleanupBarrier.wait(status: {
                ScreenRecordingCleanupStatus(startPending: startPending, stopPending: stopPending,
                    resourcesAttached: stream != nil || output != nil,
                    captureMayBeActive: captureMayBeActive, needsStopRetry: needsStopRetry)
            })
            // Active resources are gone. Strict cleanup also catches orphaned
            // finalized files from a previous process, without deleting originals.
            try ScreenRecordingFiles.removeAllOwnedRecordings()
            temporaryURL = nil
            recordedURL = nil
            recordingInterruption = nil
            recordingProvenance.clear()
            elapsedSeconds = 0
            state = .idle
            message = String(localized: "App-owned recordings removed.", bundle: .module)
            isDiscardingForForget = false
        }
        forgetCleanupTask = task
        try await task.value
    }

    /// Transfers ownership. The importer must delete this app-owned URL after extraction.
    public func takeRecording() -> URL? {
        guard !isDiscardingForForget, recordingAdmissionIssue() == nil,
              state == .ready, let url = recordedURL else { return nil }
        recordedURL = nil
        temporaryURL = nil
        recordingProvenance.clear()
        state = .idle
        elapsedSeconds = 0
        return url
    }

    fileprivate func selection(_ selection: ScreenRecordingSelection, sessionID token: UUID) {
        guard sessionID == token, Self.pickerOwnerID == token, state == .choosing, selection.existingStreamID == nil,
              let bridge else { return }
        if let issue = recordingAdmissionIssue() {
            finalization.requestDiscard()
            requestShutdown(reason: issue)
            return
        }
        guard !selection.filter.isMicrophoneEnabled, !selection.filter.isCameraEnabled else {
            fail(String(localized: "This recording needs a screen-only selection with microphone and camera turned off.", bundle: .module))
            return
        }
        state = .starting
        message = String(localized: "Starting your screen recording…", bundle: .module)
        do {
            try FileManager.default.createDirectory(at: ScreenRecordingFiles.directory, withIntermediateDirectories: true)
            let url = ScreenRecordingFiles.directory.appendingPathComponent("morning-\(UUID().uuidString).mp4")
            temporaryURL = url
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = false
            // Only iOS-supported fields. Frame-rate and captureMicrophone setters are macOS-only.
            let rect = selection.filter.contentRect
            let scale = Double(selection.filter.pointPixelScale)
            let width = Double(rect.width) * scale
            let height = Double(rect.height) * scale
            if width.isFinite, height.isFinite, width > 0, height > 0 {
                let reduction = min(1, 1_920 / max(width, height))
                configuration.width = max(2, Int(width * reduction / 2) * 2)
                configuration.height = max(2, Int(height * reduction / 2) * 2)
            }
            let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: bridge)
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = url
            recordingConfiguration.outputFileType = .mp4
            recordingConfiguration.videoCodecType = .h264
            let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: bridge)
            self.stream = stream
            self.output = output
            bridge.provenance.bind(outputID: ObjectIdentifier(output))
            try stream.addRecordingOutput(output)
            startPending = true
            armDeadline(seconds: 20, token: token, kind: .start)
            // Strong capture intentionally retains the complete operation, including delegates,
            // until the SDK resolves start. A timeout is not evidence that start was cancelled.
            stream.startCapture { [self] error in
                let detail = error?.localizedDescription
                Task { @MainActor [self] in startCompleted(error: detail, token: token) }
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func startCompleted(error: String?, token: UUID) {
        guard sessionID == token else { return }
        reconcileOutputStart()
        startPending = false
        if let error {
            finalization.fail(error)
            if stream?.isCapturing != true && !outputStarted {
                // The start operation actually failed, and no writer ever started.
                streamStopped = true
                finalization.writerDidFinish(error: error)
                finishIfReady()
            } else {
                requestShutdown(reason: error)
            }
            return
        }
        startSucceeded = true
        // A success arriving after cancellation/deadline must still be stopped.
        if stream?.isCapturing == true {
            activeLifetime = self
            streamStopped = false
        }
        if finalization.discardRequested || finalization.failureDetail != nil || state == .stopping {
            requestShutdown(reason: stopReason ?? String(localized: "Stopping the cancelled recording request…", bundle: .module))
        } else if state == .starting {
            armDeadline(seconds: 20, token: token, kind: .start)
        }
    }

    fileprivate func pickerCancelled(sessionID token: UUID) {
        guard sessionID == token, Self.pickerOwnerID == token, state == .choosing else { return }
        detachPicker()
        releaseStoppedResources()
        recordingProvenance.clear()
        state = .idle
        message = String(localized: "Recording wasn't started.", bundle: .module)
    }

    fileprivate func pickerFailed(_ detail: String, sessionID token: UUID) {
        guard sessionID == token, Self.pickerOwnerID == token else { return }
        fail(detail)
    }

    fileprivate func recordingStarted(outputID: ObjectIdentifier, sessionID token: UUID) {
        guard sessionID == token, let output, ObjectIdentifier(output) == outputID,
              reconcileOutputStart() else { return }
        if finalization.discardRequested || finalization.failureDetail != nil || state == .stopping {
            requestShutdown(reason: stopReason ?? String(localized: "Stopping the cancelled recording request…", bundle: .module))
            return
        }
        guard state == .starting else { return }
        deadline?.cancel()
        deadline = nil
        state = .recording
        message = String(localized: "Go through your morning. Recording stops after \(selectedDuration.displayName), or you can stop it sooner.", bundle: .module)
        let started = ContinuousClock.now
        monitoring = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.sessionID == token, self.state == .recording else { return }
                self.elapsedSeconds = max(0, Int(started.duration(to: ContinuousClock.now).components.seconds))
                if self.elapsedSeconds >= self.maximumDurationSeconds {
                    self.requestShutdown(reason: String(localized: "Stopped at your \(self.maximumDurationSeconds / 60)-minute limit. Your recording is ready to review.", bundle: .module))
                    return
                }
                if (self.output?.recordedFileSize ?? 0) >= 256 * 1_024 * 1_024 {
                    self.requestShutdown(reason: String(localized: "Stopped at the recording size limit. Your recording is ready to review.", bundle: .module))
                    return
                }
            }
        }
    }

    fileprivate func recordingEnded(outputID: ObjectIdentifier, sessionID token: UUID, error: String?) {
        guard sessionID == token, let output, ObjectIdentifier(output) == outputID else { return }
        finalization.writerDidFinish(error: error)
        if !streamStopped {
            requestShutdown(reason: stopReason ?? String(localized: "Your recording finished and is ready to review.", bundle: .module))
        }
        finishIfReady()
    }

    fileprivate func streamEnded(streamID: ObjectIdentifier, sessionID token: UUID,
                                 wasUserStopped: Bool, detail: String) {
        guard sessionID == token, let stream, ObjectIdentifier(stream) == streamID else { return }
        // didStopWithError itself is a terminal stream notification, including system errors.
        streamStopped = true
        stopPending = false
        needsStopRetry = false
        monitoring?.cancel()
        monitoring = nil
        state = .stopping
        if !wasUserStopped {
            // A system interruption does not itself mean the writer's saved portion failed.
            // Keep it if didFinishRecording succeeds; didFail/timeout still discard it.
            recordingInterruption = String(localized: "The system interrupted this recording. It may cover only part of your morning.", bundle: .module)
        }
        stopReason = wasUserStopped
            ? String(localized: "Stopped using the system controls. Your recording is ready to review.", bundle: .module)
            : String(localized: "Recording was interrupted. The saved portion is ready to review. \(detail)", bundle: .module)
        message = String(localized: "Screen capture has stopped. Finishing the recording…", bundle: .module)
        armDeadline(seconds: 30, token: token, kind: .finalization)
        finishIfReady()
    }

    private func requestShutdown(reason: String) {
        monitoring?.cancel()
        monitoring = nil
        stopReason = stopReason ?? reason
        guard let stream, let token = sessionID else {
            // No stream was ever created, so there is no capture or writer to await.
            detachPicker()
            let removed = removeTemporaryFile()
            releaseStoppedResources()
            if removed {
                state = finalization.failureDetail == nil ? .idle : .failed
                message = finalization.failureDetail ?? reason
            }
            return
        }
        reconcileOutputStart()
        state = .stopping
        if startPending && !stream.isCapturing {
            message = String(localized: "Waiting for the system recording request to finish. Any late start will be stopped.", bundle: .module)
            // Do not fire stop while start is unresolved. The start completion is retained
            // and performs shutdown even if the user closes this cancelled request.
            return
        }
        if !startPending && !startSucceeded && !outputStarted && !stream.isCapturing {
            streamStopped = true
            finalization.writerDidFinish(error: nil)
            finishIfReady()
            return
        }
        if streamStopped {
            message = String(localized: "Screen capture has stopped. Finishing the recording…", bundle: .module)
            // The previous finalization deadline may have elapsed while start was still
            // pending. A late start completion must establish a fresh bounded writer wait.
            if !startPending && !finalization.writerFinished {
                needsStopRetry = false
                armDeadline(seconds: 30, token: token, kind: .finalization)
            }
            finishIfReady()
            return
        }
        guard !stopPending else { return }
        activeLifetime = self
        stopPending = true
        needsStopRetry = false
        message = String(localized: "Stopping and saving your recording…", bundle: .module)
        let attempt = UUID()
        stopAttemptID = attempt
        armDeadline(seconds: 30, token: token, kind: .stop)
        // Keep all capture resources alive until the actual stop result and writer callbacks.
        stream.stopCapture { [self] error in
            let detail = error?.localizedDescription
            Task { @MainActor [self] in stopCompleted(error: detail, token: token, attempt: attempt) }
        }
    }

    private func stopCompleted(error: String?, token: UUID, attempt: UUID) {
        guard sessionID == token else { return }
        if error == nil || (!startPending && stream?.isCapturing == false) {
            streamStopped = true
            stopPending = false
            needsStopRetry = false
            message = String(localized: "Screen capture has stopped. Finishing the recording…", bundle: .module)
            armDeadline(seconds: 30, token: token, kind: .finalization)
            finishIfReady()
        } else if stopAttemptID == attempt && !streamStopped {
            stopPending = false
            needsStopRetry = true
            deadline?.cancel()
            deadline = nil
            // Keep the stream, output, delegates and active lease. No file is published/deleted.
            message = String(localized: "Screen recording may still be active. Retry Stop or use the system screen-recording controls. \(error ?? "")", bundle: .module)
        }
    }

    private func finishIfReady() {
        let disposition = finalization.disposition(streamStopped: streamStopped, startPending: startPending)
        guard disposition != .waiting else { return }
        // didFinish/stream-stop tasks may reach the main actor before the start task.
        // Atomically recover/close callback-entry evidence before releasing its delegate.
        reconcileOutputStart(closing: true)
        let detail = finalization.failureDetail
        let finishedMessage = stopReason
        detachPicker()
        releaseStoppedResources()
        if disposition == .discard {
            if removeTemporaryFile() {
                state = detail == nil ? .idle : .failed
                message = detail ?? String(localized: "Recording discarded.", bundle: .module)
            }
            return
        }
        guard let url = temporaryURL else {
            recordingProvenance.clear()
            state = .failed
            message = String(localized: "The recording finished without a file to import.", bundle: .module)
            return
        }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
                removeTemporaryFile()
                state = .failed
                message = String(localized: "The recording contains no readable video. Please try a short recording again.", bundle: .module)
                return
            }
            recordedURL = url
            state = .ready
            message = finishedMessage ?? String(localized: "Your recording is ready to review.", bundle: .module)
            if recordingAdmissionIssue() == nil,
               onRecordingFinalized?(url, recordingInterruption) == true {
                _ = takeRecording()
            }
        } catch {
            removeTemporaryFile()
            state = .failed
            message = error.localizedDescription
        }
    }

    /// Native callbacks retain their start evidence synchronously. Applying that evidence
    /// is idempotent and does not change the UI state or launch a recording timer.
    @discardableResult
    private func reconcileOutputStart(closing: Bool = false) -> Bool {
        guard let token = sessionID, let output, let bridge,
              bridge.provenance.reconcile(into: &recordingProvenance, sessionID: token,
                                          outputID: ObjectIdentifier(output), closing: closing) else { return false }
        outputStarted = true
        activeLifetime = self
        return true
    }

    private func armDeadline(seconds: Int, token: UUID, kind: DeadlineKind) {
        deadline?.cancel()
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.sessionID == token else { return }
            switch kind {
            case .start:
                self.fail(String(localized: "The system recording request took too long. It is being cancelled; no file will be imported.", bundle: .module))
            case .stop:
                if !self.startPending && self.stream?.isCapturing == false {
                    self.streamStopped = true
                    self.stopPending = false
                    self.armDeadline(seconds: 30, token: token, kind: .finalization)
                    self.finishIfReady()
                } else {
                    self.stopPending = false
                    self.needsStopRetry = true
                    self.message = String(localized: "Stop hasn't been confirmed. Retry Stop or stop recording using the system controls.", bundle: .module)
                }
            case .finalization:
                guard self.streamStopped, !self.startPending else { return }
                // Keep ownership without converting a slow successful close into deletion.
                // Explicit discard/Forget and actual writer failures remain sticky.
                self.finalization.finalizationTimedOut()
                self.needsStopRetry = true
                self.message = self.finalization.failureDetail ?? (self.finalization.discardRequested
                    ? String(localized: "Screen capture stopped. Waiting for the recording to finish closing before it can be removed. Retry cleanup after it closes.", bundle: .module)
                    : String(localized: "Screen capture stopped. The recording is still closing and is being kept. Wait or retry Stop; it will be available after it finishes closing.", bundle: .module))
            }
        }
    }

    private func fail(_ detail: String) {
        finalization.fail(detail)
        recordedURL = nil
        requestShutdown(reason: detail)
    }

    private func detachPicker() {
        let picker = SCContentSharingPicker.shared
        if let bridge { picker.remove(bridge) }
        if let token = sessionID, Self.pickerOwnerID == token {
            picker.isActive = false
            Self.pickerOwnerID = nil
        }
    }

    /// Call only when no stream was created or capture is confirmed stopped.
    private func releaseStoppedResources() {
        monitoring?.cancel()
        deadline?.cancel()
        monitoring = nil
        deadline = nil
        bridge?.provenance.invalidate()
        stream = nil
        output = nil
        bridge = nil
        sessionID = nil
        startPending = false
        stopPending = false
        stopAttemptID = nil
        needsStopRetry = false
        activeLifetime = nil
    }

    @discardableResult
    private func removeTemporaryFile() -> Bool {
        do {
            if let temporaryURL {
                guard try ScreenRecordingFiles.removeIfOwned(temporaryURL) else {
                    throw RecordingCleanupError.unsafeDirectory
                }
            }
            temporaryURL = nil
            recordedURL = nil
            recordingProvenance.clear()
            return true
        } catch {
            // Keep the URL and provenance: a failed delete must remain retryable.
            state = .failed
            message = String(localized: "The app-owned recording couldn't be removed. Retry discarding it. \(error.localizedDescription)", bundle: .module)
            return false
        }
    }

    private func recordingAdmissionIssue() -> String? {
        guard !isDiscardingForForget else { return RecordingCleanupError.forgettingInProgress.localizedDescription }
        do {
            try ScreenRecordingFiles.validateTestNamespace()
            let control = try LocalDataControl(directory: LocalDataControl.defaultDirectory).status()
            return control.forgetPending ? RecordingCleanupError.forgettingInProgress.localizedDescription : nil
        } catch {
            return String(localized: "Local privacy cleanup needs attention before recording can continue. \(error.localizedDescription)", bundle: .module)
        }
    }
}

/// SCContentFilter exposes immutable selection properties on iOS. This wrapper transfers
/// that read-only framework token from its callback to the main actor exactly once; it is
/// not shared mutable app state. All stream creation and use stay on the main actor.
@available(iOS 27.0, *)
fileprivate struct ScreenRecordingSelection: @unchecked Sendable {
    let filter: SCContentFilter
    let existingStreamID: ObjectIdentifier?
}

/// Framework callbacks may arrive off-main. Only immutable IDs/messages and the read-only
/// picker selection cross into the main-actor service. Each attempt has a distinct token.
@available(iOS 27.0, *)
fileprivate final class ScreenRecordingDelegateBridge: NSObject, SCContentSharingPickerObserver,
    SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private weak var owner: ScreenRecordingService?
    private let sessionID: UUID
    let provenance: ScreenRecordingCallbackProvenance

    init(owner: ScreenRecordingService, sessionID: UUID) {
        self.owner = owner
        self.sessionID = sessionID
        provenance = ScreenRecordingCallbackProvenance(sessionID: sessionID)
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        let token = sessionID
        Task { @MainActor [weak owner] in owner?.pickerCancelled(sessionID: token) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let selection = ScreenRecordingSelection(filter: filter, existingStreamID: stream.map(ObjectIdentifier.init))
        let token = sessionID
        Task { @MainActor [weak owner] in owner?.selection(selection, sessionID: token) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        let detail = error.localizedDescription
        let token = sessionID
        Task { @MainActor [weak owner] in owner?.pickerFailed(detail, sessionID: token) }
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        let token = sessionID
        let startedAt = Date()
        let timeZoneIdentifier = TimeZone.current.identifier
        // Store before enqueueing: independent MainActor Tasks need not execute in
        // delegate callback order, and finalization may release this bridge first.
        provenance.recordingDidStart(outputID: id, startedAt: startedAt,
                                      timeZoneIdentifier: timeZoneIdentifier)
        Task { @MainActor [weak owner] in
            owner?.recordingStarted(outputID: id, sessionID: token)
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        let token = sessionID
        Task { @MainActor [weak owner] in owner?.recordingEnded(outputID: id, sessionID: token, error: nil) }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let id = ObjectIdentifier(recordingOutput)
        let detail = error.localizedDescription
        let token = sessionID
        Task { @MainActor [weak owner] in owner?.recordingEnded(outputID: id, sessionID: token, error: detail) }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let id = ObjectIdentifier(stream)
        let nsError = error as NSError
        let userStopped = nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userStopped.rawValue
        let detail = error.localizedDescription
        let token = sessionID
        Task { @MainActor [weak owner] in
            owner?.streamEnded(streamID: id, sessionID: token, wasUserStopped: userStopped, detail: detail)
        }
    }
}
#endif
