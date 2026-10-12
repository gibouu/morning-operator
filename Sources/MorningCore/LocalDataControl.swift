import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct LocalDataControlState: Codable, Sendable, Equatable {
    public let generation: UUID?
    public let forgetPending: Bool
    public let activityLoggingAllowed: Bool

    fileprivate init(generation: UUID?, forgetPending: Bool, activityLoggingAllowed: Bool) {
        self.generation = generation
        self.forgetPending = forgetPending
        self.activityLoggingAllowed = activityLoggingAllowed
    }

    fileprivate static let initial = Self(generation: nil, forgetPending: false, activityLoggingAllowed: true)
}

public enum LocalDataControlError: Error, LocalizedError, Sendable, Equatable {
    case fileURLRequired
    case unsafePath
    case invalidControl
    case unsupportedSchema(Int)
    case forgetInProgress
    case forgetNotPending
    case staleGeneration

    public var errorDescription: String? {
        switch self {
        case .fileURLRequired: String(localized: "Local privacy controls require a file location.", bundle: .module)
        case .unsafePath: String(localized: "The local privacy files could not be opened safely. Nothing was replaced.", bundle: .module)
        case .invalidControl: String(localized: "Local privacy status is unreadable. Ordinary access is paused until it is explicitly reset.", bundle: .module)
        case .unsupportedSchema: String(localized: "Local privacy status uses an unsupported format. Ordinary access is paused.", bundle: .module)
        case .forgetInProgress: String(localized: "Forgetting local data is still in progress.", bundle: .module)
        case .forgetNotPending: String(localized: "There is no pending local-data removal.", bundle: .module)
        case .staleGeneration: String(localized: "This removal request no longer matches the current privacy state.", bundle: .module)
        }
    }
}

/// A content-free, cross-process gate for cooperating local-data owners.
/// Keep the directory and `.morning-privacy-lock` in place during cleanup. Every
/// owner must hold this lock across its full read/mutate/save operation. Locked
/// closures are synchronous and non-reentrant: do not call this control again
/// from inside one, or wait for another operation that needs the same lock.
///
/// Only the final directory, lock and marker must be nonsymlinks; normal system
/// ancestor aliases such as Apple's /var are allowed. Marker I/O is relative to
/// the opened directory descriptor. This is coordination, not secure erasure or
/// a transaction across the separately owned files removed by the caller.
public struct LocalDataControl: Sendable {
    public let directory: URL
    private static let markerName = "local-data-control.json"
    private static let lockName = ".morning-privacy-lock"
    private static let maximumMarkerBytes = 4_096

