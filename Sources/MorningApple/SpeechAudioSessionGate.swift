import Foundation

/// Serializes audio activation/release without blocking the main actor. An OS activation
/// cannot be cancelled; its late success is released before a newer request may proceed.
@MainActor
final class SpeechAudioSessionGate {
    struct Release {
        let task: Task<Void, any Error>
        fileprivate let revision: UUID
    }

    private let activate: @MainActor () async throws -> Void
    private let deactivate: @MainActor () async throws -> Void
    private var currentRequest: UUID?
    private var revision = UUID()
    private var isActive = false
    private var tail: Task<Void, Never>?

    init(activate: @escaping @MainActor () async throws -> Void,
         deactivate: @escaping @MainActor () async throws -> Void) {
        self.activate = activate
        self.deactivate = deactivate
    }

    func prepare(for requestID: UUID) -> Task<Bool, any Error> {
        currentRequest = requestID
        revision = UUID()
        let preceding = tail
        let operation = Task { @MainActor [self] () throws -> Bool in
            await preceding?.value
            guard currentRequest == requestID else { return false }
            // A prior failed release still owns the audio session. Retry that release
            // before activating another owner, and never hide its failure.
            try await releaseIfActive()
            guard currentRequest == requestID else { return false }
            try await activate()
            isActive = true
            guard currentRequest == requestID else {
                try await releaseIfActive()
                return false
            }
            return true
        }
        tail = Task { _ = try? await operation.value }
        return operation
    }

    /// Enqueues release synchronously, before a replacement can enqueue activation.
    /// Callers needing an ownership handoff await the returned ticket and verify it.
    @discardableResult
    func cancel() -> Release {
        currentRequest = nil
        revision = UUID()
        let releaseRevision = revision
        let preceding = tail
        let operation = Task { @MainActor [self] in
            await preceding?.value
            try await releaseIfActive()
        }
        tail = Task { _ = try? await operation.value }
        return Release(task: operation, revision: releaseRevision)
    }

    /// A canceled caller still waits for uninterruptible OS activation/release to settle.
    /// Newer ownership supersedes this handoff; it must not be reported as released.
    func cancelAndWait() async throws {
        let release = cancel()
        try await release.task.value
        try Task.checkCancellation()
        guard isCurrent(release) else { throw CancellationError() }
    }

    func isCurrent(_ release: Release) -> Bool {
        revision == release.revision && currentRequest == nil && !isActive
    }

    private func releaseIfActive() async throws {
        guard isActive else { return }
        try await deactivate()
        isActive = false
    }
}
