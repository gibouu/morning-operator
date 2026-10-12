# Teammate handoff

**10 October 2026 · bounded delivery.** Work on `codex/more-quiet-morning`, the branch behind draft [PR #26](https://github.com/gibouu/morning-operator/pull/26), stacked on [PR #22](https://github.com/gibouu/morning-operator/pull/22). The default-branch README points to development work; default-branch app code is not this implementation. Follow [onboarding](ONBOARDING.md), [verification](PHASE-ONE.md) and the [digest protocol](DIGEST-TEST-PROTOCOL.md) before expanding scope.

## Local development paused — 10 October 2026

The owner paused local development and handed the project to teammates. Xcode and the project’s iOS 27 runtime, MORE Design simulator and regenerable build caches were removed from the owner’s Mac. The installed iPhone app at `1952d9f` was left in place. Source, local recordings, previews and verified compressed test/simulator evidence were preserved. Recreate the toolchain using [onboarding](ONBOARDING.md) on the next development Mac; use the review branch, your own signing account and fresh synthetic tests. Do not transfer signing credentials or personal recordings. Existing issues #1, #2, #3, #19, #21 and #27 were refreshed for the handoff; all broader acceptance remains open.

## Current revision and acceptance

The owner rejected the previous `0f94f6d` visual design. Its passing UI checks did not establish design acceptance. The new sunrise app source `1952d9f` is signed, installed and launched on the owner’s iPhone. Six focused native checks and one largest-text check pass; use [PHASE-ONE](PHASE-ONE.md) for its exact source, installation and results. The product goal remains open.

- A shell-free, custom-drawn sunrise reveals a compact 286 × 58-point native-glass command bar with four labeled vector icons. Play opens a ready state; Start begins only an approved routine. Learn replaces the duplicate Update/Learn dock entries; editing stays in History → Your routine.
- Home shows lowercase good morning / bonjour and each task’s own duration. Dawn and sunset palettes follow light/dark appearance. Default details lead with a short purpose, preserve raw manual notes under Saved details and keep spoken/source content available.
- Try a sample explicitly creates a synthetic 45-minute draft with separate iMessage, WhatsApp, WhatsApp Business, Messenger and Mail steps, optional scrolling and a thought. These external-app steps are manual and unconnected. The update does not automatically migrate or replace existing saved routines; explicitly choosing a sample installs a restorable draft.
- A slow native writer close no longer means the later-successful recording is discarded. Explicit discard/forget and real writer failures remain separate. Shared lifecycle checks are not a long physical capture result.
- French greeting/sample support is partial; complete translation is [#31](https://github.com/gibouu/morning-operator/issues/31).
- Existing local learning, evidence correction, approval, sourced calendar/weather and speech paths retain their separate verification. Changing a design does not establish model accuracy or connected-inbox access.

## Three next tasks, in order

1. **Walk through the installed refinement with its owner.** Use the latest installed source recorded in PHASE-ONE and the new sunrise previews. Check that Start, Stop, latest result and one correction are discoverable without instruction; record the exact failed step if not. The manual walkthrough required by #1 remains open. Put new ideas in issues instead of expanding this handoff. [#1](https://github.com/gibouu/morning-operator/issues/1), [#25](https://github.com/gibouu/morning-operator/issues/25).
2. **Prove one real digest chain.** Follow the protocol with fresh seeded content and withheld truth. Implement the missing typed digest layer, run actual Vision/model inference, validate facts and compare displayed/spoken output. Then test the selected physical app surface. [#23](https://github.com/gibouu/morning-operator/issues/23), [#28](https://github.com/gibouu/morning-operator/issues/28), [#2](https://github.com/gibouu/morning-operator/issues/2).
3. **Earn a multi-day claim.** Obtain five independent dated mornings/authorized aggregate days, retain unknown coverage and separate origins, then review one proposed update. Investigate Screen Time authorization before promising a historical bootstrap. [#9](https://github.com/gibouu/morning-operator/issues/9), [#11](https://github.com/gibouu/morning-operator/issues/11), [#21](https://github.com/gibouu/morning-operator/issues/21), [#30](https://github.com/gibouu/morning-operator/issues/30).

## Known failures and limits to preserve

The first glass run logged six passes/two failures: active ten-moment layout scrolled, and the reorder test queried a lazy Restore row before scrolling to it. The next native drag attempt changed the order and saved a draft but failed an incorrect expected destination; the final test requests the exact after-third order. That historical ten-test run belongs to `de6d4b1`; current sunrise results are recorded separately in [PHASE-ONE](PHASE-ONE.md). A keyboard/frame-dimension runtime warning remains unexplained; no causal diagnosis or fix is claimed.

The Mac model previously reported `modelNotReady`; a different simulator attempt reported availability but its required backend rejected inference. Do not retry those unchanged environments as proof of quality. One older real phone clip saved OCR successfully but produced a bad habit proposal from MORE's setup text; targeted guards are not general accuracy. Native capture remains limited to 30 minutes or a monitored 256 MiB; imports allow 31 minutes/512 MiB and at most 24 sampled frames despite removal of the whole-input 8k rejection. The [long-recording protocol](LONG-RECORDING-TEST-PLAN.md) specifies the missing segmentation, coverage and recovery proof for 45–90 minutes. The app pauses runs on backgrounding. Real microphone recognition, listener audibility, HomePod, provider inboxes, protected messaging surfaces, exact background preparation, PCC access and Screen Time data entitlement remain separate checks.

Disk has repeatedly affected native OCR/build/test work. Removing only the unused iOS 26.5 simulator runtime increased free space from roughly 3.4 GiB to 13.8 GiB; the active iOS 27 runtime, source, raw media and result evidence remain. No extra managed worktrees needed cleanup. Reuse **one build cache per purpose** instead of creating a cold derived-data directory for every run; only remove identified regenerable outputs when needed. Do not delete system model assets or convert unavailable/failing stages into mocked passes.

## User requests and backlog homes

This maps the outstanding direction to existing issues; it does not close them or assign collaborators. The current local `work/issues-handoff.json` snapshot includes #29/#30 and supplies the titles/URLs. No separate digest issue is needed: its acceptance belongs in #23 and #28, with the existing source/learning dependencies. Check current issue bodies before changing scope.

| Request | Issue coverage |
|---|---|
| Complete French localization | [#31](https://github.com/gibouu/morning-operator/issues/31) |
| Quiet native glass, one-screen morning, sunrise actions, details/reorder, accessible fallback and review | [#25](https://github.com/gibouu/morning-operator/issues/25) |
| Reliable long recordings, explicitly started learning windows and recoverable evidence | [#19](https://github.com/gibouu/morning-operator/issues/19), [#27](https://github.com/gibouu/morning-operator/issues/27), [#9](https://github.com/gibouu/morning-operator/issues/9) |
| Seeded capture/model/fact accuracy and one honest full demo | [#23](https://github.com/gibouu/morning-operator/issues/23), [#14](https://github.com/gibouu/morning-operator/issues/14), [#2](https://github.com/gibouu/morning-operator/issues/2) |
| Short greeting, daily digest, email/news preparation and wake-time fresh deltas | [#28](https://github.com/gibouu/morning-operator/issues/28); Calendar/Weather [#13](https://github.com/gibouu/morning-operator/issues/13). Email/news provider selection is unfinished. |
| Three/seven-morning onboarding, five independent-day proof, reviewable updates and optional weekly debrief | [#11](https://github.com/gibouu/morning-operator/issues/11), [#21](https://github.com/gibouu/morning-operator/issues/21), bootstrap [#30](https://github.com/gibouu/morning-operator/issues/30) |
| Keep enjoyable rituals; optional social/time/wellbeing goals with no mandatory meditation | [#10](https://github.com/gibouu/morning-operator/issues/10), optional limits [#17](https://github.com/gibouu/morning-operator/issues/17), HealthKit [#15](https://github.com/gibouu/morning-operator/issues/15) |
| Voice choice/control, spoken completion, Siri/start opportunity and little daily app management | [#4](https://github.com/gibouu/morning-operator/issues/4), [#6](https://github.com/gibouu/morning-operator/issues/6), [#16](https://github.com/gibouu/morning-operator/issues/16), [#20](https://github.com/gibouu/morning-operator/issues/20) |
| Mail, WhatsApp/Business, iMessage, Messenger capture; social back/again/like/comment with scoped effects | Physical capture [#3](https://github.com/gibouu/morning-operator/issues/3)/[#23](https://github.com/gibouu/morning-operator/issues/23), tethered control [#7](https://github.com/gibouu/morning-operator/issues/7), effect journal [#12](https://github.com/gibouu/morning-operator/issues/12). Read-only protocol does not exercise sending. |
| HomePod, room-to-room/HomeKit/robot concept | [#4](https://github.com/gibouu/morning-operator/issues/4), [#5](https://github.com/gibouu/morning-operator/issues/5), voice/output [#20](https://github.com/gibouu/morning-operator/issues/20); wider embodiment stays future feasibility. |
| Optional direct PCC/multimodal route, current local-only behavior | [#29](https://github.com/gibouu/morning-operator/issues/29) |
| Privacy, originals/corrections, deletion/export, separate research consent | [#8](https://github.com/gibouu/morning-operator/issues/8), [#24](https://github.com/gibouu/morning-operator/issues/24) |
| Subscription, supported integration/voice options, repeat-use trial and candidate naming | [#18](https://github.com/gibouu/morning-operator/issues/18), [#20](https://github.com/gibouu/morning-operator/issues/20), [product direction](PRODUCT-DIRECTION.md), [business brief](BUSINESS.md). Naming is not a completed rename. |

Choose one of the three next tasks, agree file ownership, and stop with its report and concrete blocker or result. Keep evidence in ignored local work folders, share concise redacted summaries, and leave unrelated issues open.
