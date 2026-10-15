# MORE demo requirements

Working version 1 · 15 October 2026 · Source baseline `8e25b20` · Tracking [#155](https://github.com/gibouu/morning-operator/issues/155).

MORE learns the shape of a person's morning, proposes one daily routine, and helps them move through it with less phone handling. The demo must show a complete morning on an ordinary iPhone: wake up, hear useful facts, read and prepare an email reply, enjoy a feed or article, spend time in another app, then finish with a saved result.

The wider target is a catalog of roughly 15 destinations. The first live presentation uses six routine moments, plus setup and wake-up. Every destination enters the live route only after its own real-device gate passes. This keeps the full vision while giving the team one concrete story to finish.

This is the shared demo target. Existing design and hardening branches must be reconciled against the latest main before implementation. Earlier screenshots, tethered experiments and historical setup guides do not establish current phone behavior. [Acceptance tests](DEMO-TEST-PLAN.md) define what counts as a pass.

The [planning simulation source](demo-story.html) steps through the focused story or full catalog, unavailable-source cases and expanded timer actions. Its content is synthetic and it makes no provider or phone calls. It is a rehearsal aid, not a replacement interface or runtime evidence.

## The story to show

Suggested presentation length: 5–7 minutes, with short real budgets selected and approved before the presentation. These are rehearsal budgets, never presented as learned personal averages. A normal morning can take longer.

| Scene | What the audience sees | Required behavior |
|---|---|---|
| Before the alarm | Learn from actual Screen Time; review order and minutes; finish guided connections | One daily routine is explicitly approved. Missing apps can be excluded. The normal user completes setup on the phone. |
| Wake up | A real MORE AlarmKit alarm rings on the locked iPhone | The owner uses the labeled MORE entry action, unlocks when required, and enters MORE. Stop must have clear separate behavior; current source routes both alarm buttons through the same start intent and needs reconciliation under #126. The app does not claim it can unlock the phone or silently bring itself to the foreground. |
| 1 Your day | A short spoken greeting: weather, first appointment, and optional sleep fact | Fresh sourced facts; denied, missing and stale data have distinct outcomes. Health is included only after native wiring and permission/data tests pass. |
| 2 Gmail | Open a real unread email; prepare and edit a local reply | The saved Google connection restores. The draft is editable and remains unsent. The reader identifies its actual Inbox scope. |
| 3 Instagram | Open the owner's signed-in feed in MORE; demonstrate one supported advance | The page remains visible. Any automatic advance is separately enabled, bounded and stoppable. Learned speed replay is a later gate, not current proof. |
| 4 News | Open an approved news site or saved article | The owner can read or request a sourced extract. Unsupported extraction leaves the readable website available. |
| 5 Duolingo or Chess | MORE hands off to one installed external app | A Live Activity retains the same moment and time budget. The owner expands the island, adds two minutes, then chooses Next. The handoff target needs implementation and device proof. |
| 6 Finish | Return to MORE and finish the morning | Exactly one completion is saved; the recap separates planned minutes, elapsed routine time and unavailable observations. |

The presenter says which sources are connected. “No access to WhatsApp calls” must never become “No missed calls.” An unavailable optional source can be skipped honestly; it cannot be replaced by invented live content.

## Functional requirements

| ID | Requirement and acceptance rule |
|---|---|
| R01 Setup | One guided setup checklist covers the chosen destinations. Google services may share one consent flow when their scopes are requested together. Different providers and iOS permissions still require their own consent. Each connection shows Ready, Needs sign-in, Permission needed, Unsupported or Skipped. Chosen destinations and skips persist; the present setup selection is view state and still needs durable storage. Retry resumes setup without resetting successful connections. |
| R02 Learning | Screen Time supplies coarse usage evidence; selected recordings and permitted browser activity are separate evidence sources. Show source, observed days and measured versus estimated durations. Never infer click rate or a lesson's length from aggregate app minutes alone. |
| R03 Routine | Keep one routine every day. Start with an owner-approved default order; propose habit-based changes for review. Owner order overrides learned order. New data cannot silently reorder an approved or running morning. Missing/unconfigured destinations are skipped with a reason. Unknown installation state is not proof an app is absent. |
| R04 Start | An approved unfinished routine can start later today. An existing run offers a clear resume or end/restart path. Start, approval and alarm scheduling are separate actions. See #154 for UX discovery. |
| R05 Briefing | Weather, calendar, Health and communication facts keep provider, observation time and freshness. Speak a short opening once; let the owner expand details. Empty, denied, unavailable and stale are different states. A failed provider does not block the whole morning. |
| R06 Communications | Separate email, message, missed call, voicemail and unknown. A source must support the type: an unread badge or “call me” message is not a missed-call record. Keep per-source counts separate, deduplicate stable provider IDs, and distinguish items from threads. Important contacts and urgency rules are reviewable owner choices. |
| R07 Replies | Read connected messages and prepare local editable responses. Do not send or save a provider draft in this demo. An unavailable local model leaves manual editing available. Treat message content as untrusted input; partial bodies cannot be presented as complete reply context. |
| R08 Browsing | The owner logs in directly on the provider's page. A successful login does not prove feed/inbox extraction works. A scroll or advance is user-led; optional auto-advance has an explicit start, stop and duration. Match measured pace only on supported visible pages and keep a manual override. Backgrounding stops browser actions. |
| R09 Handoff | Use reviewed universal links/URL schemes and verify each target. Do not treat an opaque Screen Time token as a launch URL. An external app stays under its owner's control; MORE does not tap inside it. A failed launch offers Retry, Skip or an approved web fallback. |
| R10 Timer and island | A single run/moment ID owns the timer in MORE, Live Activity and Lock Screen. A user action adds exactly 120 seconds once, within the current 30-extension limit; Next advances once. Rapid/delayed duplicate actions cannot extend or skip twice. An external target’s deadline survives background/interruption/relaunch; ordinary narration pauses and browser actions stop when MORE leaves the foreground. Relaunch reconciles persisted state. Live Activity refresh and background execution remain OS-controlled. The system controls island shape, presentation and unlock requirements; content follows the UX team's design. |
| R11 Completion | Timer expiry can indicate time is up, but cannot force another app into the foreground or prove a lesson is complete. Persist the actual run once. Paused, stopped, skipped and completed remain distinct. Reopening after completion cannot create a second run or repeat the greeting. |
| R12 Privacy | Learning has an explicit start/stop and visible state. Collect only selected sources. Store refresh authorization securely; keep mailbox bodies and draft text volatile. Disconnect, revoked access and Forget prevent late work restoring deleted data. No secret screen monitor or background cross-app tap logger is part of the consumer app. |

## Integration catalog

“Implemented” below describes source. Only stated owner/device outcomes are phone proof. Web routes remain conditional on sign-in, page behavior and provider rules.

| Destination | Supported direction for this product | Current state and demo gate |
|---|---|---|
| Gmail | [Read-only Gmail API](https://developers.google.com/workspace/gmail/api/auth/scopes); native MORE reader and local replies | Real sign-in, unread count and message reading owner-confirmed. Build 1518 includes saved authorization; owner reports the bundled check looks good. Generated/edited/copied reply still needs a separate observed result. #139, #149, #151. |
| Apple Mail | Open Mail for an owner-led moment | No reviewed public personal Inbox-reading adapter in this app. Mail's native compose UI does not grant Inbox access. Avoid counting the same Gmail mailbox twice. |
| Apple Calendar | EventKit reads selected device calendars | Reader exists. Check permission, selection, timezone and actual event. |
| Google Calendar | [Read-scope options](https://developers.google.com/workspace/calendar/api/auth). First use a Google calendar already synced into iOS Calendar through EventKit; direct Google API is a separate connector | Verify the selected Google calendar is present and fresh. If using the API, request minimum read scopes. Select one authoritative route per logical calendar/account; do not enable both routes for the same calendar until explicit identity reconciliation is implemented. Not yet a direct connector in MORE. |
| Instagram | [Official API scope](https://www.postman.com/meta/instagram/collection/6yqw8pt/instagram-api). Visible in-MORE website, owner sign-in, supported read/advance commands | Owner previously confirmed an unread result. Whole feed, calls and pace replay are separate acceptance checks. Personal account access must not be inferred from professional-account APIs. |
| YouTube Shorts | [Data API](https://developers.google.com/youtube/v3). Visible browser experience or a reviewed native handoff | A YouTube data API is not the user's personalized Shorts feed. Add a supported target and test page navigation, playback and advance; not current core proof. |
| WhatsApp | [Business Platform scope](https://whatsappbusiness.com/developers/developer-hub/). Owner-led app/web route; evaluate personal-client options separately | Business APIs do not authorize the owner's consumer Inbox. Personal messages/call history have no validated adapter in MORE. A browser or app opening is the initial honest fallback. |
| iMessage | [Messages framework](https://developer.apple.com/documentation/messages). Owner-led Messages handoff | No current personal message-history reader. A compose extension or tethered UI test is not an Inbox integration. |
| Telegram | [Bot scope](https://core.telegram.org/bots/faq), [TDLib client](https://core.telegram.org/tdlib/getting-started). Owner-led route first; TDLib is a separate full client/authentication project | Bot access is not access to all of the owner's conversations. Personal Inbox and missed-call coverage require their own connector and tests. |
| LinkedIn | [OIDC sign-in scope](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2). Sign in and browse visibly, if the site permits the experience | Sign in with LinkedIn supplies identity, not a general personal feed/message grant. Browser compatibility and data extraction remain unverified. |
| Messenger | [Official platform scope](https://www.postman.com/meta/messenger-platform-api/collection/iyp204x/messenger-platform-api). Owner-led app/web route | Business/Page messaging APIs are not a personal consumer Inbox or call log. |
| Snapchat | [Login Kit scope](https://developers.snap.com/snap-kit/login-kit/overview). Owner-led app route | Snap Kit login is not a personal messages/missed-calls reader. No supported target or reader proven in MORE. |
| Duolingo | Reviewed app handoff with MORE's timer | Add a safe target and test launch, return, +2 and Next. Track time in the moment, not inferred lesson completion. |
| Chess.com | Reviewed app or approved web handoff with the same timer | Same gate as Duolingo; choose one for the first live story. |
| News and regular websites | Owner-selected permitted sites in MORE; Safari learning extension later | Current browser targets are limited. Prove one article route, readable page and explicit navigation before adding a wide news catalog. |

WeatherKit and HealthKit are native data inputs rather than additional inboxes. Current-condition weather reading exists; a day outlook needs a real forecast request and freshness checks before the presenter promises today’s forecast; Health code is currently an unlinked package, and the app lacks its HealthKit entitlement/usage setup. Phone/VoIP history is a separate capability: no verified adapter currently supplies system Recents or consumer WhatsApp/Instagram/Messenger/Snapchat missed calls. If a supported visible source explicitly exposes a call record, classify only that record and retain its provenance. Otherwise show unavailable. [CallKit observation](https://developer.apple.com/documentation/callkit/cxcallobserver) is not a general historical call Inbox. Apple’s [delivered-notification API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications%28completionhandler%3A%29) covers this app’s notifications.

## Browser habit learning

Begin with an explicitly started learning session inside MORE's browser. Measure allowed page visits, active dwell time, normalized scroll distance/speed, and coarse navigation actions. Do not record passwords, typed messages, authentication pages, form contents or arbitrary full URLs. Keep a visible stop control and allow source deletion.

A Safari web extension is the next iPhone route. Request access only to chosen sites, then pass bounded observations to the containing app. A Chrome desktop extension can provide a later desktop signal; installing a Chrome extension from a phone adds it to desktop, not to iPhone browsing. Desktop-to-phone transfer needs an explicit supported design. Neither extension can observe arbitrary native apps. Private browsing is excluded from learning; the extension must prove it can identify/exclude that context before recording there. [Safari permissions](https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions), [Chrome content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts), [Chrome installation](https://support.google.com/chrome_webstore/answer/2664769).

Retain only the site's identity, coarse time window, active duration, normalized scroll observations and consent/source version needed for a reviewed routine suggestion. Repeated observations can suggest order and duration; single-session data stays provisional. Existing sparse recording samples do not establish exact tap timing or continuous scrolling speed.

## Delivery order and ownership

| Gate | Work to finish | Existing work and ownership |
|---|---|---|
| G1 Freeze the story | Choose six moments, demo device/accounts and one external app; reconcile latest merged source | This contract, #14/#139/#155. Orchestration owns scope and evidence. |
| G2 Connected opening | Verify WeatherKit and selected Calendar; wire and test optional Health; finish actual Gmail reply proof | #13, #15, #28, #139/#149/#151; durable setup #157 and source-backed communications #156. Hardening owns service behavior. |
| G3 Complete handoff | Add one Duolingo/Chess target; prove timer, locked/unlocked +2/Next, app return and completion | #16/#126 and external target #158. Hardening owns persistence/actions; UX owns presentation and late starts #154. |
| G4 Learn and browse | Prove one real Screen Time proposal and one visible browser step; add measured pace only after observation works | #30/#105/#122/#127; pace #159 and Safari/Chrome spike #160. Current Screen Time proposals cap at eight steps; another evidence proposal path caps at ten. A 15-destination catalog does not imply one learned 15-step routine. |
| G5 Rehearse | Three normal complete phone runs, including cold launch and failure recovery, then a distribution-build rehearsal | #14/#112/#139. No tethered app tapping or seeded routine counts as acceptance. |
| G6 Expand and release | Add further destinations one at a time; build the extension and review release requirements | Separate scoped issues after their feasibility gates. UI/UX changes stay in that workstream. |

Existing PR #114 is a tethered XCTest demo, not shipped cross-app control. PR #122 concerns learning and PR #123 concerns morning extras; compare them with main before reusing them. Existing local Codex sessions visible to this chat are idle; the owner's other groups may have separate work not visible here. Reserve files before parallel edits and inspect each actual branch before integration.

## App Store release gate

App Store submission is separate from a successful hackathon demo. Use public APIs and allowed background modes. Recording/logging needs consent and a visible indication. Health access needs a clear health purpose. Confirm distribution entitlements, current supported SDK, privacy disclosures, deletion behavior, accessible controls, reviewer access and functioning services. Recheck provider authorization and Google production/verification requirements before public users connect. Do not ship tethered test control or describe unavailable personal Inbox access as supported. Apple's review decides approval. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Progress baseline

Main includes the unified visual/navigation work and Gmail implementation through PR #150. Ordinary build 1518 is installed. Real Screen Time suggestion approval and Gmail reading are owner-confirmed. The full reader/persistence source reported 1,269 local package tests with six optional model/media skips; the integrated learned-Gmail route passed 32 focused checks. Native app/widget signing passed. These results do not establish alarm ringing, on-device reply generation, connected Health, external-game handoff or a completed morning. Those are the next physical gates, not completed features.
