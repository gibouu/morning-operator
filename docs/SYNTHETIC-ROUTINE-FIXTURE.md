# Long synthetic routine: two separate paths

This development corpus contains **only invented SYNTHETIC data**. It adds no
app entry point, account, production capability, network request or executable
provider payload. Scripts and benchmark JSON are outside the app targets.
Separately coordinated DEBUG runtime checks are not an ordinary-user fixture
mode and do not turn the portable oracle into executable provider actions.

The fixed inputs are [scenario.json](../Benchmarks/routine-fixture-v1/scenario.json)
and the separately authored [expected-parsed.json](../Benchmarks/routine-fixture-v1/expected-parsed.json).
Freeze their hashes **before** extraction. Rendering uses scenario data, never
expected output to choose pixels. The oracle is not passed to OCR or a model.
Source pictures are drawn storyboards, not screenshots of running apps or a
native screen recording. Every image carries this disclosure.

| Path | Input | What it can establish |
| --- | --- | --- |
| Real extraction and context classification | MP4 only, through existing opt-in services | Actual decoded samples, Vision OCR/layout, real local-model requests or an honest unavailable/failed result |
| Direct parsed oracle | `oracle-draft-fr/en.more-routine.json` | Downstream import, review and edits of a known ten-moment synthetic draft; no OCR or model evidence |
| Separate DEBUG runtime checks | Explicitly reviewed configuration, timed moments or isolated simulated transports | Session/timer behavior and individual dialogues; not execution of all ten scenario actions or a real provider effect |

The portable document is the existing `PortableRoutineDocument` format:
`sourceIsSynthetic=true`, `approvalAtExport=false`, ten moments. It carries no
targets, automation, operation payload, preference journal or approval authority.
Import creates a draft. It cannot by itself execute Gmail, Slack or Reminders.
The oracle's separate personal choices and expected actions are **test
instructions**, never commands learned from a web page or mail. Any later
simulated runtime check must remain explicitly DEBUG-only and isolated from real
services.

## Fixed story and expected matrix

| Moment | Planned minutes after personal edits | Expected case |
| --- | ---: | --- |
| Agenda | 2 | Two events; primary calendar distinguished from a namesake |
| Gmail | 5 | Choose mail 3, draft six blue cards, correct to eight green, review, one **simulated** send |
| Slack | 3 | One simulated attempt becomes uncertain; no retry; uncertainty survives continuation and recap |
| News | 4 | Second observed same-origin link, attributed article body, return to list; same session/step/remaining budget |
| Feed | 3 | Four source minutes do not override the person's three-minute choice; pause/resume without a new budget |
| Videos | 3 | Two invented player items; no claim of real service control or actual viewing |
| Reminder | 1 | Exact title and 16 October 2026, 09:25 Europe/Paris; one simulated write |
| Reading | 3 | Existing Keep survives omission, renaming and revised sources |
| Music | 2 | Drawn invented player; source movie contains no audio |
| Recap | 2 | Explicit user-added configuration, never inferred from MORE's own screen |

The final candidate is 28 minutes. This is a **chosen plan**, not a sum of
measured complete phone use. Its apparent equality to the source movie length
does not establish coverage: the source includes negative scenes and omits the
configured recap; a personal duration also differs from source duration.

Negative source scenes are MORE's observation screen (exclude from personal
activity), a sign-in screen with empty fields, unattributable content, and two
apps called Journal without a verified human distinction. Namesakes remain
unselectable until explicitly corrected; exact internal identities never become
technical labels in the ordinary choice. A shopping advertisement cannot undo
an existing exact Exclude. No source pixels can authorize Keep/Exclude, sends,
reminders or approval. The oracle separately supplies those choices.

Additional fault expectations cover source revision, changed personal choices,
stale article links, redirects/non-2xx, privacy reset and repeated uncertain
Slack attempts. These expectations are not recorded runtime successes.

## Distinct clocks and sampling limits

The 27-scene realistic movie lasts **1,680 seconds (28 minutes)**. The accelerated
movie lasts **180 seconds** with its own explicitly declared per-scene durations.
Neither has been stretched to align with a future model response. The fictional
date/zone are scenario context, **not proven capture metadata**. No native phone
or installed-app identity is established by a drawn header.

