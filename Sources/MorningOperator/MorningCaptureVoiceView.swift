import SwiftUI
import MorningCore
import MorningApple

/// Entered only by the completed morning's Speak action. Final words are still
/// reviewed in QuickCaptureView; this screen never saves or executes a request.
struct MorningCaptureVoiceView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss
    @ViewState<MorningVoiceCommandLanguage> private var language =
        AppLanguage.isFrench ? .french : .english
    @ViewState<Bool> private var began = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: store.voiceCommands.state == .listening ? "waveform" : "mic")
                        .scaledFont(36, relativeTo: .largeTitle, weight: .light).foregroundStyle(MorningStyle.accent)
                        .accessibilityHidden(true)
                    Text("What's on your mind?")
                        .font(.serif(.largeTitle, .medium))
                    Text("A thought, a dream, something for later. Say it in your own words.")
                        .foregroundStyle(MorningStyle.muted)
                    Picker("Spoken language", selection: $language) {
                        Text("English").tag(MorningVoiceCommandLanguage.english)
                        Text("Français").tag(MorningVoiceCommandLanguage.french)
                    }.pickerStyle(.segmented).disabled(store.voiceInputBlocksPlayback)
                    Text(store.completionCaptureFeedback ?? (store.completionCapturePreparing
                        ? (store.voiceCommands.isBusy ? store.voiceCommands.message : AppLanguage.localized("Getting ready to listen…"))
                        : AppLanguage.localized("Speak when you're ready.")))
                        .font(.raleway(.subheadline)).accessibilityIdentifier("captureVoice.status")
                    if store.voiceCommands.isBusy, !store.voiceCommands.transcript.isEmpty {
                        Text(store.voiceCommands.transcript).font(.serif(.title3))
                            .accessibilityIdentifier("captureVoice.transcript")
                    }
                    if store.voiceCommands.state == .listening {
                        Button("I'm done speaking", systemImage: "checkmark") { store.voiceCommands.finishListening() }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("captureVoice.finish")
                    } else if store.voiceInputBlocksPlayback {
                        if store.voiceCommands.needsAudioRelease, !store.voiceCommands.isBusy,
                           !store.completionCapturePreparing, !store.voiceInputReleasing {
                            Button("Release microphone", systemImage: "mic.slash") { store.retryCompletionAudioRelease() }
                                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("captureVoice.release")
                        } else { ProgressView().accessibilityIdentifier("captureVoice.progress") }
                    } else {
                        Button("Try speaking again", systemImage: "mic") { store.listenForCompletionCapture(language: language) }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("captureVoice.retry")
                    }
                    Text("Up to 30 seconds, understood on this device. Review the words before saving anything. No audio recording is kept.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    if store.usesSyntheticCompletionCapture {
                        Text("Sample speech input · microphone not used")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).accessibilityIdentifier("captureVoice.sample")
                    }
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MorningStyle.background).navigationTitle("A moment for you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.cancelCompletionCapture(); dismiss() }
                        .accessibilityIdentifier("captureVoice.cancel")
                }
            }
        }
        .task {
            guard !began else { return }
            began = true
            store.listenForCompletionCapture(language: language)
        }
    }
}
