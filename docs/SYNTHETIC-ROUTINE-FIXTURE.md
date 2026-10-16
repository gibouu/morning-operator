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
native screen recording. Every original full-disclosure image carries this
disclosure; the separate compact contrast retains its visible SYNTHETIC marker
and synthetic run metadata as described below.

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

### Separate compact-disclosure contrast

The original full-disclosure v1 source and its failed results remain immutable.
`--disclosure-layout compact` is a separately named rendering factor, not a
replacement source or a correction of that verdict. It paints white only the
three renderer text rectangles: “No real account, send, write or like”, “OFFLINE
STORYBOARD · NOT NATIVE CAPTURE”, and “Invented content · no audio · no external
service”. Earlier references to four lines described OCR wrapping, not four
independent renderer rectangles. The top `SYNTHETIC · FR/EN` marker, every scene
block (including its synthetic mentions), layout, story, timing and oracle stay
unchanged. Full disclosure remains the default and retains the v1 pixels.

This tests whether repetitive artificial disclosure competes with task content;
it does not establish the cause of v1's failures or make the drawn UI a native
capture. The manifest records `origin=synthetic`, the chosen disclosure factor
and exact half-open mask bounds. Scopes and closed services remain unchanged.
Generate a separate PNG-only preview before any coordinated movie/model run:

```sh
python3 scripts/make-routine-fixture.py --run long-v2-compact-preview-fr \
  --disclosure-layout compact --languages fr --profiles realistic --images-only
```

That command performs no MP4 encoding, OCR, model request, import or runtime
action. A later MP4 must use a new run identifier and preserve its own hash and
comparison result; the oracle and the v1 movie are never replaced.

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
reported as ten automated actions from the 28-minute story.

## Follow-up checkpoint — unchanged movie, remaining failures

The later runs below do not replace the failed results above or establish MORE
§10. Generated media and reports remain local and ignored by Git.

| Route and source | Result | Evidence boundary |
| --- | --- | --- |
| Full movie v4, products from `70427b4`; `full-pipeline-realistic-fr-v4.json` | Failed after **393.306s**, `localRoutineProposal` / `insufficientEvidence`; source hash still matches | No draft or execution. Ten completed validation callbacks did not reveal why every batch was empty; no SDK-attempt count was available then |
| Context-only v2, products from `5a3feec`; `context-realistic-fr-v2.json` | **381.933s**, 12 attempted/12 responded/0 failed; **7 identified, 17 ambiguous** | Technical completion only. Ten ambiguities quoted the provenance banner alone; this is not semantic acceptance |
| Full movie v5, products from `f64a175`; `full-pipeline-realistic-fr-v5.json` | Failed after **104.086s**, `localRoutineProposal` / `insufficientEvidence`; unchanged **6,054,068-byte** source/hash | Nine SDK invocations, nine returns, nine validated batches, all explicitly `insufficientEvidence` with zero steps despite 10–15 admissible anchors per batch. Failure occurs at empty-list assembly; no SDK/citation failure or useful draft was demonstrated |
| Package v9, `f64a175`; `/tmp/more-integrated-synthetic-full-v9.log` | Build passed in **422.42s**. Health: **4 passed**. Core: **724 reported, 3 issues**. Apple: **997 reported, 22 issues**, eight optional skips | Full run failed. Core expectations assumed unpersisted malformed defaults and an English label. Two Apple issues concerned obsolete Connections wording; twenty involved real reader deadlines. Fixes require their own validation |
| Three reader suites alone, the **same `f64a175` products**; `/tmp/more-readers-isolated-f64-v1.log` | **31 passed**, 0.346s | No source or product deadline change. This distinguishes isolated contract success from the failed concurrent lot; it does not prove live provider availability or erase v9 |
| Native build8, frozen `75bb105` products; `acceptance-ux-golden-75bb105-round1.xcresult` | Build passed. Five journeys finished: **3 passed, 2 failed**; a sixth was interrupted, six were not run | Three Gmail cases passed, including the French largest-text fifth choice. Home failed during a testmanager accessibility snapshot, before business assertions. Outlook reached Settings but its helper scrolled away from the lazy routine row. The canceled lot is not accepted |

