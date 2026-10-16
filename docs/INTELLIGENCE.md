# Intelligence and personal memory — 16 October 2026

MORE already called Apple's Foundation Models for routine proposals, contextual questions and drafting. The old prototype still depended on Apple model readiness and had no durable personal-fact memory. Speech uses Apple by default; the separately consented ElevenLabs conversation can also narrate app-prepared answers.

## Explicit model route

Settings → **Intelligence & memory** selects OpenAI with the owner's personal API key and an explanation of the text shared. Apple remains the default. GPT-6 Luna (`gpt-6-luna`) uses the Responses API with `reasoning.effort: high`, strict JSON Schema for routine proposals and memory extraction, and `store: false`. This model and effort were explicitly selected by the owner on 16 October 2026. Model failure is surfaced without silently switching provider. Credentials stay in the installation Keychain and outside shared source/build settings. This is a personal development setup; a shipped multi-user app must put its provider key behind an authenticated backend.

The selected route is used by:

- routine analysis/proposals, preserving app-owned exact citations, dates, source revisions and saved exclusions;
- contextual voice answers, connected-result narration and preparation of selected account-action arguments;
- Gmail reply/revision/self-message composition and Slack reply composition;
- extraction of explicit personal facts and one optional contextual weather suggestion.

The model has no execution authority. Existing routine validation, explicit send instructions, service permissions and uncertain-effect reconciliation still own execution. Video extraction and screen-label classification stay local. This route sends bounded text, not raw media. Local-only operation never falls back to a remote provider.

## Personal corrections and proactive advice

Direct owner statements can produce short, source-quoted facts and preferences. Stable keys let the next statement replace an earlier fact. The bounded journal retains 24 recent facts, can be reloaded after relaunch, and is visible/individually removable in Settings. It does not train a model or store a raw voice transcript. Unsupported or ambiguous extraction leaves memory unchanged. Mail/page context never becomes an owner declaration.

The same extraction accepts final microphone transcripts from an explicitly started ElevenLabs conversation, even without an active morning. It follows the existing model choice and OpenAI consent; it never silently enables OpenAI or sends the saved memory to Gemini. MORE's narration and the agent's responses cannot teach personal facts. App-delegated contextual answers reuse the selected model and memory without extracting the same utterance twice. General OpenAI context excludes sleep and the other selected Health measurements; consented ElevenLabs narration remains a separate route.

For example, “I have an electric scooter” followed by “I don't have an electric scooter; I take public transport” removes the earlier assumption. A new commute correction can invalidate an old transport fact without inventing ownership. Other explicit facts, such as a coffee preference, use the same model extraction and correction mechanism.

An enabled OpenAI route can add one short suggestion after the actual weather in an opening or a morning briefing. Missing/stale weather never triggers this suggestion. Source facts stay deterministic and attributed; the model supplies advice. It cannot assume equipment or commute, invent a daily forecast from current conditions, or claim it performed an external action. Source changes, cancellation and privacy generations are checked again before speech. Advice failure leaves verified source facts readable.

## Product state against MORE.md

| Promise | Current state and evidence boundary |
| --- | --- |
| Understand a routine from three sources | Common cited proposal exists. Screen Time is aggregate data; video samples at most 24 OCR frames; browser learning records coarse sequence/gestures/timing. Accuracy across several complete personal mornings remains unaccepted. |
| Run the routine | Session pinning, budgets, pause/resume and selected real reads/actions exist. See [runtime QA](ROUTINE-AUTOMATION-QA.md) for public Reddit, Gmail reading and Apple reminder evidence. A full personal morning across all connections remains unaccepted. |
| Instagram like the native app | A persistent WKWebView loads the mobile website. Login is not proof of stories, Reels, likes or native UX parity. Authenticated acceptance remains open. |
| Browser reasoning | Current execution uses DOM rules/site-specific scripts, not an LLM observe–act–verify loop. Adding OpenAI to understanding does not complete that agent. |
| Intelligent personal voice | Selected-model answers, bounded personal memory and weather advice are wired. Real microphone/barge-in, latency and repeated on-phone correction journeys still need separate acceptance. |
| Weather forecast | Current WeatherKit conditions are supported. Daily minimum/maximum and forecast-based advice are not established by this slice. |

