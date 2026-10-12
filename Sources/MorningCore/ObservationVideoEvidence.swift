import Foundation

public enum ObservationVideoEvidenceError: Error, LocalizedError, Sendable, Equatable {
    case invalidFrame, invalidDuration, invalidFrameOrder, duplicateSample, evidenceTooLarge
    case unknownDecisionSample, duplicateDecision, decisionTimeMismatch, invalidCitation

    public var errorDescription: String? {
        switch self {
        case .invalidFrame: String(localized: "A video sample contains inconsistent extraction evidence.", bundle: .module)
        case .invalidDuration: String(localized: "The video evidence has an unsupported duration.", bundle: .module)
        case .invalidFrameOrder: String(localized: "Requested video samples must remain in time order.", bundle: .module)
        case .duplicateSample: String(localized: "The video evidence contains a repeated sample identifier.", bundle: .module)
        case .evidenceTooLarge: String(localized: "The video evidence exceeds the bounded frame or text budget.", bundle: .module)
        case .unknownDecisionSample: String(localized: "A screen interpretation refers to an unknown sample.", bundle: .module)
        case .duplicateDecision: String(localized: "A sample has more than one screen interpretation.", bundle: .module)
        case .decisionTimeMismatch: String(localized: "A screen interpretation changed its source timestamp.", bundle: .module)
        case .invalidCitation: String(localized: "A screen interpretation is not supported by its exact source sample.", bundle: .module)
        }
    }
}

/// One request and its extraction result, including failures. IDs are created once per
/// extraction and survive encoding/rendering; they are not content hashes across reimports.
public struct ObservationFrameEvidence: Codable, Identifiable, Sendable, Equatable {
    public static let maximumOCRLines = 256

    public let id: UUID
    public let requestedTimeSeconds: Double
    public let actualTimeSeconds: Double?
    /// Exact native fields, when retained at extraction. Nil includes legacy frames and
    /// unsupported/restored timing metadata; never reconstruct this value from seconds.
    public let originalPresentationTime: ObservationMediaTime?
    public let outcome: ObservationSampleOutcome
    public let text: String
    public let textWasTruncated: Bool
    public let warnings: [String]
    /// Nil means layout was not supplied (including legacy observations). An empty array
    /// means no line spans were retained, not that OCR was blank. Any nonnil array may
    /// be a bounded subset; its presence does not establish complete layout coverage.
    public let ocrLines: [ObservationOCRLine]?

    public var timeSeconds: Double { actualTimeSeconds ?? requestedTimeSeconds }
    public var timeBasis: ObservationSampleTimeBasis { actualTimeSeconds == nil ? .requestedSamplingTime : .mediaPresentation }
    public var evidenceReference: String { "sample:\(id.uuidString)" }
    public var canSupportIdentity: Bool { outcome == .observed && !textWasTruncated && !text.isEmpty }

    public init(id: UUID = UUID(), requestedTimeSeconds: Double, actualTimeSeconds: Double? = nil,
                outcome: ObservationSampleOutcome, text: String = "", textWasTruncated: Bool = false,
                warnings: [String] = [], ocrLines: [ObservationOCRLine]? = nil,
                originalPresentationTime: ObservationMediaTime? = nil) throws {
        guard requestedTimeSeconds.isFinite, requestedTimeSeconds >= 0,
              actualTimeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              warnings.count <= 8, warnings.allSatisfy({ $0.count <= 256 }),
              text.count <= ObservationVideoEvidence.maximumOCRCharacters,
              text.utf8.count <= ObservationVideoEvidence.maximumOCRBytes else {
            throw ObservationVideoEvidenceError.invalidFrame
        }
        if outcome == .observed {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || textWasTruncated else {
                throw ObservationVideoEvidenceError.invalidFrame
            }
        } else {
            guard text.isEmpty, !textWasTruncated else { throw ObservationVideoEvidenceError.invalidFrame }
        }
        if outcome == .decodeFailed, actualTimeSeconds != nil { throw ObservationVideoEvidenceError.invalidFrame }
        if let originalPresentationTime {
            guard outcome != .decodeFailed,
                  actualTimeSeconds == originalPresentationTime.seconds else {
                throw ObservationVideoEvidenceError.invalidFrame
            }
        }
        if let ocrLines {
            guard ocrLines.count <= Self.maximumOCRLines else { throw ObservationVideoEvidenceError.invalidFrame }
            var lineIDs = Set<UUID>()
            let sourceCharacterCount = text.count
            var previousEnd = 0
            var sourceCursor = text.startIndex
            for line in ocrLines {
                guard lineIDs.insert(line.id).inserted,
                      line.startCharacterOffset >= previousEnd,
                      line.endCharacterOffset <= sourceCharacterCount else {
                    throw ObservationVideoEvidenceError.invalidFrame
                }
                let start = text.index(sourceCursor, offsetBy: line.startCharacterOffset - previousEnd)
                let end = text.index(start, offsetBy: line.endCharacterOffset - line.startCharacterOffset)
                // Swift String equality permits canonical Unicode equivalence. Provenance
                // requires the original scalar sequence, including whitespace and accents.
                guard text[start..<end].unicodeScalars.elementsEqual(line.text.unicodeScalars) else {
                    throw ObservationVideoEvidenceError.invalidFrame
                }
                previousEnd = line.endCharacterOffset
                sourceCursor = end
            }
        }
        self.id = id
        self.requestedTimeSeconds = requestedTimeSeconds
        self.actualTimeSeconds = actualTimeSeconds
        self.originalPresentationTime = originalPresentationTime
        self.outcome = outcome
        self.text = text
        self.textWasTruncated = textWasTruncated
        self.warnings = warnings
        self.ocrLines = ocrLines
    }

