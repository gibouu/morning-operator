import Foundation
import CryptoKit
import MorningCore

public enum ObservationNarrationError: Error, LocalizedError, Sendable, Equatable {
    case dateRequired, originNotEligible, unsupportedSource, noUsableExcerpt
    case sourceMissing, sourceChanged, invalidExcerpt
    public var errorDescription: String? {
        switch self {
        case .dateRequired: "Choose the observed day before adding this saved text to your morning."
        case .originNotEligible: "Choose your own observation or a separate synthetic sample."
        case .unsupportedSource: "This observation has no supported text source for narration."
        case .noUsableExcerpt: "No complete short excerpt is available. Review or write a shorter note first."
        case .sourceMissing: "The saved observation was removed. Review this moment or skip it."
        case .sourceChanged: "The saved observation changed. Review and approve this moment again before speaking."
        case .invalidExcerpt: "This excerpt no longer matches a complete line in the saved source."
        }
    }
}

public struct ObservationNarrationCandidate: Identifiable, Sendable, Equatable {
    public let id: String
    public let frameID: UUID?
    public let text: String
}

/// Deterministic exact text for a historical observation, not a live briefing.
/// Store this reference in a draft step and use ordinary routine approval. The
/// displayed and spoken text must be identical, with source age shown separately.
public struct PreparedObservationNarration: Sendable, Equatable {
    public let reference: RoutineObservationReference
    public let spokenText: String
    public let sourceLabel: String
    public let sourceDateLabel: String
}

public enum ObservationNarrationComposer {
    public static let maximumCandidates = 24

