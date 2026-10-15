import AuthenticationServices
import Foundation
import MorningApple
import MorningCore
import Observation
import UIKit
import UniformTypeIdentifiers

/// Foreground Gmail reader. Only its refresh credential is kept securely; message
/// content, access sessions and local replies clear when this reader leaves.
@MainActor @Observable
final class GmailConnectionController {
    private(set) var snapshot: GmailInboxSnapshot?
    private(set) var unreadMessages: GmailUnreadMessagesSnapshot?
    private(set) var selectedMessage: GmailMessage?
    private(set) var selectedMessageID: String?
    private(set) var replyText = ""
    private(set) var replyGuidance = ""
    private(set) var replyNotice: String?
    private(set) var isBusy = false
    private(set) var isPreparingReply = false
    private(set) var errorMessage: String?
    private(set) var hasSession = false
    private(set) var hasSavedConnection = false
    private(set) var canRetryConnection = false
    @ObservationIgnored private let service = GmailConnectionService()
    @ObservationIgnored private let replyService = GmailReplyDraftService()
    @ObservationIgnored private var session: GmailAccessSession?
    @ObservationIgnored private var authentication: ASWebAuthenticationSession?
    @ObservationIgnored private var callback: CheckedContinuation<URL, any Error>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var presenter: GmailAuthenticationPresenter?
    @ObservationIgnored private var privacyState: LocalDataControlState?
    @ObservationIgnored private var restorationAttempted = false

    var hasMessageAccess: Bool { session?.canReadMessages == true }
    var isShowingMessage: Bool { selectedMessageID != nil }
    var replyUnavailabilityReason: String? { replyService.unavailabilityReason }

    var configurationError: String? {
        do { _ = try configuration(); return nil }
        catch { return safeMessage(error) }
    }

    /// Only this explicit tap opens Google consent. A successful readonly/offline
    /// grant is saved before Inbox reads, while its privacy generation is current.
    func connect() {
        guard !isBusy, UIApplication.shared.applicationState == .active else { return }
        do {
            let configuration = try configuration()
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { throw GmailPresentationError.noWindow }
            let privacy = try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess { $0 }
            clearLocal()
            privacyState = privacy; restorationAttempted = true
            presenter = GmailAuthenticationPresenter(window: window)
            let token = attempt
            isBusy = true
            task = Task { [weak self] in
                guard let self else { return }
                defer { finishOperation(token) }
                do {
                    try requireCurrent(token)
                    let request = try GmailAuthorizationRequest(configuration: configuration, access: .readMessages)
                    let url = try await authorizationCallback(for: request, token: token)
                    try requireCurrent(token)
                    let granted = try await service.completeAuthorization(request, callbackURL: url)
                    try requireCurrent(token)
                    try service.saveConnection(session: granted, generation: privacy.generation)
                    try requireCurrent(token)
                    hasSavedConnection = true
                    session = granted; hasSession = true
                    try await readInbox(using: granted, token: token)
                } catch { connectionFailed(error, token: token) }
            }
        } catch { clearLocal(); errorMessage = safeMessage(error) }
    }

    /// Opening or foregrounding this screen can refresh a saved connection, but
    /// must never open a consent browser or create a new grant.
    func restoreIfNeeded() {
        guard !restorationAttempted else { return }
        restoreSavedConnection()
    }

