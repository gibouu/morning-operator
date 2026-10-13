import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum PersistenceError: Error, LocalizedError, Sendable, Equatable {
    case fileURLRequired
    case unsupportedSchema(Int)
    public var errorDescription: String? {
        switch self {
        case .fileURLRequired: String(localized: "Choose a local file for this workspace.", bundle: .module)
        case .unsupportedSchema(let version): String(localized: "This file uses an unsupported schema version (\(version)).", bundle: .module)
        }
    }
}

private struct JSONEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let value: Value
}

/// Small local documents, atomically replaced after complete encoding.
/// A thrown save leaves the destination unchanged. All staging work finishes
/// before the rename commits; no throwing operation follows that boundary.
/// Use one authoritative writer; this does not coordinate multiple processes.
/// Store secrets in Keychain, never in these exported documents.
public struct AtomicJSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> Value {
        guard url.isFileURL else { throw PersistenceError.fileURLRequired }
        let data = try Data(contentsOf: url)
        // Read the schema independently so a future envelope is rejected before decoding its payload.
        let header = try JSONDecoder().decode(SchemaHeader.self, from: data)
        guard header.schemaVersion == 1 else { throw PersistenceError.unsupportedSchema(header.schemaVersion) }
        return try JSONDecoder().decode(JSONEnvelope<Value>.self, from: data).value
    }

    public func save(_ value: Value) throws {
        guard url.isFileURL else { throw PersistenceError.fileURLRequired }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(JSONEnvelope(schemaVersion: 1, value: value))
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // mkstemp exclusively creates a sibling file with owner-only permissions.
        // A same-directory rename replaces an existing file atomically.
        var template = directory.appendingPathComponent(".morning-save-XXXXXX").path.utf8CString
        let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard descriptor >= 0 else { throw currentPOSIXError() }
        let stagedPath = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let stagedURL = URL(fileURLWithPath: stagedPath)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var closed = false
        var committed = false
        defer {
            if !closed { try? handle.close() }
            if !committed { try? FileManager.default.removeItem(at: stagedURL) }
        }
        // Establish the exact final mode before any content or commit, independent
        // of the process umask. Failure cannot affect the old destination.
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw currentPOSIXError() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        closed = true
        let result = stagedURL.path.withCString { stagedPath in
            url.path.withCString { destinationPath in rename(stagedPath, destinationPath) }
        }
        guard result == 0 else { throw currentPOSIXError() }
        committed = true
    }
}

private func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}

private struct SchemaHeader: Decodable { let schemaVersion: Int }

public actor RoutineRepository {
    private let file: AtomicJSONFile<RoutineVersion>
    public init(fileURL: URL) { file = AtomicJSONFile(url: fileURL) }
    public func load() throws -> RoutineVersion { try file.load() }
    public func save(_ routine: RoutineVersion) throws { try file.save(routine) }
    public func export(_ routine: RoutineVersion, to fileURL: URL) throws {
        try AtomicJSONFile<RoutineVersion>(url: fileURL).save(routine)
    }
}
