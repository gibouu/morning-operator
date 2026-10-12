# Independent morning digest scoring, version 1

This is a local benchmark contract and exact-fact scorer. **There is no actual semantic digest model adapter in this slice.** Scorer unit tests use hand-authored synthetic data to exercise scoring policy; they are never evidence of successful inference, real messages, speech, or model accuracy.

Run from the repository root:

```sh
python3 -m unittest discover -s scripts/tests -p 'test_score_morning_digest.py' -v
python3 scripts/score-morning-digest.py \
  --truth work/observation-benchmark/RUN/ground-truth.jsonl \
  --actual work/observation-benchmark/RUN/actual-digest.json \
  --report work/observation-benchmark/RUN/digest-score-01.json
```

Optional inputs: `--alignment alignment.json`, `--receipt native-runtime-receipt.json`, `--speech speech-transcript.json`. Output must be new. Reports use mode `0600` and contain counts, artifact digests and error categories, not source text, senders, date values, filenames or transcripts. Keep all runtime artifacts in ignored `work/`; this contract contains only synthetic examples.

## Held-out controller truth

The `digest` runner generates fresh seeded content and XCTest records facts only after checking their actual visible fields. The scorer accepts the exported JSONL attachment's version 1 or 2 event envelopes. Each available source requires `kind: "digestSource"`, `outcome: "verified"`, one `runID`, and this `digestSource` object:

```json
{
  "sourceID": "fixture.message.01",
  "sourceRevision": "canonical-item-sha256-from-controller",
  "sourceKind": "message",
  "availability": "available",
  "fields": {"sender": "Synthetic Cedar", "body": "Meet beside the library."},
  "requiredFields": ["sender", "body"],
  "evidence": [
    {"evidenceID": "fixture.message.01.sender", "text": "Synthetic Cedar", "fields": ["sender"]},
    {"evidenceID": "fixture.message.01.body", "text": "Meet beside the library.", "fields": ["body"]}
  ]
}
```

Actual generated fixture fields include sender/subject/date/time/body for messages and subject/date/time/endTime/location/reminder/body for events. Any subset can be explicitly required by the controller. Values are exact visible strings; the scorer does not infer locale, parse dates, equate paraphrases, or grade prose semantics. Facts from different source IDs remain distinct even when their values match.

Unknown or unavailable coverage uses the same source object with `availability: "unknown"` or `"unavailable"`, empty fields/evidence/requiredFields, and row outcome `"declared"`. It does not create zero-message facts. JSONL needs a verified `benchmarkComplete` and no failed event; otherwise evaluation is blocked. Repeated identical verified source rows deduplicate; conflicting revisions reject the input. A normalized JSON alternative is `{ "schemaVersion": 1, "runID": "...", "status": "completed", "sources": [...] }`; only an independent controller may create real benchmark truth.

## Actual output

Preserve the actual native output artifact unchanged. A future adapter should emit:

```json
{
  "schemaVersion": 1,
  "runID": "same-controller-run-id",
  "status": "completed",
  "producer": "native-model",
  "sourceStates": [{"sourceID": "ocr-source-1", "status": "available"}],
  "claims": [{
    "sourceID": "ocr-source-1", "sourceRevision": "actual-input-unit-revision",
    "field": "sender", "value": "Synthetic Cedar",
    "evidence": [{"sourceID": "ocr-source-1", "evidenceID": "ocr-line-1", "quote": "Synthetic Cedar"}]
  }],
  "spokenText": "The exact prepared sentence supplied for speech."
}
```

`status` is completed/skipped/blocked/failed; noncompleted output has no scored claims. `producer` is native-model/hand-authored/unavailable. Report each source's available/unknown/unavailable state explicitly. A fact is supported only if its source revision and exact field value match and its exact quote is inside evidence permitted for that field; adding an invalid citation does not become valid by also citing a good one. No evidence means unsupported. Unknown sources, stale revisions and invented zero counts never become supported facts.

Controller fixture IDs, seed, expected values and held-out truth **must not enter model input**. Native ingestion IDs/revisions will differ from hidden controller IDs. After generation, a separate independently reviewed alignment may map them using visible recording/frame evidence; never choose mappings to improve expected-value matches. If this alignment cannot be established, report blocked instead of guessing. The scorer never rewrites the actual output:

```json
{
  "schemaVersion": 1, "method": "independent-visible-source-alignment",
  "actualSHA256": "sha256-of-original-actual-file", "truthSHA256": "sha256-of-truth-file",
  "sourceIDs": {"ocr-source-1": "fixture.message.01"},
  "evidenceIDs": {"ocr-line-1": "fixture.message.01.sender"},
  "sourceRevisions": {"ocr-source-1": {"actualRevision": "actual-input-unit-revision", "truthRevision": "canonical-item-sha256-from-controller"}}
}
```

Mappings are optional when identifiers already share an independently grounded namespace. They are one-to-one. A different actual revision cannot reuse an alignment entry to hide staleness. Cross-source ambiguous or composite evidence needs a richer future adapter; do not force a many-to-one match into this format.

## Runtime receipt and outcomes

A separate native controller receipt has `schemaVersion:1`, matching `runID`, `producer:"native-model"`, `executionStatus:"completed"`, `outputSHA256` of the actual file, positive `requestCount`/`responseCount` with responses no greater than requests, nonempty `inputSHA256` (lowercase 64-hex digests), and `truthWasModelInput:false`. The scorer rejects artifact mismatches and will not accept truth/alignment file digests among model inputs. The runner must also independently ensure that fixture-content/seed/expected answers were excluded; hashes alone cannot prove this.

Even a well-formed receipt is a controller attestation requiring inspection of native request logs and input/output artifacts. This scorer cannot establish its authenticity, prove inference occurred, or prove that a spoken narrative contains only scored facts. There is deliberately no generic `passed` field.

| Exit | `benchmarkStatus` | Meaning |
|---|---|---|
| 0 | facts-match-with-runtime-receipt | All required structured facts supported exactly, source states complete, no duplicates, separate matching runtime receipt; review native evidence before claiming model success. |
| 1 | facts-mismatch | Missing/wrong/unsupported/duplicate facts or missing/wrong source states. |
| 2 | invalid-input (stderr) | Invalid/oversized/mismatched inputs or output already exists; no success report. |
| 3 | skipped / blocked / failed | Inference or controller truth did not complete; fact metrics remain null. |
| 4 | unverified-output | Facts match, but native execution is unverified or output is hand-authored. |

`factMetrics.precision` = supported distinct claims / all claims; duplicate claims lower precision. `recall` = supported required distinct facts / expected required facts. Empty denominators yield null, never automatic success. Separate counters cover unsupported, duplicate, wrong source/sender/date-or-time/value, stale revision, invalid evidence, unavailable-source claims, missing required facts and source-state issues. Error categories overlap; do not sum them as disjoint totals. A later properly cited duplicate can establish recall, while duplicates still prevent a complete exact result. Unscored narrative/paraphrase meaning and fluency remain explicit limits.

## Speech is independently assessed

An optional speech JSON contains `schemaVersion:1`, matching `runID`, status, `origin:"recognizer"|"human-transcription"|"synthetic"`, `transcript`, and `spokenTextSHA256` of the actual output's UTF-8 `spokenText`. Completed comparisons normalize whitespace only; punctuation, words and case still matter. Synthetic comparisons are labeled synthetic. A transcript match never proves audibility, pronunciation, naturalness or the selected physical audio route; those always remain `not-assessed` here. A missing or mismatched speech result does not change factual precision/recall and never becomes a speech pass.
