import Foundation
import CryptoKit
import MorningCore

public enum ObservationNarrationError: Error, LocalizedError, Sendable, Equatable {
    case dateRequired, originNotEligible, unsupportedSource, noUsableExcerpt
    case sourceMissing, sourceChanged, invalidExcerpt
    public var errorDescription: String? {
        switch self {
        case .dateRequired: String(localized: "Choose the observed day before adding this saved text to your morning.", bundle: .module)
        case .originNotEligible: String(localized: "Choose your own observation or a separate synthetic sample.", bundle: .module)
        case .unsupportedSource: String(localized: "This observation has no supported text source for narration.", bundle: .module)
        case .noUsableExcerpt: String(localized: "No complete short excerpt is available. Review or write a shorter note first.", bundle: .module)
        case .sourceMissing: String(localized: "The saved observation was removed. Review this moment or skip it.", bundle: .module)
        case .sourceChanged: String(localized: "The saved observation changed. Review and approve this moment again before speaking.", bundle: .module)
        case .invalidExcerpt: String(localized: "This excerpt no longer matches a complete line in the saved source.", bundle: .module)
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

/// The language of a composed introduction and date. An approved moment keeps the
/// language it was composed in; it never follows a later interface language change.
public enum ObservationNarrationLanguage: String, Sendable, Equatable, CaseIterable {
    case english = "en", french = "fr"
    public static var current: Self { AppLanguage.isFrench ? .french : .english }
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
    public static func prepare(acquisition: ObservationAcquisition, frameID: UUID, quote: String,
                               language: ObservationNarrationLanguage = .current) throws -> PreparedObservationNarration {
        try validateEligibility(acquisition)
        guard let candidate = candidates(for: acquisition).first(where: {
            $0.frameID == frameID && $0.text.utf8.elementsEqual(quote.utf8)
        }) else { throw ObservationNarrationError.invalidExcerpt }
        return try prepare(acquisition: acquisition, candidate: candidate, language: language)
    }

    public static func prepare(acquisition: ObservationAcquisition, candidate: ObservationNarrationCandidate,
                               language: ObservationNarrationLanguage = .current) throws -> PreparedObservationNarration {
        try validateEligibility(acquisition)
        let choices = candidates(for: acquisition)
        guard !choices.isEmpty else { throw ObservationNarrationError.noUsableExcerpt }
        guard choices.contains(where: { $0.id == candidate.id && $0.frameID == candidate.frameID &&
            $0.text.utf8.elementsEqual(candidate.text.utf8) }) else { throw ObservationNarrationError.invalidExcerpt }
        let reference = try RoutineObservationReference(acquisitionID: acquisition.id,
            revisionSHA256: revision(acquisition), frameID: candidate.frameID, quote: candidate.text,
            isSynthetic: acquisition.origin == .synthetic)
        return try document(acquisition: acquisition, reference: reference, language: language)
    }

    /// Recomputes the approved sentence without changing it. A source mutation
    /// requires a new preview/draft/approval, never an automatic text replacement.
    public static func resolve(reference: RoutineObservationReference, archive: ObservationArchive,
                               language: ObservationNarrationLanguage = .current) throws -> PreparedObservationNarration {
        try document(acquisition: validatedSource(of: reference, in: archive), reference: reference, language: language)
    }

    /// Resolves a saved, approved moment in the language its sentence was composed in.
    /// The interface language may have changed since approval (and moments approved
    /// before French existed are English), so the saved sentence selects the composition;
    /// the current language never rewrites it. A sentence that matches no composition of
    /// the unchanged source was edited or forged and requires a new approval.
    public static func resolve(reference: RoutineObservationReference, archive: ObservationArchive,
                               approvedText: String) throws -> PreparedObservationNarration {
        let acquisition = try validatedSource(of: reference, in: archive)
        for language in ObservationNarrationLanguage.allCases {
            let candidate = try document(acquisition: acquisition, reference: reference, language: language)
            if candidate.spokenText.utf8.elementsEqual(approvedText.utf8) { return candidate }
        }
        throw ObservationNarrationError.sourceChanged
    }

    private static func validatedSource(of reference: RoutineObservationReference,
                                        in archive: ObservationArchive) throws -> ObservationAcquisition {
        guard let acquisition = archive.entry(id: reference.acquisitionID) else { throw ObservationNarrationError.sourceMissing }
        try validateEligibility(acquisition)
        guard reference.isSynthetic == (acquisition.origin == .synthetic),
              try revision(acquisition) == reference.revisionSHA256 else { throw ObservationNarrationError.sourceChanged }
        guard candidates(for: acquisition).contains(where: {
            $0.frameID == reference.frameID && $0.text.utf8.elementsEqual(reference.quote.utf8)
        }) else { throw ObservationNarrationError.invalidExcerpt }
        return acquisition
    }

    private static func validateEligibility(_ acquisition: ObservationAcquisition) throws {
        guard acquisition.observedDate != nil else { throw ObservationNarrationError.dateRequired }
        guard acquisition.origin == .human || acquisition.origin == .synthetic else { throw ObservationNarrationError.originNotEligible }
        guard acquisition.sourceKind != .unknown else { throw ObservationNarrationError.unsupportedSource }
        if acquisition.sourceKind == .video && acquisition.correctedText == nil && acquisition.videoEvidence == nil {
            throw ObservationNarrationError.unsupportedSource
        }
    }

    private static func document(acquisition: ObservationAcquisition, reference: RoutineObservationReference,
                                 language: ObservationNarrationLanguage) throws -> PreparedObservationNarration {
        guard let observed = acquisition.observedDate else { throw ObservationNarrationError.dateRequired }
        let french = language == .french
        let formatter = DateFormatter()
        formatter.locale = french ? Locale(identifier: "fr_FR") : Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: observed.timeZoneIdentifier)
        formatter.dateFormat = french ? "d MMMM yyyy" : "MMMM d, yyyy"
        let date = formatter.string(from: observed.date)
        enum Layer { case reviewedNote, screenText, imageText, text, note }
        let layer: Layer
        if acquisition.correctedText != nil { layer = .reviewedNote }
        else {
            switch acquisition.sourceKind {
            case .video: layer = .screenText
            case .image: layer = .imageText
            case .text: layer = .text
            case .manual: layer = .note
            case .unknown: throw ObservationNarrationError.unsupportedSource
            }
        }
        let synthetic = acquisition.origin == .synthetic
        let introduction: String
        if french {
            let noun = switch layer {
            case .reviewedNote: "note relue"
            case .screenText: "texte d’écran enregistré"
            case .imageText: "texte d’image enregistré"
            case .text: "texte enregistré"
            case .note: "note enregistrée"
            }
            let article = layer == .reviewedNote || layer == .note ? "la" : "le"
            introduction = synthetic ? "Dans \(article) \(noun) de cet exemple synthétique, du \(date) :"
                : "Dans votre \(noun) du \(date) :"
        } else {
            let noun = switch layer {
            case .reviewedNote: "reviewed note"
            case .screenText: "saved screen text"
            case .imageText: "saved image text"
            case .text: "saved text"
            case .note: "saved note"
            }
            introduction = "\(synthetic ? "In this synthetic sample's" : "In your") \(noun) from \(date):"
        }
        let sentence = "\(introduction)\n\(reference.quote)"
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
