import Foundation
import Combine
import ElevenLabs
import LiveKit
import MorningApple
#if os(iOS)
import AVFAudio
import Speech
import UIKit
#endif

/// ElevenLabs owns microphone capture, streamed audio and interruption. The optional
/// local caption recognizer observes that existing track without opening a microphone.
@MainActor
final class ElevenLabsMorningVoiceTransport: MorningCloudVoiceTransport {
    var onEvent: (@MainActor (MorningCloudVoiceEvent) -> Void)?
    private var conversation: Conversation?
    private var subscriptions = Set<AnyCancellable>()
    private var attempt = UUID()
    private var playbackMuted = false
    private var playbackRevision = UUID()
    private var interruptionTask: Task<Void, Never>?
    #if os(iOS)
    private var transcriptPreview: CloudVoiceTranscriptPreview?
    #endif

    func connect(token: String, language: String, voiceGender: MorningVoiceGender) async throws {
        // Configure before either SDK initializes a conversation or its shared logger.
        LiveKitSDK.disableLogging()
        ElevenLabs.configure(.init(logLevel: .error, debugMode: false))
        let id = UUID(); attempt = id
        #if os(iOS)
        let preview = CloudVoiceTranscriptPreview { [weak self] text in
            guard let self, self.attempt == id else { return }
            self.onEvent?(.userTranscriptPreview(text))
        }
        transcriptPreview = preview
        await preview.prepare(language: language)
        guard attempt == id, !Task.isCancelled else { throw CancellationError() }
        #endif
        let config = ConversationConfig(
            agentOverrides: AgentOverrides(language: language.hasPrefix("fr") ? .french : .english),
            // Public premade voices, verified for French and English. Only this
            // TTS field and language are permitted by the private agent policy.
            ttsOverrides: TTSOverrides(voiceId: voiceGender == .male ? "CwhRBWXzGAHq8TQ4Fs17" : "EXAVITQu4vr4xnSDxMaL"),
            onError: { [weak self] _ in
                Task { @MainActor in if self?.attempt == id { self?.onEvent?(.failed) } }
            },
            onAgentResponse: { [weak self] text, eventID in
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    guard !self.playbackMuted else { return }
                    #if os(iOS)
                    self.transcriptPreview?.outputText = text
                    self.transcriptPreview?.renew()
                    #endif
                    self.onEvent?(.agentText(text))
                }
            },
            onUserTranscript: { [weak self] text, eventID in
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    #if os(iOS)
                    self.transcriptPreview?.renew()
                    #endif
                    self.onEvent?(.userText(text, eventID: eventID))
                    await self.resumePlaybackForNewTurn()
                }
            },
            onInterruption: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    #if os(iOS)
                    self.transcriptPreview?.setSpeaking(false)
                    #endif
                    self.onEvent?(.interruption)
                }
            })
        let client = try await ElevenLabs.startConversation(conversationToken: token, config: config)
        guard attempt == id, !Task.isCancelled else {
            await client.endConversation()
            throw CancellationError()
        }
        conversation = client
        #if os(iOS)
        if let track = client.inputTrack { preview.start(track: track) }
        #endif
        client.$agentState.sink { [weak self] state in
            guard self?.attempt == id else { return }
            #if os(iOS)
            self?.transcriptPreview?.setSpeaking(state == .speaking)
            #endif
            switch state {
            case .speaking: self?.onEvent?(.speaking)
            case .listening: self?.onEvent?(.listening)
            case .thinking: break
            }
        }.store(in: &subscriptions)
        client.$state.sink { [weak self] state in
            guard self?.attempt == id else { return }
            switch state {
            case .ended: self?.onEvent?(.ended)
            case .error: self?.onEvent?(.failed)
            default: break
            }
        }.store(in: &subscriptions)
        client.$pendingToolCalls.sink { [weak self] calls in
            guard let self, attempt == id else { return }
            for call in calls {
                guard call.expectsResponse else { client.markToolCallCompleted(call.toolCallId); continue }
                let parameters = (try? call.getParameters()) ?? [:]
                let data = (try? JSONSerialization.data(withJSONObject: parameters)) ?? Data("{}".utf8)
                onEvent?(.tool(.init(id: call.toolCallId, name: call.toolName,
                                    parametersJSON: String(decoding: data, as: UTF8.self), eventID: call.eventId)))
            }
        }.store(in: &subscriptions)
    }

    func updateContext(_ context: String) async throws {
        guard let conversation else { throw MorningCloudVoiceError.unavailable }
        try await conversation.updateContext(context)
    }

    func reply(to callID: String, result: String, isError: Bool) async throws {
        guard let conversation else { throw MorningCloudVoiceError.unavailable }
        try await conversation.sendToolResult(for: callID, result: result, isError: isError)
    }

    func sendUserMessage(_ text: String) async throws {
        try Task.checkCancellation()
        await resumePlaybackForNewTurn()
        try Task.checkCancellation()
        guard let conversation else { throw MorningCloudVoiceError.unavailable }
        try await conversation.sendMessage(text)
    }

    func cancelPlayback() {
        guard let conversation else { return }
        let needsInterruption = !playbackMuted
        playbackMuted = true; playbackRevision = UUID()
        #if os(iOS)
        transcriptPreview?.setSpeaking(false)
        #endif
        conversation.agentAudioTrack?.volume = 0
        guard needsInterruption else { return }
        interruptionTask = Task { _ = try? await conversation.interruptAgent() }
    }

    func suspendReply() {
        playbackMuted = true; playbackRevision = UUID()
        #if os(iOS)
        transcriptPreview?.setSpeaking(false)
        #endif
        conversation?.agentAudioTrack?.volume = 0
    }

    /// A delayed response never resumes canceled audio by itself. Only a new
    /// live transcript or an explicitly approved app narration reopens output.
    private func resumePlaybackForNewTurn() async {
        guard playbackMuted else { return }
        let revision = playbackRevision, id = attempt
        await interruptionTask?.value
        guard attempt == id, playbackRevision == revision, !Task.isCancelled else { return }
        playbackMuted = false; interruptionTask = nil
        conversation?.agentAudioTrack?.volume = 1
    }

    func stop() async {
        attempt = UUID(); playbackRevision = UUID()
        #if os(iOS)
        transcriptPreview?.stop(); transcriptPreview = nil
        #endif
        interruptionTask?.cancel(); interruptionTask = nil
        subscriptions.removeAll(); conversation?.agentAudioTrack?.volume = 0
        let previous = conversation; conversation = nil
        await previous?.endConversation()
    }
}

