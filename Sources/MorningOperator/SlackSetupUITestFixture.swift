import Foundation
import MorningApple
#if DEBUG
import CryptoKit
#endif

/// Explicit synthetic UI data. The injected transport has no URLSession or live credential store.
@MainActor enum SlackSetupUITestFixture {
    /// Composition only: the imported draft still has no operation or approval.
    static var integratedJourneyRequested: Bool {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        let workspaces = flags.filter { $0.hasPrefix("--ui-testing-workspace=") }
        return flags.contains("--ui-testing") && flags.contains("--ui-testing-integrated-three-moments") &&
            flags.contains("--ui-testing-slack-setup") && GmailAttentionUITestFixture.isRequested &&
            !flags.contains("--ui-testing-slack-reply") && workspaces.count == 1 &&
            UUID(uuidString: String(workspaces[0].dropFirst("--ui-testing-workspace=".count))) != nil
        #else
        return false
        #endif
    }

    static func integratedServiceIfRequested() -> ComposioService? {
        integratedJourneyRequested ? serviceIfRequested() : nil
    }

    static var integratedDiagnostic: String {
        #if DEBUG
        guard integratedJourneyRequested else { return "" }
        return "History reads: \(historyReads); simulated send attempts: \(sendAttempts); received body SHA256: \(receivedBodySHA256 ?? "none")"
        #else
        ""
        #endif
    }

    static func integratedDraftsIfRequested() -> SlackReplyDraftService? {
        #if DEBUG
        guard integratedJourneyRequested else { return nil }
        return .syntheticIntegratedJourneyIfRequested()
        #else
        return nil
        #endif
    }

