#if canImport(JavaScriptCore)
import JavaScriptCore
import Testing
@testable import MorningCore

/// Executes the real page scripts against synthetic pages. No network or account data.
@Suite("Web page script boundaries")
@MainActor
struct WebMorningScriptBehaviorTests {
    @Test("A redirected sign-in page is refused before any DOM access")
    func redirectedSignIn() throws {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var location = {protocol:'https:', hostname:'accounts.google.com', port:'',
                        username:'', password:'', pathname:'/signin'};
        var touched = false;
        Object.defineProperty(this, 'document', {get() {touched=true; throw Error('DOM touched');}});
        """)
        let script = try #require(WebMorningPolicy.script(for: .unreadCount, on: .instagram))
        let result = try #require(context.evaluateScript(script)?.toString())
        #expect(WebMorningOutcome.parse(result, task: .unreadCount) == .unsupported("layout"))
        #expect(context.objectForKeyedSubscript("touched")?.toBool() == false)
        #expect(context.exception == nil)
    }

    @Test("A password form on a normal site URL stops before content reads")
    func inlineSignInForm() throws {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var location = {protocol:'https:', hostname:'www.instagram.com', port:'',
                        username:'', password:'', pathname:'/'};
        var document = {querySelector(selector) {
          if (selector.includes('input[type="password"]')) return {};
          throw Error('Page content read during sign-in');
        }};
        """)
        let script = try #require(WebMorningPolicy.script(for: .unreadCount, on: .instagram))
        let result = try #require(context.evaluateScript(script)?.toString())
        #expect(WebMorningOutcome.parse(result, task: .unreadCount) == .unsupported("signin"))
        #expect(context.exception == nil)
    }

    @Test("A page without room to scroll does not report a successful move")
    func endOfFeed() throws {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var location = {protocol:'https:', hostname:'m.youtube.com', port:'',
                        username:'', password:'', pathname:'/shorts/example'};
        var video = {parentElement:null, getBoundingClientRect() {return {height:600,top:0,bottom:600};}};
        var document = {body:{}, documentElement:{},
          scrollingElement:{scrollTop:0,scrollHeight:600},
          querySelector(selector) {return selector==='video' ? video : null;},
          querySelectorAll(selector) {return selector==='video' ? [video] : [];}};
        var window = {innerHeight:600, scrollBy() {throw Error('Unexpected scroll');}};
        """)
        let script = try #require(WebMorningPolicy.script(for: .nextVideo, on: .youtube))
        let result = try #require(context.evaluateScript(script)?.toString())
        #expect(WebMorningOutcome.parse(result, task: .nextVideo) == .unsupported("layout"))
        #expect(context.exception == nil)
    }

    @Test("A route change away from the video feed is refused inside the script")
    func sameSiteRouteChanged() throws {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var location = {protocol:'https:', hostname:'www.instagram.com', port:'',
                        username:'', password:'', pathname:'/some-profile/'};
        var touched = false;
        Object.defineProperty(this, 'document', {get() {touched=true; throw Error('Wrong page DOM touched');}});
        """)
        let script = try #require(WebMorningPolicy.script(for: .nextVideo, on: .instagram))
        let result = try #require(context.evaluateScript(script)?.toString())
        #expect(WebMorningOutcome.parse(result, task: .nextVideo) == .unsupported("layout"))
        #expect(context.objectForKeyedSubscript("touched")?.toBool() == false)
        #expect(context.exception == nil)
    }
}
#endif
