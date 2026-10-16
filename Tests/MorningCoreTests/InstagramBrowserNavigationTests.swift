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

    @Test("Sign-in POSTs, history, subframes and other HTTPS providers keep their request")
    func preservedNavigation() throws {
        var policy = InstagramBrowserNavigation()
        #expect(policy.decide(url: home, kind: .form, method: "POST") == .allow)
        #expect(policy.decide(url: home, kind: .history) == .allow)
        #expect(policy.decide(url: home, kind: .other, isTopLevel: false) == .allow)
        for raw in ["https://www.facebook.com/login.php", "https://accounts.google.com/o/oauth2/auth",
                    "https://instagram.com.evil.test/", "https://example.com/"] {
            #expect(policy.decide(url: try #require(URL(string: raw)), kind: .link) == .allow)
        }
        #expect(policy.decide(url: home, kind: .link, isDownload: true) == .cancel)
        #expect(policy.decide(url: try #require(URL(string: "instagram://app")), kind: .other, isTopLevel: false) == .cancel)
    }
}
