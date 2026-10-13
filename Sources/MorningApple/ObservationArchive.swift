import Foundation
import MorningCore

public enum ObservationArchiveError: Error, LocalizedError, Sendable, Equatable {
    case invalidSource, invalidDate, invalidDigest, invalidRecordingContext, duplicateAcquisition, duplicateDigest
    case archiveFull, archiveTooLarge, unknownAcquisition, invalidClassification, correctedObservation, invalidFrameReview
    public var errorDescription: String? {
        switch self {
        case .invalidSource: String(localized: "An observation contains invalid or inconsistent source evidence.", bundle: .module)
        case .invalidDate: String(localized: "Choose a valid observed date and time zone.", bundle: .module)
        case .invalidDigest: String(localized: "The observation file fingerprint is invalid.", bundle: .module)
        case .invalidRecordingContext: String(localized: "The recording-start metadata is invalid for this observation.", bundle: .module)
        case .duplicateAcquisition: String(localized: "Two observations use the same acquisition identifier.", bundle: .module)
        case .duplicateDigest: String(localized: "The archive contains the same file more than once.", bundle: .module)
        case .archiveFull: String(localized: "The observation archive is full. Delete an observation before adding another.", bundle: .module)
        case .archiveTooLarge: String(localized: "The observation archive exceeds its storage limit. Delete an observation before adding more.", bundle: .module)
        case .unknownAcquisition: String(localized: "This observation is no longer in the archive.", bundle: .module)
        case .invalidClassification: String(localized: "This interpretation is not supported by the saved original evidence.", bundle: .module)
        case .correctedObservation: String(localized: "Corrected notes cannot retain an interpretation of the original recording.", bundle: .module)
        case .invalidFrameReview: String(localized: "This screen review is not supported by its saved original sample.", bundle: .module)
        }
    }
}

public enum ObservationAcquisitionOrigin: String, Codable, Sendable, CaseIterable {
    case human, synthetic, automated, unknown
}

public enum ObservationAcquisitionSourceKind: String, Codable, Sendable, CaseIterable {
    case image, video, text, manual, unknown
}

extension ObservationAcquisition {
    /// The source label of a typed note in builds that saved no source kind. It is
    /// persisted data, not interface text: it stays English and is never translated.
    public static let legacyWrittenSourceLabel = "Your written observation"

    /// Every label a build could have saved on a typed note of unknown kind: the English
    /// one, and the French one a localized pre-release build wrote during migration.
    public static let legacyWrittenSourceLabels = [legacyWrittenSourceLabel, "Votre observation écrite"]

    /// Whether this is evidence brought in from a file or recording rather than a note
    /// typed by the user. Decided from the saved source kind, so a source label written
    /// in one interface language reads the same in another. Only a legacy entry of
    /// unknown kind falls back to the fixed labels old builds gave a typed note.
    public var isImportedEvidence: Bool {
        switch sourceKind {
        case .manual: false
        case .image, .video, .text: true
        case .unknown: !Self.legacyWrittenSourceLabels.contains(sourceLabel)
        }
    }
}

public enum ObservationDateProvenance: String, Codable, Sendable {
    case recordingSession, userAssigned
}

/// An explicitly supplied recording-start instant or user-assigned day, in its original
/// zone. It assigns one observed day; it does not establish capture coverage across days.
public struct ObservationObservedDate: Codable, Sendable, Equatable {
    public let date: Date
    public let timeZoneIdentifier: String
    public let provenance: ObservationDateProvenance

    public init(date: Date, timeZoneIdentifier: String, provenance: ObservationDateProvenance) throws {
        guard archiveDateIsValid(date), timeZoneIdentifier.count <= 128,
              let zone = TimeZone(identifier: timeZoneIdentifier) else { throw ObservationArchiveError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let values = calendar.dateComponents([.era, .year], from: date)
        guard values.era == 1, let year = values.year, (1...9999).contains(year) else {
            throw ObservationArchiveError.invalidDate
        }
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.provenance = provenance
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return value
    }
    public var dayStart: Date { calendar.startOfDay(for: date) }
    public var dayKey: String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year!, values.month!, values.day!)
    }
    private enum CodingKeys: String, CodingKey { case date, timeZoneIdentifier, provenance }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: values.decode(Date.self, forKey: .date),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
                      provenance: values.decode(ObservationDateProvenance.self, forKey: .provenance))
    }
}

