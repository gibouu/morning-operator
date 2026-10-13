import Foundation
import MorningCore
import Darwin

public enum RecordingSessionStoreError: Error, Sendable, Equatable {
    /// The sessions folder or a session's folder is a link or not a folder. Nothing was followed.
    case unsafeLocation
    /// Missing, a link, too large, or not decodable. Nothing on disk was changed.
    case unreadableManifest
    /// The manifest decoded but broke one of its own rules.
    case manifestRejected(RecordingSessionManifestError)
    /// The encoded manifest exceeds its size bound. Nothing was written.
    case manifestTooLarge
    /// The manifest in this folder names another session.
    case sessionMismatch
    case sessionExists
    /// A segment under this policy could exceed what the file fingerprint accepts.
    case policyExceedsFileLimit
    case segmentFileMissing
}

/// What relaunch found when it compared one session's manifest with its folder.
public struct RecordingSessionRecovery: Equatable, Sendable {
    public enum Finding: Equatable, Sendable {
        /// The session was still open: the app stopped while it was running.
        case sessionInterrupted
        /// The open segment's file was never completed. Its time range is lost.
        case lostOpenSegment(index: Int)
        /// The open segment's file was completed but not yet sealed in the manifest. It is
        /// left in place: fingerprint it, read its length, then seal it or discard it.
        case completedButUnsealedSegment(index: Int, byteCount: Int64)
        /// A sealed or failed segment whose file is gone. Its time range is lost.
        case rawMediaMissing(index: Int)
        /// A sealed or failed segment whose file is not the size that was sealed. Removed.
        case rawMediaChanged(index: Int)
        /// An analysed segment whose file is already gone. Its derived text is unaffected.
        case rawAlreadyReleased(index: Int)
        /// A file left behind for a segment the manifest already gave up or released.
        case removedLeftoverRaw(index: Int)
        /// A segment-named or staging file the manifest does not list. Removed.
        case removedUnlistedFile
        /// Items with names this store never writes. Left untouched.
        case unexpectedItems(count: Int)
    }
    public let manifest: RecordingSessionManifest
    public let findings: [Finding]
}

/// Sessions on disk: one folder per session, holding its manifest and its segment files.
///
/// Layout, under the workspace: `RecordingSessions/<session UUID>/session-manifest.json`,
/// `segment-0000.mp4` for a completed file and `segment-0000.writing.mp4` while the writer
/// has it open. Renaming the second to the first is the instant a file becomes complete.
/// Names come from the session's UUID and the segment's index only; a manifest holds no
/// path, so a decoded one cannot point outside its folder.
///
/// Order of every change: the manifest is saved first, files are removed after. A crash in
/// between leaves a file the manifest no longer wants, which `reconcile` removes. It never
/// leaves the manifest claiming derived text or a raw file that was not saved.
/// Every removal opens the sessions folder, then the session's folder inside it, neither
/// through a link, and unlinks leaf names there.
/// The owner serializes calls, as for `PendingScreenRecordingStore`.
///
/// **Nothing in the app creates a session yet, and two things must come first.** Full
/// forgetting in `MorningStore` must call `forgetAll()` and remove the sessions'
/// observations. And archive capacity, the five-observation selection and the
/// comparable-morning profile must count sessions, not segments: see `SegmentedSessionEvidence`.
public struct RecordingSessionStore: Sendable {
    public static let manifestFileName = "session-manifest.json"
    private let root: URL

    public init(directory: URL) {
        root = directory.appendingPathComponent("RecordingSessions", isDirectory: true)
    }

    public func sessionDirectory(_ sessionID: UUID) -> URL {
        root.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }
    public func manifestURL(_ sessionID: UUID) -> URL {
        sessionDirectory(sessionID).appendingPathComponent(Self.manifestFileName)
    }
    /// The completed file of a segment.
    public func segmentURL(sessionID: UUID, index: Int) -> URL {
        sessionDirectory(sessionID).appendingPathComponent(Self.segmentFileName(index))
    }
    /// Where the writer keeps a segment until it is complete.
    public func writingURL(sessionID: UUID, index: Int) -> URL {
        sessionDirectory(sessionID).appendingPathComponent(Self.writingFileName(index))
    }

