# Connection acceptance — 16 October 2026

This ledger distinguishes the live MORE backend, provider access and the ordinary
iPhone journey. A successful catalog or consent-link response is not a completed
user connection. No private account content, bearer, authorization URL, provider
identifier or credentials are included here.

## Resumed ordinary iPhone acceptance — delivery checkpoint

The ordinary installed build is now **2026101622**, with a strict signature and
HealthKit, WeatherKit, Family Controls and App and Website Usage entitlements
verified independently. It is an in-place Debug installation, using the approved
developer entry. It is not a StoreKit or TestFlight acceptance result.

| Ordinary iPhone route | Resumed evidence |
| --- | --- |
| Reminders | Physical test08 passed in 13.518 seconds: a fresh local-read timestamp and no app-owned read error. No reminder was created or completed; no titles or counts were exported. |
| Calendar | Physical test07 passed in 64.874 seconds after targeting the actual switch thumb: real inventory, a selected-calendar fresh read, local timestamp, no read error and temporary-selection cleanup. The previous row-center gesture failed after its 10-second wait. |
| Native Gmail, Health and Screen Time | Real grant/read acceptance remains pending. No permission or sample result is injected. |
| Remaining API connections | Real consent must reconcile through this installation before ACTIVE status or provider reads can count. Catalog availability does not satisfy this gate. |
| Full routine | A physical ordinary-UI journey is prepared for real browser learning, an explicit selected model, review/approval, automatic execution and a persisted recap. Model setup and the full journey were not run before the owner stopped further testing for delivery. |
| Natural voice | Four ordinary samples completed through Apple backup. All four primary-voice assertions failed. The owner heard the samples and rejected their quality. ElevenLabs playback remains unproved. |

The installation's UI now exposes an explicit support code derived from its
existing private credential, without exporting that credential or enrolling a
replacement installation. A private parameterized lookup found exactly one
existing installation. Only this previously identified installation was added to the voice allowlist
(one entry became two; the original entry was preserved). Worker deployment
`35e47ab2-2e67-4c75-8787-2eb51b20ca52` retained the canonical speech source,
16 services, three secrets and existing database bindings. No provider account
ownership was changed. Health returned 200, unauthenticated voice requests 401,
forbidden voice/agent overrides 400 and authenticated service inventory 200,
all with `no-store`. These guard checks made no generation call and do not yet
prove native speech playback on this installation.

A later test12 passed in 22.012 seconds and returned a different support code.
Private D1 correlation found three distinct installations: the previously
activated one, the installation refused during the TTS matrix at 08:20:33 UTC,
and the current test12 installation. The latter two are not on the allowlist.
The server configuration was unchanged. The client namespace includes its
absolute sandbox path; the precise path transition was not captured, so a
container replacement is a supported hypothesis rather than a measured event.
No additional installation was activated and no provider ownership was moved.

