import Foundation

/// The apps a routine step may open. A closed list: each one has a URL scheme MORE
/// declares in LSApplicationQueriesSchemes, and its name is safe on the Lock Screen.
public enum StepApp: String, Codable, CaseIterable, Hashable, Sendable {
    case messages, mail, whatsapp, instagram, calendar, maps, safari

    public var displayName: String { displayName(locale: AppLanguage.locale) }
    public func displayName(locale: Locale) -> String {
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        return switch self {
        case .messages: String(localized: "Messages", bundle: bundle, locale: locale)
        case .mail: String(localized: "Mail", bundle: bundle, locale: locale)
        case .whatsapp: "WhatsApp"
        case .instagram: "Instagram"
        case .calendar: String(localized: "Calendar", bundle: bundle, locale: locale)
        case .maps: String(localized: "Maps", bundle: bundle, locale: locale)
        case .safari: "Safari"
        }
    }

    /// The scheme checked with canOpenURL. Safari opens ordinary web links, which iOS
    /// always allows, so it has none.
    public var queryScheme: String? {
        switch self {
        case .messages: "sms"
        case .mail: "message"
        case .whatsapp: "whatsapp"
        case .instagram: "instagram"
        case .calendar: "calshow"
        case .maps: "maps"
        case .safari: nil
        }
    }

    /// Every scheme MORE asks about. project.yml's LSApplicationQueriesSchemes must list these.
    public static var querySchemes: [String] { allCases.compactMap(\.queryScheme) }

    /// What the optional detail means for this app, shown as the field's prompt.
    public var detailKind: StepAppDetailKind {
        switch self {
        case .messages, .whatsapp: .phoneNumber
        case .mail: .messageID
        case .instagram: .username
        case .maps: .place
        case .safari: .webAddress
        case .calendar: .none
        }
    }

    /// Web hosts that belong to this app, so an in-app page can be named by its app.
    var webHosts: [String] {
        switch self {
        case .instagram: ["instagram.com"]
        case .whatsapp: ["web.whatsapp.com", "whatsapp.com"]
        case .maps: ["maps.apple.com"]
        default: []
        }
    }

    /// The URL that opens this app, on the right screen when the detail is valid. An
    /// invalid detail falls back to the app's home screen, except for Safari, which has
    /// no home screen: it needs a valid http(s) address, otherwise nil.
    public func url(detail: String? = nil) -> URL? {
        let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch self {
        case .messages:
            if let recipient = Self.phoneNumber(detail) ?? Self.emailAddress(detail) { return URL(string: "sms:\(recipient)") }
            return URL(string: "sms:")
        case .mail:
            if let id = Self.messageID(detail) { return URL(string: "message://%3C\(id)%3E") }
            return URL(string: "message://")
        case .whatsapp:
            if let phone = Self.phoneNumber(detail) {
                return URL(string: "whatsapp://send?phone=\(phone.filter(\.isNumber))")
            }
            return URL(string: "whatsapp://")
        case .instagram:
            if let name = Self.username(detail) { return URL(string: "instagram://user?username=\(name)") }
            return URL(string: "instagram://app")
        case .calendar:
            return URL(string: "calshow://")
        case .maps:
            guard !detail.isEmpty, detail.count <= 200,
                  let query = detail.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) else {
                return URL(string: "maps://")
            }
            return URL(string: "maps://?q=\(query)")
        case .safari:
            return Self.webURL(detail)
        }
    }

    /// An http(s) address with a host, or nil. A bare host gets https.
    public static func webURL(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_000, !text.contains(where: \.isWhitespace) else { return nil }
        let candidate = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host, host.contains("."),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func phoneNumber(_ text: String) -> String? {
        let compact = text.filter { !" -.()".contains($0) }
        let digits = compact.hasPrefix("+") ? compact.dropFirst() : Substring(compact)
        guard (3...15).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return compact
    }

    static func emailAddress(_ text: String) -> String? {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard text.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "@._+-".contains($0)) }) else { return nil }
        return text
    }

    /// A Message-ID header value without its angle brackets, percent-encoded.
    static func messageID(_ text: String) -> String? {
        var value = Substring(text)
        if value.hasPrefix("<") { value = value.dropFirst() }
        if value.hasSuffix(">") { value = value.dropLast() }
        guard (3...500).contains(value.count), value.contains("@"),
              value.allSatisfy({ $0.isASCII && !$0.isWhitespace && $0 != "<" && $0 != ">" }) else { return nil }
        return value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
    }

    static func username(_ text: String) -> String? {
        let name = text.hasPrefix("@") ? String(text.dropFirst()) : text
        guard (1...30).contains(name.count),
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }) else { return nil }
        return name
    }

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#/%")
        return set
    }()
}

public enum StepAppDetailKind: Sendable { case none, phoneNumber, messageID, username, place, webAddress }

/// Where a routine step takes the person while its timer runs: another app through its
/// URL scheme, or a web page inside MORE. Both kinds share the step timer, +2 min and Next.
public enum RoutineStepTarget: Codable, Hashable, Sendable {
    case externalApp(StepApp, detail: String?)
    case inAppWeb(site: URL)
    case shortcut(name: String, input: String)
    case connectedAPI(service: String, connectionID: String, tool: String, argumentsJSON: String)
    case googleCalendarDay(GoogleCalendarDayTarget)
    case calendlyDay(CalendlyDayTarget)
    case outlookInbox(OutlookInboxTarget)

