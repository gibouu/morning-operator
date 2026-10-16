import Foundation
import CryptoKit

/// Private page content lives in memory; only digests enter the action journal.
public struct WebConversationSnapshot: Codable, Sendable, Equatable {
    public let site: WebMorningSite
    public let conversationID: String
    public let recipient: String
    public let accountID: String
    public let messageID: String
    public let messageText: String
    public let editorID: String
    public let outgoingMessageIDs: [String]

    public init(site: WebMorningSite, conversationID: String, recipient: String, accountID: String,
                messageID: String, messageText: String, editorID: String, outgoingMessageIDs: [String]) {
        self.site = site; self.conversationID = conversationID; self.recipient = recipient; self.accountID = accountID
        self.messageID = messageID; self.messageText = messageText; self.editorID = editorID
        self.outgoingMessageIDs = outgoingMessageIDs
    }

    public var isValid: Bool {
        [.linkedin, .slack].contains(site) && bounded(conversationID, 512) && bounded(recipient, 200) &&
            bounded(accountID, 512) && bounded(messageID, 512) && bounded(messageText, 4_000) && bounded(editorID, 100) &&
            outgoingMessageIDs.count <= 200 && Set(outgoingMessageIDs).count == outgoingMessageIDs.count &&
            outgoingMessageIDs.allSatisfy { bounded($0, 512) }
    }
    public var fingerprint: String { WebConversationPolicy.digest([site.rawValue, conversationID, recipient, accountID, messageID, messageText, editorID]) }
    public var targetKey: String { WebConversationPolicy.digest([site.rawValue, conversationID, accountID]) }
    private func bounded(_ text: String, _ limit: Int) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= limit }
}

public struct WebConversationScriptResult: Decodable, Sendable, Equatable {
    public enum Status: String, Decodable, Sendable { case ready, signin, choice, unavailable, stale, opened, filled, dispatched, verified }
    public let status: Status
    public let snapshot: WebConversationSnapshot?
    public let receiptID: String?
    public let editorText: String?

    public static func parse(_ value: Any?) -> Self? {
        guard let string = value as? String, string.utf8.count <= 150_000,
              let data = string.data(using: .utf8), let result = try? JSONDecoder().decode(Self.self, from: data),
              result.snapshot.map({ $0.isValid }) != false,
              result.receiptID.map({ !$0.isEmpty && $0.count <= 512 }) != false,
              result.editorText.map({ $0.count <= 4_000 }) != false,
              ![.ready, .filled, .dispatched, .verified].contains(result.status) || result.snapshot != nil,
              result.status != .verified || result.receiptID != nil else { return nil }
        return result
    }
}

public enum WebConversationIntent: Sendable, Equatable {
    case read, reply(String), revise(String), accept, decline, send, repeatReply, cancel
    public static func parse(_ text: String) -> Self? {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = original.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        switch words {
        case "oui", "yes", "okay", "ok": return .accept
        case "non", "no", "continue", "continuer": return .decline
        case "annule", "annuler", "cancel": return .cancel
        case "envoie", "envoyer", "envoie la reponse", "send", "send it", "send reply", "send the reply": return .send
        case "repete", "relis", "relis la reponse", "repeat", "read it again", "read the reply": return .repeatReply
        case "lis les messages", "lis le message", "lis cette conversation", "lis la conversation", "lis mes messages", "read messages", "read the message", "read this conversation", "read the conversation": return .read
        case "reponds", "repond", "reponds lui", "repond lui", "reply", "reply to them", "respond", "peux tu repondre", "can you reply": return .reply("")
        default: break
        }
        for prefix in ["peux tu repondre ", "can you reply ", "reponds lui ", "repond lui ", "reponds ", "repond ", "dis lui ", "reply ", "respond ", "tell them "] where words.hasPrefix(prefix) {
            return .reply(String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for prefix in ["change ", "corrige ", "modifie ", "revise ", "make it "] where words.hasPrefix(prefix) {
            return .revise(original)
        }
        return nil
    }
}

/// An edit revokes review, and an attempted send cannot become sendable again.
public struct WebConversationDraft: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case idle, awaitingIntention, preparing, reviewing, awaitingSend, sending, completed, uncertain }
    public private(set) var phase: Phase = .idle
    public private(set) var snapshot: WebConversationSnapshot?
    public private(set) var body = ""
    public private(set) var operationID = UUID()
    private var reviewedAt: Date?

