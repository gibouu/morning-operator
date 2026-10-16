import Foundation
import Observation
import Security
import MorningCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Deliberately excludes provider bodies, prompts and credentials from errors shown or logged.
public enum MoreLanguageModelError: LocalizedError, Sendable, Equatable {
    case unavailable, invalidKey, credentialStorageUnavailable, inputTooLong
    case unauthorized, rateLimited, requestFailed, timedOut, invalidResponse, incompleteResponse, refused

    public var errorDescription: String? {
        let french = AppLanguage.isFrench
        switch self {
        case .unavailable: return french ? "Aucun modèle n’est disponible. Activez Apple Intelligence ou configurez OpenAI dans les réglages." : "No model is available. Enable Apple Intelligence or configure OpenAI in settings."
        case .invalidKey: return french ? "Vérifiez la clé OpenAI saisie." : "Check the OpenAI key you entered."
        case .credentialStorageUnavailable: return french ? "La configuration sécurisée est inaccessible. Déverrouillez l’appareil puis réessayez." : "Secure configuration is unavailable. Unlock the device and try again."
        case .inputTooLong: return french ? "Cette demande dépasse la taille autorisée pour le modèle." : "This request exceeds the model input limit."
        case .unauthorized: return french ? "OpenAI a refusé cette clé ou l’accès au modèle. Vérifiez la configuration." : "OpenAI refused this key or model access. Check configuration."
        case .rateLimited: return french ? "La limite OpenAI est atteinte. Vérifiez le quota du compte puis réessayez." : "The OpenAI limit was reached. Check the account quota and try again."
        case .requestFailed: return french ? "Le modèle n’a pas pu terminer cette demande. Réessayez quand la connexion est disponible." : "The model could not complete this request. Try again when connected."
        case .timedOut: return french ? "Le modèle a mis trop de temps à répondre. Réessayez." : "The model took too long to respond. Try again."
        case .invalidResponse: return french ? "Le modèle a renvoyé une réponse inexploitable." : "The model returned an unusable response."
        case .incompleteResponse: return french ? "La réponse du modèle est incomplète. Réduisez la demande puis réessayez." : "The model response is incomplete. Shorten the request and try again."
        case .refused: return french ? "Le modèle n’a pas accepté cette demande. Reformulez-la." : "The model declined this request. Rephrase it."
        }
    }
}

@MainActor
protocol MoreModelCredentialStorage {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func clear() throws
}

private struct MoreModelKeychainStorage: MoreModelCredentialStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "MorningOperator") + ".openai",
         kSecAttrAccount as String: "explicit-model-configuration-v1",
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count <= 4_096 else {
            throw MoreLanguageModelError.credentialStorageUnavailable
        }
        return data
    }

    func save(_ data: Data) throws {
        guard data.count <= 4_096 else { throw MoreLanguageModelError.credentialStorageUnavailable }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw MoreLanguageModelError.credentialStorageUnavailable }
        guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
            throw MoreLanguageModelError.credentialStorageUnavailable
        }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MoreLanguageModelError.credentialStorageUnavailable
        }
    }
}

private struct MoreModelCredential: Codable, CustomStringConvertible, CustomDebugStringConvertible {
    let apiKey: String
    var enabled: Bool
    var description: String { "MoreModelCredential(redacted)" }
    var debugDescription: String { description }
}

/// Closed composition for synthetic QA and explicitly local diagnostics.
private struct MoreModelLocalOnlyStorage: MoreModelCredentialStorage {
    func load() throws -> Data? { nil }
    func save(_ data: Data) throws { throw MoreLanguageModelError.unavailable }
    func clear() throws { }
}

