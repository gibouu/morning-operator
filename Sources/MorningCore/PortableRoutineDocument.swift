import Foundation

public enum RoutineExportDetail: String, Codable, Sendable {
    case planOnly, includeDetails
}

public enum PortableRoutineDocumentError: Error, LocalizedError, Sendable, Equatable {
    case invalidFormat, unsupportedVersion(Int), unexpectedFields
    case invalidRoutine, invalidDocument, documentTooLarge, invalidLocalVersion

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: "Choose a supported portable routine document. Workspace snapshots and older raw routine files cannot be imported here."
        case .unsupportedVersion: "This routine document uses an unsupported version. The current routine is unchanged."
        case .unexpectedFields: "This routine document contains unsupported fields. No actions or settings were imported."
        case .invalidRoutine: "A portable routine needs 1–10 moments with unique identities, valid names and 1–120 planned minutes each. Its text and metadata must fit the supported limits."
        case .invalidDocument: "This routine document could not be read. The current routine is unchanged."
        case .documentTooLarge: "This routine document exceeds the 1 MiB limit."
        case .invalidLocalVersion: "The current routine version cannot be safely updated. No routine was replaced."
        }
    }
}

/// A portable plan contains no executable operation. Notes are absent by default;
/// titles remain visible personal text and are not automatically de-identified.
public struct PortableRoutineStep: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let kind: StepKind
    public let durationMinutes: Int
    public let isRequired: Bool
    public let detail: String?

    fileprivate init(_ step: RoutineStep, detail: RoutineExportDetail) {
        id = step.id
        title = step.title
        kind = step.kind
        durationMinutes = step.durationMinutes
        isRequired = step.isRequired
        self.detail = detail == .includeDetails ? step.detail : nil
    }

    fileprivate func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= PortableRoutineDocument.maximumTitleCharacters,
              (1...120).contains(durationMinutes),
              detail.map({ $0.count <= PortableRoutineDocument.maximumDetailCharacters }) ?? true else {
            throw PortableRoutineDocumentError.invalidRoutine
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, kind, durationMinutes, isRequired, detail
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownPortableKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        kind = try values.decode(StepKind.self, forKey: .kind)
        durationMinutes = try values.decode(Int.self, forKey: .durationMinutes)
        isRequired = try values.decode(Bool.self, forKey: .isRequired)
        detail = try values.decodeIfPresent(String.self, forKey: .detail)
        try validate()
    }
}

/// Version 1 stores sourceCreatedAt as Unix seconds, independent of the enclosing
/// encoder's date strategy. Exported approval is descriptive metadata only.
/// Import creates a new local draft; it never restores authority to run an action.
public struct PortableRoutineDocument: Codable, Sendable, Equatable {
    public static let formatIdentifier = "morning-operator.routine"
    public static let currentVersion = 1
    public static let maximumEncodedBytes = 1_048_576
    public static let maximumSteps = 10
    public static let maximumTitleCharacters = 2_000
    public static let maximumDetailCharacters = 32_000
    public static let maximumSourceLabelCharacters = 256

    public let format: String
    public let formatVersion: Int
    public let detail: RoutineExportDetail
    public let sourceRoutineID: UUID
    public let sourceRoutineVersion: Int
    public let sourceCreatedAt: Date
    public let approvalAtExport: Bool
    /// Declared sample provenance. False does not establish observed human behavior.
    public let sourceIsSynthetic: Bool
    public let sourceLabel: String?
    public let steps: [PortableRoutineStep]

    public init(routine: RoutineVersion, detail: RoutineExportDetail = .planOnly) throws {
        // Validate the source rather than clamping a duration, dropping an invalid
        // row or silently accepting an invalid field only because it is omitted.
        guard (1...Self.maximumSteps).contains(routine.steps.count),
              routine.sourceLabel.count <= Self.maximumSourceLabelCharacters,
              routine.steps.allSatisfy({ $0.detail.count <= Self.maximumDetailCharacters }) else {
            throw PortableRoutineDocumentError.invalidRoutine
        }
        format = Self.formatIdentifier
        formatVersion = Self.currentVersion
        self.detail = detail
        sourceRoutineID = routine.id
        sourceRoutineVersion = routine.number
        sourceCreatedAt = routine.createdAt
        approvalAtExport = routine.isApproved
        sourceIsSynthetic = routine.isSynthetic
        sourceLabel = detail == .includeDetails ? routine.sourceLabel : nil
        steps = routine.steps.map { PortableRoutineStep($0, detail: detail) }
        try validate()
        _ = try encoded()
    }

