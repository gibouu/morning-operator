# Long recordings: acceptance plan

This is a test plan, not a completed result. The next ingestion change must let a saved recording produce a bounded, reviewable suggestion without asking the person to trim thousands of extracted characters. The source audit below was refreshed on **10 October 2026 against `af9e669`**; no recording, native build, model request or performance test was run for this audit. The app has separately been installed and launched on a phone, but that does not establish 30–90 minute capture or understanding. Use [PHASE-ONE](PHASE-ONE.md) for actual results and source revisions.

The acceptance journey is simple: explicitly record or select a recording, let MORE save the evidence, review what it understood, and request a routine update. The existing routine stays in place until approval. Large input must not become a giant error panel, silent data loss, or permission to invent the unsampled morning.

## Keep the limits distinct

| Boundary | What the test must establish |
|---|---|
| Recording/import | Current import and fingerprinting permit up to **31 minutes / 512 MiB**. Native recording choices are **5/10/20/30 minutes**, with a separate **256 MiB monitored stop threshold**. The one-second main-actor monitor is a stop request, not an exact byte ceiling or a verified background deadline. Test the real configured boundary separately from prompt length. |
| Source extraction | At most 24 sampled frames and the existing OCR/archive bounds remain explicit. A source beyond the OCR budget retains diagnostic samples and truncation warnings. No claim of exhaustive video understanding follows. |
| Saved evidence | The original bounded extraction, frame IDs, times, available recording provenance and source fingerprint survive save/relaunch. Selecting less text for analysis must not rewrite the saved original. |
| Inference | Each request and the total work stay within documented limits. Record submitted characters, calls, selected source ranges and omissions; do not send controller truth or expected activities to the model. |
| Output | A pending proposal has exact source citations, preserves explicit saved choices and remains unapproved. Planned minutes are not measured app time. |

The current source-linked proposal candidate uses requests of at most **1,500 Characters / 6,000 UTF-8 bytes**, at most **768 serial requests**, **512 citations per suggested moment**, **32,000 Characters per detail**, and **10 final moments**. Its exact chunks retain separators and source offsets; a single oversized grapheme is explicitly refused. These are workload limits, not a prediction that such a large request count is practical on the owner's phone. Verify progress/cancellation and report actual calls and latency. A large or fragmented output can still be refused without replacing the current routine. A larger prompt budget alone is not proof that the user journey works.

## What the current source can and cannot support

The narrow immediate path is one explicitly authorized recording of up to 30 minutes, which may stop earlier at its size threshold, then saved OCR review and an explicitly requested proposal. A 31-minute/512-MiB external import is another bounded path. **A continuous 45-, 60- or 90-minute native capture is not implemented, and a single 90-minute file is rejected.** Three separately authorized 30-minute files can be examined as three sources; that is not one uninterrupted 90-minute session.

