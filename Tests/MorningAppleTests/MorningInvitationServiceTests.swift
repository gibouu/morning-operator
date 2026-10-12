import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Durable morning invitation scheduling")
@MainActor
struct MorningInvitationServiceTests {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func permissionIsExplicitAndDeniedOrQuietDoesNotClaimScheduled() async throws {
        for authorization in [MorningInvitationAuthorization.notDetermined, .denied, .provisional] {
            let storage = InvitationMemoryStorage()
            let client = InvitationNotificationFixture(authorization: authorization)
            let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
            await service.reconcile()
            #expect(client.permissionRequests == 0)
            await service.schedule(at: origin.addingTimeInterval(60))
            #expect(storage.value?.disposition == .enabled, "The chosen time survives a denied or quiet grant.")
            #expect(!service.isScheduled)
            #expect(client.added.isEmpty)
            #expect(client.permissionRequests == (authorization == .denied ? 0 : 1))
            await service.reconcile()
            #expect(client.permissionRequests == (authorization == .denied ? 0 : 1), "Reconciliation never prompts.")
        }
    }

    @Test func persistedDesiredScheduleRecoversFromAddFailureWithoutDuplicates() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        client.failAdd = true
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        await service.schedule(at: origin.addingTimeInterval(60))
        let desired = try #require(storage.value)
        #expect(!service.isScheduled && service.errorMessage != nil)
        client.failAdd = false
        let restored = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        await restored.reconcile()
        #expect(restored.isScheduled)
        #expect(client.pending?.payload == desired.payload)
        let count = client.added.count
        await restored.reconcile()
        #expect(client.added.count == count)
        #expect(client.permissionRequests == 0)
    }

    @Test func replacingAndCancellingInvalidateOldPayloadBeforeNativeWork() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        let clock = InvitationClock(origin)
        let service = MorningInvitationService(storage: storage, notifications: client, now: { clock.date })
        await service.schedule(at: origin.addingTimeInterval(60))
        let original = try #require(service.invitation)
        await service.schedule(at: origin.addingTimeInterval(120))
        clock.date = origin.addingTimeInterval(120)
        #expect(try service.consume(original.payload) == nil)
        let replacement = try #require(service.invitation)
        await service.cancel()
        #expect(storage.value?.disposition == .cancelled)
        #expect(try service.consume(replacement.payload) == nil)
        #expect(client.pending == nil)
        #expect(client.deliveredRemovalCount > 0)
        let restored = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        await restored.reconcile()
        #expect(!restored.isScheduled && client.pending == nil)
    }

    @Test func cancellationWhilePermissionIsPendingNeverAddsLater() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture(authorization: .notDetermined)
        client.holdPermission = true
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        let scheduling = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForPermission()
        let cancelling = Task { await service.cancel() }
        while storage.value?.disposition != .cancelled { await Task.yield() }
        client.completePermission(authorization: .authorized)
        await scheduling.value
        await cancelling.value
        #expect(client.added.isEmpty)
        #expect(client.pending == nil)
        #expect(!service.isBusy && !service.isScheduled)
    }

    @Test func passiveRefreshPreservesExactlyOneOutstandingExplicitPermissionRequest() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture(authorization: .notDetermined)
        client.holdFirstSettings = true
        client.authorizationAfterRequest = .authorized
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        let scheduling = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForSettings()
        let refreshing = Task { await service.reconcile() }
        // Let refresh load the same occurrence and enqueue behind the suspended job.
        while storage.loadCount < 2 { await Task.yield() }
        client.completeSettings()
        await scheduling.value
        await refreshing.value
        #expect(client.permissionRequests == 1)
        #expect(service.isScheduled)
        await service.reconcile()
        #expect(client.permissionRequests == 1)

        // A saved desired preference alone must not authorize a prompt after relaunch.
        client.authorization = .notDetermined
        client.pending = nil
        let relaunched = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        await relaunched.reconcile()
        #expect(client.permissionRequests == 1)
        #expect(!relaunched.isScheduled)
    }

    @Test func cancellationWhileNativeAddIsPendingRemovesItsLateRegistration() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        client.holdAdd = true
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        let scheduling = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForAdd()
        let cancelling = Task { await service.cancel() }
        while storage.value?.disposition != .cancelled { await Task.yield() }
        client.completeAdd()
        await scheduling.value
        await cancelling.value
        #expect(client.added.count == 1, "The OS add may finish after cancellation.")
        #expect(client.pending == nil, "Its registration is then removed before cancellation completes.")
        #expect(!service.isScheduled)
    }

    @Test func consumeIsDurableAndWriteFailureNeverReturnsEntry() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        let clock = InvitationClock(origin)
        let service = MorningInvitationService(storage: storage, notifications: client, now: { clock.date })
        await service.schedule(at: origin.addingTimeInterval(60))
        let payload = try #require(service.invitation?.payload)
        clock.date = origin.addingTimeInterval(60)
        storage.failSave = true
        #expect(throws: InvitationFixtureError.disk) { try service.consume(payload) }
        #expect(storage.value?.disposition == .enabled)
        storage.failSave = false
        #expect(try service.consume(payload)?.disposition == .consumed)
        #expect(try service.consume(payload) == nil)
        let restored = MorningInvitationService(storage: storage, notifications: client, now: { clock.date })
        #expect(try restored.consume(payload) == nil)
        await service.reconcile()
        #expect(client.pending == nil)
    }

    @Test func replacementDuringNativeAddWinsWithoutLateCleanupRemovingIt() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        client.holdAdd = true
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        let first = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForAdd()
        let firstID = try #require(storage.value?.id)
        let replacement = Task { await service.schedule(at: origin.addingTimeInterval(120)) }
        while storage.value?.id == firstID { await Task.yield() }
        let replacementID = try #require(storage.value?.id)
        client.completeAdd()
        await first.value
        await replacement.value
        #expect(client.added.map(\.id) == [firstID, replacementID])
        #expect(client.pending?.payload?.occurrenceID == replacementID)
        #expect(service.isScheduled && !service.isBusy)
    }

    @Test func dueOccurrenceIsNotRescheduledAndExpiredOccurrenceIsDurablyClosed() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        let clock = InvitationClock(origin)
        let service = MorningInvitationService(storage: storage, notifications: client, now: { clock.date })
        await service.schedule(at: origin.addingTimeInterval(60))
        let original = try #require(service.invitation)
        client.pending = nil // Models the OS having fired the one-time request, not proof of delivery.
        let added = client.added.count
        clock.date = original.scheduledAt
        await service.reconcile()
        #expect(client.added.count == added)
        #expect(!service.isScheduled)
        clock.date = original.expiresAt
        await service.reconcile()
        #expect(storage.value?.disposition == .expired)
        clock.date = origin
        await service.reconcile()
        #expect(client.added.count == added, "Clock rollback must not resurrect an expired invitation.")
    }

    @Test func filePersistenceIsSeparateAndCorruptionRequiresExplicitCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MorningInvitationFileStorage(directory: directory)
        let client = InvitationNotificationFixture()
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        await service.schedule(at: origin.addingTimeInterval(60))
        #expect(try storage.load() == service.invitation)
        let workspaceURL = directory.appendingPathComponent("workspace.json")
        let workspace = Data("routines stay here".utf8)
        try workspace.write(to: workspaceURL)
        let preferenceURL = directory.appendingPathComponent("morning-invitation.json")
        let corrupt = Data("invalid preference".utf8)
        try corrupt.write(to: preferenceURL)
        let restored = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        #expect(restored.needsRecovery)
        await restored.reconcile()
        await restored.schedule(at: origin.addingTimeInterval(120))
        #expect(try Data(contentsOf: preferenceURL) == corrupt)
        #expect(restored.errorMessage != nil)
        #expect(client.pending == nil)
        await restored.cancel()
        #expect(!restored.needsRecovery)
        #expect(try storage.load() == nil)
        #expect(try Data(contentsOf: workspaceURL) == workspace)
        await restored.schedule(at: origin.addingTimeInterval(120))
        #expect(restored.isScheduled)
    }

    @Test func payloadHelpersRejectUnrecognizedSchemaWithoutPersonalData() throws {
        let invitation = try MorningInvitation(scheduledAt: origin.addingTimeInterval(60), timeZoneIdentifier: "UTC", now: origin)
        #expect(MorningInvitationPayload(userInfo: invitation.payload.userInfo) == invitation.payload)
        #expect(MorningInvitationService.payload(from: invitation.payload.userInfo) == invitation.payload)
        var malformed = invitation.payload.userInfo
        malformed[MorningInvitationPayload.schemaKey] = "2"
        #expect(MorningInvitationPayload(userInfo: malformed) == nil)
        #expect(invitation.payload.userInfo.count == 2)
    }

    @Test func forgettingDuringPermissionWaitErasesMetadataAndNeverAddsAfterward() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture(authorization: .notDetermined)
        client.holdPermission = true
        client.delivered = true
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        let scheduling = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForPermission()
        let forgetting = Task { try await service.forget() }
        while !service.isForgetting { await Task.yield() }
        #expect(storage.value == nil)
        await service.reconcile()
        await service.schedule(at: origin.addingTimeInterval(120))
        client.completePermission(authorization: .authorized)
        await scheduling.value
        try await forgetting.value
        #expect(client.permissionRequests == 1)
        #expect(client.added.isEmpty)
        #expect(client.pending == nil && !client.delivered)
        #expect(service.invitation == nil && !service.isScheduled && !service.isBusy)
        #expect(client.authorization == .authorized, "Forgetting leaves the OS grant untouched.")
    }

    @Test func forgettingDrainsAnUncancellableLateAddBeforeConfirmingRemoval() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        client.holdAdd = true
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        let scheduling = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForAdd()
        let forgetting = Task { try await service.forget() }
        while !service.isForgetting { await Task.yield() }
        await #expect(throws: MorningInvitationForgetError.alreadyForgetting) { try await service.forget() }
        client.completeAdd()
        await scheduling.value
        try await forgetting.value
        #expect(client.added.count == 1)
        #expect(client.pending == nil)
        #expect(storage.value == nil)
        await service.reconcile()
        #expect(client.added.count == 1)
    }

    @Test func forgetReportsUnremovedNativeRequestAndCanBeRetried() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        await service.schedule(at: origin.addingTimeInterval(60))
        client.delivered = true
        client.ignoreRemoval = true
        await #expect(throws: MorningInvitationForgetError.cleanupUnconfirmed) { try await service.forget() }
        #expect(storage.value == nil)
        #expect(service.errorMessage != nil && !service.isScheduled)
        client.ignoreRemoval = false
        try await service.forget()
        #expect(client.pending == nil && !client.delivered)
        #expect(service.errorMessage == nil)
    }

    @Test func forgetSaveFailureIsThrownEvenAfterNativeRemoval() async throws {
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        let service = MorningInvitationService(storage: storage, notifications: client, now: { origin })
        await service.schedule(at: origin.addingTimeInterval(60))
        storage.failSave = true
        await #expect(throws: InvitationFixtureError.disk) { try await service.forget() }
        #expect(storage.value != nil)
        #expect(client.pending == nil)
        #expect(service.needsRecovery && service.errorMessage != nil)
        storage.failSave = false
        try await service.forget()
        #expect(storage.value == nil && !service.needsRecovery)
    }

    @Test func pendingPrivacyResetBlocksOldScheduleOnReloadAndRepairsCorruptPreference() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let privacy = LocalDataControl(directory: directory)
        let storage = MorningInvitationFileStorage(directory: directory)
        let client = InvitationNotificationFixture()
        let original = MorningInvitationService(storage: storage, notifications: client, privacy: privacy, now: { origin })
        await original.schedule(at: origin.addingTimeInterval(60))
        let added = client.added.count
        _ = try privacy.beginForget()
        let restored = MorningInvitationService(storage: storage, notifications: client, privacy: privacy, now: { origin })
        #expect(restored.invitation == nil)
        await restored.reconcile()
        await restored.schedule(at: origin.addingTimeInterval(120))
        #expect(client.added.count == added && client.pending == nil)
        let url = directory.appendingPathComponent("morning-invitation.json")
        try Data("unreadable synthetic preference".utf8).write(to: url)
        try await restored.forget()
        #expect(try storage.load() == nil)
        #expect(try privacy.status().forgetPending)
    }

    @Test func resetBeginningDuringNativeAddMakesItsLateResultIneligible() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let privacy = LocalDataControl(directory: directory)
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        client.holdAdd = true
        let service = MorningInvitationService(storage: storage, notifications: client, privacy: privacy, now: { origin })
        let scheduling = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForAdd()
        _ = try privacy.beginForget()
        client.completeAdd()
        await scheduling.value
        #expect(client.added.count == 1 && client.pending == nil)
        #expect(!service.isScheduled)
        try await service.forget()
        #expect(storage.value == nil)
    }

    @Test func oldSchedulingJobCannotResumeAfterResetHasAlreadyFinished() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let privacy = LocalDataControl(directory: directory)
        let storage = InvitationMemoryStorage()
        let client = InvitationNotificationFixture()
        client.holdFirstSettings = true
        let service = MorningInvitationService(storage: storage, notifications: client, privacy: privacy, now: { origin })
        let scheduling = Task { await service.schedule(at: origin.addingTimeInterval(60)) }
        await client.waitForSettings()
        let reset = try privacy.beginForget()
        let generation = try #require(reset.generation)
        try privacy.withForgetAccess(expectedGeneration: generation) { try storage.save(nil) }
        try privacy.finishForget(expectedGeneration: generation)
        client.completeSettings()
        await scheduling.value
        #expect(client.added.isEmpty)
        #expect(!service.isScheduled && storage.value == nil)
    }
}