Remaining real-device and browser acceptance is tracked in [#200](https://github.com/gibouu/morning-operator/issues/200), alongside the broader runtime work in #173.

## Verification

Ordinary voice follow-up on 16 October 2026: a weather question after the opening could lose the already prepared weather during a note or timer. The conversation now reuses only fresh, still-authorized weather, without another provider read, duplicate briefing or Health context. **54 targeted tests in 4 suites passed** (`more-conversation-weather-tests-retry.log`), covering admission, expiry, changed sources, privacy invalidation, personal memory and continuation. Physical microphone/correction/relaunch acceptance remains pending; these package tests do not establish it.

After integrating the current voice changes, **96 tests in 9 suites passed** in 8.179 seconds (`more-voice-weather-integrated-tests.log`); signed build-for-testing 2026101627 succeeded. Two read-only physical inspections passed on the existing ordinary build 2026101622, without fixture arguments or reinstalling MORE. Removing local `DependentProductPaths` from the private destination-only XCTest plan fixed its initial launch failure. Home showed no active morning and the app language was English. No speech was played, no fact or preference was changed, and no correction/relaunch acceptance is claimed. The owner subsequently stopped further testing in favor of a single final delivery/install; that install belongs to the delivery coordinator. The complete acoustic weather/correction/persistence journey remains tracked in [#200](https://github.com/gibouu/morning-operator/issues/200).

The opt-in live test uses harmless synthetic routine text, weather and personal statements. It creates a private temporary workspace and never reads connected accounts, recordings or real inboxes. Run it only with an explicitly supplied credential-file path:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
MORE_OPENAI_LIVE_KEY_FILE=/absolute/private/path/to/key \
./scripts/test.sh --jobs 2 --filter MoreIntelligenceLiveTests
```

Normal package tests skip the live test. Protocol tests use in-memory credentials and injected transports. A successful provider call is not proof of an acoustic or browser journey.

GPT-6 Luna migration verification on 16 October 2026, source `a4cfc0d`: **36 targeted tests in 4 suites passed** in 19.529 seconds (`more-luna-high-tests-retry.log`), including real OpenAI routine proposals, personal corrections after reload and weather advice. The protocol test checks the exact model and high reasoning in every captured request. A separate real Responses probe returned `model: gpt-6-luna`, `reasoning.effort: high`, and `status: completed`, with a French suggestion from synthetic weather/transport facts. The signed ordinary iPhone build succeeded (`more-luna-high-device-retry.log`), was installed, launched and its running process verified. The microphone journey was not replayed. Only documentation changed in the subsequent main merge.

Earlier GPT-5 mini delivery verification on 16 October 2026, source `dc130ca` (including the persisted language preference from main):

| Check | Observed result and limits |
| --- | --- |
| Targeted package selection with real OpenAI opt-in, combined source | **160 tests in 19 suites passed**: 149 Apple tests in 17 suites (11.773 seconds) and 11 Core tests in 2 suites (0.019 seconds), with the command exiting successfully (`more-intelligence-integrated-targeted.log`). The live test proposes an unapproved calendar/mail routine with valid source citations; corrects scooter ownership from yes to no and saves public transport; replaces a coffee preference; reloads the saved facts; then suggests waterproof clothing and an umbrella for synthetic rain at 7 °C, respecting public transport and without inventing a scooter. The model receives synthetic text only; this does not establish real WeatherKit data, personal morning accuracy or microphone recognition. |
| Signed iPhone build, combined source | **BUILD SUCCEEDED** (`more-intelligence-device-integrated.log`). The ordinary app was installed in place, launched, and its running process verified. The explicitly enabled development provisioning path stores the supplied credential in Keychain; credentials and phone identifiers remain private. Installation/launch does not establish an on-phone provider call, acoustic interruption or a complete routine. |
| Simulator app, widget and UI-test target | Built successfully in the integrated UI run below, with generated simulated signing entitlements for real Keychain access. The earlier unsigned build compiled but could not exercise credential storage. |
| Intelligence & memory settings UI, combined source | **2 native UI tests passed, 0 failures, 126.704 seconds** (`more-intelligence-settings-integrated.log`). Explicit activation, return to Apple and credential deletion were exercised with a synthetic key and no provider call, in English and French with the largest accessibility text. Both screenshot attachments were inspected. |
| Earlier broad package verification | **694 Core tests in 78 suites** and **4 Health mapping tests passed**. The broad Apple run recorded three city-race fixture wait failures; all three passed unchanged in an earlier 118-test serial selection, before the final main merge. A full serial rerun was stopped after stalling, with a process sample in TextRecognition/ANE model compilation. No completed full Apple-suite pass is claimed. Reproducibility and bounded diagnostics are tracked in [#204](https://github.com/gibouu/morning-operator/issues/204), separately from product acceptance. |

Full-run local evidence is retained in `more-intelligence-package-tests-final.log`, `more-intelligence-package-serial-live.log` and `more-intelligence-tests.sample`. The city-race failures and the stalled process remain part of the record; targeted passing results do not erase them. Real-iPhone correction/relaunch, voice latency/barge-in, sourced daily advice and authenticated browser execution remain [#200](https://github.com/gibouu/morning-operator/issues/200).

Official API references: [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna), [structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [data controls](https://developers.openai.com/api/docs/guides/your-data).
