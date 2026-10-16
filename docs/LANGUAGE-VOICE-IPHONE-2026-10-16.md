# Ordinary iPhone language and voice acceptance

16 October 2026 · [#184](https://github.com/gibouu/morning-operator/issues/184), [#116](https://github.com/gibouu/morning-operator/issues/116).

## Installed candidate and method

MORE 0.1.0 **(2026101622)** was installed in place on the paired physical iPhone running iOS 27.2 beta. The ordinary app source is `786f1dd0f159ad4e0ed7a3a4bc3f36e8973f6eed`; the compiled UI runner is `f4ae83faebe81585aa429863ebf5787823d2fd34`. The frozen signed app remained byte-identical when only the runner was rebuilt. The installed version, ordinary launch and running executable were checked separately from compilation.

Strict code signatures, embedded-profile coverage for the paired phone, packaged French/English resources and the actual signed HealthKit, WeatherKit, Family Controls and app/website-usage entitlements were verified. This does not establish live access to those services.

`PhysicalLocalizationAcceptanceTests.testFrenchEnglishVoiceChoicePersistsInOrdinaryApp` controls only the ordinary app through XCTest. It passes no app launch arguments, language overrides, fixture workspace, permission grants or StoreKit configuration. It captures the existing language and gender, changes them through Settings, plays the fixed non-personal sample, terminates/relaunches MORE after each choice, then restores and verifies the original preferences through another launch. No microphone, saved routine execution, provider authorization, trial or external message is used.

## First physical run: primary speech failed

After the owner unlocked the phone, the test ran from 10:18:49 to 10:21:25 Paris time. Its **four failures are retained**: all four primary-provider assertions failed because the visible backup-voice message appeared. They are not counted as successful primary synthesis.

| Choice | Started and finished | Retained after relaunch | Observed route |
| --- | --- | --- | --- |
| Français / Homme | Yes | Yes | Apple backup |
| Français / Femme | Yes | Yes | Apple backup |
| English / Male | Yes | Yes | Apple backup |
| English / Female | Yes | Yes | Apple backup |

Both language labels, both gender labels and the playback controls matched the selected language. Each sample reached the speaking state, returned to ready through the ordinary completion callback, removed Stop and reported no terminal sample-unavailable error. The app remained in the foreground. The original language/gender were restored and checked after relaunch; no restoration failure was recorded.

The public installed Apple inventory reported **Standard** as the best eligible quality for each language/gender combination. No eligible Enhanced or Premium voice was reported. Only language, gender and quality were retained in the sanitized summary; no Personal Voice or voice identifiers were exported to the repository.

The owner confirmed that the samples worked audibly but described the voices as very poor. **Perceived quality is rejected**, not accepted. The primary-synthesis fault remains under investigation with the voice/backend task. A valid HTTPS API configuration was checked in the exact frozen app, but the backup indicator alone cannot distinguish HTTP failure from native audio preparation/playback failure.

## Corrections and validation

- Pending cloud-voice startup is invalidated on stop and rechecked after asynchronous operations, including language and session identity, so an obsolete startup cannot reconnect listening.
- External speech failure uses the currently selected language's resource bundle. A regression test switches French to English before failure; missing French/English catalog entries were added together.
- The physical harness now requires complete playback, tests primary versus Apple backup explicitly, preserves preferences on failure and records installed Apple quality without private voice metadata.
- Targeted shared checks passed: 9 Core and 28 Apple tests for the startup, speech, locale and related regression coverage. Native signed `build-for-testing` passed for the combined ordinary app; the final runner-only rebuild also passed. French/English catalog invariants passed.

The broader voice task separately records its shared/backend tests and simulator journeys in [voice delivery evidence](VOICE-CHOICE-ACCEPTANCE-2026-10-16.md). Those checks do not override the failed primary-provider assertions above.

## Evidence boundaries

Raw xcresults, screenshots, device/profile identifiers, local signing configuration and audio remain ignored and local. The first physical run is retained in `work/iphone-language-physical-primary.xcresult`; its four route attachments each say `playback=apple-backup; finished=true; primaryRequired=true`. Clean voice-sheet screenshots were inspected in both languages and both genders.

An attempted pre-install workspace-file copy did not succeed; no new workspace backup or saved-routine content comparison is claimed. The install was in place, with no uninstall, reset or manual workspace write. This test establishes the preference transitions above, not live recognition, conversation, personal narration, routine effects, Siri, widgets, provider screens or quality of a voice that was not heard.
