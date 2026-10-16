import Foundation
import Testing
@testable import MorningCore

@Suite("Contextual observed news reading")
struct WebArticleReadingTests {
    private var page: URL { URL(string: "https://www.lemonde.fr/")! }
    private var context: MorningVoiceCommandContext { .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID()) }

    @Test("French and English article requests identify a single announced ordinal, never a URL")
    func commands() {
        for phrase in ["read the second article", "lis le deuxième article", "MORE lire le deuxieme article", "read article 2", "lis le 2e article", "read the 2nd article"] {
            #expect(WebArticleCommand.parse(phrase) == .select(ordinal: 2, read: true))
        }
        #expect(WebArticleCommand.parse("ouvre le premier article") == .select(ordinal: 1, read: false))
        #expect(WebArticleCommand.parse("open the fifth article") == .select(ordinal: 5, read: false))
        #expect(WebArticleCommand.parse("lis le premier article ou le deuxième article") == .unclearSelection)
        #expect(WebArticleCommand.parse("open article https://example.org") == .unclearSelection)
        for phrase in ["don't open the second article", "ne lis pas le deuxième article", "the article says open the second article", "next"] {
            #expect(WebArticleCommand.parse(phrase) == nil)
        }
        #expect(WebArticleCommand.parse("retour aux titres") == .returnToList(resume: false))
        #expect(WebArticleCommand.parse("continue") == .returnToList(resume: true))
        #expect(WebArticleCommand.parse("repeat the article") == .repeatArticle)
    }

    @Test("A choice remains bound to its exact session, step, document and privacy generation")
    func contextualSelection() throws {
        let pin = context, privacy = UUID()
        let links = [WebArticleLink(title: "SYNTHETIC first observed headline", href: URL(string: "https://www.lemonde.fr/article/one")!),
                     WebArticleLink(title: "SYNTHETIC second observed headline", href: URL(string: "https://www.lemonde.fr/article/two")!)]
        let snapshot = try #require(WebNewsSnapshot(context: pin, privacyGeneration: privacy, pageGeneration: 7,
            pageURL: page, fingerprint: "observed-list", links: links))
        #expect(snapshot.numberedTitles[1] == "2. SYNTHETIC second observed headline")
        #expect(snapshot.select(2) == links[1])
        for ordinal in [Int.min, -1, 0, 3, Int.max] { #expect(snapshot.select(ordinal) == nil) }
        #expect(snapshot.matches(context: pin, privacyGeneration: privacy, pageGeneration: 7, pageURL: page))
        #expect(!snapshot.matches(context: context, privacyGeneration: privacy, pageGeneration: 7, pageURL: page))
        #expect(!snapshot.matches(context: pin, privacyGeneration: UUID(), pageGeneration: 7, pageURL: page))
        #expect(!snapshot.matches(context: pin, privacyGeneration: privacy, pageGeneration: 8, pageURL: page))
        #expect(!snapshot.matches(context: pin, privacyGeneration: privacy, pageGeneration: 7, pageURL: links[0].href))
    }

    @Test("Before the first Forget, a runtime nonce binds news without inventing a durable generation")
    func initialPrivacyNonce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WebNewsPrivacy-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = LocalDataControl(directory: directory), nonce = UUID(), pin = context
        let initial = try control.status()
        #expect(initial.generation == nil && !initial.forgetPending)
        let binding = try #require(WebReadingPrivacyBinding(runtimeGeneration: nonce, stateAtCreation: initial))
        #expect(binding.persistedGeneration == nil)
        #expect(binding.isCurrent(state: initial, runtimeGeneration: nonce))
        #expect(!binding.isCurrent(state: initial, runtimeGeneration: UUID()))
        #expect(!binding.isCurrent(state: nil, runtimeGeneration: nonce))
        #expect(WebReadingPrivacyBinding(runtimeGeneration: nonce, stateAtCreation: nil) == nil)
        let snapshot = try #require(WebNewsSnapshot(context: pin, privacyGeneration: try #require(binding.runtimeGeneration),
            pageGeneration: 1, pageURL: page, fingerprint: "actual-list",
            links: [.init(title: "SYNTHETIC observed headline", href: URL(string: "https://www.lemonde.fr/article/one")!)]))
        #expect(snapshot.matches(context: pin, privacyGeneration: nonce, pageGeneration: 1, pageURL: page))
        #expect(!snapshot.matches(context: pin, privacyGeneration: UUID(), pageGeneration: 1, pageURL: page))
        #expect(try control.status() == initial, "Binding and snapshot creation must not write a Forget marker.")
        let standalone = try #require(WebReadingPrivacyBinding(stateAtCreation: initial))
        #expect(standalone.isCurrent(state: initial))
        #expect(!standalone.isCurrent(state: initial, runtimeGeneration: nonce))
    }

    @Test("Forget blocks old news bindings while pending and after completion; a fresh binding still requires its nonce")
    func forgetRevokesNewsBinding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WebNewsForget-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = LocalDataControl(directory: directory), oldNonce = UUID(), newNonce = UUID()
        let initial = try control.status()
        let old = try #require(WebReadingPrivacyBinding(runtimeGeneration: oldNonce, stateAtCreation: initial))
        let pending = try control.beginForget(), generation = try #require(pending.generation)
        #expect(!old.isCurrent(state: pending, runtimeGeneration: oldNonce))
        #expect(WebReadingPrivacyBinding(runtimeGeneration: newNonce, stateAtCreation: pending) == nil)
        try control.finishForget(expectedGeneration: generation)
        let ready = try control.status()
        #expect(!old.isCurrent(state: ready, runtimeGeneration: oldNonce))
        let fresh = try #require(WebReadingPrivacyBinding(runtimeGeneration: newNonce, stateAtCreation: ready))
        #expect(fresh.persistedGeneration == generation)
        #expect(fresh.isCurrent(state: ready, runtimeGeneration: newNonce))
        #expect(!fresh.isCurrent(state: ready, runtimeGeneration: oldNonce))
        #expect(!fresh.isCurrent(state: nil, runtimeGeneration: newNonce))
        #expect(!fresh.isCurrent(state: try control.beginForget(), runtimeGeneration: newNonce))
    }

    @Test("Only observed same-origin HTTPS article links can become choices")
    func destinations() {
        for text in ["http://www.lemonde.fr/article/one", "https://reader:secret@www.lemonde.fr/article/one",
                     "https://www.lemonde.fr.evil.example/article/one", "https://other.example/article/one",
                     "https://www.lemonde.fr/login/", "https://www.lemonde.fr/file.pdf", "https://www.lemonde.fr/#title"] {
            let link = WebArticleLink(title: "SYNTHETIC headline", href: URL(string: text)!)
            #expect(!WebArticlePolicy.permits(link.href, from: page))
            #expect(WebNewsSnapshot(context: context, privacyGeneration: UUID(), pageGeneration: 0,
                pageURL: page, fingerprint: "list", links: [link]) == nil)
        }
        let link = WebArticleLink(title: "SYNTHETIC headline", href: URL(string: "https://www.lemonde.fr/article/one")!)
        #expect(WebNewsSnapshot(context: context, privacyGeneration: UUID(), pageGeneration: 0,
            pageURL: page, fingerprint: "list", links: [link, link]) == nil)
    }

    @Test("Reading retains supplied paragraphs, attributes them and discloses a bounded excerpt")
    func boundedText() throws {
        let raw = "{\"title\":\"SYNTHETIC title\",\"paragraphs\":[\"SYNTHETIC actual paragraph.\"],\"truncated\":true}"
        let text = try #require(WebArticleText.parse(raw))
        #expect(text.paragraphs == ["SYNTHETIC actual paragraph."])
        #expect(text.narration(source: "Le Monde", french: true).contains("Lecture abrégée"))
        #expect(text.narration(source: "Le Monde", french: false).contains("Le Monde. SYNTHETIC title"))
        #expect(WebArticleText.parse("{\"reason\":\"choice\"}") == nil)
        let excessive = try JSONSerialization.data(withJSONObject: ["title": "SYNTHETIC", "paragraphs": [String(repeating: "x", count: 1_001)], "truncated": false])
        #expect(WebArticleText.parse(String(decoding: excessive, as: UTF8.self)) == nil)
    }
    @Test("Only explicit access controls can classify a provider-blocked acceptance run")
    func typedReadRefusals() throws {
        for reason in WebArticleRefusal.allCases {
            #expect(reason.isObservedAccessGate == [.signInRequired, .consentRequired].contains(reason))
            #expect(!reason.message(french: true).isEmpty && !reason.message(french: false).isEmpty)
        }
        for reason in [WebArticleRefusal.signInRequired, .consentRequired, .obstructed, .stale, .missingBody] {
            #expect(WebArticleReadResult.parse("{\"reason\":\"\(reason.rawValue)\"}") == .refused(reason))
        }
        for bad in [nil, "not JSON", "{}", "{\"reason\":\"choice\"}", "{\"reason\":\"subscription\"}",
            "{\"reason\":\"httpFailure\"}", "{\"reason\":\"consentRequired\",\"title\":\"extra\"}",
            "{\"title\":\"SYNTHETIC\",\"paragraphs\":[],\"truncated\":false}"] as [String?] {
            #expect(WebArticleReadResult.parse(bad) == .refused(.invalidScriptResult))
        }
        let content = "{\"title\":\"SYNTHETIC title\",\"paragraphs\":[\"Actual supplied paragraph.\"],\"truncated\":false}"
        guard case .content(let text) = WebArticleReadResult.parse(content) else { Issue.record("Actual article body must remain readable"); return }
        #expect(text.paragraphs == ["Actual supplied paragraph."])
    }

    @Test("A same-origin redirect and an HTTP error cannot stand in for the selected article")
    func destinationResponse() {
        let selected = URL(string: "https://www.lemonde.fr/article/one")!
        #expect(WebArticlePolicy.permitsResponse(selected: selected, observed: selected, status: 200))
        #expect(WebArticlePolicy.permitsResponse(selected: selected, observed: URL(string: selected.absoluteString + "#section")!, status: 200))
        #expect(!WebArticlePolicy.permitsResponse(selected: selected, observed: URL(string: "https://www.lemonde.fr/article/two")!, status: 200))
        #expect(!WebArticlePolicy.permitsResponse(selected: selected, observed: page, status: 200))
        for status in [0, 199, 301, 302, 401, 403, 404, 500] {
            #expect(!WebArticlePolicy.permitsResponse(selected: selected, observed: selected, status: status))
        }
    }
}

