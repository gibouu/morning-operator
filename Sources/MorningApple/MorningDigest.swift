import Foundation

// Version 1 of the "Actual output" shape in Benchmarks/morning-digest-contract.md.
// These types and the validator are the checking half only. No model adapter exists
// here: nothing in this file performs inference, reads an inbox or speaks.

public enum MorningDigestStatus: String, Codable, Sendable {
    case completed, skipped, blocked, failed
}

public enum MorningDigestProducer: String, Codable, Sendable {
    case nativeModel = "native-model"
    case handAuthored = "hand-authored"
    case unavailable
}

public enum MorningDigestSourceStatus: String, Codable, Sendable {
    case available, unknown, unavailable
}

public struct MorningDigestSourceState: Codable, Equatable, Sendable {
    public let sourceID: String
    public let status: MorningDigestSourceStatus
    public init(sourceID: String, status: MorningDigestSourceStatus) {
        self.sourceID = sourceID; self.status = status
    }
}

public struct MorningDigestCitation: Codable, Equatable, Sendable {
    public let sourceID: String
    /// The prepared unit that holds the quote, see `MorningDigestPreparation.evidenceID(for:)`.
    public let evidenceID: String
    public let quote: String
    public init(sourceID: String, evidenceID: String, quote: String) {
        self.sourceID = sourceID; self.evidenceID = evidenceID; self.quote = quote
    }
}

public struct MorningDigestClaim: Codable, Equatable, Sendable {
    public let sourceID: String
    public let sourceRevision: String
    public let field: String
    public let value: String
    public let evidence: [MorningDigestCitation]
    public init(sourceID: String, sourceRevision: String, field: String, value: String,
                evidence: [MorningDigestCitation]) {
        self.sourceID = sourceID; self.sourceRevision = sourceRevision
        self.field = field; self.value = value; self.evidence = evidence
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try values.decode(String.self, forKey: .sourceID)
        sourceRevision = try values.decode(String.self, forKey: .sourceRevision)
        field = try values.decode(String.self, forKey: .field)
        value = try values.decode(String.self, forKey: .value)
        // The scorer reads a claim without evidence as unsupported, not as malformed.
        evidence = try values.decodeIfPresent([MorningDigestCitation].self, forKey: .evidence) ?? []
    }
}

/// The artifact handed to the independent scorer. Only `MorningDigestPreparation` builds
/// one in memory. Decoding checks the shape alone: a decoded file has not been validated
/// against any evidence and is not proof that a model produced it.
public struct MorningDigest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    public let status: MorningDigestStatus
    public let producer: MorningDigestProducer
    public let sourceStates: [MorningDigestSourceState]
    public let claims: [MorningDigestClaim]
    /// Absent, never empty, when nothing validated: the scorer rejects an empty string.
    public let spokenText: String?

    fileprivate init(runID: String, status: MorningDigestStatus, producer: MorningDigestProducer,
                     sourceStates: [MorningDigestSourceState], claims: [MorningDigestClaim] = [],
                     spokenText: String? = nil) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID; self.status = status; self.producer = producer
        self.sourceStates = sourceStates; self.claims = claims; self.spokenText = spokenText
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        runID = try values.decode(String.self, forKey: .runID)
        status = try values.decode(MorningDigestStatus.self, forKey: .status)
        producer = try values.decode(MorningDigestProducer.self, forKey: .producer)
        sourceStates = try values.decodeIfPresent([MorningDigestSourceState].self, forKey: .sourceStates) ?? []
        claims = try values.decodeIfPresent([MorningDigestClaim].self, forKey: .claims) ?? []
        spokenText = try values.decodeIfPresent(String.self, forKey: .spokenText)
        guard schemaVersion == Self.currentSchemaVersion, MorningDigestPreparation.isValidRunID(runID),
              status == .completed || claims.isEmpty,
              spokenText.map({ !MorningDigestPreparation.isBlank($0) }) ?? true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Not a version 1 morning digest."))
        }
    }
}

public enum MorningDigestRejectionReason: String, Equatable, Sendable {
    case malformedClaim, unknownSource, unavailableSource, staleRevision
    case missingEvidence, invalidEvidence, duplicate
}

/// Why one generated claim was left out. Carries no source text.
public struct MorningDigestRejection: Equatable, Sendable {
    public let claimIndex: Int
    public let reason: MorningDigestRejectionReason
}

/// `digest` holds only claims that passed. It is therefore the checked product output,
/// not the generator's raw output: report `rejections` beside any score of it.
public struct MorningDigestOutcome: Equatable, Sendable {
    public let digest: MorningDigest
    public let rejections: [MorningDigestRejection]
}