The separate future execution budgets are 1,680 seconds at the selected plan's
pace and 120 seconds in QA acceleration. Execution timing, source presentation
time and callback/request times must remain separate. An accelerated frame's
time never becomes minutes of realistic usage.

Current import is bounded to **31 minutes, 512 MiB and 24 samples**. Sampling
evenly covers the selected movie; it is not continuous activity measurement. The
context model sees a further bounded header excerpt, currently 320 characters
and six nonempty lines, so retained OCR text is not necessarily model input.

The initial coverage forecast uses the existing sampling formula without moving
any scene. It is only a forecast. Decode failures, actual native timestamps,
truncated text and input omissions must be checked after real extraction. Brief
Gmail choices/corrections, pauses and negatives can be missed. Missed scenes are
unproven, not classifier mistakes and not zero usage. All nine broad activities
are expected to have at least one sample; no tap, send, exact foreground duration
or implicit habit can be inferred from that fact.

The unchanged realistic timeline's forecast misses `agenda-detail`,
`gmail-choice`, `gmail-sent`, `news-list`, `feed-pause`, `reminder-edit`, `login`,
`ambiguous` and `homonyms`. The accelerated forecast misses `gmail-list`,
`feed-pause`, `reminder-edit` and `ambiguous`. A missing scene never gets marked
as seen just because another scene from the same broad activity was sampled.

## Reproduce locally

Already-installed Python with Pillow, ffmpeg and ffprobe are required. Nothing
is downloaded. Encoding uses one worker, no audio and five frames per second.
Rendering stops if source text would overflow rather than hiding it.

```sh
python3 scripts/make-routine-fixture.py --run long-v1
```

Outputs go only to ignored `work/routine-fixture/long-v1/`: per-scene PNGs,
contact sheets, offline news HTML, four MP4s (FR/EN × realistic/accelerated),
ffprobe receipts, per-profile timelines, manifest hashes and two portable drafts.
An existing run is never overwritten. `--images-only`, `--languages fr` and
`--profiles accelerated` bound an optional smaller generation. No server is
started and no `.invalid` link is requested.

Short negative diagnostics use a separate declared clock, for example:

```sh
python3 scripts/make-routine-fixture.py --run negative-more-v1 \
  --scene more-front --scene-seconds 12
```

Repeat separately for `login`, `ambiguous` and `homonyms`. Each diagnostic has
its own MP4, timeline, hash and `isIsolatedDiagnostic=true`. The default 12-second
clip should yield six requested samples under the current policy. It never
replaces or extends the long source's coverage. These controlled explicit
examples establish neither general classifier accuracy nor ordinary service UI.

The manifest records generator/scenario/oracle hashes, exact source revision,
dirty status, movie hashes and ffprobe durations. Media bytes stay local and are
never committed. Hash equality is not evidence of real model execution.

First inspect the pictures and ffprobe receipts independently. Then obtain a
forecast, which exits **4** because no actual pipeline has run:

```sh
python3 scripts/score-routine-fixture.py \
  --manifest work/routine-fixture/long-v1/manifest.json \
  --timeline work/routine-fixture/long-v1/realistic-fr.timeline.json \
  --output work/routine-fixture/long-v1/forecast-realistic-fr.json
```

Root coordinates package/model runs on the chosen source/build. The existing
`ObservationLayoutMovieIntegrationTests` uses `MO_LAYOUT_VIDEO_PATH` and
`MO_LAYOUT_REPORT_PATH` for actual Vision extraction without a model. The separate
`ObservationContextModelIntegrationTests.selectedMovieInferenceAndReport` uses
`MO_RUN_MODEL_INTEGRATION=1`, `MO_OBSERVATION_VIDEO_PATH` and
`MO_OBSERVATION_REPORT_PATH`. Leave `MO_OBSERVATION_FIXTURE_CATALOG` unset for the
default no-vocabulary path. The complete route,
`RoutineMovieProposalIntegrationTests.selectedMovieToRoutineReport`, uses
`MO_RUN_MODEL_INTEGRATION=1`, `MO_ROUTINE_VIDEO_PATH` and a new
`MO_ROUTINE_REPORT_PATH` under ignored `work/`. It exports `videoEvidence`, the
source fingerprint, classification, preparation/progress counters, omissions and
the proposal or the actual failed/unavailable stage. None of these routes
receives the oracle, scene log, hidden voice cues, preference journal or intended
actions.