    static func segmentFileName(_ index: Int) -> String { String(format: "segment-%04d.mp4", index) }
    static func writingFileName(_ index: Int) -> String { String(format: "segment-%04d.writing.mp4", index) }

    /// The index in a name this store writes for a segment, completed or being written.
    static func segmentIndex(inFileName name: String) -> Int? {
        for suffix in [".writing.mp4", ".mp4"] where name.hasPrefix("segment-") && name.hasSuffix(suffix) {
            let digits = name.dropFirst("segment-".count).dropLast(suffix.count)
            guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let index = Int(digits),
                  index < RecordingSessionManifest.maximumSegments else { return nil }
            return index
        }
        return nil
    }
    /// A staged copy an interrupted atomic save can leave beside the manifest: exactly the
    /// name `AtomicJSONFile` gives `mkstemp`, six letters or digits after the prefix.
    static func isStagingFileName(_ name: String) -> Bool {
        let prefix = ".morning-save-"
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.count)
        return suffix.count == 6 && suffix.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    // MARK: Manifest

    /// Creates the session's folder and saves its first manifest, before any segment exists.
    public func create(_ manifest: RecordingSessionManifest) throws {
        guard manifest.policy.worstCaseSegmentBytes <= ObservationFileFingerprintService.maximumFileBytes else {
            throw RecordingSessionStoreError.policyExceedsFileLimit
        }
        try prepareDirectory(root)
        let directory = sessionDirectory(manifest.id)
        guard Self.kind(of: directory) == .absent else { throw RecordingSessionStoreError.sessionExists }
        try prepareDirectory(directory)
        try save(manifest)
    }

    /// Atomic: a failed save leaves the previous manifest in place.
    public func save(_ manifest: RecordingSessionManifest) throws {
        try requireSessionDirectory(manifest.id)
        guard try JSONEncoder().encode(manifest).count <= RecordingSessionManifest.maximumEncodedBytes else {
            throw RecordingSessionStoreError.manifestTooLarge
        }
        let url = manifestURL(manifest.id)
        // Never write through a link placed at the manifest's name.
        guard Self.kind(of: url) != .other else { throw RecordingSessionStoreError.unreadableManifest }
        try AtomicJSONFile<RecordingSessionManifest>(url: url).save(manifest)
    }

    public func load(_ sessionID: UUID) throws -> RecordingSessionManifest {
        try requireSessionDirectory(sessionID)
        let url = manifestURL(sessionID)
        guard case .regular(let size) = Self.kind(of: url),
              size <= Int64(4 * RecordingSessionManifest.maximumEncodedBytes) else {
            throw RecordingSessionStoreError.unreadableManifest
        }
        let manifest: RecordingSessionManifest
        do { manifest = try AtomicJSONFile<RecordingSessionManifest>(url: url).load() }
        catch let error as RecordingSessionManifestError { throw RecordingSessionStoreError.manifestRejected(error) }
        catch { throw RecordingSessionStoreError.unreadableManifest }
        guard manifest.id == sessionID else { throw RecordingSessionStoreError.sessionMismatch }
        return manifest
    }

    /// Sessions that have a folder, whether or not their manifest can be read.
    public func sessionIDs() throws -> [UUID] {
        switch Self.kind(of: root) {
        case .absent: return []
        case .directory: break
        default: throw RecordingSessionStoreError.unsafeLocation
        }
        return try FileManager.default.contentsOfDirectory(atPath: root.path)
            .compactMap { name in UUID(uuidString: name).flatMap { $0.uuidString == name ? $0 : nil } }
            .filter { Self.kind(of: sessionDirectory($0)) == .directory }
            .sorted { $0.uuidString < $1.uuidString }
    }

    // MARK: Segment files

