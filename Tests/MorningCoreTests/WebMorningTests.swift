import Foundation
import Testing
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif
@testable import MorningCore

@Suite("In-app browser: policy, scripts and outcomes")
struct WebMorningTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func noScriptRunsOnSignInPagesOrOtherSites() {
        let refusals: [(WebMorningSite, String, WebMorningRefusal)] = [
            (.instagram, "https://www.instagram.com/accounts/login/", .signInPage),
            (.instagram, "https://www.instagram.com/challenge/123/", .signInPage),
            (.instagram, "https://www.instagram.com/accounts/login/two_factor?next=%2F", .signInPage),
            (.gmail, "https://accounts.google.com/v3/signin/identifier?Email=a%40b.c", .otherSite),
            (.youtube, "https://accounts.google.com/ServiceLogin", .otherSite),
            (.youtube, "https://consent.youtube.com/m?continue=x", .otherSite),
            (.news, "https://www.lemonde.fr/connexion/", .signInPage),
            (.news, "http://www.lemonde.fr/", .notSecure),
            (.instagram, "https://www.facebook.com/login.php", .otherSite),
            (.whatsapp, "https://www.whatsapp.com/download", .otherSite)
        ]
        for (site, text, expected) in refusals {
            for task in WebMorningTask.allCases {
                let refusal = WebMorningPolicy.refusal(for: task, on: site, at: url(text))
                #expect(refusal != nil, "\(text) must refuse \(task)")
                if site.table.tasks.contains(task) { #expect(refusal == expected, "\(text)") }
            }
        }
        #expect(WebMorningPolicy.refusal(for: .nextVideo, on: .instagram, at: url("https://www.instagram.com/reels-not-a-feed/")) == .notTheFeed)
        #expect(WebMorningPolicy.refusal(for: .unreadCount, on: .instagram, at: url("https://www.instagram.com:8443/")) == .notSecure)
        #expect(WebMorningPolicy.refusal(for: .unreadCount, on: .instagram, at: url("https://user:secret@www.instagram.com/")) == .notSecure)
        #expect(WebMorningPolicy.refusal(for: .unreadCount, on: .instagram, at: nil) == .noPage)
        #expect(WebMorningPolicy.isSignInPage(nil))
    }

    @Test func targetURLsMapOnlyToExplicitSecureHosts() {
        #expect(WebMorningSite(url: url("https://m.youtube.com/shorts/abc")) == .youtube)
        #expect(WebMorningSite(url: url("https://instagram.com.evil.test/")) == nil)
        #expect(WebMorningSite(url: url("http://www.instagram.com/")) == nil)
        #expect(WebMorningSite(url: url("https://user:secret@www.instagram.com/")) == nil)
        #expect(WebMorningSite(url: url("https://www.instagram.com:8443/")) == nil)
    }

    @Test func tasksRunOnlyWhereTheTableOffersThem() {
        #expect(WebMorningPolicy.refusal(for: .headlines, on: .news, at: url("https://www.lemonde.fr/")) == nil)
        #expect(WebMorningPolicy.refusal(for: .nextVideo, on: .news, at: url("https://www.lemonde.fr/")) == .notOffered)
        #expect(WebMorningPolicy.refusal(for: .unreadCount, on: .instagram, at: url("https://www.instagram.com/")) == nil)
        #expect(WebMorningPolicy.refusal(for: .nextVideo, on: .instagram, at: url("https://www.instagram.com/")) == .notTheFeed)
        #expect(WebMorningPolicy.refusal(for: .nextVideo, on: .instagram, at: url("https://www.instagram.com/reels/abc/")) == nil)
        #expect(WebMorningPolicy.refusal(for: .nextVideo, on: .youtube, at: url("https://m.youtube.com/shorts/xyz")) == nil)
        #expect(WebMorningPolicy.refusal(for: .unreadCount, on: .whatsapp, at: url("https://web.whatsapp.com/")) == nil)
        for site in WebMorningSite.allCases {
            for task in WebMorningTask.allCases where !site.table.tasks.contains(task) {
                #expect(WebMorningPolicy.script(for: task, on: site) == nil)
            }
        }
    }

