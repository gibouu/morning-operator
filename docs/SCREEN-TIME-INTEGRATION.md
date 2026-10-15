# Screen Time → teach → review → run

This integration reuses the actual system reader and bounded morning-learning logic from [PR #122](https://github.com/gibouu/morning-operator/pull/122), rather than merging that branch's older app shell. Current verification is separate from the historical phone claims in that PR.

## What the normal app reads

`ScreenTimeSources.make()` selects the real `SystemScreenTimeSource` on iOS. There is no sample-data source or launch argument that replaces an unavailable read. The person starts a read, approves Apple's Screen Time authorization, and MORE requests the previous seven local days through `DeviceActivityData.activityData(filteredBy:using:)`. The existing source uses hourly segments and the live policy. Its first returned result supplies app seconds, direct-to-app pickup counts, category, first pickup and longest activity. These are aggregate fields; they do not contain tap events, message content, reels watched or scroll speed. [Apple's app activity fields](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/applicationactivity), [segment fields](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitysegment).

The first card shows actual returned app use by local day. It filters MORE, test runners and system-helper activity; repeated rows for the same app/hour count once. It does not create zero-use rows for missing days. These are app minutes returned by the system, not a complete event log or a promise that all requested historical dates were supplied.

The separate learner uses a heuristic: first use after a three-hour gap, then a twenty-minute gap or a three-hour cap. Screen Time aggregates can bound use but do not establish actual sleep or every app switch. Comparable mornings produce median planned minutes. Partial-hour allocations and all within-hour ordering remain estimates. A long-use budget prompt does not establish scrolling.

`ScreenTimeRoutineProposal` stays separate from the approved routine. Review can exclude apps or change planned minutes. Known launchable apps show their destination before approval and become ordinary `RoutineStepTarget.externalApp` targets. Unknown bundle IDs remain manual; a bundle ID is never treated as a URL scheme. Safari remains manual until the person chooses a URL. Approval installs the displayed rows, and the existing Start action remains separate.

## Required capabilities and availability

- iOS 26.4 or later for the direct data API. The normal app still supports earlier systems for its existing non-Screen-Time features.
- The main app needs both `com.apple.developer.family-controls` and `com.apple.developer.family-controls.app-and-website-usage` in its signed provisioning profile. The entitlement file now requests both. Adding XML alone does not grant the capability or repair a cached profile. [Family Controls](https://developer.apple.com/documentation/familycontrols), [App and Website Usage entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls.app-and-website-usage).
- Runtime status must be `approvedWithDataAccess`, rather than merely `approved`. User authorization is explicit. Only one app at a time may hold this data-access status on a device.
- For customer installations, Apple requires the device to be in the EU and its Apple Account country or region to be in the EU. Apple allows development and testing in all regions using Apple-provided provisioning. That development allowance is not a customer capability. [Apple's authorization conditions](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess), [direct API conditions](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitydata(filteredby:using:)).
- Family Controls distribution requires Apple's managed-capability review. The signing and runtime checks remain separate from local compilation. [Entitlement request](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

No new privacy usage-description Info.plist key is added. The capability uses Apple's own authorization sheet. The ordinary `DeviceActivityReport` extension is a different route: it renders a report in a sandbox and cannot export sensitive report data to the containing app. This integration uses the newer explicitly entitled direct API. [Report privacy boundary](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport).

## One credible demo

1. In normal MORE, connect Screen Time and show the actual returned dates and app minutes. If entitlement, authorization or region conditions prevent access, show that state and keep teaching available; do not substitute a sample report.
2. Teach a short morning through the existing explicit iOS 27 recording flow or a chosen file. The recording supplies visible evidence that aggregates cannot. It still samples at most 24 frames for OCR, so it does not measure every scroll or touch. Apple now offers full-display ScreenCaptureKit on iOS 27; no ReplayKit broadcast extension is required for that path. [Apple's capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios).
3. Review the suggested moments and their time budgets, correct the uncertain order and choose app/browser destinations, then approve. A Screen Time proposal and an observation-based proposal remain distinct evidence sources; presenting them as one combined suggestion requires explicit reconciliation of their revisions and citations.
4. Start the approved morning. MORE opens supported destinations and keeps one persisted step timer, with Next and +2 min. Sign in to supported websites in one visible queue, then optionally start and stop a browser rhythm lesson. Only an explicitly saved numeric summary becomes an observation; no automatic gesture replay is implemented.

## What cannot be claimed

A normal app cannot use these APIs to collect all clicks across Instagram and every other native app. UIKit delivers touch events to the app's own views; Screen Time exposes aggregates, and capture exposes media. Visual motion in a recording can support an estimate but is not a raw touch stream. [UIKit event handling](https://developer.apple.com/documentation/uikit/handling-touches-in-your-view), [ReplayKit media buffers](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/processsamplebuffer(_:with:)).

Inside MORE's own visible WKWebView, an explicitly started lesson now collects numeric same-document scroll distance/moving time and non-input trusted click counts. It stops on navigation, credential forms, backgrounding, privacy loss or 15 minutes. Only an explicit Save retains the aggregate as a reviewable observation. It does not save fields, text, URLs or tap targets. Cross-origin frames, some shadow DOM, keyboard scrolling and inertia beyond the short input window are not fully measured. It does not measure the native Instagram app or adapt playback speed. [WebKit isolated script messages](https://developer.apple.com/documentation/webkit/wkusercontentcontroller/addscriptmessagehandler(_:contentworld:name:)).

The recovered reader has a 45-second competing timeout, but structured task-group cleanup depends on SDK stream cancellation. Do not promise a hard wall-clock timeout until physical cancellation behavior is checked. Freshness, returned historical coverage, regional distribution behavior and recognition quality require separate real-device evidence. No new physical Screen Time result is asserted by this integration.

## Local verification

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/test.sh --filter 'ScreenTime|MorningStart'` passed 54 core tests in four suites and one matching Apple test. These cover morning boundaries, incomplete-hour estimates, repeated live rows, restored proposal validation, review edits and approval, exclusion preferences, daily coverage, and safe executable app targets. This package run does not verify entitlements, provisioning, the system authorization sheet, data availability, or SwiftUI rendering on a phone.

The final ordinary MORE build was signed with both Screen Time entitlements and WeatherKit and installed. The separate QA bundle cannot obtain that profile from the currently signed-out Xcode account; its signing failure is not a Screen Time API failure. Runtime approval and returned data in ordinary MORE remain hands-on checks.
