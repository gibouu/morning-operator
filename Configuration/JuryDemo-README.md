# Isolated jury app

`scripts/generate-jury-demo.sh` creates `MorningOperatorDemo.xcodeproj` from
`project.demo.yml`, which includes the current `project.yml`. The ordinary project,
Info.plist, sources and UX stay shared and are not rewritten by generation.
Only this build defines `MORE_JURY_DEMO` in the app, widget and UI-test targets.

The default identities are `com.gibouu.morningoperator.demo` and its child
`.liveactivity`; the visible app name is **MORE**, and links use `more-demo://`.
Separate signed bundle identities isolate the app container and default Keychain
access group. No Keychain sharing entitlement is added. Installing a newer jury
build updates only this app and preserves the normal MORE installation.

Copy `JuryDemo.local.xcconfig.example` to `JuryDemo.local.xcconfig` for signing,
backend URLs and a scoped demo backend token. That file is ignored. Provider
credentials for OpenAI, ElevenLabs and Composio remain on the backend.
`MORE_DEMO_API_BASE_URL` is the existing connected-services backend;
`MORE_JURY_DEMO_BASE_URL` is the jury conversation backend.

For a personal team without the normal restricted capabilities, set
`MORE_DEMO_ENTITLEMENTS_FILE = Configuration/JuryDemoPersonal.entitlements`.
This reduced build does not gain HealthKit, WeatherKit or Screen Time capabilities.
Use the regular entitlement file when the signing team has those capabilities.

Google native OAuth requires a separate iOS client registered for the demo bundle,
plus that client's distinct reversed callback scheme in the local configuration.
Reusing the normal app's callback would let iOS route login to the wrong app.
The default inert callback does not connect Google. Composio redirects must also
allow `more-demo://`; connecting either app does not transfer the other app's token.

The demo alone declares background audio and local-network access. A `.local`
Bonjour backend hostname is allowed over HTTP through `NSAllowsLocalNetworking`;
there is no global arbitrary-loads exception. Use HTTPS outside the local network.
Background audio permission is necessary configuration, not proof of continuous
microphone, speech, or Dynamic Island behavior; these require device verification.
The demo has its own localized privacy catalog so the microphone permission
accurately describes listening until the morning ends, including in the background.
Its source list mirrors the normal app with that catalog as the only substitution.

Build without installing:

```sh
scripts/build-jury-demo.sh
```

Build, install and launch on a specific connected device:

```sh
scripts/build-jury-demo.sh --install DEVICE_ID
```

The install script checks the built app and embedded widget identities, flag,
display name and deep link before installation. It refuses the normal bundle ID,
requires an identifier containing a `demo` component, and never uninstalls an app.
Use `DEVELOPER_DIR` if the active command-line developer directory is not Xcode.
`MORE_DEMO_DERIVED_DATA` optionally selects a separate build directory.
Builds use two parallel Xcode jobs by default; `MORE_DEMO_JOBS` overrides that limit.

The dedicated `JuryDemoJourneyTests` run against the shared app UX. The demo target
compiles only that test file; the ordinary target retains its complete UI suite:

```sh
xcodebuild -project MorningOperatorDemo.xcodeproj -scheme MorningOperatorDemo \
  -destination 'platform=iOS,id=DEVICE_ID' test
```
