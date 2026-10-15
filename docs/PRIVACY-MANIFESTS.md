# Required-reason API manifests

Audited 16 October 2026 against `d671826`. These manifests describe required-reason API use. They do not establish App Store approval, distribution entitlement approval, or the App Store Connect data-collection answers. No tracking or collection declarations are inferred from this API audit.

## Reasons and source evidence

| Apple category and approved reason | Actual use |
| --- | --- |
| File timestamp · `C617.1` | App-owned workspace locks and safe local file handling (`MorningCore/LocalDataControl.swift`); app-owned recording recovery, cleanup and session files (`MorningApple/PendingScreenRecordingStore.swift`, `RecordingFileCleanup.swift`, `RecordingSessionStore.swift`). These use `stat`, `fstat`, `lstat` or `fstatat` for type, size, identity or change checks. |
| File timestamp · `3B52.1` | `MorningApple/ObservationFileFingerprintService.swift` uses `fstat`/`lstat` and modification/change timestamps to detect a change while reading a file explicitly supplied by the user. Its caller obtains the file through the import picker; security-scoped access is bounded to the read. It also accepts app-owned recordings, covered by `C617.1`. This identifies file contents, not a device or person. |
| System boot time · `35F9.1` | `MorningOperator/WebMorningController.swift` subtracts `ProcessInfo.systemUptime` readings to measure an explicitly started browser lesson and enforce its 15-minute cap. It retains elapsed duration, not a device boot timestamp. |
| User defaults · `CA92.1` | `MorningOperator/WebMorningView.swift` stores the browser explanation preference with `@AppStorage`; `MorningApple/GmailCredentialStore.swift` stores an installation marker, and `NativeConnectionsService.swift` stores configured shortcut names in app-local defaults. `MorningSharedActivity/AddStepTimeIntent.swift` and `MorningOperator/StepTimerView.swift` additionally use app-local defaults for DEBUG-only QA outcomes. No defaults suite/app group, other-app values, or managed configuration is used. |

The audit found no direct disk-capacity or active-keyboard required-reason API use in `Sources`. Individual file-size checks are not disk-capacity checks. Tests and fixture apps are outside the shipped MORE app/widget target scope.

## Bundle coverage

- `Sources/MorningOperator/PrivacyInfo.xcprivacy` covers the app executable, including linked shared-code file checks, defaults and the app-only elapsed-time measurement.
- `Sources/MorningActivityWidget/PrivacyInfo.xcprivacy` covers the widget executable's timer-related local file checks and shared DEBUG defaults. The widget does not run browser learning or import user-selected media.
- `Sources/MorningCore/Resources/PrivacyInfo.xcprivacy` covers Core's local file checks.
- `Sources/MorningApple/Resources/PrivacyInfo.xcprivacy` covers Apple's local/imported file checks and local defaults.

The app and widget files are in their Copy Bundle Resources phases in the checked-in Xcode project. `project.yml` includes each target's source directory, so XcodeGen also finds these resource files. The shared package already declares `.process("Resources")` for Core and Apple in `Package.swift`; each package manifest is copied into its own resource bundle. Do not place either package manifest at the app root, where its filename would conflict with the app manifest.

## Verification

Build the ordinary Release targets without a signing identity:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MorningOperator.xcodeproj -scheme MorningOperator \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/privacy-manifest-check CODE_SIGNING_ALLOWED=NO build
```

Check the built app root, `PlugIns/MorningActivityWidget.appex` root, and the Core/Apple resource bundles in the app and extension. Each `PrivacyInfo.xcprivacy` must be a valid property list and contain its expected categories/reasons. This verifies packaging only; a signed archive and App Store Connect validation remain separate release checks.

Apple sources: [required-reason API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [required-reason rules](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), and [manifest placement, including Swift package resources](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).
