# MORE builds in Xcode Cloud

On 16 October 2026, MORE's Xcode Cloud connection to `gibouu/morning-operator` is saved for the existing Apple team and App Store Connect app. Main-branch changes automatically produce Release archives and App Store Connect uploads: cloud builds **2026101635** and **2026101636** both upload and finish Apple processing. Both builds show **Missing Compliance**, so external TestFlight delivery remains blocked. [Issue #263](https://github.com/gibouu/morning-operator/issues/263) tracks that remaining export-compliance work.

## Saved connection and workflow

| Setting | Saved value |
| --- | --- |
| Apple team / app | `U6Z87CS4W3` / MORE, App Store Connect ID `6823382969` |
| Cloud product | `58b1bc4f-96e2-464d-b0ba-5ff8296f4046` |
| Workflow | **Main → TestFlight**, ID `7C7653A8-B4A9-4A33-9357-FE7D75414C14` |
| Source / start condition | `gibouu/morning-operator`; **Branch Changes → main**, any changed file |
| Automatically cancel builds | Off |
| Restrict Editing | On |
| Clean environment | On; verified in the web workflow settings |
| Xcode / scheme | Xcode **27 (27A266a)** / shared **MorningOperator** scheme |
| Distribution action | iOS **Archive**, Release, prepared for **App Store Connect** distribution |
| Post-action | External TestFlight group **MORE – External testers**; currently zero members |
| Public Google configuration | Both required workflow variables below are set |
| Optional backend | `MORNING_API_BASE_URL` is absent |

The checked-in `MorningOperator.xcodeproj` is the build entry point. Do not regenerate it with XcodeGen in Cloud. Keep the GitHub connection limited to this repository.

PR #261 restores the ElevenLabs **3.4.0** conversation SDK on `main`, with its transitive LiveKit dependencies. The committed `MorningOperator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` pins those dependencies and must remain available to Cloud. This supersedes the earlier SDK-free dependency guidance.

## Build numbers and release evidence

The first default cloud build, **1**, ran the default iOS **Build** action at `3cae09c` before the workflow variables were set. Its `ci_post_clone.sh` step failed with `MORE_GOOGLE_CLIENT_ID must be a valid public iOS Google client ID.` Both required public Google variables are now saved. Build **2026101635** passes public configuration and dependency checks, then completes the Release archive and upload.

The separately uploaded **0.1.1 (2026101633)** passed Apple processing and remains **Waiting for Review** for external TestFlight. Its frozen archive remains SDK-free. Another separately uploaded **0.1.1 (2026101634)** is observed as **Complete / Ready to Submit**. Neither upload proves that this cloud workflow succeeds. This setup does not replace build 33's pending beta review or submit an App Store customer release.

**Settings → Build Number → Next Build Number** was saved as **2026101635**, with App Store Connect's success confirmation. The next main merge received that number; the following main merge received **2026101636**. Xcode Cloud increments subsequent build numbers. Keep them above any newer manually uploaded build for version 0.1.1, and keep the app and widget on the same version/build.

The following results are verified in the Xcode Cloud and App Store Connect web interfaces:

| Cloud build | Exact source | Archive / upload / Apple processing | TestFlight state |
| --- | --- | --- | --- |
| `2026101635` | `8d63e9a5`, PR #261 | Complete | Missing Compliance; external post-action fails with `Missing encryption compliance declaration` |
| `2026101636` | `6d6d374d`, PR #265 | Complete | Missing Compliance; external availability remains blocked |

This proves the automatic main-branch trigger, archive, upload and Apple processing path. The downloaded build 35 App Store IPA has SHA-256 `63161747f987e4cf952eb7990c57142d0d68c6db6c4f61b884f1384c50c3c863`. Independent inspection passes strict Apple Distribution signatures, team and App Store profiles, matching app/widget `0.1.1 (2026101635)` versions, expected entitlements, base/English/French permission text and ten privacy manifests. The actual binary links the restored SDK frameworks and includes WebRTC crypto. The download contains no dSYM, so no symbol-match result is claimed. Build 36 has upload/processing evidence only; build 33 remains separate.

Build 33's OS-only encryption evidence applies only to its frozen SDK-free binary. Future builds from `main` contain SDK code and need an export-compliance assessment of their actual signed contents and truthful App Store Connect answers. PR #261 removes the `ITSAppUsesNonExemptEncryption = false` assertion from the source; do not carry build 33's conclusion into these builds automatically.

In build 35's **Manage** flow, selecting standard encryption outside the Apple operating system and distribution in France displays Apple's requirement to upload export-compliance documentation and obtain approval before receiving a compliance key. The draft answers were not saved. The French encryption declaration and Apple's approval remain the external-delivery blocker in #263; no exemption or approved compliance key is claimed. See [Apple's encryption documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption).

## Workflow environment

| Workflow variable | Requirement |
| --- | --- |
| `MORE_GOOGLE_CLIENT_ID` | Required public iOS OAuth client ID ending in `.apps.googleusercontent.com`. Use the same value as the manual release. |
| `MORE_GOOGLE_CALLBACK_SCHEME` | Required exact `com.googleusercontent.apps.` plus the client ID prefix before `.apps.googleusercontent.com`. |
| `MORNING_API_BASE_URL` | Optional. Leave absent or empty to match the current manual archive. If explicitly supplied, use a valid HTTPS base URL with no credentials, query or fragment. There is no production endpoint default. |

The executable `ci_scripts/ci_post_clone.sh` validates these values before changing the temporary cloud checkout's `Configuration/iOS-Info.plist`. It changes only `MOREGoogleClientID`, `MorningAPIBaseURL`, and the Google callback URL scheme. It does nothing outside Xcode Cloud and prints no configuration values. No Google client secret is used. Never put Composio, ElevenLabs, model-provider, signing or App Store Connect credentials in the app plist or this repository.

Xcode Cloud handles signing through the connected Apple team. This route does not require an App Store Connect API key or an exported signing key in GitHub.

The existing GitHub workflows remain separate checks for packages, app compilation and simulator UI tests. Their app/UI jobs use GitHub's supported **`xcode-27` hosted preview** label; a queued job does not establish an unsupported label or require a self-hosted runner. Those workflows do not sign an archive or upload to TestFlight. Xcode Cloud runs its own Apple-managed build after changes reach `main`; an hourly schedule is not configured or required.

## Remaining release checks

- Resolve **Missing Compliance** for the SDK-containing builds, including the French encryption declaration and Apple approval for distribution in France, using their actual contents and truthful App Store Connect answers. Track the blocker in [#263](https://github.com/gibouu/morning-operator/issues/263). Do not restore a false OS-only encryption assertion to bypass it.
- After compliance is resolved, retry the external TestFlight post-action and verify its result and the resulting beta-review state. External availability and installation are still unverified. Build 33 keeps its separate pending review.
- Keep each release tied to its actual signed artifact. Build 35 passes the independent IPA checks above; symbol matching and independent inspection of later binaries remain separate checks.

## Troubleshooting

On 16 October, navigating Xcode's Cloud interface caused an internal navigation assertion and a desktop-app crash. Use **App Store Connect → MORE → Xcode Cloud** in the browser to manage the workflow and inspect its logs. The saved connection, build numbering and main trigger are verified through that web interface. Inspect the cloud build's own result separately from the local Xcode crash.

Local script smoke checks: `python3 -m unittest discover -s scripts/tests -p test_xcode_cloud_config.py`.

Apple references: [first workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [GitHub connection](https://developer.apple.com/documentation/xcode/connecting-xcode-cloud-to-github), [distribution workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution), [custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [build numbers](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds).
