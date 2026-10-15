import AuthenticationServices
import Foundation
import MorningApple
import MorningCore
import Observation
import UIKit

/// One explicit, foreground Gmail read. Credentials and counts live only for this
/// screen; a website session or opening Mail never authorizes this controller.
@MainActor @Observable
final class GmailConnectionController {
    private(set) var snapshot: GmailInboxSnapshot?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var hasSession = false
    @ObservationIgnored private let service = GmailConnectionService()
    @ObservationIgnored private var session: GmailAccessSession?
    @ObservationIgnored private var authentication: ASWebAuthenticationSession?
    @ObservationIgnored private var callback: CheckedContinuation<URL, any Error>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var presenter: GmailAuthenticationPresenter?
    @ObservationIgnored private var privacyState: LocalDataControlState?

    var configurationError: String? {
        do { _ = try configuration(); return nil }
        catch { return safeMessage(error) }
    }

    func connect() {
        guard !isBusy, UIApplication.shared.applicationState == .active else { return }
        // Resolve configuration and an actual foreground window before opening consent.
        do {
            let configuration = try configuration()
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive })
                .flatMap(\.windows).first(where: \.isKeyWindow) else {
                throw GmailPresentationError.noWindow
            }
            let privacy = try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess { $0 }
            clearLocal()
            privacyState = privacy; presenter = GmailAuthenticationPresenter(window: window)
            let token = attempt
            isBusy = true
            task = Task { [weak self] in
                guard let self else { return }
                defer { if attempt == token { isBusy = false; task = nil; presenter = nil } }
                do {
                    try requireCurrent(token)
                    let request = try GmailAuthorizationRequest(configuration: configuration)
                    let url = try await authorizationCallback(for: request, token: token)
                    try requireCurrent(token)
                    let granted = try await service.completeAuthorization(request, callbackURL: url)
                    try requireCurrent(token)
                    session = granted; hasSession = true
                    let value = try await service.inboxUnreadCount(session: granted)
                    try requireCurrent(token)
                    snapshot = value
                } catch {
                    guard attempt == token else { return }
                    // A failed read cannot leave an earlier count or an ambiguous grant.
                    session = nil; hasSession = false; snapshot = nil
                    errorMessage = safeMessage(error)
                }
            }
        } catch { clearLocal(); errorMessage = safeMessage(error) }
    }

    func refresh() {
        guard !isBusy, let session, UIApplication.shared.applicationState == .active else { return }
        let token = attempt
        snapshot = nil; errorMessage = nil; isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { if attempt == token { isBusy = false; task = nil } }
            do {
                try requireCurrent(token)
                let value = try await service.inboxUnreadCount(session: session)
                try requireCurrent(token)
                snapshot = value
            } catch {
                guard attempt == token else { return }
                self.session = nil; hasSession = false; snapshot = nil
                errorMessage = safeMessage(error)
            }
        }
    }

    /// Local removal only. Google account grants are managed separately by the owner.
    func clearLocal() {
        attempt = UUID()
        task?.cancel(); task = nil
        authentication?.cancel(); authentication = nil
        let pending = callback; callback = nil
        pending?.resume(throwing: CancellationError())
        session = nil; hasSession = false; snapshot = nil; errorMessage = nil
        privacyState = nil; presenter = nil; isBusy = false
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
        return String(localized: "Gmail is unavailable. Try connecting again from this screen.")
    }
}

private enum GmailPresentationError: Error { case noWindow, failed }

@MainActor
private final class GmailAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