    /// One stable fallback per process prevents independently created adapters
    /// from choosing different test workspaces when a UUID was not supplied.
    public static let defaultDirectory: URL = {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing") {
            let supplied = process.arguments.first { $0.hasPrefix("--ui-testing-workspace=") }
                .flatMap { UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) }
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("MorningOperatorUITests-\((supplied ?? UUID()).uuidString)", isDirectory: true)
        }
        if let override = process.environment["MORNING_OPERATOR_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MorningOperator", isDirectory: true)
    }()

    public init(directory: URL) { self.directory = directory }

    public func status() throws -> LocalDataControlState {
        try withLock { try readState(in: $0) }
    }

    /// Explicit user-requested forgetting may replace a malformed or future
    /// regular marker. Unsafe paths and I/O failures still fail closed. A retry
    /// of an already pending removal retains its generation.
    @discardableResult
    public func beginForget() throws -> LocalDataControlState {
        try withLock { descriptor in
            let previous: LocalDataControlState?
            do { previous = try readState(in: descriptor) }
            catch LocalDataControlError.invalidControl { previous = nil }
            catch LocalDataControlError.unsupportedSchema { previous = nil }
            if let previous, previous.forgetPending { return previous }
            let next = LocalDataControlState(generation: UUID(), forgetPending: true, activityLoggingAllowed: false)
            try save(next, in: descriptor)
            return next
        }
    }

    public func finishForget(expectedGeneration: UUID) throws {
        try withLock { descriptor in
            let current = try readState(in: descriptor)
            try requireForget(current, generation: expectedGeneration)
            try save(.init(generation: expectedGeneration, forgetPending: false, activityLoggingAllowed: false),
                     in: descriptor)
        }
    }

    public func withReadyAccess<T>(_ body: (LocalDataControlState) throws -> T) throws -> T {
        try withLock { descriptor in
            let current = try readState(in: descriptor)
            guard !current.forgetPending else { throw LocalDataControlError.forgetInProgress }
            return try body(current)
        }
    }

    public func withForgetAccess<T>(expectedGeneration: UUID, _ body: () throws -> T) throws -> T {
        try withLock { descriptor in
            try requireForget(try readState(in: descriptor), generation: expectedGeneration)
            return try body()
        }
    }

    public func setActivityLoggingAllowed(_ allowed: Bool) throws {
        try withLock { descriptor in
            let current = try readState(in: descriptor)
            guard !current.forgetPending else { throw LocalDataControlError.forgetInProgress }
            guard current.activityLoggingAllowed != allowed else { return }
            try save(.init(generation: current.generation, forgetPending: false, activityLoggingAllowed: allowed),
                     in: descriptor)
        }
    }

    private func requireForget(_ state: LocalDataControlState, generation: UUID) throws {
        guard state.generation == generation else { throw LocalDataControlError.staleGeneration }
        guard state.forgetPending else { throw LocalDataControlError.forgetNotPending }
    }

    private func withLock<T>(_ body: (Int32) throws -> T) throws -> T {
        guard directory.isFileURL else { throw LocalDataControlError.fileURLRequired }
        let path = directory.path
        // Inspect the original path before opening it; do not resolve a supplied
        // final symlink into a different workspace.
        var before = stat()
        if lstat(path, &before) != 0 {
            guard errno == ENOENT else { throw localControlPOSIXError() }
            // Owners can arrive together before their shared lock exists. Create
            // the final directory with one atomic mkdir, accepting only the
            // expected competing-creator result, then inspect the winner. Do not
            // run Foundation's intermediate-directory creation on that shared
            // final path while another owner may already be using it.
            let parent = directory.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if mkdir(path, mode_t(0o700)) != 0 {
                guard errno == EEXIST else { throw localControlPOSIXError() }
            }
            guard lstat(path, &before) == 0 else { throw localControlPOSIXError() }
        }
        guard localControlIsDirectory(before) else { throw LocalDataControlError.unsafePath }
        let directoryFD = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw localControlOpenError() }
        defer { _ = close(directoryFD) }
        var opened = stat()
        guard fstat(directoryFD, &opened) == 0 else { throw localControlPOSIXError() }
        guard localControlSameFile(before, opened), localControlIsDirectory(opened) else {
            throw LocalDataControlError.unsafePath
        }

        let lockFD = try openSharedLock(in: directoryFD)
        defer { _ = close(lockFD) }
        var lockInfo = stat()
        guard fstat(lockFD, &lockInfo) == 0 else { throw localControlPOSIXError() }
        guard localControlIsPrivateRegular(lockInfo) else { throw LocalDataControlError.unsafePath }
        guard fchmod(lockFD, mode_t(0o600)) == 0 else { throw localControlPOSIXError() }
        while flock(lockFD, LOCK_EX) != 0 {
            guard errno == EINTR else { throw localControlPOSIXError() }
        }
        defer { _ = flock(lockFD, LOCK_UN) }
        // Detect a removed/replaced lock while this caller was waiting. Cleanup
        // must never unlink the lock: two inode locks would not serialize access.
        var linkedLock = stat()
        guard fstatat(directoryFD, Self.lockName, &linkedLock, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw localControlPOSIXError()
        }
        var linkedDirectory = stat()
        guard lstat(path, &linkedDirectory) == 0 else { throw localControlPOSIXError() }
        guard localControlSameFile(lockInfo, linkedLock), localControlIsPrivateRegular(linkedLock),
              localControlSameFile(opened, linkedDirectory), localControlIsDirectory(linkedDirectory) else {
            throw LocalDataControlError.unsafePath
        }
        return try body(directoryFD)
    }

    private func openSharedLock(in directoryFD: Int32) throws -> Int32 {
        let accessFlags = O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        // Separate ordinary open from exclusive creation. Simultaneous
        // openat(O_CREAT) calls can return ENOENT during first creation on the
        // observed Apple filesystem, even with a valid linked parent inode.
        // EEXIST is the expected exclusive-creation loser: reopen its winner.
        // A bounded retry refuses an unstable/unlinked lock namespace.
        for _ in 0..<8 {
            let existing = openat(directoryFD, Self.lockName, accessFlags)
            if existing >= 0 { return existing }
            guard errno == ENOENT else { throw localControlOpenError() }
            let created = openat(directoryFD, Self.lockName,
                accessFlags | O_CREAT | O_EXCL, mode_t(0o600))
            if created >= 0 { return created }
            guard errno == EEXIST else { throw localControlOpenError() }
        }
        throw LocalDataControlError.unsafePath
    }

    private func readState(in directoryFD: Int32) throws -> LocalDataControlState {
        let descriptor = openat(directoryFD, Self.markerName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return .initial }
            throw localControlOpenError()
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw localControlPOSIXError() }
        guard localControlIsPrivateRegular(info) else { throw LocalDataControlError.unsafePath }
        guard info.st_size >= 0, info.st_size <= Self.maximumMarkerBytes else {
            throw LocalDataControlError.invalidControl
        }
        let data = try handle.read(upToCount: Self.maximumMarkerBytes + 1) ?? Data()
        guard data.count <= Self.maximumMarkerBytes else { throw LocalDataControlError.invalidControl }
        let header: LocalControlHeader
        do { header = try JSONDecoder().decode(LocalControlHeader.self, from: data) }
        catch { throw LocalDataControlError.invalidControl }
        guard header.schemaVersion == 1 else { throw LocalDataControlError.unsupportedSchema(header.schemaVersion) }
        let state: LocalDataControlState
        do { state = try JSONDecoder().decode(LocalControlEnvelope.self, from: data).value }
        catch { throw LocalDataControlError.invalidControl }
        guard !state.forgetPending || (state.generation != nil && !state.activityLoggingAllowed) else {
            throw LocalDataControlError.invalidControl
        }
        return state
    }

    private func save(_ state: LocalDataControlState, in directoryFD: Int32) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LocalControlEnvelope(schemaVersion: 1, value: state))
        let stagedName = ".morning-privacy-\(UUID().uuidString).tmp"
        let descriptor = openat(directoryFD, stagedName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw localControlOpenError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var closed = false
        var committed = false
        defer {
            if !closed { try? handle.close() }
            if !committed { _ = unlinkat(directoryFD, stagedName, 0) }
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw localControlPOSIXError() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        closed = true
        guard renameat(directoryFD, stagedName, directoryFD, Self.markerName) == 0 else {
            throw localControlPOSIXError()
        }
        // No throwing operation follows commit. Like AtomicJSONFile this does
        // not fsync the parent directory or promise sudden-power-loss durability.
        committed = true
    }
}

private struct LocalControlHeader: Decodable { let schemaVersion: Int }
private struct LocalControlEnvelope: Codable {
    let schemaVersion: Int
    let value: LocalDataControlState
}

private func localControlIsDirectory(_ value: stat) -> Bool {
    (value.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
}

private func localControlIsPrivateRegular(_ value: stat) -> Bool {
    (value.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) && value.st_nlink == 1 && value.st_uid == geteuid()
}

private func localControlSameFile(_ first: stat, _ second: stat) -> Bool {
    first.st_dev == second.st_dev && first.st_ino == second.st_ino
}

private func localControlOpenError() -> any Error {
    errno == ELOOP ? LocalDataControlError.unsafePath : localControlPOSIXError()
}

private func localControlPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
