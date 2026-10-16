import Foundation
import MorningCore

/// A separately supplied vocabulary of visible headers, never an expected event sequence.
/// Neither field is an OS bundle identifier or evidence that the app was opened.
public struct ObservationContextCatalogEntry: Codable, Sendable, Equatable {
    public let label: String
    public let headerText: String
    public init(label: String, headerText: String? = nil) {
        self.label = label
        self.headerText = headerText ?? label
    }
}

public enum ObservationContextClassificationError: LocalizedError, Sendable, Equatable {
    case invalidFrames, invalidCatalog, alreadyClassifying
    public var errorDescription: String? {
        switch self {
        case .invalidFrames: AppLanguage.localized("The observation frames have invalid or duplicate identifiers or timestamps.", bundle: .module)
        case .invalidCatalog: AppLanguage.localized("The visible-context catalog is invalid, ambiguous or too large.", bundle: .module)
        case .alreadyClassifying: AppLanguage.localized("A visible-context analysis is already running.", bundle: .module)
        }
    }
}

public enum ObservationContextInferenceStatus: String, Codable, Sendable {
    case noEligibleFrames, unavailable, completed, partialFailure, failed
}

/// Fixed error categories only. Associated SDK contexts may contain user text and are
/// deliberately never inspected. Unknown NSError domains and their codes are omitted.
public struct ObservationContextNativeError: Codable, Sendable, Equatable {
    public enum Category: String, Codable, Sendable {
        case contextSizeExceeded, assetsUnavailable, guardrailViolation, unsupportedGuide
        case unsupportedLanguageOrLocale, decodingFailure, rateLimited, concurrentRequests, refusal
        case unsupportedCapability, unsupportedTranscriptContent, timeout, transcriptMutationWhileResponding
        case unknownFoundationModelsError, other
    }
    public let category: Category
    public let systemDomain: String?
    public let errorCode: Int?

    init(category: Category, systemDomain: String? = nil, errorCode: Int? = nil) {
        self.category = category; self.systemDomain = systemDomain; self.errorCode = errorCode
    }
}

public struct ObservationContextDiagnostic: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case unknownSampleID, duplicateSampleID, invalidResponse, invalidEvidence
        case unsupportedIdentity, generationFailed
    }
    public let kind: Kind
    public let sampleID: UUID?
    /// Optional so classifications saved before sanitized diagnostics still decode.
    public let nativeError: ObservationContextNativeError?
    public init(kind: Kind, sampleID: UUID? = nil, nativeError: ObservationContextNativeError? = nil) {
        self.kind = kind; self.sampleID = sampleID; self.nativeError = nativeError
    }
}

/// An exact, whole-line source prefix selected for model input. Offsets count Swift
/// Characters, not UTF-8 bytes or UTF-16 code units; the end offset is exclusive.
/// This is deliberate input selection, distinct from truncated/incomplete source OCR.
public struct ObservationContextExcerpt: Codable, Sendable, Equatable {
    public let sampleID: UUID
    public let sourceCharacterCount: Int
    public let startCharacterOffset: Int
    public let endCharacterOffset: Int
    public let text: String
    public let wasExcerpted: Bool
    /// Exact source lines whose optional layout hints were sent with this excerpt.
    /// Nil means source geometry was unavailable; an empty list means none was selected.
    public let ocrLineIDs: [UUID]?

    fileprivate func withOCRLineIDs(_ ids: [UUID]?) -> Self {
        .init(sampleID: sampleID, sourceCharacterCount: sourceCharacterCount,
              startCharacterOffset: startCharacterOffset, endCharacterOffset: endCharacterOffset,
              text: text, wasExcerpted: wasExcerpted, ocrLineIDs: ids)
    }
}

/// Describes prepared input even when the model was unavailable. Presence does not imply
/// an inference attempt; consult the classification status and attempted batch count.
public struct ObservationContextInputSelection: Codable, Sendable, Equatable {
    public let policyIdentifier: String
    public let maximumExcerptCharacters: Int
    public let maximumNonemptyLines: Int
    public let excerpts: [ObservationContextExcerpt]
}

/// Inference completion is not a claim that all frames were identified or correctly classified.
/// Unavailable/failed calls have explicit status; there is no deterministic fallback labeler.
public struct ObservationContextClassification: Codable, Sendable, Equatable {
    public let decisions: [ObservationFrameIdentityDecision]
    public let status: ObservationContextInferenceStatus
    public let attemptedBatchCount: Int
    public let respondedBatchCount: Int
    public let failedBatchCount: Int
    public let diagnostics: [ObservationContextDiagnostic]
    public let modelAvailability: String
    public let modelIdentifier: String
    /// Nil for classifications saved before explicit excerpt metadata was introduced.
    public let inputSelection: ObservationContextInputSelection?

