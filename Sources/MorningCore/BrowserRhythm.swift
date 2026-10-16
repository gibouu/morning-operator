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
    public let learningTrace: BrowserLearningTrace?
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
    public private(set) var segments: [BrowserLearningSegment] = []
    public init(site: WebMorningSite) { self.site = site }

    @discardableResult public mutating func update(_ value: BrowserRhythmTotals,
        segments: [BrowserLearningSegment] = []) -> Bool {
        guard value.distance >= totals.distance, value.movingSeconds >= totals.movingSeconds,
              value.scrollBursts >= totals.scrollBursts, value.clicks >= totals.clicks,
              BrowserLearningTrace.validSegments(segments, site: site, durationSeconds: 900),
              segments.count >= self.segments.count else { return false }
        for index in self.segments.indices {
            let previous = self.segments[index], next = segments[index]
            if index == self.segments.count - 1 {
                guard previous.behavior == next.behavior, previous.startSeconds == next.startSeconds,
                      previous.endSeconds <= next.endSeconds, previous.gestures <= next.gestures else { return false }
            } else if previous != next { return false }
        }
        totals = value
        self.segments = segments
        return true
    }

    public func summary(durationSeconds: Double) -> BrowserRhythmSummary {
        let duration = durationSeconds.isFinite ? min(900, max(0, durationSeconds)) : 0
        return .init(site: site, durationSeconds: duration, totals: totals,
            learningTrace: BrowserLearningTrace(site: site, durationSeconds: duration, segments: segments))
    }
}

public enum BrowserRhythmPolicy {
    public static func permits(site: WebMorningSite, url: URL?) -> Bool {
        guard let url, WebMorningSite(url: url) == site, !WebMorningPolicy.isSignInPage(url) else { return false }
        return true
    }

    /// Known route families only. A root messaging page says nothing about unread
    /// messages; profile/search/article routes say nothing about a feed action.
    public static func behavior(site: WebMorningSite, url: URL?) -> WebMorningBehavior? {
        guard permits(site: site, url: url), let url else { return nil }
        let path = url.path.lowercased().split(separator: "/").map(String.init)
        switch site {
        case .instagram:
            if path.isEmpty { return .browseFeed }
            if path.first == "stories", path.count >= 2 { return .watchStories }
            if ["reel", "reels"].contains(path.first ?? "") { return .watchVideos }
        case .facebook:
            if path.isEmpty || path == ["home.php"] { return .browseFeed }
            if path.first == "stories" { return .watchStories }
        case .tiktok:
            if path.isEmpty || path == ["foryou"] || path == ["following"] { return .watchVideos }
        case .youtube:
            if path.first == "shorts" { return .watchVideos }
        case .twitter:
            if path.isEmpty || path == ["home"] { return .browseFeed }
        case .reddit:
            if path.isEmpty || (path.count == 2 && path.first == "r") { return .browseFeed }
        case .threads:
            if path.isEmpty || path == ["following"] { return .browseFeed }
        case .linkedin:
            if path == ["feed"] { return .browseFeed }
        case .news:
            if path.isEmpty { return .readHeadlines }
        case .gmail, .whatsapp, .slack: return nil
        }
        return nil
    }

