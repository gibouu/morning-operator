#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import Testing
@testable import MorningCore

@Suite("Browser reply page boundaries")
@MainActor
struct WebConversationScriptTests {
    private func page(_ site: WebMorningSite = .linkedin) throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript(#"""
        var window=this; window.top=window;
        var innerHeight=800,innerWidth=400;
        var location={protocol:'https:',hostname:'www.linkedin.com',port:'',username:'',password:'',pathname:'/messaging/thread/thread-1/',href:'https://www.linkedin.com/messaging/thread/thread-1/'};
        function getComputedStyle(){return {visibility:'visible',display:'block',opacity:'1'};}
        function InputEvent(){}
        function element(attributes={},text='') {
          return {attributes,innerText:text,textContent:text,disabled:false,id:attributes.id||'',selectors:{},
            getAttribute(k){return this.attributes[k]??null;},
            getBoundingClientRect(){return {top:0,bottom:100,left:0,right:200,width:200,height:100};},
            querySelector(s){return (this.selectors[s]||[])[0]||null;},
            querySelectorAll(s){return this.selectors[s]||[];},
            contains(e){return e===this;},closest(){return null;},
            classList:{contains(){return false;}},focus(){},dispatchEvent(){},click(){clicks++;}};
        }
        var clicks=0,contentReads=0,credential=false,dialog=false;
        var editor=element();
        Object.defineProperty(editor,'textContent',{get(){return this.innerText;},set(v){this.innerText=v;}});
        var recipient=element({},'Alex'),me=element({'data-current-user-id':'me'}),button=element();
        function makeMessage(id,text,own){var e=element({'data-event-urn':id,'data-is-self':own?'true':'false'});e.selectors['.msg-s-event-listitem__body']=[element({},text)];return e;}
        var incoming=makeMessage('incoming-1','Are you available tomorrow?',false),previous=makeMessage('previous-1','Previous reply',true);
        var messages=[previous,incoming],root=element();
        root.selectors['.msg-form__contenteditable[contenteditable="true"]']=[editor];
        root.selectors['.msg-thread__link-to-profile']=[recipient];
        root.selectors['.msg-s-message-list__event']=messages;
        root.selectors['button.msg-form__send-button']=[button];
        var document={hidden:false,
          querySelector(s){if(s.includes('input[type="password"]'))return credential?{}:null;contentReads++;return s==='.global-nav__me-photo'?me:null;},
          querySelectorAll(s){if(s==='[role="dialog"]')return dialog?[element()]:[];if(s==='[aria-modal="true"]'||s==='#onetrust-banner-sdk'||s==='[data-testid="cookie-consent"]')return [];contentReads++;return s==='.msg-thread'?[root]:[];}};
        """#)
        if site == .slack {
            context.evaluateScript(#"""
            location.hostname='app.slack.com';location.pathname='/client/T1/C1';location.href='https://app.slack.com/client/T1/C1';
            me=element({'data-current-user-id':'me'});
            root.selectors['[data-qa="message_input"][contenteditable="true"]']=[editor];
            root.selectors['[data-qa="channel_name"]']=[recipient];
            root.selectors['[data-qa="message_container"]']=messages;
            root.selectors['button[data-qa="texty_send_button"]']=[button];
            for(const e of messages){e.attributes['data-ts']=e.attributes['data-event-urn'];e.selectors['[data-qa="message-text"]']=e.selectors['.msg-s-event-listitem__body'];}
            document.querySelector=function(s){if(s.includes('input[type="password"]'))return credential?{}:null;contentReads++;return s==='[data-current-user-id]'?me:null;};
            document.querySelectorAll=function(s){if(s==='[role="dialog"]')return dialog?[element()]:[];if(s==='[aria-modal="true"]'||s==='#onetrust-banner-sdk'||s==='[data-testid="cookie-consent"]')return [];contentReads++;return s==='[data-qa="channel_view"]'?[root]:[];};
            """#)
        }
        #expect(context.exception == nil)
        return context
    }

    private func run(_ context: JSContext, site: WebMorningSite = .linkedin, command: WebConversationPolicy.Command = .observe,
                     snapshot: WebConversationSnapshot? = nil, body: String = "Yes, tomorrow.", expectedEditor: String = "") throws -> WebConversationScriptResult {
        let value = context.evaluateScript(WebConversationPolicy.script(site: site, command: command,
            snapshot: snapshot, reviewedBody: body, expectedEditorText: expectedEditor))?.toString()
        #expect(context.exception == nil)
        return try #require(WebConversationScriptResult.parse(value))
    }

    @Test("Both providers expose only a bounded selected conversation", arguments: [WebMorningSite.linkedin, .slack])
    func observe(site: WebMorningSite) throws {
        let result = try run(page(site), site: site)
        #expect(result.status == .ready)
        #expect(result.snapshot == WebConversationTests.source(site))
        #expect(result.editorText == "")
    }

    @Test("A redirected login is rejected before any document access")
    func loginOrigin() throws {
        let context = try page()
        context.evaluateScript("location.pathname='/login'; var touched=false; Object.defineProperty(this,'document',{get(){touched=true;throw Error('DOM touched');}});")
        #expect(try run(context).status == .signin)
        #expect(context.objectForKeyedSubscript("touched")?.toBool() == false)
    }

    @Test("Inline credentials and consent stop before message extraction")
    func credentialsAndConsent() throws {
        let context = try page()
        context.evaluateScript("credential=true;contentReads=0;")
        #expect(try run(context).status == .signin)
        #expect(context.objectForKeyedSubscript("contentReads")?.toInt32() == 0)
        context.evaluateScript("credential=false;dialog=true;contentReads=0;")
        #expect(try run(context).status == .choice)
        #expect(context.objectForKeyedSubscript("contentReads")?.toInt32() == 0)
    }

    @Test("A changed source, wrong draft or ambiguous editor never clicks send")
    func refuseChangedSource() throws {
        let context = try page(), original = try #require(run(context).snapshot)
        context.evaluateScript("editor.innerText='Yes, tomorrow.'; incoming.selectors['.msg-s-event-listitem__body'][0].innerText='A different question';")
        #expect(try run(context, command: .send, snapshot: original).status == .stale)
        context.evaluateScript("incoming.selectors['.msg-s-event-listitem__body'][0].innerText='Are you available tomorrow?'; editor.innerText='Changed by the user';")
        #expect(try run(context, command: .send, snapshot: original).status == .stale)
        context.evaluateScript("editor.innerText='Yes, tomorrow.'; me.attributes['data-current-user-id']='different-account';")
        #expect(try run(context, command: .send, snapshot: original).status == .stale)
        context.evaluateScript("me.attributes['data-current-user-id']='me';")
        context.evaluateScript("editor.innerText='Yes, tomorrow.'; root.selectors['.msg-form__contenteditable[contenteditable=\"true\"]'].push(element());")
        #expect(try run(context, command: .send, snapshot: original).status == .unavailable)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
    }

    @Test("Fill preserves an unrelated user draft and sends only the reviewed exact text")
    func fillAndDispatch() throws {
        let context = try page(), source = try #require(run(context).snapshot)
        context.evaluateScript("editor.innerText='My existing text';")
        #expect(try run(context, command: .fill, snapshot: source).status == .stale)
        #expect(context.objectForKeyedSubscript("editor")?.forProperty("innerText")?.toString() == "My existing text")
        #expect(try run(context, command: .fill, snapshot: source, expectedEditor: "My existing text").status == .filled)
        #expect(try run(context, command: .send, snapshot: source).status == .dispatched)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 1)
        #expect(try run(context, command: .verify, snapshot: source).status == .unavailable)
    }

    @Test("Only a new outgoing identity can verify a reply", arguments: [WebMorningSite.linkedin, .slack])
    func verifyNewOutgoing(site: WebMorningSite) throws {
        let context = try page(site)
        context.evaluateScript("previous.selectors['.msg-s-event-listitem__body'][0].innerText='Yes, tomorrow.';")
        let source = try #require(run(context, site: site).snapshot)
        #expect(try run(context, site: site, command: .verify, snapshot: source).status == .unavailable)
        context.evaluateScript(#"""
        var sent=makeMessage('new-receipt','Yes, tomorrow.',true); sent.attributes['data-ts']='new-receipt';
        sent.selectors['[data-qa="message-text"]']=sent.selectors['.msg-s-event-listitem__body']; messages.push(sent);
        """#)
        let receipt = try run(context, site: site, command: .verify, snapshot: source)
        #expect(receipt.status == .verified)
        #expect(receipt.receiptID == "new-receipt")
        context.evaluateScript("sent.attributes['data-is-self']='false';")
        #expect(try run(context, site: site, command: .verify, snapshot: source).status == .stale)
    }

    @Test("An expired send cannot touch a page control")
    func expired() throws {
        let context = try page(), source = try #require(run(context).snapshot)
        context.evaluateScript("editor.innerText='Yes, tomorrow.';")
        let value = context.evaluateScript(WebConversationPolicy.script(site: .linkedin, command: .send,
            snapshot: source, reviewedBody: "Yes, tomorrow.", expiresAt: .distantPast))?.toString()
        #expect(WebConversationScriptResult.parse(value)?.status == .stale)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
    }

    @Test("Unread navigation remains on the supported same-site thread route")
    func openUnread() throws {
        let context = try page()
        context.evaluateScript(#"""
        function URL(href,base){this.protocol='https:';this.hostname='www.linkedin.com';this.username='';this.password='';this.port='';this.pathname=href;}
        var unread=element({href:'/login'}),originalQuery=document.querySelectorAll;
        document.querySelectorAll=function(s){return s.includes('msg-conversation-listitem--unread')?[unread]:originalQuery(s);};
        """#)
        #expect(try run(context, command: .openUnread).status == .unavailable)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 0)
        context.evaluateScript("unread.attributes.href='/messaging/thread/thread-2/';")
        #expect(try run(context, command: .openUnread).status == .opened)
        #expect(context.objectForKeyedSubscript("clicks")?.toInt32() == 1)
    }

    @Test("Overlong current messages do not fall back to an older source")
    func longSource() throws {
        let context = try page()
        context.evaluateScript("incoming.selectors['.msg-s-event-listitem__body'][0].innerText='x'.repeat(4001);")
        #expect(try run(context).status == .unavailable)
    }

    @Test("Display names alone never identify the sending account")
    func ambiguousAccountName() throws {
        let context = try page()
        context.evaluateScript("delete me.attributes['data-current-user-id']; me.attributes.alt='Alex';")
        #expect(try run(context).status == .unavailable)
    }
}
#endif
