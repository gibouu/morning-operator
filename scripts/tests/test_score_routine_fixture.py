"""Hand-authored scorer contracts; these tests never run or prove native inference."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'score-routine-fixture.py'
SPEC = importlib.util.spec_from_file_location('routine_fixture_scorer', SCRIPT)
scorer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scorer)


class RoutineFixtureScorerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.oracle = self.write('oracle.json', {'ocrChecks': [
            {'id': 'literal', 'scene': 'article', 'literal': {'fr': 'Six bancs'}}]})
        self.timeline = self.write('timeline.json', {
            'profile': 'realistic', 'language': 'fr', 'durationSeconds': 10,
            'scenes': [{'sceneID': 'article', 'startSeconds': 0, 'endSeconds': 10}]})
        self.manifest = self.write('manifest.json', {
            'oracleSHA256': scorer.sha(self.oracle),
            'timelines': [{'profile': 'realistic', 'language': 'fr', 'sha256': scorer.sha(self.timeline)}],
            'movies': [{'profile': 'realistic', 'language': 'fr', 'sha256': 'a' * 64, 'bytes': 123}]})
        self.evidence = {'durationSeconds': 10, 'frames': [
            {'id': 'frame-1', 'actualTimeSeconds': 2, 'outcome': 'observed', 'text': 'Six bancs'}]}
        self.classification = {'status': 'completed', 'attemptedBatchCount': 1,
                               'respondedBatchCount': 1, 'failedBatchCount': 0}

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding='utf-8')
        return path

    def evaluate(self, actual):
        path = self.write('actual.json', actual)
        return scorer.compare(self.manifest, self.timeline, self.oracle, path)

    def pipeline(self):
        return {'schemaVersion': 1, 'status': 'completed', 'stage': 'exactSourceValidation',
                'fingerprint': {'sha256': 'a' * 64, 'byteCount': 123},
                'videoEvidence': copy.deepcopy(self.evidence),
                'classification': copy.deepcopy(self.classification), 'citationsValid': True,
                'preparedUnitCount': 1, 'submittedCharacterCount': 99, 'modelRequestCount': 3,
                'omissions': [{'reason': 'unsupportedVisualContext', 'sampleID': 'other-frame'}],
                'proposal': {'routine': {'isApproved': False, 'sourceLabel': 'SYNTHETIC unit input',
                                         'steps': [{'id': 'step-1', 'title': 'Reading', 'durationMinutes': 2}]},
                             'support': [{'stepID': 'step-1', 'citations': [{'unitID': 'unit-1'}]}]}}

    def test_completed_classification_never_overrides_pipeline_failure_or_unavailability(self):
        for status in ['failed', 'unavailable']:
            with self.subTest(status=status):
                actual = self.pipeline()
                actual.update(status=status, stage='localRoutineProposal', errorCategory='invalidCitation')
                actual.pop('proposal')
                actual.pop('citationsValid')
                result, code = self.evaluate(actual)
                self.assertEqual(code, 4)
                self.assertEqual(result['realClassification']['status'], 'completed')
                self.assertEqual(result['pipeline']['status'], status)
                self.assertEqual(result['pipeline']['stage'], 'localRoutineProposal')
                self.assertEqual(result['pipeline']['errorCategory'], 'invalidCitation')
                self.assertEqual(result['pipeline']['omissions'], actual['omissions'])
                self.assertFalse(result['pipeline']['proposal']['validatedDraftReported'])
                self.assertEqual(result['pipeline']['preparedModelRequestCount'], 3)
                self.assertIsNone(result['pipeline']['actualProposalModelRequestCount'])

    def test_preparation_and_reported_progress_never_invent_attempted_requests(self):
        actual = self.pipeline()
        result, _ = self.evaluate(actual)
        self.assertEqual(result['pipeline']['preparedSubmittedCharacterCount'], 99)
        self.assertEqual(result['pipeline']['preparedModelRequestCount'], 3)
        self.assertIsNone(result['pipeline']['proposalProgressTotalRequests'])
        self.assertIsNone(result['pipeline']['proposalCompletedRequests'])
        actual.update(status='failed', preparedSubmittedCharacterCount=120,
                      preparedModelRequestCount=4, proposalProgressTotalRequests=5, proposalCompletedRequests=2)
        result, code = self.evaluate(actual)
        self.assertEqual(code, 4)
        self.assertEqual(result['pipeline']['preparedSubmittedCharacterCount'], 120)
        self.assertEqual(result['pipeline']['preparedModelRequestCount'], 4)
        self.assertEqual(result['pipeline']['proposalProgressTotalRequests'], 5)
        self.assertEqual(result['pipeline']['proposalCompletedRequests'], 2)
        self.assertIsNone(result['pipeline']['actualProposalModelRequestCount'])
        for completed in [0, None]:
            actual['proposalCompletedRequests'] = completed
            self.assertEqual(self.evaluate(actual)[0]['pipeline']['proposalCompletedRequests'], completed)

    def test_reported_valid_draft_remains_distinct_from_user_approval_and_execution(self):
        actual = self.pipeline()
        result, code = self.evaluate(actual)
        self.assertEqual(code, 0)
        self.assertEqual(result['sourceBinding']['status'], 'matched')
        self.assertEqual(result['verdict'], 'pipeline-source-validated-draft-not-execution')
        self.assertTrue(result['pipeline']['proposal']['validatedDraftReported'])
        self.assertEqual(result['pipeline']['proposal']['support'], actual['proposal']['support'])
        self.assertEqual(result['pipeline']['userApproval'], 'not-performed-by-this-opt-in')
        self.assertEqual(result['pipeline']['providerExecution'], 'not-run-by-this-opt-in')
        self.assertEqual(result['downstreamRoutineExecution'], 'not-run')
        self.assertIsNone(result['realClassification']['semanticFactAccuracy'])

    def test_wrong_or_invalid_fingerprint_refuses_oracle_comparison(self):
        for fingerprint in [{'sha256': 'b' * 64, 'byteCount': 123},
                            {'sha256': 'a' * 64, 'byteCount': 124},
                            {'sha256': 'not-a-sha', 'byteCount': 123}, None]:
            with self.subTest(fingerprint=fingerprint):
                actual = self.pipeline()
                actual['fingerprint'] = fingerprint
                result, code = self.evaluate(actual)
                self.assertEqual(code, 3)
                self.assertEqual(result['realOCR']['status'], 'not-compared-source-binding-rejected')
                self.assertNotIn('literalChecks', result['realOCR'])
                self.assertNotIn('sampleComparison', result)
                self.assertEqual(result['pipeline']['status'], 'completed')
                self.assertEqual(result['verdict'], 'source-binding-rejected-no-oracle-comparison')

    def test_failure_before_extraction_has_no_invented_observations_or_proposal(self):
        result, code = self.evaluate({'schemaVersion': 1, 'status': 'failed',
                                     'stage': 'fingerprintAndExtraction', 'errorCategory': 'mediaExtractionRejected'})
        self.assertEqual(code, 4)
        self.assertEqual(result['realOCR']['status'], 'not-run')
        self.assertEqual(result['realOCR']['frameCount'], 0)
        self.assertEqual(result['realClassification']['status'], 'not-run')
        self.assertFalse(result['pipeline']['proposal']['present'])
        self.assertIsNone(result['pipeline']['proposal']['stepCount'])
        self.assertIsNone(result['realOCR']['sampledLiteralRecall'])

    def test_completed_label_does_not_replace_source_binding_citations_or_draft_guards(self):
        changes = [('fingerprint', None), ('citationsValid', False), ('proposal', None)]
        for field, value in changes:
            with self.subTest(field=field):
                actual = self.pipeline()
                if field == 'fingerprint':
                    actual.pop(field)
                else:
                    actual[field] = value
                result, code = self.evaluate(actual)
                self.assertEqual(code, 4)
                self.assertFalse(result['pipeline']['proposal']['validatedDraftReported'])
        for approved in [True, None]:
            actual = self.pipeline()
            actual['proposal']['routine']['isApproved'] = approved
            self.assertEqual(self.evaluate(actual)[1], 4)
        actual = self.pipeline()
        actual['classification']['failedBatchCount'] = 1
        self.assertEqual(self.evaluate(actual)[1], 4)

    def test_legacy_extraction_and_classification_keep_their_contract(self):
        actual = {'sourceFilename': 'realistic-fr.mp4', 'evidence': self.evidence}
        for classified, expected_code in [(False, 4), (True, 0)]:
            with self.subTest(classified=classified):
                if classified:
                    actual['classification'] = self.classification
                result, code = self.evaluate(actual)
                self.assertEqual(code, expected_code)
                self.assertNotIn('pipeline', result)
                self.assertNotIn('reportFormat', result)
                self.assertEqual(result['verdict'], 'diagnostic-report-not-full-acceptance')
                self.assertTrue(result['sourceBinding']['reportDoesNotContainMovieHash'])
                self.assertEqual(result['realOCR']['sampledLiteralMatches'], 1)
                self.assertNotIn('status', result['realOCR'])

    def test_mixed_producer_contract_is_rejected_instead_of_silently_relabelled(self):
        actual = self.pipeline()
        actual['evidence'] = self.evidence
        with self.assertRaisesRegex(ValueError, 'Ambiguous report contract'):
            self.evaluate(actual)


if __name__ == '__main__':
    unittest.main()
