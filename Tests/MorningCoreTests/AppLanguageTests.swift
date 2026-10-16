import Foundation
import Testing
@testable import MorningCore

@Suite("Chosen and primary device language")
struct AppLanguageTests {
    @Test func savedChoiceWinsOverThePrimaryDeviceLanguage() {
        #expect(AppLanguage.resolve(saved: "en", preferredLanguages: ["fr-FR"]) == "en")
        #expect(AppLanguage.resolve(saved: "fr", preferredLanguages: ["en-US"]) == "fr")
        #expect(AppLanguage.resolve(saved: "fr", preferredLanguages: ["de-DE", "en-US"]) == "fr")
        #expect(AppLanguage.resolve(saved: "de", preferredLanguages: ["fr-CA"]) == "fr")
        #expect(AppLanguage.resolve(saved: "unsupported", preferredLanguages: ["de-DE", "fr-FR"]) == "en")
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: []) == "en")
        #expect(AppLanguage.supportedCodes == ["fr", "en"])
    }

    @Test func chosenLanguagePreservesRegionalFormats() {
        let current = Locale(identifier: "en_CA@calendar=gregorian;hours=h23;numbers=latn")
        let chosen = AppLanguage.resolvedLocale(saved: "fr", preferredLanguages: ["en-US"], current: current)
        #expect(chosen.language.languageCode?.identifier == "fr")
        #expect(chosen.region == current.region)
        #expect(chosen.calendar.identifier == current.calendar.identifier)
        #expect(chosen.hourCycle == current.hourCycle)
        #expect(chosen.numberingSystem == current.numberingSystem)
    }

    @Test("Reading a chosen language preserves its persisted preference and neighboring settings")
    func chosenPreferenceIsNotLegacyCleanup() throws {
        let name = "test.more.chosen-language." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setPersistentDomain(["more.appLanguage": "fr", "AppleLanguages": ["fr"],
                                      "readAloud": true, "unrelated": "kept"], forName: name)
        let before = try #require(defaults.persistentDomain(forName: name))
        #expect(AppLanguage.resolve(saved: defaults.string(forKey: AppLanguage.preferenceKey), preferredLanguages: ["en-US"]) == "fr")
        let after = try #require(defaults.persistentDomain(forName: name))
        #expect(NSDictionary(dictionary: before).isEqual(to: after))
        #expect(after["more.appLanguage"] as? String == "fr")
        #expect(after["AppleLanguages"] as? [String] == ["fr"])
    }

    @Test("Test-only argument and registered language overlays do not mutate the process locale")
    func languageOverridesStayInTheirIsolatedDefaults() throws {
        let processLanguages = Locale.preferredLanguages
        for arguments in [true, false] {
            let name = "test.more.language-overlay." + UUID().uuidString
            let defaults = try #require(NonpersistentOverlayDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.setPersistentDomain(["AppleLanguages": ["en"], "unrelated": "kept"], forName: name)
            if arguments {
                defaults.setVolatileDomain(["more.appLanguage": "fr", "AppleLanguages": ["fr"]], forName: UserDefaults.argumentDomain)
            } else { defaults.register(defaults: ["more.appLanguage": "fr"]) }
            #expect(AppLanguage.resolve(saved: defaults.string(forKey: AppLanguage.preferenceKey), preferredLanguages: ["en-US"]) == "fr")
            let persisted = try #require(defaults.persistentDomain(forName: name))
            #expect(persisted["more.appLanguage"] == nil)
            #expect(persisted["AppleLanguages"] as? [String] == ["en"])
            #expect(persisted["unrelated"] as? String == "kept")
        }
        #expect(Locale.preferredLanguages == processLanguages)
    }

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
        #expect(AppLanguage.bundle(for: bundle, languageCode: "fr").localizedString(forKey: "Weather", value: nil, table: nil) == "Météo")
        #expect(AppLanguage.bundle(for: bundle, languageCode: "en").localizedString(forKey: "Weather", value: nil, table: nil) == "Weather")
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
/// for named suites. Keep argument/registration lookup local to this test
/// double; only its UUID persistent domain uses real UserDefaults.
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
