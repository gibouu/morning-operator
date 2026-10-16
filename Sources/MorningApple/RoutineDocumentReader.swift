import Foundation
import MorningCore

/// Reads only the explicitly selected file. It neither retains a raw copy nor
/// changes a workspace; installation remains a separate, reviewed operation.
public struct RoutineDocumentReader: Sendable {
    public init() {}

    public func read(_ url: URL) async throws -> PortableRoutineDocument {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Self.readCoordinated(url)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func readCoordinated(_ url: URL) throws -> PortableRoutineDocument {
        try Task.checkCancellation()
        guard url.isFileURL else { throw RoutineDocumentReadError.notAFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<PortableRoutineDocument, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { selectedURL in
            result = Result { try readBounded(selectedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw RoutineDocumentReadError.unreadable }
        return try result.get()
    }

    private static func readBounded(_ url: URL) throws -> PortableRoutineDocument {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw RoutineDocumentReadError.notAFile }
        let limit = PortableRoutineDocument.maximumEncodedBytes
        if let size = values.fileSize, size > limit { throw RoutineDocumentReadError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        // Bound the actual bytes, not just the pre-read file size. The extra byte
        // detects a file that grew or reports an inaccurate provider size.
        while data.count <= limit {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)),
                  !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= limit else { throw RoutineDocumentReadError.tooLarge }
        try Task.checkCancellation()
        return try PortableRoutineDocument.decode(data)
    }
}

public enum RoutineDocumentReadError: LocalizedError, Sendable {
    case notAFile, tooLarge, unreadable
    public var errorDescription: String? {
        switch self {
        case .notAFile: AppLanguage.localized("Choose a saved routine file.", bundle: .module)
        case .tooLarge: AppLanguage.localized("This routine file is too large. The limit is 1 MB.", bundle: .module)
        case .unreadable: AppLanguage.localized("This routine file could not be opened. Your current routine is unchanged.", bundle: .module)
        }
    }
}
