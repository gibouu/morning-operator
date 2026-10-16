# Long synthetic routine: two separate paths

This development corpus contains **only invented SYNTHETIC data**. It adds no
app entry point, account, production capability, network request or executable
provider payload. Scripts and benchmark JSON are outside the app targets. Root
owns the later DEBUG execution adapter; ordinary users receive no fixture mode.

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
| Future DEBUG execution | Explicitly reviewed configuration plus isolated simulated adapters | Session, timer and dialogue behavior; no real provider effect |

The portable document is the existing `PortableRoutineDocument` format:
`sourceIsSynthetic=true`, `approvalAtExport=false`, ten moments. It carries no
targets, automation, operation payload, preference journal or approval authority.
Import creates a draft. It cannot by itself execute Gmail, Slack or Reminders.
The oracle's separate personal choices and expected actions are **test
instructions**, never commands learned from a web page or mail. A later adapter
must remain explicitly DEBUG-only and isolated from real services.

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
default no-vocabulary path. Neither route receives the oracle, scene log, hidden
voice cues, preference journal or intended actions.

Only **after** that report is saved, rerun the scorer with `--actual REPORT.json`
and a new output path. It uses `actualTimeSeconds`, keeps missing actual times
unmapped, names all unsampled scenes, reports conditional literal OCR recall and
its whole-source denominator, and preserves context decisions, exact-quote
support, model status, failures, omissions and source truncation. OCR line
confidence is separate from model confidence; this adapter exposes no numeric
classifier confidence. Its context labels do not measure semantic fact accuracy.

Exit 0 means a diagnostic comparison against a completed classification was
written, **not product acceptance**. Exit 4 means forecast-only, extraction-only
or unavailable/incomplete classification. Reports currently lack a movie hash;
verify the actual invocation and source hash separately rather than pretending
the report is cryptographically bound by its filename.

For native review later, follow the current Home contract: Play/Pause and
Paramètres/Settings are the entry points; commands and interaction live in
Settings. This corpus introduces no permanent transcript, form or action panel.
Physical voice/acoustics, account behavior and real external effects remain
unverified by both synthetic paths.