    init(decisions: [ObservationFrameIdentityDecision], status: ObservationContextInferenceStatus,
         attemptedBatchCount: Int, respondedBatchCount: Int, failedBatchCount: Int,
         diagnostics: [ObservationContextDiagnostic], modelAvailability: String,
         inputSelection: ObservationContextInputSelection? = nil) {
        self.decisions = decisions; self.status = status
        self.attemptedBatchCount = attemptedBatchCount; self.respondedBatchCount = respondedBatchCount
        self.failedBatchCount = failedBatchCount; self.diagnostics = diagnostics
        self.modelAvailability = modelAvailability
        self.modelIdentifier = "Apple Foundation Models / SystemLanguageModel.default"
        self.inputSelection = inputSelection
    }
}

public enum ObservationContextLimits {
    public static let maximumFrames = 24
    public static let maximumExcerptCharacters = 320
    public static let maximumExcerptNonemptyLines = 6
    public static let maximumTotalTextCharacters = 9_000
    public static let maximumBatchFrames = 4
    public static let maximumPromptCharacters = 2_000
    public static let maximumCatalogEntries = 8
    public static let maximumCatalogCharacters = 480
    public static let maximumResponseCharacters = 12_000
}

struct ObservationContextBatch: Sendable {
    let frames: [ObservationFrameEvidence]
    let excerpts: [ObservationContextExcerpt]
    let prompt: String
}

struct ObservationContextPreparedInput: Sendable {
    let frames: [ObservationFrameEvidence]
    let catalog: [ObservationContextCatalogEntry]
    let batches: [ObservationContextBatch]
    let initialDecisions: [ObservationFrameIdentityDecision]
    let inputSelection: ObservationContextInputSelection
}

struct ObservationContextValidatedBatch: Sendable {
    let decisions: [ObservationFrameIdentityDecision]
    let diagnostics: [ObservationContextDiagnostic]
    let responseWasValid: Bool
}

