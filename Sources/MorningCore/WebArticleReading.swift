import Foundation

/// Volatile observations, never model-provided destinations or saved routine actions.
public struct WebArticleLink: Codable, Sendable, Equatable {
    public let title: String
    public let href: URL
    public init(title: String, href: URL) { self.title = title; self.href = href }
}

public struct WebNewsSnapshot: Sendable, Equatable {
    public let context: MorningVoiceCommandContext
    public let privacyGeneration: UUID
    public let pageGeneration: Int
    public let pageURL: URL
    public let fingerprint: String
    public let links: [WebArticleLink]
    public init?(context: MorningVoiceCommandContext, privacyGeneration: UUID, pageGeneration: Int,
        pageURL: URL, fingerprint: String, links: [WebArticleLink], syntheticNews: SyntheticNewsOrigin? = nil) {
        guard WebArticlePolicy.isPage(pageURL, syntheticNews: syntheticNews), !fingerprint.isEmpty, fingerprint.count <= 128,
              (1...5).contains(links.count), Set(links.map(\.href)).count == links.count,
              links.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.title.count <= 240 && WebArticlePolicy.permits($0.href, from: pageURL, syntheticNews: syntheticNews) }) else { return nil }
        self.context = context; self.privacyGeneration = privacyGeneration; self.pageGeneration = pageGeneration
        self.pageURL = pageURL; self.fingerprint = fingerprint; self.links = links
    }
    public var numberedTitles: [String] { links.enumerated().map { "\($0.offset + 1). \($0.element.title)" } }
    public func matches(context: MorningVoiceCommandContext, privacyGeneration: UUID,
        pageGeneration: Int, pageURL: URL?) -> Bool {
        self.context == context && self.privacyGeneration == privacyGeneration && self.pageGeneration == pageGeneration && self.pageURL == pageURL
    }
    public func select(_ ordinal: Int) -> WebArticleLink? { ordinal > 0 && ordinal <= links.count ? links[ordinal - 1] : nil }
    public func matchesObservation(_ observation: WebMorningPageObservation) -> Bool {
        observation.status == .ready && observation.fingerprint == fingerprint && observation.articles == links
    }
}

public enum WebArticleCommand: Equatable, Sendable {
    case select(ordinal: Int, read: Bool), returnToList(resume: Bool), repeatArticle, unclearSelection
    public static func parse(_ text: String) -> Self? {
        let words = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let phrase = (words.first == "more" ? Array(words.dropFirst()) : words).joined(separator: " ")
        if ["back to headlines", "return to headlines", "back to the list", "retour aux titres", "reviens aux titres", "retour a la liste"].contains(phrase) { return .returnToList(resume: false) }
        if ["continue", "resume", "reprends", "reprendre", "continuer"].contains(phrase) { return .returnToList(resume: true) }
        if ["read the article again", "repeat the article", "relis l article", "repete l article"].contains(phrase) { return .repeatArticle }
        let ordinals = ["first": 1, "premier": 1, "1": 1, "second": 2, "secondieme": 2, "deuxieme": 2, "2": 2,
            "third": 3, "troisieme": 3, "3": 3, "fourth": 4, "quatrieme": 4, "4": 4,
            "fifth": 5, "cinquieme": 5, "5": 5, "sixth": 6, "sixieme": 6, "6": 6]
        let numericOrdinals = ["1st": 1, "1er": 1, "2nd": 2, "2e": 2, "2eme": 2, "3rd": 3, "3e": 3,
            "4th": 4, "4e": 4, "5th": 5, "5e": 5]
        for (verb, read) in [("read", true), ("open", false), ("lis", true), ("lire", true), ("ouvre", false), ("ouvrir", false)] {
            for (word, ordinal) in ordinals.merging(numericOrdinals, uniquingKeysWith: { first, _ in first }) {
                if ["\(verb) the \(word) article", "\(verb) \(word) article", "\(verb) le \(word) article",
                    "\(verb) l article \(word)", "\(verb) article \(word)"].contains(phrase) { return .select(ordinal: ordinal, read: read) }
            }
        }
        if ["read", "open", "lis", "lire", "ouvre", "ouvrir"].contains(words.first ?? ""), words.contains("article") {
            return .unclearSelection
        }
        return nil
    }
}