    /// The executable route for an approved routine. Old Instagram app choices keep
    /// their saved identity, but use MORE's browser without granting browser actions.
    public var routineExecutionTarget: RoutineStepTarget {
        switch self {
        case let .externalApp(.instagram, detail):
            let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let name = StepApp.username(detail),
               let url = URL(string: "https://www.instagram.com/\(name)/") {
                return .inAppWeb(site: url)
            }
            return .inAppWeb(site: WebMorningSite.instagram.table.startURL)
        case let .externalApp(.safari, detail):
            guard let url = StepApp.webURL(detail ?? ""),
                  let host = url.host?.lowercased(), WebMorningSite.instagram.table.allowedHosts.contains(host),
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  url.port == nil || (url.scheme?.lowercased() == "https" && url.port == 443) ||
                    (url.scheme?.lowercased() == "http" && url.port == 80) else { return self }
            components.scheme = "https"
            if components.port == 80 { components.port = nil }
            guard let secureURL = components.url else { return self }
            return .inAppWeb(site: secureURL)
        default: return self
        }
    }

    /// The URL to open outside MORE after resolving the routine route; nil for an
    /// Instagram moment, another page inside MORE or Safari without a valid address.
    public var externalURL: URL? {
        guard case let .externalApp(app, detail) = routineExecutionTarget else { return nil }
        return app.url(detail: detail)
    }

    /// The closed, Lock Screen-safe name of where this step goes.
    public var destination: StepDestination {
        switch routineExecutionTarget {
        case let .externalApp(app, _): return .app(app)
        case let .inAppWeb(site):
            let host = (site.host ?? "").lowercased()
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return .inMORE(StepApp.allCases.first { $0.webHosts.contains(bare) })
        case .shortcut: return .nativeAction
        case .connectedAPI, .googleCalendarDay, .calendlyDay, .outlookInbox: return .connectedService
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, app, detail, site, name, input, service, connectionID, tool, argumentsJSON, calendar, account }
    private enum Kind: String, Codable { case externalApp, inAppWeb, shortcut, connectedAPI, googleCalendarDay, calendlyDay, outlookInbox }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .externalApp:
            let detail = try values.decodeIfPresent(String.self, forKey: .detail)
            guard (detail?.count ?? 0) <= 2_000 else {
                throw DecodingError.dataCorruptedError(forKey: .detail, in: values, debugDescription: "Detail is too long.")
            }
            self = .externalApp(try values.decode(StepApp.self, forKey: .app), detail: detail)
        case .inAppWeb:
            let text = try values.decode(String.self, forKey: .site)
            guard let url = StepApp.webURL(text) else {
                throw DecodingError.dataCorruptedError(forKey: .site, in: values, debugDescription: "A page in MORE needs an http(s) address.")
            }
            self = .inAppWeb(site: url)
        case .shortcut:
            self = .shortcut(name: try values.decode(String.self, forKey: .name), input: try values.decode(String.self, forKey: .input))
        case .connectedAPI:
            self = .connectedAPI(service: try values.decode(String.self, forKey: .service),
                connectionID: try values.decode(String.self, forKey: .connectionID),
                tool: try values.decode(String.self, forKey: .tool),
                argumentsJSON: try values.decode(String.self, forKey: .argumentsJSON))
        case .googleCalendarDay:
            self = .googleCalendarDay(try values.decode(GoogleCalendarDayTarget.self, forKey: .calendar))
        case .calendlyDay:
            self = .calendlyDay(try values.decode(CalendlyDayTarget.self, forKey: .account))
        case .outlookInbox:
            self = .outlookInbox(try values.decode(OutlookInboxTarget.self, forKey: .account))
        }
        try validateIntegration()
    }

    public func encode(to encoder: any Encoder) throws {
        try validateIntegration()
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .externalApp(app, detail):
            try values.encode(Kind.externalApp, forKey: .kind)
            try values.encode(app, forKey: .app)
            try values.encodeIfPresent(detail, forKey: .detail)
        case let .inAppWeb(site):
            try values.encode(Kind.inAppWeb, forKey: .kind)
            try values.encode(site.absoluteString, forKey: .site)
        case let .shortcut(name, input):
            try values.encode(Kind.shortcut, forKey: .kind)
            try values.encode(name, forKey: .name)
            try values.encode(input, forKey: .input)
        case let .connectedAPI(service, connectionID, tool, argumentsJSON):
            try values.encode(Kind.connectedAPI, forKey: .kind)
            try values.encode(service, forKey: .service)
            try values.encode(connectionID, forKey: .connectionID)
            try values.encode(tool, forKey: .tool)
            try values.encode(argumentsJSON, forKey: .argumentsJSON)
        case let .googleCalendarDay(calendar):
            try values.encode(Kind.googleCalendarDay, forKey: .kind)
            try values.encode(calendar, forKey: .calendar)
        case let .calendlyDay(account):
            try values.encode(Kind.calendlyDay, forKey: .kind)
            try values.encode(account, forKey: .account)
        case let .outlookInbox(account):
            try values.encode(Kind.outlookInbox, forKey: .kind)
            try values.encode(account, forKey: .account)
        }
    }
}

/// What the Lock Screen may say about a step's destination: an app from the closed
/// list, or a page inside MORE (named by its app when its host is a known one).
/// Never a typed address, contact or message.
public enum StepDestination: Codable, Hashable, Sendable {
    case app(StepApp)
    case inMORE(StepApp?)
    case nativeAction, connectedService

    public var displayName: String { displayName(locale: AppLanguage.locale) }
    public func displayName(locale: Locale) -> String {
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        return switch self {
        case let .app(app): app.displayName(locale: locale)
        case let .inMORE(app?): String(localized: "\(app.displayName(locale: locale)) in MORE", bundle: bundle, locale: locale)
        case .inMORE(nil): String(localized: "A page in MORE", bundle: bundle, locale: locale)
        case .nativeAction: String(localized: "iOS action", bundle: bundle, locale: locale)
        case .connectedService: String(localized: "Connected service", bundle: bundle, locale: locale)
        }
    }
}
