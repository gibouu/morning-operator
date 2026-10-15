import CoreFoundation
import Foundation

/// In-memory mail only. Neither these values nor their debug descriptions persist
/// or expose mailbox content. The UI must clear them on dismissal/background/reset.
public struct GmailMessageSummary: Sendable, Equatable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let sender: String
    public let subject: String
    public let receivedAt: Date?
    public var description: String { "GmailMessageSummary(redacted)" }
    public var debugDescription: String { description }
}

public struct GmailUnreadMessagesSnapshot: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let messages: [GmailMessageSummary]
    public let failedMessageCount: Int
    /// More server results exist; this API deliberately never follows pagination.
    public let hasMore: Bool
    public let retrievedAt: Date
    public var description: String { "GmailUnreadMessagesSnapshot(redacted)" }
    public var debugDescription: String { description }
    public func isCurrent(at date: Date) -> Bool { GmailMessageFreshness.current(retrievedAt, at: date) }
}

public struct GmailMessage: Sendable, Equatable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let sender: String
    public let subject: String
    public let receivedAt: Date?
    public let plainTextBody: String
    public let bodyWasTruncated: Bool
    /// No readable inline text was returned. Attachments, unsupported encodings
    /// and attachment-backed text are not fetched or guessed from the snippet.
    public let bodyUnavailable: Bool
    /// Time this immutable message snapshot was fetched. It is not a polling TTL
    /// and never expires an active reading or a user-edited reply after 60 seconds.
    public let retrievedAt: Date
    public var description: String { "GmailMessage(redacted)" }
    public var debugDescription: String { description }
}

private enum GmailMessageFreshness {
    static func current(_ retrievedAt: Date, at date: Date) -> Bool {
        let age = date.timeIntervalSince(retrievedAt)
        return age.isFinite && age >= 0 && age < 60
    }
}

enum GmailMessageLimits {
    static let maximumWireBytes = 524_288
    static let maximumDecodedPartBytes = 262_144
    static let maximumDeclaredPartBytes = 35_000_000
    static let maximumBodyCharacters = 32_000
    static let maximumDepth = 8
    static let maximumParts = 64
}

/// Bounded MIME/text decoding only. No HTML renderer, URL loader or attachment API.
/// Missing data stays unavailable; malformed structure fails the selected read.
enum GmailMessageDecoder {
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    static func list(from data: Data) throws -> (ids: [String], hasMore: Bool) {
        let object = try dictionary(data)
        let rows: [[String: Any]]
        if let raw = object["messages"] {
            guard let values = raw as? [[String: Any]] else { throw GmailConnectionError.invalidResponse }
            rows = values
        } else {
            guard let estimate = object["resultSizeEstimate"] as? NSNumber,
                  CFGetTypeID(estimate) != CFBooleanGetTypeID(), estimate.doubleValue == 0 else {
                throw GmailConnectionError.invalidResponse
            }
            rows = []
        }
        guard rows.count <= 5 else { throw GmailConnectionError.invalidResponse }
        let ids = try rows.map { row -> String in
            guard let id = row["id"] as? String, validID(id) else { throw GmailConnectionError.invalidResponse }
            return id
        }
        guard Set(ids).count == ids.count else { throw GmailConnectionError.invalidResponse }
        var hasMore = false
        if let token = object["nextPageToken"] {
            guard let token = token as? String, !token.isEmpty, token.utf8.count <= 2_048,
                  !rows.isEmpty else { throw GmailConnectionError.invalidResponse }
            hasMore = true
        }
        return (ids, hasMore)
    }

    static func summary(from data: Data, expectedID: String) throws -> GmailMessageSummary {
        try summary(try dictionary(data), expectedID: expectedID)
    }

    static func message(from data: Data, expectedID: String, retrievedAt: Date) throws -> GmailMessage {
        let object = try dictionary(data)
        let summary = try summary(object, expectedID: expectedID)
        guard let payload = object["payload"] as? [String: Any] else { throw GmailConnectionError.invalidResponse }
        var count = 0
        try validate(payload, depth: 0, count: &count)
        let extracted = try text(payload)
        let content = extracted?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let truncated = content.count > GmailMessageLimits.maximumBodyCharacters || extracted?.isIncomplete == true
        return GmailMessage(id: summary.id, sender: summary.sender, subject: summary.subject,
                            receivedAt: summary.receivedAt,
                            plainTextBody: String(content.prefix(GmailMessageLimits.maximumBodyCharacters)),
                            bodyWasTruncated: truncated, bodyUnavailable: content.isEmpty,
                            retrievedAt: retrievedAt)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard data.count <= GmailMessageLimits.maximumWireBytes else { throw GmailConnectionError.messageTooLarge }
        guard let value = try? JSONSerialization.jsonObject(with: data), let object = value as? [String: Any] else {
            throw GmailConnectionError.invalidResponse
        }
        return object
    }

