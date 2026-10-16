# Get started with MORE

15 October 2026. The full-screen solar/weather Home is tracked in [PR #170](https://github.com/gibouu/morning-operator/pull/170); use the ordinary **MORE** app. The latest final-install checkpoint is in [#171](https://github.com/gibouu/morning-operator/issues/171). The current shared story is in [demo requirements](DEMO-REQUIREMENTS.md); [the iOS team guide](IOS-TEAM-GUIDE.md) maps features and ownership. Older screenshots and historical phone checks do not establish current behavior.

Home opens with a full-screen dotted sky. The large sun or crescent crosses a shallow arc around the middle of the screen; a fine printed dot texture covers the uniform background, stars span the night sky, and four slightly larger trees stay near the bottom. Touch the sky anywhere to reveal **Begin**, **My routine** and **Settings**; use Close or the exposed sky to hide the menu. My routine opens Learn when no routine exists and the routine editor otherwise. Opening controls never starts playback.

Select the city in **Settings → Your day** for locally calculated sunrise/sunset and Apple Weather current conditions. The iPhone's date/time zone controls the sun/moon; weather changes the clouds, rain/snow/ice, fog/haze, wind and printed storm details. All 34 current WeatherKit condition cases map explicitly to drawing parameters. Conditions remain temporary, reuse the briefing's source/cache, and expire with the provider or the shared 30-minute limit. Backgrounding stops the Home refresh loop. Clouds drift at different speeds; stars brighten slowly and a short shooting star occasionally crosses a clear night. Rain, floating snow, wind and haze move gently; rain adds small ground ripples. Decorative time never advances the sun or moon. Covered/background Home freezes and resumes the same decorative pose; Reduce Motion keeps the entire scene still and omits shooting stars. No device location is requested.

Without a city, the menu explains the approximate 07:00–19:00 reference solar cycle. Without current weather, the art keeps its clock and adds no invented weather effects; the menu reports missing/unavailable data. Weather provider credit and the legal source link live in Settings → Your day, beside the weather connection; Home, its controls and playback show no provider branding. DEBUG weather previews remain labelled as samples. Apple explicitly rejected WeatherKit provisioning for the current free Personal Team. The source is ready for the owner’s enrolled Apple Developer team; follow [WeatherKit setup](WEATHERKIT-SETUP.md) to enable the App ID/service and regenerate its profile. Simulator previews are not live weather proof.

## First setup and morning

1. Open **Learn → 1 · See your rhythm → Connect Screen Time**. Authorize deliberately, inspect the dates/coverage returned and review the proposal's estimated order and minutes. Empty, denied and failed are different outcomes. Screen Time does not reveal every tap, message or scroll.
2. Optionally record/import a short harmless observation. Review extracted text, original samples, observed date, time zone and personal/test origin. Unknown dates stay unknown until corrected. Recording/OCR and Screen Time proposals are separate; neither approves itself.
3. Review and edit the routine's moments, order, supported destinations and budgets. **Approve** saves the plan. One routine is reused each day; later edits produce a draft requiring approval. A running/paused morning keeps its approved version.
4. Use Learn's **Make yourself at home**, or **Settings → Your websites**, for supported website sign-ins. Sign in on each provider's visible page. “Ready” is your confirmation; it is not an automatic credential check. Chosen-site setup currently needs durable storage (#157), so this queue is not yet a proven resumable onboarding checklist.
5. In **Settings → Your websites → Connect Gmail**, complete Google's consent once. A valid saved connection restores without a new sign-in on each page. Read selected unread messages, then optionally **Prepare reply → edit → Copy reply**. No mail is sent or saved as a provider draft. See [Gmail reading](GMAIL-READING.md) for size, privacy and inference limits.
6. In Settings, configure **Your day** for selected calendars and an optional city. A Google calendar already synced into iOS Calendar can use EventKit; there is no direct Google Calendar connector yet. Choose one route per calendar to avoid duplicates. Health is not linked into the app today. Current weather is not a full-day forecast.
7. Return **Home → touch the landscape → Begin** with an approved routine. Begin starts the saved routine; without a routine it opens Learn. Opening the menu alone does not start a run. An active or paused run has its own controls. There is no source hour cutoff, but late-start/resume discoverability remains #154. Do not change the design to address it in the connection workstream.
8. Use MORE normally. Supported speech can finish its own operation; unconnected external activities wait for the owner. A supported app handoff keeps one saved timer. +2/Next, lock/background/return and actual external targets require their own phone acceptance. Ordinary narration pauses when MORE backgrounds; a target timer can continue. Timer expiry does not prove a lesson ended or force another app forward.
9. Finish and inspect the recap. Optional reflection is reviewed before Save; opening an invitation does not start the microphone. Planned time, routine elapsed time and observed app use are different measures.

For the hackathon acceptance use [DEMO-TEST-PLAN](DEMO-TEST-PLAN.md): actual permissions and sources, no test arguments, no seeded routine, no Shortcuts automations tapping through the story. Synthetic fixtures remain useful engineering checks and stay labeled separately.

## Recording, privacy and models

Native capture offers 5, 10, 20 or 30 minutes with a monitored 256 MiB stop. The periodic monitor is not an exact hard byte ceiling. Selected-video import is at most 31 minutes/512 MiB and samples up to 24 frames. Long text analysis does not mean continuous video coverage or measured scrolling speed. Review what the app actually retained.

Open **Settings → Privacy & data** to inspect retained categories and the full local Forget control. Confirming Forget removes app-owned state/copies and the saved Gmail credential; incomplete cleanup blocks ordinary work and can be retried. Originals in Photos/Files, exported files, Apple-app items, account grants and backups remain separately managed. Do not reset the owner's data to perform a test. [Exact privacy scope](PRIVACY.md).

Current inference uses Apple's on-device model when available. Check its availability message; hardware, language, region, settings and model readiness matter. Unavailable inference is not an empty result. An optional iOS 27 beta PCC route needs separate entitlement, explicit selected cloud inputs and real-device evaluation before it can be enabled. [Model plan](APPLE-MODEL-PLAN.md).

## Set up a development Mac

Clone the repository with your own GitHub access. Never put tokens in repository URLs or files.

```sh
git clone https://github.com/gibouu/morning-operator.git
cd morning-operator
git switch main
./scripts/check-environment.sh
./scripts/test.sh
open MorningOperator.xcodeproj
```

Use full Xcode compatible with the phone and the guarded APIs being built; the observed setup used Xcode 27 and iOS 27.0.1. Select Xcode's command-line tools and finish first-launch setup. Deployment targets do not prove every older OS/hardware combination. The environment script exits 2 if full Xcode is unavailable; package checks are a separate result.

Choose the **MorningOperator** scheme, paired/unlocked phone and your signing team for the app and embedded **MorningActivityWidget**. Resolve required WeatherKit/Screen Time provisioning for the intended features. Do not commit team/device settings, signing profiles or credentials. XcodeGen is needed for project regeneration/device-test tooling, not for opening the checked-in project. Review generated diffs after changing `project.yml`.

The repository's Google defaults are inert. Each developer configures a matching iOS OAuth client/callback locally; there is no iOS client secret. Canonical configuration locations and override names are in `AGENTS.md`. This developer setup is not the end user's path: users connect Gmail in MORE on their iPhone.

## Review and evidence

Reserve shared files before parallel work. UI owns presentation; domain owners own permission, persistence and lifecycle behavior. Keep Core independent of UI/providers, one authoritative workspace writer, bounded values crossing adapters, and expected revision/privacy/session bindings on asynchronous results. See [modules and contracts](IOS-TEAM-GUIDE.md#eight-logical-modules-and-team-ownership).

A pull request explains the user problem, source baseline, meaningful before/after behavior, relevant tests and remaining phone/provider gates. Use the issue's acceptance criteria, a focused diff and independent review. Before merging, compare current main with older overlapping branches and preserve compatible saved data; a clean build alone is not behavior proof.

`./scripts/test.sh --with-model` deliberately opts into available local-model checks. Skips remain skips. Record commit, build, device/OS, actual route, result and failure/skip reason using [the report template](TEST-REPORT-TEMPLATE.md). Keep recordings, inbox text, tokens, personal screenshots and result bundles out of shared issues. [Historical verification](PHASE-ONE.md) retains earlier results at their original scope.

The verified phone checkpoint before final-main delivery was MORE 0.1.0 (1522), from PR #170. Subsequent merge/install results are recorded in [#171](https://github.com/gibouu/morning-operator/issues/171). In-place installation, the installed version and ordinary launch were verified on 15 October after the owner unlocked the phone. The following provider acceptance notes are separate historical evidence. The previous ordinarily launched checkpoint was MORE 0.1.0 (1519). Owner-confirmed Gmail reading and Screen Time proposal approval are partial evidence. Reply generation/copy, ring/Siri/Lock Screen controls and a completed normal morning remain individually unconfirmed. The documentation audit ran no app builds, tests, provider calls or new phone checks.
