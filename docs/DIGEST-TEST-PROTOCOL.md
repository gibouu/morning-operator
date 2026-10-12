# Repeatable morning-digest test protocol

**Acceptance plan · 10 October 2026.** This protocol is not a completed digest benchmark. The repository already has native fixture capture, Vision extraction, bounded local-model requests, validated source evidence and supported speech paths. A complete daily digest combining them still needs implementation and an actual supported-device trial. Use [PHASE-ONE](PHASE-ONE.md) for results, not this checklist.

The deliverable is one reproducible chain: **actual source → captured or directly retrieved evidence → real model output where needed → validated facts → the same displayed and spoken brief**. Record each stage separately. An unavailable model, unreadable app or skipped audio check cannot become an end-to-end pass.

## Keep the two questions separate

| Daily digest | Habit learning |
|---|---|
| What relevant, supported information is available for this particular morning? | What activities recur across genuinely independent mornings? |
| Needs source scope, current date/zone, retrieval/observation times and freshness. A historical screen quote is labeled historical. | Needs separate dated acquisitions, comparable coverage, origin and explicit review; one clip or repeated playback is insufficient. |
| A visible message can support a minimal quoted fact, not an entire-inbox count. | A sampled screen appearance does not prove a tap, read, reel, duration or independently chosen habit. |

A model-generated routine is not proof that a daily digest is accurate. A correct digest on one day is not proof that the app has learned a typical morning.

## Record the run before starting

Use a new isolated UUID workspace and fresh artifact folder per run. Record source commit/build, actual device/OS, model type and availability, test mode, language/output route, source configuration, capture window and time zone. Keep personal raw media, transcripts and device identifiers local. Use reviewed summaries when sharing results.

The controller/scorer keeps a separate manifest of seeded content and intended actions. The model receives only the allowed media/OCR or authorized direct-source facts, stable source/sample IDs, order and timestamps. **Do not supply the controller trace, expected answer, expected counts or expected sequence to inference.** Any independent app-header catalog must be declared and unchanged across seeds. Freeze the model result before the scorer opens the truth manifest.

The [two-app benchmark](OBSERVATION-BENCHMARK.md) now has a separate seeded digest variant in source. Its historical baseline/held-out runs are not fresh digest trials. Build or reuse `MorningObservationBenchmark` products from the same source revision using that guide, then run:

```sh
python3 scripts/run-observation-benchmark.py \
  --device "$MORE_SIMULATOR_ID" --run digest-seed-01 --variant digest
```

Repeat with new run names for seeds 02 and 03. Omitted seed generates fresh content; `--seed <16hex>` explicitly replays a saved seed using `seeded-fixture-v1`. Each run saves `fixture-content.json`, `capture-metadata.json` with seed/version/content hash, `recording.mov`, logs and `test.xcresult`. Its schema-2 truth attachment contains verified `digestSource` rows, actual visible strings and field-specific evidence IDs. Digest mode opens row 01 in Cedar Mail and Lumen Calendar and holds each detail for twelve seconds; the script/data alone do not prove that native run succeeded.

The generator's syntax/pure checks and native benchmark build pass. The first actual seeded capture, `digest-handoff-01`, passed **1/1 in 81.623s**, with 20 controller events and two verified `digestSource` records. Fresh Vision extraction passed **1/1 in 52.698s**: 24 samples, 460 regions and 24 prepared frames across 11 batches. An independent whitespace-folded check found all **11 required field strings somewhere in OCR**; source attribution and comprehension were not evaluated. This establishes one capture/extraction run, not the three-seed gate. Full outcomes are in [PHASE-ONE](PHASE-ONE.md).

The semantic digest adapter remains absent. Its explicit blocked-stage artifact has no claims; the real scorer returned **exit 3**, null fact metrics and speech not assessed. No model or spoken digest pass follows from the OCR result. A reproducible capture command is:

```sh
python3 scripts/run-observation-benchmark.py \
  --device "$MORE_SIMULATOR_ID" --run digest-handoff-01 \
  --variant digest --seed 0000000000000001
```

