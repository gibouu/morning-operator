import Foundation
import Testing
@testable import MorningCore

@Suite("Primary device language")
struct AppLanguageTests {
    @Test("French variants use French regardless of region", arguments: [
        "fr", "fr-FR", "fr-CA", "fr-BE", "fr-CH", "fr_CA", "fr-Latn-CA", "fr-CA-u-ca-gregory"
    ])
    func frenchVariants(_ primary: String) {
        #expect(AppLanguage.resolvedCode(preferredLanguages: [primary, "en-US"]) == "fr")
    }

    @Test("A secondary French preference never changes a non-French primary language", arguments: [
        "en", "en-GB", "es-ES", "de-DE", "ar-SA", "ja-JP", "zh-Hant-TW", "pt-BR", ""
    ])
    func otherLanguagesUseEnglish(_ primary: String) {
        #expect(AppLanguage.resolvedCode(preferredLanguages: [primary, "fr-FR", "en-US"]) == "en")
    }

    @Test("Missing language preferences default to English")
    func missingPreferences() {
        #expect(AppLanguage.resolvedCode(preferredLanguages: []) == "en")
    }

    @Test("Only the exact persisted picker pair is removed", arguments: ["fr", "en"])
    func removesIdentifiableLegacyPair(_ code: String) throws {
        try withIsolatedDefaults { defaults, name in
            defaults.setPersistentDomain(["more.appLanguage": code, "AppleLanguages": [code],
                                          "unrelated": "kept", "readAloud": true], forName: name)
            AppLanguage.removeLegacyLanguageOverride(in: defaults, domainName: name)
            let domain = try #require(defaults.persistentDomain(forName: name))
            #expect(domain["more.appLanguage"] == nil)
            #expect(domain["AppleLanguages"] == nil)
            #expect(domain["unrelated"] as? String == "kept")
            #expect(domain["readAloud"] as? Bool == true)
        }
    }

    @Test("A changed, multiple or unidentifiable persisted language preference is retained")
    func preservesOtherLanguagePreferences() throws {
        let alternatives: [Any] = [["en"], ["fr", "en"], "fr", 17]
        for languages in alternatives {
            try withIsolatedDefaults { defaults, name in
                defaults.setPersistentDomain(["more.appLanguage": "fr", "AppleLanguages": languages,
                                              "unrelated": "kept"], forName: name)
                var expected = try #require(defaults.persistentDomain(forName: name))
                if let codes = languages as? [String] {
                    #expect(expected["AppleLanguages"] as? [String] == codes)
                } else if let persisted = expected["AppleLanguages"] {
                    if let text = languages as? String {
                        #expect(persisted as? String == text)
                    } else {
                        #expect(persisted as? Int == languages as? Int)
                    }
                }
                // Foundation may reject malformed AppleLanguages values on write.
                // Preserve the actual persisted snapshot, not an unpersisted input.
                expected.removeValue(forKey: "more.appLanguage")
                AppLanguage.removeLegacyLanguageOverride(in: defaults, domainName: name)
                let domain = try #require(defaults.persistentDomain(forName: name))
                #expect(domain["more.appLanguage"] == nil)
                #expect(NSDictionary(dictionary: domain).isEqual(to: expected))
                #expect(domain["unrelated"] as? String == "kept")
                // The old marker cannot later erase a newly matching preference.
                defaults.set(["fr"], forKey: "AppleLanguages")
                AppLanguage.removeLegacyLanguageOverride(in: defaults, domainName: name)
                #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["fr"])
            }
        }
    }

    @Test("Argument and registered defaults cannot identify an old persisted picker choice")
    func ignoresNonpersistentMarkers() throws {
        let processLanguages = Locale.preferredLanguages
        for useArguments in [true, false] {
            try withIsolatedDefaults(make: { NonpersistentOverlayDefaults(suiteName: $0) }) { defaults, name in
                defaults.setPersistentDomain(["AppleLanguages": ["fr"], "unrelated": "kept"], forName: name)
                if useArguments {
                    defaults.setVolatileDomain(["more.appLanguage": "fr"], forName: UserDefaults.argumentDomain)
                } else {
                    defaults.register(defaults: ["more.appLanguage": "fr"])
                }
                #expect(defaults.object(forKey: "more.appLanguage") as? String == "fr")
                #expect(defaults.string(forKey: "more.appLanguage") == "fr")
                AppLanguage.removeLegacyLanguageOverride(in: defaults, domainName: name)
                #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["fr"])
                #expect(defaults.object(forKey: "more.appLanguage") as? String == "fr")

                // An argument override must not make different persisted values match.
                defaults.setPersistentDomain(["more.appLanguage": "fr", "AppleLanguages": ["en"],
                                              "unrelated": "kept"], forName: name)
                defaults.setVolatileDomain(["AppleLanguages": ["fr"]], forName: UserDefaults.argumentDomain)
                AppLanguage.removeLegacyLanguageOverride(in: defaults, domainName: name)
                let domain = try #require(defaults.persistentDomain(forName: name))
                #expect(domain["more.appLanguage"] == nil)
                #expect(domain["AppleLanguages"] as? [String] == ["en"])
                #expect(domain["unrelated"] as? String == "kept")
                #expect(defaults.volatileDomain(forName: UserDefaults.argumentDomain)["AppleLanguages"] as? [String] == ["fr"])
            }
        }
        #expect(Locale.preferredLanguages == processLanguages)
    }

