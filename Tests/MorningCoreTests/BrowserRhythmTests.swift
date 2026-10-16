import Foundation
import Testing
@testable import MorningCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

@Suite("Browser rhythm aggregates")
struct BrowserRhythmTests {
    @Test("Cumulative snapshots do not double-count and cannot move backwards")
    func cumulative() throws {
        var rhythm = BrowserRhythmAccumulator(site: .instagram)
        let totals = try #require(BrowserRhythmTotals(distance: 600, movingSeconds: 2, scrollBursts: 2, clicks: 3))
        let first = rhythm.update(totals)
        let repeated = rhythm.update(totals)
        #expect(first)
        #expect(repeated)
        let smaller = try #require(BrowserRhythmTotals(distance: 10, movingSeconds: 1, scrollBursts: 1, clicks: 2))
        let backward = rhythm.update(smaller)
        #expect(!backward)
        let summary = rhythm.summary(durationSeconds: 20)
        #expect(summary.totals.distance == 600)
        #expect(summary.averageMovingSpeed == 300)
        #expect(summary.durationSeconds == 20)
        #expect(summary.site == .instagram)
    }

    @Test("Bad numeric aggregates are refused and an empty sample invents no speed")
    func invalid() {
        for value in [Double.nan, .infinity, -1, 10_000_001] {
            #expect(BrowserRhythmTotals(distance: value, movingSeconds: 1, scrollBursts: 1, clicks: 1) == nil)
        }
        #expect(BrowserRhythmTotals(distance: 1, movingSeconds: .nan, scrollBursts: 1, clicks: 1) == nil)
        #expect(BrowserRhythmTotals(distance: 1, movingSeconds: 1, scrollBursts: -1, clicks: 1) == nil)
        #expect(BrowserRhythmTotals(distance: 1, movingSeconds: 1, scrollBursts: 1, clicks: 100_001) == nil)
        #expect(BrowserRhythmAccumulator(site: .news).summary(durationSeconds: 0).averageMovingSpeed == nil)
    }

    @Test("Summary duration and speed remain safe to display as integers")
    func boundedSummary() throws {
        var rhythm = BrowserRhythmAccumulator(site: .news)
        let tiny = try #require(BrowserRhythmTotals(distance: 1, movingSeconds: .leastNonzeroMagnitude, scrollBursts: 1, clicks: 0))
        let updated = rhythm.update(tiny)
        #expect(updated)
        #expect(rhythm.summary(durationSeconds: .greatestFiniteMagnitude).durationSeconds == 900)
        #expect(rhythm.summary(durationSeconds: .nan).durationSeconds == 0)
        #expect(rhythm.summary(durationSeconds: -1).durationSeconds == 0)
        #expect(rhythm.summary(durationSeconds: 1).averageMovingSpeed == nil)
    }

    @Test("Only the chosen secure site outside sign-in routes can be learned")
    func pagePolicy() {
        #expect(BrowserRhythmPolicy.permits(site: .instagram, url: URL(string: "https://www.instagram.com/reels/")))
        for address in ["http://www.instagram.com/", "https://www.instagram.com/accounts/login/",
                        "https://www.instagram.com/challenge/", "https://accounts.google.com/",
                        "https://www.instagram.com.evil.example/", "https://user:secret@www.instagram.com/"] {
            #expect(!BrowserRhythmPolicy.permits(site: .instagram, url: URL(string: address)))
        }
    }
}

#if canImport(JavaScriptCore)
@Suite("Browser rhythm passive script")
@MainActor
struct BrowserRhythmScriptTests {
    private let nonce = UUID(uuidString: "D634C2F6-AC7A-4E73-99FB-BA4BFEBC421E")!

