import SwiftUI
import MorningApple
import MorningCore
import UIKit

/// Requests system grants only after this explicit UI action. It never starts
/// an audio engine, records a test sample or declares an acoustic check passed.
struct MorningVoicePreparationView: View {
    @Bindable var store: MorningStore
    var startRequest: MorningVoiceStartRequest? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var operation: Task<Void, Never>?
    @State private var visible = false
    @State private var preparedStartPending = false
    @State private var releaseIssue: String?
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeading(eyebrow: french ? "Votre voix" : "Your voice",
                        title: startRequest == nil ? (french ? "Préparer l’écoute" : "Prepare listening")
                            : (french ? "La voix de MORE" : "MORE’s voice"),
                        subtitle: startRequest != nil && !store.automatic
                            ? (french ? "MORE peut lire les moments de votre matin." : "MORE can read the moments of your morning.")
                            : french ? "Autorisez la reconnaissance locale et le microphone avant votre matin. L’écoute commencera seulement pendant la session."
                            : "Allow local recognition and microphone access before your morning. Listening starts only during the session.")
                    MorningVoiceAccessStatusView(access: store.voiceAccess)
                    if startRequest != nil {
                        Text(french ? "La voix naturelle utilise les passages lus pendant ce matin. Ils sont traités en ligne."
                             : "Natural voice uses the passages read during this morning. They are processed online.")
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("voice.readingConsent")
                        DisclosureGroup(french ? "Confidentialité" : "Privacy") {
                            Text(french
                                 ? "En commençant, vous envoyez les passages que MORE lit à ElevenLabs pour produire la voix : informations de votre routine et lectures que vous lancez, y compris les messages, calendrier ou mesures Santé choisis. Cette lecture n’envoie ni microphone, ni vidéo, ni historique Santé complet. L’accord vaut pour ce matin ; le modèle choisi garde ses propres réglages."
                                 : "Beginning sends the passages MORE reads to ElevenLabs to produce the voice: routine information and readings you choose to play, including selected messages, calendar or Health measurements. This reading sends no microphone audio, video or complete Health history. Consent applies to this morning; your selected model keeps its own settings.")
                                .font(.footnote).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let releaseIssue { Text(releaseIssue).font(.raleway(.subheadline)).accessibilityIdentifier("voice.access.releaseIssue") }
                    if store.forcesVoicePreparationReviewForUITests {
                        Text("Synthetic preparation · actual system permissions · microphone not simulated")
                            .font(.raleway(.caption)).accessibilityIdentifier("voice.access.synthetic")
                    }
                    Text(french ? "Cette préparation n’enregistre aucun son et ne teste pas le microphone. La lecture à voix haute et l’enchaînement de votre routine restent des choix distincts."
                         : "This preparation records no audio and does not test the microphone. Reading aloud and continuing your routine remain separate choices.")
                        .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
                    if let startRequest, !store.automatic {
                        Button(french ? "Commencer" : "Begin") {
                            beginPrepared(startRequest, listen: false)
                        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("voice.access.begin")
                    } else if store.voiceAccess.snapshot.canRequest {
                        Button(startRequest == nil
                            ? (french ? "Préparer les autorisations" : "Prepare permissions")
                            : (french ? "Préparer puis commencer" : "Prepare, then begin")) { prepare() }
                            .buttonStyle(PrimaryButtonStyle()).disabled(store.voiceAccess.isRequesting)
                            .accessibilityIdentifier("voice.access.prepare")
                    } else if store.voiceAccess.snapshot.isReady, let startRequest {
                        Button(french ? "Commencer avec l’écoute" : "Begin with listening") {
                            beginPrepared(startRequest, listen: true)
                        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("voice.access.begin")
                    }
                    if store.voiceAccess.isRequesting { ProgressView(french ? "Autorisations en cours…" : "Preparing permissions…") }
                    if store.voiceAccess.snapshot.canOpenSettings {
                        Link(french ? "Ouvrir les réglages iPhone" : "Open iPhone settings",
                             destination: URL(string: UIApplication.openSettingsURLString)!)
                            .accessibilityIdentifier("voice.access.settings")
                    }
                    Button(french ? "Actualiser l’état" : "Refresh status") {
                        store.voiceAccess.refresh(language: store.voicePreparationLanguage)
                    }.buttonStyle(SecondaryButtonStyle()).disabled(store.voiceAccess.isRequesting)
                        .accessibilityIdentifier("voice.access.refresh")
                    if let startRequest {
                        if store.automatic {
                            Button(french ? "Commencer sans écoute" : "Begin without listening") {
                                beginPrepared(startRequest, listen: false)
                            }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("voice.access.withoutListening")
                        }
                        Text(french ? "MORE pourra lire et enchaîner les moments selon vos réglages. Utilisez les boutons pour le contrôler pendant ce matin."
                             : "MORE can still read and continue moments according to your settings. Use the buttons to control this morning.")
                            .font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
                        Button(french ? "Continuer sans partager les lectures" : "Continue without sharing readings") {
                            beginPrepared(startRequest, listen: store.automatic && store.voiceAccess.snapshot.isReady,
                                          onlineSpeech: false)
                        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("voice.access.withoutOnlineVoice")
                    }
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
            }.background(MorningPaper(showsSun: false)).foregroundStyle(MorningStyle.ink)
                .navigationTitle(french ? "Écoute" : "Listening").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(french ? "Fermer" : "Close") { stopRequest(); dismiss() }
                        .accessibilityIdentifier("voice.access.close")
                } }
        }
        .onAppear { visible = true; store.voiceAccess.refresh(language: store.voicePreparationLanguage) }
        .onDisappear { visible = false; stopRequest() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopRequest(); dismiss() }
            else if phase == .active {
                store.voiceAccess.refresh(language: store.voicePreparationLanguage)
                completePreparedStart()
            }
        }
        .onChange(of: AppLanguage.code) { _, _ in
            stopRequest()
            store.voiceAccess.refresh(language: store.voicePreparationLanguage)
            if startRequest != nil { dismiss() }
        }
        .onChange(of: store.dataGeneration) { _, _ in stopRequest(); dismiss() }
        .onChange(of: store.routine?.id) { _, _ in if startRequest != nil { stopRequest(); dismiss() } }
        .onChange(of: store.privacyBlocksWork) { _, blocked in if blocked { stopRequest(); dismiss() } }
    }

    private func stopRequest() {
        preparedStartPending = false
        operation?.cancel(); operation = nil; store.voiceAccess.cancel()
    }
    private func completePreparedStart() {
        guard preparedStartPending, visible, scenePhase == .active, let startRequest else { return }
        beginPrepared(startRequest, listen: true)
    }
    private func beginPrepared(_ request: MorningVoiceStartRequest, listen: Bool, onlineSpeech: Bool = true) {
        stopRequest(); releaseIssue = nil
        operation = Task { @MainActor in
            do {
                if store.cloudVoice.isActive || store.cloudVoiceReleasing {
                    store.stopCloudVoice()
                    await store.cloudVoiceReleaseTask?.value
                    await store.cloudVoice.stopAndRelease()
                    store.speech.externalSpeech = nil; store.speech.cancelExternalSpeech = nil
                    store.cloudVoiceReleasing = false
                }
                #if MORE_JURY_DEMO
                if !listen || !onlineSpeech { try await store.juryDemoVoice.pauseAndRelease() }
                #endif
                if !listen { try await store.handsFreeVoice.stopAndRelease() }
                try Task.checkCancellation()
                guard visible, scenePhase == .active, store.voicePreparationIsCurrent(request) else { return }
                operation = nil
                if store.finishVoicePreparation(request, listen: listen, onlineSpeech: onlineSpeech) { dismiss() }
            } catch is CancellationError { operation = nil }
            catch {
                operation = nil
                guard visible, store.voicePreparationIsCurrent(request) else { return }
                releaseIssue = french ? "Le microphone n’a pas pu être libéré. Réessayez avant de commencer."
                    : "The microphone could not be released. Try again before beginning."
            }
        }
    }
    private func prepare() {
        guard visible, scenePhase == .active, !store.privacyBlocksWork, !store.voiceAccess.isRequesting else { return }
        let generation = store.dataGeneration
        operation = Task { @MainActor in
            do {
                let ready = try await store.voiceAccess.requestAccess(language: store.voicePreparationLanguage)
                try Task.checkCancellation()
                guard visible, scenePhase != .background, generation == store.dataGeneration, !store.privacyBlocksWork else { return }
                operation = nil
                preparedStartPending = ready.isReady && startRequest != nil
                completePreparedStart()
            } catch { operation = nil }
        }
    }
}

struct MorningVoiceAccessStatusView: View {
    @Bindable var access: MorningVoiceAccess
    var body: some View {
        Text(access.snapshot.description(french: AppLanguage.isFrench))
            .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("voice.access.status")
    }
}