    /// Call this bounded decoder for selected external data. It rejects raw legacy
    /// RoutineVersion files, unknown fields and operation payloads at either level.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumEncodedBytes else { throw PortableRoutineDocumentError.documentTooLarge }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch let error as PortableRoutineDocumentError { throw error }
        catch { throw PortableRoutineDocumentError.invalidDocument }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else { throw PortableRoutineDocumentError.documentTooLarge }
        return data
    }

    /// Source identifiers and version remain in this document for the review UI.
    /// The installed draft has a fresh local identity and advances only the local
    /// version, with the original step identities/order and manual operations.
    public func importedDraft(replacing current: RoutineVersion?, at date: Date = Date()) throws -> RoutineVersion {
        try validate()
        _ = try encoded()
        guard date.timeIntervalSince1970.isFinite else { throw PortableRoutineDocumentError.invalidDocument }
        let localNumber = current?.number ?? 0
        guard localNumber >= 0, localNumber < Int.max,
              current == nil || localNumber >= 1 else { throw PortableRoutineDocumentError.invalidLocalVersion }
        return RoutineVersion(number: localNumber + 1, createdAt: date,
            sourceLabel: sourceIsSynthetic ? "Demo fixture — imported synthetic plan" : "Imported routine — review before approval",
            steps: steps.map {
                RoutineStep(id: $0.id, title: $0.title, detail: $0.detail ?? "", kind: $0.kind,
                    durationMinutes: $0.durationMinutes, isRequired: $0.isRequired, automation: nil)
            }, isApproved: false)
    }

    private func validate() throws {
        guard format == Self.formatIdentifier else { throw PortableRoutineDocumentError.invalidFormat }
        guard formatVersion == Self.currentVersion else { throw PortableRoutineDocumentError.unsupportedVersion(formatVersion) }
        guard sourceRoutineVersion >= 1, sourceRoutineVersion < Int.max,
              sourceCreatedAt.timeIntervalSince1970.isFinite,
              (1...Self.maximumSteps).contains(steps.count),
              Set(steps.map(\.id)).count == steps.count,
              sourceLabel.map({ $0.count <= Self.maximumSourceLabelCharacters }) ?? true else {
            throw PortableRoutineDocumentError.invalidRoutine
        }
        switch detail {
        case .planOnly:
            guard sourceLabel == nil, steps.allSatisfy({ $0.detail == nil }) else {
                throw PortableRoutineDocumentError.invalidDocument
            }
        case .includeDetails:
            guard sourceLabel != nil, steps.allSatisfy({ $0.detail != nil }) else {
                throw PortableRoutineDocumentError.invalidDocument
            }
        }
        for step in steps { try step.validate() }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, formatVersion, detail, sourceRoutineID, sourceRoutineVersion
        case sourceCreatedAt, approvalAtExport, sourceIsSynthetic, sourceLabel, steps
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownPortableKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(String.self, forKey: .format)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        detail = try values.decode(RoutineExportDetail.self, forKey: .detail)
        sourceRoutineID = try values.decode(UUID.self, forKey: .sourceRoutineID)
        sourceRoutineVersion = try values.decode(Int.self, forKey: .sourceRoutineVersion)
        let unixSeconds = try values.decode(Double.self, forKey: .sourceCreatedAt)
        guard unixSeconds.isFinite else { throw PortableRoutineDocumentError.invalidDocument }
        sourceCreatedAt = Date(timeIntervalSince1970: unixSeconds)
        approvalAtExport = try values.decode(Bool.self, forKey: .approvalAtExport)
        sourceIsSynthetic = try values.decode(Bool.self, forKey: .sourceIsSynthetic)
        sourceLabel = try values.decodeIfPresent(String.self, forKey: .sourceLabel)
        steps = try values.decode([PortableRoutineStep].self, forKey: .steps)
        try validate()
        _ = try encoded()
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(format, forKey: .format)
        try values.encode(formatVersion, forKey: .formatVersion)
        try values.encode(detail, forKey: .detail)
        try values.encode(sourceRoutineID, forKey: .sourceRoutineID)
        try values.encode(sourceRoutineVersion, forKey: .sourceRoutineVersion)
        try values.encode(sourceCreatedAt.timeIntervalSince1970, forKey: .sourceCreatedAt)
        try values.encode(approvalAtExport, forKey: .approvalAtExport)
        try values.encode(sourceIsSynthetic, forKey: .sourceIsSynthetic)
        try values.encodeIfPresent(sourceLabel, forKey: .sourceLabel)
        try values.encode(steps, forKey: .steps)
    }
}

private struct PortableJSONKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func rejectUnknownPortableKeys(_ decoder: any Decoder, allowed: Set<String>) throws {
    let keys = try decoder.container(keyedBy: PortableJSONKey.self).allKeys.map(\.stringValue)
    guard Set(keys).isSubset(of: allowed) else { throw PortableRoutineDocumentError.unexpectedFields }
}
