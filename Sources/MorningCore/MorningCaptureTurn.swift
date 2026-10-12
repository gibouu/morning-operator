import Foundation

public enum MorningCaptureTurnError: LocalizedError, Sendable, Equatable {
    case empty, tooLong

    public var errorDescription: String? {
        switch self {
        case .empty: "No words were received. Try again or type your thought."
        case .tooLong: "That capture is longer than 4,000 characters. Try a shorter thought or type it instead."
        }
    }
}

/// One explicit dictation turn, separate from the routine-command grammar. This only
/// returns text for review: it never interprets commands, saves a note or takes an action.
/// The caller owns audio deadlines, cancellation and the context in which review appears.
public struct MorningCaptureTurn: Sendable {
    public static let maximumCharacters = 4_000
    public let id: UUID
    public private(set) var isFinished = false

    public init(id: UUID = UUID()) { self.id = id }

    /// Partials never consume the turn. The first final consumes it even if rejected,
    /// preventing a later callback from silently replacing the user's reviewed text.
    public mutating func accept(transcript: String, isFinal: Bool) throws -> String? {
        guard !isFinished, isFinal else { return nil }
        isFinished = true
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MorningCaptureTurnError.empty }
        guard text.count <= Self.maximumCharacters else { throw MorningCaptureTurnError.tooLong }
        return text
    }

    public mutating func cancel() { isFinished = true }
}