private final class MoreModelNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// One explicit route for understanding and generation. Construction never contacts OpenAI.
/// Cloud requests contain only the caller's bounded text; no recordings or images are uploaded.
@MainActor
@Observable
public final class MoreLanguageModel {
    public static let shared = MoreLanguageModel()
    public static let openAIModel = "gpt-5-mini-2025-08-07"
    public private(set) var usesOpenAI = false
    public var isAvailable: Bool { !credentialStorageFailed && (usesOpenAI || localAvailable()) }
    public var summary: String {
        let french = AppLanguage.isFrench
        if credentialStorageFailed { return MoreLanguageModelError.credentialStorageUnavailable.localizedDescription }
        if usesOpenAI {
            return french ? "OpenAI GPT-5 mini est activé. Les textes utiles à l’analyse et à la conversation sont envoyés à OpenAI. Les vidéos restent sur l’appareil." : "OpenAI GPT-5 mini is enabled. Text needed for analysis and conversation is sent to OpenAI. Videos stay on this device."
        }
        return localAvailable()
            ? (french ? "Le modèle Apple fonctionne sur cet appareil. Aucun texte n’est envoyé à OpenAI." : "The Apple model runs on this device. No text is sent to OpenAI.")
            : (french ? "Le modèle Apple est indisponible. Configurez OpenAI pour activer l’analyse et la conversation intelligentes." : "The Apple model is unavailable. Configure OpenAI to enable intelligent analysis and conversation.")
    }

    typealias Transport = @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias LocalGenerator = @MainActor (String, String, Int) async throws -> String
    static let maximumRequestBytes = 131_072
    static let maximumResponseBytes = 262_144
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    @ObservationIgnored private let storage: any MoreModelCredentialStorage
    @ObservationIgnored private let transport: Transport
    @ObservationIgnored private let localAvailable: @MainActor () -> Bool
    @ObservationIgnored private let localGenerate: LocalGenerator
    @ObservationIgnored private let privacyEpoch: @MainActor () throws -> UUID?
    @ObservationIgnored private var credential: MoreModelCredential?
    private var credentialStorageFailed = false
    @ObservationIgnored private var generation = UUID()
    /// Identifies the explicit route choice without exposing its credentials.
    public var configurationID: UUID { generation }
    @ObservationIgnored private var pending: [UUID: Task<String, any Error>] = [:]

    /// Never reads Keychain or provisioning variables, and cannot enable a remote route.
    /// A supplied workspace still participates in Forget invalidation.
    public static func localOnly(directory: URL? = nil) -> MoreLanguageModel {
        .init(storage: MoreModelLocalOnlyStorage(), transport: { _ in throw MoreLanguageModelError.unavailable },
              localAvailable: Self.appleAvailable, localGenerate: Self.generateLocally, privacyEpoch: {
                  guard let directory else { return nil }
                  let state = try LocalDataControl(directory: directory).status()
                  guard !state.forgetPending else { throw MoreLanguageModelError.unavailable }
                  return state.generation
              })
    }

    struct RequestContext: Equatable, Sendable {
        let configurationID: UUID
        let privacyEpoch: UUID?
        let usesOpenAI: Bool
    }

    func requestContext() throws -> RequestContext {
        try Task.checkCancellation()
        guard !credentialStorageFailed else { throw MoreLanguageModelError.credentialStorageUnavailable }
        return .init(configurationID: generation, privacyEpoch: try accessEpoch(), usesOpenAI: usesOpenAI)
    }

    func requireCurrent(_ context: RequestContext) throws {
        try Task.checkCancellation()
        do { guard try requestContext() == context else { throw CancellationError() } }
        catch { throw CancellationError() }
    }

    public convenience init() {
        self.init(storage: MoreModelKeychainStorage(), transport: Self.send,
                  localAvailable: Self.appleAvailable, localGenerate: Self.generateLocally,
                  privacyEpoch: {
                      let state = try LocalDataControl(directory: LocalDataControl.defaultDirectory).status()
                      guard !state.forgetPending else { throw MoreLanguageModelError.unavailable }
                      return state.generation
                  })
        #if DEBUG
        // Development provisioning is an explicit opt-in; ordinary builds never read these values.
        let environment = ProcessInfo.processInfo.environment
        if credential == nil, environment["MORE_OPENAI_ENABLED"] == "1",
           let key = environment["MORE_OPENAI_API_KEY"] {
            try? configureOpenAI(apiKey: key, enabled: true)
        }
        #endif
    }