    private func page() throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript(#"""
        var clock = 0, hooks = {}, messages = [], timers = [], password = false;
        var location = {protocol:'https:',hostname:'www.instagram.com',pathname:'/reels/'};
        var performance = {now:() => clock};
        class Element {
          constructor(input = false) {this.scrollTop=0; this.input=input;}
          closest() {return this.input ? this : null;}
          get textContent() {throw Error('Text capture');}
          get value() {throw Error('Input capture');}
          get href() {throw Error('Link capture');}
        }
        var root = new Element(), nested = new Element(), inputField = new Element(true);
        var document = {hidden:false,documentElement:root,scrollingElement:root,
          querySelector:() => password ? {} : null,
          addEventListener:(name,fn) => {hooks[name]=fn;},
          removeEventListener:(name,fn) => {if(hooks[name]===fn) delete hooks[name];}};
        class MutationObserver {constructor(fn) {this.fn=fn;} observe() {} disconnect() {}}
        var window = globalThis; window.top=window;
        window.webkit={messageHandlers:{moreRhythm:{postMessage:body => messages.push(body)}}};
        function setTimeout(fn) {timers.push(fn); return timers.length;}
        function clearTimeout() {}
        function flush() {let tasks=timers;timers=[];tasks.forEach(fn=>fn());}
        function event(name,target,trusted=true) {
          if(hooks[name]) hooks[name]({target,isTrusted:trusted,composedPath:()=>[target,root]});
        }
        """#)
        return context
    }

    @Test("Nested manual scroll and clicks produce only numeric totals; Stop removes observers")
    func nestedManual() throws {
        let context = try page()
        #expect(context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))?.toBool() == true)
        context.evaluateScript("event('pointerdown',nested);clock=100;nested.scrollTop=120;event('scroll',nested);event('click',nested);flush();")
        #expect(context.evaluateScript("messages[0].distance")?.toDouble() == 120)
        #expect(context.evaluateScript("messages[0].clicks")?.toInt32() == 1)
        #expect(context.evaluateScript("messages[0].segments[0].behavior")?.toString() == "watchVideos")
        #expect(context.evaluateScript("Object.keys(messages[0].segments[0]).sort().join(',')")?.toString() == "behavior,endSeconds,gestures,startSeconds")
        #expect(context.evaluateScript("Object.keys(messages[0]).sort().join(',')")?.toString() == "clicks,distance,movingSeconds,nonce,scrollBursts,segments")
        context.evaluateScript("globalThis.__moreRhythm.stop('\(nonce.uuidString)')")
        #expect(context.evaluateScript("Object.keys(hooks).length")?.toInt32() == 0)
        #expect(context.exception == nil)
    }

    @Test("Untrusted clicks, input controls and scrolling without recent user input are ignored")
    func excludedEvents() throws {
        let context = try page()
        context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))
        context.evaluateScript("clock=100;nested.scrollTop=120;event('scroll',nested);event('click',nested,false);event('click',inputField);flush();")
        #expect(context.evaluateScript("messages.length")?.toInt32() == 0)
        #expect(context.exception == nil)
    }

    @Test("Stop disconnects listeners even after native has removed or closed its message bridge")
    func removedBridgeStillCleansUp() throws {
        for removal in ["delete window.webkit.messageHandlers.moreRhythm",
                        "window.webkit.messageHandlers.moreRhythm.postMessage=()=>{throw Error('Bridge closed');}"] {
            let context = try page()
            context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))
            context.evaluateScript("event('pointerdown',nested);clock=100;nested.scrollTop=120;event('scroll',nested);\(removal);globalThis.__moreRhythm.stop('\(nonce.uuidString)');")
            #expect(context.evaluateScript("Object.keys(hooks).length")?.toInt32() == 0)
            #expect(context.evaluateScript("globalThis.__moreRhythm === undefined")?.toBool() == true)
            #expect(context.exception == nil)
        }
    }

    @Test("Listener cleanup runs even when the final safety check throws")
    func failedFlushStillCleansUp() throws {
        let context = try page()
        context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))
        context.evaluateScript("document.querySelector=()=>{throw Error('Document unavailable');};try{globalThis.__moreRhythm.stop('\(nonce.uuidString)');}catch(_){}")
        #expect(context.evaluateScript("Object.keys(hooks).length")?.toInt32() == 0)
        #expect(context.evaluateScript("globalThis.__moreRhythm === undefined")?.toBool() == true)
        #expect(context.exception == nil)
    }

    @Test("An inline credential form or hidden document immediately removes the collector")
    func credentialsAndBackground() throws {
        for change in ["password=true", "document.hidden=true", "location.pathname='/accounts/login/'"] {
            let context = try page()
            context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))
            context.evaluateScript("\(change);event('scroll',nested);")
            #expect(context.evaluateScript("messages[0].blocked")?.toBool() == true)
            #expect(context.evaluateScript("Object.keys(hooks).length")?.toInt32() == 0)
            #expect(context.exception == nil)
        }
    }

    @Test("New social sign-in routes stop the real collector before any credential form inspection")
    func socialSignInRoutesStopCollector() throws {
        let routes: [(WebMorningSite, String, String)] = [
            (.twitter, "x.com", "/i/flow/login"), (.twitter, "twitter.com", "/i/jf"),
            (.twitter, "x.com", "/onboarding"),
            (.tiktok, "www.tiktok.com", "/passport/web/"), (.tiktok, "www.tiktok.com", "/login"),
            (.reddit, "www.reddit.com", "/register"),
            (.facebook, "www.facebook.com", "/login.php"),
            (.threads, "www.threads.com", "/accounts/login/"),
            (.linkedin, "www.linkedin.com", "/uas/login"),
            (.slack, "team.slack.com", "/signin"),
            (.slack, "signin.slack.com", "/")
        ]
        for (site, host, path) in routes {
            let context = try page()
            context.evaluateScript("location.hostname='\(host)';location.pathname='\(path)';var formChecks=0;document.querySelector=()=>{formChecks++;throw Error('Credential DOM inspected');};")
            #expect(context.evaluateScript(BrowserRhythmPolicy.script(site: site, nonce: nonce))?.toBool() == false)
            #expect(context.evaluateScript("formChecks")?.toInt32() == 0)
            #expect(context.evaluateScript("Object.keys(hooks).length")?.toInt32() == 0)
            #expect(context.evaluateScript("messages.length")?.toInt32() == 0)
            #expect(context.exception == nil)
        }
    }

    @Test("Manual scroll learning on new social sites emits the same numeric-only contract")
    func socialSitesKeepNumericOnlyLearning() throws {
        for site in [WebMorningSite.tiktok, .twitter, .reddit, .facebook, .threads] {
            let host = try #require(site.table.startURL.host)
            #expect(BrowserRhythmPolicy.permits(site: site, url: site.table.startURL))
            let context = try page()
            context.evaluateScript("location.hostname='\(host)';location.pathname='/';")
            #expect(context.evaluateScript(BrowserRhythmPolicy.script(site: site, nonce: nonce))?.toBool() == true)
            context.evaluateScript("event('pointerdown',nested);clock=100;nested.scrollTop=120;event('scroll',nested);flush();")
            #expect(context.evaluateScript("messages[0].distance")?.toDouble() == 120)
            #expect(context.evaluateScript("Object.keys(messages[0]).sort().join(',')")?.toString() == "clicks,distance,movingSeconds,nonce,scrollBursts,segments")
            #expect(context.exception == nil)
        }
    }

    @Test("Message pages expose no conversation text or inferred unread category during learning")
    func messagingSitesKeepNumericOnlyLearning() throws {
        for (site, host, path) in [(WebMorningSite.linkedin, "www.linkedin.com", "/messaging/thread/example/"),
                                   (.slack, "team.slack.com", "/client/TEXAMPLE/CEXAMPLE")] {
            let context = try page()
            context.evaluateScript("location.hostname='\(host)';location.pathname='\(path)';")
            #expect(context.evaluateScript(BrowserRhythmPolicy.script(site: site, nonce: nonce))?.toBool() == true)
            context.evaluateScript("event('pointerdown',nested);clock=100;nested.scrollTop=120;event('scroll',nested);flush();")
            #expect(context.evaluateScript("messages[0].distance")?.toDouble() == 120)
            #expect(context.evaluateScript("messages[0].segments.length")?.toInt32() == 0)
            #expect(context.evaluateScript("Object.keys(messages[0]).sort().join(',')")?.toString() == "clicks,distance,movingSeconds,nonce,scrollBursts,segments")
            #expect(context.exception == nil)
        }
    }

    @Test("SPA categories retain observed order, bounded gesture times and no page data")
    func semanticRouteSequence() throws {
        let context = try page()
        context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))
        context.evaluateScript("clock=100;event('click',root);clock=200;location.pathname='/stories/person/private-id/';event('click',root);clock=300;location.pathname='/direct/inbox/';event('click',root);clock=400;location.pathname='/';event('click',root);")
        #expect(context.evaluateScript("messages.at(-1).segments.map(s=>s.behavior).join(',')")?.toString() == "watchVideos,watchStories,browseFeed")
        #expect(context.evaluateScript("messages.at(-1).segments[1].startSeconds")?.toDouble() == 0.2)
        #expect(context.evaluateScript("JSON.stringify(messages.at(-1)).includes('private-id')")?.toBool() == false)
        #expect(context.exception == nil)
    }

    @Test("Retargeted shadow inputs and synthetic controls establish no semantic behavior")
    func shadowInputsExcluded() throws {
        let context = try page()
        context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))
        context.evaluateScript("hooks.click({target:root,isTrusted:true,composedPath:()=>[inputField,root]});event('click',root,false);flush();")
        #expect(context.evaluateScript("messages.length")?.toInt32() == 0)
        #expect(context.exception == nil)
    }

    @Test("A long lesson preserves its first sixteen segments instead of evicting evidence")
    func boundedSemanticSequence() throws {
        let context = try page()
        context.evaluateScript(BrowserRhythmPolicy.script(site: .instagram, nonce: nonce))
        context.evaluateScript("for(let i=0;i<20;i++){clock=100*(i+1);location.pathname=i%2?'/stories/person/':'/';event('click',root);}")
        #expect(context.evaluateScript("messages.at(-1).segments.length")?.toInt32() == 16)
        #expect(context.evaluateScript("messages.at(-1).segments[0].startSeconds")?.toDouble() == 0.1)
        #expect(context.evaluateScript("messages.at(-1).segments[15].endSeconds")?.toDouble() == 1.6)
        #expect(context.evaluateScript("messages.at(-1).clicks")?.toInt32() == 20)
        #expect(context.exception == nil)
    }
}
#endif