    private static func summary(_ object: [String: Any], expectedID: String) throws -> GmailMessageSummary {
        guard validID(expectedID), let id = object["id"] as? String, id == expectedID,
              let payload = object["payload"] as? [String: Any] else { throw GmailConnectionError.invalidResponse }
        let headers = try headers(payload)
        let sender = try header("from", in: headers)
        let subject = try header("subject", in: headers)
        guard sender.utf8.count <= 1_024, subject.utf8.count <= 2_048 else { throw GmailConnectionError.messageTooLarge }
        var date: Date?
        if let raw = object["internalDate"] {
            guard let milliseconds = raw as? String, milliseconds.utf8.count <= 16,
                  let value = Int64(milliseconds), value >= 0, value <= 253_402_300_799_999 else {
                throw GmailConnectionError.invalidResponse
            }
            date = Date(timeIntervalSince1970: Double(value) / 1_000)
        }
        return GmailMessageSummary(id: id, sender: oneLine(sender), subject: oneLine(subject), receivedAt: date)
    }

    private static func headers(_ part: [String: Any]) throws -> [[String: String]] {
        guard let raw = part["headers"] else { return [] }
        guard let headers = raw as? [[String: String]], headers.count <= 128,
              headers.allSatisfy({ ($0["name"]?.utf8.count ?? Int.max) <= 256 &&
                  ($0["value"]?.utf8.count ?? Int.max) <= 16_384 }) else { throw GmailConnectionError.messageTooLarge }
        return headers
    }

    private static func header(_ name: String, in headers: [[String: String]]) throws -> String {
        let values = headers.filter { $0["name"]?.lowercased() == name }.compactMap { $0["value"] }
        guard values.count <= 1 else { throw GmailConnectionError.invalidResponse }
        return values.first ?? ""
    }

