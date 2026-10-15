import Foundation
import Testing
@testable import MorningApple

/// Invented mail/protocol input only. No Google account, mail, network or app fixture.
@Suite("Gmail message reading — synthetic HTTP responses only")
@MainActor
struct GmailReadingTests {
    private static let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private static let client = "123456789-synthetic.apps.googleusercontent.com"
    private static let scheme = "com.googleusercontent.apps.123456789-synthetic"
    private static let state = String(repeating: "s", count: 43)

    @Test func readUpgradeRequestsOnlyReadonlyAndNeverGrantsImplicitReading() async throws {
        let request = try attempt(.readMessages)
        let items = URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first(where: { $0.name == "scope" })?.value == GmailConnectionService.readonlyScope)
        #expect(!items.contains(where: { ["access_type", "client_secret", "include_granted_scopes"].contains($0.name) }))
        let read = try await session(.readMessages)
        #expect(read.canReadMessages)
        let count = try await session(.metadata, grant: GmailConnectionService.readonlyScope)
        #expect(!count.canReadMessages, "An existing broader Google grant must not silently enable reading.")
        var calls = 0
        let service = GmailConnectionService(transport: { request in
            calls += 1; return response(request, object: [:])
        }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.readAccessRequired) { try await service.unreadInboxMessages(session: count) }
        await #expect(throws: GmailConnectionError.readAccessRequired) { try await service.message(id: "a1", session: count) }
        #expect(calls == 0)
        let denied = GmailConnectionService(transport: { request in
            response(request, object: token(GmailConnectionService.metadataScope))
        }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.permissionDenied) {
            try await denied.completeAuthorization(attempt(.readMessages), callbackURL: callback())
        }
    }

    @Test func unreadListUsesBothLabelsBoundedHeadersAndReportsPartialReads() async throws {
        let access = try await session(.readMessages)
        var requests: [URLRequest] = []
        let service = GmailConnectionService(transport: { request in
            requests.append(request)
            if request.url!.path.hasSuffix("/messages") {
                return response(request, object: ["messages": [["id": "a1"], ["id": "b2"]], "nextPageToken": "synthetic-next"])
            }
            if request.url!.path.hasSuffix("/b2") { return response(request, object: [:], status: 404) }
            return response(request, object: messageObject("a1", body: part("text/plain", "not requested")))
        }, now: { Self.instant })
        let result = try await service.unreadInboxMessages(session: access)
        #expect(result.messages.count == 1 && result.failedMessageCount == 1 && result.hasMore)
        #expect(result.messages.first?.sender == "Invented Sender <sender@example.invalid>")
        #expect(result.messages.first?.subject == "Invented planning note")
        #expect(result.messages.first?.receivedAt == Self.instant)
        #expect(result.isCurrent(at: Self.instant.addingTimeInterval(59)))
        #expect(!result.isCurrent(at: Self.instant.addingTimeInterval(60)))
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(Set(query.filter { $0.name == "labelIds" }.compactMap(\.value)) == ["INBOX", "UNREAD"])
        #expect(query.first(where: { $0.name == "maxResults" })?.value == "5")
        #expect(requests.dropFirst().allSatisfy { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains(.init(name: "format", value: "metadata")) })
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == "Bearer SYNTHETIC_READ_TOKEN" })
        #expect(!String(reflecting: result).contains("Invented"))
        #expect(!String(reflecting: result.messages[0]).contains("sender@example"))
    }

    @Test func emptyInboxRequiresAnActualEmptyListAndInvalidIDsNeverBecomePaths() async throws {
        let access = try await session(.readMessages)
        for object: [String: Any] in [["resultSizeEstimate": 0], ["messages": []]] {
            let service = GmailConnectionService(transport: { response($0, object: object) }, now: { Self.instant })
            let result = try await service.unreadInboxMessages(session: access)
            #expect(result.messages.isEmpty && result.failedMessageCount == 0 && !result.hasMore)
        }
        for object: [String: Any] in [[:], ["resultSizeEstimate": true], ["resultSizeEstimate": 0.5],
            ["messages": [["id": "../steal"]]], ["messages": [["id": "a1"], ["id": "a1"]]],
            ["messages": (0..<6).map { ["id": "a\($0)"] }]] {
            let service = GmailConnectionService(transport: { response($0, object: object) }, now: { Self.instant })
            await #expect(throws: GmailConnectionError.invalidResponse) { try await service.unreadInboxMessages(session: access) }
        }
        var calls = 0
        let service = GmailConnectionService(transport: { request in calls += 1; return response(request, object: [:]) }, now: { Self.instant })
        for id in ["", "a/b", "x?q=private", String(repeating: "a", count: 129)] {
            await #expect(throws: GmailConnectionError.invalidResponse) { try await service.message(id: id, session: access) }
        }
        #expect(calls == 0)
    }

    @Test func fullReadPrefersPlainAlternativeAndNeverFetchesAttachmentIDs() async throws {
        let access = try await session(.readMessages)
        var calls = 0
        let payload: [String: Any] = ["mimeType": "multipart/mixed", "parts": [
            ["mimeType": "multipart/alternative", "parts": [part("text/html", "<b>HTML duplicate</b>"), part("text/plain", "Invented plain body\nSecond line")]],
            ["mimeType": "text/plain", "filename": "private.txt", "body": ["attachmentId": "DO_NOT_FETCH", "data": encoded("not the body")]],
            ["mimeType": "image/png", "body": ["attachmentId": "NEVER_FETCH"]]
        ]]
        let service = GmailConnectionService(transport: { request in
            calls += 1
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains(.init(name: "format", value: "full")))
            return response(request, object: messageObject("a1", body: payload))
        }, now: { Self.instant })
        let message = try await service.message(id: "a1", session: access)
        #expect(message.plainTextBody == "Invented plain body\nSecond line")
        #expect(!message.bodyUnavailable && !message.bodyWasTruncated && calls == 1)
        #expect(message.retrievedAt == Self.instant)
        #expect(!String(reflecting: message).contains("Invented"))
    }

    @Test func htmlOnlyBecomesInertTextWithoutScriptStylesResourcesOrAttributes() async throws {
        let html = "<html><head><style>PRIVATE_STYLE</style></head><body><script>PRIVATE_SCRIPT</script><!--PRIVATE_COMMENT--><p>Hello &amp; welcome &#x1F31E;</p><img src='https://example.invalid/track'><a href='javascript:PRIVATE_ACTION' title='a > b'>Visible link</a><iframe src='https://example.invalid/embed'>PRIVATE_FRAME</iframe><p>&lt;b&gt;inert&lt;/b&gt;</p></body></html>"
        let value = try await read(part("text/html", html))
        #expect(value.plainTextBody.contains("Hello & welcome 🌞"))
        #expect(value.plainTextBody.contains("Visible link") && value.plainTextBody.contains("<b>inert</b>"))
        #expect(!value.plainTextBody.contains("PRIVATE") && !value.plainTextBody.contains("https://") && !value.plainTextBody.contains("javascript"))
        let malformed = try await read(part("text/html", "<p>Visible</p><script>NEVER_VISIBLE"))
        #expect(malformed.plainTextBody == "Visible")
    }

    @Test func unterminatedHTMLMarkupRetainsReadablePrefixOnlyAsPartialContext() async throws {
        for suffix in ["<!-- unfinished comment", "<div", "<div title='unfinished > tag", "<a title=\"unfinished > tag", "<script>unfinished script"] {
            let value = try await read(part("text/html", "<p>Visible prefix</p>" + suffix))
            #expect(value.plainTextBody == "Visible prefix")
            #expect(value.bodyWasTruncated && !value.bodyUnavailable,
                    "A readable prefix is useful for reading, but is incomplete reply context.")
        }
    }

    @Test func multipartIncompletenessPropagatesOnlyFromTheBodyThatWasSelected() async throws {
        let partial = part("text/html", "<p>Visible prefix</p><!-- unfinished")
        let complete = part("text/plain", "Complete invented body")
        let mixed = try await read(["mimeType": "multipart/mixed", "parts": [complete, partial]])
        #expect(mixed.bodyWasTruncated && mixed.plainTextBody.contains("Visible prefix"))
        let preferred = try await read(["mimeType": "multipart/alternative", "parts": [complete, partial]])
        #expect(preferred.plainTextBody == "Complete invented body" && !preferred.bodyWasTruncated)
        let fallback = try await read(["mimeType": "multipart/alternative", "parts": [part("text/plain", ""), partial]])
        #expect(fallback.plainTextBody == "Visible prefix" && fallback.bodyWasTruncated)
    }

    @Test func unavailableBodyIsExplicitAndBoundedTextIsMarkedTruncated() async throws {
        for payload: [String: Any] in [
            ["mimeType": "application/pdf", "body": ["attachmentId": "DO_NOT_FETCH"]],
            ["mimeType": "text/plain", "body": ["attachmentId": "DO_NOT_FETCH"]],
            ["mimeType": "text/plain", "headers": [["name": "Content-Type", "value": "text/plain; charset=unsupported"]], "body": ["size": 9, "data": encoded("synthetic")]]
        ] {
            let value = try await read(payload)
            #expect(value.bodyUnavailable && value.plainTextBody.isEmpty && !value.bodyWasTruncated)
        }
        let long = try await read(part("text/plain", String(repeating: "é", count: 32_001)))
        #expect(long.plainTextBody.count == 32_000 && long.bodyWasTruncated && !long.bodyUnavailable)
    }

    @Test func malformedMIMEIdentityDepthAndPartLimitsFailExplicitly() async throws {
        let access = try await session(.readMessages)
        for payload: [String: Any] in [
            ["mimeType": "text/plain", "body": ["size": 2, "data": "not base64!"]],
            ["mimeType": "text/plain", "body": ["size": 2, "data": "ab=c"]],
            ["mimeType": "multipart/mixed", "parts": (0..<65).map { _ in part("text/plain", "tiny") }]
        ] {
            let service = GmailConnectionService(transport: { response($0, object: messageObject("a1", body: payload)) }, now: { Self.instant })
            await #expect(throws: GmailConnectionError.self) { try await service.message(id: "a1", session: access) }
        }
        var nested = part("text/plain", "tiny")
        for _ in 0..<10 { nested = ["mimeType": "multipart/mixed", "parts": [nested]] }
        let deep = nested
        let service = GmailConnectionService(transport: { response($0, object: messageObject("a1", body: deep)) }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.messageTooLarge) { try await service.message(id: "a1", session: access) }
        let mismatched = GmailConnectionService(transport: { response($0, object: messageObject("different", body: part("text/plain", "synthetic"))) }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.invalidResponse) { try await mismatched.message(id: "a1", session: access) }
    }

    @Test func emptyPlaintextIsUnavailableAndDoesNotHideReadableHTMLAlternative() async throws {
        let empty = try await read(part("text/plain", " \n\t "))
        #expect(empty.bodyUnavailable && empty.plainTextBody.isEmpty)
        let alternative = try await read(["mimeType": "multipart/alternative", "parts": [
            part("text/plain", " \n"), part("text/html", "<p>Actual invented HTML body</p>")
        ]])
        #expect(alternative.plainTextBody == "Actual invented HTML body" && !alternative.bodyUnavailable)
    }

    @Test func declaredBodySizeMustMatchDecodedBytesBeforeTextIsAdmitted() async throws {
        let access = try await session(.readMessages)
        for size: Any in [-1, true, 0.5, 2, 4, 35_000_001, "3"] {
            let payload: [String: Any] = ["mimeType": "text/plain", "body": ["size": size, "data": encoded("abc")]]
            let service = GmailConnectionService(transport: { response($0, object: messageObject("a1", body: payload)) }, now: { Self.instant })
            await #expect(throws: GmailConnectionError.self) { try await service.message(id: "a1", session: access) }
        }
        let missing = GmailConnectionService(transport: { response($0, object: messageObject("a1", body: ["mimeType": "text/plain", "body": ["data": encoded("abc")]])) }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.invalidResponse) { try await missing.message(id: "a1", session: access) }
        let valid = try await read(part("text/plain", "é🙂"))
        #expect(valid.plainTextBody == "é🙂" && !valid.bodyWasTruncated)
    }

    @Test func foldedAttachmentDispositionExcludesEvenUnnamedInlineData() async throws {
        for disposition in [" attachment; filename=synthetic.txt", "\r\n\tAtTaChMeNt ; filename=synthetic.txt"] {
            var attachment = part("text/plain", "PRIVATE_SYNTHETIC_ATTACHMENT")
            attachment["filename"] = ""
            attachment["headers"] = [["name": "Content-Disposition", "value": disposition]]
            let onlyAttachment = try await read(attachment)
            #expect(onlyAttachment.bodyUnavailable && onlyAttachment.plainTextBody.isEmpty)
            let mixed = try await read(["mimeType": "multipart/mixed", "parts": [part("text/plain", "Visible body"), attachment]])
            #expect(mixed.plainTextBody == "Visible body" && !mixed.bodyUnavailable)
        }
    }

    @Test func fullWireBoundAndMetadataFailuresNeverPublishAnEmptySuccess() async throws {
        let access = try await session(.readMessages)
        let large = GmailConnectionService(transport: { request in
            (Data(repeating: 32, count: GmailMessageLimits.maximumWireBytes + 1), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.messageTooLarge) { try await large.message(id: "a1", session: access) }
        for (status, error): (Int, GmailConnectionError) in [(401, .sessionExpired), (403, .permissionDenied), (429, .rateLimited), (302, .redirectRejected)] {
            let service = GmailConnectionService(transport: { request in
                if request.url!.path.hasSuffix("/messages") { return response(request, object: ["messages": [["id": "a1"]]]) }
                return response(request, object: ["error": "PRIVATE_REMOTE_BODY"], status: status)
            }, now: { Self.instant })
            if status == 401 || status == 403 {
                await #expect(throws: error) { try await service.unreadInboxMessages(session: access) }
            } else {
                let result = try await service.unreadInboxMessages(session: access)
                #expect(result.messages.isEmpty && result.failedMessageCount == 1)
            }
        }
    }

    @Test func expiryAndTransportCancellationAbortReadsIncludingPartialLists() async throws {
        let access = try await session(.readMessages)
        var calls = 0
        let expired = GmailConnectionService(transport: { request in calls += 1; return response(request, object: [:]) }, now: { Self.instant.addingTimeInterval(3_600) })
        await #expect(throws: GmailConnectionError.sessionExpired) { try await expired.unreadInboxMessages(session: access) }
        #expect(calls == 0)
        let cancelled = GmailConnectionService(transport: { request in
            if request.url!.path.hasSuffix("/messages") { return response(request, object: ["messages": [["id": "a1"]]]) }
            throw URLError(.cancelled)
        }, now: { Self.instant })
        await #expect(throws: CancellationError.self) { try await cancelled.unreadInboxMessages(session: access) }
        var entered = false
        let late = GmailConnectionService(transport: { request in
            entered = true
            try? await Task.sleep(for: .seconds(30))
            return response(request, object: messageObject("a1", body: part("text/plain", "synthetic")))
        }, now: { Self.instant })
        let pending = Task { try await late.message(id: "a1", session: access) }
        while !entered { await Task.yield() }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
    }

    private func read(_ payload: [String: Any]) async throws -> GmailMessage {
        let access = try await session(.readMessages)
        let service = GmailConnectionService(transport: { response($0, object: messageObject("a1", body: payload)) }, now: { Self.instant })
        return try await service.message(id: "a1", session: access)
    }

    private func session(_ access: GmailAuthorizationAccess, grant: String? = nil) async throws -> GmailAccessSession {
        let scope = grant ?? (access == .metadata ? GmailConnectionService.metadataScope : GmailConnectionService.readonlyScope)
        let service = GmailConnectionService(transport: { response($0, object: token(scope)) }, now: { Self.instant })
        return try await service.completeAuthorization(attempt(access), callbackURL: callback())
    }

    private func attempt(_ access: GmailAuthorizationAccess) throws -> GmailAuthorizationRequest {
        try GmailAuthorizationRequest(configuration: GmailOAuthConfiguration(clientID: Self.client, registeredURLSchemes: [Self.scheme]),
                                      verifier: String(repeating: "v", count: 43), state: Self.state, access: access)
    }

    private func callback() -> URL { URL(string: "\(Self.scheme):/oauth2redirect?state=\(Self.state)&code=synthetic")! }
    private func token(_ scope: String) -> [String: Any] {
        ["access_token": "SYNTHETIC_READ_TOKEN", "token_type": "Bearer", "expires_in": 3_600, "scope": scope]
    }
    private func messageObject(_ id: String, body: [String: Any]) -> [String: Any] {
        var payload = body
        var headers = payload["headers"] as? [[String: String]] ?? []
        headers += [["name": "From", "value": "Invented Sender <sender@example.invalid>"], ["name": "Subject", "value": "Invented planning note"]]
        payload["headers"] = headers
        return ["id": id, "internalDate": String(Int64(Self.instant.timeIntervalSince1970 * 1_000)), "payload": payload]
    }
    private func part(_ mime: String, _ text: String) -> [String: Any] { ["mimeType": mime, "body": ["size": text.utf8.count, "data": encoded(text)]] }
    private func encoded(_ text: String) -> String { Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private func response(_ request: URLRequest, object: [String: Any], status: Int = 200) -> (Data, URLResponse) {
        (try! JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}
