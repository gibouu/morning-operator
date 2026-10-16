# MORE builds in Xcode Cloud

This repository preparation does not connect an account, grant GitHub access, upload a build or change the first TestFlight release. Connect MORE after that upload completes.

1. Open the checked-in `MorningOperator.xcodeproj` in Xcode 27 and create MORE's first Xcode Cloud workflow. Select the existing Apple team and app. Allow Apple's GitHub app to access only `gibouu/morning-operator`.
2. Use **Branch Changes → main** so each push to main starts a build. Select Xcode 27, a **Clean** environment, and the shared **MorningOperator** scheme. Do not regenerate the project with XcodeGen; the project is committed. The committed `Package.resolved` pins the restored ElevenLabs 3.4.0 conversation SDK and its transitive dependencies.
3. Add an iOS **Archive** action using Release and **TestFlight and App Store** distribution. Restrict workflow editing as required by Apple. Add an external TestFlight group as a post-action. External beta review and export compliance still apply; a successful archive alone does not mean testers can install it.
4. In MORE's Xcode Cloud **Settings → Build Number**, set the next number to at least **2026101634** (above **2026101633**) and above any newer build already uploaded for version 0.1.1. Xcode Cloud then increments it. Keep the app and widget on the same version/build.
5. Set the workflow environment values below, then run one build and inspect its archive configuration and TestFlight processing before relying on automatic delivery.

| Workflow variable | Requirement |
| --- | --- |
| `MORE_GOOGLE_CLIENT_ID` | Required public iOS OAuth client ID ending in `.apps.googleusercontent.com`. Use the same value as the manual release. |
| `MORE_GOOGLE_CALLBACK_SCHEME` | Required exact `com.googleusercontent.apps.` plus the client ID prefix before `.apps.googleusercontent.com`. |
| `MORNING_API_BASE_URL` | Optional. Leave absent or empty to match the current manual archive. If explicitly supplied, use a valid HTTPS base URL with no credentials, query or fragment. There is no production endpoint default. |

The executable `ci_scripts/ci_post_clone.sh` validates these values before changing the temporary cloud checkout's `Configuration/iOS-Info.plist`. It changes only `MOREGoogleClientID`, `MorningAPIBaseURL`, and the Google callback URL scheme. It does nothing outside Xcode Cloud and prints no configuration values. No Google client secret is used. Never put Composio, ElevenLabs, model-provider, signing or App Store Connect credentials in the app plist or this repository.

Xcode Cloud handles signing through the connected Apple team. This route does not require an App Store Connect API key in GitHub. The existing GitHub workflows run package checks and unsigned simulator builds; they do not archive or upload to TestFlight. An hourly Xcode Cloud schedule is an alternative to main pushes, not required for this setup.

Local script smoke checks: `python3 -m unittest discover -s scripts/tests -p test_xcode_cloud_config.py`.

Apple references: [first workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [GitHub connection](https://developer.apple.com/documentation/xcode/connecting-xcode-cloud-to-github), [distribution workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution), [custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [build numbers](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds).