    /// Injection boundary keeps protocol tests away from the live network and Keychain.
    init(storage: any MoreModelCredentialStorage, transport: @escaping Transport,
         localAvailable: @escaping @MainActor () -> Bool = { false },
         localGenerate: @escaping LocalGenerator = { _, _, _ in throw MoreLanguageModelError.unavailable },
         privacyEpoch: @escaping @MainActor () throws -> UUID? = { nil }) {
        self.storage = storage
        self.transport = transport
        self.localAvailable = localAvailable
        self.localGenerate = localGenerate
        self.privacyEpoch = privacyEpoch
        do {
            if let data = try storage.load() {
                guard let saved = try? JSONDecoder().decode(MoreModelCredential.self, from: data),
                      Self.validKey(saved.apiKey) else { throw MoreLanguageModelError.credentialStorageUnavailable }
                credential = saved
                usesOpenAI = saved.enabled
            }
        } catch { credentialStorageFailed = true }
    }

    public func configureOpenAI(apiKey: String, enabled: Bool) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validKey(key) else { throw MoreLanguageModelError.invalidKey }
        invalidateRequests()
        let next = MoreModelCredential(apiKey: key, enabled: enabled)
        do { try storage.save(JSONEncoder().encode(next)) }
        catch { throw MoreLanguageModelError.credentialStorageUnavailable }
        credential = next
        credentialStorageFailed = false
        usesOpenAI = enabled
    }

    public func useLocal() throws {
        invalidateRequests()
        guard var saved = credential else {
            // If startup could not read the selection, explicit local mode must remove it
            // successfully before another launch can restore an unknown cloud selection.
            if credentialStorageFailed {
                do { try storage.clear() }
                catch { throw MoreLanguageModelError.credentialStorageUnavailable }
            }
            credentialStorageFailed = false
            usesOpenAI = false
            return
        }
        saved.enabled = false
        do { try storage.save(JSONEncoder().encode(saved)) }
        catch { throw MoreLanguageModelError.credentialStorageUnavailable }
        credential = saved
        credentialStorageFailed = false
        usesOpenAI = false
    }

    public func forget() throws {
        invalidateRequests()
        do { try storage.clear() }
        catch { throw MoreLanguageModelError.credentialStorageUnavailable }
        credential = nil
        credentialStorageFailed = false
        usesOpenAI = false
    }

    public func generate(instructions: String, prompt: String, maximumResponseTokens: Int,
                         schema: ComposioJSONValue? = nil, expectedConfigurationID: UUID? = nil,
                         expectedPrivacyGeneration: UUID? = nil) async throws -> String {
        try Task.checkCancellation()
        guard !credentialStorageFailed else { throw MoreLanguageModelError.credentialStorageUnavailable }
        if let expectedConfigurationID, expectedConfigurationID != generation { throw CancellationError() }
        let epoch = try accessEpoch()
        // A pinned configuration also pins an absent privacy epoch. Forget may
        // create the first epoch after the caller captured its source context.
        if expectedConfigurationID != nil || expectedPrivacyGeneration != nil {
            guard expectedPrivacyGeneration == epoch else { throw CancellationError() }
        }
        guard instructions.utf8.count + prompt.utf8.count <= Self.maximumRequestBytes,
              maximumResponseTokens > 0, maximumResponseTokens <= 8_192 else {
            throw MoreLanguageModelError.inputTooLong
        }
        let route = generation
        let id = UUID()
        let task: Task<String, any Error>
        if usesOpenAI {
            guard let key = credential?.apiKey else { throw MoreLanguageModelError.unavailable }
            let request = try Self.request(key: key, instructions: instructions, prompt: prompt,
                                           maximumResponseTokens: maximumResponseTokens, schema: schema)
            let transport = transport
            task = Task { @MainActor in
                do {
                    try Task.checkCancellation()
                    guard self.generation == route, try self.accessEpoch() == epoch else { throw CancellationError() }
                    let (data, response) = try await transport(request)
                    try Task.checkCancellation()
                    return try Self.output(data: data, response: response)
                } catch is CancellationError { throw CancellationError() }
                catch let error as MoreLanguageModelError { throw error }
                catch let error as URLError {
                    if error.code == .cancelled { throw CancellationError() }
                    throw error.code == .timedOut ? MoreLanguageModelError.timedOut : .requestFailed
                } catch { throw MoreLanguageModelError.requestFailed }
            }
        } else {
            guard localAvailable() else { throw MoreLanguageModelError.unavailable }
            let generate = localGenerate
            task = Task { @MainActor in
                do {
                    try Task.checkCancellation()
                    guard self.generation == route, try self.accessEpoch() == epoch else { throw CancellationError() }
                    return try await generate(instructions, prompt, maximumResponseTokens)
                }
                catch is CancellationError { throw CancellationError() }
                catch { throw MoreLanguageModelError.requestFailed }
            }
        }
        pending[id] = task
        defer { pending[id] = nil }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard route == generation else { throw CancellationError() }
        do { guard try accessEpoch() == epoch else { throw CancellationError() } }
        catch { throw CancellationError() }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.utf8.count <= Self.maximumResponseBytes else { throw MoreLanguageModelError.invalidResponse }
        return result
    }

    private func invalidateRequests() {
        generation = UUID()
        for task in pending.values { task.cancel() }
        pending.removeAll()
    }

    private func accessEpoch() throws -> UUID? {
        do { return try privacyEpoch() }
        catch { throw MoreLanguageModelError.unavailable }
    }

    private static func validKey(_ key: String) -> Bool {
        key.hasPrefix("sk-") && (20...512).contains(key.utf8.count)
            && key.utf8.allSatisfy { (33...126).contains($0) }
    }

    private static func request(key: String, instructions: String, prompt: String,
                                maximumResponseTokens: Int, schema: ComposioJSONValue?) throws -> URLRequest {
        let format: ComposioJSONValue
        if let schema {
            guard schema.objectValue != nil else { throw MoreLanguageModelError.invalidResponse }
            format = .object(["type": .string("json_schema"), "name": .string("more_response"),
                              "strict": .bool(true), "schema": schema])
        } else { format = .object(["type": .string("text")]) }
        let body: ComposioJSONValue = .object([
            "model": .string(openAIModel), "instructions": .string(instructions), "input": .string(prompt),
            "store": .bool(false), "reasoning": .object(["effort": .string("minimal")]),
            // The API budget includes hidden reasoning, unlike Foundation Models' visible output budget.
            "max_output_tokens": .number(Decimal(min(16_384, max(2_048, maximumResponseTokens * 4)))),
            "text": .object(["format": format])])
        let data = try JSONEncoder().encode(body)
        guard data.count <= maximumRequestBytes else { throw MoreLanguageModelError.inputTooLong }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    private static func output(data: Data, response: HTTPURLResponse) throws -> String {
        guard response.url == endpoint, data.count <= maximumResponseBytes else {
            throw MoreLanguageModelError.invalidResponse
        }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw MoreLanguageModelError.unauthorized
        case 429: throw MoreLanguageModelError.rateLimited
        default: throw MoreLanguageModelError.requestFailed
        }
        guard let root = try? JSONDecoder().decode(ComposioJSONValue.self, from: data).objectValue else {
            throw MoreLanguageModelError.invalidResponse
        }
        guard root["status"]?.stringValue == "completed" else {
            throw MoreLanguageModelError.incompleteResponse
        }
        guard let output = root["output"]?.arrayValue else { throw MoreLanguageModelError.invalidResponse }
        var texts: [String] = []
        for item in output {
            guard let message = item.objectValue, message["type"]?.stringValue == "message",
                  message["role"]?.stringValue == "assistant",
                  let content = message["content"]?.arrayValue else { continue }
            for part in content {
                let object = part.objectValue
                if object?["type"]?.stringValue == "refusal" { throw MoreLanguageModelError.refused }
                if object?["type"]?.stringValue == "output_text", let text = object?["text"]?.stringValue {
                    texts.append(text)
                }
            }
        }
        guard !texts.isEmpty else { throw MoreLanguageModelError.invalidResponse }
        return texts.joined(separator: "\n")
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: MoreModelNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              response.expectedContentLength <= Int64(maximumResponseBytes) else {
            throw MoreLanguageModelError.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else { throw MoreLanguageModelError.invalidResponse }
            data.append(byte)
        }
        return (data, http)
    }

    private static func appleAvailable() -> Bool {
        #if canImport(FoundationModels)
        SystemLanguageModel.default.isAvailable
        #else
        false
        #endif
    }

    private static func generateLocally(instructions: String, prompt: String, maximumResponseTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let response = try await session.respond(to: prompt,
            options: GenerationOptions(temperature: 0, maximumResponseTokens: min(maximumResponseTokens, 4_096)))
        return response.content
        #else
        throw MoreLanguageModelError.unavailable
        #endif
    }
}