    public init() {}
    @discardableResult public mutating func begin(_ snapshot: WebConversationSnapshot) -> Bool {
        guard snapshot.isValid, phase != .sending, phase != .uncertain else { return false }
        self.snapshot = snapshot; body = ""; operationID = UUID(); reviewedAt = nil; phase = .awaitingIntention; return true
    }
    public mutating func preparing() { guard snapshot != nil, ![.sending, .uncertain, .completed].contains(phase) else { return }; reviewedAt = nil; phase = .preparing }
    @discardableResult public mutating func edit(_ body: String) -> Bool {
        guard snapshot != nil, ![.sending, .uncertain, .completed].contains(phase) else { return false }
        self.body = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_001))
        operationID = UUID(); reviewedAt = nil; phase = .reviewing
        return Self.validBody(body)
    }
    @discardableResult public mutating func reviewed(at date: Date = Date()) -> Bool {
        guard phase == .reviewing, Self.validBody(body) else { return false }
        reviewedAt = date; phase = .awaitingSend; return true
    }
    @discardableResult public mutating func claimSend(current: WebConversationSnapshot, at date: Date = Date()) -> Bool {
        guard phase == .awaitingSend, current == snapshot, let reviewedAt,
              (0..<300).contains(date.timeIntervalSince(reviewedAt)) else { return false }
        self.reviewedAt = nil; phase = .sending; return true
    }
    public mutating func finish(verified: Bool) { guard phase == .sending else { return }; phase = verified ? .completed : .uncertain }
    public mutating func cancel() { if phase == .sending { phase = .uncertain; reviewedAt = nil } else if phase != .uncertain { self = Self() } }
    public static func validBody(_ text: String) -> Bool { let clean = text.trimmingCharacters(in: .whitespacesAndNewlines); return !clean.isEmpty && clean.count <= 4_000 && !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) }
}

