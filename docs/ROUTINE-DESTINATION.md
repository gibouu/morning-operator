# Learn → Routine integration

Issue [#136](https://github.com/gibouu/morning-operator/issues/136) supplies the center destination. The shell owns Home / Learn→Routine / Settings and removes the large duplicate Home learning action.

Use `MorningRoutineDestination(store: store)` as the center tab's root. It owns its `NavigationStack`; do not wrap it in another stack or a full-screen cover. Give the tab the label **Learn** while `store.routine == nil`, and **Routine** otherwise. A draft counts as an existing routine. There is one saved routine reused every day, independent of the selected date.

To route a recording, saved observation or pending Learn intent to teaching, pass `learningRequested: $learningRequested`, select the center tab, then set the binding true. The destination consumes the request. Before creation it is already teaching; with a routine it pushes refinement. Do not open a second Learn cover from Home.

Pass `onInteractionChanged` to the shell's existing pending-entry occupancy guard. It is true while teaching/refining or a moment editor is open. Queue starts and capture-result processing while occupied; resume after it becomes false and other shell presentations permit it. `MorningRoutineDataView` has the same callback for Settings file pickers/previews/exports. Keep the existing proposal occupancy and privacy-reset guards too. The callbacks expose presentation state; they do not dispatch entries themselves.

Before creation, the destination opens the existing teaching page directly. It hides the manual starter action. Recording, selected-media import, observation corrections, provenance review, local availability checks and evidence proposal approval stay in `LearnView`. Once a routine exists, the same destination shows its moments directly. Tap a moment to edit; native move handles are always visible on iOS. VoiceOver offers Move earlier / Move later. There is no top-right Edit mode.

`RoutineReviewContent(store:onLearn:onApproved:)` is the stack-free editor content. `onLearn` opens teaching to refine the current routine. `onApproved` runs only after a saved draft has been approved successfully; it defaults to no action so the center tab stays on Routine. It never starts playback. `RoutineReviewEditor(store:onLearn:)` remains a modal compatibility wrapper for old review links and keeps their Done/return-to-Home behavior.

For Settings, push `MorningRoutineDataView(store: store)` from the Settings navigation stack. It retains native import preview, stale-base rejection, reset generation checks, export snapshotting and cancellation. It does not own a navigation stack. File tools are absent from the Learn→Routine destination. Existing file-transfer UI tests that use the old editor route need shell integration before their navigation can be updated.

`LearnView` adds two compatible parameters: `allowsManualRoutineCreation` (default true for existing callers), and `onRoutineSaved` (default nil, preserving modal dismiss). The center supplies false and an explicit navigation callback. Approval of source-linked suggestions still belongs to `RoutineEvidenceProposalView`; opening a destination never approves or creates anything.

Edits use the existing store transactions. Saving a step captures the base routine and privacy generation and rejects a stale editor without replacing newer content. Reordering supplies captured routine/generation identities. An active or paused run, busy analysis, unavailable storage or privacy reset blocks edits and approval. A changed routine remains a draft until explicit approval. No new capture, model, date, theme, connection or playback policy is introduced.

## Verification boundary

The app build proves native source compilation. Focused package tests cover the existing evidence and routine policies. Native component images use invented in-memory input and prove only component layout. They do not prove recording, inference, persistence, root navigation, system file-provider behavior or a real morning. No phone installation, routine seeding or UI automation is part of this change. The integrating shell session owns the full user journey check.
