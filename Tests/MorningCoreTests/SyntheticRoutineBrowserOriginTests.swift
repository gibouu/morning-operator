import Foundation
import Testing
@testable import MorningCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

@Suite("Closed synthetic routine browser input")
struct SyntheticRoutineBrowserOriginTests {
    let workspace = UUID(uuidString: "74000000-0000-4000-8000-000000000001")!
    var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("MorningOperatorUITests-\(workspace.uuidString)", isDirectory: true) }
    var flags: [String] { ["--ui-testing", "--fixture-mode", SyntheticRoutineBrowserOrigin.flag, "--ui-testing-workspace=\(workspace)"] }
    let feedID = UUID(uuidString: "90000000-0000-4000-8000-000000000005")!

    @Test("No partial, ambiguous or ordinary activation can substitute a page")
    func activation() {
        #if DEBUG
        #expect(SyntheticRoutineBrowserOrigin.requested(arguments: flags, directory: directory, site: .reddit, stepID: feedID) != nil)
        for missing in flags.indices {
            #expect(SyntheticRoutineBrowserOrigin.requested(arguments: flags.enumerated().filter { $0.offset != missing }.map(\.element), directory: directory, site: .reddit, stepID: feedID) == nil)
        }
        for wrong in [directory.deletingLastPathComponent(), directory.appendingPathComponent("nested")] {
            #expect(SyntheticRoutineBrowserOrigin.requested(arguments: flags, directory: wrong, site: .reddit, stepID: feedID) == nil)
        }
        #expect(SyntheticRoutineBrowserOrigin.requested(arguments: flags + ["--ui-testing-workspace=\(UUID())"], directory: directory, site: .reddit, stepID: feedID) == nil)
        #expect(SyntheticRoutineBrowserOrigin.requested(arguments: flags, directory: directory, site: .reddit, stepID: UUID()) == nil)
        #expect(SyntheticRoutineBrowserOrigin.requested(arguments: flags, directory: directory, site: .instagram, stepID: feedID) == nil)
        #else
        #expect(SyntheticRoutineBrowserOrigin.requested(arguments: flags, directory: directory, site: .reddit, stepID: feedID) == nil)
        #endif
    }

    #if DEBUG
    @Test("Each input is bound to one exact workspace, site, moment and local document")
    func closedResources() throws {
        for (site, suffix, path) in [(WebMorningSite.reddit, "5", "/feed"), (.youtube, "6", "/videos"), (.youtube, "9", "/music")] {
            let step = UUID(uuidString: "90000000-0000-4000-8000-00000000000" + suffix)!
            let origin = try #require(SyntheticRoutineBrowserOrigin.requested(arguments: flags, directory: directory, site: site, stepID: step))
            #expect(origin.startURL.path == path)
            #expect(origin.permits(origin.startURL))
            #expect(WebMorningExecutionPolicy.permits(site: site, url: origin.startURL, syntheticRoutine: origin))
            #expect(!WebMorningExecutionPolicy.permits(site: site, url: origin.startURL))
            #expect(!WebMorningExecutionPolicy.permits(site: .news, url: origin.startURL, syntheticRoutine: origin))
            #expect(WebMorningSite(url: origin.startURL) == nil)
            for raw in ["https://www.reddit.com/", "more-qa-routine://\(UUID())\(path)",
                        origin.startURL.absoluteString + "?remote=1", origin.startURL.absoluteString + "#fragment",
                        "more-qa-routine://\(workspace.uuidString.lowercased()):443\(path)",
                        "more-qa-routine://reader@\(workspace.uuidString.lowercased())\(path)",
                        "more-qa-routine://\(workspace.uuidString.lowercased())/other"] {
                #expect(!origin.permits(URL(string: raw)))
            }
            #expect(WebMorningExecutionPolicy.script(site: site, behavior: .readUnread, syntheticRoutine: origin) == "JSON.stringify({status:'unavailable'})")
        }
    }
    #if canImport(JavaScriptCore)
    @Test("The DOM guard refuses another namespace even when opaque origins are equal")
    @MainActor func domOrigin() throws {
        let origin = try #require(SyntheticRoutineBrowserOrigin.requested(arguments: flags, directory: directory, site: .reddit, stepID: feedID))
        let js = try #require(JSContext())
        for (host, path, search, expected) in [(workspace.uuidString.lowercased(), "/feed", "", true),
            (UUID().uuidString.lowercased(), "/feed", "", false), (workspace.uuidString.lowercased(), "/videos", "", false),
            (workspace.uuidString.lowercased(), "/feed", "?network=1", false)] {
            let data = try JSONSerialization.data(withJSONObject: ["protocol": "more-qa-routine:", "hostname": host,
                "pathname": path, "search": search, "port": "", "username": "", "password": "", "hash": ""])
            js.evaluateScript("var candidate=\(String(decoding: data, as: UTF8.self));")
            #expect(js.evaluateScript(origin.javascriptPermits("candidate"))?.toBool() == expected)
        }
    }
    #endif
    #endif

    @Test("Media time is an observed finite bounded value, not an elapsed routine budget")
    func mediaTime() {
        #expect(WebMorningPageObservation.parse(#"{"status":"ready","fingerprint":"video-one","mediaPlaying":true,"mediaPlaybackSeconds":1.25}"#)?.mediaPlaybackSeconds == 1.25)
        for time in ["-1", "604801", "1e300"] {
            #expect(WebMorningPageObservation.parse("{\"status\":\"ready\",\"fingerprint\":\"v\",\"mediaPlaybackSeconds\":\(time)}") == nil)
        }
    }
}