Only **after** that report is saved, rerun the scorer with `--actual REPORT.json`
and a new output path. It uses `actualTimeSeconds`, keeps missing actual times
unmapped, names all unsampled scenes, reports conditional literal OCR recall and
its whole-source denominator, and preserves context decisions, exact-quote
support, model status, failures, omissions and source truncation. OCR line
confidence is separate from model confidence; this adapter exposes no numeric
classifier confidence. Its context labels do not measure semantic fact accuracy.

For legacy extraction/classification reports, exit **0** means a diagnostic
comparison against completed classification, **not product acceptance**. Exit
**4** retains forecast-only, extraction-only or incomplete/unavailable results.
Those older reports lack a movie hash: verify the native invocation and source
hash separately; a filename is not a cryptographic source binding.

The full-pipeline report has a separate contract, not a reconstructed legacy
classifier report. Its complete-file SHA-256 and byte count are compared with
the frozen manifest when present. An invalid/mismatched fingerprint (or missing
matching manifest entry) exits **3** without comparing the oracle. Exit **0**
requires a completed pipeline, matching fingerprint, completed classification
without failed batches, and an unapproved one-to-ten-moment draft whose citations
the application validated. This remains a **source-validated draft report**, not
independent semantic accuracy, user approval or execution. A failed/unavailable
pipeline stays exit **4**, even if classification completed.

`preparedModelRequestCount` and `preparedSubmittedCharacterCount` describe
preparation. `proposalProgressTotalRequests` and `proposalCompletedRequests`
retain the announced total and completed callbacks; absent callbacks remain
unknown rather than zero. Repacking may change that total. These counters do
not establish how many proposal requests were actually attempted, and never
turn a partial result into a successful proposal.

For native review later, follow the current Home contract: Play/Pause and
Paramètres/Settings are the entry points; commands and interaction live in
Settings. This corpus introduces no permanent transcript, form or action panel.
Physical voice/acoustics, account behavior and real external effects remain
unverified by both synthetic paths.

## First retained checkpoint — 16 October 2026

The fixed corpus/oracle and portable drafts were pushed as `8242faf` and
`3e0e7f0`. The two tracked portable JSON files can be consumed through
`#filePath` by a separately coordinated Core contract test. At this first
checkpoint, no package test or app source was changed in this fixture worktree.

- First render attempt `work/routine-fixture/long-v1/` stopped on the long
  visible news URL instead of truncating it. Its failure receipt and incomplete
  pictures remain local. Soft wrapping was corrected without changing source
  text or any scene duration; the successful attempt used a new directory.
- Immutable `work/routine-fixture/long-v1b/realistic-fr.mp4`: ffprobe **1,680.0s**,
  6,054,068 bytes, five fps, no audio. SHA-256
  `ae1e088bcb8230d027ecea57498c38afc9ce0901db5b28c8f40b34b0f2dcd683`.
- Immutable `accelerated-fr.mp4` in the same directory: **180.0s**, 2,070,883
  bytes, five fps, no audio. SHA-256
  `828554d4ae2ecd75b0a286432c0e572fb7992c2c2f4c068026f6f97e012860fe`.
- The source's scenario/oracle hashes and generator hash are retained in its
  final `manifest.json`. Later script fixes do not retroactively change that
  receipt or its movie bytes. The eight isolated FR/EN negative clips each
  finalized at **12.0s**, five fps, no audio; their absolute paths and hashes are
  indexed in ignored `work/routine-fixture/negative-assets-v1.json`.
- An independent FFmpeg decode retained frames with actual PTS **0, 300 and
  700 seconds** in `work/routine-fixture/pixel-review-v1/`. Visual inspection
  confirmed the MORE text, corrected eight-green-card Gmail draft and attributed
  article. This is a pixel review, not OCR, inference or action validation.

Root then ran the existing **real Vision extraction** against the complete
1,680-second movie: 24 observed samples, 260 OCR lines, no truncated sample, no
missing actual timestamp, 19.650s test time. The retained report is
`work/routine-fixture-validation/vision-realistic-fr-v1.json` in the acceptance
worktree, with `score-vision-realistic-fr-v1.json` from the separate scorer.

