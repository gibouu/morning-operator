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
