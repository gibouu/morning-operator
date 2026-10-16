import CryptoKit
import Foundation

/// Execution is chosen for the operation, not inferred from an installed app or its sign-in.
public enum IntegrationRoute: String, Codable, CaseIterable, Sendable, Identifiable {
    case nativeIOS, browser, api
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .nativeIOS: AppLanguage.localized("On this iPhone", bundle: .module)
        case .browser: AppLanguage.localized("Browser", bundle: .module)
        case .api: AppLanguage.localized("Connected accounts", bundle: .module)
        }
    }
}

public enum IntegrationTargetError: Error, LocalizedError, Equatable {
    case invalidShortcut, invalidAPIAction, invalidArguments
    public var errorDescription: String? {
        switch self {
        case .invalidShortcut: "Choose an existing shortcut name and keep its input within 1,024 bytes."
        case .invalidAPIAction: "Choose a connected account and a supported service action."
        case .invalidArguments: "Action parameters must be a JSON object within 32 KiB."
        }
    }
}

extension RoutineStepTarget {
    public var isConnectedAction: Bool {
        switch self {
        case .shortcut, .connectedAPI, .googleCalendarDay, .calendlyDay, .outlookInbox: true
        case .externalApp, .inAppWeb: false
        }
    }
    /// Resolve legacy Instagram choices before describing the execution route.
    /// Other third-party app links remain handoffs, not native integrations.
    public var integrationRoute: IntegrationRoute? {
        switch routineExecutionTarget {
        case .shortcut: .nativeIOS
        case .connectedAPI, .googleCalendarDay, .calendlyDay, .outlookInbox: .api
        case .inAppWeb: .browser
        case .externalApp(let app, _):
            switch app {
            case .messages, .mail, .calendar, .maps: .nativeIOS
            case .whatsapp, .instagram, .safari: nil
            }
        }
    }

    public func validateIntegration() throws {
        switch self {
        case let .shortcut(name, input):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  name.count <= 128, name.utf8.count <= 512,
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), input.utf8.count <= 1_024 else {
                throw IntegrationTargetError.invalidShortcut
            }
        case let .connectedAPI(service, account, tool, arguments):
            func identifier(_ text: String, maximum: Int) -> Bool {
                !text.isEmpty && text.utf8.count <= maximum && text.allSatisfy {
                    $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
                }
            }
            guard identifier(service, maximum: 80), identifier(account, maximum: 200),
                  identifier(tool, maximum: 200) else { throw IntegrationTargetError.invalidAPIAction }
            guard arguments.utf8.count <= 32_768,
                  let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)),
                  object is [String: Any] else { throw IntegrationTargetError.invalidArguments }
        case .googleCalendarDay(let target): try target.validate()
        case .calendlyDay(let target): try target.validate()
        case .outlookInbox(let target): try target.validate()
        case .externalApp, .inAppWeb: break
        }
    }
}

/// Stable across pauses/relaunches; one approved step in one run has one provider request.
public enum IntegrationRequestID {
    public static func make(sessionID: UUID, stepID: UUID) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("more.api.v1:\(sessionID.uuidString):\(stepID.uuidString)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
