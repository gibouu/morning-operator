# Enable real Apple Weather on an iPhone

The app already calls native WeatherKit for the deliberately selected city. A paid Apple Developer Program team must authorize and sign that app; a Personal Team cannot enable WeatherKit. This guide prepares a WeatherKit-only build without requiring the unrelated Screen Time capabilities. It does not establish a successful live weather response.

## Paid-team owner

An Account Holder or Admin enables the App ID services. The person building must have access to that paid team's Certificates, Identifiers & Profiles in Xcode; otherwise the owner builds and installs the app themselves. Do not share Apple passwords, certificates or private keys in Git or chat.

For an **organization** membership, invite the builder to the developer team and grant Certificates, Identifiers & Profiles access. For an **individual** membership, an App Store Connect invitation does not grant that developer-team access: the paid Account Holder must perform signing. [Apple's role rules](https://developer.apple.com/help/account/access/roles).

1. Sign in to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), select the paid team and open the explicit App ID for `com.gibouu.morningoperator`.
2. Enable **WeatherKit** in **Capabilities** and in **App Services**, save and confirm both changes. Apple requires both selections. Update or regenerate the development provisioning profile after changing the App ID; an older cached profile is insufficient. [Apple's steps](https://developer.apple.com/help/account/identifiers/enable-app-capabilities).
3. In full Xcode, add the authorized Apple account under **Settings → Accounts** and select the paid team for **MorningOperator** and **MorningActivityWidget**. Keep automatic signing enabled. Register the intended phone with that team if required, and complete Trust/Developer Mode prompts on the unlocked phone.

The checked-in default entitlement file also requests Screen Time access. The optional [WeatherKitOnly.xcconfig](../Configuration/WeatherKitOnly.xcconfig) below substitutes [WeatherKitOnly.entitlements](../Configuration/WeatherKitOnly.entitlements) for the **MorningOperator app only**. The widget, test targets and package resource bundles receive no custom entitlement file. It does not change the project's default entitlements or enable Screen Time.

If the paid team cannot use the existing bundle ID, stop before replacing the installed personal app. Changing team or bundle ID can prevent an in-place update and access to the existing data/keychain. Keep the personal app installed; use a separate local bundle ID and matching widget suffix for a side-by-side trial, or arrange an explicit transfer/migration. Do not uninstall the personal app to resolve a signing error. Keep account, bundle and Google OAuth overrides outside shared configuration.

## Build and provision

Run from the repository root with full Xcode selected explicitly. Replace the two placeholders locally; do not commit their values. The optional override is supplied with `-xcconfig`, so regenerating or changing the checked-in project is unnecessary.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
MORE_PAID_TEAM_ID='YOUR_PAID_TEAM_ID'
MORE_DEVICE_ID='YOUR_DEVICE_ID'
MORE_DERIVED_DATA="$PWD/.build/weatherkit-owner"

xcrun xcodebuild -project MorningOperator.xcodeproj \
  -scheme MorningOperator -configuration Debug \
  -destination "platform=iOS,id=$MORE_DEVICE_ID" \
  -derivedDataPath "$MORE_DERIVED_DATA" \
  -xcconfig "$PWD/Configuration/WeatherKitOnly.xcconfig" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$MORE_PAID_TEAM_ID" build
```

`-allowProvisioningUpdates` lets Xcode update signing resources using the authorized account. A permission or provisioning error is a blocker, not a reason to remove the entitlement. Native WeatherKit needs no REST key or server token.

To inspect every project target before provisioning:

```sh
xcrun xcodebuild -project MorningOperator.xcodeproj -alltargets \
  -configuration Debug -sdk iphoneos \
  -xcconfig "$PWD/Configuration/WeatherKitOnly.xcconfig" -showBuildSettings
```

`CODE_SIGN_ENTITLEMENTS` must resolve to `Configuration/WeatherKitOnly.entitlements` under the repository root for **MorningOperator**, and to empty for **MorningActivityWidget** and the other targets. Confirm `CODE_SIGN_STYLE = Automatic`. Do not pass a global `CODE_SIGN_ENTITLEMENTS=...` argument: it would also reach the widget and resource bundles.

## Verify signing before installation

Keep these outputs local; the provisioning profile contains team and device information.

```sh
MORE_APP="$MORE_DERIVED_DATA/Build/Products/Debug-iphoneos/MorningOperator.app"
mkdir -p work/weatherkit-owner
codesign --verify --deep --strict "$MORE_APP"
codesign -d --entitlements :- "$MORE_APP" \
  > work/weatherkit-owner/signed-entitlements.plist 2> work/weatherkit-owner/signature.log
security cms -D -i "$MORE_APP/embedded.mobileprovision" \
  > work/weatherkit-owner/profile.plist
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.weatherkit' \
  work/weatherkit-owner/signed-entitlements.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.weatherkit' \
  work/weatherkit-owner/profile.plist
```

Both WeatherKit checks must be `true`. Also inspect the signed app's `application-identifier` and team identifier against the profile's `Entitlements` and `TeamIdentifier`; check the profile's expiration date and that it covers the selected phone. Verify the embedded `PlugIns/MorningActivityWidget.appex` signature too. The widget must not acquire WeatherKit or Screen Time entitlements. Passing these checks proves signing/provisioning, not Apple's weather backend.

After confirming that this is a safe in-place update, install through Xcode Run or:

```sh
xcrun devicectl device install app --device "$MORE_DEVICE_ID" "$MORE_APP"
xcrun devicectl device process launch --device "$MORE_DEVICE_ID" \
  --terminate-existing com.gibouu.morningoperator
```

## Prove the ordinary app receives current weather

Use no `--ui-testing`, `--theme-weather`, `--theme-phase`, `MO_THEME_PHASE` or `MORNING_OPERATOR_DATA_DIR` override. Do not use a synthetic workspace or reset the owner's data.

1. On Home, reveal the controls and open **Settings → Calendar & weather** (also reachable through **Apps & accounts → Calendar & weather**).
2. Keep the existing chosen city. If none is configured, deliberately choose the intended city using **Search for a city**. MORE never requests device location. Leave calendars and the routine unchanged.
3. Return to Home and allow the bounded weather request to finish. With a fresh app process, the chosen city's actual condition in the revealed Home controls establishes a new admitted native result. Home and playback have no provider branding. Return to **Settings → Calendar & weather** to inspect the **Apple Weather** credit and data-sources link beside the weather connection; verify that its native mark loads. There must be no “sample”, “Weather preview” or synthetic-source marker.
4. A developer can assert the same UI state in the UI-test target using `morning.weatherStatus` on Home and `weather.sources` in the weather settings, without adding fixture launch arguments or changing saved sources. Do not add phone-control code to the app target.

The service publishes a snapshot only after both current conditions and required attribution succeed. Snapshots remain in memory, match the selected city and expire at the earlier of Apple's expiry or 30 minutes from retrieval/conditions time. They are not written to the settings file. The selected city is stored at `Library/Application Support/MorningOperator/briefing-settings.json` inside the app container; do not overwrite that file to run acceptance.

If Home reports unavailable, record that outcome. A valid profile alone is insufficient. The UI's unavailable state does not identify the cause: only Apple's explicit permission-denied error is classified as denied; network and other service failures remain unavailable. Keep any device logs and screenshots local and report signing, installation and live-response results separately.

Apple references: [membership and attribution](https://developer.apple.com/weatherkit/), [WeatherKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit), [build setting inheritance](https://developer.apple.com/documentation/xcode/configuring-the-build-settings-of-a-target/).
