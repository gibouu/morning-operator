import SwiftUI
import MorningApple
import MorningCore

struct MorningConversationView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss
    @State private var starting = false
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        NavigationStack {
            MorningForm {
                Section {
                    Text("Talk to MORE and interrupt at any time.")
                    if let caption = store.cloudVoice.userCaption ?? store.cloudVoice.caption {
                        Text(store.cloudVoice.userCaption == nil ? caption : SpeechCoordinator.inputCaption(caption))
                            .accessibilityIdentifier("cloudVoice.caption")
                    }
                    if let fallback = store.voiceFallbackMessage {
                        Label(fallback, systemImage: "speaker.wave.2")
                            .accessibilityIdentifier("voice.fallback")
                    } else {
                        if let error = store.cloudVoice.errorMessage { Text(error).foregroundStyle(MorningStyle.muted) }
                        if let error = store.cloudVoiceStartIssue { Text(error).foregroundStyle(MorningStyle.muted) }
                    }
                    if store.cloudVoice.isActive {
                        Label(store.cloudVoice.state == .speaking
                              ? (french ? "MORE parle" : "MORE is speaking")
                              : (french ? "MORE vous écoute" : "MORE is listening"), systemImage: "waveform")
                        Button(french ? "Arrêter la conversation" : "End conversation", role: .destructive) { store.stopCloudVoice() }
                            .accessibilityIdentifier("cloudVoice.stop")
                    } else {
                        Button {
                            starting = true
                            Task {
                                await store.startCloudVoice()
                                starting = false
                                if store.cloudVoice.isActive, store.session?.status == .paused { store.resume() }
                            }
                        } label: {
                            if starting { ProgressView() }
                            else { Text("Talk") }
                        }.disabled(starting || store.cloudVoiceReleasing || store.privacyBlocksWork ||
                                   store.voiceInputBlocksPlayback)
                            .accessibilityIdentifier("cloudVoice.start")
                    }
                } footer: {
                    Text("By tapping Talk, your voice and spoken passages are processed online during this conversation.")
                        .accessibilityIdentifier("cloudVoice.consent")
                }
                Section {
                    DisclosureGroup {
                        Text("This conversation uses ElevenLabs and Google Gemini to process your voice and MORE’s spoken text.")
                            .accessibilityIdentifier("cloudVoice.providers")
                        Text("Previews and recaps you choose to play during the conversation are shared. During an active morning, its routine steps and information MORE speaks from your chosen sources are also shared: calendar, weather, read messages and Health measurements included in this routine. No video recording or complete Health history is sent.")
                            .accessibilityIdentifier("cloudVoice.sharingDetails")
                        if let routine = store.sessionActive ? store.session?.routine : store.routine {
                            ForEach(routine.steps) { step in Text(step.title).font(.subheadline) }
                        }
                        Text("This consent applies to this session. Choosing a voice or granting Apple Health access never enables this sharing. Ending the conversation releases the microphone. Listening also ends when you leave the app or end the morning.")
                        Link(french ? "Confidentialité ElevenLabs" : "ElevenLabs privacy", destination: URL(string: "https://elevenlabs.io/privacy-policy")!)
                    } label: {
                        Text("Privacy")
                    }
                    .accessibilityIdentifier("cloudVoice.privacy")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                }
            }
            .navigationTitle(french ? "Parler avec MORE" : "Talk with MORE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.cloudVoice.isActive ? (french ? "Retour au matin" : "Back to morning") : String(localized: "Done", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { dismiss() }
                }
            }
        }.tint(MorningStyle.accent)
    }
}
