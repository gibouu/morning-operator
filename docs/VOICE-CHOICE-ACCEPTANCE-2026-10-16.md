# Voice choice and automatic speech recovery

16 October 2026 · [#20](https://github.com/gibouu/morning-operator/issues/20), [#116](https://github.com/gibouu/morning-operator/issues/116).

## Result

Settings → Voice contains Male / Female (Homme / Femme), a selected checkmark and one fixed example to listen to. The choice persists in the workspace across launches and language changes. No provider selector remains. Provider attribution stays in the privacy disclosure.

Ordinary readings use ElevenLabs TTS after agreement to share the selected text for that morning. A declined choice is remembered for the same morning. A new morning requires its own choice; resuming the same session keeps its decision. The fixed example sends only its bundled sample text and opens no microphone. Explicit Talk uses the existing conversation SDK and its separate microphone/context disclosure.

On a real synthesis, conversation or audio failure, release finishes before Apple continues the same pending app narration. Cancellation, stop, privacy/language/gender changes do not trigger a replay. Routine actions, service requests and provider captions are never replayed by speech recovery. Language changes clear obsolete synthesis callbacks. Cancelled release still clears obsolete SDK hooks.

Apple selects the requested language and available gender, prioritizing installed Premium, Enhanced, then Standard. If that combination is unavailable it can use the best available language voice. Neither a Premium download nor an audible gender is guaranteed without an installed-voice inventory and listener acceptance. Inference model selection remains unchanged by audio recovery.

## Combined source

The task branch includes current main's approved dotted-sun icon/model corrections and onboarding acceptance (#215), pending startup cancellation guards and physical language harness (`82aab35`), and connection support-code/SSO changes plus denied-Reminders recovery (`07c3dbf`). Merge conflicts retained both the new speech renderer/locale handling and the existing cancellation guards. No primary-checkout edits were included.

## Verified evidence

- **115 shared tests / ten suites passed** on `b0a1da9`: voice selection, interruption/release gates, cloud output, PCM decoding, SDK session, narration ledger, TTS client, workspace compatibility, model configuration and Composio service. No provider or microphone was used in this selection. Subsequent app-only lifecycle corrections are validated by the native checks below.
- Another **13 native-connection/Reminders tests / four suites passed** on `ab7d7dd`, whose tested service files remained identical on `3639b1a`. This gives 128 targeted shared tests across the two selections; it is not a claim that the whole package suite ran.
- Four existing synthetic provider MP3s (French/English × male/female) decoded through the production audio decoder's autodetected temporary format. No playback or new provider call was involved in that check.
- **51 backend Node/Workerd tests passed**. Worker `b623c00b-4c3a-4166-bae8-63cf75790278`, runtime source `e245094`, returned `200 audio/mpeg` and `no-store` for all four deployed synthetic combinations. Unauthorized, inactive and malformed requests retained their rejection gates. Existing secrets, database, catalog, journal and QA activation were preserved. Details: [backend delivery](../Services/Composio/CLOUDFLARE.md).
- Two synthetic SDK checks confirmed the gender override without a phone microphone. Provider model, prompt, tools and retention settings were preserved; only permission for the voice-ID override changed.
- French/English catalogs pass the repository's localization invariant check. Raw logs, audio, installation identifiers, deployment configuration and credentials remain private.

## Native and physical acceptance

**Seven simulator journeys passed across two runs.** The initial run on `bcb9c85` passed four: language changes pause the same session, both genders persist across relaunch/language changes without audio, day Settings retain their appearance, and French night Settings remain readable at the largest text size. Three test-navigation failures were retained in that run: a partly covered language selector, disclosure-content lookup and hidden Settings controls. Test-only corrections on `5260336` then passed the three targeted reruns: switching and persisting French/English with exactly two voice choices, reviewing conversation sharing before microphone access, and reviewing fresh reading consent for each new morning while retaining the same session's decision. No microphone or provider was used by these simulator journeys.

Final frozen `d0658df` ordinary iOS `build-for-testing` passed in 209 seconds. Its separate Demo build passed in 653 seconds with the expected `MORE_JURY_DEMO` setting. All 110 ordinary app and test-runner files remained byte-identical before and after the Demo build. These are compilation/isolation checks, not Demo runtime or real conversation acceptance.

The ordinary-phone installation is coordinated with the other native acceptance tasks to avoid concurrent replacement or audio. The phone's existing installation was subsequently activated through its displayed support code; backend version `35e47ab2` changed only the allowlist, preserving the tested TTS runtime. The physical harness distinguishes primary speech from the visible Apple-backup message; a speaking callback alone is insufficient to claim ElevenLabs playback.

**Physical primary speech failed on ordinary build `2026101622`, app source `786f1dd`.** All four French/English × male/female examples began and completed playback, but all four displayed the Apple-backup message and failed the primary-provider assertion. Language and gender persisted across relaunch, and original preferences were restored. The owner confirmed hearing the examples and rejected their voice quality. The installed inventory exposed only Standard voices for these combinations, with no Premium or Enhanced asset. This does not validate ElevenLabs in the app or satisfy perceived voice quality. See [physical evidence](LANGUAGE-VOICE-IPHONE-2026-10-16.md).

Read-only backend diagnosis on `35e47ab2` independently returned `200 audio/mpeg` for all four approved synthetic QA combinations and `200` for a conversation token. Its two approved installation IDs matched the canonical private configuration. A recent activation request belonged to a different installation. The client currently includes its absolute workspace/container path in the Keychain account; a changed path can therefore create a different identity. The phone's current support-code correlation must establish the actual cause before another physical primary test. No allowlist or provider setting was changed during this diagnosis.

Provider connectivity and synthetic audio alone do not establish audible phone playback, recognition or perceived naturalness. Personal Health sharing and microphone permission remain the owner's explicit decisions.