    /// Installed only for the visible document after Start learning. Capture-phase
    /// scroll observes nested elements in that document, never cross-origin frames.
    public static func script(site: WebMorningSite, nonce: UUID) -> String {
        let paths = json(WebMorningPolicy.signInPathFragments)
        return #"""
        (() => {
          const nonce = '\#(nonce.uuidString)', paths = \#(paths), site = '\#(site.rawValue)';
          const previous = globalThis.__moreRhythm;
          if (previous) previous.stop(previous.nonce);
          let ended = false, pending = null, userUntil = 0, lastScroll = -Infinity;
          let distance = 0, movingSeconds = 0, scrollBursts = 0, clicks = 0;
          const started = performance.now(), segments = [];
          let lastBehavior = null, semanticEnded = false;
          const positions = new WeakMap();
          const field = target => target instanceof Element && !!target.closest('input,textarea,select,[contenteditable],[role="textbox"]');
          const inputEvent = event => field(event.target) || event.composedPath().some(field);
          const behavior = () => {
            const p = location.pathname.toLowerCase().split('/').filter(Boolean), first = p[0];
            if (site === 'instagram') {
              if (!p.length) return 'browseFeed';
              if (first === 'stories' && p.length >= 2) return 'watchStories';
              if (['reel','reels'].includes(first)) return 'watchVideos';
            } else if (site === 'facebook') {
              if (!p.length || (p.length === 1 && first === 'home.php')) return 'browseFeed';
              if (first === 'stories') return 'watchStories';
            } else if (site === 'tiktok') {
              if (!p.length || (p.length === 1 && ['foryou','following'].includes(first))) return 'watchVideos';
            } else if (site === 'youtube') {
              if (first === 'shorts') return 'watchVideos';
            } else if (site === 'twitter') {
              if (!p.length || (p.length === 1 && first === 'home')) return 'browseFeed';
            } else if (site === 'reddit') {
              if (!p.length || (p.length === 2 && first === 'r')) return 'browseFeed';
            } else if (site === 'threads') {
              if (!p.length || (p.length === 1 && first === 'following')) return 'browseFeed';
            } else if (site === 'linkedin') {
              if (p.length === 1 && first === 'feed') return 'browseFeed';
            } else if (site === 'news' && !p.length) return 'readHeadlines';
            return null;
          };
          const record = now => {
            const current = behavior(), elapsed = (now - started) / 1000;
            if (semanticEnded || !Number.isFinite(elapsed) || elapsed < 0 || elapsed > 900) return;
            if (!current) { lastBehavior = null; return; }
            const previous = segments[segments.length - 1];
            if (previous && lastBehavior === current && previous.gestures < 100000) {
              previous.endSeconds = elapsed; previous.gestures++;
            } else {
              // Preserve the beginning of the observed sequence. Never evict an
              // earlier segment or pretend the bounded lesson covers every route.
              if (segments.length >= 16) { semanticEnded = true; return; }
              segments.push({behavior:current,startSeconds:elapsed,endSeconds:elapsed,gestures:1});
            }
            lastBehavior = current;
          };
          const safe = () => window.top === window && !document.hidden && location.protocol === 'https:' &&
            \#(site.table.javascriptPermitsHost("location.hostname")) &&
            (!location.port || location.port === '443') && !location.username && !location.password &&
            !paths.some(p => (location.pathname.toLowerCase() + '/').includes(p)) &&
            !document.querySelector('input[type="password"],input[type="email"],input[autocomplete="username"],input[autocomplete="current-password"],input[autocomplete="new-password"],input[autocomplete="one-time-code"],form[action*="login" i],form[action*="signin" i]');
          const post = body => {
            // Native revokes the bridge before asking this document to stop.
            // Missing or closed bridges must never prevent DOM cleanup.
            try { window.webkit?.messageHandlers?.moreRhythm?.postMessage({nonce, ...body}); } catch (_) {}
          };
          const flush = () => {
            if (pending) clearTimeout(pending);
            pending = null;
            if (!ended && safe()) post({distance, movingSeconds, scrollBursts, clicks, segments});
          };
          const queue = () => { if (!pending) pending = setTimeout(flush, 250); };
          const remember = node => {
            if (node instanceof Element) positions.set(node, {top: node.scrollTop, time: performance.now()});
          };
          const input = event => {
            if (!event.isTrusted || inputEvent(event)) return;
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
            record(now);
            queue();
          };
          const click = event => {
            if (!event.isTrusted || inputEvent(event)) return;
            if (!safe()) { stop(nonce, true); return; }
            clicks++; record(performance.now()); flush();
          };
          const changed = () => {
            if (!safe()) stop(nonce, true);
            else if (behavior() !== lastBehavior) lastBehavior = null;
          };
          const observer = new MutationObserver(changed);
          function stop(requested, blocked = false) {
            if (requested !== nonce || ended) return;
            try {
              if (!blocked) flush();
            } finally {
              ended = true;
              clearTimeout(pending);
              for (const name of ['pointerdown', 'touchstart', 'wheel']) document.removeEventListener(name, input, true);
              document.removeEventListener('scroll', scroll, true);
              document.removeEventListener('click', click, true);
              document.removeEventListener('visibilitychange', changed, true);
              observer.disconnect();
              if (blocked) post({blocked: true});
              if (globalThis.__moreRhythm?.nonce === nonce) delete globalThis.__moreRhythm;
            }
            return {distance, movingSeconds, scrollBursts, clicks, segments};
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