public enum ObservationAcquisitionWarning: String, Codable, Sendable {
    case invalidClassificationRemoved, invalidRecordingContextRemoved, invalidFrameReviewsRemoved
    public var message: String {
        switch self {
        case .invalidClassificationRemoved:
            String(localized: "An unsupported saved interpretation was removed. The original observation is still available.", bundle: .module)
        case .invalidRecordingContextRemoved:
            String(localized: "Unsupported recording-start metadata was removed. The original observation and its chosen day are still available.", bundle: .module)
        case .invalidFrameReviewsRemoved:
            String(localized: "Unsupported saved screen reviews and their original interpretation were removed. The original observation is still available for review.", bundle: .module)
        }
    }
}

/// Original source is immutable. Corrections are a separate field and always invalidate
/// attached analysis. The optional digest is caller-supplied local SHA-256, never a filename.
public struct ObservationAcquisition: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let importedAt: Date?
    public let fileSHA256: String?
    public let observedDate: ObservationObservedDate?
    /// Immutable native output-start callback metadata, independent of the editable day.
    /// It does not establish physical pickup, PTS-zero alignment or continuous coverage.
    /// Legacy and externally imported recordings have no inferred recording context.
    public let recordingContext: ObservationRecordingContext?
    public let origin: ObservationAcquisitionOrigin
    public let sourceKind: ObservationAcquisitionSourceKind
    public let sourceLabel: String
    public let originalText: String
    public let correctedText: String?
    public let videoEvidence: ObservationVideoEvidence?
    public let classification: ObservationContextClassification?
    /// User reviews override the projection only; original model output remains separate.
    public let frameReviews: [ObservationFrameReview]
    public let warnings: [ObservationAcquisitionWarning]
    /// Set when this observation is one segment of a longer recording session. Entries
    /// sharing its `sessionID` are one recording kept as several files, in index order.
    /// Nil for every observation saved before sessions existed and for a single file.
    public let sessionSegment: ObservationSessionSegmentReference?
    public var effectiveText: String { correctedText ?? originalText }

    public init(id: UUID = UUID(), importedAt: Date? = Date(), fileSHA256: String? = nil,
                observedDate: ObservationObservedDate? = nil, origin: ObservationAcquisitionOrigin = .unknown,
                sourceKind: ObservationAcquisitionSourceKind, sourceLabel: String, originalText: String,
                correctedText: String? = nil, videoEvidence: ObservationVideoEvidence? = nil,
                classification: ObservationContextClassification? = nil,
                warnings: [ObservationAcquisitionWarning] = [],
                recordingContext: ObservationRecordingContext? = nil,
                frameReviews: [ObservationFrameReview] = [],
                sessionSegment: ObservationSessionSegmentReference? = nil) throws {
        // Only a recorded file can be a segment of a recording session.
        guard sessionSegment == nil || sourceKind == .video else { throw ObservationArchiveError.invalidSource }
        self.sessionSegment = sessionSegment
        if let recordingContext, !Self.recordingContextIsValid(recordingContext, sourceKind: sourceKind) {
            throw ObservationArchiveError.invalidRecordingContext
        }
        guard importedAt.map(archiveDateIsValid) ?? true else { throw ObservationArchiveError.invalidDate }
        guard !sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sourceLabel.count <= 256, !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.textIsBounded(originalText, maximumCharacters: ObservationArchive.maximumOriginalTextCharacters),
              correctedText.map({ Self.textIsBounded($0, maximumCharacters: ObservationArchive.maximumTextCharacters) }) ?? true,
              warnings.count <= 4 else { throw ObservationArchiveError.invalidSource }
        let digest = fileSHA256?.lowercased()
        if let digest {
            guard digest.utf8.count == 64, digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ObservationArchiveError.invalidDigest
            }
        }
        if let videoEvidence {
            guard sourceKind == .video, videoEvidence.hasRecognizedText,
                  Self.hasOriginalVideoBody(originalText, renderedText: videoEvidence.renderedText) else {
                throw ObservationArchiveError.invalidSource
            }
        }
        try Self.validateFrameReviews(frameReviews, evidence: videoEvidence, correctedText: correctedText)
        let frameOrder = Dictionary(uniqueKeysWithValues: (videoEvidence?.frames ?? []).enumerated().map { ($0.element.id, $0.offset) })
        self.frameReviews = frameReviews.sorted { frameOrder[$0.sampleID, default: 0] < frameOrder[$1.sampleID, default: 0] }
        self.id = id
        self.importedAt = importedAt
        self.fileSHA256 = digest
        self.observedDate = observedDate
        self.recordingContext = recordingContext
        self.origin = origin
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
        self.originalText = originalText
        self.correctedText = correctedText
        self.videoEvidence = videoEvidence
        var retainedWarnings = warnings.reduce(into: [ObservationAcquisitionWarning]()) { result, warning in
            if !result.contains(warning) { result.append(warning) }
        }
        if let classification,
           correctedText != nil || !Self.supports(classification, evidence: videoEvidence) {
            self.classification = nil
            if !retainedWarnings.contains(.invalidClassificationRemoved) { retainedWarnings.append(.invalidClassificationRemoved) }
        } else {
            self.classification = classification
        }
        self.warnings = retainedWarnings
    }

    /// Strict mutation boundary. A human label is grounded by an exact original quote,
    /// but remains a human assertion, not a successful model classification.
    private static func validateFrameReviews(_ reviews: [ObservationFrameReview],
        evidence: ObservationVideoEvidence?, correctedText: String?) throws {
        guard reviews.count <= ObservationVideoEvidence.maximumFrames else { throw ObservationArchiveError.invalidFrameReview }
        guard !reviews.isEmpty else { return }
        guard correctedText == nil, let evidence else { throw ObservationArchiveError.invalidFrameReview }
        let frames = Dictionary(uniqueKeysWithValues: evidence.frames.map { ($0.id, $0) })
        var ids = Set<UUID>()
        for review in reviews {
            guard ids.insert(review.sampleID).inserted, let frame = frames[review.sampleID] else {
                throw ObservationArchiveError.invalidFrameReview
            }
            if review.label != nil {
                guard frame.canSupportIdentity, let quote = review.evidenceQuote,
                      Data(frame.text.utf8).range(of: Data(quote.utf8)) != nil else {
                    throw ObservationArchiveError.invalidFrameReview
                }
            }
        }
    }

    private static func recordingContextIsValid(_ context: ObservationRecordingContext,
                                                sourceKind: ObservationAcquisitionSourceKind) -> Bool {
        guard sourceKind == .video else { return false }
        // Apply the same finite Gregorian date/zone bounds as archived dates, without
        // assigning or reconstructing an editable observedDate from this metadata.
        return (try? ObservationObservedDate(date: context.startedAt,
            timeZoneIdentifier: context.timeZoneIdentifier, provenance: .recordingSession)) != nil
    }

    private static func textIsBounded(_ text: String, maximumCharacters: Int) -> Bool {
        text.count <= maximumCharacters && text.utf8.count <= ObservationArchive.maximumTextBytes
    }

    private static func hasOriginalVideoBody(_ text: String, renderedText: String) -> Bool {
        if text.utf8.elementsEqual(renderedText.utf8) { return true }
        guard text.count > renderedText.count else { return false }
        let split = text.index(text.endIndex, offsetBy: -renderedText.count)
        let prefix = text[..<split]
        return prefix.count <= 1_000 && prefix.hasPrefix("[Recording coverage: ") &&
            prefix.hasSuffix("]\n\n") && text[split...].utf8.elementsEqual(renderedText.utf8)
    }

    fileprivate func replacing(correctedText: String?, observedDate: ObservationObservedDate?,
                               classification: ObservationContextClassification?, origin: ObservationAcquisitionOrigin? = nil,
                               frameReviews: [ObservationFrameReview]? = nil) throws -> Self {
        try .init(id: id, importedAt: importedAt, fileSHA256: fileSHA256, observedDate: observedDate,
                  origin: origin ?? self.origin, sourceKind: sourceKind, sourceLabel: sourceLabel, originalText: originalText,
                  correctedText: correctedText, videoEvidence: videoEvidence,
                  classification: classification, warnings: warnings, recordingContext: recordingContext,
                  frameReviews: frameReviews ?? self.frameReviews, sessionSegment: sessionSegment)
    }

    /// Derived interpretation can be discarded independently of valid source. Exact source
    /// citations and prepared-input metadata are rechecked after restoration, not trusted.
    fileprivate static func supports(_ result: ObservationContextClassification,
                                     evidence: ObservationVideoEvidence?) -> Bool {
        guard let evidence, result.decisions.count == evidence.frames.count,
              (0...24).contains(result.attemptedBatchCount),
              (0...result.attemptedBatchCount).contains(result.respondedBatchCount),
              (0...result.attemptedBatchCount).contains(result.failedBatchCount),
              result.respondedBatchCount + result.failedBatchCount >= result.attemptedBatchCount,
              result.diagnostics.count <= 256, result.modelAvailability.count <= 512,
              result.modelIdentifier.count <= 256 else { return false }
        switch result.status {
        case .unavailable, .noEligibleFrames:
            guard result.attemptedBatchCount == 0 else { return false }
        case .completed:
            guard result.attemptedBatchCount > 0, result.failedBatchCount == 0 else { return false }
        case .partialFailure:
            guard result.failedBatchCount > 0, result.failedBatchCount < result.attemptedBatchCount else { return false }
        case .failed:
            guard result.failedBatchCount == result.attemptedBatchCount else { return false }
        }
        if result.status == .unavailable || result.status == .noEligibleFrames || result.status == .failed {
            guard result.decisions.allSatisfy({ $0.evidence == .unknown }) else { return false }
        }
        guard result.diagnostics.allSatisfy({ ($0.nativeError?.systemDomain?.count ?? 0) <= 128 }) else { return false }
        // Oversized derived payloads must be downgraded here, before archive-wide source
        // limits, so a damaged interpretation cannot strand otherwise valid observations.
        guard let encoded = try? JSONEncoder().encode(result), encoded.count <= 512 * 1_024 else { return false }
        do { _ = try evidence.makeTrace(decisions: result.decisions) } catch { return false }
        if let selection = result.inputSelection {
            guard !selection.policyIdentifier.isEmpty, selection.policyIdentifier.count <= 128,
                  (1...320).contains(selection.maximumExcerptCharacters),
                  (1...6).contains(selection.maximumNonemptyLines), selection.excerpts.count <= evidence.frames.count else { return false }
            let sources = Dictionary(uniqueKeysWithValues: evidence.frames.map { ($0.id, $0) })
            var seen = Set<UUID>()
            for excerpt in selection.excerpts {
                guard seen.insert(excerpt.sampleID).inserted, let source = sources[excerpt.sampleID],
                      source.canSupportIdentity, excerpt.sourceCharacterCount == source.text.count,
                      excerpt.startCharacterOffset == 0, excerpt.endCharacterOffset > 0,
                      excerpt.endCharacterOffset <= source.text.count,
                      excerpt.endCharacterOffset == excerpt.text.count,
                      excerpt.text.count <= selection.maximumExcerptCharacters,
                      !excerpt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      excerpt.wasExcerpted == (excerpt.endCharacterOffset < source.text.count),
                      source.text.prefix(excerpt.endCharacterOffset).utf8.elementsEqual(excerpt.text.utf8),
                      excerpt.text.split(whereSeparator: \.isNewline).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count <= selection.maximumNonemptyLines else { return false }
                if let ids = excerpt.ocrLineIDs {
                    guard let lines = source.ocrLines, ids.count <= 6, Set(ids).count == ids.count else { return false }
                    for id in ids {
                        guard let line = lines.first(where: { $0.id == id }), line.endCharacterOffset <= excerpt.endCharacterOffset else { return false }
                    }
                }
            }
            let excerpts = Dictionary(uniqueKeysWithValues: selection.excerpts.map { ($0.sampleID, $0) })
            for decision in result.decisions where decision.evidence != .unknown {
                guard let excerpt = excerpts[decision.sampleID], let quote = decision.evidenceQuote,
                      Data(excerpt.text.utf8).range(of: Data(quote.utf8)) != nil else { return false }
            }
        }
        return true
    }

    fileprivate var textByteCount: Int {
        var total = originalText.utf8.count + (correctedText?.utf8.count ?? 0) + sourceLabel.utf8.count
        for frame in videoEvidence?.frames ?? [] {
            total += frame.text.utf8.count
            for line in frame.ocrLines ?? [] { total += line.text.utf8.count }
        }
        for excerpt in classification?.inputSelection?.excerpts ?? [] { total += excerpt.text.utf8.count }
        for review in frameReviews { total += (review.label?.utf8.count ?? 0) + (review.evidenceQuote?.utf8.count ?? 0) }
        return total
    }
    fileprivate var lineCount: Int { videoEvidence?.frames.reduce(0) { $0 + ($1.ocrLines?.count ?? 0) } ?? 0 }

    private enum CodingKeys: String, CodingKey {
        case id, importedAt, fileSHA256, observedDate, origin, sourceKind, sourceLabel, originalText
        case correctedText, videoEvidence, classification, warnings, recordingContext, frameReviews
        case sessionSegment
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var warnings = try values.decodeIfPresent([ObservationAcquisitionWarning].self, forKey: .warnings) ?? []
        guard warnings.count <= 4 else { throw ObservationArchiveError.invalidSource }
        // Legal repeated warnings must not exhaust the room for recovery diagnostics.
        warnings = warnings.reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        let sourceKind = try values.decode(ObservationAcquisitionSourceKind.self, forKey: .sourceKind)
        let restoredContext: ObservationRecordingContext?
        do {
            let context = try values.decodeIfPresent(ObservationRecordingContext.self, forKey: .recordingContext)
            if let context, !Self.recordingContextIsValid(context, sourceKind: sourceKind) {
                throw ObservationArchiveError.invalidRecordingContext
            }
            restoredContext = context
        } catch {
            restoredContext = nil
            if !warnings.contains(.invalidRecordingContextRemoved) { warnings.append(.invalidRecordingContextRemoved) }
        }
        var restoredClassification: ObservationContextClassification?
        do { restoredClassification = try values.decodeIfPresent(ObservationContextClassification.self, forKey: .classification) }
        catch {
            restoredClassification = nil
            if !warnings.contains(.invalidClassificationRemoved) { warnings.append(.invalidClassificationRemoved) }
        }
        let correctedText = try values.decodeIfPresent(String.self, forKey: .correctedText)
        let videoEvidence = try values.decodeIfPresent(ObservationVideoEvidence.self, forKey: .videoEvidence)
        let restoredReviews: [ObservationFrameReview]
        do {
            let reviews = try values.decodeIfPresent([ObservationFrameReview].self, forKey: .frameReviews) ?? []
            try Self.validateFrameReviews(reviews, evidence: videoEvidence, correctedText: correctedText)
            restoredReviews = reviews
        } catch {
            // Do not restore a model label that an unreadable unknown review may have
            // explicitly rejected. Keep source, remove the whole overlay and analysis.
            restoredReviews = []
            restoredClassification = nil
            if !warnings.contains(.invalidFrameReviewsRemoved) { warnings.append(.invalidFrameReviewsRemoved) }
        }
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      importedAt: values.decodeIfPresent(Date.self, forKey: .importedAt),
                      fileSHA256: values.decodeIfPresent(String.self, forKey: .fileSHA256),
                      observedDate: values.decodeIfPresent(ObservationObservedDate.self, forKey: .observedDate),
                      origin: values.decode(ObservationAcquisitionOrigin.self, forKey: .origin),
                      sourceKind: sourceKind,
                      sourceLabel: values.decode(String.self, forKey: .sourceLabel),
                      originalText: values.decode(String.self, forKey: .originalText),
                      correctedText: correctedText, videoEvidence: videoEvidence,
                      classification: restoredClassification, warnings: warnings, recordingContext: restoredContext,
                      frameReviews: restoredReviews,
                      // A reference that cannot be read, or that sits on a source that is not a
                      // recording, leaves an ordinary single observation. It must not cost the
                      // person its text.
                      sessionSegment: sourceKind == .video
                          ? (try? values.decodeIfPresent(ObservationSessionSegmentReference.self, forKey: .sessionSegment))
                          : nil)
    }
}

