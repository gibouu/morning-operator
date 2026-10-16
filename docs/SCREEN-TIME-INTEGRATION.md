# Screen Time → teach → review → run

This integration reuses the actual system reader and bounded morning-learning logic from [PR #122](https://github.com/gibouu/morning-operator/pull/122), rather than merging that branch's older app shell. Current verification is separate from the historical phone claims in that PR.

## What the normal app reads

`ScreenTimeSources.make()` selects the real `SystemScreenTimeSource` on iOS. There is no sample-data source or launch argument that replaces an unavailable read. The person starts a read, approves Apple's Screen Time authorization, and MORE requests the previous seven local days through `DeviceActivityData.activityData(filteredBy:using:)`. The existing source uses hourly segments and the live policy. Its first returned result supplies app seconds, direct-to-app pickup counts, category, first pickup and longest activity. These are aggregate fields; they do not contain tap events, message content, reels watched or scroll speed. [Apple's app activity fields](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/applicationactivity), [segment fields](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitysegment).

The first card shows each retained morning's local date, start and end, then its apps in estimated first-use order. It does not show all-day app totals. MORE, test runners and system-helper activity are excluded; repeated rows for the same app/hour count once. Missing days and undetected windows remain unknown.

The learner uses the first activity after a three-hour inactivity gap, then a twenty-minute pause or a three-hour cap. If the person has already connected Health, a separate sleep-only read supplies recorded sleep windows for each local day and anchors the first waking activity. It never requests Health access during a Screen Time read. Recorded sleep can establish the wake-up anchor even when Screen Time returned no preceding night hours; without sleep records, the original activity heuristic applies. Inactivity is never displayed as recorded sleep. Raw sleep samples remain transient, and the archive stores only the retained morning's app aggregates. The Health window follows the existing sleep-summary convention, which can include fragmented sleep and morning naps; it is a hint, not a measured wake-up time.

Comparable mornings produce median planned minutes. Partial-hour allocations and all within-hour ordering remain estimates. Screen Time aggregates do not establish taps, content, every app switch, or scrolling.

`ScreenTimeRoutineProposal` stays separate from the approved routine. Review can exclude apps or change planned minutes. Known launchable apps show their destination before approval and become ordinary `RoutineStepTarget.externalApp` targets. Unknown bundle IDs remain manual; a bundle ID is never treated as a URL scheme. Safari remains manual until the person chooses a URL. Approval installs the displayed rows, and the existing Start action remains separate.

## Join the saved observations

The 16 October implementation also archives bounded dated aggregates for days with actually returned intervals. It records the requested range, returned coverage, phone zone, detected morning window when available and measured/estimated app seconds. An unanswered day creates no zero-use observation, and an empty refresh does not erase an earlier source. A returned day without an established morning remains explicitly unknown.

**Combine selected observations** opens the existing explicit selection beside reviewed videos and saved browser lessons. All selected source revisions and citations go through the same pending proposal and interface review. Screen Time is typed aggregate evidence, not a written claim or a source of gestures. Known exact identities can support an observed activity; whole-app minutes are never divided arbitrarily among stories/feed segments or used to change their behavior. Aggregates alone propose manual app moments for review. Personal corrections and retained choices apply last.

Refreshing a real payload updates its existing dated source, preserves corrections separately and invalidates a proposal based on the previous revision. Source text is local semantic evidence, subject to the archive's existing bounds and Forget controls. The legacy direct Screen Time suggestion remains available. Shared contract checks and the explicitly synthetic native source-join fixture are separate from a real entitled Screen Time read; current native UI results belong in the [acceptance ledger](ROUTINE-AUTOMATION-QA.md).

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
3. Select the available dated Screen Time, video and browser sources for one proposal, or use the compatible direct Screen Time suggestion. Review the moments, uncertain order, operations and budgets, then approve in the interface. Sources never approve themselves.
4. Start the approved morning. MORE follows reviewed operations and keeps one persisted timer, with Next and +2 min. Sign in to supported websites, then explicitly start/stop and save a browser lesson. Reviewed browser behavior and its real-service proof are described in [routine automation](ROUTINE-AUTOMATION.md); opening a destination alone does not prove execution.

## What cannot be claimed

A normal app cannot use these APIs to collect all clicks across Instagram and every other native app. UIKit delivers touch events to the app's own views; Screen Time exposes aggregates, and capture exposes media. Visual motion in a recording can support an estimate but is not a raw touch stream. [UIKit event handling](https://developer.apple.com/documentation/uikit/handling-touches-in-your-view), [ReplayKit media buffers](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/processsamplebuffer(_:with:)).

Inside MORE's visible WKWebView, numeric scroll/moving-time and trusted non-input click measurements are limited to supported page observations. Explicitly saved structured browser lessons can add reviewed operation sequences to the common proposal. Neither those lessons nor Screen Time measure the native Instagram app or establish every gesture. Credentials never become learning evidence. See [browser learning and execution](IN-APP-BROWSER.md) for current coverage and exclusions. [WebKit isolated script messages](https://developer.apple.com/documentation/webkit/wkusercontentcontroller/addscriptmessagehandler(_:contentworld:name:)).

The recovered reader has a 45-second competing timeout, but structured task-group cleanup depends on SDK stream cancellation. Do not promise a hard wall-clock timeout until physical cancellation behavior is checked. Freshness, returned historical coverage, regional distribution behavior and recognition quality require separate real-device evidence. No new physical Screen Time result is asserted by this integration.

## Local verification

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/test.sh --filter 'ScreenTime|MorningStart'` passed 54 core tests in four suites and one matching Apple test. These cover morning boundaries, incomplete-hour estimates, repeated live rows, restored proposal validation, review edits and approval, exclusion preferences, daily coverage, and safe executable app targets. This package run does not verify entitlements, provisioning, the system authorization sheet, data availability, or SwiftUI rendering on a phone.

The final ordinary MORE build was signed with both Screen Time entitlements and WeatherKit and installed. The separate QA bundle cannot obtain that profile from the currently signed-out Xcode account; its signing failure is not a Screen Time API failure. Runtime approval and returned data in ordinary MORE remain hands-on checks.
