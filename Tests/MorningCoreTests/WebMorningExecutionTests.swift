import Foundation
import Testing
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif
@testable import MorningCore

@Suite("Approved browser execution")
struct WebMorningExecutionTests {
    @Test func planBoundsAndScopeAreExplicit() {
        let session = UUID(), step = UUID()
        let plan = WebMorningExecutionPlan(sessionID: session, stepID: step, behavior: .watchVideos,
            likesAllowed: true, maximumLikes: 500, dwellSeconds: .infinity)
        #expect(plan.maximumLikes == 3)
        #expect(plan.dwellSeconds == 12)
        #expect(WebMorningExecutionPlan(sessionID: session, stepID: step, behavior: .browseFeed).likesAllowed == false)
        #expect(WebMorningBehavior.availableBehaviors(for: .news) == [.readHeadlines])
        #expect(WebMorningBehavior.availableBehaviors(for: .gmail).isEmpty)
        #expect(!WebMorningBehavior.permitsLikes(for: .news, behavior: .readHeadlines))
        let event = WebMorningExecutionEvent(plan: plan, state: .waitingForPage, observedContentCount: 0, confirmedLikeCount: 0)
        #expect(event.sessionID == session && event.stepID == step)
        #expect(event.observedContentCount == 0)
    }

    @Test func observationsFailClosedAndNeverTurnMissingContentIntoAResult() {
        #expect(WebMorningPageObservation.parse(#"{"status":"ready"}"#) == nil)
        #expect(WebMorningPageObservation.parse(#"{"status":"dispatched"}"#) == nil)
        #expect(WebMorningPageObservation.parse(#"{"status":"empty"}"#)?.status == .empty)
        #expect(WebMorningPageObservation.parse(#"{"status":"signin"}"#)?.status == .signin)
        #expect(WebMorningPageObservation.parse(#"{"status":"choice"}"#)?.pageAccessRefusal == nil)
        #expect(WebMorningPageObservation.parse(#"{"status":"choice","pageAccessRefusal":"consentRequired"}"#)?.pageAccessRefusal == .consentRequired)
        #expect(WebMorningPageObservation.parse(#"{"status":"choice","pageAccessRefusal":"guessedSubscription"}"#) == nil)
        #expect(WebMorningPageObservation.parse(#"{"status":"ready","fingerprint":"abc","pageAccessRefusal":"consentRequired"}"#) == nil)
        #expect(WebMorningPageObservation.parse(#"{"status":"ready","fingerprint":"abc","liked":"true"}"#) == nil)
        #expect(WebMorningPageObservation.parse(String(repeating: "x", count: 12_001)) == nil)
        #expect(WebMorningPageObservation.parse("{") == nil)
    }

    @Test func contentProgressSurvivesAColdRestoreWithoutCountingTheSameContentAgain() throws {
        let session = UUID(), step = UUID()
        var progress = WebMorningContentProgress()
        #expect(try progress.observe(site: .reddit, fingerprint: "first-private-content"))
        #expect(try progress.observe(site: .reddit, fingerprint: "second-private-content"))
        let record = RoutineExecutionRecord(sessionID: session, stepID: step, outcome: .interrupted,
            observedContents: 2, webContentProgress: progress)
        let saved = try JSONEncoder().encode(record)
        #expect(!String(decoding: saved, as: UTF8.self).contains("private-content"))
        let restored = try JSONDecoder().decode(RoutineExecutionRecord.self, from: saved)
        let plan = WebMorningExecutionPlan(sessionID: session, stepID: step, behavior: .browseFeed,
            initialObservedContentCount: restored.observedContents, initialContentProgress: restored.webContentProgress)
        var reopened = plan.initialContentProgress
        #expect(plan.initialObservedContentCount == 2)
        #expect(try !reopened.observe(site: .reddit, fingerprint: "first-private-content"))
        #expect(reopened.observedCount == 2)
        #expect(try reopened.observe(site: .reddit, fingerprint: "third-private-content"))
        #expect(reopened.observedCount == 3)
        // A new session/step starts without importing the previous moment's keys.
        var next = WebMorningExecutionPlan(sessionID: UUID(), stepID: UUID(), behavior: .browseFeed).initialContentProgress
        #expect(try next.observe(site: .reddit, fingerprint: "first-private-content"))
        #expect(next.observedCount == 1)
    }