/// Pure validation: exact citations constrain a model proposal; they do not prove that an
/// OCR line is a true app header. The identity namespace deliberately says visual-context.
enum ObservationContextValidation {
    static func prepare(frames: [ObservationFrameEvidence], catalog: [ObservationContextCatalogEntry]) throws -> ObservationContextPreparedInput {
        var ids = Set<UUID>()
        var previous = 0.0
        for frame in frames {
            guard ids.insert(frame.id).inserted,
                  frame.requestedTimeSeconds.isFinite, frame.requestedTimeSeconds >= 0,
                  frame.actualTimeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  frame.timeSeconds.isFinite, frame.timeSeconds >= previous else {
                throw ObservationContextClassificationError.invalidFrames
            }
            previous = frame.timeSeconds
        }
        let catalog = try validatedCatalog(catalog)
        var reasons: [UUID: String] = [:]
        var totalText = 0
        var batches: [ObservationContextBatch] = []
        var current: [ObservationFrameEvidence] = []
        var currentExcerpts: [ObservationContextExcerpt] = []
        var currentOrders: [Int] = []
        var selectedExcerpts: [ObservationContextExcerpt] = []
        func flush() throws {
            guard !current.isEmpty else { return }
            batches.append(.init(frames: current, excerpts: currentExcerpts,
                                 prompt: try prompt(frames: current, excerpts: currentExcerpts,
                                                    orders: currentOrders, catalog: catalog)))
            current = []; currentExcerpts = []; currentOrders = []
        }
        for (index, frame) in frames.enumerated() {
            let reason: String?
            if frame.outcome != .observed { reason = AppLanguage.localized("The source frame was blank or could not be extracted.", bundle: .module) }
            else if frame.textWasTruncated { reason = AppLanguage.localized("The source text was truncated; context remains unknown.", bundle: .module) }
            else if frame.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reason = AppLanguage.localized("No visible text was extracted.", bundle: .module) }
            else if index >= ObservationContextLimits.maximumFrames { reason = AppLanguage.localized("Excluded by the model frame limit.", bundle: .module) }
            else { reason = nil }
            if let reason { reasons[frame.id] = reason; continue }
            var excerpt = headerExcerpt(frame)
            guard !excerpt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                reasons[frame.id] = AppLanguage.localized("No complete header line fits the model excerpt limit.", bundle: .module)
                continue
            }
            guard totalText + excerpt.text.count <= ObservationContextLimits.maximumTotalTextCharacters else {
                reasons[frame.id] = AppLanguage.localized("Excluded by the total text limit.", bundle: .module)
                continue
            }
            var singlePrompt = try prompt(frames: [frame], excerpts: [excerpt], orders: [index], catalog: catalog)
            // Optional geometry must never displace a frame's text from the model budget.
            // Keep the exact selected IDs so a reviewer can reconstruct omitted hints.
            while singlePrompt.count > ObservationContextLimits.maximumPromptCharacters,
                  let ids = excerpt.ocrLineIDs, !ids.isEmpty {
                excerpt = excerpt.withOCRLineIDs(Array(ids.dropLast()))
                singlePrompt = try prompt(frames: [frame], excerpts: [excerpt], orders: [index], catalog: catalog)
            }
            guard singlePrompt.count <= ObservationContextLimits.maximumPromptCharacters else {
                reasons[frame.id] = AppLanguage.localized("Excluded by the encoded model-context limit.", bundle: .module)
                continue
            }
            let candidate = try prompt(frames: current + [frame], excerpts: currentExcerpts + [excerpt],
                                       orders: currentOrders + [index], catalog: catalog)
            if current.count >= ObservationContextLimits.maximumBatchFrames || candidate.count > ObservationContextLimits.maximumPromptCharacters {
                try flush()
            }
            current.append(frame); currentExcerpts.append(excerpt); currentOrders.append(index)
            selectedExcerpts.append(excerpt); totalText += excerpt.text.count
            reasons[frame.id] = AppLanguage.localized("The local model has not classified this frame.", bundle: .module)
        }
        try flush()
        let selection = ObservationContextInputSelection(policyIdentifier: "whole-line-source-prefix-layout-v2",
            maximumExcerptCharacters: ObservationContextLimits.maximumExcerptCharacters,
            maximumNonemptyLines: ObservationContextLimits.maximumExcerptNonemptyLines,
            excerpts: selectedExcerpts)
        return .init(frames: frames, catalog: catalog, batches: batches,
                     initialDecisions: frames.map { unknown($0, reason: reasons[$0.id] ?? AppLanguage.localized("Context remains unknown.", bundle: .module)) },
                     inputSelection: selection)
    }

    static func validate(json: String, batch: ObservationContextBatch,
                         catalog: [ObservationContextCatalogEntry]) -> ObservationContextValidatedBatch {
        guard json.count <= ObservationContextLimits.maximumResponseCharacters,
              let response = try? JSONDecoder().decode(ContextModelResponse.self, from: Data(json.utf8)),
              response.frames.count <= ObservationContextLimits.maximumBatchFrames * 2 else {
            return .init(decisions: batch.frames.map { unknown($0, reason: AppLanguage.localized("The model response could not be validated.", bundle: .module)) },
                         diagnostics: [.init(kind: .invalidResponse)], responseWasValid: false)
        }
        let knownIDs = Set(batch.frames.map(\.id))
        var proposals: [UUID: [ContextModelProposal]] = [:]
        var diagnostics: [ObservationContextDiagnostic] = []
        for proposal in response.frames {
            guard let id = UUID(uuidString: proposal.sampleID), knownIDs.contains(id) else {
                diagnostics.append(.init(kind: .unknownSampleID, sampleID: UUID(uuidString: proposal.sampleID)))
                continue
            }
            proposals[id, default: []].append(proposal)
        }
        let decisions = batch.frames.map { frame -> ObservationFrameIdentityDecision in
            guard let candidates = proposals[frame.id] else {
                return unknown(frame, reason: AppLanguage.localized("The local model omitted this frame.", bundle: .module))
            }
            guard candidates.count == 1, let proposal = candidates.first else {
                diagnostics.append(.init(kind: .duplicateSampleID, sampleID: frame.id))
                return unknown(frame, reason: AppLanguage.localized("Conflicting or duplicate proposals were rejected.", bundle: .module))
            }
            if proposal.outcome == "unknown", proposal.contextLabel.isEmpty, proposal.evidenceQuote.isEmpty {
                return unknown(frame, reason: AppLanguage.localized("The local model abstained.", bundle: .module))
            }
            let quote = proposal.evidenceQuote
            guard let excerpt = batch.excerpts.first(where: { $0.sampleID == frame.id }),
                  !quote.isEmpty, quote.count <= 240,
                  Data(excerpt.text.utf8).range(of: Data(quote.utf8)) != nil,
                  Data(frame.text.utf8).range(of: Data(quote.utf8)) != nil,
                  frame.outcome == .observed, !frame.textWasTruncated else {
                diagnostics.append(.init(kind: .invalidEvidence, sampleID: frame.id))
                return unknown(frame, reason: AppLanguage.localized("The proposed quote was not grounded in this frame.", bundle: .module))
            }
            if proposal.outcome == "ambiguous", proposal.contextLabel.isEmpty {
                return .init(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                             evidence: .ambiguous(reference: frame.evidenceReference), evidenceQuote: quote,
                             reason: AppLanguage.localized("The local model reported ambiguous visible context.", bundle: .module))
            }
            guard proposal.outcome == "identified", let identity = identity(for: proposal, excerpt: excerpt.text, catalog: catalog) else {
                diagnostics.append(.init(kind: .unsupportedIdentity, sampleID: frame.id))
                return unknown(frame, reason: AppLanguage.localized("The proposed visual identity was unsupported.", bundle: .module))
            }
            return .init(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                         evidence: .identified(app: identity, reference: frame.evidenceReference),
                         evidenceQuote: quote, reason: AppLanguage.localized("Model-proposed visual header; not an OS-verified app identity.", bundle: .module))
        }
        return .init(decisions: decisions, diagnostics: diagnostics, responseWasValid: true)
    }

    static func unknown(_ frame: ObservationFrameEvidence, reason: String) -> ObservationFrameIdentityDecision {
        .init(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
              evidence: .unknown, evidenceQuote: nil, reason: reason)
    }

    private static func identity(for proposal: ContextModelProposal, excerpt: String,
                                 catalog: [ObservationContextCatalogEntry]) -> ObservationAppIdentity? {
        let headers = headerLines(excerpt)
        let label: String
        if catalog.isEmpty {
            guard isSafeLabel(proposal.contextLabel), proposal.contextLabel == proposal.evidenceQuote,
                  headers.contains(proposal.evidenceQuote) else { return nil }
            label = proposal.contextLabel
        } else {
            let comparableHeaders = headers.map(removingLeadingDecoration)
            let visibleCatalog = catalog.filter { comparableHeaders.contains($0.headerText) }
            // A second catalog name is still a competing mention when OCR corrupts its
            // icon into a letter. A mention can block identity, never establish it.
            let mentionedCatalog = catalog.filter { entry in headers.contains { $0.contains(entry.headerText) } }
            guard visibleCatalog.count == 1, mentionedCatalog.count == 1, let entry = visibleCatalog.first,
                  proposal.contextLabel == entry.label, headers.contains(proposal.evidenceQuote),
                  removingLeadingDecoration(proposal.evidenceQuote) == entry.headerText else { return nil }
            label = entry.label
        }
        // Generic casing/diacritics may vary between OCR frames. Canonicalize the
        // display name with the key so one trace cannot contain conflicting names.
        let canonical = normalized(label)
        return .init(key: "visual-context:\(canonical)", displayName: catalog.isEmpty ? canonical : label)
    }

    /// Select a contiguous prefix without rewriting whitespace, newline sequences or OCR.
    /// An overlong line stops selection; later lines cannot jump ahead of unknown content.
    private static func headerExcerpt(_ frame: ObservationFrameEvidence) -> ObservationContextExcerpt {
        let text = frame.text
        var cursor = text.startIndex
        var selectedEnd = text.startIndex
        var nonemptyLines = 0
        while cursor < text.endIndex {
            let lineStart = cursor
            while cursor < text.endIndex, !text[cursor].isNewline { cursor = text.index(after: cursor) }
            let lineEnd = cursor
            let afterNewline = cursor < text.endIndex ? text.index(after: cursor) : cursor
            guard text.distance(from: text.startIndex, to: lineEnd) <= ObservationContextLimits.maximumExcerptCharacters else { break }
            selectedEnd = lineEnd
            let includesNewline = text.distance(from: text.startIndex, to: afterNewline) <= ObservationContextLimits.maximumExcerptCharacters
            if includesNewline { selectedEnd = afterNewline }
            if !text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces).isEmpty { nonemptyLines += 1 }
            if nonemptyLines >= ObservationContextLimits.maximumExcerptNonemptyLines || !includesNewline { break }
            cursor = afterNewline
        }
        let excerpt = String(text[..<selectedEnd])
        let lineIDs = frame.ocrLines.map { lines in
            Array(lines.filter { $0.endCharacterOffset <= excerpt.count }
                .prefix(ObservationContextLimits.maximumExcerptNonemptyLines).map(\.id))
        }
        return .init(sampleID: frame.id, sourceCharacterCount: text.count, startCharacterOffset: 0,
                     endCharacterOffset: excerpt.count, text: excerpt, wasExcerpted: selectedEnd != text.endIndex,
                     ocrLineIDs: lineIDs)
    }

    /// These remain lexical lines; neither geometry nor an OS app identity is available.
    private static func headerLines(_ excerpt: String) -> [String] {
        excerpt.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Do not repair alphabetic OCR noise (for example J/y), internal text or suffixes.
    private static func removingLeadingDecoration(_ line: String) -> String {
        let decorations = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces)
        return String(String.UnicodeScalarView(line.unicodeScalars.drop(while: { decorations.contains($0) })))
    }

    private static func validatedCatalog(_ entries: [ObservationContextCatalogEntry]) throws -> [ObservationContextCatalogEntry] {
        guard entries.count <= ObservationContextLimits.maximumCatalogEntries,
              entries.reduce(0, { $0 + $1.label.count + $1.headerText.count }) <= ObservationContextLimits.maximumCatalogCharacters else {
            throw ObservationContextClassificationError.invalidCatalog
        }
        var labels = Set<String>(); var headers = Set<String>()
        for entry in entries {
            guard isSafeLabel(entry.label), isSafeLabel(entry.headerText),
                  labels.insert(normalized(entry.label)).inserted,
                  headers.insert(normalized(entry.headerText)).inserted else {
                throw ObservationContextClassificationError.invalidCatalog
            }
        }
        return entries
    }

    private static func isSafeLabel(_ label: String) -> Bool {
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: " -_&'’"))
        return (2...80).contains(label.count) && label == label.trimmingCharacters(in: .whitespacesAndNewlines) &&
            label.unicodeScalars.contains(where: CharacterSet.letters.contains) &&
            label.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private struct InputFrame: Encodable {
        let sampleID: String
        let order: Int
        let timeSeconds: Double
        let timeBasis: String
        let text: String
        let layout: [InputLine]?
    }
    private struct InputLine: Encodable {
        let range: [Int]
        let box: [Double]
        let confidence: Double
    }
    private struct Input: Encodable {
        let catalog: [ObservationContextCatalogEntry]
        let frames: [InputFrame]
    }
    private static func prompt(frames: [ObservationFrameEvidence], excerpts: [ObservationContextExcerpt],
                               orders: [Int], catalog: [ObservationContextCatalogEntry]) throws -> String {
        let input = Input(catalog: catalog, frames: zip(zip(frames, orders), excerpts).map { item, excerpt in
            let (frame, order) = item
            let lines = excerpt.ocrLineIDs.map { ids in
                ids.compactMap { id in frame.ocrLines?.first { $0.id == id } }.map { line in
                    InputLine(range: [line.startCharacterOffset, line.endCharacterOffset],
                              box: [line.bounds.x, line.bounds.y, line.bounds.width, line.bounds.height].map(roundedHint),
                              confidence: roundedHint(line.confidence))
                }
            }
            return .init(sampleID: frame.id.uuidString, order: order, timeSeconds: frame.timeSeconds,
                         timeBasis: frame.timeBasis.rawValue, text: excerpt.text, layout: lines)
        })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(input), as: UTF8.self)
    }

    /// Compact descriptive hints only. Exact Vision values stay in source evidence.
    private static func roundedHint(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}

