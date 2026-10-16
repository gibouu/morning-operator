# MORE's in-app browser

Checked 15 October 2026. This is a built prototype, not an App Store approval or a verified integration with these services.

## Inline sign-in and browser replies — 16 October 2026

LinkedIn and Slack are ordinary browser destinations, independent of the remote API catalogue. The routine and learning open their websites directly. Website sign-ins share the existing dedicated persistent WebKit store; they remain available until the provider expires or revokes them, or the owner clears website data. No cookie values or credentials are exported. LinkedIn and Slack HTTPS links are reloaded through the visible WebKit view so app links do not hand the routine to a native app; their authentication form requests retain their original body without replay. This is not a promise that every identity provider accepts an embedded browser. Supported APIs remain optional alternatives.

A routine that encounters sign-in pauses its saved budget, asks the owner to sign in on the visible page, and resumes that same moment when a supported content layout is observed. Closing, backgrounding or explicitly pausing revokes automatic resumption. No separate account-setup checklist is required.

LinkedIn and Slack message moments can open the first visible unread conversation when its recognized link is available, read the visible conversation and offer a reply. The owner supplies an intention, reviews or edits the draft and separately instructs Send. The selected language model prepares text only; website content never authorizes execution. Unsupported layouts, missing account identity, multiple editors, changed conversation/source, pre-existing user text and sign-in/consent pages fail closed. Replies remain scoped to the observed account, recipient, thread, source message, editor and reviewed body.

Before clicking Send, MORE persists only opaque digests and an operation identity in `browser-reply-journal.json`. Confirmation requires a new, uniquely identified outgoing message with the exact reviewed text, a recognized sent state or server permalink, no pending/error marker, and an empty composer. A click alone is not a receipt. An uncertain send stays reserved across restarts and is never automatically retried; the visible conversation offers explicit owner reconciliation. Full Forget removes this journal. Raw message and draft text stay in memory and are cleared on navigation, close/background and privacy reset.

