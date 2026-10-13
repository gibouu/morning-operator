# Voice audit: Personal Voice, Siri voices and custom voices

This audit answers two open boxes of [issue #20](https://github.com/gibouu/morning-operator/issues/20). It records what Apple documents about Personal Voice and what any custom voice would require. It changes no code.

**MORE does not offer Personal Voice, a Siri voice or any custom voice.** The companion voice is an installed Apple system speech voice. Everything below the first section describes options that are not implemented.

Sources were opened on 13 October 2026. The project deploys to iOS 26.0 and is built with Xcode 27. Each source is labelled with the OS version it describes. Apple's developer reference pages carry no OS-version label; they show the release that introduced each API and no deprecation. A claim without an Apple page behind it is listed under [Unverified](#unverified).

## Conclusions

1. Personal Voice is technically reachable through one authorization call. Apple's pages name no `Info.plist` purpose string for it; that absence still needs a device check.
2. Apple's iOS 27 pages list Personal Voice for English (U.S.), Mandarin Chinese (China mainland) and Spanish (Mexico) only. French is not listed, and MORE speaks English and French.
3. Apple describes Personal Voice as the user's own voice, for personal non-commercial use, intended mainly for assistive communication apps. It is not a route to a relative's or a performer's voice.
4. Siri voices are not available through `AVSpeechSynthesizer` according to Apple's 2020 session. The picker must keep describing its list as Apple system speech voices.
5. Every cloud voice provider conflicts with the local-only rule in [AGENTS.md](../AGENTS.md). Screen-derived text may not be sent at all under that rule. Other text could be sent only behind a separate, explicit choice. No such choice exists today.

## What the app does today

| Behavior | Where |
|---|---|
| Speech uses `AVSpeechSynthesizer` on the device. | [SpeechCoordinator.swift](../Sources/MorningApple/SpeechCoordinator.swift) |
| The voice list is `AVSpeechSynthesisVoice.speechVoices()` filtered by `isBuiltInVoice`: identifier starts with `com.apple.`, and the voice has neither the `.isPersonalVoice` nor the `.isNoveltyVoice` trait. | `SpeechCoordinator.availableVoices`, `isBuiltInVoice` |
| The same filter is applied again when an utterance is queued. A saved identifier that fails the filter is not used. | `SpeechCoordinator.enqueueSpeech` |
| The automatic choice ranks by language match, then quality, then the system voice for the language. | [SpeechVoicePolicy.swift](../Sources/MorningApple/SpeechVoicePolicy.swift) |
| The picker offers Automatic, a preview, search, and the installed list by name, language and quality. Its footer says: "These are Apple system speech voices; Siri may use a different voice." | [VoicePickerView.swift](../Sources/MorningOperator/VoicePickerView.swift) |
| A saved voice that is no longer installed is reported, and speech uses the automatic choice. | `VoicePickerView`, `SpeechCoordinator.selectedVoice` |
| The selected identifier is saved in the local workspace snapshot. | [MorningStore.swift](../Sources/MorningOperator/MorningStore.swift) (`voiceIdentifier`, `saveVoicePreference`) |
| The audio session is `.playback`, mode `.spokenAudio`, option `.duckOthers`. | `SpeechCoordinator.activateAudioSession` |
| The app never calls `requestPersonalVoiceAuthorization`. It never writes synthesized speech to a buffer or file. It sends no text to a speech service. | No such call exists in `Sources/` |
| Purpose strings present: microphone, speech recognition, calendars (full and write-only), reminders, screen capture. None concerns speech output. | [iOS-Info.plist](../Configuration/iOS-Info.plist) |
| Background modes: `screen-capture` only. There is no `audio` background mode. | [iOS-Info.plist](../Configuration/iOS-Info.plist) |
| Entitlements: WeatherKit only. | [MorningOperator.entitlements](../Configuration/MorningOperator.entitlements) |

The exclusion of Personal Voice is deliberate. The code comment reads: "Personal Voice stays excluded even if another app flow previously authorized it."

## Personal Voice

### What Apple documents

| Point | What the source says | Source and OS version |
|---|---|---|
| Request call | `AVSpeechSynthesizer.requestPersonalVoiceAuthorization(completionHandler:)`, also available as `async`. It "prompts the user to authorize your app to use personal voices". | [Developer reference](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/requestpersonalvoiceauthorization(completionhandler:)), iOS 17.0+ |
| Status | `AVSpeechSynthesizer.personalVoiceAuthorizationStatus`. Cases: `notDetermined`, `denied`, `unsupported`, `authorized`. | [Status enumeration](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/personalvoiceauthorizationstatus-swift.enum), iOS 17.0+ |
| Changing the answer | The user answers the first prompt and can change the authorization later in the Settings app. A device that does not support personal voices is refused. | [Status property](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/personalvoiceauthorizationstatus-swift.type.property), iOS 17.0+ |
| How voices appear | Once authorized, personal voices appear in `speechVoices()` with the `isPersonalVoice` trait. The system makes them available only while the status is `authorized`. | [isPersonalVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice/traits/ispersonalvoice), iOS 17.0+; [WWDC23 session 10033](https://developer.apple.com/videos/play/wwdc2023/10033/), iOS 17 |
| Voice list changes | `availableVoicesDidChangeNotification` is posted when available voices change, for example when a personal voice becomes available and the user authorized the app. The picker already observes it. | [Notification](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/availablevoicesdidchangenotification), iOS 17.0+ |
| Minimum OS | The API is marked iOS 17.0. The Xcode 27 SDK header `AVFAudio/AVSpeechSynthesis.h` carries the same availability and no deprecation. Apple's support article states "iOS 17 or later". | Reference pages above; [Create a Personal Voice](https://support.apple.com/en-us/104993), published 13 October 2025 |
| Devices | Two Apple pages disagree. The support article lists iPhone 12 or later. The iOS 27 user guide says iPhone 15 Pro models, iPhone 16 models and later. | [Support article](https://support.apple.com/en-us/104993), October 2025; [iPhone User Guide](https://support.apple.com/guide/iphone/record-your-personal-voice-iph51936468d/27/ios/27), iOS 27 |
| Languages | English (United States), Mandarin Chinese (China mainland), Spanish (Mexico). French is not listed. | [Feature availability](https://www.apple.com/ios/feature-availability/#accessibility-personal-voice), iOS and iPadOS 27; same list in the iOS 27 user guide |
| What the user does first | Set a passcode. Create the voice in Settings → Accessibility → Personal Voice by reading sentences aloud. Then turn on **Allow Apps to Request to Use**. | [iPhone User Guide](https://support.apple.com/guide/iphone/record-your-personal-voice-iph51936468d/26/ios/26), iOS 26 version; [support article](https://support.apple.com/en-us/104993) |
| Sending the user to that setting | `AccessibilitySettings.openSettings(for: .personalVoiceAllowAppsToRequestToUse)` opens the setting. Apple's page states it is relevant to the authorization status API. | [openSettings(for:)](https://developer.apple.com/documentation/accessibility/accessibilitysettings/opensettings(for:)), iOS 18.0+ |
| Purpose string | Apple's list of protected-resource keys contains no Personal Voice entry. The request call's page and the SDK header mention no `Info.plist` key. This is an absence on those pages, not a statement by Apple. | [Protected resources](https://developer.apple.com/documentation/bundleresources/protected-resources), unversioned |
| Intended use | Apple's engineer says use "is sensitive and should be primarily used for augmentative or alternative communication apps". The user guide says Personal Voice can be used "only with Live Speech and with third-party apps that you allow, such as" AAC apps. | [WWDC23 session 10033](https://developer.apple.com/videos/play/wwdc2023/10033/), iOS 17; [iPhone User Guide](https://support.apple.com/guide/iphone/record-your-personal-voice-iph51936468d/27/ios/27), iOS 27 |
| Whose voice | Only the user's own voice, created on device, for personal non-commercial use. | [Support article](https://support.apple.com/en-us/104993), October 2025 |
| Capture and export | Authorized apps can speak aloud through the device speaker or during calls, "but they can't capture speech from Personal Voice". | [Support article](https://support.apple.com/en-us/104993), October 2025 |
| Where processing happens | Recordings are "processed securely on device". The voice is "generated on the device and not on a server". | [Support article](https://support.apple.com/en-us/104993); [WWDC23 session 10033](https://developer.apple.com/videos/play/wwdc2023/10033/) |
| Storage and iCloud | The voice is encrypted and stored on the device. Sharing across devices is optional, needs two-factor authentication, and uses end-to-end encryption in iCloud. A Legacy Contact cannot access it. | [Support article](https://support.apple.com/en-us/104993), October 2025 |
| Removal | The user deletes the voice in Settings → Accessibility → Personal Voice → the voice → Delete → **Delete Voice And Recordings**. A deleted voice cannot be recovered. | [Support article](https://support.apple.com/en-us/104993), October 2025 |
| Recent change | Apple announced in May 2025 that a voice can be created from 10 recorded phrases, and added Spanish (Mexico). | [Apple Newsroom](https://www.apple.com/newsroom/2025/05/apple-unveils-powerful-accessibility-features-coming-later-this-year/), May 2025 |

Background playback, AirPlay and HomePod output are not described on any page opened for this audit. See [Unverified](#unverified).

### What this means for MORE

- The owner's routine language decides whether the feature is useful at all. A French morning has no Personal Voice on Apple's current list.
- A morning companion is not an assistive communication app. Apple's wording says "primarily", so a personal build is not excluded by the pages read here. A public release would need a view from App Review. The [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) page, as opened on 13 October 2026, does not mention Personal Voice.
- Personal Voice cannot deliver "a family member's voice". Apple limits it to the user's own voice.
- MORE never needs the synthesized audio as a file, so the capture restriction costs nothing.

### Checklist if it is ever offered

Nothing in this list is done.

1. Add a separate, explicit control such as "Use my Personal Voice". Do not request authorization at launch or when the picker opens.
2. Read `personalVoiceAuthorizationStatus` first. Show a distinct, truthful state for `unsupported`, `denied` and `notDetermined`.
3. Call `requestPersonalVoiceAuthorization` only from that control.
4. When access is refused or the setting is off, offer `AccessibilitySettings.openSettings(for: .personalVoiceAllowAppsToRequestToUse)`.
5. Change `SpeechCoordinator.isBuiltInVoice` so that a voice with `.isPersonalVoice` is accepted only when the user turned the control on and the status is `authorized`. Keep the check at queue time as well as at list time.
6. List personal voices in their own picker section, labelled as the user's Personal Voice. Never mix them into "Installed voices".
7. Keep the existing fallback: if the voice disappears or authorization is revoked, say so and use the automatic voice.
8. Do not call `write(_:toBufferCallback:)` with a personal voice. Do not store its audio.
9. Add package tests for the policy: off by default, excluded without authorization, fallback after revocation.
10. Add a purpose string only if the device test shows the system requires one.
11. Update [VOICE.md](VOICE.md), [CAPABILITIES.md](CAPABILITIES.md) and [PRIVACY.md](PRIVACY.md) in the same change.

### Device checks before it is offered

Record source revision, iPhone model, iOS version, language and outcome, as in the [verification record](PHASE-ONE.md). A simulator pass does not count.

| Check | Required outcome |
|---|---|
| Support | The owner's iPhone shows Settings → Accessibility → Personal Voice. Record the model, to settle the device disagreement above. |
| Language | A voice can be created in the language the routine is spoken in. Record what happens for French. |
| Status before consent | With no voice created, and with **Allow Apps to Request to Use** off, record the status value and whether a prompt appears. |
| Prompt | Record the exact system prompt text. Record whether the build runs without any new `Info.plist` key. |
| Listing | After authorization, the voice appears in `speechVoices()` with `.isPersonalVoice`. Record its identifier prefix, language and reported quality. |
| Audibility | A human listener confirms the voice is heard for a routine step, and that pause, resume and stop work. |
| Offline | With airplane mode on, the voice still speaks. |
| Locked or backgrounded | Record what happens when the phone locks or the app leaves the foreground during speech. |
| Routes | Record behavior on the built-in speaker, Bluetooth, AirPlay and a HomePod. |
| Revocation | Turn access off in Settings during and between sessions. Speech must fall back visibly, with no crash and no silent failure. |
| Deletion | Delete the voice in Settings. The saved identifier must be reported as unavailable. |
| Capture | Confirm no audio file is created by the app. |

## Siri voices

Apple's 2020 session states: "although Siri voices are available to be selected in Spoken Content Settings, they are not available through the AVSpeechSynthesizer API." When a Siri voice is the user's Spoken Content choice, the system picks a fallback voice in the same language. Source: [WWDC20 session 10022](https://developer.apple.com/videos/play/wwdc2020/10022/), iOS 14. This page predates iOS 26. No later Apple page opened here restates or withdraws it.

The current [AVSpeechSynthesisVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice) reference describes voices by language, locale and quality. It offers no Siri voice selector.

What the picker may truthfully show:

- Only voices returned by `speechVoices()`, under the name the system reports.
- The qualities the system reports: Standard, Enhanced, Premium.
- The existing sentence that Siri may use a different voice.

What it must not show: a row called "Siri voice", "the voice Siri uses", or any promise that the companion sounds like Siri. If a returned voice carries a Siri-like name on a given OS, it is shown under that reported name and nothing more is claimed.

## Custom voices

None of these options is implemented. The table records what each would require before work starts.

| Option | Rights and consent needed | Authorization and how to record it | Where processing happens | Removal and revocation | Cost | Status |
|---|---|---|---|---|---|---|
| The user's own Personal Voice | The user's own voice only, personal non-commercial use (Apple's terms above). | System prompt plus the Settings switch. The system stores the answer; the app stores only its own on/off choice. | On device, per Apple. Fits the local-only rule. | User revokes in Settings or deletes the voice. App falls back to the automatic voice. | No fee documented by Apple. | Not implemented. Excluded in code. |
| A relative's or friend's Personal Voice | Not available. Apple limits Personal Voice to the user's own voice, shared only across the same Apple Account. | None possible. | Not applicable. | Not applicable. | Not applicable. | Not offered. Must not be suggested. |
| Recorded phrases from a consenting relative or friend, played as audio, with no synthesis | Written consent from the speaker for this use, by this user, in this app. Likeness and data-protection points to be checked with counsel. | A dated consent record kept by the user outside the repository. The app shows who the voice belongs to and the consent date. | On device. Fits the local-only rule. Recordings stay out of Git, as AGENTS.md requires. | The speaker can withdraw. The app deletes the recordings and confirms the deletion on the Privacy screen. | Recording time only. | Not implemented. Covers fixed phrases only, not arbitrary routine text. |
| A synthesized voice built from a consenting relative's or friend's recordings | As above, plus explicit consent to voice synthesis of new sentences. Counsel should check voice-likeness rights and, for a speaker or user in the EU, how data-protection law treats voice recordings and voice models. | As above, plus the scope of what the voice may say. | Depends on the tool. No Apple API for cloning another person's voice was found in the pages read. A local model would fit the rule; a cloud service falls under the cloud row below. | Delete recordings and the voice model everywhere they exist, including at any provider. Confirm provider deletion in writing. | Unknown. No provider priced. | Not implemented. Feasibility not established. |
| A licensed performer voice installed as a system voice by another app | A license from the rights holder that covers this use. The other app's publisher holds it, not MORE. | The user installs that app. No authorization passes through MORE. | On device. Apple states voices from speech synthesis provider extensions are available to `AVSpeechSynthesizer`, and that network access is not allowed in speech synthesizers. Source: [AVSpeechSynthesisProviderAudioUnit](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisprovideraudiounit), iOS 16.0+. | The user removes the other app. The picker's existing "unavailable" message applies. | Set by the other app. | Not implemented. The `com.apple.` filter excludes these voices today. |
| A third-party cloud voice provider, stock or cloned | A provider license for the voice. For a cloned voice, the speaker's consent as above and the provider's own consent process. An imitation of an actor without a license is never offered. | Provider account held by the user. Consent and license references recorded by the user. No key or token in the repository. | Cloud. Spoken text would leave the device: step text, calendar titles, saved thoughts. Excerpts quoted from observed screens are screen content and may not be sent under the current rule. The rest conflicts with the rule unless the explicit opt-in below exists. | Delete the voice and data at the provider; revoke the key; turn the option off. Deletion terms must be read before enrollment. | Provider pricing, not checked. | Not implemented. |

### The local-only rule and what an explicit opt-in would require

[AGENTS.md](../AGENTS.md) says: "Keep Apple inference and screen content local. No silent remote-model fallback." It also says to label unavailable capabilities and to keep recordings, tokens and secrets out of the repository.

A cloud voice is a remote model. Two limits apply.

**Screen content stays local.** Text taken from observed screens, such as [saved moments](SAVED-MOMENTS.md) excerpts and quotations from recordings, is never sent to a cloud voice. An opt-in does not lift this. Sending it would need the owner to change the rule in AGENTS.md first; a setting is not enough. Such steps are spoken with the local voice.

**Everything else needs an explicit choice.** For text that is not screen content, a cloud voice may exist only as a separate, explicit choice:

- Off by default. A separate setting, not a row in the installed-voice list.
- The setting names the provider and states which text is sent, which text is never sent, and when.
- The user confirms before the first utterance is sent.
- Local speech never switches to the cloud on its own. If the cloud voice fails, the app says so and uses the local voice.
- A visible indicator shows when a cloud voice is speaking.
- Credentials are entered by the user and stored on the device, never in the repository.
- Turning the option off stops all sending at once. The Privacy screen lists what was stored and how to remove it.
- The choice is documented in [PRIVACY.md](PRIVACY.md) before it ships.

### Legal points

This audit states no legal rule. Before any voice other than an Apple system voice is used, counsel should check:

- Voice likeness and right of publicity for the speaker, in the speaker's and the user's jurisdictions.
- How data-protection law treats voice recordings and voice models for a user or speaker in the EU, and whether they count as biometric data in this use.
- The license terms of any performer voice, and the provider's terms on cloning, storage and deletion.
- Apple's "personal, non-commercial use" wording if MORE is ever sold.

## Unverified

Not confirmed from an Apple page opened for this audit, or only testable on the phone:

1. Whether a personal voice keeps speaking when the app is in the background or the phone is locked. The app declares no `audio` background mode; the effect of that on speech was not sourced.
2. Whether a personal voice plays over AirPlay or on a HomePod. Apple's support article mentions only the device speaker and calls.
3. Whether `write(_:toBufferCallback:)` returns audio for a personal voice. The developer reference is silent; the support article says apps cannot capture it.
4. Whether any `Info.plist` key is required. None is listed; no Apple page says none is needed.
5. The exact wording of the system authorization prompt.
6. Which status is returned when no voice exists or **Allow Apps to Request to Use** is off, and whether the prompt appears.
7. Where a per-app authorization is revoked in Settings, and what the app observes when that happens during speech.
8. Whether `availableVoicesDidChangeNotification` is posted when a personal voice is deleted.
9. Which iPhone models qualify. Two Apple pages disagree.
10. Whether French or any other language has been added since the pages were read. Only the owner's phone settles it.
11. The identifier prefix and reported quality of a personal voice. The `com.apple.` filter may or may not match it.
12. Whether synthesis with a personal voice works offline. Apple states the voice is generated on device; the speaking step was not separately sourced.
13. Whether Apple's developer reference pages reflect iOS 26 and iOS 27 without change. They carry no version label. The Xcode 27 SDK header agrees with them.
14. Whether the 2020 statement on Siri voices still holds on iOS 26 and 27, and whether any voice with a Siri-like name is returned by `speechVoices()`.
15. Whether App Review accepts Personal Voice in an app that is not an assistive communication app.
16. Whether the May 2025 announcement shipped exactly as announced.
17. The feasibility, quality and size of an on-device model that synthesizes another person's voice.
18. Every third-party provider's price, license, consent process and deletion terms. No provider was examined.
19. All legal points above.

Related guides: [Voice with MORE](VOICE.md), [Apple capabilities](CAPABILITIES.md), [Privacy & local data](PRIVACY.md).
