import Foundation
import Testing
@testable import MorningCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

@Suite("Private synthetic news document boundary")
struct SyntheticNewsOriginTests {
    private let workspace = UUID(uuidString: "74000000-0000-4000-8000-000000000001")!
    private var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("MorningOperatorUITests-\(workspace.uuidString)", isDirectory: true) }
    private var flags: [String] { ["--ui-testing", "--fixture-mode", "--ui-testing-private-news", "--ui-testing-workspace=\(workspace)"] }

    @Test("Activation requires every private flag and the exact isolated workspace")
    func activation() {
        #if DEBUG
        #expect(SyntheticNewsOrigin.requested(arguments: flags, directory: directory) != nil)
        for missing in flags.indices {
            #expect(SyntheticNewsOrigin.requested(arguments: flags.enumerated().filter { $0.offset != missing }.map(\.element), directory: directory) == nil)
        }
        for extra in ["--ui-testing-workspace=invalid", "--ui-testing-workspace=\(UUID())"] {
            #expect(SyntheticNewsOrigin.requested(arguments: flags + [extra], directory: directory) == nil)
        }
        for wrong in [directory.deletingLastPathComponent(), directory.appendingPathComponent("nested"), URL(fileURLWithPath: "/not-the-test-directory/MorningOperatorUITests-\(workspace)")] {
            #expect(SyntheticNewsOrigin.requested(arguments: flags, directory: wrong) == nil)
        }
        #else
        #expect(SyntheticNewsOrigin.requested(arguments: flags, directory: directory) == nil)
        #endif
    }

    #if DEBUG
    @Test("A private origin admits only its four local news documents, never a network or other behavior")
    func closedRegistry() throws {
        let source = try #require(SyntheticNewsOrigin.requested(arguments: flags, directory: directory))
        let host = workspace.uuidString.lowercased()
        for path in SyntheticNewsOrigin.paths {
            let url = URL(string: "more-qa-news://\(host)\(path)")!
            #expect(source.permits(url))
            #expect(WebMorningExecutionPolicy.permits(site: .news, url: url, syntheticNews: source))
            #expect(!WebMorningExecutionPolicy.permits(site: .news, url: url))
            #expect(!WebMorningExecutionPolicy.permits(site: .reddit, url: url, syntheticNews: source))
            #expect(!WebArticlePolicy.isPage(url))
            #expect(!WebArticlePolicy.permitsResponse(selected: url, observed: url, status: 200))
        }
        for raw in ["https://www.lemonde.fr/", "https://\(host)/headlines", "more-qa-news://\(UUID())/headlines",
                    "more-qa-news://reader@\(host)/headlines", "more-qa-news://\(host):443/headlines",
                    "more-qa-news://\(host)/outside", "more-qa-news://\(host)/article/%74wo",
                    "more-qa-news://\(host)/headlines?url=https://example.org", "more-qa-news://\(host)/headlines#hidden"] {
            #expect(!source.permits(URL(string: raw)))
        }
        #expect(WebMorningSite(url: source.startURL) == nil, "The private scheme never becomes an ordinary saved site.")
        #expect(WebMorningExecutionPolicy.permits(site: .news, url: URL(string: "https://www.lemonde.fr/")))
    }

    @Test("Observed choices reject stale links, an unregistered destination, and another session or page generation")
    func observedSelection() throws {
        let source = try #require(SyntheticNewsOrigin.requested(arguments: flags, directory: directory))
        let context = MorningVoiceCommandContext(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID()), privacy = UUID()
        let second = URL(string: "more-qa-news://\(workspace.uuidString.lowercased())/article/two")!
        let links = [WebArticleLink(title: "SYNTHETIC second title", href: second)]
        let snapshot = try #require(WebNewsSnapshot(context: context, privacyGeneration: privacy, pageGeneration: 3,
            pageURL: source.startURL, fingerprint: "observed-list", links: links, syntheticNews: source))
        func observation(fingerprint: String, link: URL) throws -> WebMorningPageObservation {
            let data = try JSONSerialization.data(withJSONObject: ["status": "ready", "fingerprint": fingerprint,
                "articles": [["title": "SYNTHETIC second title", "href": link.absoluteString]]])
            return try #require(WebMorningPageObservation.parse(String(decoding: data, as: UTF8.self)))
        }
        #expect(snapshot.matchesObservation(try observation(fingerprint: "observed-list", link: second)))
        #expect(!snapshot.matchesObservation(try observation(fingerprint: "new-list", link: second)))
        let changedRegisteredLink = URL(string: "more-qa-news://\(workspace.uuidString.lowercased())/article/three")!
        #expect(!snapshot.matchesObservation(try observation(fingerprint: "observed-list", link: changedRegisteredLink)))
        let outside = URL(string: "more-qa-news://\(workspace.uuidString.lowercased())/not-registered")!
        #expect(!snapshot.matchesObservation(try observation(fingerprint: "observed-list", link: outside)))
        #expect(WebNewsSnapshot(context: context, privacyGeneration: privacy, pageGeneration: 3, pageURL: source.startURL,
            fingerprint: "observed-list", links: [.init(title: "SYNTHETIC", href: outside)], syntheticNews: source) == nil)
        #expect(!snapshot.matches(context: context, privacyGeneration: privacy, pageGeneration: 4, pageURL: source.startURL))
        #expect(!snapshot.matches(context: .init(sessionID: UUID(), routineVersionID: context.routineVersionID, stepID: context.stepID),
            privacyGeneration: privacy, pageGeneration: 3, pageURL: source.startURL))
        #expect(WebArticlePolicy.matchesDestination(second, selected: second, syntheticNews: source))
        #expect(!WebArticlePolicy.matchesDestination(outside, selected: second, syntheticNews: source))
    }

    #if canImport(JavaScriptCore)
    @Test("The DOM boundary compares the explicit private scheme, workspace and resource, not opaque origin equality")
    @MainActor func scriptOrigin() throws {
        let source = try #require(SyntheticNewsOrigin.requested(arguments: flags, directory: directory))
        let js = try #require(JSContext())
        for (scheme, host, path, query, allowed) in [
            ("more-qa-news:", workspace.uuidString.lowercased(), "/headlines", "", true),
            ("more-qa-news:", workspace.uuidString.lowercased(), "/article/two", "", true),
            ("more-qa-news:", UUID().uuidString.lowercased(), "/headlines", "", false),
            ("https:", workspace.uuidString.lowercased(), "/headlines", "", false),
            ("more-qa-news:", workspace.uuidString.lowercased(), "/missing", "", false),
            ("more-qa-news:", workspace.uuidString.lowercased(), "/headlines", "?remote=1", false)] {
            let data = try JSONSerialization.data(withJSONObject: ["protocol": scheme, "hostname": host, "pathname": path,
                "port": "", "username": "", "password": "", "hash": "", "search": query])
            js.evaluateScript("var candidate=\(String(decoding: data, as: UTF8.self));")
            #expect(js.evaluateScript(source.javascriptPermits("candidate"))?.toBool() == allowed)
        }
        #expect(WebMorningExecutionPolicy.script(site: .reddit, behavior: .browseFeed, syntheticNews: source) == "JSON.stringify({status:'unavailable'})")
    }
    #endif
    #endif
}