    private enum CodingKeys: String, CodingKey {
        case id, requestedTimeSeconds, actualTimeSeconds, outcome, text, textWasTruncated, warnings, ocrLines
        case originalPresentationTime
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Validate source text/layout/decimal timing independently. A broken optional native
        // timestamp must not strand otherwise valid OCR, and cannot rescue invalid source.
        let source = try Self(id: values.decode(UUID.self, forKey: .id),
            requestedTimeSeconds: values.decode(Double.self, forKey: .requestedTimeSeconds),
            actualTimeSeconds: values.decodeIfPresent(Double.self, forKey: .actualTimeSeconds),
            outcome: values.decode(ObservationSampleOutcome.self, forKey: .outcome),
            text: values.decode(String.self, forKey: .text),
            textWasTruncated: values.decode(Bool.self, forKey: .textWasTruncated),
            warnings: values.decode([String].self, forKey: .warnings),
            ocrLines: values.decodeIfPresent([ObservationOCRLine].self, forKey: .ocrLines))
        do {
            let original = try values.decodeIfPresent(ObservationMediaTime.self, forKey: .originalPresentationTime)
            self = try Self(id: source.id, requestedTimeSeconds: source.requestedTimeSeconds,
                actualTimeSeconds: source.actualTimeSeconds, outcome: source.outcome, text: source.text,
                textWasTruncated: source.textWasTruncated, warnings: source.warnings,
                ocrLines: source.ocrLines, originalPresentationTime: original)
        } catch {
            let warning = String(localized: "Original media timing metadata was invalid or inconsistent and was omitted; saved sample time and text were preserved.", bundle: .module)
            let warnings: [String]
            if source.warnings.contains(warning) { warnings = source.warnings }
            else if source.warnings.count < 8 { warnings = source.warnings + [warning] }
            else { warnings = Array(source.warnings.prefix(7)) + [warning + String(localized: " One prior warning was omitted.", bundle: .module)] }
            self = try Self(id: source.id, requestedTimeSeconds: source.requestedTimeSeconds,
                actualTimeSeconds: source.actualTimeSeconds, outcome: source.outcome, text: source.text,
                textWasTruncated: source.textWasTruncated, warnings: warnings, ocrLines: source.ocrLines)
        }
    }
}

/// An immutable, bounded extraction. The file timeline says nothing about wall-clock start,
/// continuous native capture, or a complete human morning. Those are separate declarations.
public struct ObservationVideoEvidence: Codable, Identifiable, Sendable, Equatable {
    public static let maximumFrames = 24
    public static let maximumDurationSeconds: Double = 31 * 60
    // Reserve space for frame/timeline labels within the 32,000-character notes limit.
    public static let maximumOCRCharacters = 30_000
    public static let maximumOCRBytes = 256_000
    public static let maximumRenderedCharacters = 32_000

    public let id: UUID
    public let durationSeconds: Double
    public let frames: [ObservationFrameEvidence]
    public let warnings: [String]
    public var hasRecognizedText: Bool { frames.contains { $0.outcome == .observed && !$0.text.isEmpty } }
    public var decodedFrameCount: Int { frames.filter { $0.outcome != .decodeFailed }.count }

    public init(id: UUID = UUID(), durationSeconds: Double, frames: [ObservationFrameEvidence],
                warnings: [String] = []) throws {
        guard durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= Self.maximumDurationSeconds else {
            throw ObservationVideoEvidenceError.invalidDuration
        }
        guard !frames.isEmpty, frames.count <= Self.maximumFrames,
              frames.reduce(0, { $0 + $1.text.count }) <= Self.maximumOCRCharacters,
              frames.reduce(0, { $0 + $1.text.utf8.count }) <= Self.maximumOCRBytes,
              warnings.count <= 32, warnings.allSatisfy({ $0.count <= 256 }) else {
            throw ObservationVideoEvidenceError.evidenceTooLarge
        }
        var ids = Set<UUID>()
        var previousRequest: Double?
        for frame in frames {
            guard ids.insert(frame.id).inserted else { throw ObservationVideoEvidenceError.duplicateSample }
            guard frame.requestedTimeSeconds < durationSeconds,
                  frame.actualTimeSeconds.map({ $0 <= durationSeconds }) ?? true else {
                throw ObservationVideoEvidenceError.invalidFrame
            }
            if let previousRequest, frame.requestedTimeSeconds <= previousRequest {
                throw ObservationVideoEvidenceError.invalidFrameOrder
            }
            previousRequest = frame.requestedTimeSeconds
        }
        self.id = id
        self.durationSeconds = durationSeconds
        self.frames = frames
        self.warnings = warnings
        guard renderedText.count <= Self.maximumRenderedCharacters else { throw ObservationVideoEvidenceError.evidenceTooLarge }
    }

