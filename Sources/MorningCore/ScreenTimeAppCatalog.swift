import Foundation

/// Names and kinds for the bundle identifiers Screen Time returns. On iOS 27 the usage rows
/// carry real bundle identifiers but no display name (docs/SCREEN-TIME-INTEGRATION.md), so MORE keeps
/// its own small table and falls back to a readable name made from the identifier.
public enum ScreenTimeAppCatalog {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case messaging, mail, calendar, browser, social, video, games, news, weather, music, productivity, other

        /// Categories that may benefit from a budget. Duration alone does not establish scrolling.
        public var isAttentionSink: Bool { self == .social || self == .video || self == .games }

        public var stepKind: StepKind {
            switch self {
            case .messaging, .mail: .messages
            case .calendar: .calendar
            case .social, .video, .games, .music: .entertainment
            case .news, .weather: .briefing
            case .browser, .productivity, .other: .custom
            }
        }
    }

    public struct Entry: Equatable, Sendable {
        public let name: String
        public let kind: Kind
    }

    /// A known app's name and kind, or a readable fallback (kind `.other`, or a kind guessed
    /// from the system category name when one is given).
    public static func entry(for bundleIdentifier: String, categoryName: String? = nil) -> Entry {
        if let known = known(bundleIdentifier) { return known }
        return Entry(name: fallbackName(for: bundleIdentifier), kind: kind(forCategory: categoryName))
    }

    /// True for rows that are not part of a routine: system sheets and services, MORE itself
    /// (any build, including the side-by-side spike and the UI-test runner), and XCTest runners.
    public static func isNoise(_ bundleIdentifier: String, ownBundleIdentifiers: Set<String> = []) -> Bool {
        let id = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return true }
        if isOwnOrTest(id, ownBundleIdentifiers: ownBundleIdentifiers) { return true }
        let lower = id.lowercased()
        if systemNoise.contains(lower) { return true }
        guard lower.hasPrefix("com.apple.") else { return false }
        let last = lower.split(separator: ".").last.map(String.init) ?? lower
        return noiseSuffixes.contains { last.hasSuffix($0) }
    }

    /// The last meaningful part of the identifier, split into words: `com.chess.iphone` →
    /// "Chess", `com.example.MorningNews` → "Morning News".
    public static func fallbackName(for bundleIdentifier: String) -> String {
        let parts = bundleIdentifier.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        let meaningful = parts.dropFirst(parts.count > 1 ? 1 : 0).reversed().first {
            !genericParts.contains($0.lowercased()) && $0.contains(where: \.isLetter)
        } ?? parts.last ?? bundleIdentifier
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in meaningful {
            if character == "-" || character == "_" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let previous, previous.isLowercase {
                words.append(current); current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        let name = words.map { word in
            word.first.map { String($0).uppercased() + word.dropFirst() } ?? word
        }.joined(separator: " ")
        return name.isEmpty ? String(localized: "Unnamed app", bundle: .module) : String(name.prefix(60))
    }

    /// Screen Time's localized category names (English and French) mapped to a kind.
    public static func kind(forCategory name: String?) -> Kind {
        guard let name = name?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) else { return .other }
        if name.contains("social") || name.contains("sociaux") { return .social }
        if name.contains("entertainment") || name.contains("divertissement") { return .video }
        if name.contains("game") || name.contains("jeu") { return .games }
        if name.contains("news") || name.contains("actualit") || name.contains("information") { return .news }
        if name.contains("productiv") || name.contains("finance") { return .productivity }
        return .other
    }

    private static let genericParts: Set<String> = [
        "com", "net", "org", "io", "co", "app", "apps", "ios", "iphone", "ipad", "mobile", "client",
        "prod", "production", "release", "main", "phone", "native", "inc", "ltd", "www"
    ]
    private static let systemNoise: Set<String> = [
        "com.apple.springboard", "com.apple.localauthenticationuiservice", "com.apple.screenshotservicesservice",
        "com.apple.authkituiservice", "com.apple.passbookuiservice", "com.apple.servicespaymentangel",
        "com.apple.passkit.servicespaymentangel", "com.apple.familycontrolsauthenticationui",
        "com.apple.preboard", "com.apple.incallservice", "com.apple.sharingviewservice",
        "com.apple.springboard.screentime", "com.apple.screentimeunlockui", "com.apple.siri"
    ]
    private static let noiseSuffixes = ["uiservice", "viewservice", "servicesservice", "service", "angel", "extension", "ui"]

    private static func known(_ id: String) -> Entry? {
        switch id {
        case "com.apple.MobileSMS": Entry(name: String(localized: "Messages", bundle: .module), kind: .messaging)
        case "com.apple.mobilemail": Entry(name: String(localized: "Mail", bundle: .module), kind: .mail)
        case "com.apple.mobilecal": Entry(name: String(localized: "Calendar", bundle: .module), kind: .calendar)
        case "com.apple.mobilesafari": Entry(name: "Safari", kind: .browser)
        case "com.apple.weather": Entry(name: String(localized: "Weather", bundle: .module), kind: .weather)
        case "com.apple.news": Entry(name: "Apple News", kind: .news)
        case "com.apple.reminders": Entry(name: String(localized: "Reminders", bundle: .module), kind: .productivity)
        case "com.apple.mobilenotes": Entry(name: String(localized: "Notes", bundle: .module), kind: .productivity)
        case "com.apple.mobilephone": Entry(name: String(localized: "Phone", bundle: .module), kind: .messaging)
        case "com.apple.facetime": Entry(name: "FaceTime", kind: .messaging)
        case "com.apple.Music": Entry(name: String(localized: "Music", bundle: .module), kind: .music)
        case "com.apple.podcasts": Entry(name: "Podcasts", kind: .music)
        case "com.apple.mobileslideshow": Entry(name: String(localized: "Photos", bundle: .module), kind: .other)
        case "com.apple.camera": Entry(name: String(localized: "Camera", bundle: .module), kind: .other)
        case "com.apple.Maps": Entry(name: String(localized: "Maps", bundle: .module), kind: .other)
        case "com.apple.Health": Entry(name: String(localized: "Health", bundle: .module), kind: .other)
        case "com.apple.Fitness": Entry(name: String(localized: "Fitness", bundle: .module), kind: .other)
        case "com.apple.stocks": Entry(name: String(localized: "Stocks", bundle: .module), kind: .news)
        case "com.apple.mobiletimer": Entry(name: String(localized: "Clock", bundle: .module), kind: .other)
        case "com.apple.Preferences": Entry(name: String(localized: "Settings", bundle: .module), kind: .other)
        case "com.apple.tv": Entry(name: "Apple TV", kind: .video)
        case "com.apple.iBooks": Entry(name: String(localized: "Books", bundle: .module), kind: .other)
        case "com.apple.shortcuts": Entry(name: String(localized: "Shortcuts", bundle: .module), kind: .productivity)
        case "net.whatsapp.WhatsApp": Entry(name: "WhatsApp", kind: .messaging)
        case "ph.telegra.Telegraph": Entry(name: "Telegram", kind: .messaging)
        case "org.whispersystems.signal": Entry(name: "Signal", kind: .messaging)
        case "com.facebook.Messenger": Entry(name: "Messenger", kind: .messaging)
        case "com.hammerandchisel.discord": Entry(name: "Discord", kind: .messaging)
        case "com.tinyspeck.chatlyio": Entry(name: "Slack", kind: .messaging)
        case "com.microsoft.skype.teams": Entry(name: "Teams", kind: .messaging)
        case "com.google.Gmail": Entry(name: "Gmail", kind: .mail)
        case "com.microsoft.Office.Outlook": Entry(name: "Outlook", kind: .mail)
        case "com.google.calendar": Entry(name: "Google Calendar", kind: .calendar)
        case "com.google.chrome.ios": Entry(name: "Chrome", kind: .browser)
        case "org.mozilla.ios.Firefox": Entry(name: "Firefox", kind: .browser)
        case "com.burbn.instagram": Entry(name: "Instagram", kind: .social)
        case "com.zhiliaoapp.musically": Entry(name: "TikTok", kind: .social)
        case "com.facebook.Facebook": Entry(name: "Facebook", kind: .social)
        case "com.atebits.Tweetie2": Entry(name: "X", kind: .social)
        case "com.toyopagroup.picaboo": Entry(name: "Snapchat", kind: .social)
        case "com.reddit.Reddit": Entry(name: "Reddit", kind: .social)
        case "com.linkedin.LinkedIn": Entry(name: "LinkedIn", kind: .social)
        case "com.burbn.barcelona": Entry(name: "Threads", kind: .social)
        case "pinterest": Entry(name: "Pinterest", kind: .social)
        case "com.google.ios.youtube": Entry(name: "YouTube", kind: .video)
        case "com.netflix.Netflix": Entry(name: "Netflix", kind: .video)
        case "tv.twitch": Entry(name: "Twitch", kind: .video)
        case "com.spotify.client": Entry(name: "Spotify", kind: .music)
        case "com.chess.iphone": Entry(name: "Chess.com", kind: .games)
        case "com.lichess.mobileapp", "org.lichess.mobileapp": Entry(name: "Lichess", kind: .games)
        case "com.nytimes.NYTimes": Entry(name: "NYTimes", kind: .news)
        case "com.lemonde.lmfr", "fr.lemonde.lemonde": Entry(name: "Le Monde", kind: .news)
        case "com.google.Maps": Entry(name: "Google Maps", kind: .other)
        case "com.openai.chat": Entry(name: "ChatGPT", kind: .productivity)
        case "com.anthropic.claude": Entry(name: "Claude", kind: .productivity)
        case "com.google.GoogleMobile": Entry(name: "Google", kind: .browser)
        case "com.duolingo.DuolingoMobile": Entry(name: "Duolingo", kind: .other)
        default: nil
        }
    }
}

public extension ScreenTimeAppCatalog {
    /// Only supported in-MORE readers or reviewed app URL schemes become targets.
    /// Screen Time's bundle identifier is not a launch URL; unknown apps stay manual.
    static func routineTarget(for bundleIdentifier: String) -> RoutineStepTarget? {
        let app: StepApp
        switch bundleIdentifier {
        case "com.google.Gmail": return .inAppWeb(site: WebMorningSite.gmail.table.startURL)
        case "com.apple.MobileSMS": app = .messages
        case "com.apple.mobilemail": app = .mail
        case "net.whatsapp.WhatsApp": app = .whatsapp
        case "com.burbn.instagram": app = .instagram
        case "com.apple.mobilecal": app = .calendar
        case "com.apple.Maps": app = .maps
        default: return nil
        }
        return .externalApp(app, detail: nil)
    }
}