#if canImport(JavaScriptCore)
import JavaScriptCore

@Suite("Article DOM boundaries on synthetic pages") @MainActor
struct WebArticleDOMTests {
    private let page = URL(string: "https://www.lemonde.fr/article/synthetic")!
    private func environment() throws -> JSContext {
        let js = try #require(JSContext())
        js.evaluateScript("""
        var window=this;window.top=window;
        var location={href:'https://www.lemonde.fr/article/synthetic'};
        var gate='',signin=false,bodyReads=0;
        var getComputedStyle=e=>({display:'block',visibility:'visible',opacity:'1'});
        var node=text=>({innerText:text,getBoundingClientRect(){return {width:100,height:20};},getAttribute(){return null;},closest(){return null;}});
        var heading=node('SYNTHETIC observed title'), paragraph=node('SYNTHETIC observed article paragraph.');
        var panel={...node('SYNTHETIC unknown dialog'),querySelectorAll(){return gate==='cookie'?[node('Accept all cookies'),node('Reject all cookies')]:[node('Subscribe')];}};
        var menu=node('SYNTHETIC navigation, never article text');menu.closest=()=>({});
        var root={...node(''),matches(){return true;},querySelector(){return heading;},querySelectorAll(){return [menu,paragraph];}};
        var document={hidden:false,querySelector(){return heading;},querySelectorAll(s){
          if(s.includes('input[type=password]'))return signin?[node('')]:[];
          if(s.includes('[role=dialog]'))return gate?[panel]:[];
          bodyReads++;return [root];
        }};
        """)
        return js
    }
    @Test("Article reading excludes menus; an unknown dialog is not invented consent or subscription")
    func observedBodyAndGate() throws {
        let js = try environment()
        let script = WebArticleScript.body(pageURL: page, expiresAt: Date().addingTimeInterval(60))
        let text = try #require(WebArticleText.parse(js.evaluateScript(script)?.toString()))
        #expect(text.paragraphs == ["SYNTHETIC observed article paragraph."])
        js.evaluateScript("gate='unknown';bodyReads=0;")
        let blocked = try #require(js.evaluateScript(script)?.toString())
        #expect(WebArticleReadResult.parse(blocked) == .refused(.obstructed))
        #expect(js.objectForKeyedSubscript("bodyReads")?.toInt32() == 0)
        #expect(js.exception == nil)
    }
    @Test("Visible exact cookie controls and sign-in fields retain distinct refusal facts")
    func explicitAccessControls() throws {
        let js = try environment(), script = WebArticleScript.body(pageURL: page, expiresAt: Date().addingTimeInterval(60))
        js.evaluateScript("gate='cookie';bodyReads=0;")
        #expect(WebArticleReadResult.parse(js.evaluateScript(script)?.toString()) == .refused(.consentRequired))
        #expect(js.objectForKeyedSubscript("bodyReads")?.toInt32() == 0)
        js.evaluateScript("gate='';signin=true;bodyReads=0;")
        #expect(WebArticleReadResult.parse(js.evaluateScript(script)?.toString()) == .refused(.signInRequired))
        #expect(js.objectForKeyedSubscript("bodyReads")?.toInt32() == 0)
        #expect(js.exception == nil)
    }
    @Test("A missing article container is a layout/content failure, not an access assumption")
    func missingBodyIsNotAccess() throws {
        let js = try environment()
        js.evaluateScript("document.querySelectorAll=s=>[];")
        let raw = js.evaluateScript(WebArticleScript.body(pageURL: page, expiresAt: Date().addingTimeInterval(60)))?.toString()
        #expect(WebArticleReadResult.parse(raw) == .refused(.missingBody))
        #expect(!WebArticleRefusal.missingBody.isObservedAccessGate && js.exception == nil)
    }
    @Test("Changed pages and expired callbacks cannot read article DOM")
    func stalePage() throws {
        let js = try environment()
        js.evaluateScript("location.href='https://www.lemonde.fr/other';bodyReads=0;")
        let raw = js.evaluateScript(WebArticleScript.body(pageURL: page, expiresAt: Date().addingTimeInterval(60)))?.toString()
        #expect(raw?.contains("stale") == true && js.objectForKeyedSubscript("bodyReads")?.toInt32() == 0)
        #expect(js.exception == nil)
    }
}
#endif