- [ScreenRecordingService](../Sources/MorningApple/ScreenRecordingService.swift) writes screen-only H.264 MP4, reducing the longest image dimension to at most 1,920 pixels when valid filter dimensions are available. It has no implemented free-space reserve check, thermal policy or durable rolling writer. Native start and stop/finalization deadlines are 20 and 30 seconds respectively. Their operation under long background capture needs real measurement.
- [MediaObservationService](../Sources/MorningApple/MediaObservationService.swift) decodes and recognizes frames sequentially, at most 24 per file, with requested and actual presentation times and explicit failures. For a 30-minute movie the requested samples are about **78.3 seconds apart**. Raising only the duration cap to 90 minutes would produce gaps of about **234.8 seconds** with the same 24 samples. A message appearing between samples may never be seen. No model can recover its missing text from this evidence.
- [VideoObservationBuilder](../Sources/MorningApple/VideoObservationBuilder.swift) admits at most 30,000 OCR Characters / 256,000 UTF-8 bytes, consuming this budget in extraction order. Dense early frames can leave later frames truncated or empty. The warning is correct, but later sample timestamps alone do not prove later text survived. Layout metadata is bounded to 256 regions per frame. A 32,000-Character rendered result does not mean the whole movie was understood.
- [ObservationFileFingerprintService](../Sources/MorningApple/ObservationFileFingerprintService.swift) streams at most 1 MiB per read. The app fingerprints before and after extraction, adding approximately two full-file reads besides decoding. This avoids loading the entire movie for hashing; it does not establish a bound on Vision/decoder peak memory or latency.
- [PendingScreenRecordingStore](../Sources/MorningApple/PendingScreenRecordingStore.swift) has **one finalized recovery slot**, not a segment queue. There is no persisted in-progress writer checkpoint or promised recovery of an unfinished MP4 after process death. Finalized recovery retains recording-start context, interruption metadata and retry/discard controls. Successful atomic evidence save allows owned raw-file deletion; retention for later denser extraction is not provided by that saved OCR record.
- [ObservationArchive](../Sources/MorningApple/ObservationArchive.swift) allows 60 entries, 8 MiB aggregate text, 20,000 OCR regions and 16 MiB compact archive encoding. Per-entry original/correction limits are 33,000/32,000 Characters and 300,000 UTF-8 bytes. There is no automatic eviction. Current proposal selection is 1–5 dated acquisitions of one origin and one saved time zone. A future segmented session must not spend these limits as if every segment were an independent morning.

**Lifecycle correction in the sunrise revision:** the audit found that a finalization timeout marked an otherwise successful late writer result for deletion. The shared completion policy now treats the deadline as waiting, retains a later successful result, and keeps explicit discard/Forget and real errors sticky. The selected lifecycle/recovery suite passes 28 test declarations across five suites, including five new declarations/eight cases. Native compilation and an actual delayed hardware callback remain separate evidence; see PHASE-ONE. A process killed before the writer closes is still not promised recoverable.

Unsupported email/message-provider access is a separate capability gap. Screen capture of Mail, WhatsApp, WhatsApp Business, iMessage or Messenger must be verified on the actual selected surface; a blank/protected/unavailable result stays unknown. A long synthetic fixture run does not establish any of those connectors or private-app capture paths.

## Bounded 30–90 minute validation ladder

Run only the stage the installed source actually supports. A correct unsupported-duration rejection is boundary evidence, not a long-recording success. Use the [digest protocol](DIGEST-TEST-PROTOCOL.md) for independent seeded content, source citations, runtime receipts and exact-fact scoring; do not feed controller truth, seed or expected output into inference.

| Stage | Required evidence and decision |
|---|---|
| Five-minute pilot | Record synthetic screens through the real native path. Measure baseline/peak memory, raw-byte growth, battery/thermal state, stop latency and extraction latency. Confirm finalization, review, cancel/retry and relaunch before extending duration. |
| Current 30-minute ceiling | One actual 30-minute request with verified beginning/middle/end content. Record actual duration and any earlier size/system stop. Static low-motion and scrolling/high-change variants are separate trials. Reachable/saved text is required; this is not yet exhaustive understanding. |
| Current negative boundaries | Production import of a valid encoded movie just above 31 minutes and a file above 512 MiB must reject without replacing the current observation/routine. Label manufactured boundary media as such. Verify native size-limit stop using measured growth; do not fill the owner's disk to provoke a failure. |
| Future 45/60/90-minute path | **Blocked until durable segmentation, bounded storage and recovery exist.** Once implemented, test these durations in order. Do not display a 90-minute preset while the writer/import/archive path still has shorter incompatible limits. |
| Held-out repetition | Repeat the supported path with at least two new seeds after the initial run, changing sender/date/body/order and short/long screen holds. A replay proves reproducibility only; it is not held-out accuracy. Keep every failed or interrupted attempt. |

