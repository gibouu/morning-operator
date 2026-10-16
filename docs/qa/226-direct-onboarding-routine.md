# Direct routine preparation after onboarding — issue 226

## Change

After the optional voice choice, the first-run flow opens routine preparation instead of the generic Learn toolbox. The existing saved routine opens in its editor; otherwise the person sees a MORE-styled proposal destination. Screen Time already approved is read once on entry. Fresh access needs the person's explicit Connect Screen Time choice. A saved pending proposal is reused without rereading, approving or starting it.

No data, denied access and unsupported devices have a continue-for-now path. Later preserves a pending review. Relaunch keeps the existing persisted permission progress and workspace; it does not automatically reopen this destination. Play or Settings → Your routine returns to it when no routine is saved. Advanced tools remain under Settings → Refine my morning.

Website sign-in remains optional through Settings → Apps & accounts. The proposal explains that sites can be connected later. This change does not infer provider identities from opaque tokens, add a batch login hub, approve a routine or start a session.

## Verification

- `swift test --filter 'MorningPermissionProgressTests|ScreenTimeRoutineLearningTests'`: **43 passed**. Covers the existing progress persistence and Screen Time proposal/data-boundary policy; it is not native routing proof.
- Changed Swift and UI-test files passed Swift parsing; 9 changed catalog entries have both English and French translations.
- Native generic iOS Simulator Debug build with signing disabled: **passed** (arm64 and x86_64). This is a compile check, not a simulated-device or physical-phone run.
- Native `build-for-testing` with signing disabled: **passed**, including the changed UI-test sources.
- UI journeys added/updated for Connect → proposal → Later → relaunch → same saved proposal, French no-data/Later, and voice-choice persistence. They have not yet been executed; root owns the device and native filming checks.
- Independent read-only review requested. Claude CLI cross-model review is unavailable because its OAuth session is expired; this is reported, not treated as a pass.
- The annotation companion is `design/gallery/onboarding-direct-routine.html`. It labels its sample rows, supports EN/FR and no-data/proposal states, and saves right-click notes locally with route, element and page coordinates. Native iPhone output remains the source of truth. Prior previews are preserved.

No real Screen Time data, provider requests, phone actions, screenshots, recordings or credentials were used in this worktree.