private struct ContextModelResponse: Decodable {
    let frames: [ContextModelProposal]
    init(from decoder: any Decoder) throws {
        try requireOnlyKeys(["frames"], from: decoder)
        let values = try decoder.container(keyedBy: Keys.self)
        frames = try values.decode([ContextModelProposal].self, forKey: .frames)
    }
    private enum Keys: String, CodingKey { case frames }
}

private struct ContextModelProposal: Decodable {
    let sampleID: String
    let outcome: String
    let contextLabel: String
    let evidenceQuote: String
    init(from decoder: any Decoder) throws {
        try requireOnlyKeys(["sampleID", "outcome", "contextLabel", "evidenceQuote"], from: decoder)
        let values = try decoder.container(keyedBy: Keys.self)
        sampleID = try values.decode(String.self, forKey: .sampleID)
        outcome = try values.decode(String.self, forKey: .outcome)
        contextLabel = try values.decode(String.self, forKey: .contextLabel)
        evidenceQuote = try values.decode(String.self, forKey: .evidenceQuote)
    }
    private enum Keys: String, CodingKey { case sampleID, outcome, contextLabel, evidenceQuote }
}

private struct ContextResponseKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireOnlyKeys(_ expected: Set<String>, from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: ContextResponseKey.self)
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                               debugDescription: AppLanguage.localized("Unexpected visible-context response fields.", bundle: .module)))
    }
}