/// Bounded acquisition history. Mutations validate a replacement before changing this value;
/// full archives reject additions rather than evicting a person's earlier observations.
/// Persistence and selected acquisition ID belong to the application workspace owner.
public struct ObservationArchive: Codable, Sendable, Equatable {
    public static let maximumEntries = 60
    public static let maximumOriginalTextCharacters = 33_000
    public static let maximumTextCharacters = 32_000
    public static let maximumTextBytes = 300_000
    public static let maximumAggregateTextBytes = 8 * 1_024 * 1_024
    public static let maximumOCRLines = 20_000
    public static let maximumEncodedBytes = 16 * 1_024 * 1_024
    public private(set) var entries: [ObservationAcquisition]

    public init() { entries = [] }

    public init(entries: [ObservationAcquisition]) throws {
        guard entries.count <= Self.maximumEntries else { throw ObservationArchiveError.archiveFull }
        var ids = Set<UUID>(); var digests = Set<String>()
        for entry in entries {
            guard ids.insert(entry.id).inserted else { throw ObservationArchiveError.duplicateAcquisition }
            if let digest = entry.fileSHA256, !digests.insert(digest).inserted { throw ObservationArchiveError.duplicateDigest }
        }
        // One segment of a session is one observation: a second entry for the same segment
        // would count that part of the recording twice.
        let segments = entries.compactMap { entry in
            entry.sessionSegment.map { SessionSegmentKey(sessionID: $0.sessionID, segmentIndex: $0.segmentIndex) }
        }
        guard Set(segments).count == segments.count else { throw ObservationArchiveError.duplicateAcquisition }
        guard entries.reduce(0, { $0 + $1.textByteCount }) <= Self.maximumAggregateTextBytes,
              entries.reduce(0, { $0 + $1.lineCount }) <= Self.maximumOCRLines else { throw ObservationArchiveError.archiveTooLarge }
        self.entries = entries
        guard try JSONEncoder().encode(self).count <= Self.maximumEncodedBytes else { throw ObservationArchiveError.archiveTooLarge }
    }

