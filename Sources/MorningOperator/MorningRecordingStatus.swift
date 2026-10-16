import MorningCore
import SwiftUI
import MorningApple

/// Saved media remains recoverable without the native screen-capture framework.
/// Simulator, older supported OS versions and live capture share these controls.
struct SavedRecordingRecoveryView: View {
    @Bindable var store: MorningStore
    var onReview: () -> Void
    @ViewState<Bool> private var confirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(store.busy ? "Reading your recording" : "Your recording is saved", systemImage: "externaldrive.badge.checkmark")
                .font(.raleway(.subheadline, .medium))
            Text(store.busy ? store.analysisStatus : (store.observationIssue ?? AppLanguage.localized("Retry understanding it, or discard the recording.")))
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            if store.sessionActive {
                Text("Finish or stop the current morning before retrying.").font(.raleway(.caption))
            }
            HStack {
                Button("Retry") { store.retryPendingRecording() }
                    .buttonStyle(SecondaryButtonStyle()).disabled(store.busy || store.sessionActive)
                    .accessibilityIdentifier("record.retryImport")
                Button("Discard recording", role: .destructive) { confirmingDiscard = true }
                    .buttonStyle(.borderless).accessibilityIdentifier("record.discardPending")
                    .disabled(store.busy)
                    .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Discard recording", role: .destructive) { store.discardPendingRecording() }
                        Button("Cancel", role: .cancel) { }
                    } message: { Text("The video is deleted from this device. Text already saved from it stays available.") }
            }
            if store.hasImportedObservation {
                Button("Review text", action: onReview).buttonStyle(.borderless).font(.raleway(.caption))
            }
        }
        .padding(14).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius)).overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
@available(iOS 27.0, *)
struct MorningRecordingStatus: View {
    @Bindable var store: MorningStore
    var onReview: () -> Void
    @Bindable private var recording = ScreenRecordingService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if recording.captureMayBeActive {
                HStack(spacing: 12) {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recording.state == .recording ? "Recording your morning" : "Finishing your recording")
                            .font(.raleway(.subheadline, .medium))
                        Text(recording.state == .recording
                             ? AppLanguage.localized("Stops in \(remainingTime) · visible screen only")
                             : recording.message).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    Spacer(minLength: 4)
                    if recording.state == .recording || recording.needsStopRetry {
                        Button("Stop") { recording.stopRecording() }
                            .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("record.stop")
                    } else { ProgressView() }
                }
                .padding(14).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius)).overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
                .padding(.horizontal, 16).padding(.vertical, 6)
            } else if store.busy {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Understanding your morning").font(.raleway(.subheadline, .medium))
                        Text(store.analysisStatus).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    Spacer(minLength: 4)
                    Button("Stop") { store.cancelAnalysis() }.buttonStyle(.borderless)
                }
                .padding(14).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius)).overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
                .padding(.horizontal, 16).padding(.vertical, 6)
            } else if store.hasPendingRecording {
                SavedRecordingRecoveryView(store: store, onReview: onReview)
            } else if recording.hasRecordingToReview {
                VStack(alignment: .leading, spacing: 8) {
                    if let issue = store.observationIssue { Text(issue).font(.raleway(.caption)) }
                    Button("Your recording is ready · Review") {
                        transferAndProcessRecordingIfReady(store: store, sceneIsActive: scenePhase == .active, onReview: onReview)
                    }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("record.review")
                }.padding(10)
            } else if recording.state == .failed {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle")
                    Text(recording.message).font(.raleway(.caption))
                    Spacer()
                    Button("Dismiss") { recording.discard() }.font(.raleway(.caption))
                }.padding(14).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius)).overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
                    .padding(.horizontal, 16).padding(.vertical, 6)
            } else if let issue = store.observationIssue {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your observation needs attention", systemImage: "exclamationmark.circle")
                        .font(.raleway(.subheadline, .medium))
                    Text(issue).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    HStack {
                        Button(store.hasImportedObservation ? "Review saved text" : "Open learning", action: onReview)
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Dismiss") { store.dismissObservationIssue() }.buttonStyle(.borderless)
                    }
                }
                .padding(14).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius)).overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
                .padding(.horizontal, 16).padding(.vertical, 6)
            } else if store.hasImportedObservation {
                Button(action: onReview) {
                    Label("Review your saved observation", systemImage: "text.viewfinder")
                        .font(.raleway(.caption, .medium))
                }.buttonStyle(SecondaryButtonStyle()).padding(8).accessibilityIdentifier("observation.review")
            }
        }
    }

    private var remainingTime: String {
        String(format: "%02d:%02d", recording.remainingSeconds / 60, recording.remainingSeconds % 60)
    }
}

/// One nonvisual owner keeps lifecycle effects independent of the tab layouts.
@available(iOS 27.0, *)
struct MorningRecordingCoordinator: View {
    @Bindable var store: MorningStore
    var canProcessRecording: Bool
    var onStarted: () -> Void
    var onReview: () -> Void
    @Bindable private var recording = ScreenRecordingService.shared
    @Environment(\.scenePhase) private var scenePhase
    @ViewState<Bool> private var didAnnounceStart = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        .onChange(of: recording.state, initial: true) { _, state in
            if state != .recording { didAnnounceStart = false }
            announceStartedIfActive()
            processRecordingIfReady()
        }
        .onChange(of: scenePhase) { _, _ in
            announceStartedIfActive()
            processRecordingIfReady()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            recording.ownInterfaceChanged(inFront: phase != .background)
        }
        .onChange(of: store.busy) { _, busy in
            if !busy { processRecordingIfReady() }
        }
        .onChange(of: store.sessionActive) { _, active in
            if !active { processRecordingIfReady() }
        }
        .onChange(of: store.hasPendingRecording) { _, _ in
            processRecordingIfReady()
        }
        .onChange(of: store.pendingRecordingShouldAutoProcess) { _, _ in
            processRecordingIfReady()
        }
        .onChange(of: canProcessRecording) { _, allowed in
            if allowed { processRecordingIfReady() }
        }
    }

    private func announceStartedIfActive() {
        guard recording.state == .recording, scenePhase == .active, !didAnnounceStart else { return }
        didAnnounceStart = true
        // One owner dismisses the app's sheets. Scene activity is not proof that Apple's
        // sharing picker has dismissed; the app cannot control that system presentation.
        onStarted()
    }

    private func processRecordingIfReady() {
        guard canProcessRecording else { return }
        transferAndProcessRecordingIfReady(store: store, sceneIsActive: scenePhase == .active, onReview: onReview)
    }
}

@available(iOS 27.0, *)
@MainActor
private func transferAndProcessRecordingIfReady(store: MorningStore, sceneIsActive: Bool, onReview: () -> Void) {
    let recording = ScreenRecordingService.shared
    // The service's finalization callback normally stages this without any view rendering.
    // Retry staging here only if its earlier attempt could not accept ownership.
    if !store.hasPendingRecording, recording.hasRecordingToReview, let url = recording.recordedURL,
       store.retainFinalizedRecording(url, interruptionNote: recording.recordingInterruption) {
        _ = recording.takeRecording()
    }
    guard sceneIsActive, !store.busy, !store.sessionActive,
          store.hasPendingRecording, store.pendingRecordingShouldAutoProcess else { return }
    store.retryPendingRecording()
    // The root queues review until extraction is idle and no other task owns the
    // presentation. Saved evidence is useful even when the model isn't available.
    onReview()
}
#endif