V5 context inference completed twelve batches with zero technical failures but
only **two identified and 22 ambiguous** frames. The two MORE frames were omitted
before proposal generation. Context decisions do not themselves grant proposal
citations or execution authority. V5's scorer exits **4**,
`pipeline-not-complete-no-execution-proof`; its newly recorded structure narrows
the defect to explicit model abstention, without proving its cause. In
particular, the synthetic source's task content must not be silently replaced
with the independently authored oracle.

The private three-moment journey imports a manual synthetic draft, configures
Gmail and Slack through ordinary UI, approves and relaunches, then tests one
session and a real timed remainder. Its Slack transport is explicitly simulated
and deliberately loses one response, which must remain uncertain without a
retry. It is prepared for native execution, **not a runtime pass**, voice proof,
video-import proof or live-provider proof.

### Next diagnostic iteration

The origin clarification alone did **not** repair generation. Full movie v6
(`d193826`, unchanged Apple products/source from `f09ad84`) failed after
**126.187s**, again at empty-list assembly. Its ten SDK invocations all returned
and validated with explicit `insufficientEvidence`, zero steps and 8–15 anchors
per batch. Context again completed 12/12 batches without a technical failure,
with two identified and 22 ambiguous frames. The source fingerprint is unchanged
and the scorer remains exit **4**. Both v5 and v6 initially prepared eight
requests; their final SDK workloads were nine and ten respectively. Metadata is
included in rebatching.

The first real two-frame synthetic positive control on `f09ad84` also failed
after **18.383s**, with one SDK invocation, return and validation but zero resolved
steps. Its aggregate diagnostic did not record the batch outcome: this control
alone cannot distinguish explicit abstention from `supportedActivities` with an
empty array. A separately flagged written-activity control and detailed bounded
diagnostics are prepared for the next iteration; neither has run yet.

| Check | Verified result and boundary |
| --- | --- |
| Package v10 on `f09ad84`, with the two real OCR tests explicitly separated | Build **19.26s**; Health **4 passed**; Apple **1,001 reported**, nine optional skips, zero issues in **19.899s**; Core **724 reported**, one English-label expectation failed. This is not a fully green package run |
| The two real OCR tests alone on the same products | **2 passed**, **49.947s**; `/tmp/more-integrated-synthetic-package-v10-ocr-only.log` |
| Core v11 on `d193826` | **725 reported**, seven issues in two media-warning tests. Two disposable Foundation probes then confirmed that the migration test's `NSArgumentDomain` overlay changes `Locale.preferredLanguages` across all defaults instances in the test process. The claimed isolation was incorrect; a per-instance test-double correction is pending validation |
| Native build9 on `bd2801a` | Build failed on the mixed fixture's use of an internal Slack initializer; no runtime |
| Native build9b on `f09ad84` | **TEST BUILD SUCCEEDED**, frozen binary/test/xctestrun hashes retained in `work/acceptance-ux-build9b-source.json`. A fixed-draft factory now exists only in DEBUG, behind the private flags and unique workspace. The mixed native journey is in progress, with no result claimed here |

Do not change production read deadlines or translate unrelated expectations to
hide a process-wide test-preference leak. Preserve the failed logs, the immutable
movie and independent oracle while repairing that test boundary.

### Controlled positive/negative checks and native fixture repair

Package v12 (`08057f5`) passed after isolating the test-only argument and
registration defaults per instance: **4 Health, 725 Core and 1,002 Apple
reported**, ten optional skips, zero issues. Package v13 (`6c51a6c`) likewise
passed: **4 Health, 725 Core and 1,004 Apple reported**, eleven optional skips,
zero issues. Both runs explicitly excluded the two real OCR tests; the separate
real OCR result above remains scoped to its unchanged media source. No
production reader deadline, application language choice or media-warning copy
was changed to hide the earlier leak.