    /// A display rendering of this extraction, never a second OCR pass. Deduplication here
    /// affects notes only; original frames and later returns remain in the structured evidence.
    public var renderedText: String {
        let header = "[User-selected video: \(Self.timestamp(durationSeconds)); \(decodedFrameCount) frames sampled. This is partial visual evidence, not a complete interaction log.]"
        var segments = [header]
        var previousText: String?
        for frame in frames {
            guard frame.outcome == .observed, !frame.text.isEmpty else { previousText = nil; continue }
            let normalized = frame.text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard normalized != previousText else { continue }
            segments.append("[Observed frame at \(Self.timestamp(frame.timeSeconds))]\n\(frame.text)")
            previousText = normalized
        }
        if frames.contains(where: \.textWasTruncated) {
            segments.append("[Some OCR text was omitted to stay within the import limit. Truncated frames cannot support app identification.]")
        }
        return segments.joined(separator: "\n\n")
    }

    /// Decisions identify visible contexts, not OS launches. Missing decisions remain unknown.
    /// Coverage must be supplied independently from trusted capture metadata; default is unknown.
    public func makeTrace(decisions: [ObservationFrameIdentityDecision] = [],
                          origin: ObservationTraceOrigin = .unknown,
                          capturedIntervals: [ObservationTraceInterval]? = nil) throws -> ObservationTrace {
        let source = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
        var accepted: [UUID: ObservationAppEvidence] = [:]
        for decision in decisions {
            guard let frame = source[decision.sampleID] else { throw ObservationVideoEvidenceError.unknownDecisionSample }
            guard accepted[decision.sampleID] == nil else { throw ObservationVideoEvidenceError.duplicateDecision }
            guard decision.timeSeconds == frame.timeSeconds, decision.timeBasis == frame.timeBasis else {
                throw ObservationVideoEvidenceError.decisionTimeMismatch
            }
            guard decision.reason.map({ $0.count <= 256 }) ?? true else { throw ObservationVideoEvidenceError.invalidCitation }
            switch decision.evidence {
            case .unknown:
                guard decision.evidenceQuote == nil else { throw ObservationVideoEvidenceError.invalidCitation }
            case .identified(_, let reference), .ambiguous(let reference):
                guard frame.canSupportIdentity, reference == frame.evidenceReference,
                      let quote = decision.evidenceQuote, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      quote.count <= 512, Data(frame.text.utf8).range(of: Data(quote.utf8)) != nil else {
                    throw ObservationVideoEvidenceError.invalidCitation
                }
            }
            accepted[decision.sampleID] = decision.evidence
        }
        return try ObservationTrace(id: id, durationSeconds: durationSeconds, capturedIntervals: capturedIntervals,
            origin: origin, samples: frames.map {
                ObservationTraceSample(id: $0.id, timeSeconds: $0.timeSeconds, timeBasis: $0.timeBasis,
                                       outcome: $0.outcome, appEvidence: accepted[$0.id] ?? .unknown)
            })
    }

    private static func timestamp(_ seconds: Double) -> String {
        String(format: "%02d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    private enum CodingKeys: String, CodingKey { case id, durationSeconds, frames, warnings }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      durationSeconds: values.decode(Double.self, forKey: .durationSeconds),
                      frames: values.decode([ObservationFrameEvidence].self, forKey: .frames),
                      warnings: values.decode([String].self, forKey: .warnings))
    }
}

/// The shared classifier/adapter envelope. Validation against the original frame happens
/// in makeTrace, including after decoding. Outcome always comes from the source frame.
public struct ObservationFrameIdentityDecision: Codable, Sendable, Equatable {
    public let sampleID: UUID
    public let timeSeconds: Double
    public let timeBasis: ObservationSampleTimeBasis
    public let evidence: ObservationAppEvidence
    public let evidenceQuote: String?
    public let reason: String?
    public init(sampleID: UUID, timeSeconds: Double, timeBasis: ObservationSampleTimeBasis,
                evidence: ObservationAppEvidence, evidenceQuote: String? = nil, reason: String? = nil) {
        self.sampleID = sampleID
        self.timeSeconds = timeSeconds
        self.timeBasis = timeBasis
        self.evidence = evidence
        self.evidenceQuote = evidenceQuote
        self.reason = reason
    }
}