The actual samples cover **18 of 27 scenes**, missing exactly the nine scenes
forecast above. **17 of 18 sampled literal checkpoints** match; across the whole
source there are still **27 checkpoints**, not 18. The real OCR error is preserved:
at actual PTS 1,387.6 and 1,460.6, `cinq feuilles` was recognized as `cind feuilles`.
The oracle and matcher were not altered to accept that mistake. These are literal
checkpoint counts, not overall OCR character accuracy or semantic fact accuracy.

That extraction-only scorer correctly exits **4**, with classification `not-run`.
At this first checkpoint the separate actual local-model attempt was pending,
without the oracle or a fixture catalogue. No unavailable/failed generation is
replaced with oracle output; later results are recorded separately below.

Current generator revisions also provide a separate corrected offline DOM in
`work/routine-fixture/offline-news-v2/`: FR/EN lists each contain three actual
anchors, with ordinal two pointing at the frozen article URL. Only static markup
was checked; no browser, HTTPS response, article navigation or return occurred.
This directory does not mutate the earlier long movie or its manifest. At this
first checkpoint, runtime browser, voice, approval, privacy and simulated-effect
assertions remained for separately coordinated downstream checks, followed by
separate real-provider validation.

## Later validation checkpoint — 16 October 2026

The movie, timelines, scenario and independent oracle above remain immutable.
The following results have different source/build scopes and do not establish
the complete personal routine in MORE §10.

| Route and retained evidence | Verified result | Boundary |
| --- | --- | --- |
| Shared package tests, compiled products from `70427b4`; `/tmp/more-integrated-synthetic-full-v8.log` | **1,691 reported**: 4 Health + 713 Core + 974 Apple; eight optional skips, zero issues | Component/contract checks, not a model run, native UI journey or provider execution |
| Fixed-frame-slot preparation replay; `work/routine-fixture-validation/context-frame-slot-schema-budget-v2.json` | 24 selected frames, 12 batches; maximum SDK schema **2,821 UTF-8 bytes**, prompt **1,616 bytes**, instructions **4,408 bytes** | Byte measurements only, not tokens, inference or submitted model-call counts |
| Actual full pipeline v3 on `830e9cd`; `work/routine-fixture-validation/full-pipeline-realistic-fr-v3.json` | Test **failed after 183.183s**, at `localRoutineProposal`, `invalidCitation`; fingerprint matches the frozen 28-minute source | No validated proposal, approval or execution; the scorer remains exit **4** |
| Native twelve-journey lot on `830e9cd`; `/tmp/more-isolated-acceptance-ux-golden-830e9cd-round1.log` | **5 passed, 7 failed, 0 skipped**, 1,027.944s | These results predate the later UI corrections; the lot is not accepted |

V3 classification is `partialFailure`: **12 attempted batches, 12 responded,
one failed**, with **8 identified, 3 ambiguous and 13 unknown** frames. The
proposal stage records **8 originally prepared requests**, then **11 announced
after repacking and 9 completed callbacks**. The actual proposal-attempt count
is unknown. No raw response was retained to prove that duplicate sample IDs
caused the classification failure. The fixed-slot correction is not evidence of
improved model output until a new actual run completes.

The five native passes are Gmail's honest fallback, Gmail preferences plus
choice of the fourth read message, Home's five-second caption-drag behavior,
French AccessibilityXXXL Outlook setup, and cold-relaunch Reddit. In the parsed
oracle case, only the **ten-moment, 28-minute draft** was established before the
image-capture helper failed; editing, approval and restoration were **not
proved** by that run. Slack's prepare controls were unreachable after typing;
the retained captures show the keyboard open. Gmail's French largest-text fifth
choice was unreachable. These failures remain failures, including when a test
helper contributes to them.

The real Le Monde attempt observed a consent wall. No consent was clicked, and
no article-body reading or successful article-return journey was proved. The
separate eight negative FR/EN clips passed actual Vision extraction (48 samples,
528 OCR lines, all eight source hashes checked); model exclusion/proposal
behavior for those clips remains unproved. Neither check repairs unsampled
negative scenes in the unchanged long movie.

The separate ten-timed-moment runtime test is prepared, not yet a runtime pass.
It uses short declared timer budgets and claims no service action; it cannot be
reported as ten automated actions from the 28-minute story. **Pipeline v4 and
native build8 are in progress at this checkpoint, with no result recorded.**