Full movie v7 (`08057f5`) still failed after **93.999s** with ten explicit
`insufficientEvidence` responses, ten validated batches and zero steps. Context
completed 12/12 batches with zero technical failures, two identified frames and
22 ambiguities. The frozen movie hash still matched and its scorer exited **4**.
On `6c51a6c`, three actual local-model controls returned: the manually reported
activity produced one validated synthetic draft; the visual-content positive
control still abstained; and the advertisement negative control correctly
abstained. These visual controls use **constructed OCR text**, not real images,
Vision extraction or the long movie. They disprove neither missing video
coverage nor semantic defects in a returned draft.

Full movie v8 on `6c51a6c` was **operator-interrupted**, exit 130, without a
pipeline report or model verdict. At the last observation the helper had run
8m33s; a one-second process sample showed TextRecognition waiting for ANE
compilation through XPC. That sample does not prove a permanent hang or its
cause. The log, sample and separate interruption receipt remain under `/tmp/`
and ignored `work/`; this attempt is not scored as a completed pipeline.

The first mixed native run on frozen build9b **failed before approval**. The
actual screen said the synthetic import was refused: its three JSON steps
omitted the `detail` fields required by its declared portable format. This was
an invalid test input, correctly refused by the application, rather than proof
of a broken approval button. Test-only corrections add the fields, predecode
and import with the real MorningCore contract before launch, and report missing
elements without trying to read their identifiers. Build9c on `6c51a6c`
**TEST BUILD SUCCEEDED** and was frozen; its new mixed runtime remains pending.

An opt-in, test-only eight-case diagnostic now varies the original versus
explicit event/message text, English versus French, banner presence and native
video versus manual evidence type. All sources retain synthetic origin. It
never receives the long oracle, changes a source to human, or requires a
positive model output to make the diagnostic green. Validated proposals are
logged separately for semantic review. The diagnostic has not run at this
checkpoint; a technical pass with abstentions would not be product acceptance.

### Grounded rendering and the next native checkpoint

The eight-case diagnostic ran on `b589eec`: **two tests passed, 41.192s**.
Explicit event/message inputs yielded one proposed step per case in both EN and
FR, with and without the short banner. The original snippets abstained for both
video and manual evidence. These are constructed text probes, not Vision.
Independent review accepted only **one of the four positive proposals** under
the selected-excerpt rule: three summaries added a date or room from other,
uncited lines. A native exact citation alone did not establish that the summary
was grounded.

The grounded proposal schema/DTO now omits free model details. Its native
resolver supplies no factual summary; the existing renderer adds its localized
tentative note and exact citations. Manual details, personal choices, the legacy
analysis path and the public assembly contract remain separate. Nineteen tests
in three suites passed on `4addd10` (**0.585s**, build **10.29s**), covering omitted
and ignored legacy details, uncited facts, forged IDs and retained preferences.
The eight real local probes then completed in **17.801s**. Independent review
found all four positive titles and citations compatible; each still covers only
one of two input frames. Proposed 15–30 minute budgets remain poorly suited to
a quick review and do not establish measured use or full routine coverage.

The bounded OCR lane on `f57c6a3` passed its five deterministic regressions
(**0.250s**, compiled on `51295f4`). It releases the caller after 60 seconds or
cancellation, discards late output and keeps the native slot occupied until the
worker actually finishes. A video aborts on that timeout; no partial failure is
turned into another 23 pending requests. This is not yet a new real Vision pass.

An opt-in replay diagnostic retains the actual archived OCR bytes, verifies the
unchanged MP4 fingerprint before/after, and explicitly labels its reports
`replay-not-full-pipeline`. It neither re-extracts pixels nor reruns the
classifier. On `06f9848`, a single complete agenda frame without classification
still returned a validated empty result in **2.266s**, with five anchors and one
SDK invocation/return/validation. The diagnostic passed; the learning result did
not. The two additional EN/FR probes with the full movie disclosure are prepared
but have not run. None of these receipts is a new full-pipeline score.

Native build9d on `06f9848` **TEST BUILD SUCCEEDED** and its app, UI test bundle
and xctestrun hashes were sealed. Its mixed3 runtime is still in progress. The
previous removal-helper failure was independently reviewed against the capture:
two nested native buttons share the same identifier. The test now selects the
exact enabled/hittable action within the observed confirmation sheet, without
scrolling that modal or choosing Exclude. Later operations remain subject to the
actual runtime result.