Before each run, save a local manifest: source revision/build, OS/device class (no public device identifier), consented duration, source kind/origin, requested sampling policy, model/provider availability, declared performance budgets and fresh artifact paths. Record monotonic controller bounds alongside wall time/zone; never equate a callback start timestamp with media PTS zero without measured alignment.

Use Xcode's native memory/CPU tools or Instruments for actual process physical footprint, with device storage available capacity at start and fixed intervals. Record at least every 30 seconds: memory footprint, raw/temporary/retained bytes, free space, thermal state and interruptions. Capture stop/finalization, each fingerprint, each decode/OCR, save and model request as separate stages. Do not substitute movie byte size for memory, or decoder completion for saved evidence. Metrics collection must stay local and must not log source text.

Declare the device-specific memory budget, minimum disk headroom and stage deadlines **before** testing, based on the pilot and target hardware. Publish the chosen budgets with the result; do not invent a universal safe iPhone memory limit or revise thresholds after seeing a failure. Require no unexplained sustained memory growth across the second half of a steady-content trial, no OS termination, no exhausted storage, and successful bounded cancellation. A run without real resource measurements is incomplete. Disk admission for a future segmented implementation must reserve the active writer, at least one finalized pending segment, temporary/atomic-save overhead and an explicit safety margin; queue backpressure must stop recording visibly before that reserve is exhausted.

Report four separate denominators:

1. **Controller-visible facts/events:** all independently verified scripted content across the whole run, including short-lived content deliberately placed between sampling opportunities.
2. **Sampling coverage:** requested/decoded/OCR-observed/blank/failed/truncated frames, actual PTS, duplicate timestamps, longest sample gap and beginning/middle/end coverage. Unknown intervals remain unknown.
3. **Retained source coverage:** exact bytes/regions retained versus omitted, by time window; explicitly show useful late text lost to the OCR budget. No silent prefix-only pass.
4. **Inference accuracy:** attempted/responded/failed calls, exact supported and unsupported facts, wrong source/sender/date, stale/duplicate claims, explicit unknowns and missing facts. Measure both recall of whole-run controller facts and recall conditional on facts actually present in retained input; the latter cannot hide sampling loss.

For speech, separately inspect the exact prepared text, actual synthesis completion, independently obtained transcript and owner-audibility/route result. The scorer's transcript comparison does not establish pronunciation or audible playback. Unavailable inference or audio remains blocked/skipped, never a successful empty summary.

## Minimum architecture before extending to 90 minutes

1. **One durable session manifest, bounded segments.** Record consent, immutable session ID/start context, local zone, privacy generation and ordered segment identities/statuses. Use measured time/byte boundaries; choose segment budgets from the pilot. Verify native writer rollover and any gaps on the installed SDK/device before claiming seamless capture. Do not assume adding/removing outputs is gap-free.
2. **Finalize and checkpoint before reusing capacity.** Each completed segment gets immutable bytes, a fingerprint, interruption information and an atomic queue record. Extraction/retry can resume after relaunch. Never overwrite the current recovery slot with the next segment. In-progress process death must report the uncertain tail, not claim complete recovery.
3. **Bound decoding/OCR and apply backpressure.** Process a small bounded number of frames at a time, checkpoint completed work, and use a documented per-window sampling budget. Retain unknown intervals and actual timestamps. More points or scene-change sampling still do not reveal taps, reads, exact foreground app time or intention.
4. **Keep source identity and limits coherent.** Multiple chunks from one movie need segment ranges/identities under the same logical source; existing full-file SHA dedup cannot simply insert each chunk as a different acquisition. Group one recording's segments as one morning, preserve source-date/time-zone semantics, and reject overlapping/conflicting segments. Plan aggregate OCR/archive retention and selection limits together; do not only raise a duration constant.
5. **Preserve policy and explicit approval.** Cancellation, source correction/deletion, permission loss and full forgetting invalidate late work. Persist supported evidence before raw cleanup, leave the approved routine untouched, and offer one reviewable pending proposal with source ranges/omissions. If raw retention for re-extraction is required, make its scope/expiry explicit rather than silently retaining more content.

