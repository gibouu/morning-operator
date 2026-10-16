import Foundation
import MorningCore
import Darwin

public enum PendingScreenRecordingError: LocalizedError, Sendable, Equatable {
    case appOwnedRecordingRequired
    case anotherRecordingPending
    case unreadableRecording
    case unreadableMetadata

    public var errorDescription: String? {
        switch self {
        case .appOwnedRecordingRequired: AppLanguage.localized("Only a recording created by this app can enter recording recovery.", bundle: .module)
        case .anotherRecordingPending: AppLanguage.localized("Retry or discard the saved recording before adding another one.", bundle: .module)
        case .unreadableRecording: AppLanguage.localized("The saved recording cannot be opened. It has not been overwritten.", bundle: .module)
        case .unreadableMetadata: AppLanguage.localized("The saved recording's metadata cannot be read. The recording and metadata have been kept unchanged.", bundle: .module)
        }
    }
}

/// One immutable reading of the recovery sidecar. Missing legacy fields remain unknown;
/// a malformed present field must not be mistaken for a legacy absence.
public struct PendingScreenRecordingMetadata: Codable, Sendable, Equatable {
    public let interruptionNote: String?
    public let recordingContext: ObservationRecordingContext?

    public init(interruptionNote: String? = nil, recordingContext: ObservationRecordingContext? = nil) {
        self.interruptionNote = interruptionNote
        self.recordingContext = recordingContext
    }
}

/// One local recovery slot. Moving a finalized recording here preserves it across launches;
/// nothing is removed merely because processing, cancellation, or persistence fails.
/// The caller explicitly removes it after saving extracted text, or when the person discards it.
/// The owner serializes synchronous mutations (the app's store uses its main actor).
public struct PendingScreenRecordingStore: Sendable {
    private let directory: URL
    public var recordingURL: URL { directory.appendingPathComponent("pending-screen-recording.mp4") }
    private var metadataURL: URL { directory.appendingPathComponent("recording-info.json") }

    private static let maximumMetadataBytes = 64 * 1_024

    public init(directory: URL) {
        self.directory = directory.appendingPathComponent("RecordingRecovery", isDirectory: true)
    }

    public func owns(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL == recordingURL.standardizedFileURL
    }

    public func recover() throws -> URL? {
        guard FileManager.default.fileExists(atPath: recordingURL.path) else { return nil }
        let values = try recordingURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PendingScreenRecordingError.unreadableRecording
        }
        return recordingURL
    }

    public func interruptionNote() throws -> String? {
        try recoveredMetadata()?.interruptionNote
    }

    public func recordingContext() throws -> ObservationRecordingContext? {
        try recoveredMetadata()?.recordingContext
    }

    public func recoveredMetadata() throws -> PendingScreenRecordingMetadata? {
        // A failed move/removal may leave metadata behind. It is never provenance for an
        // absent file; a later successful retain writes its own metadata before moving.
        guard try recover() != nil else { return nil }
        guard let data = try readMetadataBytes() else { return PendingScreenRecordingMetadata() }
        do { return try JSONDecoder().decode(PendingScreenRecordingMetadata.self, from: data) }
        catch { throw PendingScreenRecordingError.unreadableMetadata }
    }

    /// A single bounded open/read keeps the note and context from the same sidecar version.
    /// Reject links (including dangling links) and nonregular files before reading. Sidecar
    /// replacement is atomic; no personal path or decoding details escape in an error.
    private func readMetadataBytes() throws -> Data? {
        let opened = metadataURL.withUnsafeFileSystemRepresentation { path -> (descriptor: Int32, error: Int32) in
            guard let path else { return (-1, EINVAL) }
            let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            return (descriptor, descriptor < 0 ? errno : 0)
        }
        let descriptor = opened.descriptor
        guard descriptor >= 0 else {
            if opened.error == ENOENT { return nil }
            throw PendingScreenRecordingError.unreadableMetadata
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_size >= 0, before.st_size <= Int64(Self.maximumMetadataBytes) else {
            throw PendingScreenRecordingError.unreadableMetadata
        }
        var data = Data()
        do {
            while data.count <= Self.maximumMetadataBytes {
                let chunk = try handle.read(upToCount: Self.maximumMetadataBytes + 1 - data.count) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
            }
        } catch { throw PendingScreenRecordingError.unreadableMetadata }
        var after = stat()
        guard data.count <= Self.maximumMetadataBytes, Int64(data.count) == before.st_size,
              fstat(descriptor, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw PendingScreenRecordingError.unreadableMetadata
        }
        return data
    }

    @discardableResult
    public func retain(_ url: URL, interruptionNote: String? = nil,
                       recordingContext: ObservationRecordingContext? = nil) throws -> URL {
        // An idempotent retry preserves the already accepted metadata, even if the
        // caller no longer has the live recorder's context after a process restart.
        if owns(url), let existing = try recover() {
            _ = try recoveredMetadata()
            return existing
        }
        guard ScreenRecordingFiles.isOwnedRecording(url) else {
            throw PendingScreenRecordingError.appOwnedRecordingRequired
        }
        guard try recover() == nil else { throw PendingScreenRecordingError.anotherRecordingPending }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PendingScreenRecordingError.unreadableRecording
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var localDirectory = directory
        var protection = URLResourceValues()
        protection.isExcludedFromBackup = true
        try localDirectory.setResourceValues(protection)
        // Metadata is committed first; a crash after the move still has its coverage note
        // and observed session start. Neither the source path nor its filename is stored.
        let metadata = PendingScreenRecordingMetadata(interruptionNote: interruptionNote, recordingContext: recordingContext)
        let encoded = try JSONEncoder().encode(metadata)
        guard encoded.count <= Self.maximumMetadataBytes else { throw PendingScreenRecordingError.unreadableMetadata }
        try encoded.write(to: metadataURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
        // moveItem refuses an existing destination, so an overlapping handoff cannot replace it.
        try FileManager.default.moveItem(at: url, to: recordingURL)
        return recordingURL
    }

    public func remove() throws {
        try removeAllOwnedData()
    }

    /// Explicit cleanup does not need to decode corrupt provenance or a broken
    /// recovery symlink. Only these two owned leaf names are unlinked; a link's
    /// target and unexpected directories remain untouched. Every failure throws.
    public func removeAllOwnedData() throws {
        try RecordingFileCleanup.remove(in: directory,
            names: [recordingURL.lastPathComponent, metadataURL.lastPathComponent])
    }
}