    @Test func legacyBrowserCountsRemainUsableWithoutInventingMissingContentIdentities() throws {
        var progress = WebMorningExecutionPlan(sessionID: UUID(), stepID: UUID(), behavior: .browseFeed,
            initialObservedContentCount: 7).initialContentProgress
        #expect(progress.observedCount == 7)
        #expect(try progress.observe(site: .reddit, fingerprint: "new"))
        #expect(progress.observedCount == 8)
        #expect(try !progress.observe(site: .reddit, fingerprint: "new"))
        #expect(progress.observedCount == 8)
        #expect(try progress.observe(site: .twitter, fingerprint: "new"))
        #expect(progress.observedCount == 9)
    }

    @Test func corruptContentProgressCannotSilentlyRestartDeduplication() throws {
        let validKey = String(repeating: "a", count: 64)
        let invalid: [[String: Any]] = [
            ["observedCount": 1, "keys": ["raw page text"]],
            ["observedCount": 2, "keys": [validKey, validKey]],
            ["observedCount": 0, "keys": [validKey]],
            ["observedCount": -1, "keys": []],
            ["observedCount": 100_001, "keys": []]
        ]
        for object in invalid {
            let saved = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(WebMorningContentProgress.self, from: saved) }
        }
    }

    @Test func progressCapacityKeepsOldIdentitiesInsteadOfEvictingAndRecountingThem() throws {
        var progress = WebMorningContentProgress()
        for index in 0..<WebMorningContentProgress.maximumKeys {
            try progress.observe(site: .reddit, fingerprint: "content-\(index)")
        }
        #expect(try !progress.observe(site: .reddit, fingerprint: "content-0"))
        #expect(throws: WebMorningContentProgress.ProgressError.capacityReached) {
            try progress.observe(site: .reddit, fingerprint: "one-too-many")
        }
        #expect(progress.observedCount == WebMorningContentProgress.maximumKeys)
        let restored = try JSONDecoder().decode(WebMorningContentProgress.self, from: JSONEncoder().encode(progress))
        #expect(restored == progress)
    }

    @Test func journalBlocksAnUnknownEffectAcrossReopenAndNeverTogglesTwice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = WebMorningLikeJournal.key(site: .instagram, contentID: "/p/first-private-content/")
        let second = WebMorningLikeJournal.key(site: .instagram, contentID: "/p/second/")
        let journal = WebMorningLikeJournal(directory: directory)
        #expect(try journal.reserve(first))
        let reopened = WebMorningLikeJournal(directory: directory)
        #expect(try reopened.unresolvedKeys() == [first])
        #expect(try reopened.reserve(first) == false)
        #expect(try reopened.reserve(second) == false)
        try reopened.confirm(first)
        #expect(try reopened.unresolvedKeys().isEmpty)
        #expect(try reopened.reserve(first) == false)
        #expect(try reopened.reserve(second))
        let saved = try String(contentsOf: directory.appendingPathComponent("browser-action-journal.json"), encoding: .utf8)
        #expect(!saved.contains("private-content"))
        #expect(first.count == 64)
    }

    @Test func corruptJournalCannotAuthorizeALike() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("broken".utf8).write(to: directory.appendingPathComponent("browser-action-journal.json"))
        #expect(throws: (any Error).self) {
            try WebMorningLikeJournal(directory: directory).reserve(WebMorningLikeJournal.key(site: .twitter, contentID: "/status/1"))
        }
    }

    @Test func executionHostBoundaryIsExact() {
        for path in ["https://x.com.evil.test/home", "https://x.com:8443/home", "http://x.com/home",
                     "https://user:secret@x.com/home", "https://x.com/i/flow/login"] {
            #expect(!WebMorningExecutionPolicy.permits(site: .twitter, url: URL(string: path)))
        }
        #expect(WebMorningExecutionPolicy.permits(site: .twitter, url: URL(string: "https://x.com/home")))
        #expect(!WebMorningExecutionPolicy.permits(site: .gmail, url: WebMorningSite.gmail.table.startURL))
    }
}

