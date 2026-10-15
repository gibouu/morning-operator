# MORE iOS team guide

15 October 2026 · Runtime inspected at `8e25b20`; planning contract merged at `b8a6c93` without runtime changes. Tracking [#161](https://github.com/gibouu/morning-operator/issues/161).

Use this inventory with the [demo requirements](DEMO-REQUIREMENTS.md), [normal iPhone checks](DEMO-TEST-PLAN.md), [source audit](audit/2026-10-15-IOS-AUDIT.md) and [Apple model plan](APPLE-MODEL-PLAN.md). Planning IDs below identify stories; they are not new GitHub issues. Acceptance criteria are proposed closing evidence and were not executed in this audit.

## Product and journey

MORE helps one person turn explicitly shared morning evidence into a reviewed routine, then follow it with useful facts, chosen pleasures and simple controls. First value is approving a sourced plan and starting a supported moment. Returning value is using the plan and valid saved connections tomorrow without daily setup.

Person contexts: **P1** first setup/learning; **P2** returning morning; **P3** correction, access loss or privacy; **P4** maintainer/demo operator. Accessibility and French apply across these contexts. Reduced screen time and accurate habit inference are hypotheses, not proven benefits.

Small complete story: **choose sources → learn from actual coverage → edit/approve → short sourced opening → read Gmail → one supported external moment with timer/+2/Next → recap → return tomorrow**. Local reply generation remains optional until the intended phone proves it. The 15-destination catalogue is an expansion map. See [#155](https://github.com/gibouu/morning-operator/issues/155) and [merged #162](https://github.com/gibouu/morning-operator/pull/162).

No separate MORE account or backend is needed. Gmail authorization, iOS permissions and website sessions are distinct. “Connect once” preserves successful configuration where allowed; it cannot suppress future consent or restore revoked access.

## Twenty user stories

**Source** = inspected path exists; **partial** = full promise/proof incomplete; **future** = scoped investigation/build. References E1–E10 below identify source evidence.

| ID / person | Promise and domain | Current implementation / existing issue | Acceptance |
|---|---|---|---|
| IOS-AUTH-01 · P1–P3 | Connect once, see real status, disconnect — Connections | **Source, restore acceptance partial.** Gmail readonly/offline, private refresh credential, silent restore, Retry, Disconnect. Website “ready” is an owner assertion. E2/E3. #149/#151/#139 | Reopen/relaunch/next morning without OAuth when valid. Transient failure offers Retry without deleting access. Revoked access requires explicit Connect. Explain device disconnect versus Google grant revocation. |
| IOS-SETUP-01 · P1 | Choose a few sources and resume setup — Connections/Shell | **Gap/partial.** Chosen-site/ready state is view-local; the normal first-use destination opens Learn directly. Legacy manual/sample helpers are not the chosen onboarding menu. E2. #157/#25 | Persist selected/skipped/configured choices without content/passwords. Recheck actual permissions. Resume unfinished setup; successful steps stay done. Reach one approved usable plan without every integration. |
| IOS-LEARN-01 · P1 | Get a starting plan from authorized Screen Time — Learning | **Source; quality/eligibility partial.** Seven days requested; actual coverage, estimated order, pending proposal. E4. #30/#105; historical PR #122 | Show returned dates/zone/coverage. Distinguish denied/no coverage/read failure. No claim of exact app switches, scrolling, calls or message reads. Owner approval remains separate. |
| IOS-LEARN-02 · P1/P3 | Record/import, inspect and correct evidence — Learning | **Source; real quality partial.** Explicit capture/import, bounded extraction, acquisition/date/zone/origin, original OCR and corrections. E5. #19/#23/#27/#84; PR #108 | Clear start/stop/retry/discard; preserve provenance and unknowns. Editing evidence invalidates dependent interpretations/proposals. Samples cannot establish a complete movie or morning. |
| IOS-LEARN-03 · P1/P2 | Receive a cited proposal from comparable mornings — Learning/Plan | **Partial.** Local guided generation, exact quotes, one–five dated same-zone observations; no proven three/seven-day habit program. E5. #2/#11/#23/#105 | Abstain on unsupported evidence. State included dates/origin/coverage; missing days are not zero. Late/stale output cannot attach. Preserve saved choices; no automatic plan adaptation. |
| IOS-PLAN-01 · P1/P3 | Edit, order and approve wanted moments — Plan | **Source; UX acceptance partial.** Versioned drafts, Keep/Exclude/duration choices, previous approved version, pending approval. E6. #10/#11/#72/#67 | Changes need approval; approval does not start. Persist before showing success. Save failure keeps prior state. Running/paused session pins its version. Accessible reorder alternative works. |
| IOS-PLAN-02 · P2 | Reuse one approved plan on later days — Plan/Run | **Source; discoverability partial.** Plan persists; separate sessions; no once-per-day lock. E6/E7. #154 | No reapproval if unchanged. Explain unfinished run versus new morning. New Gmail target policy must not rewrite existing approved routines silently. |
| IOS-BRIEF-01 · P2/P3 | Hear concise ordered current facts — Briefing | **Partial.** Weather→Calendar opening, optional fuller brief, once-per-session greeting; Gmail not connected to speech. Health module unlinked. E8. #28/#13/#139/#15 | Agree order, check day/zone/freshness before playback. Missing/denied/stale is not zero. Forecast claims require forecast data. No repeated greeting on refresh/relaunch. |
| IOS-MAIL-01 · P2 | Read selected unread Gmail safely — Connections | **Source; owner confirmed reading.** Up to five summaries, bounded inert plaintext, native reader in approved Gmail moment. E3. #149/#151 | Report partial failures and unsupported/truncated bodies. No remote images/HTML actions/attachments. Same routine timer; login alone never proves another inbox’s access. |
| IOS-MAIL-02 · P2 | Prepare, edit and copy a reply — Connections/local model | **Source; real model acceptance pending.** Guidance, local Prepare, editor, expiring local Copy. E3/E5. #149; #111 is separate | No send, remote draft or mailbox mutation. Reject unsupported/truncated/oversized context honestly. Manual edit/copy works without inference. Leave/background clears volatile content as disclosed. |
| IOS-COMMS-01 · P2 | Distinguish email/message/missed call/unknown — Providers | **Gap.** App categories and badges do not establish communication-event semantics; no general call-history adapter. E4. #156/#139 | Source-bound kind/identity/time/coverage/freshness. “Call me” text stays a message. Unsupported call access is unavailable, not zero. No Notification Center scraping. |
| IOS-WEB-01 · P2 | Use a visible website under personal control — Browser | **Source; service proof varies.** Explicit badge/headline/one-scroll requests with login/origin guards. E9. #127/#139 | Unsupported markup fails honestly. Scripts do not type/click/submit/read credentials. A scroll request is not a watched video. Site permission/rules and real service checks gate release. |
| IOS-WEB-02 · P1/P2 | Teach pace, then choose bounded replay — Browser/Learning | **Partial.** Numeric Start/Stop/review/save exists; replay absent. E9. #159 | Prove measurement first. Later replay is separate opt-in, reviewed, timed and stoppable; stop on login/background/privacy/site changes. No comprehension/native-gesture claim. |
| IOS-WEB-03 · P1 | Learn in Safari, later desktop Chrome — Extension/Learning | **Future.** No extension target/manifest found in inspected inventory. #160 | Narrow site consent, explicit start/stop, private-browsing exclusion, no credentials/text capture, review/delete and bounded transfer. iPhone Safari and desktop-to-phone Chrome are separate gates. |
| IOS-RUN-01 · P2/P3 | Start/resume/pause/end with touch or supported voice — Run/Shell | **Source; UX/phone proof partial.** Today-only Play surface; active/paused alternatives; explicit voice turn. No hour cutoff. E7. #154/#6/#16 | Clear next action for past day/draft/paused/complete. Ready needs explicit Start. Navigation starts no microphone/recording. Late-start UX stays parked until owner resumes it. |
| IOS-RUN-02 · P2 | Open one chosen external activity — Run/Targets | **Source for closed list; lesson/game gap.** Explicit URL handoffs. E10. #126/#158 | Verify one reviewed installed/unavailable route. Unknown launch is not “not installed.” No automated taps or invented lesson completion. |
| IOS-RUN-03 · P2 | Keep one timer and use Island +2/Next — Run/System | **Source; ordinary-phone actions pending.** Bound timer, exact deadline token, guarded Next, durable retirement. E10. #16/#126/#158 | Lock/background/return/relaunch retain run+step. +2 adds exactly 120 seconds once. Duplicate/stale controls cannot affect another moment. Expiry does not force app switching. |
| IOS-RECAP-01 · P2/P3 | See what happened and optionally reflect — Review | **Source; full journey proof pending.** Completed/skipped/stopped recap, save state, optional thoughts/feedback/goals. E10. #10/#12/#14 | Match session facts; show save failure; label samples. Planned/run time is not observed external-app usage. Review before Save; reconcile uncertain Apple-app writes before retry. |
| IOS-PRIV-01 · P3 | Inspect/export/remove/recover local work — Privacy/Storage | **Partial.** Full Forget generation/lock/cleanup exists; automatic expiry is not implemented, its policy needs a decision, and recovery defects remain tracked. E3/E10. #8/#94/#118/#119/#120; PRs #100/#106 | Cancel changes nothing. Reset drains work, removes owned content/credential and blocks on incomplete cleanup. Relaunch resumes removal. Preserve readable/unsupported records exactly; never restore forgotten data. |
| IOS-REL-01 · P3/P4 | Use clear settings and a release matching its claims — Shell/Delivery | **Partial.** Current design differs from old onboarding docs; test harness and ordinary app proof differ. E1/E7. #31/#86/#79/#98/#110/#124/#161 | Current EN/FR navigation/status, readable errors and relevant feature gates. Record revision/build/device/OS and actual normal-route result. Fixture/model mocks or rendered previews cannot replace provider/phone proof. |

## Crosscutting gates

| Gate | Acceptance across domains | Existing issue |
|---|---|---|
| Offline/degraded | Local plan/manual/timer paths remain useful. Unavailable optional sources do not erase work; distinguish stale, empty, denied, partial and failed. | #13/#139/#151 |
| Accessibility | Real narrow phone, largest Dynamic Type, VoiceOver, 44 pt taps, focus after errors, long text, readable contrast, reduced motion and reorder alternatives. | #89/#109/#110/#67/#72 |
| Localization/time | EN/FR, long labels/plurals/speech, DST/midnight/zone/non-Gregorian dates. Exact source quotes stay unchanged. | #31/#94/#154 |
| Privacy/races | Cancel plus source/base/attempt/privacy-generation guards at final mutation, including credential rotation/intents. No late resurrection after leave/Disconnect/Forget. | #8/#149/#151 |
| Broken state | Preserve readable records/exact unsupported values; report partial save, duplicate IDs, interrupted capture/reset and ambiguous effects honestly. | #94/#118/#119/#120/#12 |
| Bounds/AI | Existing media/MIME/text/model limits, cancellation and source citations; documents/email/web content never grant action authority. | #23/#27/#149/#159 |
| Platform/release | Per-feature OS/entitlement/model/permission availability and fallback. iOS26 baseline does not make every feature available. Compatible saved data and isolated fixtures. | #1/#2/#15/#29/#30/#124 |
| Evidence | Sanitized outcome/build/route receipts, not private content logs. Separate unit/contract/native preview/phone/provider/model acceptance; no new telemetry server required. | #14/#23/#86/#155/#161 |

Gmail draft clearing is an intentional privacy promise. Do not silently persist replies merely because the supplied planning template suggests preserving drafts. Copy has a disclosed separate five-minute local clipboard lifetime.

## iOS practice baseline

These are team decisions grounded in the platform; they are not a claim that Apple mandates one folder structure or that the app has passed every gate.

| Practice | Apply in MORE | Primary guidance |
|---|---|---|
| Native accessible interaction | SF Symbols with accessible names, a 44 pt team touch-target goal, Dynamic Type, VoiceOver, contrast and reduced-motion checks. An icon-only dock still needs spoken labels. | [Apple accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) |
| Clear data ownership | SwiftUI observes owned state; ephemeral presentation state does not substitute for durable setup or domain state. Core values remain independent of views. | [SwiftUI model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app) |
| Responsive concurrency | Own task cancellation and immutable cross-isolation values. Measure heavy encode/OCR/model work; main-actor isolation alone does not prevent a UI stall. | [Responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [Sendable](https://developer.apple.com/documentation/swift/sendable) |
| Feature-specific permission and delivery | Ask for access in context; preserve denied/unavailable states and honest fallback. Check distribution entitlements, privacy, accessible UX and working services separately from the demo. | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) |

## Eight logical modules and team ownership

Keep the current app, Swift packages and widget. Start with logical folders/extensions and agreed contracts; do not launch a package rewrite while UX is active.

| Module | Current home | Owner and contract |
|---|---|---|
| Experience shell/design | Root/destinations/Learn/setup, DesignSystem/theme/art, strings | UX owns composition, labels/navigation/accessibility. Calls domain commands and displays honest states; does not implement OAuth or persistence policy. |
| Connections/setup | Gmail controller/views; connections view; Apple Gmail service/credential store | Connection hardening owns auth/API/status; UX owns presentation. Durable source choices, private credentials, volatile fetched content. Distinct connect/restore/retry/disconnect. |
| Evidence/learning | Core Screen Time/observation; Store+ScreenTime; Apple capture/archive/extraction/classifier/local model | Learning owns provenance, bounds, quality and cancellation. Returns reviewed evidence or pending proposal; cannot approve/run. |
| Approved plan | Core routine/preferences/portable document/proposals; routine review components | Plan hardening owns target/version/approval invariants. Sole workspace transaction changes approved state; no provider access from pure Core policy. |
| Morning run/system | Core session/timer/entry/activity/voice; Store+StepTimer/+Opening; Apple runtime/speech/listener; widget/intents | Run owns bound commands/effects/lifecycle; UX owns controls/art. Widget receives bounded generic projection and opaque bindings, never workspace/mail/evidence. |
| Briefing/provider facts | Apple Calendar/Weather/optional Health; briefing/opening models/controller/view | Provider hardening owns permissions/freshness/status; UX owns concise order. Returns prepared sourced facts; no silent learning reuse. |
| Review/privacy/storage | Core LocalDataControl/persistence/history; Apple archive/retention/receipts; privacy/recap | Privacy/storage owns generation, atomic write/reset and recovery. All durable writers cooperate with one workspace owner/lock; no competing whole-workspace stores. |
| Delivery/evidence | Package/project/entitlements/plists, CI/tests/docs | One integration owner handles shared registration and baseline. Domain owners own focused tests; phone/provider acceptance stays separately coordinated. |

Dependency rules: **MorningCore has no UI/provider dependency; MorningApple depends on Core and wraps platform services; the SwiftUI app composes both.** Keep domain policy in Core and provider effects behind adapters; the app may use Core directly. MorningHealth remains optional/unlinked; widget remains a separate target. MorningStore remains the workspace coordinator while narrower domain ownership grows.

Settle these small contracts before UI/backend work splits: **source status/capabilities**, **reviewed evidence with provenance**, **plan commands with expected revision**, **run commands with session+step+timer binding**, **prepared facts with freshness/coverage**, **privacy cancellation/drain/current generation**. These are conceptual boundaries, not newly implemented APIs.

File leases prevent overlap: one owner at a time for MorningRootView, MorningStore, strings, project.yml/generated project and entitlements. Domain workers return small hooks there. UX and hardening review the same acceptance story; neither correct policy nor a clean screen alone proves the full task.

## Review and merge gate

Every change starts with a user outcome and observable acceptance. A reported defect includes its trigger, expected behavior, actual result and affected baseline. The fix's evidence must exercise that failure; do not close an issue from a changed line or clean build alone. If characterization does not reproduce it, record the uncertainty rather than invent a successful repair.

Before integration: compare the branch with current main; reserve shared-file ownership; review domain invariants, cancellation, error/empty/denied states and compatible saved data; run the checks that address the change; obtain independent review. Record source/build/route and keep physical provider/OS acceptance separate. Generated project/entitlement changes have one integration owner. Merge a small coherent PR, then update the common baseline and retire only worktrees whose needed work is preserved.

The main-source audit's focused followups are [#163 resource measurements](https://github.com/gibouu/morning-operator/issues/163), [#164 backup/restore and upgrade](https://github.com/gibouu/morning-operator/issues/164), and [#165 timer scheduling diagnosis](https://github.com/gibouu/morning-operator/issues/165). Existing #8 covers retention policy. These investigations do not establish a measured hang, failed restore or missed alert.

## Historical PR overlap

GitHub snapshot on 15 October: **#162 merged at b8a6c93**; the eight older PRs below reported **DIRTY/CONFLICTING** against the earlier baseline. Recheck status and changes at the actual merge revision. This is conflict metadata, not evidence of who currently edits each branch. Inspect useful deltas against main; avoid broad merges of old Root/Store/design snapshots.

| PR | Overlap and reconciliation |
|---|---|
| [#162](https://github.com/gibouu/morning-operator/pull/162) demo contract | README plus requirements/test plan/rehearsal. Current #155 story; this ledger supplies #161 module detail. |
| [#122](https://github.com/gibouu/morning-operator/pull/122) Screen Time | Core/catalog, reader/Learn/Store/Root, strings/project/entitlements. Main already has normal learning and the learned Gmail target in [#152](https://github.com/gibouu/morning-operator/pull/152). Recover only remaining justified deltas. |
| [#123](https://github.com/gibouu/morning-operator/pull/123) extras | Briefing/opening/Health/capture/settings/Store/Root/project. Separate desired concise facts from optional unlinked Health and closing questions. |
| [#108](https://github.com/gibouu/morning-operator/pull/108) recognition | Context/archive/review/evidence/Store. Preserve citation/revision/unknown contracts; require #23 ground-truth quality. |
| [#106](https://github.com/gibouu/morning-operator/pull/106) recovery | Persistence/workspace/choices/privacy/Store. Reconcile #94/#118–#120 with synthetic damaged records; preserve Gmail/reset lifecycle. |
| [#100](https://github.com/gibouu/morning-operator/pull/100) retention | Privacy/history/retention/Store/strings/project. Keep full-reset generation contract; full Forget does not establish selective expiry. |
| [#102](https://github.com/gibouu/morning-operator/pull/102) a11y/errors/home | Root/Store/model errors/review/UItests. Recover focused fixes and retest current design, not the old layout. |
| [#114](https://github.com/gibouu/morning-operator/pull/114) tethered demo | Separate demo package/voice/UItests plus app/project. Developer control must remain outside ordinary product capabilities. |
| [#113](https://github.com/gibouu/morning-operator/pull/113) old design | Gallery/preview/app/project. Historical reference; current art/type/navigation already supersede broad redesign work. |

Main already contains Gmail #149/#151 and learned target #152; source existence does not close restore/model/full-morning acceptance. Reuse #139 rather than filing a duplicate generic API audit. #154 is parked. #156–#160 already cover communication kinds, durable setup, one external lesson/game, pace and extensions.

## Five next actions

1. Use the merged #162/#155 contract and this #161 guide as the common scope. This slice corrects README/onboarding/index drift; #86 retains broader historical handoff/evidence reconciliation. Keep the current design.
2. Characterize retained-state defects #118–#120 and select useful #106/#100 deltas before introducing new durable setup. Do not wholesale merge history.
3. Settle source-status/persistence contract and finish #157 using existing Gmail restore; then UX wiring and interrupted/relaunch/next-morning acceptance.
4. Prove #139/#14/#155 on the ordinary app: Calendar/Weather/Gmail plus one external route. #158 adds one lesson/game, with actual locked/background/relaunch/+2/Next.
5. Expand through bounded gates: #156 kinds; #159 measurement before replay; #160 Safari before desktop transfer; #29 optional PCC spike; #11 comparable multi-day learning. No silent approval.

## Future Apple model and recording boundary

Current flow stays explicit acquisition → bounded ordered frames/OCR → provenance/review → local availability → cited draft/abstention → validation → approval. Sampling cannot prove complete coverage or exact habits.

[#29](https://github.com/gibouu/morning-operator/issues/29) already names iOS27 PrivateCloudComputeLanguageModel and managed eligibility. The [Apple model plan](APPLE-MODEL-PLAN.md) records current official details and validation gates. Start with manufactured text/images and compare citation precision, abstention, latency and coverage. Any enabled PCC adapter needs explicit provider/source choice, availability/quota/offline handling, cancellation and no silent fallback. Direct model APIs, the system Apple Intelligence experience and Shortcuts Use Model are separate routes. No whole-movie contract or upload is assumed. No PCC call ran here. Separate opted-in research remains #24.

## Evidence anchors and inspection limits

- **E1 Stack:** [Package.swift](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Package.swift#L1), [architecture modules](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/docs/ARCHITECTURE.md#L68), [project targets](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/project.yml#L25).
- **E2 Setup:** [view-local selection/ready](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningOperator/MorningConnectionsView.swift#L8); initialization at line 117, owner-ready disclosure at line 81.
- **E3 Gmail:** [connect/save](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningOperator/GmailConnectionController.swift#L46), restore at line 81, Disconnect at line 145, volatile clear at line 247; [generation-checked service](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningApple/GmailConnectionService.swift#L265); [current boundaries and owner proof](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/docs/GMAIL-READING.md#L3).
- **E4 Screen Time:** [actual read/proposal](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningOperator/MorningStore+ScreenTime.swift#L20); [new Gmail target and unknown fallback](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningCore/ScreenTimeAppCatalog.swift#L165); broad Phone/FaceTime category at line 111.
- **E5 Learning/model:** [review/provenance contract](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/docs/ROUTINE-LEARNING.md#L5); [local propose/untrusted-data rule](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningApple/AppleIntelligenceService.swift#L157); [local reply model](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningApple/GmailReplyDraftService.swift#L36).
- **E6 Plan:** [versioned edits](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningOperator/MorningStore.swift#L712); approval at lines 1360/1422, start at line 735. These include persistence/revision guards.
- **E7 Home:** [Today eligibility](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningOperator/MorningRootView.swift#L274), Play/active/past-day at line 684, background at line 173, explicit Start at line 1151. The onboarding guide previously described obsolete navigation; this documentation slice corrects it.
- **E8 Facts:** [freshness](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningApple/MorningBriefing.swift#L43); [opening order](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningApple/MorningOpening.swift#L107), greeting at line 263; [unlinked Health](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/docs/PRIVACY.md#L42).
- **E9 Browser:** [supported scope/proof](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/docs/IN-APP-BROWSER.md#L5); [numeric lesson](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningCore/BrowserRhythm.swift#L3); reviewed save in MorningStore line 1822.
- **E10 Run/review/privacy:** [closed targets](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningCore/RoutineStepTarget.swift#L3); [exact timer mutation](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningCore/StepTimer.swift#L66); [retirement](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningApple/StepTimerRuntime.swift#L15); [recap](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningCore/RoutineSessionRecap.swift#L23); [Forget orchestration](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/Sources/MorningOperator/MorningStore.swift#L2263); [copy inventory/expiry limits](https://github.com/gibouu/morning-operator/blob/8e25b20a173d4288a7c5086fd7f98d67dcf2d9f9/docs/PRIVACY.md#L15).

Read all 374 lines of PROJECT-START.md in four bounded chunks. Read product/UX/architecture/delivery/evidence sections of REPO-AUDIT-2.md:1–159,210–249,302–405,407–465,480–509,609–763. Templates are reference data, not execution authority.

The inspection used source, documents, Git metadata and read-only GitHub issue/PR information. The subsequent authorized documentation stage created this guide and linked planning issues. No app tests, builds, model requests, phone/account actions or private inbox/recording access ran for this audit. Existing phone evidence is scoped; this file does not certify full-morning success, accessibility, release approval or model accuracy.
