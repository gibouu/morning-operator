import MorningApple

/// The SDK-free beta never creates a network or microphone conversation transport.
@MainActor
final class UnavailableMorningVoiceTransport: MorningCloudVoiceTransport {
    static let isAvailable = false
    var onEvent: (@MainActor (MorningCloudVoiceEvent) -> Void)?
    func connect(token: String, language: String, voiceGender: MorningVoiceGender) async throws {
        throw MorningCloudVoiceError.unavailable
    }
    func updateContext(_ context: String) async throws { throw MorningCloudVoiceError.unavailable }
    func sendUserMessage(_ text: String) async throws { throw MorningCloudVoiceError.unavailable }
    func reply(to callID: String, result: String, isError: Bool) async throws { throw MorningCloudVoiceError.unavailable }
    func suspendReply() { }
    func cancelPlayback() { }
    func stop() async { }
}