    /// The scripts read and scroll. Nothing in them can click, type, submit, send or load.
    @Test func scriptsCannotTakeASocialActionOrSendData() throws {
        let forbidden = [".click(", "submit", "fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", ".focus(", "dispatchEvent", "KeyboardEvent",
                         ".value", "MouseEvent", "PointerEvent", "TouchEvent", "innerHTML", "location.href =",
                         "location.assign", "window.open", "postMessage", "cookie", "localStorage", "setAttribute",
                         "eval(", "Function(", "import("]
        for site in WebMorningSite.allCases {
            for task in site.table.tasks {
                let script = try #require(WebMorningPolicy.script(for: task, on: site))
                for token in forbidden { #expect(!script.contains(token), "\(site) \(task) contains \(token)") }
                #expect(script.contains("input[type=\"password\"]"), "\(site) \(task) lacks the sign-in guard")
                #expect(script.contains("reason: \"layout\""), "\(site) \(task) must fail closed")
            }
        }
    }

    #if canImport(JavaScriptCore)
    /// Every generated script parses as JavaScript; a syntax error would only surface on the phone.
    @Test func scriptsParse() throws {
        for site in WebMorningSite.allCases {
            for task in site.table.tasks {
                let script = try #require(WebMorningPolicy.script(for: task, on: site))
                let context = try #require(JSContext())
                context.setObject(script, forKeyedSubscript: "source" as NSString)
                let result = context.evaluateScript("try { new Function('return ' + source); 'ok' } catch (e) { String(e) }")
                #expect(result?.toString() == "ok", "\(site) \(task)")
            }
        }
    }
    #endif

    @Test func outcomesAreBoundedAndFailClosed() {
        #expect(WebMorningOutcome.parse("{\"status\":\"ok\",\"count\":3}", task: .unreadCount) == .count(3))
        #expect(WebMorningOutcome.parse("{\"status\":\"ok\",\"count\":-1}", task: .unreadCount) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse("{\"status\":\"ok\",\"count\":\"3\"}", task: .unreadCount) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse("{\"status\":\"unsupported\",\"reason\":\"signin\"}", task: .unreadCount) == .unsupported("signin"))
        #expect(WebMorningOutcome.parse("{\"status\":\"unsupported\",\"reason\":\"<b>x</b>\"}", task: .unreadCount) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse(#"{"status":"ok","count":true}"#, task: .unreadCount) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse(#"{"status":"ok","count":1.5}"#, task: .unreadCount) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse(nil, task: .headlines) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse(42, task: .headlines) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse("{\"status\":\"ok\",\"headlines\":[\"One headline here\"]}", task: .headlines)
                == .headlines(["One headline here"]))
        let six = "[" + Array(repeating: "\"A long enough headline\"", count: 6).joined(separator: ",") + "]"
        #expect(WebMorningOutcome.parse("{\"status\":\"ok\",\"headlines\":\(six)}", task: .headlines) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse("{\"status\":\"ok\",\"method\":\"container\"}", task: .nextVideo)
                == .scrollRequested(method: "container"))
        #expect(WebMorningOutcome.parse(#"{"status":"ok","method":"key"}"#, task: .nextVideo) == .unsupported("malformed"))
        #expect(WebMorningOutcome.parse(String(repeating: " ", count: 5_000), task: .unreadCount) == .unsupported("malformed"))
    }

    @Test func logLinesCarryNoPageText() {
        let line = WebMorningOutcome.headlines(["Secret headline words"]).logLine(site: .news, task: .headlines)
        #expect(line == "WEBMORNING site=news task=headlines result=ok headlines=1")
        #expect(WebMorningOutcome.scrollRequested(method: "container").logLine(site: .youtube, task: .nextVideo)
                == "WEBMORNING site=youtube task=nextVideo result=scrollRequested method=container")
    }

    @Test func stepClockCountsDownAndExtends() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = WebMorningStepClock(start: start, minutes: 10)
        #expect(clock.remaining(at: start) == 600)
        #expect(clock.isOver(at: start.addingTimeInterval(600)))
        clock.extend(at: start.addingTimeInterval(700))
        #expect(clock.remaining(at: start.addingTimeInterval(700)) == 120)
        clock.extend(at: start.addingTimeInterval(700))
        #expect(clock.remaining(at: start.addingTimeInterval(700)) == 240)
        #expect(WebMorningStepClock(start: start, minutes: 0).remaining(at: start) == 60)
    }

}