public enum MorningDigestError: Error, Sendable, Equatable {
    case invalidRunID, invalidSourceStates
}

/// Produces candidate claims from prepared evidence. The evidence is the whole input:
/// controller truth, seeds and expected values must never reach an implementation.
public protocol MorningDigestGenerating: Sendable {
    /// `.handAuthored` for fixtures. `.nativeModel` only for real on-device inference.
    var producer: MorningDigestProducer { get }
    func claims(from evidence: PreparedLearningEvidence) async throws -> [MorningDigestClaim]
}

public enum MorningDigestPreparation {
    // The scorer's own input limits.
    public static let maximumClaims = 4_096
    public static let maximumCitationsPerClaim = 64
    public static let maximumSpokenCharacters = 65_536
    public static let maximumSourceStates = 512
    public static let maximumArtifactBytes = 10 * 1_024 * 1_024
    private static let maximumIdentifierCharacters = 256
    private static let maximumFieldCharacters = 64

    public static func sourceID(for snapshot: LearningSourceSnapshot) -> String { snapshot.acquisitionID.uuidString }
    public static func evidenceID(for unit: PreparedLearningEvidenceUnit) -> String { unit.id.uuidString }

    /// Never invents a digest. Without a generator the output is blocked; a generator that
    /// throws or exceeds the bounds gives a failed output. Both carry no claims and no speech.
    /// `undeterminedSources` names sources that could not be prepared, such as an inbox that
    /// was not readable. A source counts as available only when it is in `evidence` and is
    /// not listed there as unknown or unavailable.
    public static func prepare(runID: String, evidence: PreparedLearningEvidence,
                               undeterminedSources: [MorningDigestSourceState] = [],
                               generator: (any MorningDigestGenerating)?) async throws -> MorningDigestOutcome {
        guard isValidRunID(runID) else { throw MorningDigestError.invalidRunID }
        let states = sourceStates(evidence: evidence, undetermined: undeterminedSources)
        guard undeterminedSources.allSatisfy({ isIdentifier($0.sourceID) }), states.count <= maximumSourceStates else {
            throw MorningDigestError.invalidSourceStates
        }
        guard let generator, generator.producer != .unavailable else {
            return .init(digest: .init(runID: runID, status: .blocked, producer: .unavailable, sourceStates: states),
                         rejections: [])
        }
        let failed = MorningDigestOutcome(
            digest: .init(runID: runID, status: .failed, producer: generator.producer, sourceStates: states),
            rejections: [])
        let claims: [MorningDigestClaim]
        do {
            claims = try await generator.claims(from: evidence)
        } catch {
            try Task.checkCancellation()
            return failed
        }
        // A provider that ignores cancellation cannot deliver a late digest.
        try Task.checkCancellation()
        guard claims.count <= maximumClaims else { return failed }
        let checked = validate(claims, evidence: evidence, states: states)
        let spoken = spokenText(for: checked.accepted)
        let digest = MorningDigest(runID: runID, status: .completed, producer: generator.producer,
                                   sourceStates: states, claims: checked.accepted, spokenText: spoken)
        // Repeated long citations can pass one by one and still outgrow what the scorer reads.
        guard (spoken?.unicodeScalars.count ?? 0) <= maximumSpokenCharacters,
              let size = try? JSONEncoder().encode(digest).count, size <= maximumArtifactBytes else { return failed }
        return .init(digest: digest, rejections: checked.rejections)
    }

    /// Provenance only. A claim that passes quotes its value from the unit it names, at the
    /// current revision of an available source. Whether the field label is the right reading
    /// of that text is not established here; that is what the held-out scoring is for.
    static func validate(_ claims: [MorningDigestClaim], evidence: PreparedLearningEvidence,
                         states: [MorningDigestSourceState])
        -> (accepted: [MorningDigestClaim], rejections: [MorningDigestRejection]) {
        var accepted: [MorningDigestClaim] = []
        var rejections: [MorningDigestRejection] = []
        for (index, claim) in claims.enumerated() {
            if let reason = rejection(of: claim, evidence: evidence, states: states, accepted: accepted) {
                rejections.append(.init(claimIndex: index, reason: reason))
            } else {
                accepted.append(claim)
            }
        }
        return (accepted, rejections)
    }

