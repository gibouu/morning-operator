import Foundation
import Testing
@testable import MorningCore

@Suite("Instagram stays in the browser")
struct InstagramBrowserNavigationTests {
    private let home = WebMorningSite.instagram.table.startURL

    @Test("Initial, tapped, script and redirect loads use public browser requests once")
    func webNavigation() throws {
        var policy = InstagramBrowserNavigation()
        for kind in [InstagramBrowserNavigation.Kind.other, .link] {
            #expect(policy.decide(url: home, kind: kind) == .load(home))
            #expect(policy.decide(url: home, kind: .other) == .allow)
        }
        let redirected = try #require(URL(string: "https://instagram.com/accounts/login/?next=%2Freels%2F"))
        #expect(policy.decide(url: redirected, kind: .other) == .load(redirected))
        #expect(policy.decide(url: redirected, kind: .other) == .allow)
        // A replay allowance is consumed once, not retained for the next script.
        #expect(policy.decide(url: redirected, kind: .other) == .load(redirected))
    }

    @Test("New windows are intercepted before WebKit can try an app link")
    func newWindow() {
        var policy = InstagramBrowserNavigation()
        #expect(policy.decide(url: home, kind: .link, isNewWindow: true) == .load(home))
        #expect(policy.decide(url: home, kind: .other, isNewWindow: true) == .load(home))
        #expect(policy.decide(url: home, kind: .other) == .allow)
    }

    @Test("Known Instagram app links have safe browser equivalents; unknown app actions stop")
    func appLinks() throws {
        var policy = InstagramBrowserNavigation()
        for (raw, destination) in [("instagram://app", home),
                                   ("instagram://user?username=nasa", URL(string: "https://www.instagram.com/nasa/")!)] {
            #expect(policy.decide(url: try #require(URL(string: raw)), kind: .other) == .load(destination))
            #expect(policy.decide(url: destination, kind: .other) == .allow)
        }
        for raw in ["instagram://camera", "instagram://authorize?client_id=123", "instagram://media?id=123",
                    "instagram://user?username=nasa&username=other", "instagram://user?username=a%2Fb",
                    "instagram://user?username=nasa&url=https://evil.test", "instagram://app/path",
                    "instagram://evil:secret@user?username=nasa", "fb://profile", "javascript:alert(1)",
                    "http://www.instagram.com/", "https://name:secret@www.instagram.com/"] {
            #expect(policy.decide(url: try #require(URL(string: raw)), kind: .link) == .cancel, "\(raw)")
        }
    }

    @Test("Sign-in POSTs, history and subframes keep their request")
    func preservedNavigation() throws {
        var policy = InstagramBrowserNavigation()
        #expect(policy.decide(url: home, kind: .form, method: "POST", committedURL: home) == .allow)
        // A 302/303 after POST may retain WebKit's form navigation type while
        // changing to GET. It must use the in-browser route too.
        #expect(policy.decide(url: home, kind: .form, method: "GET") == .load(home))
        #expect(policy.decide(url: home, kind: .other) == .allow)
        #expect(policy.decide(url: home, kind: .history) == .allow)
        #expect(policy.decide(url: home, kind: .other, isTopLevel: false) == .allow)
        #expect(policy.decide(url: home, kind: .link, isDownload: true) == .cancel)
        #expect(policy.decide(url: try #require(URL(string: "instagram://app")), kind: .other, isTopLevel: false) == .cancel)
    }

    @Test("Cross-host credential bodies are never replayed or handed to native apps")
    func crossHostForms() throws {
        var policy = InstagramBrowserNavigation()
        let provider = try #require(URL(string: "https://www.facebook.com/login.php"))
        #expect(policy.decide(url: home, kind: .form, method: "POST", committedURL: provider) == .cancel)
        #expect(policy.decide(url: provider, kind: .form, method: "POST", committedURL: home) == .cancel)
        #expect(policy.decide(url: provider, kind: .form, method: "POST", committedURL: provider) == .allow)
        #expect(policy.decide(url: home, kind: .form, method: "POST") == .cancel)
    }

    @Test("HTTPS providers, app stores and redirect wrappers stay in the Instagram browser")
    func redirectChains() throws {
        var policy = InstagramBrowserNavigation()
        for raw in ["https://l.instagram.com/?u=https%3A%2F%2Fapps.apple.com%2Fapp%2Fid389801252",
                    "https://apps.apple.com/app/instagram/id389801252", "https://www.facebook.com/login.php",
                    "https://accounts.google.com/o/oauth2/auth", "https://instagram.com.evil.test/"] {
            let url = try #require(URL(string: raw))
            #expect(policy.decide(url: url, kind: .other) == .load(url))
            #expect(policy.decide(url: url, kind: .other) == .allow)
        }
        #expect(policy.decide(url: try #require(URL(string: "intent://instagram.com/#Intent;scheme=instagram;end")), kind: .other) == .cancel)
    }

    @Test("Repeated redirect replay has a finite load budget")
    func redirectLoop() {
        var policy = InstagramBrowserNavigation()
        for _ in 0..<16 {
            #expect(policy.decide(url: home, kind: .other) == .load(home))
            #expect(policy.decide(url: home, kind: .other) == .allow)
        }
        #expect(policy.decide(url: home, kind: .other) == .cancel)
        #expect(policy.decide(url: home, kind: .other) == .cancel)
        policy = InstagramBrowserNavigation()
        #expect(policy.decide(url: home, kind: .other) == .load(home))
    }
}