The separate long10 test is now registered, statically reviewed, and compiled
in build9d; it has not run. It imports the unchanged manual oracle, configures
Calendar and read-only Gmail through UI, replaces the Slack placeholder through
account Setup, and explicitly edits the other seven moments to time-only
budgets. Its declared plan stays 28 minutes without acceleration. Mail/Slack are
left through explicit controls; therefore 28 planned minutes is not a promised
wall-clock execution time. Expected recap: seven elapsed budgets, two verified
simulated readings, one uncertain simulated Slack attempt. It does not claim
the movie's simulated Gmail/reminder sends, browser actions, audio, a complete
inferred routine or MORE §10.

A byte-identical 43-file private copy of the FR corpus now also lives in this
acceptance worktree's ignored `work/routine-fixture/long-v1b/`. Every copied file
was SHA-256 verified; no media was rerendered or committed and the original
manifest was not edited.

## Mixed3 passed; separate learning gates remain open

Frozen build9d on `06f9848` passed its single mixed3 test in **444.017s**, with
no failures/skips and unchanged sealed binaries. It configured and approved the
manual synthetic draft through UI, restored it, selected Gmail message four,
retained exactly one uncertain simulated Slack attempt without retry, and
preserved 32.155s of its real one-minute budget through pause/relaunch and a
65-second paused wait. The recap restored. Narration of the Slack read remained
incomplete; no external reply was confirmed. Voice was off in this run, so it
proves no acoustic interaction. Captures/receipt/xcresult and exact timer/body
values stay local under `work/acceptance-ux-golden-06f9848-mixed3-round1*`.

Actual new Vision extraction on `003ba4a` passes the immutable full movie in
28.753s: 24 frames, 260 lines. Their text, times, bounds, confidence and offsets
match archived v7; only generated IDs differ. The two separate real OCR tests
also pass. None of this establishes model semantics or coverage of every scene.

Model diagnostics retain their failures. D9's cited agenda candidates describe
the event tasks with 30/45-minute budgets; `003ba4a` improves budgets but returns
an inconsistent agenda outcome, rejected before assembly. Its constructed EN
contrast titles also include uncited context. The steps-only `b5ebe32`
experiment fails the actual advertisement abstention control and is reverted
in `49b04aa`; its green package run is not model acceptance. The schema stimuli,
movie, oracle and native postvalidation were not relaxed to obtain a pass.

`e81cada` attributes recap results to the exact pinned moment, keeps source
read/restoration status separate from Slack reply receipts, and preserves
browser counters per moment. Four Core + 23 Apple + 16 Slack targeted tests
pass. `4ec210f` adapts native assertions to these rows. The separate Calendar
speech smoke, long10 and follow-up lot still require new native execution.
The [QA ledger](ROUTINE-AUTOMATION-QA.md) records package/source boundaries;
full video-to-routine acceptance and MORE §10 remain open.

### Explicit selection and full movie v9

The disjoint selection schema `42dc82b` preserves the model's explicit outcome
and native strict validation. Package v16 is green: **2,077 reported tests**
(51 LiveDemo, 8 Health, 764 Core, 1,254 Apple), including 14 optional skips; two
real OCR checks are separately excluded. Actual declared-activity and advert
controls both pass (5.838s). Its single agenda-frame replay remains explicitly
empty, and the actual full movie v9 **fails after 72.747s** at proposal:
classification completes 12/12 requests, then all ten actual proposal SDK
responses explicitly abstain, with zero resolved steps. The scorer exits 4,
`pipeline-not-complete-no-execution-proof`. Completion of schema validation or
classification requests establishes no semantic identity accuracy.

A shorter dedicated instruction experiment `7c3df12` then makes both positive
controls abstain (while the advert remains excluded). It is reverted in
`30b8d4b`; retained source equals `42dc82b` for Sources/Tests. These failed
experiments do not change the movie, manual oracle, negative stimuli or native
validation. The next native build exercises the independent downstream manual
path and cannot be credited as fixing video learning.