#if os(iOS)
/// The pinned SDK does not forward tentative transcripts. These local hypotheses
/// are captions only; final provider transcripts remain the sole command authority.
@MainActor
private final class CloudVoiceTranscriptPreview {
    var outputText: String?
    private let onText: @MainActor (String) -> Void
    private let sink = CloudVoicePreviewAudioRenderer()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var track: LocalAudioTrack?
    private var deadline: Task<Void, Never>?
    private var generation = UUID()
    private var failures = 0
    private var isSpeaking = false
    private var outputFinishedAt = Date.distantPast

    init(onText: @escaping @MainActor (String) -> Void) { self.onText = onText }

    func prepare(language: String) async {
        var authorization = SFSpeechRecognizer.authorizationStatus()
        if authorization == .notDetermined {
            let raw = await withCheckedContinuation { continuation in
                let callback: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = {
                    continuation.resume(returning: $0.rawValue)
                }
                SFSpeechRecognizer.requestAuthorization(callback)
            }
            authorization = SFSpeechRecognizerAuthorizationStatus(rawValue: raw) ?? .denied
        }
        guard !Task.isCancelled, UIApplication.shared.applicationState != .background,
              authorization == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.hasPrefix("fr") ? "fr-FR" : "en-US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return }
        self.recognizer = recognizer
    }

    func start(track: LocalAudioTrack) {
        guard recognizer != nil else { return }
        self.track = track
        renew()
        track.add(audioRenderer: sink)
    }

    func setSpeaking(_ speaking: Bool) {
        if isSpeaking && !speaking { outputFinishedAt = Date() }
        isSpeaking = speaking
    }

    /// Replacing a turn invalidates queued callbacks before canceling its recognizer.
    func renew() {
        generation = UUID()
        deadline?.cancel(); task?.cancel(); sink.replace(with: nil)
        guard let recognizer, track != nil, failures < 3,
              UIApplication.shared.applicationState == .active else { return }
        let id = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        request.addsPunctuation = true; request.taskHint = .dictation
        sink.replace(with: request)
        let receive: @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void = { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true, failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == id else { return }
                guard UIApplication.shared.applicationState == .active else { self.stop(); return }
                let echo = self.isSpeaking || Date().timeIntervalSince(self.outputFinishedAt) < 1.5
                    ? self.outputText : nil
                if let text, !failed, text.count <= 4_000, !text.isEmpty,
                   !MorningHandsFreeVoicePolicy.isOutputEcho(text, output: echo, acousticDuplexIsActive: true) {
                    self.failures = 0; self.onText(text)
                }
                if failed { self.failures += 1 }
                if final || failed { self.renew() }
            }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: receive)
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.generation == id else { return }
            self.renew()
        }
    }

    func stop() {
        generation = UUID(); deadline?.cancel(); deadline = nil
        task?.cancel(); task = nil; sink.replace(with: nil)
        track?.remove(audioRenderer: sink); track = nil; recognizer = nil; outputText = nil
        isSpeaking = false; outputFinishedAt = .distantPast
    }
}

/// LiveKit invokes this on its audio executor. The adapter retains no audio buffers;
/// the lock also makes recognition replacement atomic with input.
private final class CloudVoicePreviewAudioRenderer: NSObject, AudioRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func replace(with request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        self.request?.endAudio(); self.request = request
    }
    func render(pcmBuffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(pcmBuffer)
    }
}
#endif