    func refresh() {
        guard !isBusy, UIApplication.shared.applicationState == .active else { return }
        guard let session, session.expiresAt.timeIntervalSinceNow > 30 else {
            restoreSavedConnection()
            return
        }
        let token = beginOperation()
        clearMessageContent(); snapshot = nil; unreadMessages = nil; canRetryConnection = false
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(token) }
            do { try await readInbox(using: session, token: token) }
            catch { connectionFailed(error, token: token) }
        }
    }

    private func restoreSavedConnection() {
        guard !isBusy, UIApplication.shared.applicationState == .active else { return }
        do {
            _ = try configuration()
            let privacy = try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess { $0 }
            clearLocal()
            privacyState = privacy; restorationAttempted = true
            let token = attempt
            isBusy = true
            task = Task { [weak self] in
                guard let self else { return }
                defer { finishOperation(token) }
                do {
                    try requireCurrent(token)
                    let restored = try await service.restoreConnection(generation: privacy.generation)
                    try requireCurrent(token)
                    guard let restored else {
                        hasSavedConnection = false
                        return
                    }
                    hasSavedConnection = true
                    session = restored; hasSession = true
                    try await readInbox(using: restored, token: token)
                } catch { restorationFailed(error, token: token) }
            }
        } catch {
            clearLocal(); restorationAttempted = true
            errorMessage = safeMessage(error)
        }
    }

    private func readInbox(using session: GmailAccessSession, token: UUID) async throws {
        try requireCurrent(token)
        let value = try await service.inboxUnreadCount(session: session)
        try requireCurrent(token)
        snapshot = value
        let messages = try await service.unreadInboxMessages(session: session)
        try requireCurrent(token)
        unreadMessages = messages
    }

    /// Deleting the saved connection is separate from clearing the reader's memory.
    func disconnect() {
        clearLocal()
        restorationAttempted = true
        do {
            try service.disconnect()
            hasSavedConnection = false; canRetryConnection = false
        } catch {
            // A failed deletion must not claim the saved credential is gone.
            canRetryConnection = true
            errorMessage = safeMessage(error)
        }
    }

    func openMessage(id: String) {
        guard !isBusy, let session, session.canReadMessages,
              unreadMessages?.messages.contains(where: { $0.id == id }) == true,
              UIApplication.shared.applicationState == .active else { return }
        let token = beginOperation()
        clearMessageContent(); selectedMessageID = id
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(token) }
            do {
                try requireCurrent(token)
                var readableSession = session
                if session.expiresAt.timeIntervalSinceNow <= 30 {
                    guard let privacyState,
                          let restored = try await service.restoreConnection(generation: privacyState.generation) else {
                        hasSavedConnection = false
                        throw GmailConnectionError.savedConnectionInvalid
                    }
                    try requireCurrent(token)
                    self.session = restored; hasSession = true; hasSavedConnection = true
                    readableSession = restored
                }
                let message = try await service.message(id: id, session: readableSession)
                try requireCurrent(token)
                guard selectedMessageID == id else { throw CancellationError() }
                selectedMessage = message
            } catch { messageReadFailed(error, token: token) }
        }
    }

    func closeMessage() {
        attempt = UUID(); task?.cancel(); task = nil
        isBusy = false; isPreparingReply = false; errorMessage = nil
        clearMessageContent()
    }

    func editReply(_ value: String) { replyText = String(value.prefix(8_000)); replyNotice = nil }
    func editGuidance(_ value: String) { replyGuidance = String(value.prefix(600)); replyNotice = nil }

    func prepareReply() {
        guard !isBusy, let message = selectedMessage,
              !message.bodyUnavailable, !message.bodyWasTruncated,
              UIApplication.shared.applicationState == .active else { return }
        if let reason = replyUnavailabilityReason { errorMessage = reason; return }
        let token = beginOperation()
        isPreparingReply = true
        let guidance = replyGuidance
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(token) }
            do {
                try requireCurrent(token)
                let draft = try await replyService.draftReply(sender: message.sender, subject: message.subject,
                    body: message.plainTextBody, guidance: guidance)
                try requireCurrent(token)
                guard selectedMessageID == message.id else { throw CancellationError() }
                replyText = draft
                replyNotice = String(localized: "Prepared on this iPhone. Review before copying.")
            } catch {
                guard attempt == token else { return }
                if error is CancellationError { clearLocal(); return }
                if let known = error as? GmailReplyDraftError { errorMessage = known.localizedDescription }
                else { errorMessage = String(localized: "A reply could not be prepared. You can write one below.") }
            }
        }
    }

    func copyReply() {
        guard !isBusy, !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try requireCurrent(attempt)
            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: replyText]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
            replyNotice = String(localized: "Copied.")
        } catch { clearLocal() }
    }

    /// Parents replace this view on their generation change. This additional check
    /// also clears an idle reader when another local owner changes privacy state.
    func clearIfPrivacyChanged() {
        guard let privacyState else { return }
        do {
            try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess {
                guard $0.generation == privacyState.generation else { throw CancellationError() }
            }
        } catch { clearLocal(); hasSavedConnection = false }
    }

    /// Clears volatile content and attempts only. It never deletes Keychain access.
    func clearLocal() {
        attempt = UUID()
        task?.cancel(); task = nil
        authentication?.cancel(); authentication = nil
        let pending = callback; callback = nil
        pending?.resume(throwing: CancellationError())
        session = nil; hasSession = false; snapshot = nil; unreadMessages = nil
        clearMessageContent(); errorMessage = nil
        privacyState = nil; presenter = nil; isBusy = false; isPreparingReply = false
        canRetryConnection = false; restorationAttempted = false
    }

    private func clearMessageContent() {
        selectedMessageID = nil; selectedMessage = nil
        replyText = ""; replyGuidance = ""; replyNotice = nil
    }

    private func beginOperation() -> UUID {
        task?.cancel(); attempt = UUID()
        errorMessage = nil; replyNotice = nil; isBusy = true
        return attempt
    }

    private func finishOperation(_ token: UUID) {
        guard attempt == token else { return }
        isBusy = false; isPreparingReply = false; task = nil; presenter = nil
    }

    private func connectionFailed(_ error: any Error, token: UUID) {
        guard attempt == token else { return }
        do { try requireCurrent(token) }
        catch { clearLocal(); return }
        if error is CancellationError { clearLocal(); return }
        let saved = hasSavedConnection
        clearLocal(); restorationAttempted = true
        hasSavedConnection = saved
        canRetryConnection = saved
        errorMessage = safeMessage(error)
    }

    private func restorationFailed(_ error: any Error, token: UUID) {
        guard attempt == token else { return }
        do { try requireCurrent(token) }
        catch { clearLocal(); return }
        if error is CancellationError { clearLocal(); return }
        clearLocal(); restorationAttempted = true; canRetryConnection = true
        if let known = error as? GmailConnectionError,
           [.savedConnectionInvalid, .connectionChanged].contains(known) {
            hasSavedConnection = false
        } else {
            // A transient restore/read failure leaves the saved credential intact.
            // Retry refreshes it; it never starts another consent browser.
            canRetryConnection = true
        }
        errorMessage = safeMessage(error)
    }

    /// A removed or unreadable message does not revoke an otherwise valid grant.
    /// Keep the existing timestamped list so the owner can choose another message.
    private func messageReadFailed(_ error: any Error, token: UUID) {
        guard attempt == token else { return }
        do { try requireCurrent(token) }
        catch { clearLocal(); return }
        if error is CancellationError {
            clearLocal()
        } else if let known = error as? GmailConnectionError,
                  [.permissionDenied, .sessionExpired, .readAccessRequired, .savedConnectionInvalid, .connectionChanged].contains(known) {
            connectionFailed(known, token: token)
        } else {
            clearMessageContent()
            canRetryConnection = hasSavedConnection
            if let known = error as? GmailConnectionError,
               [.invalidResponse, .redirectRejected].contains(known) {
                errorMessage = String(localized: "This message could not be read. Choose another message or refresh the Inbox.")
            } else {
                errorMessage = safeMessage(error)
            }
        }
    }

    private func configuration() throws -> GmailOAuthConfiguration {
        let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return try GmailOAuthConfiguration(
            clientID: Bundle.main.object(forInfoDictionaryKey: "MOREGoogleClientID") as? String ?? "",
            registeredURLSchemes: schemes)
    }

    private func requireCurrent(_ token: UUID) throws {
        try Task.checkCancellation()
        guard attempt == token, UIApplication.shared.applicationState != .background,
              let privacyState else { throw CancellationError() }
        try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess {
            guard $0.generation == privacyState.generation else { throw CancellationError() }
        }
    }

    private func authorizationCallback(for request: GmailAuthorizationRequest, token: UUID) async throws -> URL {
        try requireCurrent(token)
        return try await withCheckedThrowingContinuation { continuation in
            callback = continuation
            let browser = ASWebAuthenticationSession(url: request.authorizationURL,
                callbackURLScheme: request.callbackScheme) { [weak self] url, error in
                Task { @MainActor in
                    guard let self, self.attempt == token, let waiting = self.callback else { return }
                    self.callback = nil; self.authentication = nil
                    if let url { waiting.resume(returning: url) }
                    else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        waiting.resume(throwing: CancellationError())
                    } else { waiting.resume(throwing: GmailPresentationError.failed) }
                }
            }
            browser.presentationContextProvider = presenter
            browser.prefersEphemeralWebBrowserSession = true
            authentication = browser
            if !browser.start() {
                callback = nil; authentication = nil
                continuation.resume(throwing: GmailPresentationError.failed)
            }
        }
    }

    private func safeMessage(_ error: any Error) -> String {
        if error is CancellationError { return String(localized: "Gmail connection cancelled.") }
        if let known = error as? GmailConnectionError { return known.localizedDescription }
        return String(localized: "Gmail is unavailable. Try again from this screen.")
    }
}

private enum GmailPresentationError: Error { case noWindow, failed }

@MainActor
private final class GmailAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