public enum WebArticlePolicy {
    public static let maximumCharacters = 6_000
    public static func isPage(_ url: URL, syntheticNews: SyntheticNewsOrigin? = nil) -> Bool {
        if let syntheticNews { return syntheticNews.permits(url) }
        return url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil &&
            (url.port == nil || url.port == 443) && WebMorningSite(url: url) == .news && !WebMorningPolicy.isSignInPage(url)
    }
    public static func permits(_ url: URL, from page: URL, syntheticNews: SyntheticNewsOrigin? = nil) -> Bool {
        guard isPage(url, syntheticNews: syntheticNews), isPage(page, syntheticNews: syntheticNews), url.host?.lowercased() == page.host?.lowercased(),
              url.absoluteString.utf8.count <= 2_048, !["pdf", "zip", "epub", "mp3", "mp4"].contains(url.pathExtension.lowercased()) else { return false }
        var destination = URLComponents(url: url, resolvingAgainstBaseURL: false), source = URLComponents(url: page, resolvingAgainstBaseURL: false)
        destination?.fragment = nil; source?.fragment = nil
        return destination?.url != source?.url
    }
    public static func matchesDestination(_ observed: URL, selected: URL, syntheticNews: SyntheticNewsOrigin? = nil) -> Bool {
        guard isPage(observed, syntheticNews: syntheticNews), isPage(selected, syntheticNews: syntheticNews) else { return false }
        var actual = URLComponents(url: observed, resolvingAgainstBaseURL: false)
        var expected = URLComponents(url: selected, resolvingAgainstBaseURL: false)
        actual?.fragment = nil; expected?.fragment = nil
        return actual?.url == expected?.url
    }
    public static func permitsResponse(selected: URL, observed: URL, status: Int) -> Bool {
        (200..<300).contains(status) && matchesDestination(observed, selected: selected)
    }
}

/// Volatile refusal facts, never persisted article/source data. Only explicit
/// visible access controls justify treating a live acceptance run as blocked.
public enum WebArticleRefusal: String, Sendable, Equatable, CaseIterable {
    case signInRequired, consentRequired, obstructed, stale, missingBody, invalidScriptResult
    case unexpectedDestination, httpFailure, unsupportedContent, navigationTimeout, navigationFailure, selectionUnavailable

    public var isObservedAccessGate: Bool { self == .signInRequired || self == .consentRequired }
    public func message(french: Bool) -> String {
        let reason: String
        switch self {
        case .signInRequired: reason = french ? "La page affiche des champs de connexion. Je n’ai pas lu l’article." : "The page displays sign-in fields. I did not read the article."
        case .consentRequired: reason = french ? "La page affiche un choix de cookies. Je n’ai pas lu l’article." : "The page displays a cookie choice. I did not read the article."
        case .obstructed: reason = french ? "Un panneau masque la lecture. Je ne peux pas en confirmer la raison et je n’ai pas lu l’article." : "A panel blocks reading. I cannot confirm its reason and did not read the article."
        case .stale: reason = french ? "La page ou les titres ont changé depuis votre choix. Je n’ai pas lu l’article." : "The page or headlines changed after your choice. I did not read the article."
        case .missingBody: reason = french ? "Aucun corps d’article lisible n’a été trouvé sur cette page. Je n’ai pas lu l’article." : "No readable article body was found on this page. I did not read the article."
        case .invalidScriptResult: reason = french ? "La lecture de cette page n’a pas produit de résultat fiable. Je n’ai pas lu l’article." : "Reading this page did not produce a reliable result. I did not read the article."
        case .unexpectedDestination: reason = french ? "La destination ne correspond pas à l’article choisi. Je ne l’ai pas lu." : "The destination does not match the chosen article. I did not read it."
        case .httpFailure: reason = french ? "Le site a renvoyé une erreur pour l’article choisi. Je ne l’ai pas lu." : "The site returned an error for the chosen article. I did not read it."
        case .unsupportedContent: reason = french ? "Le contenu reçu n’est pas une page d’article lisible. Je ne l’ai pas lu." : "The received content is not a readable article page. I did not read it."
        case .navigationTimeout: reason = french ? "Le chargement de l’article n’a pas été confirmé à temps. Je ne l’ai pas lu." : "The article did not finish loading in time. I did not read it."
        case .navigationFailure: reason = french ? "Le chargement de l’article a échoué. Je ne l’ai pas lu." : "Loading the article failed. I did not read it."
        case .selectionUnavailable: reason = french ? "Ce numéro n’est pas disponible dans les titres observés." : "That number is not available in the observed headlines."
        }
        return reason + (french ? " Revenez aux titres ou passez au moment suivant." : " Return to headlines or skip to the next moment.")
    }
}

/// A malformed script/unknown refusal is an internal reading failure, never an
/// inferred subscription, sign-in requirement or successful empty article.
public enum WebArticleReadResult: Sendable, Equatable {
    case content(WebArticleText), refused(WebArticleRefusal)
    public static func parse(_ value: Any?) -> Self {
        guard let raw = value as? String, raw.utf8.count <= 32_000,
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return .refused(.invalidScriptResult) }
        if Set(object.keys) == ["reason"], let code = object["reason"] as? String,
           let reason = WebArticleRefusal(rawValue: code),
           [.signInRequired, .consentRequired, .obstructed, .stale, .missingBody].contains(reason) { return .refused(reason) }
        guard Set(object.keys) == ["title", "paragraphs", "truncated"], let text = WebArticleText.parse(raw) else { return .refused(.invalidScriptResult) }
        return .content(text)
    }
}

