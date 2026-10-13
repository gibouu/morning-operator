import Foundation
import Testing
@testable import MorningApple

/// Guards the build, not the wording: a toolchain that copies `Localizable.xcstrings`
/// into the bundle without compiling it leaves every lookup returning its English key,
/// and tests of French text or plurals then prove nothing.
@Suite("String Catalogs are compiled into the package bundle")
struct StringCatalogLoadingTests {
    private func table(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"),
            "No \(language).lproj in the package bundle: the String Catalog was not compiled.")
        return try #require(Bundle(path: path))
    }

    @Test func frenchTextLoadsFromTheCompiledCatalog() throws {
        let french = try table("fr")
        #expect(french.localizedString(forKey: "Evidence:", value: nil, table: nil) == "Source :")
    }

    @Test func pluralFormsResolveFromTheCompiledCatalog() throws {
        let english = try table("en")
        let key = "%lld frames contain truncated or omitted OCR and cannot support app identification."
        let format = english.localizedString(forKey: key, value: nil, table: nil)
        #expect(String.localizedStringWithFormat(format, 1)
            == "1 frame contains truncated or omitted OCR and cannot support app identification.")
        #expect(String.localizedStringWithFormat(format, 2)
            == "2 frames contain truncated or omitted OCR and cannot support app identification.")
    }
}
