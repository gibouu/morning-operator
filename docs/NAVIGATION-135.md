# Three-destination shell — issue #135

The shell has exactly three bottom buttons: Home, Learn or Routine, and Settings. Each button has an explicit VoiceOver name and a native SF Symbol. The center uses Learn while `store.routine == nil`; any installed routine, including an unapproved draft, uses Routine. Pending evidence suggestions stay in the existing teaching/review flow until installed by that flow.

Home always reveals Home. It resets the inline date selection to today and collapses the day browser. It never toggles playback or opens a menu. Home's large Learn and sample controls are removed. Settings remains a direct full-screen destination.

An approved idle morning gets inline Play on Home, followed by the existing explicit Cancel/Start confirmation. Running and paused mornings retain inline controls. Root owns the pending start's routine/generation snapshot and entry occupancy; switching adaptive layouts does not lose the confirmation. Routine, session, scene and privacy changes clear it on stable Root callbacks. Routine/Settings navigation can cancel it synchronously while holding navigation occupancy. Start still checks the same routine, generation, approval, active scene, storage, privacy, busy and voice state. Pause/Continue keep the displayed command tied to its original session and data generation.

The `WeeklyReviewView` shell root is removed. All old `store.tab = .review` shell paths are gone. Legacy `.review` and `.captures` routes normalize to Home. Legacy `.learn` and `.setup` routes normalize to Home before presenting their existing destination. Dismissing a destination therefore cannot reveal the old history hub. Home keeps a stable navigation identity through privacy cleanup. History, observations, routines, receipts, learning policy and approval persistence are untouched.

## Integration hooks

### Inline day browser — issue #138

Root already owns `selectedDay` and `showingDays`. `TodayView` accepts a `dayBrowser` builder as its trailing closure and places it at the start of the Home header. The current `homeDateBrowser` is a compile-safe date button: it toggles the shared expansion binding and has no route to Review. It does not yet render days. After adding issue #138's component and core models, replace only this builder:

```swift
private var homeDateBrowser: some View {
    MorningInlineDayStrip(
        selectedDate: $selectedDay,
        isExpanded: $showingDays,
        history: store.history
    )
    .disabled(store.privacyBlocksWork)
}
```

The component owns its date button and expanded strip, so do not add a second date header. Its optional `observations` input can receive the evidence projection from issue #138. Changing the selected date never selects a routine version. The routine remains the one saved reusable daily routine. Root resets both date bindings after privacy generation changes; Home also resets them.

### Routine destination — issue #136

The center calls `openRoutineReview()`. With no routine it directly presents `LearnView` through the existing Learn cover. With a draft or approved routine it directly presents `RoutineReviewEditor` through the existing routine cover. The Learn-after-routine-dismissal handoff and saved-recording recovery path remain intact.

Issue #136's current API is:

```swift
MorningRoutineDestination(
    store: store,
    learningRequested: $learningRequested,
    onInteractionChanged: { routineInteractionBusy = $0 }
)
```

The integration owner adds these two Root state values and feeds interaction occupancy into the existing entry/recording guards. The component is designed for an embedded persistent center destination; if first hosted in the existing cover, retain a dismiss control and Root's `activeEntryPresentations`/`onDismiss` ordering. The compatibility `RoutineReviewEditor(store:onLearn:)` remains available after issue #136. A saved pending recording intentionally blocks automatic Start but does not block the center Learn destination from reviewing that recording. Do not replace the center guard with `entryIsOccupied` wholesale.

### Typography / artwork tracks

The shell and destination header use the system font; `MorningDockGlyph` explicitly uses Apple's default font design. Existing content typography remains in its separate owner track, including the Home greeting's `MorningTheme.Typography.title`. No theme, background, artwork or font files change here.

## Validation boundary

Source parsing and whitespace validation pass. A read-only navigation/entry audit found two confirmation lifecycle risks during implementation; both were fixed by putting the snapshot and invalidation on Root. The follow-up source review reports no remaining P1/P2 finding. The final different-model review remains with the integration owner, as assigned.

Unsigned generic iOS app/widget build and component proof results are recorded in the PR and the external proof folder. No phone automation, routine traversal, acceptance fixture, install or main merge is performed here. Existing `SunriseDockTests` and helpers that target `morning.actions`, `morning.playback` or a separate `morning.reviewDraft` still describe the rejected expanding dock and require integration-owner updates before a future UI run; this branch does not claim those tests pass. Offscreen AppKit images demonstrate native symbol shapes and component spacing; they cannot demonstrate live composited Liquid Glass, iPhone layout, VoiceOver operation or route behavior.