Do not reuse an existing run directory; use a new name for a repeat. Keep independent scoring under [#23](https://github.com/gibouu/morning-operator/issues/23) and the digest implementation under [#28](https://github.com/gibouu/morning-operator/issues/28).

## Three fresh synthetic seeds

Prepare three independently generated datasets, labeled **seed 01, 02 and 03**, before evaluating output. These labels identify the trial records; keep each actual hexadecimal seed in its saved metadata.

- Vary subjects, names, dates/times, quantities and meaningful content—not just source UUIDs or filenames. Include at least one useful fact and one irrelevant item per dataset. Do not encode the expected answer in a visible heading.
- Use a declared local date/zone and synthetic origin. Include different app orders and return visits, plus a blank/protected/unclear screen where the correct output is unknown.
- Render the generated content in the actual native fixture apps and record the real UI. Seed truth is not passed into the extractor/model. A manufactured `ObservationVideoEvidence` envelope is a unit-test input, not a captured movie.
- Use a new workspace and source hash for each run. Preserve all attempts, including failures. Score the third seed without tuning to its output; any later correction needs a new held-out seed.

Calendar/Reminders fixtures may use an injected provider for deterministic logic tests. They do not prove EventKit authorization or real device data access. Label the source adapter in every artifact.

## Stage gates

| Stage | Execute and retain | Pass boundary |
|---|---|---|
| 1. Source/capture | Actual fixture movie or explicitly scoped direct-source response; separate issued actions and observed postconditions. Record interruptions and actual finalization. | Intended source is genuinely present in the captured/retrieved evidence. A tap command alone is not its postcondition. Blank/protected content stays unavailable. |
| 2. Vision/ingestion | Run real extraction. Retain original bounded text, sample IDs/order, requested/actual media times, rational timestamps when present, truncation/failure warnings and source digest. | Saved and reopened evidence matches extraction. Report lost/missing target facts and sample coverage; do not infer continuous capture from movie duration. |
| 3. Real inference | Invoke the actual ready model on allowed evidence. Record attempted/responded/failed requests, input selections/omissions and sanitized failure categories. | Genuine returned output exists. An availability preflight, deterministic replay, canned fixture response, skip or failed request is not a model pass. |
| 4. Fact validation | Validate every proposed fact against its current source and exact supporting quote/provider field; preserve source date, scope, freshness and unknowns. Reject invalid IDs, fabricated quotes, stale/deleted sources and unsupported totals. | Every fact admitted to the brief is grounded and correctly scoped; unsupported claims are rejected rather than narrated. Report accepted/rejected/omitted facts and scorer disagreements. |
| 5. Display/speech | Save the immutable prepared test transcript locally, show that exact content, then invoke the real native speech path. Record actual enqueued text, completion/cancel/failure and output route; obtain listener confirmation separately. | Displayed facts and spoken text agree. Actual audible delivery requires a listener check; synthesis callbacks alone establish only the system playback path. No source is silently refreshed into different facts during Repeat. |

Do not bypass an unavailable stage to continue the “real” run with a mock. Deterministic validator/UI tests may run separately with explicit synthetic labels. Existing visible-context classification and routine proposals are not a ready-made typed digest schema; a digest fact/validation layer must be implemented before claiming Stage 4 for the combined product.

For each seed, report ground-truth facts observable in the actual retained input, exact fact precision/recall over that declared set, unsupported claims, omissions, unknowns and source/citation failures. Report extraction recall separately from model recall so an OCR miss cannot be hidden as a reasoning error. Tiny fixture scores are not general accuracy estimates. An overall digest pass requires all required stages on all three seeds; a partial run reports its last established stage.

## Score an actual result independently

The [versioned digest contract](../Benchmarks/morning-digest-contract.md) defines the actual-output schema, held-out truth, independent source alignment, runtime receipt and optional speech transcript. The scorer is implemented; **the semantic digest model adapter is not**. Fourteen synthetic Python tests check scoring behavior, not model quality.

After exporting the verified truth attachment and freezing the actual adapter output, run from the repository root:

```sh
python3 scripts/score-morning-digest.py \
  --truth work/observation-benchmark/RUN/ground-truth.jsonl \
  --actual work/observation-benchmark/RUN/actual-digest.json \
  --report work/observation-benchmark/RUN/digest-score-01.json
```

Replace `RUN` with the completed run folder; the output must be new. When independently produced, add `--alignment alignment.json`, `--receipt native-runtime-receipt.json` and `--speech speech-transcript.json`. Do not invent those artifacts to satisfy a gate. Model-side IDs must be aligned to hidden controller IDs only after generation, using visible evidence rather than expected-answer matching. The report contains counts, hashes and error categories, without source text or transcripts.

Read `factMetrics`, `inferenceEvidence` and `speech` separately. Exit **4** means matching but unverified/hand-authored output; exit **3** means skipped, blocked or failed. Exit **0** requires exact supported facts and a matching separate runtime receipt, but the receipt is still an attestation: inspect the native requests and artifacts before claiming actual model execution. It proves neither narrative quality nor audible delivery. Unknown/missing denominators stay null; duplicate, stale, wrong-source and unsupported claims remain visible. Full exit meanings and schema examples live in the contract so the protocol and implementation do not drift.

## Adversarial cases

Run these against the same production validation/playback boundaries; changes affect only synthetic or expressly chosen test data.

| Case | Expected result |
|---|---|
| Deleted or corrected source after preparation | No stale replay or automatic advancement. Re-review/reprepare explicitly; original evidence and user corrections remain distinguishable. |
| Stale, revoked or missing source | Typed unavailable/stale state; no fabricated zero, “nothing new,” complete-inbox claim or old fact presented as current. Other valid sources may remain useful. |
| Duplicate import, provider ID or repeated frame | No extra fact/count/day merely from duplication. Preserve distinct occurrences only when the source contract distinguishes them. |
| Wrong date, zone or future retrieval timestamp | Reject or explicitly correct the metadata through the supported path before use. Do not substitute import time for observed day. |
| Blank/protected screen, conflicting labels or app's own recap | Unknown/abstention or explicit omission. Do not learn a recap's derived statements as fresh personal activity. |
| Mid-batch failure, cancellation or late callback | No partial published digest/proposal, late playback, duplicate effect or privacy-reset resurrection. |

## Separate physical app checks

Test each app independently on the owner's phone with explicit start/stop and minimal content. Prefer an existing synthetic/owner-controlled test account or thread. Open only the designated top conversation/message when needed, capture the smallest useful visible excerpt, then stop. Opening a conversation may change its read state; record that native behavior rather than calling the test effect-free. **Do not send, reply, like, comment, archive, delete, change account settings or traverse unrelated threads.** This protocol grants no additional account access.

| App/source | What this check establishes | What it must not imply |
|---|---|---|
| Apple Mail | Whether a specified account/surface and one chosen message are visible in that device's capture and extractable. | MessageUI is not a universal Apple Mail inbox API. A future provider/protocol connector needs its own authorization, pagination, freshness and count definition. |
| WhatsApp | Ordinary selected chat/list capture, visible text and unknown/protected behavior. | A previous screenshot check is not native ScreenCaptureKit proof. Do not bypass View Once/protected content or infer whole-account access. |
| WhatsApp Business | A separate installed-app trial with its own version, surface and result. | A WhatsApp pass does not establish Business behavior or a customer-message connector. |
| Messages / iMessage | One designated visible conversation and its actual capture/OCR result. | Carrier-messaging/default-app capabilities do not provide a general iMessage inbox. |
| Messenger | One designated visible conversation and independent capture/OCR result. | Results from another messenger, notification badges or an automation's intended tap do not establish access. |
| Calendar / Reminders | Prefer the existing EventKit readers and compare returned dates/items with owner-verified test facts. Calendar selection is explicit; `fetchUpcomingReminders` reads bounded incomplete reminders with due dates (default seven days), excluding undated/completed items. | Neither local read proves server sync or the entire reminders collection. Each permission/scope needs its own check. Connecting these readers to the combined digest remains work; OCR is not the preferred substitute for structured access. |

Record each as passed, failed, unavailable or not run. Cross-app XCTest control is a separate tethered development mode, not an ordinary background iPhone capability. UserNotifications exposes MORE's notification scope, not the entire Notification Center; visible badges and sampled message lists cannot supply verified total unread/overnight counts. [Access matrix](PRODUCT-DIRECTION.md#apple-access-matrix-checked-10-october-2026).

## Five independent days before a personal-pattern claim

After the synthetic pipeline and chosen physical source work, collect **five genuinely independent dated mornings** with explicit consent and known source provenance. Five is a minimum trial gate for this protocol, not statistical proof of a habit.

1. Use separate actual acquisitions on five different observed dates. Reimports, copies, repeated playback, changed date labels and synthetic seeds do not create independent days. Keep source hashes/session provenance and truthful date/zone metadata.
2. Keep human mornings, automation and synthetic tests separate. Declare the intended morning window and actual coverage on each day; preserve missing/failed sections. A historical Screen Time export may provide real dated aggregates only after authorized access and actual returned coverage are verified.
3. Evaluate each day's digest before combining days. Compare like sources, zones and time windows; disclose exclusions instead of silently choosing only successful days.
4. Show recurrence with its denominator: for example, a label supported on three of five comparable observed days. Do not derive average app time from sparse point samples, or counts of taps/reels/reads from screen labels.
5. Have the person review the cross-day proposal and correct it. Confirm that their approved plan and chosen enjoyable rituals remain intact until explicit approval of a replacement.

The current one-to-five-source proposal path can support that selected-source review; automatic capture, complete phone-use averages and continuous adaptation are not thereby implemented. Extend to seven-day onboarding only with an explicit coverage/selection design. [Metrics](OBSERVATION-METRICS.md) · [Bootstrap #30](https://github.com/gibouu/morning-operator/issues/30) · [Multi-day learning #11](https://github.com/gibouu/morning-operator/issues/11).

## Stop and hand off

For this bounded deliverable, save one report per attempted seed/app, the exact source/build, stage outcomes, failures and artifact locations using [TEST-REPORT-TEMPLATE](TEST-REPORT-TEMPLATE.md). Preserve raw content locally. Open or update the relevant issue with a reviewed summary; do not rerun an unchanged unsupported backend indefinitely or expand into unrelated UI work. The handoff says what ran, what remains unavailable and the single next experiment. [Teammate handoff](HANDOFF.md).