    public func entry(id: UUID) -> ObservationAcquisition? { entries.first { $0.id == id } }

    /// Same-file import preserves the first source, ID, dates, corrections and analysis.
    /// A new OCR pass is not a new observed morning. Explicit reclassification is separate.
    @discardableResult public mutating func insert(_ acquisition: ObservationAcquisition) throws -> UUID {
        if let existing = entry(id: acquisition.id) {
            guard existing.fileSHA256 == acquisition.fileSHA256, existing.sourceKind == acquisition.sourceKind,
                  existing.originalText.utf8.elementsEqual(acquisition.originalText.utf8) else { throw ObservationArchiveError.duplicateAcquisition }
            return existing.id
        }
        if let digest = acquisition.fileSHA256, let existing = entries.first(where: { $0.fileSHA256 == digest }) { return existing.id }
        self = try Self(entries: entries + [acquisition])
        return acquisition.id
    }

    /// Enrich an existing exact-file copy only with metadata retained by the caller's
    /// native recording session. This is not date inference or a metadata replacement.
    /// The workspace owner must atomically save success before deleting raw recovery.
    @discardableResult public mutating func attachRecordingContext(_ context: ObservationRecordingContext,
        to id: UUID, matchingFileSHA256 digest: String) throws -> Bool {
        let current = try required(id)
        let normalizedDigest = digest.lowercased()
        guard normalizedDigest.utf8.count == 64,
              normalizedDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              current.fileSHA256 == normalizedDigest else { throw ObservationArchiveError.invalidDigest }
        guard current.sourceKind == .video else { throw ObservationArchiveError.invalidRecordingContext }
        // Validate even if this is a no-op; malformed supplied metadata is never accepted.
        let enriched = try ObservationAcquisition(id: current.id, importedAt: current.importedAt,
            fileSHA256: current.fileSHA256, observedDate: current.observedDate, origin: current.origin,
            sourceKind: current.sourceKind, sourceLabel: current.sourceLabel, originalText: current.originalText,
            correctedText: current.correctedText, videoEvidence: current.videoEvidence,
            classification: current.classification, warnings: current.warnings, recordingContext: context,
            frameReviews: current.frameReviews, sessionSegment: current.sessionSegment)
        guard current.recordingContext == nil else { return false }
        try replace(enriched)
        return true
    }

