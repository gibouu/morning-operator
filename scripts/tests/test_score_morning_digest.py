"""Synthetic unit tests for scorer policy, never native model success evidence."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "score-morning-digest.py"
SPEC = importlib.util.spec_from_file_location("digest_scorer", SCRIPT)
scorer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scorer)


def source(identifier="message.01", sender="Cedar Person"):
    fields = {"sender": sender, "body": "Meet beside the library.", "date": "October 10, 2026"}
    return {"sourceID": identifier, "sourceRevision": "revision-1", "sourceKind": "message",
            "availability": "available", "fields": fields, "requiredFields": list(fields),
            "evidence": [{"evidenceID": identifier + "." + key, "text": value, "fields": [key]}
                         for key, value in fields.items()]}


def fixture():
    s = source()
    truth = {"schemaVersion": 1, "runID": "synthetic-unit-test", "status": "completed", "sources": [s]}
    actual = {"schemaVersion": 1, "runID": truth["runID"], "status": "completed",
              "producer": "hand-authored", "sourceStates": [{"sourceID": s["sourceID"], "status": "available"}],
              "spokenText": "A synthetic test sentence.",
              "claims": [{"sourceID": s["sourceID"], "sourceRevision": s["sourceRevision"],
                          "field": key, "value": value,
                          "evidence": [{"sourceID": s["sourceID"], "evidenceID": s["sourceID"] + "." + key,
                                        "quote": value}]} for key, value in s["fields"].items()]}
    return truth, actual


def evaluate(truth, actual, **options):
    return scorer.score(scorer.load_truth(json.dumps(truth).encode()), actual,
                        actual_hash="a" * 64, truth_hash="b" * 64, **options)


class DigestScorerTests(unittest.TestCase):
    def test_exact_hand_authored_facts_are_not_model_success(self):
        truth, actual = fixture()
        report = evaluate(truth, actual)
        self.assertEqual(report["factMetrics"]["precision"], 1)
        self.assertEqual(report["factMetrics"]["recall"], 1)
        self.assertEqual(report["benchmarkStatus"], "unverified-output")
        self.assertEqual(report["inferenceEvidence"]["status"], "not-model-output")
        serialized = json.dumps(report)
        for private_value in truth["sources"][0]["fields"].values():
            self.assertNotIn(private_value, serialized)

    def test_model_label_alone_is_unverified_and_receipt_is_only_attestation(self):
        truth, actual = fixture()
        actual["producer"] = "native-model"
        self.assertEqual(evaluate(truth, actual)["benchmarkStatus"], "unverified-output")
        receipt = {"schemaVersion": 1, "runID": truth["runID"], "outputSHA256": "a" * 64,
                   "producer": "native-model", "executionStatus": "completed", "requestCount": 1,
                   "responseCount": 1, "inputSHA256": ["c" * 64], "truthWasModelInput": False}
        report = evaluate(truth, actual, receipt=receipt)
        self.assertEqual(report["benchmarkStatus"], "facts-match-with-runtime-receipt")
        self.assertFalse(report["inferenceEvidence"]["receiptIsIndependentProof"])
        for key, value in [("responseCount", 0), ("truthWasModelInput", True), ("inputSHA256", ["b" * 64])]:
            with self.subTest(key=key):
                self.assertEqual(evaluate(truth, actual, receipt={**receipt, key: value})["benchmarkStatus"],
                                 "unverified-output")
        with self.assertRaises(scorer.ContractError):
            evaluate(truth, actual, receipt={**receipt, "outputSHA256": "d" * 64})

    def test_wrong_sender_date_and_stale_are_independent_counters(self):
        truth, actual = fixture()
        actual["claims"][0]["value"] = "Wrong person"
        actual["claims"][1]["sourceRevision"] = "older-revision"
        actual["claims"][2]["value"] = "October 9, 2026"
        metrics = evaluate(truth, actual)["factMetrics"]
        self.assertEqual(metrics["wrongSenderCount"], 1)
        self.assertEqual(metrics["wrongDateOrTimeCount"], 1)
        self.assertEqual(metrics["staleCount"], 1)
        self.assertEqual(metrics["unsupportedCount"], 3)
        self.assertEqual(metrics["precision"], 0)

    def test_wrong_source_and_bogus_extra_citation_cannot_be_laundered(self):
        truth, actual = fixture()
        truth["sources"].append(source("message.02", "Other Person"))
        actual["claims"][0]["value"] = "Other Person"
        actual["claims"][1]["evidence"].append({"sourceID": "message.02", "evidenceID": "message.02.body",
                                              "quote": actual["claims"][1]["value"]})
        metrics = evaluate(truth, actual)["factMetrics"]
        self.assertEqual(metrics["wrongSourceCount"], 2)
        self.assertEqual(metrics["unsupportedCount"], 2)

    def test_duplicate_penalizes_precision_but_does_not_inflate_recall(self):
        truth, actual = fixture()
        actual["claims"].append(copy.deepcopy(actual["claims"][0]))
        metrics = evaluate(truth, actual)["factMetrics"]
        self.assertEqual(metrics["duplicateCount"], 1)
        self.assertEqual(metrics["precision"], .75)
        self.assertEqual(metrics["recall"], 1)
        self.assertEqual(metrics["unsupportedCount"], 0)

    def test_supported_retry_counts_recall_even_after_bad_evidence_duplicate(self):
        truth, actual = fixture()
        good = copy.deepcopy(actual["claims"][0])
        actual["claims"][0]["evidence"] = []
        actual["claims"].append(good)
        metrics = evaluate(truth, actual)["factMetrics"]
        self.assertEqual(metrics["recall"], 1)
        self.assertEqual(metrics["precision"], .75)
        self.assertEqual(metrics["unsupportedCount"], 1)

    def test_unknown_unavailable_require_explicit_state_and_never_expected_zero_facts(self):
        truth, actual = fixture()
        for state in ("unknown", "unavailable"):
            truth["sources"].append({"sourceID": state, "sourceKind": "message", "sourceRevision": "1",
                                     "availability": state, "fields": {}, "evidence": [], "requiredFields": []})
            actual["sourceStates"].append({"sourceID": state, "status": state})
        self.assertEqual(evaluate(truth, actual)["factMetrics"]["expectedFactCount"], 3)
        actual["claims"].append({"sourceID": "unavailable", "sourceRevision": "1", "field": "unreadCount",
                                 "value": "0", "evidence": []})
        metrics = evaluate(truth, actual)["factMetrics"]
        self.assertEqual(metrics["unavailableSourceClaimCount"], 1)
        self.assertEqual(metrics["unsupportedCount"], 1)

    def test_skipped_blocked_failed_have_no_precision_or_success(self):
        truth, actual = fixture()
        for status in ("skipped", "blocked", "failed"):
            with self.subTest(status=status):
                actual.update(status=status, claims=[])
                report = evaluate(truth, actual)
                self.assertEqual(report["benchmarkStatus"], status)
                self.assertIsNone(report["factMetrics"])
        actual.update(status="completed", claims=[])
        self.assertIsNone(evaluate(truth, actual)["factMetrics"]["precision"])

    def test_exact_unicode_and_field_specific_evidence_no_paraphrase_credit(self):
        truth, actual = fixture()
        s = truth["sources"][0]
        s["fields"]["sender"] = s["evidence"][0]["text"] = "Amélie"
        actual["claims"][0]["value"] = actual["claims"][0]["evidence"][0]["quote"] = "Ame\u0301lie"
        actual["claims"][1]["evidence"][0]["evidenceID"] = "message.01.sender"
        metrics = evaluate(truth, actual)["factMetrics"]
        self.assertEqual(metrics["wrongSenderCount"], 1)
        self.assertEqual(metrics["invalidEvidenceCount"], 2)

    def test_truth_jsonl_requires_verified_complete_and_deduplicates_repeated_visibility(self):
        truth, actual = fixture()
        row = {"schemaVersion": 2, "runID": truth["runID"], "kind": "digestSource", "outcome": "verified",
               "digestSource": truth["sources"][0]}
        complete = {"runID": truth["runID"], "kind": "benchmarkComplete", "outcome": "verified"}
        data = "\n".join(json.dumps(item) for item in [row, row, complete]).encode()
        loaded = scorer.load_truth(data)
        self.assertEqual(len(loaded["sources"]), 1)
        self.assertEqual(evaluate(loaded, actual)["factMetrics"]["expectedFactCount"], 3)
        loaded = scorer.load_truth((json.dumps(row) + "\n" + json.dumps(row)).encode())
        self.assertEqual(evaluate(loaded, actual)["benchmarkStatus"], "blocked")

    def test_conflicting_truth_and_unverified_truth_are_rejected(self):
        truth, _ = fixture()
        truth["sources"].append(source())
        truth["sources"][-1]["sourceRevision"] = "different"
        with self.assertRaises(scorer.ContractError):
            scorer.load_truth(json.dumps(truth).encode())
        with self.assertRaises(scorer.ContractError):
            scorer.parse_json('{"schemaVersion":1,"schemaVersion":2}')

    def test_alignment_is_bound_to_original_files_and_does_not_change_original_output(self):
        truth, actual = fixture()
        for claim in actual["claims"]:
            claim["sourceID"] = claim["evidence"][0]["sourceID"] = "ocr-source-1"
            claim["sourceRevision"] = "extraction-unit-revision"
        actual["sourceStates"][0]["sourceID"] = "ocr-source-1"
        alignment = {"schemaVersion": 1, "actualSHA256": "a" * 64, "truthSHA256": "b" * 64,
                     "method": "independent-visible-source-alignment", "sourceIDs": {"ocr-source-1": "message.01"},
                     "evidenceIDs": {}, "sourceRevisions": {
                         "ocr-source-1": {"actualRevision": "extraction-unit-revision", "truthRevision": "revision-1"}}}
        self.assertTrue(evaluate(truth, actual, alignment=alignment)["allRequiredFactsSupportedExactly"])
        self.assertEqual(actual["claims"][0]["sourceID"], "ocr-source-1")
        actual["claims"][0]["sourceRevision"] = "stale-extraction-unit-revision"
        self.assertEqual(evaluate(truth, actual, alignment=alignment)["factMetrics"]["staleCount"], 1)
        with self.assertRaises(scorer.ContractError):
            evaluate(truth, actual, alignment={**alignment, "actualSHA256": "c" * 64})

    def test_transcript_match_never_claims_audibility_and_synthetic_is_explicit(self):
        truth, actual = fixture()
        speech = {"schemaVersion": 1, "runID": truth["runID"], "status": "completed", "origin": "synthetic",
                  "transcript": "A synthetic\n test sentence.",
                  "spokenTextSHA256": scorer.sha256(actual["spokenText"].encode())}
        result = evaluate(truth, actual, speech=speech)["speech"]
        self.assertTrue(result["transcriptMatchesPreparedText"])
        self.assertEqual(result["status"], "synthetic-comparison")
        self.assertEqual(result["audibility"], "not-assessed")
        speech["origin"] = "recognizer"
        speech["transcript"] = "A different sentence."
        self.assertFalse(evaluate(truth, actual, speech=speech)["speech"]["transcriptMatchesPreparedText"])

    def test_cli_unverified_exit_owner_only_report_and_no_overwrite(self):
        truth, actual = fixture()
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "truth.json").write_text(json.dumps(truth))
            (base / "actual.json").write_text(json.dumps(actual))
            command = [sys.executable, str(SCRIPT), "--truth", str(base / "truth.json"),
                       "--actual", str(base / "actual.json"), "--report", str(base / "report.json")]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 4, result.stderr)
            report = (base / "report.json").read_bytes()
            self.assertEqual((base / "report.json").stat().st_mode & 0o777, 0o600)
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
            self.assertEqual((base / "report.json").read_bytes(), report)

    def test_hand_authored_file_in_swift_emitted_shape_is_unverified_never_a_pass(self):
        # The same file is decoded by Tests/MorningAppleTests/MorningDigestTests.swift.
        # It was written by hand in the shape the Swift types emit; no model produced it.
        actual_bytes = (Path(__file__).parent / "fixtures" / "swift-digest-hand-authored.json").read_bytes()
        actual = json.loads(actual_bytes)
        native_source, inbox = (state["sourceID"] for state in actual["sourceStates"])
        fields = {claim["field"]: claim["value"] for claim in actual["claims"]}
        # A prepared unit is one evidence ID, so this truth keeps both fields in one evidence item.
        truth = {"schemaVersion": 1, "runID": actual["runID"], "status": "completed", "sources": [
            {"sourceID": "fixture.message.01", "sourceRevision": "controller-revision", "sourceKind": "message",
             "availability": "available", "fields": fields, "requiredFields": list(fields),
             "evidence": [{"evidenceID": "fixture.message.01.text", "text": "\n".join(fields.values()),
                           "fields": list(fields)}]},
            {"sourceID": inbox, "sourceRevision": "1", "sourceKind": "message", "availability": "unavailable",
             "fields": {}, "requiredFields": [], "evidence": []}]}
        truth_bytes = json.dumps(truth).encode()
        alignment = {"schemaVersion": 1, "method": "independent-visible-source-alignment",
                     "actualSHA256": scorer.sha256(actual_bytes), "truthSHA256": scorer.sha256(truth_bytes),
                     "sourceIDs": {native_source: "fixture.message.01"},
                     "evidenceIDs": {actual["claims"][0]["evidence"][0]["evidenceID"]: "fixture.message.01.text"},
                     "sourceRevisions": {native_source: {"actualRevision": actual["claims"][0]["sourceRevision"],
                                                         "truthRevision": "controller-revision"}}}
        receipt = {"schemaVersion": 1, "runID": actual["runID"], "outputSHA256": scorer.sha256(actual_bytes),
                   "producer": "native-model", "executionStatus": "completed", "requestCount": 1,
                   "responseCount": 1, "inputSHA256": ["c" * 64], "truthWasModelInput": False}
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name, data in [("truth", truth_bytes), ("actual", actual_bytes),
                               ("alignment", json.dumps(alignment).encode()), ("receipt", json.dumps(receipt).encode())]:
                (base / (name + ".json")).write_bytes(data)
            command = [sys.executable, str(SCRIPT), "--truth", str(base / "truth.json"),
                       "--actual", str(base / "actual.json"), "--alignment", str(base / "alignment.json")]
            # Even beside a well-formed receipt, a hand-authored producer cannot reach exit 0.
            for report_name, extra in [("report.json", []), ("report-with-receipt.json", ["--receipt", str(base / "receipt.json")])]:
                with self.subTest(report=report_name):
                    result = subprocess.run(command + ["--report", str(base / report_name)] + extra,
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 4, result.stderr)
                    report = json.loads((base / report_name).read_text())
                    self.assertEqual(report["benchmarkStatus"], "unverified-output")
                    self.assertEqual(report["inferenceEvidence"]["status"], "not-model-output")
                    self.assertTrue(report["allRequiredFactsSupportedExactly"])
                    self.assertEqual(report["factMetrics"]["unsupportedCount"], 0)


if __name__ == "__main__":
    unittest.main()
