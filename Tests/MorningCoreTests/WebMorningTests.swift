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

    @Test("Slack workspace hosts are bounded and saved message destinations survive routing")
    func messagingBrowserDestinations() throws {
        for address in ["https://app.slack.com/client/TEXAMPLE/CEXAMPLE", "https://team-42.slack.com/archives/CEXAMPLE",
                        "https://www.linkedin.com/messaging/thread/example/"] {
            let destination = url(address)
            let target = RoutineStepTarget.externalApp(.safari, detail: address)
            #expect(target.routineExecutionTarget == .inAppWeb(site: destination))
            #expect(target.externalURL == nil)
            let restored = try JSONDecoder().decode(RoutineStepTarget.self, from: JSONEncoder().encode(target))
            #expect(restored.routineExecutionTarget == .inAppWeb(site: destination))
        }
        for host in ["slack.com.evil.example", "workspace.slack.com.evil.example", "a.b.slack.com",
                     "-workspace.slack.com", "workspace-.slack.com", "workspace_name.slack.com",
                     String(repeating: "a", count: 64) + ".slack.com", "signin.slack.com", "slackusercontent.com"] {
            #expect(!WebMorningSite.slack.table.permits(host: host), "\(host)")
            #expect(WebMorningSite(url: url("https://\(host)/")) == nil)
        }
        #expect(WebMorningPolicy.isSignInPage(url("https://signin.slack.com/")))
        #expect(!BrowserRhythmPolicy.permits(site: .slack, url: url("https://signin.slack.com/")))
        #expect(BrowserRhythmPolicy.behavior(site: .slack, url: url("https://team.slack.com/client/")) == nil)
        #expect(BrowserRhythmPolicy.behavior(site: .linkedin, url: url("https://www.linkedin.com/messaging/")) == nil)
        #expect(BrowserRhythmPolicy.behavior(site: .linkedin, url: url("https://www.linkedin.com/feed/")) == .browseFeed)
        #expect(BrowserLearningTrace.observedBehaviors(for: .slack).isEmpty)
        #expect(BrowserLearningTrace.observedBehaviors(for: .linkedin) == [.browseFeed])
    }

    #if canImport(JavaScriptCore)
    @Test("Native and isolated scripts enforce the same Slack workspace host boundary")
    func matchingWorkspaceHostGuards() throws {
        let context = try #require(JSContext())
        let hosts = ["app.slack.com", "TEAM.slack.com", "a.slack.com", "team-42.slack.com", "signin.slack.com",
                     "-team.slack.com", "team-.slack.com", "a.b.slack.com", "a.slack.com.evil.example",
                     String(repeating: "a", count: 63) + ".slack.com", String(repeating: "a", count: 64) + ".slack.com"]
        for host in hosts {
            context.setObject(host, forKeyedSubscript: "hostname" as NSString)
            let scriptResult = context.evaluateScript(WebMorningSite.slack.table.javascriptPermitsHost("hostname"))?.toBool()
            #expect(scriptResult == WebMorningSite.slack.table.permits(host: host), "\(host)")
        }
        #expect(context.exception == nil)
    }
    #endif

    @Test("Social browser routes accept exact HTTPS hosts and keep saved destinations")
    func socialBrowserRoutes() throws {
        let routes: [(WebMorningSite, String)] = [
            (.tiktok, "https://www.tiktok.com/@example/video/123"),
            (.twitter, "https://x.com/home"),
            (.twitter, "https://twitter.com/example/status/123"),
            (.reddit, "https://www.reddit.com/r/example/"),
            (.facebook, "https://m.facebook.com/"),
            (.threads, "https://www.threads.com/@example"),
            (.threads, "https://www.threads.net/@example"),
            (.linkedin, "https://www.linkedin.com/messaging/thread/example/"),
            (.slack, "https://app.slack.com/client/TEXAMPLE/CEXAMPLE"),
            (.slack, "https://my-workspace.slack.com/archives/CEXAMPLE")
        ]
        for (site, address) in routes {
            let page = url(address)
            #expect(WebMorningSite(url: page) == site)
            let saved = RoutineStepTarget.inAppWeb(site: page)
            let restored = try JSONDecoder().decode(RoutineStepTarget.self, from: JSONEncoder().encode(saved))
            #expect(restored == saved)
            if case let .inAppWeb(restoredURL) = restored { #expect(WebMorningSite(url: restoredURL) == site) }
            let host = try #require(page.host)
            for rejected in ["http://\(host)/", "https://\(host).evil.example/", "https://user:secret@\(host)/",
                             "https://\(host):8443/"] {
                #expect(WebMorningSite(url: url(rejected)) == nil)
            }
        }
        for rawID in ["instagram", "youtube", "news", "whatsapp", "gmail", "twitter", "tiktok", "linkedin", "slack"] {
            let encoded = Data("\"\(rawID)\"".utf8)
            #expect(try JSONDecoder().decode(WebMorningSite.self, from: encoded).rawValue == rawID)
        }
    }

    @Test("New social destinations offer manual browsing without invented readers or scroll actions")
    func uncalibratedSitesOfferNoScripts() {
        for site in [WebMorningSite.tiktok, .twitter, .reddit, .facebook, .threads, .linkedin, .slack] {
            #expect(WebMorningSite(url: site.table.startURL) == site)
            #expect(site.table.tasks.isEmpty)
            #expect(site.table.feedURL == nil)
            for task in WebMorningTask.allCases {
                #expect(WebMorningPolicy.script(for: task, on: site) == nil)
                #expect(WebMorningPolicy.refusal(for: task, on: site, at: site.table.startURL) == .notOffered)
            }
        }
    }

    @Test("Provider sign-in and onboarding routes block every task, including passive rhythm collection")
    func socialSignInRoutes() {
        let routes: [(WebMorningSite, String)] = [
            (.twitter, "https://x.com/i/flow"), (.twitter, "https://x.com/i/flow/login"),
            (.twitter, "https://x.com/i/jf"), (.twitter, "https://twitter.com/i/jf/entrance"),
            (.twitter, "https://x.com/onboarding"),
            (.tiktok, "https://www.tiktok.com/passport/web/"),
            (.tiktok, "https://www.tiktok.com/login/phone-or-email/email"),
            (.tiktok, "https://www.tiktok.com/signup"),
            (.reddit, "https://www.reddit.com/login"), (.reddit, "https://www.reddit.com/register/"),
            (.facebook, "https://m.facebook.com/login.php"),
            (.facebook, "https://www.facebook.com/checkpoint/123/"),
            (.threads, "https://www.threads.com/login"),
            (.threads, "https://www.threads.net/accounts/login/"),
            (.linkedin, "https://www.linkedin.com/uas/login"),
            (.linkedin, "https://www.linkedin.com/checkpoint/challenge/"),
            (.slack, "https://my-workspace.slack.com/signin"),
            (.slack, "https://slack.com/signin")
        ]
        for (site, address) in routes {
            let page = url(address)
            #expect(WebMorningPolicy.isSignInPage(page))
            #expect(!BrowserRhythmPolicy.permits(site: site, url: page))
            for task in WebMorningTask.allCases {
                #expect(WebMorningPolicy.refusal(for: task, on: site, at: page) == .signInPage)
            }
        }
    }

    @Test func tasksRunOnlyWhereTheTableOffersThem() {
        #expect(WebMorningSite.gmail.table.tasks.isEmpty)
        #expect(WebMorningPolicy.refusal(for: .unreadCount, on: .gmail, at: url("https://mail.google.com/mail/u/0/")) == .notOffered)
        #expect(WebMorningPolicy.script(for: .unreadCount, on: .gmail) == nil)
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