Package/script checks use synthetic DOM inputs. Simulator UI and unsigned builds are separate evidence. Real LinkedIn/Slack sign-in, actual provider layouts, selected-model drafting, audible interruption and real message receipts require an authorized account/device acceptance run; none is established by these fixtures. Track physical acceptance in [#251](https://github.com/gibouu/morning-operator/issues/251).

### Local verification — 16 October 2026

- Shared/browser regression selection: 172 tests passed, including conversation identity, reviewed-send expiry, duplicate-effect reservations, receipt rejection, navigation containment and saved-routine routing. Script checks: 57 passed; localization audit: no missing French keys.
- Two simulator UI journeys passed on iPhone 17 / iOS 26.5: automatic LinkedIn and Slack moments open their public sign-in page directly and pause the routine; services and first-use guidance remain available in French and English without changing a saved personal title. Screenshots were inspected. No account was signed in and no real message was sent.
- The full package run completed with 2,188 passes, 16 skips and two native Vision OCR timeouts in unchanged tests (`MediaObservationLayoutTests.nativeTextAndBoundsFromSyntheticImage` and `MorningAppleTests.realVisionOCRFromSyntheticScreenshot`). The suite is not fully green; the OCR failures are tracked in [#244](https://github.com/gibouu/morning-operator/issues/244).
- Replies implemented here are specific to LinkedIn and Slack. Other websites can keep their browser session, but supported actions still depend on a recognized service/layout. Further communication adapters are tracked in [#257](https://github.com/gibouu/morning-operator/issues/257).

## Routine execution revision — 15 October 2026

Reviewed routine moments now have session-scoped feed, video, story, headline or unread-information behaviors, automatic progression and optional explicitly reviewed likes. The driver observes before/after actions, stops for sign-in or privacy/subscription choices, and journals uncertain likes before any retry. Previously saved web moments remain manual until edited. Closing an automated page pauses its session. [Execution contract and evidence boundaries](ROUTINE-AUTOMATION.md).

The descriptions and phone evidence below refer to the earlier standalone/manual tools; they do not establish the new autonomous service behavior.

## Instagram navigation fix — 16 October 2026

Instagram routine moments now stay in MORE, including saved native-app choices and Safari choices pointing to supported Instagram hosts. Valid saved usernames keep their profile destination. This resolves the execution route without rewriting the saved routine or granting browser actions to an old manual moment. The timer, Next, and page reopening use that same route. The editor offers Instagram under **In MORE**.

The Instagram browser cancels web-initiated HTTPS GET navigation in that browser before WebKit can try a universal link, then loads the request through the public `WKWebView.load` API. The next programmatic callback is allowed once; redirected URLs are checked again. New-window links use the visible browser. Known `instagram://app` and username links have HTTPS equivalents; unknown app actions are refused. Instagram link previews are disabled to avoid their separate native-app handoff. Same-host sign-in POSTs retain their requests. A cross-host non-GET form is refused without replaying its potentially unavailable credential body; this limits such sign-in flows inside the Instagram browser. HTTPS providers and app-store redirect hosts stay in the same browser. Other services' native and system-browser OAuth flows keep their existing consent routes.

Regression coverage includes saved routine progression, profile details, unchanged saved authority, timer destinations, redirects, new windows, deep links, and French/English destination labels. A UI journey starts, advances and reopens saved Instagram moments in both app languages without signing into an account. Local verification results and remaining runtime/device limits are recorded in issue #234 and its PR. This change does not establish live account or feed behavior.

## Manual browsing mode

The person sees the website and signs in on its own page. One tap asks MORE to read a visible unread number, show up to five headlines, or request one video-feed scroll. This standalone mode does not automatically advance. Approved routine moments use the execution path described above. The website's own buttons still work when the person uses them.

The standalone reading scripts never click, type, submit, read credential values or send network requests. The routine driver additionally performs only the reviewed browser operations. Known login, consent and recovery URLs are blocked before any script. Each script checks its HTTPS origin again, then checks only whether a credential field exists; an inline login form returns `unsupported` before page content is read. No DOM dumps, message bodies, account screenshots, full URLs or unknown hostnames enter MORE's logs. Results stay in memory while the screen is open. Headline text is displayed locally; logs record only its count.

The browser uses a dedicated persistent WebKit data store. The site can keep its sign-in there between launches. **Clear all website sign-ins** removes that store's website data. This does not revoke a linked device on the service's server; use that service's device settings too. `Library/WebKit` and `Library/Cookies` are marked excluded from backup on a best-effort basis. WebKit controls its storage layout: backup/restore exclusion is **unverified**, so do not promise that sessions cannot enter backups.

Routine callers must use Plan B's `RoutineStep.target`, saved `StepTimer.endsAt`, pause instant, extension and Next callbacks. Opening or closing the browser must not create a fresh routine timer. The debug-only `--web-morning --web-morning-site=news` launch opens a standalone ten-minute screen. It still requires taps for every action.

## Evidence so far

| Site | Implemented action | Phone evidence |
|---|---|---|
| Instagram | Visible DM badge; one feed scroll | Owner signed in inside MORE QA and confirmed MORE's unread report matched an actual unread message. No exact count or account content was captured. Feed scroll remains untested. A missing numeric badge reports unsupported, not zero. |
| YouTube | One Shorts feed scroll | Not tested. A scroll request is not proof that another video plays. |
| Le Monde | Up to five matching headline titles | iPhone WKWebView loaded the site's consent/subscription choice. Timer extension, close/reopen and Next passed in a synthetic routine. No consent choice or headline extraction was performed. |
| WhatsApp | Visible unread markers inside the chat list; desktop user agent | Not tested. No claim that iPhone WKWebView loads or links successfully. Zero markers report unsupported. |
| Gmail | Native metadata API reader replaces title scraping and embedded sign-in; saved Gmail moments open that reader. | Client configuration is absent and live Google consent/read is unverified. See [connection evidence](CONNECTION-EVIDENCE.md). Opening Mail or marking a website ready is not inbox access. |

Core policy/parser/script tests and an unsigned generic iOS app build run on the Mac. A signed, separate MORE QA bundle passed the shared routine/timer phone journey described above. Instagram sign-in and one matching unread result are owner-confirmed; other account flows, count accuracy across layouts and video progression remain unverified. The newer simulator runs are recorded separately in the execution report.

## Login and service rules

Being in control reduces the risk of unwanted actions. A user tap does not itself grant third-party permission for programmatic access. The following risk judgments are engineering judgments, not approval decisions.

- **Apple:** [5.2.2 “Third-Party Sites/Services”](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) requires permission under the service's terms, and evidence on request. [4.2 “Minimum Functionality”](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality) requires useful native features beyond a repackaged website. MORE's native routine and timer help explain its utility; they do not guarantee approval.
- **Instagram: high unresolved risk for a shipped scripted integration.** The official [Terms of Use](https://help.instagram.com/581066165581870) and [Meta Automated Data Collection Terms](https://www.facebook.com/legal/automated_data_collection_terms) could not be read in this check: the endpoints returned errors, a login page or a block page. No current clause is quoted or asserted as verified. Obtain the current terms and permission before shipping the reader. Do not call this approved based on human login alone.
- **YouTube: high unresolved risk for programmatic feed control.** [“Permissions and Restrictions”](https://www.youtube.com/static?template=terms) limits automated access except for stated exceptions or prior written permission. Do not bypass a challenge, restriction or sign-in block. A supported player/API route needs a separate review for this use.
- **WhatsApp: high unresolved risk for a shipped reader.** [“Harm To WhatsApp Or Our Users”](https://www.whatsapp.com/legal/terms-of-service-eea) restricts unauthorized access and information collection. It is not a blanket ban on ordinary human browsing, nor evidence of permission for MORE's reader. Its [linked-device guidance](https://faq.whatsapp.com/378279804439436) describes QR or phone-number linking; [supported browsers](https://faq.whatsapp.com/803865374003522) does not prove support for our embedded iPhone view. The owner performs pairing and any 2FA; MORE never extracts QR or verification data.
- **Gmail: poor embedded-login candidate.** Google's [“Use secure browsers” OAuth policy](https://developers.google.com/identity/protocols/oauth2/policies#use_secure_browsers) prohibits directing Google OAuth requests to developer-controlled embedded user agents. This source is a policy, not a phone observation of Gmail's particular web-login error. No user-agent trick is used for Google.
- **Le Monde: unresolved content permission.** [“Rules for Website and/or Application Use”](https://www.lemonde.fr/en/cgv-en/) restricts collection/distribution and crawling or mass collection without prior consent. Five transient local headlines are a narrower use, but permission is not established. No article body or paywall bypass is implemented.

## Demo and release recommendation

For a reliable hackathon demo, first prove the native timer plus a page you control, with synthetic headlines and video. Then test one public service at a time without promising success. Keep social account login with the owner and record only outcomes/counts. Do not publish account media or bypass site controls.

For an App Store release, the native morning guide is the foundation. Use permitted feeds/APIs and supported authentication for extracted data. Ship a service-specific browser reader only after current terms, service permission and real device behavior are checked.

Selectors live in one table per site. Missing roots, credential forms, unknown origins, invalid results and scroll boundaries fail closed. DOM changes, locale, virtualization and experiments can still make counts incomplete or wrong. Keep a manual website route and repeat a small owner-run smoke check after selector changes. A successful scroll request never reports an invented number of videos watched.
