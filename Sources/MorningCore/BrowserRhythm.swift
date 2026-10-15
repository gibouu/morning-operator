import Foundation

/// Numeric browser observations only. No event targets, text, addresses or input
/// values belong in this model. Distances are CSS pixels, rather than screen points.
public struct BrowserRhythmTotals: Equatable, Sendable {
    public let distance: Double
    public let movingSeconds: Double
    public let scrollBursts: Int
    public let clicks: Int

    public init?(distance: Double, movingSeconds: Double, scrollBursts: Int, clicks: Int) {
        guard distance.isFinite, movingSeconds.isFinite,
              (0...10_000_000).contains(distance), (0...900).contains(movingSeconds),
              (0...100_000).contains(scrollBursts), (0...100_000).contains(clicks) else { return nil }
        self.distance = distance; self.movingSeconds = movingSeconds
        self.scrollBursts = scrollBursts; self.clicks = clicks
    }
}

public struct BrowserRhythmSummary: Equatable, Sendable {
    public let site: WebMorningSite
    public let durationSeconds: Double
    public let totals: BrowserRhythmTotals
    public var averageMovingSpeed: Double? {
        guard totals.movingSeconds > 0 else { return nil }
        let speed = totals.distance / totals.movingSeconds
        return speed.isFinite && (0...100_000).contains(speed) ? speed : nil
    }
}

/// A single in-memory aggregate, never a replayable interaction history.
public struct BrowserRhythmAccumulator: Sendable {
    public let site: WebMorningSite
    public private(set) var totals = BrowserRhythmTotals(distance: 0, movingSeconds: 0, scrollBursts: 0, clicks: 0)!
    public init(site: WebMorningSite) { self.site = site }

    @discardableResult public mutating func update(_ value: BrowserRhythmTotals) -> Bool {
        guard value.distance >= totals.distance, value.movingSeconds >= totals.movingSeconds,
              value.scrollBursts >= totals.scrollBursts, value.clicks >= totals.clicks else { return false }
        totals = value
        return true
    }

    public func summary(durationSeconds: Double) -> BrowserRhythmSummary {
        .init(site: site, durationSeconds: durationSeconds.isFinite ? min(900, max(0, durationSeconds)) : 0, totals: totals)
    }
}

public enum BrowserRhythmPolicy {
    public static func permits(site: WebMorningSite, url: URL?) -> Bool {
        guard let url, WebMorningSite(url: url) == site, !WebMorningPolicy.isSignInPage(url) else { return false }
        return true
    }

    /// Installed only for the visible document after Start learning. Capture-phase
    /// scroll observes nested elements in that document, never cross-origin frames.
    public static func script(site: WebMorningSite, nonce: UUID) -> String {
        let hosts = json(site.table.allowedHosts.sorted())
        let paths = json(WebMorningPolicy.signInPathFragments)
        return #"""
        (() => {
          const nonce = '\#(nonce.uuidString)', hosts = \#(hosts), paths = \#(paths);
          const previous = globalThis.__moreRhythm;
          if (previous) previous.stop(previous.nonce);
          let ended = false, pending = null, userUntil = 0, lastScroll = -Infinity;
          let distance = 0, movingSeconds = 0, scrollBursts = 0, clicks = 0;
          const positions = new WeakMap();
          const field = target => target instanceof Element && !!target.closest('input,textarea,select,[contenteditable],[role="textbox"]');
          const safe = () => window.top === window && !document.hidden && location.protocol === 'https:' &&
            hosts.includes(location.hostname.toLowerCase()) && !paths.some(p => (location.pathname.toLowerCase() + '/').includes(p)) &&
            !document.querySelector('input[type="password"],input[type="email"],input[autocomplete="username"],input[autocomplete="current-password"],input[autocomplete="new-password"],input[autocomplete="one-time-code"],form[action*="login" i],form[action*="signin" i]');
          const post = body => window.webkit.messageHandlers.moreRhythm.postMessage({nonce, ...body});
          const flush = () => {
            if (pending) clearTimeout(pending);
            pending = null;
            if (!ended && safe()) post({distance, movingSeconds, scrollBursts, clicks});
          };
          const queue = () => { if (!pending) pending = setTimeout(flush, 250); };
          const remember = node => {
            if (node instanceof Element) positions.set(node, {top: node.scrollTop, time: performance.now()});
          };
          const input = event => {
            if (!event.isTrusted || field(event.target)) return;
            if (!safe()) { stop(nonce, true); return; }
            userUntil = performance.now() + 2000;
            event.composedPath().forEach(remember);
            remember(document.scrollingElement);
          };
          const scroll = event => {
            if (!safe()) { stop(nonce, true); return; }
            const now = performance.now();
            const node = event.target === document ? document.scrollingElement : event.target;
            if (!(node instanceof Element) || field(node)) return;
            const prior = positions.get(node), top = node.scrollTop;
            positions.set(node, {top, time: now});
            if (now > userUntil || !prior) return;
            const delta = Math.abs(top - prior.top);
            if (!Number.isFinite(delta) || delta === 0 || delta > 10000) return;
            distance += delta;
            movingSeconds += Math.min(0.25, Math.max(0, now - prior.time) / 1000);
            if (now - lastScroll > 300) scrollBursts++;
            lastScroll = now;
            queue();
          };
          const click = event => {
            if (!event.isTrusted || field(event.target)) return;
            if (!safe()) { stop(nonce, true); return; }
            clicks++; flush();
          };
          const changed = () => { if (!safe()) stop(nonce, true); };
          const observer = new MutationObserver(changed);
          function stop(requested, blocked = false) {
            if (requested !== nonce || ended) return;
            if (!blocked) flush();
            ended = true;
            clearTimeout(pending);
            for (const name of ['pointerdown', 'touchstart', 'wheel']) document.removeEventListener(name, input, true);
            document.removeEventListener('scroll', scroll, true);
            document.removeEventListener('click', click, true);
            document.removeEventListener('visibilitychange', changed, true);
            observer.disconnect();
            if (blocked) post({blocked: true});
            if (globalThis.__moreRhythm?.nonce === nonce) delete globalThis.__moreRhythm;
            return {distance, movingSeconds, scrollBursts, clicks};
          }
          if (!safe()) return false;
          globalThis.__moreRhythm = {nonce, stop};
          for (const name of ['pointerdown', 'touchstart', 'wheel']) document.addEventListener(name, input, {capture:true, passive:true});
          document.addEventListener('scroll', scroll, {capture:true, passive:true});
          document.addEventListener('click', click, {capture:true, passive:true});
          document.addEventListener('visibilitychange', changed, true);
          observer.observe(document.documentElement, {childList:true, subtree:true, attributes:true, attributeFilter:['type','autocomplete']});
          return true;
        })()
        """#
    }

    private static func json(_ value: [String]) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }
}