    /// Offers whole retained lines only. No model, sentence completion, semantic
    /// label selection, synthetic fallback or truncation is performed.
    public static func candidates(for acquisition: ObservationAcquisition) -> [ObservationNarrationCandidate] {
        guard (try? validateEligibility(acquisition)) != nil else { return [] }
        var result: [ObservationNarrationCandidate] = []
        func appendLines(_ text: String, frameID: UUID?) {
            for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
                guard result.count < maximumCandidates else { return }
                let exact = String(line)
                guard !exact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      exact.count <= RoutineObservationReference.maximumQuoteCharacters,
                      exact.utf8.count <= RoutineObservationReference.maximumQuoteUTF8Bytes else { continue }
                let digest = SHA256.hash(data: Data(exact.utf8)).map { String(format: "%02x", $0) }.joined()
                result.append(.init(id: "\(frameID?.uuidString ?? "notes"):\(index):\(digest)", frameID: frameID, text: exact))
            }
        }
        if let correction = acquisition.correctedText {
            appendLines(correction, frameID: nil)
        } else if acquisition.sourceKind == .video {
            for frame in acquisition.videoEvidence?.frames ?? [] where frame.outcome == .observed {
                // Limited OCR can end mid-line. Such frames stay reviewable elsewhere,
                // but cannot supply a claimed complete line to this bounded narration.
                guard !frame.textWasTruncated else { continue }
                appendLines(frame.text, frameID: frame.id)
                if result.count == maximumCandidates { break }
            }
        } else {
            appendLines(acquisition.originalText, frameID: nil)
        }
        return result
    }

    /// Direct sample handoff preserves the exact selected line and frame. A
    /// substring, different frame or unavailable source never chooses a fallback.
    public static func prepare(acquisition: ObservationAcquisition, frameID: UUID,
                               quote: String) throws -> PreparedObservationNarration {
        try validateEligibility(acquisition)
        guard let candidate = candidates(for: acquisition).first(where: {
            $0.frameID == frameID && $0.text.utf8.elementsEqual(quote.utf8)
        }) else { throw ObservationNarrationError.invalidExcerpt }
        return try prepare(acquisition: acquisition, candidate: candidate)
    }

    public static func prepare(acquisition: ObservationAcquisition,
                               candidate: ObservationNarrationCandidate) throws -> PreparedObservationNarration {
        try validateEligibility(acquisition)
        let choices = candidates(for: acquisition)
        guard !choices.isEmpty else { throw ObservationNarrationError.noUsableExcerpt }
        guard choices.contains(where: { $0.id == candidate.id && $0.frameID == candidate.frameID &&
            $0.text.utf8.elementsEqual(candidate.text.utf8) }) else { throw ObservationNarrationError.invalidExcerpt }
        let reference = try RoutineObservationReference(acquisitionID: acquisition.id,
            revisionSHA256: revision(acquisition), frameID: candidate.frameID, quote: candidate.text,
            isSynthetic: acquisition.origin == .synthetic)
        return try document(acquisition: acquisition, reference: reference)
    }

    /// Recomputes the approved sentence without changing it. A source mutation
    /// requires a new preview/draft/approval, never an automatic text replacement.
    public static func resolve(reference: RoutineObservationReference,
                               archive: ObservationArchive) throws -> PreparedObservationNarration {
        guard let acquisition = archive.entry(id: reference.acquisitionID) else { throw ObservationNarrationError.sourceMissing }
        try validateEligibility(acquisition)
        guard reference.isSynthetic == (acquisition.origin == .synthetic),
              try revision(acquisition) == reference.revisionSHA256 else { throw ObservationNarrationError.sourceChanged }
        guard candidates(for: acquisition).contains(where: {
            $0.frameID == reference.frameID && $0.text.utf8.elementsEqual(reference.quote.utf8)
        }) else { throw ObservationNarrationError.invalidExcerpt }
        return try document(acquisition: acquisition, reference: reference)
    }

    private static func validateEligibility(_ acquisition: ObservationAcquisition) throws {
        guard acquisition.observedDate != nil else { throw ObservationNarrationError.dateRequired }
        guard acquisition.origin == .human || acquisition.origin == .synthetic else { throw ObservationNarrationError.originNotEligible }
        guard acquisition.sourceKind != .unknown else { throw ObservationNarrationError.unsupportedSource }
        if acquisition.sourceKind == .video && acquisition.correctedText == nil && acquisition.videoEvidence == nil {
            throw ObservationNarrationError.unsupportedSource
        }
    }

    private static func document(acquisition: ObservationAcquisition,
                                 reference: RoutineObservationReference) throws -> PreparedObservationNarration {
        guard let observed = acquisition.observedDate else { throw ObservationNarrationError.dateRequired }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: observed.timeZoneIdentifier)
        formatter.dateFormat = "MMMM d, yyyy"
        let date = formatter.string(from: observed.date)
        let layer: String
        if acquisition.correctedText != nil { layer = "reviewed note" }
        else {
            switch acquisition.sourceKind {
            case .video: layer = "saved screen text"
            case .image: layer = "saved image text"
            case .text: layer = "saved text"
            case .manual: layer = "saved note"
            case .unknown: throw ObservationNarrationError.unsupportedSource
            }
        }
        let introduction = acquisition.origin == .synthetic ? "In this synthetic sample's" : "In your"
        let sentence = "\(introduction) \(layer) from \(date):\n\(reference.quote)"
        return .init(reference: reference, spokenText: sentence, sourceLabel: acquisition.sourceLabel,
                     sourceDateLabel: "\(date) · \(observed.timeZoneIdentifier)")
    }

    private static func revision(_ acquisition: ObservationAcquisition) throws -> String {
        // Independent schema: do not change the existing learning-proposal digest.
        // Classification is not used in a direct quote and cannot authorize speech.
        struct Source: Encodable {
            let schemaVersion = 1
            let id: UUID; let importedAt: Date?; let fileSHA256: String?
            let observedDate: ObservationObservedDate?; let recordingContext: ObservationRecordingContext?
            let origin: ObservationAcquisitionOrigin; let sourceKind: ObservationAcquisitionSourceKind
            let sourceLabel: String; let originalText: String; let correctedText: String?
            let videoEvidence: ObservationVideoEvidence?
        }
        let source = Source(id: acquisition.id, importedAt: acquisition.importedAt, fileSHA256: acquisition.fileSHA256,
            observedDate: acquisition.observedDate, recordingContext: acquisition.recordingContext, origin: acquisition.origin,
            sourceKind: acquisition.sourceKind, sourceLabel: acquisition.sourceLabel, originalText: acquisition.originalText,
            correctedText: acquisition.correctedText, videoEvidence: acquisition.videoEvidence)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(source)).map { String(format: "%02x", $0) }.joined()
    }
}
