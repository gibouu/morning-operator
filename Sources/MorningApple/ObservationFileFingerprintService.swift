import CryptoKit
import Darwin
import Foundation
import MorningCore

public enum ObservationFileFingerprintError: Error, LocalizedError, Sendable, Equatable {
    case localRegularFileRequired, unreadableFile, fileTooLarge, fileChanged

    public var errorDescription: String? {
        switch self {
        case .localRegularFileRequired: AppLanguage.localized("Choose a local regular file to identify.", bundle: .module)
        case .unreadableFile: AppLanguage.localized("This local file could not be read.", bundle: .module)
        case .fileTooLarge: AppLanguage.localized("This file exceeds the prototype's local fingerprint size limit.", bundle: .module)
        case .fileChanged: AppLanguage.localized("This file changed while it was being identified. Try again after it finishes saving.", bundle: .module)
        }
    }
}

/// Reads explicitly supplied local bytes on this actor, bounded to one chunk at a time.
/// Nothing is uploaded, logged, or inferred from a filename. A successful fingerprint
/// describes these bytes; callers must keep the same finalized file stable during OCR.
public actor ObservationFileFingerprintService {
    public typealias ProgressHandler = @Sendable (Int64) async -> Void
    public static let maximumFileBytes: Int64 = 512 * 1_024 * 1_024
    private let maximumBytes: Int64
    private let chunkByteCount: Int

    public init() {
        maximumBytes = Self.maximumFileBytes
        chunkByteCount = 1_024 * 1_024
    }

    /// Small limits/chunks let tests exercise the same streaming and size checks cheaply.
    init(maximumBytes: Int64, chunkByteCount: Int) {
        precondition(maximumBytes >= 0 && chunkByteCount > 0 && chunkByteCount <= 1_024 * 1_024)
        self.maximumBytes = maximumBytes
        self.chunkByteCount = chunkByteCount
    }

    public func fingerprint(of url: URL, progress: ProgressHandler? = nil) async throws -> ObservationFileFingerprint {
        try Task.checkCancellation()
        guard url.isFileURL else { throw ObservationFileFingerprintError.localRegularFileRequired }
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        // O_NOFOLLOW rejects a final symlink, including one swapped in between inspection
        // and opening. O_NONBLOCK prevents a named pipe from blocking before fstat rejects it.
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw ObservationFileFingerprintError.unreadableFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let before = try Self.snapshot(descriptor)
        guard before.isRegular else { throw ObservationFileFingerprintError.localRegularFileRequired }
        guard before.size >= 0, before.size <= maximumBytes else {
            throw ObservationFileFingerprintError.fileTooLarge
        }

        var hasher = SHA256()
        var byteCount: Int64 = 0
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do { chunk = try handle.read(upToCount: chunkByteCount) ?? Data() }
            catch { throw ObservationFileFingerprintError.unreadableFile }
            guard !chunk.isEmpty else { break }
            guard Int64(chunk.count) <= maximumBytes - byteCount else {
                throw ObservationFileFingerprintError.fileTooLarge
            }
            hasher.update(data: chunk)
            byteCount += Int64(chunk.count)
            if let progress { await progress(byteCount) }
            // Give cancellation a scheduling opportunity even without a progress handler.
            await Task.yield()
        }
        try Task.checkCancellation()
        let after = try Self.snapshot(descriptor)
        // Inspecting the path also catches replacement/unlinking while the original open
        // descriptor still describes unchanged bytes. No metadata here is persisted.
        let pathSnapshot = try Self.snapshot(url)
        guard before == after, before == pathSnapshot, byteCount == before.size else {
            throw ObservationFileFingerprintError.fileChanged
        }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        try Task.checkCancellation()
        return try ObservationFileFingerprint(sha256: hex, byteCount: byteCount)
    }

    private struct Snapshot: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: Int64
        let mode: mode_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        var isRegular: Bool { (mode & mode_t(S_IFMT)) == mode_t(S_IFREG) }

        init(_ value: stat) {
            device = value.st_dev
            inode = value.st_ino
            size = Int64(value.st_size)
            mode = value.st_mode
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private static func snapshot(_ descriptor: Int32) throws -> Snapshot {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw ObservationFileFingerprintError.unreadableFile }
        return Snapshot(value)
    }

    private static func snapshot(_ url: URL) throws -> Snapshot {
        var value = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &value)
        }
        guard result == 0 else { throw ObservationFileFingerprintError.fileChanged }
        return Snapshot(value)
    }
}