    public mutating func correct(id: UUID, text: String?) throws {
        let current = try required(id)
        // An unchanged editor save is not a source edit. Exact bytes matter for both
        // evidence receipts and Unicode corrections.
        guard current.correctedText.map({ Data($0.utf8) }) != text.map({ Data($0.utf8) }) else { return }
        try replace(current.replacing(correctedText: text, observedDate: current.observedDate,
                                      classification: nil, frameReviews: []))
    }
    public mutating func assignObservedDate(id: UUID, value: ObservationObservedDate?, origin: ObservationAcquisitionOrigin? = nil) throws {
        let current = try required(id)
        try replace(current.replacing(correctedText: current.correctedText, observedDate: value, classification: current.classification, origin: origin))
    }
    public mutating func classify(id: UUID, result: ObservationContextClassification?) throws {
        let current = try required(id)
        if let result {
            guard current.correctedText == nil else { throw ObservationArchiveError.correctedObservation }
            guard ObservationAcquisition.supports(result, evidence: current.videoEvidence) else { throw ObservationArchiveError.invalidClassification }
        }
        try replace(current.replacing(correctedText: current.correctedText, observedDate: current.observedDate, classification: result))
    }
    /// Upsert one deliberate review; original source and model result stay unchanged.
    public mutating func reviewFrame(id: UUID, review: ObservationFrameReview) throws {
        let current = try required(id)
        guard current.correctedText == nil else { throw ObservationArchiveError.correctedObservation }
        let reviews = current.frameReviews.filter { $0.sampleID != review.sampleID } + [review]
        try replace(current.replacing(correctedText: nil, observedDate: current.observedDate,
            classification: current.classification, frameReviews: reviews))
    }
    /// Removing a review reveals the retained original interpretation, if still valid.
    public mutating func removeFrameReview(id: UUID, sampleID: UUID) throws {
        let current = try required(id)
        guard current.videoEvidence?.frames.contains(where: { $0.id == sampleID }) == true else {
            throw ObservationArchiveError.invalidFrameReview
        }
        try replace(current.replacing(correctedText: current.correctedText, observedDate: current.observedDate,
            classification: current.classification, frameReviews: current.frameReviews.filter { $0.sampleID != sampleID }))
    }
    public mutating func delete(id: UUID) throws {
        _ = try required(id)
        self = try Self(entries: entries.filter { $0.id != id })
    }
    public mutating func clear() { entries.removeAll() }

