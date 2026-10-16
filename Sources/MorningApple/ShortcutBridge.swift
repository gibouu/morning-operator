import MorningCore
import Foundation

public enum NativeShortcutOperation: String, Codable, CaseIterable, Sendable, Identifiable {
    case messages, mail, notes, clock, custom
    public var id: String { rawValue }
    public static let configurable: [Self] = [.messages, .mail, .notes, .clock, .custom]
    public var displayName: String {
        switch self {
        case .messages: AppLanguage.localized("Messages", bundle: .module)
        case .mail: AppLanguage.localized("Mail", bundle: .module)
        case .notes: AppLanguage.localized("Notes", bundle: .module)
        case .clock: AppLanguage.localized("Clock", bundle: .module)
        case .custom: AppLanguage.localized("Other shortcut", bundle: .module)
        }
    }
}

public struct ShortcutBridgeRequest: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let operation: NativeShortcutOperation
    public let expiresAt: Date
    public let launchURL: URL
}

public struct ShortcutBridgeOutcome: Sendable, Equatable {
    public enum Status: String, Sendable { case returned, failed, cancelled }
    public let requestID: UUID
    public let operation: NativeShortcutOperation
    public let status: Status
    public let text: String
}

public enum ShortcutBridgeError: LocalizedError, Sendable, Equatable {
    case invalidName, inputTooLarge, alreadyWaiting, invalidCallback, noPendingRequest, expired, resultTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidName: AppLanguage.localized("Enter the exact name of a shortcut you added in Shortcuts (up to 128 characters).", bundle: .module)
        case .inputTooLarge: AppLanguage.localized("Keep shortcut input within 1,024 bytes.", bundle: .module)
        case .alreadyWaiting: AppLanguage.localized("MORE is already waiting for a shortcut. Check its outcome before running another.", bundle: .module)
        case .invalidCallback, .noPendingRequest: AppLanguage.localized("This shortcut return doesn't match a pending request. Nothing was accepted.", bundle: .module)
        case .expired: AppLanguage.localized("The shortcut didn't return in time. Check it in Shortcuts before running it again.", bundle: .module)
        case .resultTooLarge: AppLanguage.localized("The shortcut returned too much text. Limit its output to 8,192 bytes.", bundle: .module)
        }
    }
}

/// A callback confirms a named shortcut returned; it never verifies that a native effect happened.
public struct ShortcutBridge: Sendable {
    public static let inputByteLimit = 1_024
    public static let resultByteLimit = 8_192
    public static let timeout: TimeInterval = 300
    public private(set) var pending: ShortcutBridgeRequest?
    private let callbackScheme: String

    public init(callbackScheme: String = "more") { self.callbackScheme = callbackScheme }

    public static func isValidName(_ value: String) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 128 && name.utf8.count <= 512
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    public mutating func begin(name: String, input: String, operation: NativeShortcutOperation = .custom,
                               now: Date = Date()) throws -> ShortcutBridgeRequest {
        guard pending == nil else { throw ShortcutBridgeError.alreadyWaiting }
        guard Self.isValidName(name) else { throw ShortcutBridgeError.invalidName }
        guard input.utf8.count <= Self.inputByteLimit else { throw ShortcutBridgeError.inputTooLarge }
        guard ["more", "moreqa"].contains(callbackScheme), now.timeIntervalSinceReferenceDate.isFinite else {
            throw ShortcutBridgeError.invalidCallback
        }
        let nonce = UUID()
        func callback(_ path: String) throws -> String {
            var url = URLComponents()
            url.scheme = callbackScheme; url.host = "native-shortcut"; url.path = "/\(path)"
            url.queryItems = [.init(name: "operation", value: operation.rawValue), .init(name: "nonce", value: nonce.uuidString)]
            guard let value = url.url else { throw ShortcutBridgeError.invalidCallback }
            return value.absoluteString
        }
        var url = URLComponents()
        url.scheme = "shortcuts"; url.host = "x-callback-url"; url.path = "/run-shortcut"
        url.queryItems = [.init(name: "name", value: name.trimmingCharacters(in: .whitespacesAndNewlines)),
                          .init(name: "input", value: "text"), .init(name: "text", value: input),
                          .init(name: "x-success", value: try callback("success")),
                          .init(name: "x-error", value: try callback("error")),
                          .init(name: "x-cancel", value: try callback("cancel"))]
        // URL query parsers may treat an unescaped plus as a space.
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let launchURL = url.url else { throw ShortcutBridgeError.invalidCallback }
        let request = ShortcutBridgeRequest(id: nonce, operation: operation,
            expiresAt: now.addingTimeInterval(Self.timeout), launchURL: launchURL)
        pending = request
        return request
    }

    public func recognizes(_ url: URL) -> Bool { url.scheme == callbackScheme && url.host == "native-shortcut" }

    public mutating func accept(_ url: URL, now: Date = Date()) throws -> ShortcutBridgeOutcome {
        guard recognizes(url), url.absoluteString.utf8.count <= 65_536,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              ["/success", "/error", "/cancel"].contains(components.path) else { throw ShortcutBridgeError.invalidCallback }
        guard let request = pending else { throw ShortcutBridgeError.noPendingRequest }
        let items = components.queryItems ?? []
        let allowed: Set<String> = ["operation", "nonce", "result", "errorMessage", "errorCode"]
        guard items.allSatisfy({ allowed.contains($0.name) && $0.value != nil }),
              Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "nonce" })?.value == request.id.uuidString,
              items.first(where: { $0.name == "operation" })?.value == request.operation.rawValue else {
            throw ShortcutBridgeError.invalidCallback
        }
        guard now.timeIntervalSinceReferenceDate.isFinite, now < request.expiresAt,
              now >= request.expiresAt.addingTimeInterval(-Self.timeout) else {
            pending = nil; throw ShortcutBridgeError.expired
        }
        let text = items.first(where: { $0.name == "result" })?.value ?? ""
        guard text.utf8.count <= Self.resultByteLimit,
              items.allSatisfy({ ($0.value?.utf8.count ?? 0) <= Self.resultByteLimit }) else {
            throw ShortcutBridgeError.resultTooLarge
        }
        let status: ShortcutBridgeOutcome.Status
        switch components.path {
        case "/success":
            guard !items.contains(where: { $0.name == "errorMessage" || $0.name == "errorCode" }) else { throw ShortcutBridgeError.invalidCallback }
            status = .returned
        case "/error":
            guard !items.contains(where: { $0.name == "result" }) else { throw ShortcutBridgeError.invalidCallback }
            status = .failed
        default:
            guard items.count == 2 else { throw ShortcutBridgeError.invalidCallback }
            status = .cancelled
        }
        pending = nil
        return ShortcutBridgeOutcome(requestID: request.id, operation: request.operation, status: status, text: text)
    }

    @discardableResult public mutating func expire(at now: Date = Date()) -> Bool {
        guard let pending, now >= pending.expiresAt else { return false }
        self.pending = nil; return true
    }
    public mutating func cancel() { pending = nil }
}