/// A bounded, attributed passage from an article container in the visible browser.
/// Missing paragraphs and subscription/consent gates are explicit failures.
public struct WebArticleText: Decodable, Sendable, Equatable {
    public let title: String
    public let paragraphs: [String]
    public let truncated: Bool
    public static func parse(_ value: Any?) -> Self? {
        guard let raw = value as? String, raw.utf8.count <= 32_000,
              let data = raw.data(using: .utf8), let result = try? JSONDecoder().decode(Self.self, from: data),
              !result.title.isEmpty, result.title.count <= 240, (1...12).contains(result.paragraphs.count),
              result.paragraphs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1_000 }),
              result.paragraphs.reduce(0, { $0 + $1.count }) <= WebArticlePolicy.maximumCharacters else { return nil }
        return result
    }
    public func narration(source: String, french: Bool) -> String {
        (french ? "\(source). \(title). Texte de l’article visible dans MORE. " : "\(source). \(title). Article text visible in MORE. ") +
            paragraphs.joined(separator: "\n") + (truncated ? (french ? " Lecture abrégée ; la suite reste dans la page." : " This reading is shortened; the rest remains on the page.") : "") +
            (french ? " Dites retour aux titres, reprends ou suivant." : " Say back to headlines, resume, or next.")
    }
}

public enum WebArticleScript {
    /// Reads rendered article paragraphs only. Never body text, form values, a
    /// paywall API, hidden DOM, navigation/menu text or a parallel network fetch.
    public static func body(pageURL: URL, expiresAt: Date) -> String {
        #"""
        (()=>{
          const out=x=>JSON.stringify(x), expected=\#(json(pageURL.absoluteString));
          if(Date.now()>\#(Int(expiresAt.timeIntervalSince1970*1000)) || window.top!==window || location.href!==expected || document.hidden) return out({reason:'stale'});
          const clean=s=>(s||'').replace(/\s+/g,' ').trim();
          const shown=e=>{if(!e)return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden'&&s.opacity!=='0'&&e.getAttribute('aria-hidden')!=='true';};
          if([...document.querySelectorAll('input[type=password],input[autocomplete=one-time-code],form[action*="login" i]')].some(shown))return out({reason:'signInRequired'});
          // Generic overlays are not evidence of a subscription or consent wall.
          // Cookie consent is recognized only from visible, explicitly named
          // cookie buttons inside a visible panel; no provider selector is guessed.
          const panels=[...document.querySelectorAll('[role=dialog],[aria-modal=true],[id*="consent" i],[class*="paywall" i],[id*="paywall" i],.article__paywall,.paywall')].filter(shown);
          const cookieAccept=['accepter les cookies','tout accepter les cookies','accept all cookies','accept cookies'];
          const cookieDecline=['refuser les cookies','reject all cookies','reject cookies','continuer sans accepter','continue without accepting','refuser tout','reject all'];
          const cookiePanel=panels.some(p=>{
            const names=[...p.querySelectorAll('button,[role=button]')].filter(shown).map(e=>clean(e.getAttribute('aria-label')||e.innerText).toLowerCase());
            return names.some(n=>cookieAccept.includes(n))&&names.some(n=>cookieDecline.includes(n));
          });
          if(cookiePanel)return out({reason:'consentRequired'});
          if(panels.length)return out({reason:'obstructed'});
          const roots=[...document.querySelectorAll('[itemprop=articleBody],.article__body,.article__content,article')].filter(shown);
          const candidates=roots.filter(r=>r.matches('[itemprop=articleBody],.article__body,.article__content') || r.querySelector('h1'));
          if(!candidates.length)return out({reason:'missingBody'});
          const root=candidates[0], heading=root.querySelector('h1') || document.querySelector('main h1');
          if(!shown(heading))return out({reason:'missingBody'});
          const title=clean(heading.innerText).slice(0,240), all=[...root.querySelectorAll('p')].filter(p=>shown(p)&&!p.closest('nav,aside,footer,form,header,[role=navigation],.article__related,.article__author,.article__credits'));
          let count=0,paragraphs=[],truncated=false;
          for(const p of all){let t=clean(p.innerText);if(!t)continue;if(paragraphs.length===12||count===6000){truncated=true;break;}const n=Math.min(1000,6000-count);if(t.length>n){t=t.slice(0,n);truncated=true;}paragraphs.push(t);count+=t.length;}
          if(!title||!paragraphs.length)return out({reason:'missingBody'});
          return out({title,paragraphs,truncated});
        })()
        """#
    }
    private static func json(_ value: String) -> String { String(data: (try? JSONEncoder().encode(value)) ?? Data(), encoding: .utf8) ?? "null" }
}