    /// The saved segments of one recording session, in the order they were recorded.
    public func entries(ofSession sessionID: UUID) -> [ObservationAcquisition] {
        entries.filter { $0.sessionSegment?.sessionID == sessionID }
            .sorted { $0.sessionSegment!.segmentIndex < $1.sessionSegment!.segmentIndex }
    }

    /// Removes every observation made from one recording session and nothing else.
    /// Returns the identifiers removed, in recording order.
    @discardableResult public mutating func deleteSession(_ sessionID: UUID) throws -> [UUID] {
        let removed = entries(ofSession: sessionID).map(\.id)
        guard !removed.isEmpty else { return [] }
        self = try Self(entries: entries.filter { $0.sessionSegment?.sessionID != sessionID })
        return removed
    }

    private func required(_ id: UUID) throws -> ObservationAcquisition {
        guard let value = entry(id: id) else { throw ObservationArchiveError.unknownAcquisition }
        return value
    }
    private mutating func replace(_ value: ObservationAcquisition) throws {
        guard let index = entries.firstIndex(where: { $0.id == value.id }) else { throw ObservationArchiveError.unknownAcquisition }
        var next = entries; next[index] = value
        self = try Self(entries: next)
    }
    private enum CodingKeys: String, CodingKey { case entries }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(entries: values.decode([ObservationAcquisition].self, forKey: .entries))
    }
}

private struct SessionSegmentKey: Hashable {
    let sessionID: UUID
    let segmentIndex: Int
}

private func archiveDateIsValid(_ date: Date) -> Bool {
    let seconds = date.timeIntervalSince1970
    return seconds.isFinite && seconds >= -62_135_596_800 && seconds < 253_402_300_800
}
