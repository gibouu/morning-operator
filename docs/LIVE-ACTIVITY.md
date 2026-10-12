# Your morning on the Lock Screen

MORE's optional Live Activity shows a small, generic view of a morning you have chosen to start. The setting is off by default. Source `c926c17` passes focused shared checks, native simulator lifecycle and actual Dynamic Island presentation checks, including stale content and reveal-only entry. Simulator and unsigned generic iPhone builds pass. [PHASE-ONE](PHASE-ONE.md) records verified revisions separately. No new physical-phone or signed-device pass is claimed.

## Use it

1. Open **Review → Settings & connections → Morning at a glance**.
2. Turn on **Show on Lock Screen**. The setting must save successfully before the app requests an activity. iPhone's Live Activities setting still applies.
3. Start or resume an approved morning. Turning the setting on during an active morning also permits a request while MORE is in the foreground.
4. Tap the activity to reveal **Morning**. This does not resume, advance, approve, record or listen. An unfinished review stays open.
5. Turn the setting off to end its display. Ending or completing the morning also ends the activity; removing the activity through iOS does not stop the routine inside MORE.

**MORE currently pauses a running morning when it goes into the background.** The activity reflects that pause; return to MORE and choose Resume. ActivityKit does not make the routine executor or audio run indefinitely in the background. A supported background-audio transport is separate future work. Apple permits background updates only while the app actually has execution time. [ActivityKit lifecycle](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

## What another person can see

The Lock Screen and Dynamic Island use app-owned categories—Briefing, Messages, Calendar, Wellbeing, Time to enjoy or Your moment—plus running/paused/needs-attention status and passed/total moment counts. Passed moments include explicit skips; they do not establish that a physical action was completed or a message read. Counts describe progression through a routine, not minutes, phone use, scrolls or measured productivity. The ordinary Lock Screen and expanded Dynamic Island layouts show a static last-update time; the accessibility summary includes it too.

Routine names, personal step titles/details, messages, calendar entries, weather location, observations, quotations and transcripts are excluded from the payload. Generic categories and progress can still reveal something about your morning to anyone who can see the display. The preference is therefore explicit; it is not enabled by approving a routine or connecting Calendar.

The widget extension has no workspace access, network client, microphone or action buttons. It renders the bounded payload through WidgetKit and opens only `more://morning`. The system chooses which supported surface to show and may make the activity visible on compatible paired surfaces; this is not a separately implemented Watch or CarPlay product. [Apple's Live Activity presentations](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities).

## Freshness and recovery

Each published update requests a **stale date 60 seconds later**, with no heartbeat that pretends work is continuing. iOS controls when the visible display refreshes; this is not a promise of a one-minute transition. When the system supplies the stale presentation state, the widget replaces its category/status headline with **Update needed** and **Open MORE to update**. A simulator check initially timed out after 75 seconds; native logs showed a later nonwaking refresh schedule, and the bounded follow-up observed the real transition. The static update time stays truthful during that delay. It does not draw a countdown or extrapolate progress. Returning to the foreground can confirm and republish the current state; unchanged background refreshes do not extend freshness. A stale date marks old content; it does not end the activity. [Apple: staleDate](https://developer.apple.com/documentation/activitykit/activitycontent/staledate).

The source separates routine state from presentation. Failed workspace saves block publication. Relaunch reconciles activities left by the prior process, and restoring an old session does not silently create a new activity. Native dismissal is not permission to recreate one during ordinary updates. A later explicit Resume or a deliberate Off → On change can authorize another request for the same active morning; repeating an already-used request cannot. If iPhone Settings denies Live Activities, changing the MORE preference does not override that denial.

Turning the display off, ending a morning and forgetting local data use immediate ActivityKit dismissal rather than leaving a completed card on the Lock Screen. A system dismissal affects only presentation; it does not cancel the underlying routine. [Apple: immediate dismissal](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/immediate), [dismissed state](https://developer.apple.com/documentation/activitykit/activitystate/dismissed).

## Storage and forgetting

`workspace.json` stores the opt-in Boolean; a missing field restores as off. The extension receives opaque routing/session identifiers and the bounded generic content, not a second routine database. No push token, APNs server or shared workspace container is added.

**Forget local data** disables new publication and awaits activity cleanup before completing the reset. It resets the opt-in to off. Cleanup failure must remain visible and retryable through the pending privacy reset. Fixture activities use a separate workspace namespace so test cleanup cannot target the person's ordinary activity. System authorization stays under iPhone Settings. The app does not promise erasure of screenshots, device backups or all OS-managed records. [Full forgetting scope](PRIVACY.md).

## Verification and remaining checks

The shared run passed **20 tests (21 parameterized cases)**. Native simulator runs passed **4/4 lifecycle journeys**, **3/3 presentation/home checks**, and the final **1/1 stale-display check**. They use synthetic routine data, native ActivityKit and an isolated workspace namespace. The detailed chronology, initial compiler failures and exact scope are in [PHASE-ONE](PHASE-ONE.md).

Use a harmless synthetic approved routine and record the exact installed revision. Check off-by-default and save failure; enable, start, pause and advance; verify generic content and passed counts in both appearances; background the app and verify paused/stale presentation. Tap it and confirm that the run does not resume. Exercise system dismissal, disabled Live Activities, process termination/relaunch, end, opt-out and full forgetting, including a delayed native request during cleanup.

Check actual Lock Screen and compact/minimal/expanded Island layouts, the largest accessibility text, VoiceOver, Reduce Motion and available paired surfaces separately. Source-level adaptive layout and fake-provider lifecycle tests do not establish these outcomes. Signed-phone validation is currently blocked by the developer-account/signing setup; current installation status belongs in [PHASE-ONE](PHASE-ONE.md).
