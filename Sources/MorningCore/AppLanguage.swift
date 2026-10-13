import Foundation

/// The language the app's interface resolved to. Spoken prose and formatted
/// dates follow it so a French interface never reads English text aloud.
public enum AppLanguage {
    /// Localizations shipped with the app, in priority order of the device's preferences.
    public static var code: String {
        let resolved = Bundle.main.preferredLocalizations.first ?? "en"
        return resolved.hasPrefix("fr") ? "fr" : "en"
    }

    public static var isFrench: Bool { code == "fr" }

    /// A locale for formatting in the interface language, keeping the device region when it matches.
    public static var locale: Locale {
        let current = Locale.current
        if current.language.languageCode?.identifier == code { return current }
        return Locale(identifier: code == "fr" ? "fr_FR" : "en_US")
    }

    /// The locale identifier passed to deterministic composers such as the morning briefing.
    public static var localeIdentifier: String { locale.identifier }
}
