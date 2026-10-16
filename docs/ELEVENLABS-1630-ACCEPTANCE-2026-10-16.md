# ElevenLabs on the ordinary iPhone: build 1630

16 October 2026 · [#116](https://github.com/gibouu/morning-operator/issues/116), [#220](https://github.com/gibouu/morning-operator/issues/220).

## Result

**The final ordinary MORE installation is activated, and all four fixed samples played completely through the primary ElevenLabs route without Apple backup.** The owner confirmed: “Oui, les quatre sont audibles et meilleures.” This accepts audibility and improved quality for these samples, not a microphone conversation or every future utterance.

| Selected language / gender | Primary playback began and finished | Apple backup | Retained after relaunch |
| --- | --- | --- | --- |
| Français / Homme | Passed | Absent | Passed |
| Français / Femme | Passed | Absent | Passed |
| English / Male | Passed | Absent | Passed |
| English / Female | Passed | Absent | Passed |

The original language/gender were restored and checked after another ordinary relaunch. The app returned to Home and its ordinary process remained running. Four clean voice-sheet screenshots were inspected; no backup message appeared.

## Exact installation and phone control

The installed app is MORE **0.1.1 (2026101630)**, ordinary bundle `com.gibouu.morningoperator`, source `724d013ad3bc359560e1dbd58e8e847101436f35`. Its delivered executable hash and strict signature were verified. At the start of this task, fresh app inventory was empty and ordinary launch explicitly returned app-not-installed; the exact signed 1630 artifact was installed again, without uninstall/reset or a different build. The delivery coordinator's earlier private owner backup was retained; no new pre-install backup is claimed here.

Only the signed UI-test runner was separately installed. Both acceptance runs used Xcode's documented `UseDestinationArtifacts=true` mode and the already installed target bundle. App paths and dependent products were removed from those plans, so the test driver could not reinstall the old 1622 app or replace MORE during testing. Ordinary app arguments and environment overrides were empty. No seeded workspace, StoreKit fixture, microphone, purchase, provider reauthorization or saved-routine execution was used.

`OrdinaryConnectionsAcceptanceTests.test12ReadPrivateInstallationSupportCodeFromOrdinaryApp` passed in **27.764 seconds** and captured a fresh private support code from build 1630. It selected the product's visible Debug developer entry and deferred optional setup prompts; no StoreKit entitlement, purchase or native grant was simulated. Its unique server match differed from the earlier 1622 test12 identity. No installation identity, support code, bearer or signing value is published.

## Targeted server activation

At **11:11:24 Paris time**, an exact support-code/D1 match identified a single existing installation. The canonical configuration was checked against live settings immediately before changing it. Only that installation was appended to the voice allowlist, **two entries to three**. Both prior entries were preserved.

Deployment **`8eaf7dde-56e2-48bc-b598-3fc82777ce99`** retained the canonical runtime source, all other bindings, three secret bindings, sixteen service registrations and the database. Catalog and business-execution row aggregates matched before and after. No provider-account assignment or business execution was changed. Live readback confirmed the exact appended list and every other binding unchanged.

The physical test exercised the resulting authorization and playback; successful settings readback alone was not counted as a working voice. An observer captured **two actual `POST /v1/voice/speech` responses with HTTP 200**, corresponding to the English samples. It connected after the first French samples, so four HTTP captures are not claimed. Authorization headers were not available for matching in the tail; the installation match came from the fresh UI code and D1. Only method/path/status/time were retained, with no request headers, bodies or audio. The observer was stopped after testing.

## Physical acceptance evidence

`PhysicalLocalizationAcceptanceTests.testFrenchEnglishVoiceChoicePersistsInOrdinaryApp` passed in **144.595 seconds**, **one test, zero failures**, ending at **11:14:16 Paris time**. Its four retained route attachments each state `playback=primary; finished=true; primaryRequired=true`, with the corresponding language and gender. The test requires the ordinary completion callback, ready state and removal of Stop; it also rejects both the backup indicator and the sample-unavailable error before and after completion.

The installed version was independently read again after the run and remained **2026101630**. Raw xcresults, screenshots, configuration snapshots and support-code correlation remain local/ignored in `work/voice-cause-research/`; only the sanitized findings are shared.

This resolves activation and fixed-sample primary playback on 1630. The earlier [1622 authorization diagnosis](VOICE-FAILURE-DIAGNOSIS-2026-10-16.md) and four Apple-backup failures remain historical evidence. First-upgrade namespace continuity and recovery of previously lost namespaces remain separate in #220; microphone conversation, interruption and personal narration were not exercised by this acceptance.