#if canImport(JavaScriptCore)
@Suite("Browser execution page effects")
@MainActor
struct WebMorningExecutionScriptTests {
    private func context() throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var window = this, innerHeight=800;
        var location={protocol:'https:',hostname:'www.instagram.com',port:'',username:'',password:'',pathname:'/',href:'https://www.instagram.com/'};
        var getComputedStyle=e=>({visibility:'visible',display:'block',overflowY:'visible'});
        var liked=false, clicks=0, itemNumber=1, moves=0;
        var bounds=()=>({width:400,height:500,top:0,bottom:500});
        var button={getBoundingClientRect:bounds,getAttribute:k=>k==='aria-label' ? (liked ? 'Unlike':'Like') : null,
                    querySelector:()=>null,innerText:'',click:()=>{clicks++;liked=!liked;}};
        var item={getBoundingClientRect:bounds,getAttribute:k=>k==='data-id' ? 'post-'+itemNumber : null,
                  matches:()=>false,querySelector:()=>null,querySelectorAll:s=>s==='button' ? [button] : [],
                  parentElement:null,innerText:'Visible post'};
        var scroller={scrollTop:0,clientHeight:800,scrollHeight:10000,
                      scrollBy:()=>{moves++;itemNumber++;}};
        var document={hidden:false,readyState:'complete',body:{},documentElement:{},scrollingElement:scroller,
                      querySelector:()=>null,querySelectorAll:s=>s==='article' ? [item] : []};
        window.top=window;
        """)
        return context
    }
    private func evaluate(_ context: JSContext, command: String = "observe", fingerprint: String? = nil,
                          likesAllowed: Bool = false, expiresAt: Date = Date().addingTimeInterval(10),
                          behavior: WebMorningBehavior = .browseFeed) throws -> String {
        let script = WebMorningExecutionPolicy.script(site: .instagram, behavior: behavior, command: command,
            fingerprint: fingerprint, likesAllowed: likesAllowed, expiresAt: expiresAt)
        let result = try #require(context.evaluateScript(script)?.toString())
        #expect(context.exception == nil)
        return result
    }

    @Test func crossSiteAndSignInRefuseBeforeReadingTheDOM() throws {
        for (host, path, expected) in [("www.instagram.com.evil.test", "/", "unavailable"),
                                        ("www.instagram.com", "/accounts/login/", "signin")] {
            let context = try #require(JSContext())
            context.evaluateScript("""
            var window=this; window.top=window;
            var location={protocol:'https:',hostname:'\(host)',port:'',username:'',password:'',pathname:'\(path)'};
            var touched=false; Object.defineProperty(this,'document',{get(){touched=true;throw Error('DOM touched');}});
            """)
            let result = try evaluate(context)
            #expect(result.contains(expected))
            #expect(context.objectForKeyedSubscript("touched")?.toBool() == false)
        }
    }

    @Test func likesNeedApprovalExactContentAndAnUnlikedControl() throws {
        let context = try context()
        let before = try #require(WebMorningPageObservation.parse(evaluate(context)))
        #expect(before.canLike == true && before.liked == false)
        _ = try evaluate(context, command: "like", fingerprint: before.fingerprint)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
        _ = try evaluate(context, command: "like", fingerprint: "stale", likesAllowed: true)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
        let dispatched = try evaluate(context, command: "like", fingerprint: before.fingerprint, likesAllowed: true)
        #expect(dispatched.contains("dispatched"))
        let after = try #require(WebMorningPageObservation.parse(evaluate(context)))
        #expect(after.liked == true)
        #expect(after.fingerprint == before.fingerprint)
        _ = try evaluate(context, command: "like", fingerprint: after.fingerprint, likesAllowed: true)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 1)
    }

    @Test func anAdvanceIsOnlyDispatchUntilADifferentContentIsObserved() throws {
        let context = try context()
        let before = try #require(WebMorningPageObservation.parse(evaluate(context)))
        let dispatched = try evaluate(context, command: "advance", fingerprint: before.fingerprint)
        #expect(WebMorningPageObservation.parse(dispatched) == nil)
        let after = try #require(WebMorningPageObservation.parse(evaluate(context)))
        #expect(before.fingerprint != after.fingerprint)
        #expect(context.objectForKeyedSubscript("moves")?.toInt32() == 1)
    }

    @Test func anOverlayBlocksUnderlyingContentAndLikeControls() throws {
        let context = try context()
        context.evaluateScript("""
        var innerWidth=400;
        var overlay={contains:()=>false};
        item.contains=()=>false;
        button.contains=()=>false;
        document.elementFromPoint=()=>overlay;
        """)
        let result = try evaluate(context)
        #expect(WebMorningPageObservation.parse(result)?.status == .empty)
        _ = try evaluate(context, command: "like", fingerprint: "anything", likesAllowed: true)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
    }

    @Test func videoCaptionsDoNotMakeUnloadedMediaLookReady() throws {
        let context = try context()
        context.evaluateScript("""
        var video={readyState:0,paused:true};
        item.querySelectorAll=s=>s==='video' ? [video] : [];
        item.innerText='A caption while the video is still loading';
        """)
        let result = try evaluate(context, behavior: .watchVideos)
        #expect(WebMorningPageObservation.parse(result)?.status == .loading)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
    }

    @Test func consentDismissalOnlyRejectsTrackingAndIsObservedAgain() throws {
        let context = try context()
        context.evaluateScript("""
        var rejected=0,accepted=0;
        var consentHost={localName:'div',getAttribute:k=>k==='id' ? 'didomi-host' : null};
        var reject={parentElement:consentHost,getBoundingClientRect:bounds,getAttribute:()=>null,innerText:'Reject all',click:()=>{rejected++;}};
        var accept={getBoundingClientRect:bounds,getAttribute:()=>null,innerText:'Accept all',click:()=>{accepted++;}};
        var originalQuery=document.querySelectorAll;
        document.querySelectorAll=s=>s==='button' && !rejected ? [reject,accept] : originalQuery(s);
        """)
        let before = try #require(WebMorningPageObservation.parse(evaluate(context)))
        #expect(before.status == .loading && before.consentCanDismiss == true)
        _ = try evaluate(context, command: "rejectConsent", fingerprint: before.fingerprint)
        let after = try #require(WebMorningPageObservation.parse(evaluate(context)))
        #expect(after.status == .ready && after.fingerprint != before.fingerprint)
        #expect(context.objectForKeyedSubscript("rejected")?.toInt32() == 1)
        #expect(context.objectForKeyedSubscript("accepted")?.toInt32() == 0)
    }

    @Test func redditCookieDialogAndContentInsideOpenShadowRootsAreObservedSafely() throws {
        let context = try context()
        context.evaluateScript("""
        location.hostname='www.reddit.com';location.href='https://www.reddit.com/';
        var innerWidth=400,rejected=0,accepted=0;
        var cookieHost={localName:'shreddit-cookie-banner',getAttribute:()=>null};
        var cookieRoot={host:cookieHost,querySelectorAll:s=>!rejected && (s==='button'||s==='*') ? [reject,accept] : [],elementFromPoint:()=>reject};
        var reject={getBoundingClientRect:bounds,getAttribute:()=>null,getRootNode:()=>cookieRoot,innerText:'Reject Optional Cookies',click:()=>{rejected++;}};
        var accept={getBoundingClientRect:bounds,getAttribute:()=>null,getRootNode:()=>cookieRoot,innerText:'Accept All',click:()=>{accepted++;}};
        cookieHost.shadowRoot=cookieRoot;
        var postRoot={host:item,querySelectorAll:s=>s==='h1'||s==='*' ? [title] : [],elementFromPoint:()=>title};
        var title={getBoundingClientRect:bounds,getAttribute:()=>null,getRootNode:()=>postRoot,innerText:'A real public post title'};
        item.innerText='';item.textContent='';item.shadowRoot=postRoot;
        document.elementFromPoint=()=>rejected ? item : cookieHost;
        document.querySelectorAll=s=>s==='*' ? [cookieHost,item] : s==='shreddit-cookie-banner' ? [cookieHost] : s==='shreddit-post' ? [item] : [];
        """)
        let beforeScript = WebMorningExecutionPolicy.script(site: .reddit, behavior: .browseFeed)
        let beforeValue = try #require(context.evaluateScript(beforeScript)?.toString())
        #expect(context.exception == nil)
        let before = try #require(WebMorningPageObservation.parse(beforeValue))
        #expect(before.consentCanDismiss == true && before.status == .loading)
        let rejectScript = WebMorningExecutionPolicy.script(site: .reddit, behavior: .browseFeed,
            command: "rejectConsent", fingerprint: before.fingerprint)
        let dispatch = try #require(context.evaluateScript(rejectScript)?.toString())
        #expect(dispatch.contains("dispatched"))
        let afterValue = try #require(context.evaluateScript(beforeScript)?.toString())
        #expect(context.exception == nil)
        let after = try #require(WebMorningPageObservation.parse(afterValue))
        #expect(after.status == .ready && after.text == ["A real public post title"])
        #expect(context.objectForKeyedSubscript("rejected")?.toInt32() == 1)
        #expect(context.objectForKeyedSubscript("accepted")?.toInt32() == 0)
    }

    @Test func privacyWordsInsideAnOrdinaryPostDoNotAuthorizeConsentClicks() throws {
        let context = try context()
        context.evaluateScript("""
        var originalQuery=document.querySelectorAll;
        var pretend={parentElement:item,getBoundingClientRect:bounds,getAttribute:()=>null,innerText:'Reject Optional Cookies',click:()=>{throw Error('Post content clicked');}};
        document.querySelectorAll=s=>s==='button' ? [pretend] : originalQuery(s);
        """)
        let result = try #require(WebMorningPageObservation.parse(evaluate(context)))
        #expect(result.status == .ready && result.consentCanDismiss != true)
    }

    @Test func privacyOrSubscriptionWallNeedsThePersonsChoice() throws {
        let context = try context()
        context.evaluateScript("""
        location.hostname='www.lemonde.fr';location.href='https://www.lemonde.fr/';
        var accepted=0,subscribed=0;
        var accept={getBoundingClientRect:bounds,getAttribute:()=>null,innerText:'Accepter et continuer',click:()=>{accepted++;}};
        var subscribe={getBoundingClientRect:bounds,getAttribute:()=>null,innerText:'S’abonner',click:()=>{subscribed++;}};
        var originalQuery=document.querySelectorAll;
        document.querySelectorAll=s=>s==='button' ? [accept,subscribe] : originalQuery(s);
        """)
        let script = WebMorningExecutionPolicy.script(site: .news, behavior: .readHeadlines)
        let result = try #require(context.evaluateScript(script)?.toString())
        #expect(context.exception == nil)
        #expect(WebMorningPageObservation.parse(result)?.status == .choice)
        #expect(WebMorningPageObservation.parse(result)?.pageAccessRefusal == nil)
        #expect(context.objectForKeyedSubscript("accepted")?.toInt32() == 0)
        #expect(context.objectForKeyedSubscript("subscribed")?.toInt32() == 0)
    }

    @Test(arguments: ["observedPanel", "dispersedControls", "navbar", "textOutsidePanel", "hiddenPanel",
        "hiddenText", "genericChoice", "mainContainer", "pageContainer", "genericFixedContainer"])
    func aPageAccessGateRequiresTheObservedControlsAndVisibleTextInOneRealPanel(_ variant: String) throws {
        let context = try context()
        let mode = String(decoding: try JSONEncoder().encode(variant), as: UTF8.self)
        // Shape/content is based on the captured wall; it does not claim a live
        // provider DOM replay. In particular, body text behind it is not proof.
        context.evaluateScript("""
        location.hostname='www.lemonde.fr';location.href='https://www.lemonde.fr/';
        var mode=\(mode), accepted=0, subscribed=0;
        function element(tag,attributes,text){return {
          localName:tag,parentElement:null,attributes:attributes||{},innerText:text||'',
          getBoundingClientRect:bounds,getAttribute:function(k){return this.attributes[k]||null;},
          querySelector:function(){return this.hasPageContent ? {} : null;},querySelectorAll:()=>[],
          closest:function(){return null;}
        };}
        var panel=element('section',{role:'dialog'},''), footer=element('footer',{},'');
        var navbar=element('nav',{},''), outside=element('div',{},'');
        var copy=element('p',{},''), cookies=element('p',{},'');
        var accept=element('button',{},'Accepter et continuer');accept.click=()=>{accepted++;};
        var subscribe=element('a',{},'S’abonner');subscribe.click=()=>{subscribed++;};
        panel.parentElement=document.body;footer.parentElement=panel;
        navbar.parentElement=document.body;outside.parentElement=document.body;
        accept.parentElement=footer;subscribe.parentElement=footer;
        copy.parentElement=panel;cookies.parentElement=panel;
        if(mode==='dispersedControls')subscribe.parentElement=outside;
        if(mode==='navbar')subscribe.parentElement=navbar;
        if(mode==='textOutsidePanel'){copy.parentElement=outside;cookies.parentElement=outside;}
        if(mode==='hiddenPanel')panel.hidden=true;
        if(mode==='hiddenText'){copy.hidden=true;cookies.hidden=true;}
        if(mode==='mainContainer'){panel.localName='main';panel.attributes={role:'main'};}
        if(mode==='pageContainer')panel.hasPageContent=true;
        if(mode==='genericFixedContainer'){panel.attributes={};panel.fixed=true;}
        var textNodes=[
          {parentElement:copy,nodeValue:mode==='genericChoice' ? 'Choose a content plan.' : 'L’accès gratuit au site est subordonné à votre consentement.'},
          {parentElement:cookies,nodeValue:mode==='genericChoice' ? 'Discover our products.' : 'Des données collectées via des cookies et technologies similaires.'}
        ];
        function belongs(root,node){for(var e=node;e;e=e.parentElement)if(e===root)return true;return false;}
        document.createTreeWalker=root=>{var rows=textNodes.filter(n=>belongs(root,n.parentElement)),i=0;return {nextNode:()=>rows[i++]||null};};
        getComputedStyle=e=>({visibility:e.hidden ? 'hidden' : 'visible',display:e.hidden ? 'none' : 'block',overflowY:'visible',position:e.fixed ? 'fixed' : 'static'});
        document.querySelectorAll=s=>s==='button' ? [accept] : s==='a' ? [subscribe] : s==='*' ? [panel,footer,navbar,outside,copy,cookies,accept,subscribe] : [];
        """)
        let script = WebMorningExecutionPolicy.script(site: .news, behavior: .readHeadlines)
        let result = try #require(context.evaluateScript(script)?.toString())
        #expect(context.exception == nil)
        let observation = try #require(WebMorningPageObservation.parse(result))
        #expect(observation.status == .choice && observation.text == nil && observation.articles == nil)
        #expect(observation.pageAccessRefusal == (variant == "observedPanel" ? .consentRequired : nil))
        #expect(context.objectForKeyedSubscript("accepted")?.toInt32() == 0)
        #expect(context.objectForKeyedSubscript("subscribed")?.toInt32() == 0)
    }

    @Test func expiredCommandsAndInlinePasswordFormsCannotInteract() throws {
        let context = try context()
        let before = try #require(WebMorningPageObservation.parse(evaluate(context)))
        _ = try evaluate(context, command: "like", fingerprint: before.fingerprint, likesAllowed: true,
                         expiresAt: Date().addingTimeInterval(-10))
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
        context.evaluateScript("""
        document.querySelectorAll=s=>s==='input[type=password]' ? [{getBoundingClientRect:bounds}] : [];
        Object.defineProperty(item,'innerText',{get(){throw Error('Content read during sign-in');}});
        """)
        let result = try evaluate(context)
        #expect(WebMorningPageObservation.parse(result)?.status == .signin)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
    }

    @Test func aDelayedReadOnlyObservationIsAcceptedWhileExpiredMutationsRemainBlocked() throws {
        let context = try context()
        let staleDeadline = Date().addingTimeInterval(-10)
        let observation = try #require(WebMorningPageObservation.parse(evaluate(context, expiresAt: staleDeadline)))
        #expect(observation.status == .ready)
        #expect(observation.fingerprint != nil)
        let expired = try #require(WebMorningPageObservation.parse(evaluate(context, command: "advance",
            fingerprint: observation.fingerprint, expiresAt: staleDeadline)))
        #expect(expired.status == .unavailable && expired.reason == "expired")
        #expect(context.objectForKeyedSubscript("moves")?.toInt32() == 0)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
    }

    @Test func aDocumentHiddenDuringPresentationWaitsBeforeReadingContent() throws {
        let context = try context()
        context.evaluateScript("""
        document.hidden=true;
        Object.defineProperty(item,'innerText',{get(){throw Error('Hidden content read');}});
        """)
        let observation = try #require(WebMorningPageObservation.parse(evaluate(context)))
        #expect(observation.status == .loading && observation.reason == "hidden")
        #expect(observation.fingerprint == nil && observation.text == nil)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
    }
}
#endif