    @Test("Absent or unknown markers leave the persisted domain untouched")
    func preservesUnmarkedPreferences() throws {
        try withIsolatedDefaults { defaults, name in
            AppLanguage.removeLegacyLanguageOverride(in: defaults, domainName: name)
            #expect(defaults.persistentDomain(forName: name) == nil)
            defaults.setPersistentDomain(["more.appLanguage": "es", "AppleLanguages": ["es"],
                                          "unrelated": "kept"], forName: name)
            AppLanguage.removeLegacyLanguageOverride(in: defaults, domainName: name)
            let domain = try #require(defaults.persistentDomain(forName: name))
            #expect(domain["more.appLanguage"] as? String == "es")
            #expect(domain["AppleLanguages"] as? [String] == ["es"])
            #expect(domain["unrelated"] as? String == "kept")
        }
    }

    private func withIsolatedDefaults(make: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) },
                                      _ body: (UserDefaults, String) throws -> Void) throws {
        let name = "test.more.language-migration." + UUID().uuidString
        let defaults = try #require(make(name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, name)
    }

    @Test("Region does not select the interface language")
    func languageIsIndependentOfRegion() {
        let french = AppLanguage.resolvedLocale(preferredLanguages: ["fr-CA"], current: Locale(identifier: "en_US"))
        #expect(french.language.languageCode?.identifier == "fr")
        #expect(french.region?.identifier == "US")
        let english = AppLanguage.resolvedLocale(preferredLanguages: ["es-ES", "fr-FR"], current: Locale(identifier: "fr_FR"))
        #expect(english.language.languageCode?.identifier == "en")
        #expect(english.region?.identifier == "FR")
    }

    @Test("Fallback preserves regional, calendar, and hour-format preferences")
    func preservesRegionalPreferences() {
        var components = Locale.Components(languageCode: "ar", script: "Arab", languageRegion: "SA")
        components.calendar = .gregorian
        components.hourCycle = .zeroToTwentyThree
        components.numberingSystem = Locale.NumberingSystem("latn")
        let current = Locale(components: components)
        let resolved = AppLanguage.resolvedLocale(preferredLanguages: ["ar-SA", "fr-FR"], current: current)
        #expect(resolved.language.languageCode?.identifier == "en")
        #expect(resolved.language.script?.identifier == "Latn")
        #expect(resolved.region == current.region)
        #expect(resolved.calendar.identifier == current.calendar.identifier)
        #expect(resolved.hourCycle == current.hourCycle)
        #expect(resolved.numberingSystem == current.numberingSystem)
    }

    @Test("A locale already using the interface language keeps its exact settings")
    func matchingLocaleIsPreserved() {
        let current = Locale(identifier: "fr_CA@calendar=gregorian;hours=h23;numbers=latn")
        #expect(AppLanguage.resolvedLocale(preferredLanguages: ["fr-CA"], current: current) == current)
    }

    @Test("Bundle lookup follows the primary language rather than secondary French")
    func bundleLookupFollowsTheResolvedLanguage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info: [String: Any] = ["CFBundleIdentifier": "test.more.language", "CFBundleDevelopmentRegion": "en",
                                   "CFBundleLocalizations": ["en", "fr"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"))
        for (code, strings) in [
            "en": ["Weather": "Weather", "Next: %@": "Next: %@"],
            "fr": ["Weather": "Météo", "Next: %@": "Ensuite : %@"]
        ] {
            let localization = directory.appendingPathComponent(code + ".lproj")
            try FileManager.default.createDirectory(at: localization, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
                .write(to: localization.appendingPathComponent("Localizable.strings"))
        }
        let bundle = try #require(Bundle(url: directory))
        let english = AppLanguage.resolvedLocale(preferredLanguages: ["es-ES", "fr-FR"], current: Locale(identifier: "es_ES"))
        let french = AppLanguage.resolvedLocale(preferredLanguages: ["fr-CA", "en"], current: Locale(identifier: "en_US"))
        #expect(AppLanguage.localized("Weather", bundle: bundle, locale: english) == "Weather")
        #expect(AppLanguage.localized("Weather", bundle: bundle, locale: french) == "Météo")
        let next = "Calendar"
        #expect(AppLanguage.localized("Next: \(next)", bundle: bundle, locale: english) == "Next: Calendar")
        #expect(AppLanguage.localized("Next: \(next)", bundle: bundle, locale: french) == "Ensuite : Calendar")
    }
}

/// Foundation's NSArgumentDomain and registration domain are process-shared even
/// for named suites. Keep their aggregate lookup behavior local to this test
/// double; the UUID persistent domain and its removal use real UserDefaults.
/// Each mutable instance stays inside one synchronous test scope.
private final class NonpersistentOverlayDefaults: UserDefaults, @unchecked Sendable {
    private var argumentValues: [String: Any] = [:]
    private var registeredValues: [String: Any] = [:]

    override func setVolatileDomain(_ domain: [String: Any], forName domainName: String) {
        precondition(domainName == UserDefaults.argumentDomain)
        argumentValues = domain
    }

    override func volatileDomain(forName domainName: String) -> [String: Any] {
        domainName == UserDefaults.argumentDomain ? argumentValues : super.volatileDomain(forName: domainName)
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        registeredValues.merge(registrationDictionary, uniquingKeysWith: { _, new in new })
    }

    override func object(forKey defaultName: String) -> Any? {
        argumentValues[defaultName] ?? super.object(forKey: defaultName) ?? registeredValues[defaultName]
    }
}