    private static func oneLine(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) })
            .joined(separator: " ")
    }

    private static func validate(_ part: [String: Any], depth: Int, count: inout Int) throws {
        count += 1
        guard depth <= GmailMessageLimits.maximumDepth, count <= GmailMessageLimits.maximumParts else {
            throw GmailConnectionError.messageTooLarge
        }
        _ = try headers(part)
        if let mime = part["mimeType"], !(mime is String) { throw GmailConnectionError.invalidResponse }
        if let filename = part["filename"] {
            guard let filename = filename as? String, filename.utf8.count <= 4_096 else {
                throw GmailConnectionError.messageTooLarge
            }
        }
        if let raw = part["body"] {
            guard let body = raw as? [String: Any] else { throw GmailConnectionError.invalidResponse }
            _ = try declaredSize(body)
        }
        if let raw = part["parts"] {
            guard let parts = raw as? [[String: Any]], parts.count <= GmailMessageLimits.maximumParts else {
                throw GmailConnectionError.messageTooLarge
            }
            for child in parts { try validate(child, depth: depth + 1, count: &count) }
        }
    }

    private struct TextBody {
        let value: String
        let hasPlain: Bool
        let isIncomplete: Bool
    }

    private static func text(_ part: [String: Any]) throws -> TextBody? {
        let headers = try headers(part)
        let disposition = try header("content-disposition", in: headers)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (part["filename"] as? String ?? "").isEmpty, disposition != "attachment" else { return nil }
        let mime = (part["mimeType"] as? String ?? "").lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        if mime.hasPrefix("multipart/") {
            let children = part["parts"] as? [[String: Any]] ?? []
            let values = try children.compactMap { try text($0) }
            if mime == "multipart/alternative" {
                return values.first(where: { $0.hasPlain && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? values.first(where: { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
            guard !values.isEmpty else { return nil }
            return TextBody(value: values.map(\.value).joined(separator: "\n\n"),
                            hasPlain: values.contains(where: \.hasPlain),
                            isIncomplete: values.contains(where: \.isIncomplete))
        }
        guard mime == "text/plain" || mime == "text/html", let body = part["body"] as? [String: Any] else { return nil }
        // Body data can be held behind an attachment ID even for text MIME types.
        guard body["attachmentId"] == nil else { return nil }
        guard let raw = body["data"] else { return nil }
        guard let encoded = raw as? String, let expectedSize = try declaredSize(body) else {
            throw GmailConnectionError.invalidResponse
        }
        let data = try base64URL(encoded)
        // Gmail's size is the decoded byte count, not the encoded string length.
        // Incomplete or contradictory text must never be offered as a complete source.
        guard expectedSize == data.count else { throw GmailConnectionError.invalidResponse }
        let contentType = try header("content-type", in: headers)
        guard let decoded = decode(data, contentType: contentType) else { return nil }
        if mime == "text/html" {
            let extracted = GmailHTMLText.extract(decoded)
            return TextBody(value: extracted.value, hasPlain: false, isIncomplete: extracted.isIncomplete)
        }
        return TextBody(value: decoded, hasPlain: true, isIncomplete: false)
    }

    private static func declaredSize(_ body: [String: Any]) throws -> Int? {
        guard let raw = body["size"] else { return nil }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else {
            throw GmailConnectionError.invalidResponse
        }
        guard number.doubleValue <= Double(GmailMessageLimits.maximumDeclaredPartBytes) else {
            throw GmailConnectionError.messageTooLarge
        }
        return number.intValue
    }

    private static func base64URL(_ value: String) throws -> Data {
        guard value.utf8.count <= GmailMessageLimits.maximumWireBytes else { throw GmailConnectionError.messageTooLarge }
        let unpadded = value.replacingOccurrences(of: "=", with: "")
        let paddingCount = value.utf8.count - unpadded.utf8.count
        guard paddingCount <= 2, !value.dropLast(paddingCount).contains("="),
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                  (97...122).contains($0) || $0 == 45 || $0 == 95 || $0 == 61 }),
              unpadded.utf8.count % 4 != 1,
              paddingCount == 0 || paddingCount == (4 - unpadded.utf8.count % 4) % 4 else {
            throw GmailConnectionError.invalidResponse
        }
        var base64 = unpadded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw GmailConnectionError.invalidResponse }
        guard data.count <= GmailMessageLimits.maximumDecodedPartBytes else { throw GmailConnectionError.messageTooLarge }
        return data
    }

    private static func decode(_ data: Data, contentType: String) -> String? {
        let charset = contentType.split(separator: ";").dropFirst().map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.first(where: { $0.hasPrefix("charset=") })?.dropFirst(8).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        switch charset {
        case nil, "utf-8", "utf8", "us-ascii": return String(data: data, encoding: .utf8)
        case "iso-8859-1", "latin1": return String(data: data, encoding: .isoLatin1)
        case "windows-1252": return String(data: data, encoding: .windowsCP1252)
        default: return nil
        }
    }
}

/// Deliberately small text extractor, not a browser or HTML interpreter. All tag
/// attributes disappear, script/style/embedded document content is suppressed,
/// and decoded entities are returned only as inert text.
private enum GmailHTMLText {
    static func extract(_ html: String) -> (value: String, isIncomplete: Bool) {
        var output = ""
        var isIncomplete = false
        var cursor = html.startIndex
        var suppressed: [String] = []
        let hidden: Set<String> = ["script", "style", "head", "template", "noscript", "iframe", "object", "svg"]
        let breaks: Set<String> = ["br", "p", "div", "li", "tr", "h1", "h2", "h3", "blockquote", "hr"]
        while cursor < html.endIndex {
            if html[cursor] != "<" {
                if suppressed.isEmpty { output.append(html[cursor]) }
                cursor = html.index(after: cursor)
                continue
            }
            if html[cursor...].hasPrefix("<!--") {
                guard let end = html[cursor...].range(of: "-->") else {
                    isIncomplete = true
                    break
                }
                cursor = end.upperBound
                continue
            }
            var end = html.index(after: cursor)
            var quote: Character?
            while end < html.endIndex {
                let char = html[end]
                if let active = quote { if char == active { quote = nil } }
                else if char == "\"" || char == "'" { quote = char }
                else if char == ">" { break }
                end = html.index(after: end)
            }
            guard end < html.endIndex else {
                isIncomplete = true
                break
            }
            let tag = html[html.index(after: cursor)..<end].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let closing = tag.hasPrefix("/")
            let name = tag.drop(while: { $0 == "/" || $0.isWhitespace }).prefix(while: { $0.isLetter || $0.isNumber })
            let key = String(name)
            if hidden.contains(key) {
                if closing {
                    if let last = suppressed.lastIndex(of: key) { suppressed.removeSubrange(last...) }
                } else if !tag.hasSuffix("/") { suppressed.append(key) }
            } else if suppressed.isEmpty, breaks.contains(key) { output.append("\n") }
            cursor = html.index(after: end)
        }
        let value = entities(output).split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Preserve readable text, but unfinished markup or a suppressed region
        // cannot establish complete source context for a suggested reply.
        return (value, isIncomplete || !suppressed.isEmpty)
    }

    private static func entities(_ text: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                     "euro": "€", "hellip": "…", "ndash": "–", "mdash": "—", "copy": "©", "reg": "®"]
        var output = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text[cursor] == "&" {
                let limit = text.index(cursor, offsetBy: 16, limitedBy: text.endIndex) ?? text.endIndex
                if let end = text[cursor..<limit].firstIndex(of: ";") {
                    let token = String(text[text.index(after: cursor)..<end])
                    var replacement = named[token]
                    if token.hasPrefix("#") {
                        let hex = token.lowercased().hasPrefix("#x")
                        let digits = token.dropFirst(hex ? 2 : 1)
                        if let number = UInt32(digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(number),
                           !CharacterSet.controlCharacters.contains(scalar) { replacement = String(scalar) }
                    }
                    if let replacement { output += replacement; cursor = text.index(after: end); continue }
                }
            }
            output.append(text[cursor]); cursor = text.index(after: cursor)
        }
        return output
    }
}