private enum InvitationFixtureError: Error { case disk, add }

@MainActor private final class InvitationClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor private final class InvitationMemoryStorage: MorningInvitationStorage {
    var value: MorningInvitation?
    var failSave = false
    var loadCount = 0
    func load() throws -> MorningInvitation? { loadCount += 1; return value }
    func save(_ invitation: MorningInvitation?) throws {
        if failSave { throw InvitationFixtureError.disk }
        value = invitation
    }
}

@MainActor private final class InvitationNotificationFixture: MorningInvitationNotificationClient {
    var authorization: MorningInvitationAuthorization
    var pending: MorningInvitationPendingRequest?
    var added: [MorningInvitation] = []
    var permissionRequests = 0
    var deliveredRemovalCount = 0
    var delivered = false
    var ignoreRemoval = false
    var failAdd = false
    var holdPermission = false
    var holdAdd = false
    var holdFirstSettings = false
    var authorizationAfterRequest: MorningInvitationAuthorization?
    private var settingsContinuation: CheckedContinuation<Void, Never>?
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    private var addContinuation: CheckedContinuation<Void, Never>?

    init(authorization: MorningInvitationAuthorization = .authorized) { self.authorization = authorization }
    func settings() async -> MorningInvitationNotificationSettings {
        if holdFirstSettings {
            holdFirstSettings = false
            await withCheckedContinuation { settingsContinuation = $0 }
        }
        return .init(authorization: authorization, alertsEnabled: authorization == .authorized, soundsEnabled: authorization == .authorized)
    }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if holdPermission { return await withCheckedContinuation { permissionContinuation = $0 } }
        if let authorizationAfterRequest { authorization = authorizationAfterRequest }
        return authorization == .authorized
    }
    func pendingInvitation() async -> MorningInvitationPendingRequest? { pending }
    func add(_ invitation: MorningInvitation, sound: Bool) async throws {
        if failAdd { throw InvitationFixtureError.add }
        if holdAdd { await withCheckedContinuation { addContinuation = $0 } }
        added.append(invitation)
        pending = .init(payload: invitation.payload, scheduledAt: invitation.scheduledAt)
    }
    func removePendingInvitation() async { if !ignoreRemoval { pending = nil } }
    func removeDeliveredInvitation() async {
        deliveredRemovalCount += 1
        if !ignoreRemoval { delivered = false }
    }
    func hasDeliveredInvitation() async -> Bool { delivered }
    func waitForPermission() async { while permissionContinuation == nil { await Task.yield() } }
    func waitForAdd() async { while addContinuation == nil { await Task.yield() } }
    func waitForSettings() async { while settingsContinuation == nil { await Task.yield() } }
    func completeSettings() {
        settingsContinuation?.resume()
        settingsContinuation = nil
    }
    func completePermission(authorization: MorningInvitationAuthorization) {
        self.authorization = authorization
        permissionContinuation?.resume(returning: authorization == .authorized)
        permissionContinuation = nil
    }
    func completeAdd() {
        holdAdd = false
        addContinuation?.resume()
        addContinuation = nil
    }
}
