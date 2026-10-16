import Foundation

/// French follows the primary device language; every other language uses English.
public enum AppLanguage {
    public static var code: String {
        resolvedCode(preferredLanguages: Locale.preferredLanguages)
    }

    public static var isFrench: Bool { code == "fr" }

    /// Keep regional formats and explicit calendar/number preferences in the UI language.
    public static var locale: Locale {
        resolvedLocale(preferredLanguages: Locale.preferredLanguages, current: .current)
    }

    /// The locale identifier passed to deterministic composers such as the morning briefing.
    public static var localeIdentifier: String { locale.identifier }

    /// A resource's locale selects the translation; String's locale only formats values.
    public static func localized(_ value: String.LocalizationValue, table: String? = nil,
                                 bundle: Bundle = .main, comment: StaticString? = nil) -> String {
        localized(value, table: table, bundle: bundle, locale: locale, comment: comment)
    }

    static func localized(_ value: String.LocalizationValue, table: String? = nil,
                          bundle: Bundle, locale: Locale, comment: StaticString? = nil) -> String {
        String(localized: LocalizedStringResource(value, table: table, locale: locale,
                                                 bundle: .atURL(bundle.bundleURL), comment: comment))
    }

    static func resolvedCode(preferredLanguages: [String]) -> String {
        guard let primary = preferredLanguages.first else { return "en" }
        return Locale.Language(identifier: primary).languageCode?.identifier == "fr" ? "fr" : "en"
    }

    static func resolvedLocale(preferredLanguages: [String], current: Locale) -> Locale {
        let language = resolvedCode(preferredLanguages: preferredLanguages)
        guard current.language.languageCode?.identifier != language else { return current }
        var components = Locale.Components(locale: current)
        components.languageComponents.languageCode = Locale.LanguageCode(language)
        components.languageComponents.script = nil
        return Locale(components: components)
    }
}
