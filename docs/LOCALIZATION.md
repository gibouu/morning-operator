# French and English in MORE

MORE offers exactly **Français** and **English** in Settings → Language. The choice persists independently of workspace data. First launch uses French for a French primary iPhone language and English otherwise; region and secondary French do not change that rule. A saved choice takes precedence. No language questionnaire precedes discovery.

`MorningCore.AppLanguage` supplies SwiftUI, explicit Foundation resource bundles, formatting, local-model instructions, recognition, command grammar and speech. Regional formats remain intact. Settings offers Homme/Femme or Male/Female, with one persisted gender for primary synthesis and conversation. Automatic Apple recovery selects a compatible installed voice; the best available quality and audible gender depend on the phone's installed inventory. Recognition uses `fr-FR` or `en-US`; Apple speech can use an installed dialect of the chosen language without falling back to another language. See [voice choice](VOICE-CHOICE-ACCEPTANCE-2026-10-16.md).

Changing language pauses the same session, stops speech/listening, invalidates generated prose and pending action review, and refreshes notices from semantic state. Drafts, recipients, receipts, uncertain-operation journals and partial dictation remain available for review. It does not repeat an effect or request permission. Typed Health errors relocalize without another request/read; pending setup is cancelled and late consent completion cannot enable sleep. Resume remains explicit.

Saved routine text, notes, recordings/OCR, messages, account/calendar names, provider pages and protocol values retain their original wording. MORE's permission/shortcut resources have both languages; Apple-owned prompts, Siri and provider pages retain their system/provider boundaries. Live Activity payloads carry the choice. Known service failures use app-owned explanations instead of raw diagnostics.

## Source and delivery

Main `fcd8f0d` is included in code freeze `6921b87007d59c8b30b83b7eaac0edcaf6e1a9ad`, Sources tree `5117eb25cc23dc1756273da33c5384b2022897a8`. This preserves Home, native Settings, optional Health sleep, Glass discovery/access screens, compact branded connections and the nonvisual DEBUG preview identifier. The preview cannot purchase or grant access; StoreKit owns actual pricing and trial eligibility.

The compact Connections screen is recognized in both sign-in and confirmed-website states using three required pieces of live wording. Historical screen wording remains recognized after retirement. Regression tests preserve the source/catalog assertions and reject incomplete matches and ordinary provider lists.

Delivery and live merge/check status are tracked in [PR #193](https://github.com/gibouu/morning-operator/pull/193). Documentation-only delivery commits do not change the tested application inputs or signed artifact.

## Verification

Commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Check | Observed result |
| --- | --- |
| Full serialized Swift package tests | **PASSED** on the final code: Health 4 tests/1 suite, Core 700/80, Apple 949/104. Includes Health language/cancellation and compact Connections current/historical recognition. Six optional model/video/replay tests explicitly skipped; real Apple model inference was not run. Command: `./scripts/test.sh --jobs 2 -Xswiftc -j2 --no-parallel`. Log: `/tmp/more-localization-final-confirmed-package.log`. |
| Python | **34 PASSED**, `/tmp/more-localization-final-confirmed-python.log`. |
| Six-catalog audit | **PASSED**: all translatable entries have explicit FR/EN; 192 formatted keys, 2,141 paired variants, 52 named/plural substitution keys and 11 shortcut phrase variants. No unresolved placeholders or argument-position/type/length mismatch. |
| Signed iOS Debug build 1600 | **PASSED**, `/tmp/more-localization-final-confirmed-signed-build.log`. No physical device was selected or controlled. |
| arm64 simulator build | **PASSED**, app/widget/UI-test targets, `/tmp/more-localization-final-confirmed-simulator-build.log`. Compilation does not establish UI runtime success. |
| Signed artifact verification | **PASSED**: strict signatures, FR/EN bundles, six privacy manifests, actual app capabilities, widget isolation and app-only Health framework linkage. |
| Cloud CI | Final-code [run 38844714092](https://github.com/gibouu/morning-operator/actions/runs/38844714092) was queued at 03:20 UTC on 16 October 2026; no cloud package/app success is claimed for this freeze. Current status is visible in PR #193. |
| UI runtime | **PARTIAL / final-source runtime unverified**. Two later smoke attempts stalled in accessibility or runner preparation and were interrupted; no pass was inferred. [#202](https://github.com/gibouu/morning-operator/issues/202), related [#199](https://github.com/gibouu/morning-operator/issues/199). |

Earlier UI batches recorded 18/21 passes on `6ded082`, then 10/12 on `e3c03f4`. The obsolete microphone-heading assertion was corrected; legacy navigation remains [#186](https://github.com/gibouu/morning-operator/issues/186). Two largest-text rotation failures remain [#195](https://github.com/gibouu/morning-operator/issues/195): videos stay portrait despite rotation requests in headless iOS 26.5/Xcode 27, with cause unresolved and strict assertions retained. These recordings predate the final Health/Glass source; the full UI suite is not green. Fixture startup under load remains tracked separately in [#190](https://github.com/gibouu/morning-operator/issues/190).

## Artifact and acceptance boundaries

`work/localization-1600-artifact/` contains `MorningOperator.app`, `MorningOperator-1600.zip` and `verification.json`: official bundle `com.gibouu.morningoperator`, version 0.1.0 (1600), source/Sources matching the freeze above. Archive SHA-256: `31328b605f2f420400301e3f037da08059cd38f556bd40a507beb046bbefffcc`.

Strict signatures and FR/EN resources pass. All six privacy manifests are present, including Core's defaults reason `CA92.1`. HealthKit, WeatherKit, Family Controls and app/website usage are actually signed app entitlements; extra Health entitlements are absent. Widget capability isolation and Health linked only in the app pass. The embedded profile expires on 2027-10-16. Packaging does not establish consent, live data, StoreKit access or App Store approval.

Google client/callback metadata match local configuration; its prototype bundle metadata differs from this official artifact. Console alignment and live OAuth remain unverified ([#197](https://github.com/gibouu/morning-operator/issues/197)); this does not establish an OAuth failure. No private configuration values or signing/profile identifiers are published.

The earlier freeze above did not install/control the reserved phone. Subsequent owner-authorized physical testing is recorded in [ordinary iPhone acceptance](LANGUAGE-VOICE-IPHONE-2026-10-16.md): build 2026101622 retained French/English and gender through relaunch, but all four examples used Apple backup and the owner rejected their quality. The final **2026101630** installation was then individually activated; all four primary ElevenLabs samples finished without Apple backup, persisted through relaunch and restored the original choices. The owner confirmed them audible and better. [Exact 1630 acceptance](ELEVENLABS-1630-ACCEPTANCE-2026-10-16.md). The broader physical surfaces and conversation remain tracked in [#184](https://github.com/gibouu/morning-operator/issues/184) and [#116](https://github.com/gibouu/morning-operator/issues/116). Owner Health consent/sample acceptance remains [#15](https://github.com/gibouu/morning-operator/issues/15), and live purchase/access [#191](https://github.com/gibouu/morning-operator/issues/191). Synthetic checks do not establish live recognition, Siri/widget behavior, provider authentication or external effects. Raw evidence, signing inputs and artifacts remain local and ignored.
