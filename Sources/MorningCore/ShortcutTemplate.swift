import Foundation

/// A shortcut built by hand in the Shortcuts app and shared as an iCloud link. Its card
/// stays hidden until its link is filled in, so an empty or wrong link never shows.
public struct ShortcutTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let symbol: String
    public let link: String

    public init(id: String, symbol: String, link: String) {
        self.id = id; self.symbol = symbol; self.link = link
    }

    public var title: String {
        switch id {
        case "text": String(localized: "Text someone", bundle: .module)
        case "email": String(localized: "Email someone", bundle: .module)
        case "playlist": String(localized: "Morning playlist", bundle: .module)
        case "focus": String(localized: "Work Focus on", bundle: .module)
        case "home": String(localized: "Lights and coffee", bundle: .module)
        case "water": String(localized: "Log water", bundle: .module)
        default: id
        }
    }

    /// Only an https link on icloud.com/shortcuts/ opens. Anything else hides the card.
    public var url: URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host == "www.icloud.com" || url.host == "icloud.com",
              url.path.hasPrefix("/shortcuts/"), url.path.count > "/shortcuts/".count else { return nil }
        return url
    }

    /// Fill in each link once the shortcut exists. Empty links keep their cards hidden.
    public static let all: [ShortcutTemplate] = [
        ShortcutTemplate(id: "text", symbol: "message", link: ""),
        ShortcutTemplate(id: "email", symbol: "envelope", link: ""),
        ShortcutTemplate(id: "playlist", symbol: "music.note", link: ""),
        ShortcutTemplate(id: "focus", symbol: "moon", link: ""),
        ShortcutTemplate(id: "home", symbol: "lightbulb", link: ""),
        ShortcutTemplate(id: "water", symbol: "drop", link: "")
    ]

    public static func visible(_ templates: [ShortcutTemplate] = all) -> [ShortcutTemplate] {
        templates.filter { $0.url != nil }
    }
}