Adversarial recovery cases: background/foreground transitions; device lock; system capture stop; a successful writer callback arriving after its deadline; cancellation during decode/OCR/model; a crash between segment finalization/manifest/save; missing or corrupt sidecar; duplicate completion; changed file bytes; archive full; controlled save/no-space failure; unreadable/protected/blank intervals; and forgetting while a writer is closing. Record each stage as passed, failed, blocked or skipped. Preserve old data and the recoverable finalized portion unless the person explicitly discards or forgets it.

### Built so far: the session manifest, in shared logic only

**No phone has run this.** The live recorder still writes one file of at most 30 minutes; nothing in the app creates a session yet, and full forgetting does not yet call the session store because no session can exist. What exists is the model and its rules, tested with small fake files and an injected clock.

- **One policy value.** `SegmentedRecordingPolicy.provisional` holds every size: a segment ends at **5 minutes or 64 MiB**, whichever comes first; a session ends at **90 minutes or 18 segments**; 12 sampled frames per segment (216 per session); 180,000 Characters of text per session, shared equally (10,000 per segment). These numbers were chosen on 13 October 2026 without a measurement. The pilot changes them in that one value; a manifest stores the policy it was recorded under.
- **The manifest** (`RecordingSessionManifest`, saved atomically as `RecordingSessions/<session>/session-manifest.json`) lists ordered segments with their time range on the session's clock, file fingerprint, state and what was derived. It refuses, when changed and when decoded, an unknown version, an index gap or repeat, an overlapping or backwards time range, and a segment started before the one ahead was sealed.
- **A crash** loses at most the open segment. Relaunch compares manifest and folder in both directions (`RecordingSessionStore.reconcile`): sealed segments stay analysable, the lost tail is reported with an unknown end, and a file the writer had already completed is kept for sealing.
- **Analysis** goes one sealed segment at a time and can stop and resume. A segment's raw file is released only after its text is saved and recorded. A failed segment is reported as a missing time range, never as a range with no activity, and the others are still analysed.
- **In the archive**, each segment is one observation carrying a reference to its session and index. Existing limits are unchanged, so today a segment uses one of the 60 archive entries, one suggestion takes at most five observations (25 minutes of one session), and a day with several segments is excluded from the comparable-morning profile as a day with more than one recording. Counting per session instead is a later decision.

Worst case on disk under the provisional policy: 68 MiB per segment (64 MiB plus a 4 MiB allowance for the one-second size monitor), so **1,224 MiB of raw video** for a 90-minute session if nothing is analysed before capture ends, and 1,482 MiB of free space asked for up front (raw, a 256 MiB reserve, the manifest). One more segment needs 324 MiB free to start. If the pilot shows analysis keeps pace during capture, a backlog limit of two sealed segments bounds the peak at 204 MiB.

The pilot must measure, to replace these numbers: bytes per minute for still and for scrolling content; how far a file runs past its size limit before the writer stops; whether a rollover loses frames and how long the gap is; the offset between a segment's start reading and its file's first frame; whether extraction can run while the phone records in the background; peak memory and time to extract one segment; and free space at start and end.

