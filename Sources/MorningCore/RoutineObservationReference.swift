import Foundation

public enum RoutineObservationReferenceError: Error, LocalizedError, Sendable, Equatable {
    case invalidRevision, invalidQuote
    public var errorDescription: String? {
        switch self {
        case .invalidRevision: "The saved observation reference is invalid."
        case .invalidQuote: "Choose one complete, short excerpt from the saved observation."
        }
    }
}

/// A reference to explicitly reviewed historical text, never authority to read an
/// external app. Playback must resolve the current source and revision again.
public struct RoutineObservationReference: Codable, Sendable, Equatable {
    public static let maximumQuoteCharacters = 500
    public static let maximumQuoteUTF8Bytes = 4_000
    public let acquisitionID: UUID
    public let revisionSHA256: String
    public let frameID: UUID?
    public let quote: String
    /// Immutable source provenance travels with explicit keep choices and exports.
    public let isSynthetic: Bool

    public init(acquisitionID: UUID, revisionSHA256: String, frameID: UUID? = nil, quote: String,
                isSynthetic: Bool = false) throws {
        let revision = revisionSHA256.lowercased()
        guard revision.utf8.count == 64,
              revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw RoutineObservationReferenceError.invalidRevision
        }
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              quote.count <= Self.maximumQuoteCharacters,
              quote.utf8.count <= Self.maximumQuoteUTF8Bytes,
              !quote.contains(where: \.isNewline) else { throw RoutineObservationReferenceError.invalidQuote }
        self.acquisitionID = acquisitionID; self.revisionSHA256 = revision
        self.frameID = frameID; self.quote = quote; self.isSynthetic = isSynthetic
    }

    private enum CodingKeys: String, CodingKey { case acquisitionID, revisionSHA256, frameID, quote, isSynthetic }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(acquisitionID: values.decode(UUID.self, forKey: .acquisitionID),
            revisionSHA256: values.decode(String.self, forKey: .revisionSHA256),
            frameID: values.decodeIfPresent(UUID.self, forKey: .frameID),
            quote: values.decode(String.self, forKey: .quote),
            // Unmarked pre-release bindings cannot establish personal provenance.
            isSynthetic: values.decodeIfPresent(Bool.self, forKey: .isSynthetic) ?? true)
    }
}
