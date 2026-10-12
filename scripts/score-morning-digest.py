#!/usr/bin/env python3
"""Independent, local exact-fact scoring. This script never calls a model or speaks.

See Benchmarks/morning-digest-contract.md. A matching hand-authored answer is not
model evidence. Runtime receipts are controller attestations, not cryptographic
proof of inference; native logs/artifacts still require independent inspection.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

MAX_BYTES = 10 * 1024 * 1024
STATUSES = {"completed", "skipped", "blocked", "failed"}
SOURCE_STATES = {"available", "unknown", "unavailable"}
DATE_FIELDS = {"date", "time", "endTime", "receivedAt", "sentAt", "startsAt", "endsAt"}


class ContractError(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise ContractError(reason)


def string(value, name, maximum=32768):
    require(isinstance(value, str) and bool(value.strip()) and len(value) <= maximum,
            "invalid " + name)
    return value


def array(value, name, maximum=4096):
    require(isinstance(value, list) and len(value) <= maximum, "invalid " + name)
    return value


def object_value(value, name):
    require(isinstance(value, dict), "invalid " + name)
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def parse_json(text):
    def invalid_constant(_):
        raise ContractError("nonfinite JSON number")
    try:
        return json.loads(text, object_pairs_hook=unique_object, parse_constant=invalid_constant)
    except (ValueError, RecursionError) as error:
        raise ContractError("invalid JSON") from error


def read_bytes(path):
    with Path(path).open("rb") as source:
        data = source.read(MAX_BYTES + 1)
    require(len(data) <= MAX_BYTES, "artifact exceeds byte limit")
    return data


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def is_digest(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def validate_source(source):
    object_value(source, "source")
    string(source.get("sourceID"), "source ID", 256)
    string(source.get("sourceRevision"), "source revision", 256)
    string(source.get("sourceKind"), "source kind", 64)
    require(source.get("availability") in SOURCE_STATES, "invalid source availability")
    fields = object_value(source.get("fields", {}), "source fields")
    require(len(fields) <= 64, "too many source fields")
    for key, value in fields.items():
        require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,63}", key) is not None, "invalid field name")
        string(value, "field value")
    required = source.get("requiredFields", list(fields))
    array(required, "required fields", 64)
    require(all(isinstance(k, str) and k in fields for k in required)
            and len(set(required)) == len(required), "invalid required fields")
    evidence = array(source.get("evidence", []), "source evidence", 256)
    ids = set()
    for item in evidence:
        object_value(item, "evidence item")
        identifier = string(item.get("evidenceID"), "evidence ID", 256)
        require(identifier not in ids, "duplicate evidence ID")
        ids.add(identifier)
        text = string(item.get("text"), "evidence text")
        supported = array(item.get("fields"), "evidence fields", 64)
        require(bool(supported) and all(isinstance(k, str) and k in fields for k in supported),
                "invalid evidence fields")
        require(all(fields[k] in text for k in supported), "truth field absent from its evidence")
    if source["availability"] != "available":
        require(not fields and not evidence and not required,
                "unknown/unavailable source cannot supply expected facts")
    else:
        require(bool(fields) and all(any(k in item["fields"] for item in evidence) for k in required),
                "required fact lacks independent evidence")
    return source


def load_truth(data):
    """Read either a normalized object or verified controller JSONL attachment."""
    try:
        text = data.decode("utf-8")
    except UnicodeError as error:
        raise ContractError("truth is not UTF-8") from error
    try:
        document = parse_json(text)
    except ContractError:
        rows = [parse_json(line) for line in text.splitlines() if line.strip()]
        require(bool(rows), "empty truth")
        require(all(isinstance(row, dict) for row in rows), "invalid truth row")
        run_ids = {string(row.get("runID"), "truth run ID", 256) for row in rows}
        require(len(run_ids) == 1, "mixed truth runs")
        sources = []
        for row in rows:
            if row.get("kind") == "digestSource":
                require(row.get("schemaVersion") in (1, 2), "unsupported truth row schema")
                source = object_value(row.get("digestSource"), "digest source")
                expected_outcome = "verified" if source.get("availability") == "available" else "declared"
                require(row.get("outcome") == expected_outcome, "unverified truth source")
                sources.append(source)
        document = {"schemaVersion": 1, "runID": next(iter(run_ids)), "sources": sources,
                    "status": "completed" if any(row.get("kind") == "benchmarkComplete" and
                    row.get("outcome") == "verified" for row in rows) and not any(
                    row.get("outcome") == "failed" for row in rows) else "blocked"}
    object_value(document, "truth")
    require(document.get("schemaVersion") == 1, "unsupported truth schema")
    string(document.get("runID"), "truth run ID", 256)
    require(document.get("status") in STATUSES, "invalid truth status")
    sources = array(document.get("sources"), "truth sources", 512)
    indexed = {}
    for source in sources:
        validate_source(source)
        previous = indexed.get(source["sourceID"])
        require(previous is None or previous == source, "conflicting truth source revisions")
        indexed[source["sourceID"]] = source
    require(bool(indexed), "truth has no sources")
    return {**document, "sources": list(indexed.values())}


def validate_actual(actual, run_id):
    object_value(actual, "actual output")
    require(actual.get("schemaVersion") == 1, "unsupported actual schema")
    require(actual.get("runID") == run_id, "actual/truth run mismatch")
    require(actual.get("status") in STATUSES, "invalid actual status")
    require(actual.get("producer") in {"native-model", "hand-authored", "unavailable"},
            "invalid producer")
    claims = array(actual.get("claims", []), "claims")
    for claim in claims:
        object_value(claim, "claim")
        for key in ("sourceID", "sourceRevision", "field", "value"):
            string(claim.get(key), "claim " + key, 32768 if key == "value" else 256)
        for citation in array(claim.get("evidence", []), "claim evidence", 64):
            object_value(citation, "citation")
            for key in ("sourceID", "evidenceID", "quote"):
                string(citation.get(key), "citation " + key, 32768 if key == "quote" else 256)
    states = array(actual.get("sourceStates", []), "source states", 512)
    for state in states:
        object_value(state, "source state")
        string(state.get("sourceID"), "state source ID", 256)
        require(state.get("status") in SOURCE_STATES, "invalid source state")
    if "spokenText" in actual:
        string(actual["spokenText"], "spoken text", 65536)
    if actual["status"] != "completed":
        require(not claims, "noncompleted output must not contain scored claims")
    return actual


def validate_alignment(alignment, actual_hash, truth_hash):
    if alignment is None:
        return {}, {}, {}
    object_value(alignment, "alignment")
    require(alignment.get("schemaVersion") == 1 and alignment.get("actualSHA256") == actual_hash
            and alignment.get("truthSHA256") == truth_hash, "alignment artifact mismatch")
    require(alignment.get("method") == "independent-visible-source-alignment", "invalid alignment method")
    sources = object_value(alignment.get("sourceIDs", {}), "aligned source IDs")
    evidence = object_value(alignment.get("evidenceIDs", {}), "aligned evidence IDs")
    for mapping in (sources, evidence):
        require(len(mapping) <= 4096, "too many aligned IDs")
        for key, value in mapping.items():
            string(key, "aligned identifier", 256)
            string(value, "aligned identifier", 256)
        require(len(set(mapping.values())) == len(mapping), "alignment cannot collapse separate identities")
    revisions = object_value(alignment.get("sourceRevisions", {}), "aligned revisions")
    require(len(revisions) <= 512, "too many aligned revisions")
    for key, value in revisions.items():
        string(key, "aligned source identifier", 256)
        object_value(value, "aligned source revision")
        string(value.get("actualRevision"), "actual aligned revision", 256)
        string(value.get("truthRevision"), "truth aligned revision", 256)
    return sources, evidence, revisions


def inference_evidence(actual, receipt, actual_hash, truth_hash, alignment_hash):
    """Separate factual correctness from an independently supplied execution receipt."""
    result = {"status": "unverified", "receiptIsIndependentProof": False,
              "note": "A controller receipt requires native-log/artifact review; scorer cannot prove execution."}
    if actual["producer"] != "native-model":
        result["status"] = "not-model-output"
        return result
    if receipt is None:
        return result
    object_value(receipt, "runtime receipt")
    require(receipt.get("schemaVersion") == 1, "unsupported runtime receipt")
    require(receipt.get("runID") == actual["runID"] and receipt.get("outputSHA256") == actual_hash,
            "runtime receipt output mismatch")
    request_count = receipt.get("requestCount")
    response_count = receipt.get("responseCount")
    inputs = array(receipt.get("inputSHA256", []), "runtime input digests", 512)
    require(all(is_digest(value) for value in inputs), "invalid runtime input digest")
    completed = (receipt.get("executionStatus") == "completed" and
                 receipt.get("producer") == "native-model" and
                 type(request_count) is int and type(response_count) is int and
                 0 < response_count <= request_count and bool(inputs) and
                 receipt.get("truthWasModelInput") is False and truth_hash not in inputs and
                 (alignment_hash is None or alignment_hash not in inputs))
    result["status"] = "controller-reported-native-inference" if completed else "unverified"
    return result


def speech_result(actual, speech):
    result = {"status": "not-assessed", "transcriptMatchesPreparedText": None,
              "audibility": "not-assessed", "pronunciation": "not-assessed"}
    if speech is None:
        return result
    object_value(speech, "speech result")
    require(speech.get("schemaVersion") == 1 and speech.get("runID") == actual["runID"],
            "speech run/schema mismatch")
    require(speech.get("status") in STATUSES, "invalid speech status")
    result["status"] = speech["status"]
    if speech["status"] != "completed":
        return result
    require(speech.get("origin") in {"recognizer", "human-transcription", "synthetic"},
            "invalid transcript origin")
    text = string(speech.get("transcript"), "speech transcript", 65536)
    prepared = actual.get("spokenText")
    require(prepared is not None and speech.get("spokenTextSHA256") == sha256(prepared.encode()),
            "speech prepared-text mismatch")
    result.update({"origin": speech["origin"], "comparison": "whitespace-only normalization",
                   "transcriptMatchesPreparedText": " ".join(text.split()) == " ".join(prepared.split()),
                   "status": "synthetic-comparison" if speech["origin"] == "synthetic" else "compared"})
    return result


def score(truth, actual, *, actual_hash, truth_hash, receipt=None, speech=None,
          alignment=None, alignment_hash=None):
    validate_actual(actual, truth["runID"])
    source_map, evidence_map, revision_map = validate_alignment(alignment, actual_hash, truth_hash)
    inference = inference_evidence(actual, receipt, actual_hash, truth_hash, alignment_hash)
    report = {"schemaVersion": 1, "runID": truth["runID"], "actualSHA256": actual_hash,
              "truthSHA256": truth_hash, "benchmarkStatus": actual["status"],
              "factMetrics": None, "inferenceEvidence": inference,
              "speech": speech_result(actual, speech),
              "limits": ["Exact structured facts only; narrative completeness, paraphrase meaning and fluency are unscored.",
                         "No audibility or pronunciation conclusion; no model call is performed."]}
    if truth["status"] != "completed":
        report["benchmarkStatus"] = "blocked"
        report["reason"] = "controller-truth-not-completed"
        return report
    if actual["status"] != "completed":
        report["reason"] = "actual-" + actual["status"]
        return report
    sources = {source["sourceID"]: source for source in truth["sources"]}
    expected = {(s["sourceID"], field, s["fields"][field]) for s in sources.values()
                if s["availability"] == "available" for field in s.get("requiredFields", list(s["fields"]))}
    counts = dict.fromkeys(["claimCount", "supportedUniqueCount", "unsupportedCount", "duplicateCount",
                           "wrongSourceCount", "wrongSenderCount", "wrongDateOrTimeCount",
                           "wrongValueCount", "staleCount", "invalidEvidenceCount",
                           "unavailableSourceClaimCount"], 0)
    matched = set()
    supported = set()
    seen = set()
    diagnostics = []
    for index, claim in enumerate(actual.get("claims", [])):
        counts["claimCount"] += 1
        source_id = source_map.get(claim["sourceID"], claim["sourceID"])
        field, value = claim["field"], claim["value"]
        key = (source_id, field, value)
        duplicate = key in seen
        seen.add(key)
        source = sources.get(source_id)
        errors = set()
        if duplicate:
            counts["duplicateCount"] += 1
            errors.add("duplicate")
        if source is None:
            errors.add("wrong-source")
        else:
            if source["availability"] != "available":
                errors.add("unavailable-source-claim")
            revision = claim["sourceRevision"]
            aligned_revision = revision_map.get(claim["sourceID"])
            if aligned_revision and revision == aligned_revision["actualRevision"]:
                revision = aligned_revision["truthRevision"]
            if revision != source["sourceRevision"]:
                errors.add("stale")
            if source["fields"].get(field) != value:
                errors.add("wrong-value")
                if field == "sender":
                    errors.add("wrong-sender")
                if field in DATE_FIELDS:
                    errors.add("wrong-date-or-time")
                if any(other["sourceID"] != source_id and other["fields"].get(field) == value
                       for other in sources.values()):
                    errors.add("wrong-source")
            source_evidence = {item["evidenceID"]: item for item in source.get("evidence", [])}
            valid_evidence = False
            for citation in claim.get("evidence", []):
                citation_source = source_map.get(citation["sourceID"], citation["sourceID"])
                item = source_evidence.get(evidence_map.get(citation["evidenceID"], citation["evidenceID"]))
                if citation_source != source_id:
                    errors.add("wrong-source")
                if (citation_source == source_id and item is not None and field in item["fields"]
                        and citation["quote"] in item["text"] and value in citation["quote"]):
                    valid_evidence = True
                else:
                    errors.add("invalid-evidence")
            if not valid_evidence:
                errors.add("invalid-evidence")
        mapping = {"wrong-source": "wrongSourceCount", "wrong-sender": "wrongSenderCount",
                   "wrong-date-or-time": "wrongDateOrTimeCount", "wrong-value": "wrongValueCount",
                   "stale": "staleCount", "invalid-evidence": "invalidEvidenceCount",
                   "unavailable-source-claim": "unavailableSourceClaimCount"}
        for error, counter in mapping.items():
            counts[counter] += int(error in errors)
        fact_errors = errors - {"duplicate"}
        if fact_errors:
            counts["unsupportedCount"] += 1
        else:
            supported.add(key)
            if key in expected:
                matched.add(key)
        if errors:
            diagnostics.append({"claimIndex": index, "categories": sorted(errors)})
    counts["supportedUniqueCount"] = len(supported)
    declared_states = {}
    state_errors = 0
    for state in actual.get("sourceStates", []):
        source_id = source_map.get(state["sourceID"], state["sourceID"])
        if source_id in declared_states:
            state_errors += 1
        declared_states[source_id] = state["status"]
        if source_id not in sources or state["status"] != sources[source_id]["availability"]:
            state_errors += 1
    missing_states = sum(source_id not in declared_states for source_id in sources)
    metrics = {**counts, "expectedFactCount": len(expected), "matchedRequiredFactCount": len(matched),
               "missingRequiredFactCount": len(expected - matched),
               "precision": len(supported) / counts["claimCount"] if counts["claimCount"] else None,
               "recall": len(matched) / len(expected) if expected else None,
               "sourceStateErrorCount": state_errors, "missingSourceStateCount": missing_states}
    facts_exact = (bool(expected) and bool(counts["claimCount"]) and
                   not counts["unsupportedCount"] and not counts["duplicateCount"] and
                   matched == expected and not state_errors and not missing_states)
    report.update({"factMetrics": metrics, "claimDiagnostics": diagnostics,
                   "allRequiredFactsSupportedExactly": facts_exact,
                   "benchmarkStatus": "facts-mismatch" if not facts_exact else "unverified-output"})
    if facts_exact and inference["status"] == "controller-reported-native-inference":
        report["benchmarkStatus"] = "facts-match-with-runtime-receipt"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--truth", required=True)
    parser.add_argument("--actual", required=True)
    parser.add_argument("--report", required=True, help="Fresh local output; existing files are never replaced")
    parser.add_argument("--receipt", help="Separate native controller execution receipt")
    parser.add_argument("--alignment", help="Separate independently reviewed ID alignment, bound to artifact hashes")
    parser.add_argument("--speech", help="Separate transcript result; never proves audibility")
    args = parser.parse_args()
    try:
        truth_bytes, actual_bytes = read_bytes(args.truth), read_bytes(args.actual)
        optional = {name: read_bytes(getattr(args, name)) if getattr(args, name) else None
                    for name in ("receipt", "alignment", "speech")}
        report = score(load_truth(truth_bytes), parse_json(actual_bytes),
                       actual_hash=sha256(actual_bytes), truth_hash=sha256(truth_bytes),
                       **{name: parse_json(data) if data else None for name, data in optional.items()},
                       alignment_hash=sha256(optional["alignment"]) if optional["alignment"] else None)
        # No source text, sender/date values, paths, or transcript are copied into reports.
        with Path(args.report).open("x", encoding="utf-8") as destination:
            import os
            os.chmod(destination.fileno(), 0o600)
            json.dump(report, destination, indent=2, ensure_ascii=False, allow_nan=False)
            destination.write("\n")
        print(json.dumps({"benchmarkStatus": report["benchmarkStatus"],
                          "factMetrics": report["factMetrics"]}))
        return {"facts-match-with-runtime-receipt": 0, "facts-mismatch": 1,
                "skipped": 3, "blocked": 3, "failed": 3, "unverified-output": 4}[report["benchmarkStatus"]]
    except (ContractError, OSError, UnicodeError) as error:
        # Error text deliberately omits source payloads and filesystem paths.
        print(json.dumps({"benchmarkStatus": "invalid-input", "errorCategory": type(error).__name__}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
