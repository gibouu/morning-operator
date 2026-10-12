import CryptoKit
import Foundation
import MorningCore

/// A person's review of one saved sample, separate from original OCR and model output.
/// A label names the visible context; it never establishes an installed app, an action,
/// capture coverage, or time spent. A nil label explicitly keeps this sample unknown.
public struct ObservationFrameReview: Codable, Sendable, Equatable {
    public static let maximumLabelCharacters = 80
    public static let maximumQuoteCharacters = 320

    public let sampleID: UUID
    public let label: String?
    public let evidenceQuote: String?
    /// When the person saved this review, not when the screen was captured.
    public let reviewedAt: Date

    public init(sampleID: UUID, label: String?, evidenceQuote: String? = nil,
                reviewedAt: Date = Date()) throws {
        let instant = reviewedAt.timeIntervalSince1970
        guard instant.isFinite, instant >= -62_135_596_800, instant < 253_402_300_800 else {
            throw ObservationArchiveError.invalidFrameReview
        }
        if let label {
            guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  label.count <= Self.maximumLabelCharacters, label.utf8.count <= 320,
                  !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let evidenceQuote, !evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  evidenceQuote.count <= Self.maximumQuoteCharacters, evidenceQuote.utf8.count <= 1_280 else {
                throw ObservationArchiveError.invalidFrameReview
            }
        } else if evidenceQuote != nil {
            throw ObservationArchiveError.invalidFrameReview
        }
        self.sampleID = sampleID; self.label = label
        self.evidenceQuote = evidenceQuote; self.reviewedAt = reviewedAt
    }

    /// Exact label bytes intentionally distinguish spelling/case/Unicode differences.
    /// A separate namespace prevents silent merging with inferred visual-context keys.
    public var contextIdentity: ObservationAppIdentity? {
        guard let label else { return nil }
        let digest = SHA256.hash(data: Data(label.utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(key: "reviewed-context:" + digest, displayName: label)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sampleID == rhs.sampleID && lhs.reviewedAt == rhs.reviewedAt &&
            lhs.label.map { Data($0.utf8) } == rhs.label.map { Data($0.utf8) } &&
            lhs.evidenceQuote.map { Data($0.utf8) } == rhs.evidenceQuote.map { Data($0.utf8) }
    }

    private enum CodingKeys: String, CodingKey { case sampleID, label, evidenceQuote, reviewedAt }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sampleID: values.decode(UUID.self, forKey: .sampleID),
            label: values.decodeIfPresent(String.self, forKey: .label),
            evidenceQuote: values.decodeIfPresent(String.self, forKey: .evidenceQuote),
            reviewedAt: values.decode(Date.self, forKey: .reviewedAt))
    }
}
