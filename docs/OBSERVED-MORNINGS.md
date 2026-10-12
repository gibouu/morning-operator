# Your observed mornings

A recording gives MORE a few saved glimpses of your morning. Review lets you inspect those moments and see which screen labels appear across days, without adding controls to the Morning page.

**Available in the V2 source branch.** This does not yet measure a complete morning, time in other apps, scrolls or messages read. The installed phone remains on the earlier build; see [verification](PHASE-ONE.md) for current device status.

## Start with one morning

1. Record with Apple's explicit screen-sharing choice, or select a video to import in Learn. Return to MORE after stopping so processing can finish.
2. Open **Review → Saved observations**. Each import keeps its own original extraction; corrections are stored separately.
3. Check its observed day, time zone and origin. An imported file's date is not guessed from its name or import time. Leave unknown information unknown.
4. If you want screen labels, use **Edit in Learn → See sampled screens → Recognize sampled screens** on an eligible uncorrected recording. This explicitly requests the on-device model. Importing and opening Review do not call it.
5. Return to the observation's **Recording evidence**. Open **View sampled screens**, then a moment, to inspect the original text, accepted quotation and requested/actual frame times.

An unavailable model or unresolved screen still leaves the saved samples visible. A recognized label is a proposal about visible text; “Inbox” does not prove Mail was open, and a message on screen does not prove you read it. Separate samples at the same timestamp remain inspectable, but MORE does not invent their order.

## Look across days

The selected seven-day period sits at the top of Review. When it contains dated observations, **Your observed mornings** leads with the labels that appeared across those days. **Routine-run timing** stays collapsed below. Samples and other origins stay apart from personal mornings, and each saved time zone keeps its own group.

Tap the date range to reveal the days. Open a day to see a brief sequence for each recording, including unknown moments, then use **Inspect sampled moments** to reach its original text. Separate clips remain separate; the preview does not create a continuous morning. Notes-only sources remain visible without acquiring fictional screen samples.

**From your observations** still opens the complete period view. The compact overview shows up to three groups and three labels per group, with omitted counts disclosed. Each clip previews up to six moments; its full observation retains the rest. The complete view shows days with labeled samples, observed days with no labels, and dates without an observation.

A label seen on two of three labeled days means just that: its quoted evidence appeared on two distinct dates among the three dates that supplied at least one accepted label. Two recordings on one date still count as one date. It does not mean two complete mornings, a measured frequency of app launches, or a two-thirds habit probability.

Open a label, then a quotation, to reach its current source moment directly. **The seven days** reveals separate clips and missing dates. Different movies are never concatenated into one activity timeline. Samples, automated activity and uncertain origins remain separate from personal mornings.

| You see | What it means |
|---|---|
| A → B → A in one clip | The samples establish at least one visible return to label A. More activity may lie in the gaps. |
| A → unknown → A | A return is not established. The unknown moment remains visible. |
| Several requests at one frame time | Several source samples, one effective moment. Conflicting labels make that moment unresolved. |
| No labeled samples | Evidence may be unclassified, ambiguous, corrected, limited, or affected by a model failure. It is not zero activity. |
| No observation | No saved source for that date and partition. It is not a zero-minute morning. |
| Invalid time order | Original samples stay available in extraction order; sequence and return claims are withheld. |

An eligible exact quotation also offers **Read this saved moment**. Its dated speech preview opens with that same source already selected. Opening it does not speak or change the routine; **Add to my morning** creates a draft for separate approval. Shortened quotations, unsupported sources and lines outside the bounded chooser do not substitute other text. [Saved-moment guide](SAVED-MOMENTS.md).

## Correct one screen

Open a sampled moment, then **Correct label**. Describe what was on that screen and select an exact excerpt from its saved text. **Save** applies your label; **Cancel** changes nothing. **Keep this screen unknown** suppresses that sample's label and excludes it from later activity suggestions. **Remove my correction** reveals the original interpretation, if one exists.

The source keeps your review time, label and selected quotation separately from the original extraction and model result. The weekly view marks **Your label** and updates from the saved source, including after relaunch. Your labels form their own groups: a matching model label is not silently combined with a personal assertion. Different spelling or capitalization remains separate. Correcting one of several samples at the same timestamp does not resolve disagreement or establish their order.

The next explicit routine suggestion receives your label as context beside the original text. It must still cite eligible original activity evidence. Marking a screen unknown prevents it from supporting that suggestion; it does not mean no activity happened. Editing or removing a screen review invalidates an older pending suggestion that used the observation. No model is trained, invoked or approved by saving a label.

For broader changes, **Edit in Learn** changes the observation's notes. Changing those notes clears both the earlier model interpretation and your screen reviews while preserving original text and samples. Reverting the notes does not recreate cleared reviews. Day/origin changes, recognition reruns and same-file retries preserve individual screen reviews. Deleting the observation removes them.

If saved screen reviews cannot be read, MORE removes their interpretation and reports the problem while preserving the original evidence. New suggestions from that recording stay blocked until you supply reviewed notes in Learn; an unreadable unknown choice must not silently become permission to reuse its screen text.

Labels remain descriptions, not verified app identities, message reads, scroll counts or measured minutes. Review any proposed routine separately before approving it.

## Keep the recording's original date

For new recordings made in MORE, **Recording details** keeps the start reported by Apple's recording output and the time zone at that moment. This stays separate from the observed day you assign for Review. Changing or removing that day, editing notes and reopening the app keep the original start. Older observations and selected files without this information remain unknown.

If the exact same recording was already imported, a retry can add missing recording-start information without changing your edits, chosen day or existing start. If recovery information is damaged, MORE keeps the recording and shows an error instead of silently discarding the information. Retry only succeeds once it can read the saved information; Discard remains your explicit choice.

These details do not establish your first phone pickup, how long an app was used, or exactly when each recorded frame occurred on the clock.

## What still needs to be built

Reliable app identities, actions and comparable morning windows need more than sparse screen samples. Current video import retains at most 24 requested frames, which can miss many transitions in a long clip. Continuous capture coverage is unknown, so review does not turn the first/last frame into time spent. Exact scroll counts, reads, likes, pickups, full habit averages and continuing adaptation remain open work in [#21](https://github.com/gibouu/morning-operator/issues/21) and [#11](https://github.com/gibouu/morning-operator/issues/11).

The new review stores no additional media, sends no data and does not train a model. [Observation metrics](OBSERVATION-METRICS.md) covers the evidence contract; [architecture](ARCHITECTURE.md) describes local persistence and inference; [privacy](PRIVACY.md) explains removal and separate copies.