    /// Makes the written file the segment's completed file. The rename is atomic and
    /// refuses to replace a completed file. Sealing in the manifest follows.
    public func completeWrittenSegment(sessionID: UUID, index: Int) throws {
        try requireSessionDirectory(sessionID)
        let source = writingURL(sessionID: sessionID, index: index)
        let destination = segmentURL(sessionID: sessionID, index: index)
        guard case .regular = Self.kind(of: source), Self.kind(of: destination) == .absent else {
            throw RecordingSessionStoreError.segmentFileMissing
        }
        let renamed = source.path.withCString { from in
            destination.path.withCString { to in renamex_np(from, to, UInt32(RENAME_EXCL)) }
        }
        guard renamed == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Releases the raw file of an analysed segment. The derived text and the entry stay.
    @discardableResult
    public func releaseRaw(sessionID: UUID, index: Int) throws -> RecordingSessionManifest {
        var manifest = try load(sessionID)
        try manifest.expireRaw(index: index)
        try save(manifest)
        try removeFiles(sessionID: sessionID, index: index)
        return manifest
    }

    /// Releases every raw file whose retention has passed at `now`.
    @discardableResult
    public func releaseExpiredRaw(sessionID: UUID, now: Date) throws -> RecordingSessionManifest {
        var manifest = try load(sessionID)
        let due = manifest.segmentsWithReleasableRaw(at: now).map(\.index)
        guard !due.isEmpty else { return manifest }
        for index in due { try manifest.expireRaw(index: index) }
        try save(manifest)
        for index in due { try removeFiles(sessionID: sessionID, index: index) }
        return manifest
    }

    /// Gives one segment up: its entry becomes discarded, then its files are removed. The
    /// caller removes the segment's observation from the archive before calling this.
    @discardableResult
    public func discardSegment(sessionID: UUID, index: Int, reason: RecordingSegmentLossReason,
                               endSeconds: Double? = nil) throws -> RecordingSessionManifest {
        var manifest = try load(sessionID)
        try manifest.discard(index: index, reason: reason, endSeconds: endSeconds)
        try save(manifest)
        try removeFiles(sessionID: sessionID, index: index)
        return manifest
    }

    // MARK: Relaunch

    /// Compares the manifest with the folder, in both directions, and settles what a crash
    /// left behind. Call it at launch, or whenever no capture and no analysis of this
    /// session is running. An unreadable manifest throws and nothing is touched.
    public func reconcile(_ sessionID: UUID) throws -> RecordingSessionRecovery {
        var manifest = try load(sessionID)
        let original = manifest
        let names = try FileManager.default.contentsOfDirectory(atPath: sessionDirectory(sessionID).path)
        var findings: [RecordingSessionRecovery.Finding] = []
        var removals: [String] = []
        if manifest.isOpen {
            // Nothing is recording now, so an open session was cut short at an unknown instant.
            try manifest.end(reason: .interrupted, atSeconds: nil)
            findings.append(.sessionInterrupted)
        }
        for segment in manifest.segments {
            let index = segment.index
            let completedName = Self.segmentFileName(index)
            let writingName = Self.writingFileName(index)
            let completed = names.contains(completedName)
                ? Self.kind(of: sessionDirectory(sessionID).appendingPathComponent(completedName)) : .absent
            let hasWritingFile = names.contains(writingName)
            switch segment.state {
            case .writing:
                if case .regular(let size) = completed {
                    findings.append(.completedButUnsealedSegment(index: index, byteCount: size))
                    if hasWritingFile { removals.append(writingName) }
                } else {
                    try manifest.discard(index: index, reason: .interruptedWhileWriting)
                    findings.append(.lostOpenSegment(index: index))
                    removals += [completedName, writingName].filter(names.contains)
                }
            case .sealed, .failed:
                if hasWritingFile { removals.append(writingName) }
                if case .regular(let size) = completed, size == segment.byteCount { break }
                let missing = completed == .absent
                try manifest.discard(index: index, reason: missing ? .rawMediaMissing : .rawMediaChanged)
                findings.append(missing ? .rawMediaMissing(index: index) : .rawMediaChanged(index: index))
                if !missing { removals.append(completedName) }
            case .analysed:
                if hasWritingFile { removals.append(writingName) }
                if case .regular = completed { break }
                // The derived text is saved, so only the raw file's absence is recorded.
                try manifest.expireRaw(index: index)
                findings.append(.rawAlreadyReleased(index: index))
                if completed != .absent { removals.append(completedName) }
            case .discarded, .rawExpired:
                let leftovers = [completedName, writingName].filter(names.contains)
                if !leftovers.isEmpty { findings.append(.removedLeftoverRaw(index: index)) }
                removals += leftovers
            }
        }
        var unexpected = 0
        for name in names where name != Self.manifestFileName {
            if let index = Self.segmentIndex(inFileName: name) {
                if index >= manifest.segments.count { removals.append(name); findings.append(.removedUnlistedFile) }
            } else if Self.isStagingFileName(name) {
                removals.append(name); findings.append(.removedUnlistedFile)
            } else {
                unexpected += 1
            }
        }
        if unexpected > 0 { findings.append(.unexpectedItems(count: unexpected)) }
        if manifest != original { try save(manifest) }
        try RecordingFileCleanup.remove(in: root, child: sessionID.uuidString, names: removals)
        return .init(manifest: manifest, findings: findings)
    }

    // MARK: Forgetting

    /// Removes one session: every segment file this store could have written for it, staged
    /// manifest copies, then the manifest, then the folder if it is empty. The manifest goes
    /// last, so an interrupted call can be repeated. It works when the manifest cannot be
    /// read. Only these names inside this session's folder are unlinked: a link is removed
    /// without being followed, and any other item, folder or session is left alone.
    /// The caller removes the session's observations with `ObservationArchive.deleteSession`.
    public func forget(_ sessionID: UUID) throws {
        let directory = sessionDirectory(sessionID)
        switch Self.kind(of: directory) {
        case .absent: return
        case .directory: break
        default: throw RecordingSessionStoreError.unsafeLocation
        }
        guard Self.kind(of: root) == .directory else { throw RecordingSessionStoreError.unsafeLocation }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let owned = names.filter { Self.segmentIndex(inFileName: $0) != nil || Self.isStagingFileName($0) }
        // The folder is removed only when empty. Anything unexpected keeps it in place.
        try RecordingFileCleanup.remove(in: root, child: sessionID.uuidString,
            names: owned + [Self.manifestFileName], removingChildIfEmpty: true)
    }

    /// Forgets every session. One that cannot be removed does not stop the others; the
    /// first error is thrown at the end.
    public func forgetAll() throws {
        var failure: (any Error)?
        for sessionID in try sessionIDs() {
            do { try forget(sessionID) } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    // MARK: Helpers

    private func removeFiles(sessionID: UUID, index: Int) throws {
        try RecordingFileCleanup.remove(in: root, child: sessionID.uuidString,
            names: [Self.segmentFileName(index), Self.writingFileName(index)])
    }

    private func prepareDirectory(_ directory: URL) throws {
        switch Self.kind(of: directory) {
        case .directory: return
        case .absent: break
        default: throw RecordingSessionStoreError.unsafeLocation
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var local = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try local.setResourceValues(values)
    }

    private func requireSessionDirectory(_ sessionID: UUID) throws {
        guard Self.kind(of: root) == .directory, Self.kind(of: sessionDirectory(sessionID)) == .directory else {
            throw RecordingSessionStoreError.unsafeLocation
        }
    }

    private enum ItemKind: Equatable {
        case absent, directory, regular(size: Int64), other
    }

    /// Inspects the item itself. A link, whatever it points to, is `other`.
    private static func kind(of url: URL) -> ItemKind {
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        var value = stat()
        guard lstat(path, &value) == 0 else { return errno == ENOENT ? .absent : .other }
        switch value.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFDIR): return .directory
        case mode_t(S_IFREG): return .regular(size: Int64(value.st_size))
        default: return .other
        }
    }
}