public enum WebConversationPolicy {
    public enum Command: String, Sendable { case observe, openUnread, fill, send, verify }
    public static func supports(_ site: WebMorningSite) -> Bool { [.linkedin, .slack].contains(site) }
    public static func digest(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Every mutation binds to the observed thread, source, editor and reviewed text.
    /// Selectors are provider-specific and deliberately fail closed on an unknown layout.
    public static func script(site: WebMorningSite, command: Command = .observe,
                              snapshot: WebConversationSnapshot? = nil, reviewedBody: String = "",
                              expectedEditorText: String = "", expiresAt: Date = Date().addingTimeInterval(3)) -> String {
        guard supports(site), [.observe, .openUnread].contains(command) || (snapshot?.isValid == true && snapshot?.site == site && WebConversationDraft.validBody(reviewedBody)) else {
            return "JSON.stringify({status:'unavailable'})"
        }
        let selectors: String
        switch site {
        case .linkedin:
            selectors = #"""
            const route = location.pathname.match(/^\/messaging\/thread\/([^/]+)\/?$/);
            const roots = visibleAll(document, ['.msg-thread', '.msg-conversation-card', '.msg-s-message-list-container']).filter(e => one(e, ['.msg-form__contenteditable[contenteditable="true"]', '[contenteditable="true"][role="textbox"]']));
            const root = uniqueRoot(roots);
            const editor = root && unique(visibleAll(root, ['.msg-form__contenteditable[contenteditable="true"]', '[contenteditable="true"][role="textbox"]']));
            const recipientNode = root && uniqueLabel(root, ['.msg-thread__link-to-profile', '.msg-entity-lockup__entity-title', '.msg-overlay-bubble-header__title']);
            const me = one(document, ['.global-nav__me-photo', '[data-current-user-id]']);
            const ownAvatar = avatarID(me);
            const account = me && (me.getAttribute('data-current-user-id') || ownAvatar);
            const messageNodes = root ? visibleAll(root, ['.msg-s-message-list__event', '[data-event-urn]']) : [];
            const message = e => ({id:e.getAttribute('data-event-urn') || e.id,
              text:clean(one(e,['.msg-s-event-listitem__body','.msg-s-message-group__message-bubble'])?.innerText),
              own:e.getAttribute('data-is-self')==='true' || e.classList.contains('msg-s-message-list__event--own') ||
                Boolean(ownAvatar && avatarID(one(e.closest('.msg-s-message-group')||e,['.msg-s-message-group__profile-photo','img']))===ownAvatar)});
            const sendButtons = root ? visibleAll(root, ['button.msg-form__send-button', 'button[type="submit"]']) : [];
            const conversationID = route ? route[1] : null;
            const editorID = 'linkedin-message-editor';
            """#
        case .slack:
            selectors = #"""
            const route = location.pathname.match(/^\/client\/([^/]+)\/([^/]+)(?:\/thread\/([^/]+))?\/?$/);
            const roots = visibleAll(document, ['[data-qa="channel_view"]', '.p-workspace__primary_view', '[data-qa="thread_view"]']).filter(e => one(e, ['[data-qa="message_input"][contenteditable="true"]', '.ql-editor[contenteditable="true"]']));
            const root = uniqueRoot(roots);
            const editor = root && unique(visibleAll(root, ['[data-qa="message_input"][contenteditable="true"]', '.ql-editor[contenteditable="true"]']));
            const recipientNode = root && uniqueLabel(root, ['[data-qa="channel_name"]', '[data-qa="channel_header_title"]', '.p-view_header__channel_title']);
            const me = one(document, ['[data-current-user-id]', '[data-qa="user-menu"] [data-member-id]', '[data-qa="user-menu"]']);
            const ownAvatar = avatarID(me && one(me,['img']));
            const account = me && (me.getAttribute('data-current-user-id') || me.getAttribute('data-member-id') || me.getAttribute('data-user-id') || ownAvatar);
            const messageNodes = root ? visibleAll(root, ['[data-qa="message_container"]', '.c-message_kit__message']) : [];
            const message = e => ({id:e.getAttribute('data-ts') || e.getAttribute('data-message-id') || e.closest('[data-item-key]')?.getAttribute('data-item-key') || e.id,
              text:clean(one(e,['[data-qa="message-text"]','.c-message_kit__text'])?.innerText),
              own:e.getAttribute('data-is-self')==='true' || e.getAttribute('data-user-id')===account ||
                one(e,['[data-message-sender]'])?.getAttribute('data-message-sender')===account ||
                Boolean(ownAvatar && avatarID(one(e,['.c-avatar img','img.c-avatar__image']))===ownAvatar)});
            const sendButtons = root ? visibleAll(root, ['button[data-qa="texty_send_button"]', 'button[data-qa="send_button"]']) : [];
            const conversationID = route ? route.slice(1).filter(Boolean).join('/') : null;
            const editorID = 'slack-message-editor';
            """#
        default: return "JSON.stringify({status:'unavailable'})"
        }
        return #"""
        (() => {
          const out=x=>JSON.stringify(x), command=\#(json(command.rawValue)), expected=\#(json(snapshot)), body=\#(json(reviewedBody)), expectedEditor=\#(json(expectedEditorText));
          if (window.top!==window || location.protocol!=='https:' || !\#(site.table.javascriptPermitsHost("location.hostname")) ||
              location.port && location.port!=='443' || location.username || location.password) return out({status:'unavailable'});
          if (\#(json(WebMorningPolicy.signInPathFragments)).some(p=>(location.pathname.toLowerCase()+'/').includes(p))) return out({status:'signin'});
          if (document.querySelector('input[type="password"],input[autocomplete="one-time-code"],input[autocomplete="current-password"],input[autocomplete="new-password"]')) return out({status:'signin'});
          if (document.hidden) return out({status:'unavailable'});
          const clean=x=>String(x||'').replace(/\r\n?/g,'\n').trim();
          const visible=e=>{if(!e)return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);if(!(r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight&&r.right>0&&r.left<innerWidth&&s.visibility!=='hidden'&&s.display!=='none'&&s.opacity!=='0'))return false;if(typeof document.elementFromPoint==='function'){const hit=document.elementFromPoint(Math.max(1,Math.min(innerWidth-1,(Math.max(0,r.left)+Math.min(innerWidth,r.right))/2)),Math.max(1,Math.min(innerHeight-1,(Math.max(0,r.top)+Math.min(innerHeight,r.bottom))/2)));if(!hit||!(hit===e||e.contains(hit)))return false;}return true;};
          const visibleAll=(root,selectors)=>Array.from(new Set(selectors.flatMap(s=>Array.from(root.querySelectorAll(s))))).filter(visible);
          const one=(root,selectors)=>{for(const s of selectors){const e=root.querySelector(s);if(e)return e;}return null;};
          const avatarID=e=>{const src=e?.getAttribute('src');return src&&!/ghost|default|placeholder/i.test(src)?src.split('?')[0].replace(/shrink_\d+_\d+/g,'shrink').replace(/_\d+\.(png|jpe?g|webp)$/i,'.$1'):null;};
          const unique=list=>list.length===1?list[0]:null;
          const uniqueRoot=list=>unique(list.filter(e=>!list.some(other=>other!==e&&e.contains(other))));
          const uniqueLabel=(root,selectors)=>{const nodes=visibleAll(root,selectors),labels=new Set(nodes.map(e=>clean(e.innerText)).filter(Boolean));return labels.size===1?nodes[0]:null;};
          if (visibleAll(document,['[role="dialog"]','[aria-modal="true"]']).length) return out({status:'choice'});
          if(command==='openUnread') {
            if(Date.now()>\#(Int(expiresAt.timeIntervalSince1970*1000))) return out({status:'stale'});
            const selector=\#(json(site == .linkedin ? ".msg-conversation-listitem--unread a[href*='/messaging/thread/']" : "a[data-sidebar-link-id][data-is-unread='true'],.p-channel_sidebar__link--unread[href]"));
            const links=visibleAll(document,[selector]);
            if(!links.length) return out({status:'unavailable'});
            const link=links[0], url=new URL(link.getAttribute('href'),location.href);
            if(url.protocol!=='https:'||url.hostname!==location.hostname||url.username||url.password||url.port&&url.port!=='443'||
              !(\#(json(site.rawValue))==='linkedin' ? /^\/messaging\/thread\/[^/]+\/?$/.test(url.pathname) : /^\/client\/[^/]+\/[^/]+\/?$/.test(url.pathname))) return out({status:'unavailable'});
            link.click(); return out({status:'opened'});
          }
          \#(selectors)
          if(!conversationID||!root||!editor||!recipientNode||!account) return out({status:'unavailable'});
          const messages=messageNodes.map(message).filter(m=>m.text);
          if(messages.some(m=>!m.id||m.id.length>512||m.text.length>4000)) return out({status:'unavailable'});
          if(new Set(messages.map(m=>m.id)).size!==messages.length) return out({status:'unavailable'});
          const incoming=messages.filter(m=>!m.own), last=incoming.at(-1);
          if(!last||messages.length>200) return out({status:'unavailable'});
          const snapshot={site:\#(json(site.rawValue)),conversationID,recipient:clean(recipientNode.innerText),accountID:clean(account),messageID:last.id,messageText:last.text,editorID,outgoingMessageIDs:messages.filter(m=>m.own).map(m=>m.id)};
          const editorText=clean(editor.innerText||editor.textContent);
          if(command==='observe') return out({status:'ready',snapshot,editorText});
          if(Date.now()>\#(Int(expiresAt.timeIntervalSince1970*1000))) return out({status:'stale'});
          if(!expected||['site','conversationID','recipient','accountID','messageID','messageText','editorID'].some(k=>snapshot[k]!==expected[k])) return out({status:'stale'});
          if(command==='verify') {
            const added=messages.filter(m=>m.own&&m.text===body&&!expected.outgoingMessageIDs.includes(m.id));
            return added.length===1&&editorText==='' ? out({status:'verified',snapshot,receiptID:added[0].id}) : out({status:'unavailable'});
          }
          if(command==='fill') {
            if(editorText!==clean(expectedEditor)) return out({status:'stale'});
            editor.focus(); editor.textContent=body;
            editor.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:body}));
            return clean(editor.innerText||editor.textContent)===body ? out({status:'filled',snapshot,editorText:body}) : out({status:'unavailable'});
          }
          if(command==='send') {
            if(editorText!==body||!unique(sendButtons)||sendButtons[0].disabled||sendButtons[0].getAttribute('aria-disabled')==='true') return out({status:'stale'});
            sendButtons[0].click(); return out({status:'dispatched',snapshot});
          }
          return out({status:'unavailable'});
        })()
        """#
    }
    private static func json(_ value: some Encodable) -> String { String(decoding: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), as: UTF8.self) }
}

/// A reserved dispatch stays uncertain across view dismissal and process restart.
public struct WebConversationJournal: Sendable {
    private struct Entry: Codable, Sendable { let id: UUID; let context: String; let target: String; let fingerprint: String; var receipt: String? }
    private let file: AtomicJSONFile<[Entry]>
    public init(directory: URL) { file = AtomicJSONFile(url: directory.appendingPathComponent("browser-reply-journal.json"), maximumBytes: 524_288) }
    public func hasPending() throws -> Bool { try entries().contains { $0.receipt == nil } }
    public func pendingID(for snapshot: WebConversationSnapshot) throws -> UUID? {
        guard snapshot.isValid else { return nil }
        return try entries().first { $0.receipt == nil && $0.target == snapshot.targetKey }?.id
    }
    @discardableResult public func reserve(id: UUID, sessionID: UUID, stepID: UUID, snapshot: WebConversationSnapshot, body: String) throws -> Bool {
        var values = try entries()
        guard snapshot.isValid, WebConversationDraft.validBody(body), values.count < 1_000,
              !values.contains(where: { $0.receipt == nil || $0.id == id }) else { return false }
        values.append(Entry(id: id, context: WebConversationPolicy.digest([sessionID.uuidString, stepID.uuidString]), target: snapshot.targetKey,
            fingerprint: WebConversationPolicy.digest([snapshot.fingerprint, body]), receipt: nil))
        try file.save(values); return true
    }
    public func confirm(id: UUID, receiptID: String) throws {
        var values = try entries()
        guard !receiptID.isEmpty, receiptID.count <= 512, let index = values.firstIndex(where: { $0.id == id && $0.receipt == nil }) else { throw CocoaError(.fileReadCorruptFile) }
        values[index].receipt = WebConversationPolicy.digest([receiptID]); try file.save(values)
    }
    /// Only a refusal known to precede dispatch may release its reservation.
    public func releaseNotDispatched(id: UUID) throws {
        let values = try entries()
        guard values.contains(where: { $0.id == id && $0.receipt == nil }) else { throw CocoaError(.fileReadCorruptFile) }
        try file.save(values.filter { $0.id != id })
    }
    /// Owner attestation after checking the displayed thread, never automatic verification.
    public func reconcile(id: UUID, sent: Bool) throws {
        if sent { try confirm(id: id, receiptID: "owner-checked-" + id.uuidString) }
        else { try releaseNotDispatched(id: id) }
    }
    private func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: file.url.path) else { return [] }
        let attributes = try file.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        let values = try file.load()
        guard values.count <= 1_000, Set(values.map(\.id)).count == values.count,
              values.allSatisfy({ ([$0.context, $0.target, $0.fingerprint] + [$0.receipt].compactMap { $0 }).allSatisfy { $0.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } } }) else { throw CocoaError(.fileReadCorruptFile) }
        return values
    }
}
