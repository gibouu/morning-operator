# Subscription entry verification — 16 October 2026

The source includes the current adaptive Settings design and the separate solar permission setup. Its visual tokens, typography and primary buttons now match discovery and the paywall; permission behavior is unchanged. The subscription entry builds the existing root only after verified StoreKit access; no permission implementation was duplicated in this workstream.

## Observed results

| Check | Result and boundary |
| --- | --- |
| Integrated app and UI-test build | `xcodebuild build-for-testing` passed using Xcode 27, deployment target iOS 26.0 and the installed iOS 26.5 simulator. App, widget, shared modules and UI tests compiled. |
| Welcome interface suite | Four native XCTest journeys passed: three intro pages plus offer in day/night and French/English; Back/skip and Terms/Privacy sheets; purchase/restore failure recovery; ineligible trial, unavailable offer and pending state; accessibility XXXL portrait/landscape reachability. A fifth existing Settings → routine/accounts/voice journey also passed after integration. Welcome transactions use explicitly labelled simulated previews. |
| Native StoreKit suite | Initial local-store calls failed with `SKInternalErrorDomain Code=3`, including configuration and transaction setup. The installed iOS 26.5 runtime has the reported StoreKit Test connection problem. The original eight and, after adding declined-request recovery, all nine native purchase cases were explicitly skipped. **No native purchase test passed; transaction behavior remains unverified.** The supported-runtime assertions are retained. |
| Shared package tests | Not rerun for this app-only workstream. Package compilation was part of the Xcode build; it is not a package-test result. |
| Live offer and physical iPhone | App Store Connect configuration, Apple sandbox purchases, production billing and physical-device purchase flows were not performed. No physical app installation was replaced. |

Apple references: [reported StoreKit CLI failure and DTS replies](https://developer.apple.com/forums/thread/826971), [iOS 26.6 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_6-release-notes). Re-run `MORESubscriptions` with a compatible simulator before treating native purchase coverage as complete.

## Local evidence

- Final build: `/tmp/more-onboarding-final-build.log` (passed after the declined-request recovery fix).
- Latest-main integration: `/tmp/more-onboarding-main-build.log` passed; `/tmp/more-onboarding-main-smoke-fresh.xcresult` and `.log` contain one passing native night-appearance permission-screen smoke. The first launch failed destination discovery and a cached runner enumerated zero tests; neither was counted as a pass. Reinstalling only this isolated UI-test runner ran the actual case successfully.
- Final access integration: `/tmp/more-onboarding-shared-style-build.log` passed; `/tmp/more-onboarding-shared-style-ui.xcresult` and `.log` contain 4 passing native UI tests (0 failures): unpaid intro/purchase recovery, French day/night access surfaces and disclosure, accessibility XXXL portrait/landscape, and revisiting access from Settings without restarting onboarding. Captures are exported outside Git in the same visualization directory under `onboarding/access-integration/`.
- First full UI run: `/tmp/more-onboarding-ui-verified.xcresult` and `.log` (4 passed, 8 explicitly skipped).
- Combined UI run: `/tmp/more-onboarding-integrated-ui.xcresult` and `.log` (5 passed, 0 failures).
- Final targeted UI and StoreKit environment check: `/tmp/more-onboarding-final-ui.xcresult` and `.log` (3 UI cases passed, 9 native StoreKit cases explicitly skipped). This rerun covers the compact intro layout, large-text navigation and explicit pending-request recovery.
- Synthetic screenshot matrix: the chat's local `visualizations/2026/10/16/01a1423f-d371-7551-a0e0-b2c66997f472/onboarding/` directory, outside Git. It includes 16 standard introduction/paywall captures and accessibility/error-state captures. No screenshots, recordings or private account contents are committed.

The first new simulator stalled during system migration and was removed. Checks ran on a dedicated clone of an initialized iPhone 17 Pro simulator, with isolated UUID workspaces. Other chats' simulators were left alone. The visual review identified and corrected large-text header compression and an oversized debug-only preview marker; text remains on opaque surfaces at sunset, and changing pages returns to the top. Intro artwork and spacing were shortened so the example card fits above the action area at ordinary text sizes. A source review identified that declined Ask to Buy requests do not produce callbacks; explicit retry now reconciles verified access before making a new user-requested purchase attempt.

Live release prerequisites and the purchase-to-permission acceptance journey are tracked in [issue #191](https://github.com/gibouu/morning-operator/issues/191).

## Primary language and glass refinement — 16 October 2026

The entry/access presentation now uses frosted native materials and Liquid Glass actions, with opaque accessibility fallbacks and an original two-arch monogram. Light, dark and tinted app icons are regenerated by `scripts/make-app-icon.swift`; all three are opaque 1024 × 1024 assets and regeneration was deterministic. The visible preview badge is gone; its DEBUG-only isolation is retained through a nonvisual test identifier and simulated failures.

The primary iPhone language alone chooses French or English; secondary French never selects French for a non-French primary language. Root locale/layout and the shared Foundation lookup agree. The mechanical migration preserves bundle selection, interpolation and compiler-extracted keys; existing translations were not rewritten. Regional formatting and explicit voice choices remain intact.

| Final-source check | Observed result |
| --- | --- |
| iOS app/widget/UI-test build | `/tmp/more-glass-language-final-build.log`: build-for-testing passed. |
| Repository language/catalog tests | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/test.sh --jobs 2 --filter 'AppLanguageTests\|StringCatalogLoadingTests'`: 9 passed on final source; `/tmp/more-primary-language-final-tests.log`. |
| Independent language harness | Final `AppLanguage.swift` and its portable temporary-bundle tests: 7 passed; `/tmp/more-language-focused.log`. |
| Native visual matrix | `/tmp/more-glass-matrix.xcresult`: 1 test passed, with 16 day/night × French/English intro/paywall captures. The rendered screens were inspected; no preview badge appears. |
| Native access presentation | `/tmp/more-glass-language-ui.xcresult`: both access tests passed (French day/night/disclosure and accessibility XXXL portrait/landscape). The overall run was interrupted later and is **not a passing suite**. |
| Remaining native welcome acceptance | The first primary-language loop completed, then XCTest app relaunch stalled. The run records 2 passed and 1 cancelled. After restarting only the dedicated simulator, `/tmp/more-glass-welcome-retry.xcresult` stalled before execution and was cancelled. Device discovery through both the standard simctl wrapper and CoreSimulator 1171.7 backend also timed out. No app assertion identifies a source bug; the four remaining UI cases are **unverified**, tracked in [issue #199](https://github.com/gibouu/morning-operator/issues/199). |

The final screenshots are outside Git in the chat's `visualizations/2026/10/16/01a1423f-d371-7551-a0e0-b2c66997f472/glass-onboarding/` directory. Other chats' simulators and the global CoreSimulator service were preserved. No physical-device installation, real purchase, production billing or model inference was performed in this refinement.
