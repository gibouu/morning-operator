# Inline days on Home · issue #138

This branch supplies the component, read model and isolated native preview. The
navigation owner integrates it into `MorningRootView.swift`; this branch does not
change Home routing, `WeeklyReviewView`, bottom destinations or routine playback.

## Home binding

Keep selection in Home presentation state. Never use it as a routine key, create a
session for it, write it to history or pass it to Start/Resume. All days use the one
current routine. Historic `MorningRunRecord.routine` values are saved evidence only.

```swift
@ViewState<Date> private var selectedDay = .now
@ViewState<Bool> private var showingDays = false

// Replace the old date-to-Review button with this component in Home's vertical
// content. Retain recording/attention controls as separate sibling controls.
@ViewBuilder private var homeDate: some View {
    if let evidence = try? store.observationArchive.inlineDayEvidence {
        MorningInlineDayStrip(
            selectedDate: $selectedDay,
            isExpanded: $showingDays,
            history: store.history,
            observations: evidence
        )
    } else {
        Text("Saved day evidence could not be displayed.")
    }
}
```

Do not turn an adapter error into `[]`: that would make unavailable evidence look
empty. Ordinary Home omits `referenceDate`; it is a preview-only pinned clock. The
component reads the environment calendar, locale and time zone and refreshes each
minute. At midnight, a selection that was today follows today; an older selected
day stays selected. A time-zone change preserves the selected older civil date and
rebases today to the new actual day. Forward movement clamps to today. There is no
oldest-day history cutoff.

The date button keeps accessibility ID `morning.date` and expands in place.
`morning.days.strip` is the native horizontal scroll view. Swipe to browse and tap
a day to select; arrows move the selected day, and Today returns to today. More
older dates become available when the leading edge is visible. Swiping itself
does not change selection or start an action. Selection, expansion and scrolling
are the only component behavior. The evidence summary remains inline.

Keep the normal routine editor in Learn → Routine and the normal routine entry on
Home. While a past date is selected, show the same current routine as read-only
context and gate any shell-owned Start, Continue, Next, retry or automatic-opening
entry until the person deliberately returns to Today. Use a live day comparison
(including foreground/time-zone changes), rather than a boolean captured once:

```swift
var calendar = Calendar.current
calendar.timeZone = .current
let isViewingToday = calendar.isDate(selectedDay, inSameDayAs: .now)
// Require isViewingToday at the action boundary as well as in disabled UI.
// Keep existing approval, session, privacy and microphone guards unchanged.
```

This guard is required integration work. The component cannot guard controls it
does not own. Remove the old `showReview` closure from the date path; do not wrap
the strip in a NavigationLink, sheet or old history/settings hub. Retain underlying
history data. Exactly Home / Learn → Routine / Settings remain shell-owned.

## Evidence contract

`try MorningInlineDaySnapshot(selectedDate:today:calendar:history:observations:)`
returns `.completed`, `.partial`, `.evidenceOnly` or `.noSavedEvidence`, with the
actual saved completed/stopped runs and dated observations. `.partial` means a
saved stopped run; it does not promise that a single step ran. Finished runs can
contain skipped steps, so the view shows completed and skipped counts separately.

Synthetic runs, synthetic routines, synthetic app snapshots and non-human archive
sources never become personal evidence. An observation does not prove a routine
ran or that the whole day was observed. Empty means no saved personal evidence,
not that the person did nothing. Unassigned observations stay unassigned; import
time is never used as their observed date. A separate archive-wide note explains
that those entries are absent from the selected day.

Source Gregorian day keys and source zones are preserved across travel, matching
the existing archive convention. A recording saved as October 8 in Los Angeles
remains under October 8 when viewed in Paris. Display calendar and locale affect
labels without rewriting or regrouping saved evidence. The source zones appear
under the evidence. No averages, measured app-use totals or inferred activity are
introduced here.

## Native proof

`#Preview("Inline days · empty history")` provides a live SwiftUI preview.
For a standalone macOS component demo and PNG renders, run:

```sh
scripts/preview-inline-days.sh /absolute/local/proof/directory --interactive
```

Omit `--interactive` to close the preview after rendering. The harness creates only
in-memory fixture sessions and evidence. It never opens MorningStore, loads the
owner's data, runs a routine, calls a model, installs an app or controls a phone.
It renders collapsed, empty, finished-with-skipped, stopped, observation-only,
a requested largest Dynamic Type environment, and dark/French-date states. macOS
does not visibly scale these semantic fonts with that environment; actual largest
iPhone text remains unverified. Reduce Motion follows the real system setting and
is not forced by the harness. These are
native macOS SwiftUI component renders, not iPhone screenshots or proof of shell
navigation, actual archived activity, VoiceOver speech or touch/swipe behavior.

The annotation companion and local proof files stay outside Git. Before product
acceptance, the integrated shell still needs actual iPhone checks for inline date
expansion, touch swiping, past-day action guards, midnight/foreground/time-zone
updates, VoiceOver focus and speech, largest Dynamic Type and Reduce Motion. This
branch makes no claim that those integrations passed.

— gib