    static func serviceIfRequested() -> ComposioService? {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        let catalog = flags.contains("--ui-testing-connections-catalog")
        let unavailable = flags.contains("--ui-testing-connections-unavailable")
        guard flags.contains("--ui-testing"), flags.contains("--ui-testing-slack-setup") || catalog || unavailable else { return nil }
        let empty = flags.contains("--ui-testing-slack-empty") || catalog || unavailable
        let integrated = integratedJourneyRequested
        if integrated { historyReads = 0; sendAttempts = 0; receivedBodySHA256 = nil }
        let connection = "ca_slack_synthetic_setup", cursor = "opaque-fixture-page-two"
        return ComposioService(baseURL: URL(string: "https://synthetic-slack.invalid")!,
            tokenStore: Tokens("synthetic-slack-ui-installation-token"), executionStore: Tokens(nil)) { request in
            guard let url = request.url, url.scheme == "https", url.host == "synthetic-slack.invalid",
                  url.port == nil, url.user == nil, url.password == nil, url.fragment == nil else { throw FixtureError.blocked }
            let payload: [String: Any]
            switch (request.httpMethod, url.path) {
            case ("GET", "/v1/services"):
                if unavailable { throw FixtureError.blocked }
                let services = catalog ? ["gmail", "outlook", "googlecalendar", "googledrive", "googledocs", "googlesheets", "notion", "slack", "calendly", "linkedin", "discord", "youtube", "reddit", "instagram", "whatsapp", "facebook"] : ["slack"]
                payload = ["services": services.map { ["id": $0, "name": $0.capitalized] }]
            case ("GET", "/v1/connections"):
                payload = ["connections": empty ? [] : [["id": connection, "service": "slack", "name": "Slack", "status": "ACTIVE",
                    "accountLabel": "SYNTHETIC compte de préparation du matin"]]]
            case ("GET", "/v1/slack/reply-identity"):
                guard !empty, URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "connectionID" })?.value == connection else { throw FixtureError.blocked }
                payload = ["protocolVersion": 1, "connectionID": connection, "revision": String(repeating: "a", count: 64),
                    "teamID": "T12345678", "userID": "U12345678",
                    "teamName": "SYNTHETIC équipe du matin avec un nom volontairement très long",
                    "userName": "SYNTHETIC Camille propriétaire du compte de démonstration"]
            case ("GET", "/v1/tools"):
                payload = ["tools": []]
            case ("POST", "/v1/execute"):
                guard !empty, let body = request.httpBody,
                      let input = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                      input["connectionID"] as? String == connection,
                      let tool = input["tool"] as? String,
                      let requestID = input["requestID"] as? String, UUID(uuidString: requestID) != nil,
                      let arguments = input["arguments"] as? [String: Any] else { throw FixtureError.blocked }
                if integrated, tool != "SLACK_LIST_ALL_CHANNELS" {
                    guard Set(input.keys) == ["connectionID", "tool", "requestID", "arguments"],
                          arguments["channel"] as? String == "C12345678" else { throw FixtureError.blocked }
                    let data: [String: Any]
                    switch tool {
                    case "SLACK_FETCH_CONVERSATION_HISTORY":
                        guard Set(arguments.keys) == ["channel", "limit"],
                              (arguments["limit"] as? NSNumber)?.intValue == 3 else { throw FixtureError.blocked }
                        historyReads += 1
                        data = ["ok": true, "messages": messages]
                    case "SLACK_RETRIEVE_CONVERSATION_INFORMATION":
                        guard Set(arguments.keys) == ["channel"] else { throw FixtureError.blocked }
                        data = ["ok": true, "channel": channel("C12345678", "SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long")]
                    case "SLACK_FETCH_MESSAGE_THREAD_FROM_A_CONVERSATION":
                        guard Set(arguments.keys) == ["channel", "ts", "limit"],
                              arguments["ts"] as? String == "1792100000.000001",
                              (arguments["limit"] as? NSNumber)?.intValue == 15 else { throw FixtureError.blocked }
                        data = ["ok": true, "messages": [messages[0]]]
                    default: throw FixtureError.blocked
                    }
                    payload = ["requestID": requestID, "successful": true, "resultAvailable": true, "data": data]
                    break
                }
                guard tool == "SLACK_LIST_ALL_CHANNELS",
                      Set(arguments.keys).isSubset(of: ["limit", "types", "exclude_archived", "cursor"]),
                      (arguments["limit"] as? NSNumber)?.intValue == 50,
                      arguments["types"] as? String == "public_channel,private_channel",
                      arguments["exclude_archived"] as? Bool == true else { throw FixtureError.blocked }
                let channels: [[String: Any]], next: String
                if let requested = arguments["cursor"] as? String {
                    guard requested == cursor else { throw FixtureError.blocked }
                    channels = [channel("C22222222", "SYNTHETIC-seconde-page-canal-membre")]
                    next = ""
                } else {
                    channels = [channel("C12345678", "SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"),
                        channel("C33333333", "SYNTHETIC-archive-masque", archived: true),
                        channel("C44444444", "SYNTHETIC-non-membre-masque", member: false),
                        channel("C55555555", "SYNTHETIC-lecture-seule-masque", readOnly: true)]
                    next = cursor
                }
                payload = ["requestID": requestID, "successful": true,
                    "data": ["ok": true, "channels": channels, "response_metadata": ["next_cursor": next]]]
            case ("POST", "/v1/slack/replies"):
                guard integrated, !empty, let body = request.httpBody,
                      let input = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                      Set(input.keys) == ["connectionID", "requestID", "expectedIdentity", "channelID", "threadTS", "body"],
                      input["connectionID"] as? String == connection,
                      input["channelID"] as? String == "C12345678",
                      input["threadTS"] as? String == "1792100000.000001",
                      let text = input["body"] as? String, text.hasPrefix("SYNTHETIC "), text.count <= 2_000,
                      let requestID = input["requestID"] as? String, UUID(uuidString: requestID) != nil,
                      let identity = input["expectedIdentity"] as? [String: String],
                      identity == ["revision": String(repeating: "a", count: 64), "teamID": "T12345678", "userID": "U12345678"] else { throw FixtureError.blocked }
                // The ordinary service and conversation have durably claimed this
                // dispatch. A lost simulated response must remain uncertain.
                receivedBodySHA256 = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
                sendAttempts += 1
                throw URLError(.timedOut)
            default: throw FixtureError.blocked
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { throw FixtureError.blocked }
            return (data, response)
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    private static var historyReads = 0
    private static var sendAttempts = 0
    private static var receivedBodySHA256: String?
    private static var messages: [[String: Any]] {
        (0..<3).map { index in ["type": "message", "ts": "179210000\(index).000001", "user": "U12345678",
            "text": "SYNTHETIC invented meeting note \(index + 1)."] }
    }
    private enum FixtureError: Error { case blocked }
    private final class Tokens: ComposioTokenStoring {
        private var value: String?
        init(_ value: String?) { self.value = value }
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private static func channel(_ id: String, _ name: String, member: Bool = true,
                                archived: Bool = false, readOnly: Bool = false) -> [String: Any] {
        ["id": id, "name": name, "is_member": member, "is_archived": archived,
         "is_read_only": readOnly, "is_im": false, "is_mpim": false]
    }
    #endif
}
