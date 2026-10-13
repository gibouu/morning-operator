import Foundation
import Testing
@testable import MorningApple

/// Guards the build, not the wording: a toolchain that copies `Localizable.xcstrings`
/// into the bundle without compiling it leaves every lookup returning its English key,
/// and tests of French text or plurals then prove nothing. Expected text is read from
/// the catalog itself, so a translation edit never fails these checks.
@Suite("String Catalogs are compiled into the package bundle")
struct StringCatalogLoadingTests {
    private func table(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"),
            "No \(language).lproj in the package bundle: the String Catalog was not compiled.")
        return try #require(Bundle(path: path))
    }

    /// The catalog source as written, keyed by English text.
    private func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MorningApple/Resources/Localizable.xcstrings")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try #require(root["strings"] as? [String: Any])
    }

    @Test func frenchTextLoadsFromTheCompiledCatalog() throws {
        let french = try table("fr")
        var checked = 0
        for (key, entry) in try catalog() {
            guard let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any],
                  let unit = (localizations["fr"] as? [String: Any])?["stringUnit"] as? [String: Any],
                  let expected = unit["value"] as? String, expected != key, !key.contains("%") else { continue }
            #expect(french.localizedString(forKey: key, value: nil, table: nil) == expected)
            checked += 1
        }
        #expect(checked > 50, "Too few plain French entries were found to prove anything.")
    }

    @Test func pluralFormsResolveFromTheCompiledCatalog() throws {
        let english = try table("en")
        let key = "%lld frames contain truncated or omitted OCR and cannot support app identification."
        #expect(try catalog()[key] != nil, "Pick another plural entry: this one left the catalog.")
        let format = english.localizedString(forKey: key, value: nil, table: nil)
        // Pinned locale: the machine's own would change the digits, not the plural rule.
        let locale = Locale(identifier: "en_US_POSIX")
        let one = String(format: format, locale: locale, arguments: [1])
        let two = String(format: format, locale: locale, arguments: [2])
        #expect(one.hasPrefix("1 ") && two.hasPrefix("2 "))
        #expect(one.dropFirst(2) != two.dropFirst(2), "One and two used the same form: plurals were not compiled.")
        #expect(!one.contains("%") && !two.contains("%"))
    }
}
