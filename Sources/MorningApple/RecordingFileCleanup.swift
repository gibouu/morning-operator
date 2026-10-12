import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum RecordingCleanupError: LocalizedError, Sendable, Equatable {
    case invalidTestWorkspace
    case unsafeDirectory
    case unexpectedFileType
    case captureStopUnconfirmed
    case forgettingInProgress

    public var errorDescription: String? {
        switch self {
        case .invalidTestWorkspace: "Recording cleanup requires an isolated test workspace."
        case .unsafeDirectory: "The recording folder couldn't be safely opened. No linked folder was followed."
        case .unexpectedFileType: "An unexpected item remains in the recording folder. It hasn't been removed."
        case .captureStopUnconfirmed: "Screen recording hasn't fully stopped. Stop it using the system controls, then retry forgetting."
        case .forgettingInProgress: "Finish forgetting local data before starting another recording."
        }
    }
}

/// Recording-only cleanup. The open directory descriptor pins the directory for
/// inspection and unlinking. A symlink at an allowed filename is unlinked itself;
/// directories and other unexpected types are never traversed or removed.
enum RecordingFileCleanup {
    static func remove(in directory: URL, names: [String]) throws {
        try withDirectory(directory) { descriptor in
            for name in names {
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                    throw RecordingCleanupError.unsafeDirectory
                }
                try remove(name: name, descriptor: descriptor)
            }
        }
    }

    static func removeRecordings(in directory: URL) throws {
        try withDirectory(directory) { descriptor in
            // Enumerate through the same descriptor used for deletion, so replacing
            // a path while cleanup runs cannot redirect cleanup to a different folder.
            let duplicate = dup(descriptor)
            guard duplicate >= 0 else { throw posixError() }
            guard let enumeration = fdopendir(duplicate) else {
                let error = posixError(); close(duplicate); throw error
            }
            defer { closedir(enumeration) }
            var names: [String] = []
            while true {
                errno = 0
                guard let entry = readdir(enumeration) else {
                    if errno != 0 { throw posixError() }
                    break
                }
                let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                        String(cString: $0)
                    }
                }
                if ScreenRecordingFiles.isRecordingFilename(name) { names.append(name) }
            }
            for name in names { try remove(name: name, descriptor: descriptor) }
        }
    }

    private static func withDirectory(_ directory: URL, body: (Int32) throws -> Void) throws {
        guard directory.isFileURL else { throw RecordingCleanupError.unsafeDirectory }
        // A trailing separator makes a symlink an intermediate path component on
        // POSIX systems. Remove it so O_NOFOLLOW applies to this owned directory.
        var path = directory.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let descriptor = path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else {
            if errno == ENOENT { return }
            if errno == ELOOP || errno == ENOTDIR { throw RecordingCleanupError.unsafeDirectory }
            throw posixError()
        }
        defer { close(descriptor) }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0 else { throw posixError() }
        try body(descriptor)
        var linked = stat()
        guard lstat(path, &linked) == 0,
              linked.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              opened.st_dev == linked.st_dev, opened.st_ino == linked.st_ino else {
            throw RecordingCleanupError.unsafeDirectory
        }
    }

    private static func remove(name: String, descriptor: Int32) throws {
        var metadata = stat()
        let inspected = name.withCString { fstatat(descriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW) }
        if inspected != 0 {
            if errno == ENOENT { return }
            throw posixError()
        }
        let type = metadata.st_mode & mode_t(S_IFMT)
        guard type == mode_t(S_IFREG) || type == mode_t(S_IFLNK) else {
            throw RecordingCleanupError.unexpectedFileType
        }
        // No AT_REMOVEDIR: even a last-instant replacement with a directory cannot
        // recurse or delete that directory. unlinkat never follows a leaf symlink.
        guard name.withCString({ unlinkat(descriptor, $0, 0) }) == 0 else { throw posixError() }
        let verified = name.withCString { fstatat(descriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW) }
        guard verified != 0, errno == ENOENT else { throw RecordingCleanupError.unexpectedFileType }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
