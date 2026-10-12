import SwiftUI
import MorningApple

/// The caller returns true after retaining the file for processing/retry. Only then is the
/// recorder's ready URL released. Saved text or an explicit discard permits raw-file deletion.
struct RecordMorningView: View {
    var canStartRecording = true
    let onRecorded: (URL) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            RecordMorningContent(canStartRecording: canStartRecording, onRecorded: onRecorded)
        } else {
            unavailable
        }
        #else
        unavailable
        #endif
    }

    private var unavailable: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.largeTitle).foregroundStyle(MorningStyle.accent)
                Text("Bring a recording you've made")
                    .font(.title2.weight(.semibold))
                Text("Recording from inside Morning Operator needs an iPhone or iPad with iOS 27 or later. You can still choose an existing screen recording, screenshot or text file from Learn.")
                    .foregroundStyle(MorningStyle.muted)
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(28).frame(maxWidth: 560, alignment: .leading)
            .background(MorningStyle.background)
            .navigationTitle("Show your morning")
        }
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
@available(iOS 27.0, *)
private struct RecordMorningContent: View {
    let canStartRecording: Bool
    let onRecorded: (URL) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Bindable private var recording = ScreenRecordingService.shared
    @ViewState<ScreenRecordingDuration> private var duration = .twentyMinutes

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: recording.state == .recording ? "record.circle" : "rectangle.on.rectangle")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(recording.state == .recording ? Color.red : MorningStyle.accent)
                    Text(title).font(.system(.largeTitle, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recording.message).font(.body).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if recording.state == .recording {
                        Text(String(format: "%02d:%02d", recording.elapsedSeconds / 60, recording.elapsedSeconds % 60))
                            .font(.system(size: 44, weight: .medium, design: .rounded)).monospacedDigit()
                            .accessibilityLabel("Recording duration")
                        Button { recording.stopRecording() } label: {
                            Label("Stop recording", systemImage: "stop.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("record.stop")
                    } else if recording.state == .ready {
                        Button {
                            guard let url = recording.recordedURL, onRecorded(url) else { return }
                            _ = recording.takeRecording()
                            dismiss()
                        } label: {
                            Label("Use this recording", systemImage: "checkmark")
                        }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("record.use")
                        Button("Discard recording", role: .destructive) { recording.discard() }
                            .buttonStyle(.borderless)
                    } else if recording.state == .starting || recording.state == .stopping {
                        if recording.needsStopRetry {
                            Button("Try stopping again") { recording.stopRecording() }.buttonStyle(PrimaryButtonStyle())
                        } else { ProgressView().tint(MorningStyle.accent) }
                        if recording.state == .starting {
                            Button("Cancel") { recording.discard() }.buttonStyle(SecondaryButtonStyle())
                        }
                    } else if recording.state == .choosing {
                        Button("Cancel recording request") { recording.discard() }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Text("Confirm Apple's picker, then go through your morning. This screen closes when recording begins. We stop at your chosen limit and save the visible text for you to review when you return.")
                            .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        Picker("Stop automatically after", selection: $duration) {
                            ForEach(ScreenRecordingDuration.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }.pickerStyle(.menu)
                        Button { recording.presentPicker(duration: duration) } label: {
                            Label("Start screen recording", systemImage: "record.circle")
                        }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("record.start")
                        .disabled(!canStartRecording)
                        if !canStartRecording {
                            Text("Finish the current activity, or retry or discard the saved recording, before starting another.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("You're in control", systemImage: "hand.raised")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(MorningStyle.green)
                        Text("This records visible screen content without sound or camera video. Keep the part you want to teach short; other personal content on screen may also appear.")
                        Text("Recording stops at your chosen time limit or its file-size limit. This is a time limit, not a guess that you stopped using your phone. You can stop earlier using the app or the system controls.")
                        Text("When recording finishes, visible text is extracted and saved locally. Review the text, then choose whether to ask Apple Intelligence for a routine suggestion. Your routine changes only after you approve. The video stays on this device until its extracted text is saved, or until you discard it.")
                    }
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(24).frame(maxWidth: 580, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(MorningStyle.background)
            .foregroundStyle(MorningStyle.ink)
            .navigationTitle("Show your morning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(!recording.canDismiss)
                }
            }
            .interactiveDismissDisabled(!recording.canDismiss)
        }
    }

    private var title: String {
        switch recording.state {
        case .recording: "Go through your morning."
        case .ready: "A little of your routine, captured."
        case .stopping: "Finishing your recording."
        case .starting: "Getting ready to record."
        case .failed: "Let's try that again."
        case .idle, .choosing: "Show how your morning goes."
        }
    }
}
#endif