Suggested issue scope: **[#27](https://github.com/gibouu/morning-operator/issues/27)** owns the late-finalization preservation fix, bounded recording segments, durable queue, source grouping, resource admission and an honest 90-minute gate. **[#23](https://github.com/gibouu/morning-operator/issues/23)** owns the measured duration ladder, repeated seeded held-out truth, whole-run versus retained-input recall, source attribution, failure injection and separate physical-app capture proof. These are proposed updates, not newly completed acceptance criteria.

## Controlled sources

Use an isolated test workspace and synthetic content only. Keep the expected sequence outside the app's input.

1. **Long readable source:** text exceeding the old 8,000-character input ceiling but within the archive limit. Put distinct, ordinary activity evidence near the beginning, middle and end. Keep exact original bytes for comparison.
2. **Structured video evidence:** complete eligible frames across the full movie, including dense frames, repeated screens, one unknown/failed frame and a user-reviewed unknown. Include useful later evidence so prefix-only selection cannot pass.
3. **Long movie import:** a real encoded synthetic movie whose readable screen text exceeds the former ceiling. Include static holds and sparse changes. Import the actual file through the production loader; a manufactured evidence envelope does not substitute for this check.
4. **Native capture:** a separately authorized, bounded recording on the owner's iPhone, using non-sensitive test screens. This is a separate result from an encoded movie, simulator capture or synthetic text fixture.

At least one fixture should contain only setup/marketing/picker text; another should mix those screens with real task content. Long irrelevant text must not defeat the existing activity-evidence guard.

## Required checks

| Journey | Pass condition |
|---|---|
| Import and relaunch | The full bounded extraction is readable in Learn/original evidence after relaunch. Import alone performs no inference and leaves the approved routine unchanged. |
| Prepare a long source | No whole-input 8,000-character refusal for a supported saved acquisition. The preparation covers the intended parts of the source according to its documented selection policy, retains exact source offsets and discloses anything omitted. |
| Fair multi-source selection | Every selected eligible acquisition contributes according to the documented policy. The app does not silently drop a later source or silently change a human/sample or time-zone partition. |
| Exact grounding | Each accepted quote matches the correct original/correction/frame bytes and offsets. No quote crosses unrelated frames or acquires a fabricated app identity, tap, read or scroll count. |
| Unknowns and exclusions | Truncated/failed/explicitly unknown frames cannot support claims. Selection warnings distinguish unsupported evidence, source truncation and budget exclusion; omitted content is not represented as absent activity. |
| Local model unavailable | The saved observation remains readable. Unavailable means no result, not a successful empty routine or a synthetic fallback. Record model attempts separately from successful responses. |
| Cancel or source change | Cancel during preparation or generation, edit/delete/re-date a source, or forget local data. A late result cannot replace the routine, restore erased evidence or install stale citations. |
| Save failure/recovery | Fail the workspace save after extraction. The prior workspace remains intact and an owned recording remains available for Retry/Discard. Successful persisted extraction permits recovery cleanup; later inference failure does not erase saved text. |
| Pending review | A valid response opens or offers the exact pending proposal, with selected source dates and omissions. Dismiss/relaunch preserves the pending review. Only explicit approval replaces the current routine. |
| Short-source regression | Existing short observations, guarded setup-only input, source corrections, kept/excluded moments and planned-duration preferences retain their behavior. |

Shared deterministic tests should exercise the selection, exact citations, bounds and stale-result behavior without calling Apple models. Native UI tests should exercise the production saved-source path, persistence and review controls. A marked test response may test presentation, but must never be reported as model inference.

## Real inference and recording evidence

For a supported local model, report availability, attempted/responded/failed calls, source length, selected length and elapsed time. Compare the proposal with independently recorded ground truth: supported claims, unsupported claims, omissions and explicit unknowns. A model response or syntactically valid proposal alone is not an accuracy pass.

For the native recording check, record explicit system authorization, actual stop/finalization, import, saved-text review and relaunch as separate observations. If the system panel remains visible, document the required manual dismissal. A saved callback start time is not proof that media time zero is the first captured pixel; movie duration and sampled frame timestamps do not establish continuous context or phone-use duration.

Do not claim whole-morning duration, app opens, reels, reads, scrolling or comparable week averages from this test. Those need their own evidence and [metric definitions](OBSERVATION-METRICS.md).

Keep movies, source text, screenshots and detailed reports local in ignored test artifacts. Publish only the source revision, test boundaries, aggregate counts and results. Preserve failed attempts alongside corrected reruns; identify exact synthetic, simulator and physical-device evidence separately.