The delivered client fix pins the existing non-secret Keychain namespace in
`composio-keychain-namespace.json`. Both the credential and pending-execution
journal keep their original Keychain accounts. Each access checks the pin;
an absent file is recreated with the same captured namespace, and a damaged or
contradictory file blocks access. Injected stores and explicit UI-test/data
directory overrides retain their existing isolation. No credentials or journal
entries are copied, and no historical namespace is searched. A namespace already
lost before this first pin cannot be recovered by this change; one final
reconnection or server activation may still be needed. First-upgrade continuity
remains tracked in [issue #220](https://github.com/gibouu/morning-operator/issues/220).
This final patch was reviewed in source but was not rebuilt or retested after
the owner's instruction to stop tests and deliver.

Both native and API authentication now permit the standard shared sign-in
session while retaining their callback and ownership checks; native Google also
retains its existing PKCE/state validation. New
physical-only opt-ins exercise real provider consent and explicit model setup;
they never inject app workspaces, model output or system grants. The resumed
targeted shared checks passed **29/29**, and resource/Python checks passed
**34/34**. Raw device results, credentials and owner-state backups remain local
and ignored. The earlier detailed checkpoints below retain their original proof
boundaries; this resumed work does not yet certify every connection or the full
routine.

The owner unlocked the iPhone and the Calendar/code checks above completed.
Further tests and the full routine were then stopped on the owner's delivery
instruction. The phone and owner data are released without a pending routine
mutation or restoration. Final installation is handled by the delivery
coordinator; there is no StoreKit/TestFlight acceptance dependency.

## Live API checkpoint

The deployed origin is `https://more-composio.more-gderamchi.workers.dev`.
The existing isolated QA installation authenticated successfully: `/health`,
`/v1/services` and `/v1/connections` returned HTTP 200. Its connection list was
empty. This bearer is separate from any ordinary iPhone installation.

All 16 deployed catalogs returned HTTP 200. Their 1,152 tool definitions each
contained a tool slug and normalized object input schema. This checks catalog
availability and basic schema shape, not all semantic arguments or provider
operations.

| Service | Catalog tools | ACTIVE accounts in the actual MORE project |
| --- | ---: | ---: |
| Gmail | 61 | 1 |
| Google Calendar | 47 | 0 |
| Outlook | 306 | 0 |
| Google Drive | 92 | 0 |
| Google Docs | 46 | 0 |
| Google Sheets | 50 | 0 |
| Notion | 57 | 0 |
| Slack | 161 | 0 |
| Calendly | 53 | 0 |
| Instagram | 32 | 0 |
| WhatsApp | 58 | 0 |
| LinkedIn | 25 | 0 |
| Discord | 23 | 0 |
| Facebook | 49 | 0 |
| YouTube | 59 | 0 |
| Reddit | 33 | 0 |

These counts came from complete, unpaginated-final project account and auth-config
responses. All 16 exact configured auth configurations existed, were ENABLED and
used managed OAuth2. No account belonging to an unrelated chat connector was
used as evidence.

### Actual Gmail provider read

The single active Gmail account belonged to a generated MORE installation
identity, but not the locally recoverable isolated QA bearer. Without changing
ownership or server storage, an explicitly account-bound, version-pinned
`GMAIL_GET_PROFILE` was executed using the actual MORE project API key.
HTTP 200, `successful:true`, an email-address field containing `@` and a numeric
message-count field were verified in memory. The address and counts were not printed or
retained in this report. No mailbox messages were read and no email was sent in
this initial profile-only checkpoint. The subsequent self-send is recorded below.

A subsequent read-only, parameterized production D1 query found exactly one
installation row for that account's existing owner. The account is therefore
associated with an installation in the current deployed database; its private
bearer was not recovered or replaced by this test.

This establishes actual Gmail provider access under the MORE project. It does
**not** establish execution through an authenticated MORE installation, completion
of the app's OAuth callback, a spoken operation or a physical iPhone journey.

### Actual Gmail self-send and readback

One administrator-level provider test was explicitly authorized using the actual
MORE project's existing active Gmail account. The current pinned schemas for
profile, send, search and message reading were fetched and inspected first.
A fresh profile supplied the only permitted recipient: that same connected
account. A random UUID identified the one local test record and the unique
`MORE-QA-COMPOSIO-20261016-…` subject; the fixed test body contained no private data.
The send payload set From and To to that exact profile address, supplied empty
CC/BCC/additional-recipient arrays, and included no attachment.

| Check | Live result |
| --- | --- |
| Unique-marker search before sending | HTTP 200; zero matching messages; no further page |
| Single send dispatch | HTTP 200; `successful:true`; provider message ID and SENT label present |
| Fresh unique-marker search | HTTP 200; exactly one matching message; no further page |
| Full readback of that provider message | HTTP 200; exact subject/body, From=self, To=only self, no CC/BCC/attachments, SENT label and send-receipt ID match |

There was exactly **one send dispatch**, no retry and no deletion or trash action.
The private local ledger was reserved exclusively before preparation and retained
the request UUID, address, body, provider identifiers and results outside Git in a
mode-0600 file. Composio's direct execution contract exposes no request-id or
idempotency field; this UUID identifies the local test, not provider deduplication.
Any uncertain response would require read-only reconciliation before another
action. [Direct execution contract](https://docs.composio.dev/reference/api-reference/tools/postToolsExecuteByToolSlug).

This is a verified **provider administrator self-send** through the actual MORE
project. It bypasses the app installation bearer and MORE's execution journal,
so it does not certify the ordinary iPhone, spoken send, native Gmail route or
user-bound Worker send journey.

A separate request to the ordinary deployed Worker attempted only
`GMAIL_GET_PROFILE` for this account with the unrelated isolated QA installation's
valid bearer. It returned **HTTP 404 `connection_not_found`**, correctly refusing
cross-installation ownership. No database identity or account ownership was
modified to bypass that boundary.

### Consent initiation for the 15 missing providers

A fresh isolated QA installation was created through the ordinary deployed
`POST /v1/installations` route, returning HTTP 201. It authenticated normally.
For each service other than Gmail, `POST /v1/connections` with this deployment's
exact native callback returned HTTP 201 and an HTTPS authorization link.
The authenticated connection list then contained 15 `INITIALIZING` accounts,
and zero `ACTIVE` accounts. Those are unfinished consent sessions, not grants.
An authenticated read roughly sixteen minutes later returned 15 `EXPIRED`
accounts and still zero active grants. The prepared authorization links are
therefore expired and must not be presented as currently usable.

No provider consent page was opened, grant completed, scope expanded or account
ownership changed during this checkpoint. The test installation's private bearer
and short-lived links remain outside Git. A consent initiated for this test
identity cannot be completed with a different iPhone installation's Keychain
bearer. For app acceptance, start each connection inside the ordinary app and
finish its same-installation authenticated completion.

## Selected model and cloud conversation checkpoint

The following additional checks ran at 04:03–04:06 UTC on 16 October against the
new model/conversation implementation inspected at `origin/main` `4bd789f`.
They used the owner's existing MORE provider credentials and only fixed
synthetic text. No real mail, Health information, screen recording, microphone
audio or other owner context was uploaded. No provider settings, grants,
subscriptions, voice allowlist or production deployment were changed.

### Live Worker voice authorization

| Request to `POST /v1/voice/token` | Live result |
| --- | --- |
| No installation bearer, empty object | HTTP 401 `unauthorized` |
| Existing QA bearer with a client-selected agent field | HTTP 400 `unexpected_field` |
| Existing isolated Composio QA bearer, empty object | HTTP 503 `voice_not_configured` |
| This task's separate isolated QA bearer, empty object | HTTP 503 `voice_not_configured` |

Every response had `Cache-Control: no-store`; no conversation token was returned.
These two QA identities are not activated for cloud voice. Their 503 responses
establish that the installation gate refuses them; they do **not** establish a
global ElevenLabs failure. The earlier activated-QA token proof in
[the broker runbook](../Services/Composio/CLOUDFLARE.md#broker-evidence-16-october-2026)
belongs to a different test identity. This checkpoint did not add either of these
identities to the allowlist or try to bypass activation.

### Fresh OpenAI synthetic generation

A single Responses request used the exact source pin
`gpt-5-mini-2025-08-07`, minimal reasoning, a strict one-field JSON Schema,
bounded output and `store:false`. It returned HTTP 200, `completed`, the exact
requested model, the expected synthetic JSON result and `store:false` in the
response. Observed latency was **2.405 seconds**, with **66 input / 30 output
tokens**. There was no retry, external tool or owner data in the request.

This proves current model access and the small strict-output contract. It does
not repeat the broader live routine/memory tests in [INTELLIGENCE.md](INTELLIGENCE.md)
or prove app Keychain selection, microphone recognition or a real morning.
Official OpenAI documentation schedules this exact snapshot's API removal for
**11 December 2026**. [Migration issue #206](https://github.com/gibouu/morning-operator/issues/206)
tracks replacement evaluation, privacy/schema/no-fallback checks and delivery;
no model pin was changed in this audit.
[Official deprecation notice](https://developers.openai.com/api/docs/deprecations#2026-06-11-gpt-5-and-o3-model-deprecations).

### Fresh ElevenLabs configuration and generated audio

Authenticated read-only provider discovery found exactly one MORE agent matching
the repository template's exact name and tag. Its retrieved configuration had:

- Gemini 3.5 Flash, Eleven v4 Turbo and the source-selected voice;
- authentication required, Zero Retention Mode enabled, voice recording disabled
  and LLM cascading disabled;
- exactly `more_control`, `more_request` and `more_narration_complete` as client
  tools, with no external action tools.

These are provider configuration values, not an independent guarantee about
every system log or subprocessor. No configuration was modified.

One bounded provider conversation then used a private signed WebSocket URL and
an approved narration containing fixed synthetic French text. It produced
**11 PCM chunks / 143,360 bytes** in `pcm_16000` format; the first audio arrived
**1.501 seconds** after connection. The exact synthetic narration-completion
tool was observed and answered without any app effect. The connection closed
cleanly with code 1000 after **6.175 seconds**. No owner audio was captured or
uploaded, and no action tool was given live effect authority.

This proves fresh real-provider generated audio and a synthetic client-tool
round trip. It used the provider's administrative WebSocket route, while the
ordinary iOS app uses its separately gated Worker WebRTC token and Swift SDK.
It therefore does **not** prove native LiveKit playback, audible quality,
microphone transcription, interruption/audio drain, consent UI, subscription
access or a real iPhone conversation. Identifiers, signed URLs, tokens, raw
events and synthetic audio remain outside Git in private mode-0600 files.

## Remaining live gates

Scope clarification from the owner, 16 October: this acceptance concerns the
directly installed development prototype using the approved Debug developer
entry (MORE §8). Apple subscription, App Store Connect and TestFlight validation
are future distribution work in [#191](https://github.com/gibouu/morning-operator/issues/191),
not blockers for the functional service journeys below. No Apple-account sign-in
is requested for the current prototype tests.

- Recover the legitimate owning installation journey for the existing Composio
  Gmail account, or initiate a fresh Gmail grant from the actual ordinary app.
  Never rewrite account ownership or D1 identity to make a test pass.
- Complete the intended user's OAuth grant for each of the other 15 services.
  Google/Slack/Microsoft/Notion workspace policies and professional Meta account
  eligibility still constrain the available accounts and scopes.
- Execute a useful bounded read against every granted account and compare the
  real result to the app's presentation. For writes, use a uniquely identified,
  self-owned QA artifact with provider readback and stable request identity.
- Verify the ordinary app's native, browser and spoken journeys separately.
  Project API reads and synthetic test receipts cannot close those gates.

The operator's authorization to pay for API calls does not supply missing user
OAuth grants or eligible provider accounts. No paid plan, subscription, provider
developer application or billing setting was changed by this API checkpoint.

## Ordinary physical iPhone checkpoint

The current app and UI-test runner compiled and signed successfully for the
physical iPhone. The ordinary `com.gibouu.morningoperator` application was installed
without uninstalling or resetting data. Its signed HealthKit, WeatherKit, Family
Controls and App and Website Usage entitlements were checked, together with its
configured Google client and deployed backend origin. This verifies build and
configuration, not the individual services' runtime permission or data access.

The new physical-only `OrdinaryConnectionsAcceptanceTests` requires the explicit
runner opt-in `MORE_PHYSICAL_CONNECTIONS_ACCEPTANCE=1`. It terminates and launches
the ordinary app with empty app arguments and environment, without a test
workspace, StoreKit fixture or injected subscription. The launch guard was also
reviewed independently. Simulator and ordinary CI runs skip this opt-in suite.

Four actual phone runs reached the normal subscription screen, including
combined-source signed builds **1702** and **1703** after integrating `origin/main`
`fe19a40`. In that fresh-launch run, the configured StoreKit offer did not expose
`paywall.price` after 45 seconds; the app's accessibility state displayed the
App Store unavailable notice and its Try again control. The result was **one
failed live-offer check and one skipped native Gmail check**, not a passing
physical acceptance run. The other runs had the same outcome. A screenshot from
the first run captured an unrelated system permission overlay and is not used
as paywall evidence; the ordinary app's accessibility hierarchy establishes the
observed state. The final build-1702 screenshot was separately inspected and
does show the ordinary MORE paywall and App Store unavailable notice.

No purchase, restore, injected subscription or permission grant was performed in
those runs. The paywall prevented downstream service acceptance at that checkpoint.
Main `4bd789f` subsequently introduced the product-approved Debug developer entry
described in MORE §8. The physical suite now distinguishes its explicit UI button
from StoreKit proof and supports opting into that route through
`MORE_PHYSICAL_DEVELOPER_ACCESS=1`. It still uses ordinary app storage and no
fixture or system-grant injection. Release purchase, restore and eligibility
remain separate gates.

App Store Connect's apps page redirected to a signed-out login form. Existing
local credentials did not establish API access. An existing passkey
reached macOS Touch ID; no authenticated App Store Connect session was obtained.
The observed failure
does not by itself establish whether the cause is product configuration, account
state or Apple availability. [Issue #191](https://github.com/gibouu/morning-operator/issues/191)
tracks that future distribution gate. The owner subsequently clarified the
direct-install prototype scope: this investigation is deferred and does not
block functional tests through the approved Debug entry. No Apple account,
agreement or billing settings were changed.

### Ordinary Debug service checkpoint

The final task binary **0.1.0 (2026101608)** built successfully, passed strict
app/widget signature verification and was installed in place. Its four native
capabilities were verified again. The physical suite selected the actual Debug
developer-entry button, then opened normal Home → Settings → Apps & accounts.
No test workspace, provider fixture, StoreKit transaction or system grant was
injected. This entry persisted across fresh ordinary launches.

| Ordinary physical check | Observed result |
| --- | --- |
| Saved native Gmail restoration | Skipped after 67.756 seconds: the screen exposed Connect Gmail, with no saved native grant or error. No Google consent was initiated. |
| Existing Calendar inventory | Skipped after 33.936 seconds: no readable inventory was obtained; no permission or calendar selection changed. |
| Existing Reminders read | Skipped after 11.250 seconds: the actual CTA required permission; no permission was requested or reminder completed. |
| Existing current-location Weather | Failed after 31.453 seconds: Home explicitly required location access or a chosen city. This installation had no admitted weather source. |

The initial Calendar/Reminders attempts failed before reaching either service
because a single Home landscape tap did not expose Settings. A bounded helper
now observes the auto-hiding controls after each attempt; both destinations
became reachable and reported the skipped preconditions above. Production Home
code was unchanged. The first physical selection therefore remains **three
failures / one skip**; its two-case navigation retry is **two skips / zero
failures**, not two successful provider reads. Real Health data, native/spoken
Gmail sending and an ordinary cloud conversation remain unaccepted.

### Real public-city Maps and Weather journey

A separate ordinary physical test on build **2026101608** passed **1/1**, zero
failures or skips, in **117.598 seconds** (122.535 elapsed). It read the actual
weather picker, confirmed no existing resolved or hidden fallback city, selected
Choose a city and searched Apple Maps for the fixed public query `Paris, France`.
It selected the real matching result, then observed an admitted native Apple
Weather snapshot with the `weather.sources` attribution link, a measured wind
value and no synthetic/error marker. No fixture coordinates, provider response,
GPS permission or personal source was substituted.

The initial attempt stopped before mutation because the picker exposed its
selection through child text rather than its value. The test now requires one
unambiguous known label/value/child selection; ambiguity fails without changing
the setting. That initial failure is retained as test-selector evidence, not a
WeatherKit failure.

Deferred cleanup tapped the temporary city's **Remove weather** control,
verified the city disappeared, restored the exact original **Current location**
picker selection and closed the sheet. Those assertions passed. No system grant
was requested. The original current-location source remains unconfigured; this
proves a real chosen-city Maps → WeatherKit → ordinary MORE presentation, not
personal GPS weather, a full forecast, Health reading or spoken advice.

### Ordinary iPhone → Worker discovery

The ordinary physical app then passed **1/1**, zero failures or skips, in
**26.960 seconds** (31.183 elapsed): Home → Settings → Apps & accounts → Notion.
It displayed the successful **Refresh my accounts** label, the fresh empty
Notion account state, the configured Connect Notion action and no error notice.
The test did not tap Connect or start provider authorization.

These positive UI states require `APIConnectionsView.hasLoaded`, initially false
and assigned true only after both `services()` and `connections()` succeed.
The ordinary client uses an ephemeral session with URL caching disabled and
authenticates these requests using its Keychain installation bearer. No fixture,
administrator credential or substituted installation was used. The signed app's
actual Worker origin and Google public configuration were checked again.

This proves **ordinary iPhone → authenticated Worker service/account inventory**.
It does not prove Notion consent, a tool-catalog read, provider execution, an
existing Gmail grant's ownership by this installation or OAuth completion. The
first attempt failed before reaching Notion because a Settings navigation tap
did not leave Settings; the source UI hierarchy confirmed that state. A bounded,
observed navigation retry fixed the test helper, without production changes.

### Final combined physical check

After integrating main `5f33adb`, the clock correction and cleanup hardening,
source `35c4d36` passed a fresh signed physical **build-for-testing**. Ordinary
MORE build **2026101611** was installed in place. Strict app/widget signatures,
all four signed capability entitlements and actual public Google/Worker
configuration passed verification. No uninstall, grant injection or test
workspace was used.

The two ordinary physical journeys passed again, **2/2**, zero failures/skips,
in 132.588 test seconds (135.422 elapsed): public-city Weather **111.511 seconds**,
ordinary Worker inventory **21.077 seconds**. The strengthened weather cleanup
positively verifies empty city-search UI while **Choose a city** remains selected
before restoring the exact original source; a failed cleanup leaves the state
visible for reconciliation. The public city was removed and the original source
was restored in this final run.

A separate ordinary launch then succeeded, the process was still running on a
fresh device inventory, and the installed bundle version was confirmed as
**2026101611**. These fresh passes retain all provider and permission limits
above; they establish neither new OAuth grants nor a subscription transaction.

## Delivery check

The behavior fix gives professional connections independent rows. Extras now
accept an injectable clock with the same continuous-clock production default;
the concurrent-success Worker deadline change affects synthetic fixtures only.
Exact English source entries were restored without changing existing French strings.
Local builds, targeted runtime tests, live provider calls and their failures/skips
are recorded separately above. [PR #207](https://github.com/gibouu/morning-operator/pull/207)
was merged at `a94cdf3`; the later physical Weather and Worker acceptance additions
and deterministic deadline regression are tracked in
[PR #210](https://github.com/gibouu/morning-operator/pull/210). GitHub reports main
as unprotected; no admin bypass is used.

The CI package job at that merged head actually failed:
[`aHangingSourceIsSilentAfterTheDeadline`](https://github.com/gibouu/morning-operator/actions/runs/38850390646/job/116810090322)
returned after 26.901 seconds against a 20-second wall-clock assertion. The test's
source deadline is only 50 ms, but parallel Apple tests share the main actor and
held multiple checks for 23–27 seconds. This is a failed CI check, separate from
the two local Vision failures. The app-build job was still queued at inspection;
CI is not claimed green.

## Synthetic backend regression

[#196](https://github.com/gibouu/morning-operator/issues/196) was traced to the
test fixture's shared 100 ms provider deadline. The two successful cross-isolate
checks hold the first provider response until a second Worker/D1 request finishes;
that coordination can exceed 100 ms. Holding the response for 150 ms with the old
deadline reproduced both failures exactly: the original Gmail and Slack requests
returned HTTP 409 `execution_uncertain` instead of HTTP 200. This was correct
timeout handling under an incorrectly short success-test deadline.

[Commit 12d8768](https://github.com/gibouu/morning-operator/commit/12d8768) gives
ordinary success fixtures 2,000 ms, keeps explicit 100 ms deadlines in both
deliberate timeout cases, and retains the 150 ms overlap in the concurrent tests.
Production deadlines, duplicate-dispatch guards and durable receipt assertions
were not changed.

On Node 25.6.1 after `npm ci --ignore-scripts --no-audit --no-fund`, the four
affected Worker checks passed **4/4**. The first complete `npm test` passed
**38/38**, with zero failures or skips, in 58.60 seconds under concurrent Mac load.
Every upstream request in these checks was intercepted by a synthetic provider;
they prove Worker/D1 timeout, concurrency and receipt behavior, not real account
access, provider effects or the ordinary iPhone journey.

After integrating main `4bd789f`, the complete suite passed **44/44**, zero
failures or skips, in 5.37 test seconds (5.57 seconds elapsed). This includes the
new voice-token contract checks while retaining both deliberate timeouts and
cross-isolate duplicate-dispatch protection.

## Combined source checks

After integrating the current `origin/main` (`fe19a40`), both generic simulator
and signed physical-device **build-for-testing passed**, compiling the app,
widget and UI-test target. The signed app was installed in place as build 1702;
its four capability entitlements and configured Google/backend values were
checked again. The live-offer failure above was then reproduced on that build.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh --jobs 2 --no-parallel`
completed successfully: **1,647 passed, six optional integration skips, zero
failures** across 1,653 tests and 185 suites. Those skips concern explicitly
selected local-model/video/replay integrations. Build and test time was 408
seconds. The complete Python script/resource suite also passed: **34/34**.
These package checks are separate from the physical StoreKit failure and live
account grants.

### Latest model/voice integration

After integrating main `4bd789f`, the full serial Swift command built successfully
and completed with exit 1 after 428.60 seconds. The LiveDemo, Health and Core
products passed 51, 8 and 735 tests respectively. The Apple product encountered
two real Vision OCR failures: `e5rt_e5_compiler_compile call failed` (code 11),
after 100.486 and 52.909 seconds. These are failures, not optional skips or a green
full suite. [Issue #204](https://github.com/gibouu/morning-operator/issues/204)
tracks the platform failure; it was not fixed by weakening recognition checks.

The full-run accounting is **1,952 passed / two failed / seven optional skips**
out of 1,961 tests. After task-owned cache cleanup and additional free disk space,
the two failed Vision cases were rerun once with the same cached binaries and no
OCR source changes. Both passed (129.124 and 45.472 seconds; 174.598 test seconds,
176.43 elapsed). This is a scoped recovery, not a newly green full-suite run or
proof that disk pressure caused the earlier compiler errors.

The required Python/resource suite initially found 133 newly added source
strings missing explicit English translations (104 app, 29 Apple package).
Adding each exact English source unit preserved all previous French and catalog
metadata/forms. The required suite then passed **34/34**, and all seven string
catalogs, 23 JSON resources and eight plist/entitlement files parsed successfully.

### CI deadline regression

The observed CI failure in `aHangingSourceIsSilentAfterTheDeadline` used real
elapsed time to judge a 50 ms asynchronous deadline. `MorningExtrasProvider` now
accepts the same injectable `Clock<Duration>` pattern used by other briefing
controllers. Its production default remains `ContinuousClock`; the 4-second
default, 1 ms–10 second clamp, six source races, late-answer rejection and
cancellation policy are unchanged.

The regression holds the reader on a continuation, verifies it is still waiting
at 49 ms, advances to 50 ms and requires an empty result **before releasing the
reader**. It then checks cancellation and the discarded late result. Separate
cases verify caller cancellation and cleanup of an unused deadline after an
early successful answer. No longer wall-clock allowance or disabled assertion
was used.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh --jobs 2 --parallel --filter 'MorningExtrasProviderTests|MorningOpeningTests'`
passed **39/39**, zero failures/skips, in 0.014 test seconds (11.14 seconds including
the cached build). This targeted correction does not retroactively turn the old
CI failure or the earlier full local run green.

### Final complete parallel package run

On combined source `02c6899`,
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh --jobs 2 --parallel`
completed with **exit 0** in 14.02 seconds (0.38-second cached build). All four
products passed: LiveDemo **51**, Health **8**, Core **735** and Apple **1,169**
tests, across 226 suites. The aggregate is **1,956 passed, zero failed and seven
explicit optional integration skips**, out of 1,963 tests. Model/media inputs and
the opted-in live OpenAI memory integration remained unselected.

Both previously failing Vision cases actually passed, rather than skipping:
layout **7.933 seconds**, screenshot **7.942 seconds**. The corrected hanging-source
deadline case passed in **10.108 seconds** under parallel main-actor load, using
its controlled 49/50 ms clock assertions. This is a newly green complete local
run; the earlier real compiler failures remain recorded in
[issue #204](https://github.com/gibouu/morning-operator/issues/204), and hosted CI
is a separate pending check.

After integrating main `297ec1a`, the retained Jury client identity and typed
browser-command contracts passed **19/19**, zero failures/skips. The new Jury
microphone graph is iOS-only and guarded by `MORE_JURY_DEMO`; these Mac package
tests do not prove its acoustic behavior or ordinary cloud voice acceptance.

## Connections UI acceptance

Testing reproduced a production SwiftUI navigation defect: Instagram, WhatsApp
and Facebook professional NavigationLinks were wrapped inside a single List row.
Tapping Instagram's visible title opened Facebook. Moving the note and each link
into direct sibling disclosure rows restored independent destinations; the fix
does not change provider eligibility or account ownership.

The first post-fix three-destination regression passed in 54.391 seconds. A fresh
build after integrating main `4bd789f` then passed all four final targeted cases,
zero failures, in 280.722 seconds:

| Simulator journey | Result / seconds |
| --- | --- |
| Standard day navigation and Settings appearance | Pass / 27.584 |
| Website/native/account returns and each professional destination | Pass / 58.918 |
| French largest/night unavailable accounts with reachable Retry | Pass / 69.378 |
| French largest/night expanded professional titles | Pass / 124.843 |

The earlier Calendar/Slack setup and empty-account recovery run passed 4/4.
All account values in these UI scenarios were explicitly synthetic, DEBUG-only
fixtures; no provider grant, real mailbox read or write is implied. Raw xcresults
and screenshots remain ignored local evidence. The new physical test03/test04
were added afterward and are physical-only; production UI is unchanged.

A separate temporary observer test saw the real Instagram cookie-consent page
inside MORE's WKWebView (20 static texts, 13 buttons, three links), then closed
back to Connections. It took 46.905 seconds; no strict 30-second latency guarantee
is claimed. No cookie choice, login, authenticated feed, Ready confirmation or
automated social action occurred. The temporary observer was removed after
inspection. This resolves public remote-render uncertainty while retaining the
authenticated-browser acceptance gate.