    /// Field and value exactly as validated, one claim per line. No connecting prose is
    /// added, so nothing can be spoken that was not checked. This is not natural narration.
    static func spokenText(for claims: [MorningDigestClaim]) -> String? {
        claims.isEmpty ? nil : claims.map { "\($0.field): \($0.value)" }.joined(separator: "\n")
    }

    static func isValidRunID(_ runID: String) -> Bool {
        isIdentifier(runID)
    }

    private static func sourceStates(evidence: PreparedLearningEvidence,
                                     undetermined: [MorningDigestSourceState]) -> [MorningDigestSourceState] {
        var states: [MorningDigestSourceState] = []
        for declared in undetermined where !states.contains(where: { same($0.sourceID, declared.sourceID) }) {
            // Nothing is available without prepared evidence, whatever the caller declares.
            states.append(.init(sourceID: declared.sourceID, status: declared.status == .available ? .unknown : declared.status))
        }
        let prepared = evidence.sourceSnapshots.map(sourceID(for:))
            .filter { id in !states.contains(where: { same($0.sourceID, id) }) }
            .map { MorningDigestSourceState(sourceID: $0, status: .available) }
        return prepared + states
    }

    private static func rejection(of claim: MorningDigestClaim, evidence: PreparedLearningEvidence,
                                  states: [MorningDigestSourceState],
                                  accepted: [MorningDigestClaim]) -> MorningDigestRejectionReason? {
        guard isIdentifier(claim.sourceID), isIdentifier(claim.sourceRevision), isFieldName(claim.field),
              !isBlank(claim.value),
              claim.evidence.count <= maximumCitationsPerClaim else { return .malformedClaim }
        guard let state = states.first(where: { same($0.sourceID, claim.sourceID) }), state.status != .unknown else {
            return .unknownSource
        }
        guard state.status == .available,
              let snapshot = evidence.sourceSnapshots.first(where: { same(sourceID(for: $0), claim.sourceID) }) else {
            return .unavailableSource
        }
        guard same(snapshot.sourceRevision, claim.sourceRevision) else { return .staleRevision }
        guard !claim.evidence.isEmpty else { return .missingEvidence }
        // Every citation must hold. A good one does not excuse a bad one beside it.
        for citation in claim.evidence {
            guard same(citation.sourceID, claim.sourceID),
                  let unit = evidence.units.first(where: { same(evidenceID(for: $0), citation.evidenceID) }),
                  unit.acquisitionID == snapshot.acquisitionID,
                  contains(citation.quote, in: unit.text), contains(claim.value, in: citation.quote) else {
                return .invalidEvidence
            }
        }
        // Among accepted claims only, so a properly cited retry is not lost to a bad first try.
        let repeated = accepted.contains {
            same($0.sourceID, claim.sourceID) && same($0.field, claim.field) && same($0.value, claim.value)
        }
        return repeated ? .duplicate : nil
    }

    /// The exact-quote rule of the routine proposal citations (`EvidenceText.exactRange`,
    /// private to that file): identical UTF-8 bytes that start and end on Character
    /// boundaries. Swift's `==` and `contains` treat composed and decomposed text as equal,
    /// which would let a look-alike through, so the comparison is on bytes.
    private static func contains(_ quote: String, in source: String) -> Bool {
        let needle = quote.utf8
        guard !needle.isEmpty else { return false }
        var start = source.startIndex
        while start < source.endIndex {
            if source[start...].utf8.starts(with: needle) {
                var end = start
                var remaining = needle.count
                while remaining > 0, end < source.endIndex {
                    remaining -= source[end].utf8.count
                    end = source.index(after: end)
                }
                if remaining == 0 { return true }
            }
            start = source.index(after: start)
        }
        return false
    }

    /// Blank as the scorer's `str.strip()` sees it, which also strips U+001C to U+001F.
    static func isBlank(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { $0.properties.isWhitespace || (0x1C...0x1F).contains($0.value) }
    }

    private static func same(_ first: String, _ second: String) -> Bool {
        first.utf8.elementsEqual(second.utf8)
    }

    private static func isIdentifier(_ value: String) -> Bool {
        // The scorer counts code points, not Characters.
        value.unicodeScalars.count <= maximumIdentifierCharacters
            && !isBlank(value)
    }

    /// The scorer's field-name rule for controller truth: an ASCII letter, then letters, digits or `_`.
    private static func isFieldName(_ value: String) -> Bool {
        guard let first = value.utf8.first, value.utf8.count <= maximumFieldCharacters else { return false }
        func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
        return isLetter(first) && value.utf8.allSatisfy { isLetter($0) || (48...57).contains($0) || $0 == 95 }
    }
}
