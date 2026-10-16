import SwiftUI
import MorningCore
import MorningApple

/// An explicit listening turn, separate from background listening or Siri invocation.
struct MorningVoiceCommandView: View {
    @Bindable var store: MorningStore
    @ViewState<MorningVoiceCommandLanguage> private var language =
        AppLanguage.isFrench ? .french : .english
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: store.voiceCommands.state == .listening ? "waveform" : "mic")
                        .scaledFont(36, relativeTo: .largeTitle, weight: .light).foregroundStyle(MorningStyle.accent)
                        .accessibilityHidden(true)
                    Text("A word from you.")
                        .font(.serif(.largeTitle, .medium))
                    Text("Your morning is paused. Say next, pause, resume, skip, repeat or stop.")
                        .font(.raleway(.body)).foregroundStyle(MorningStyle.muted)
                    Picker("Command language", selection: $language) {
                        Text("English").tag(MorningVoiceCommandLanguage.english)
                        Text("Français").tag(MorningVoiceCommandLanguage.french)
                    }.pickerStyle(.segmented).disabled(store.voiceInputBlocksPlayback)
                    if language == .french {
                        Text("Suivant · pause · reprends · passe cette étape · répète · arrête")
                            .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    }
                    Text(store.voiceCommandFeedback ?? store.voiceCommands.message)
                        .font(.raleway(.subheadline)).accessibilityIdentifier("voiceCommand.status")
                    if !store.voiceCommands.transcript.isEmpty {
                        Text(store.voiceCommands.transcript).font(.serif(.title3))
                            .accessibilityIdentifier("voiceCommand.transcript")
                    }
                    if let route = store.voiceCommands.inputRouteName, store.voiceCommands.state == .listening {
                        Label(route, systemImage: "mic.fill").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    controls
                    Text("Only listens when you tap. Up to eight seconds, processed on this device. Nothing is saved from this turn.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MorningStyle.background).navigationTitle("Speak to MORE").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { store.cancelVoiceCommandTurn(); dismiss() }
                        .accessibilityIdentifier("voiceCommand.close")
                }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        if store.voiceCommands.state == .listening {
            Button("I'm done speaking", systemImage: "checkmark") { store.voiceCommands.finishListening() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("voiceCommand.finish")
        } else if store.voiceCommandPreparing || store.voiceCommands.isBusy {
            ProgressView("Getting ready…").accessibilityIdentifier("voiceCommand.progress")
        } else if store.voiceCommands.needsAudioRelease {
            Button("Release microphone", systemImage: "mic.slash") { store.cancelVoiceCommandTurn() }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("voiceCommand.release")
        } else {
            Button("Tap to speak", systemImage: "mic") { store.listenForCommand(language: language) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("voiceCommand.listen")
        }
    }
}
