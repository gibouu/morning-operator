"""Hand-authored coverage contracts; no extraction, inference or provider proof.

The fixtures deliberately use unrelated/duplicate generated titles. Coverage
comes from native citation linkage, never expected title or duration matching.
"""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import uuid


SCRIPT = Path(__file__).resolve().parents[1] / 'score-routine-coverage.py'
SPEC = importlib.util.spec_from_file_location('routine_coverage_scorer', SCRIPT)
scorer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scorer)


def uid(index):
    return str(uuid.UUID(int=index))


class RoutineCoverageScorerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.scenario = self.write('scenario.json', dict(fixtureID='synthetic-contract', origin='synthetic',
            languages=['fr'], profiles={'realistic': {}}, scenes=[
                dict(id='agenda', moment='agenda', seconds={'realistic': 10}),
                dict(id='inbox', moment='messages', seconds={'realistic': 10}),
                dict(id='reading', moment='reading', seconds={'realistic': 10}),
                dict(id='own-ui', moment=None, negative='own-interface', seconds={'realistic': 10})]))
        self.oracle = self.write('oracle.json', dict(fixtureID='synthetic-contract', origin='synthetic', ocrChecks=[],
            steps=[dict(key=key, supportingScenes=[scene]) for key, scene in
                   [('agenda', 'agenda'), ('messages', 'inbox'), ('reading', 'reading')]] +
                  [dict(key='recap', supportingScenes=[])]))
        self.timeline = self.write('timeline.json', dict(profile='realistic', language='fr', durationSeconds=40,
            scenes=[dict(sceneID=scene, moment=moment, startSeconds=index * 10, endSeconds=(index + 1) * 10,
                         negative='own-interface' if moment is None else None)
                    for index, (scene, moment) in enumerate([
                        ('agenda', 'agenda'), ('inbox', 'messages'), ('reading', 'reading'), ('own-ui', None)])]))
        self.manifest = self.write('manifest.json', dict(scenarioSHA256=scorer.baseline.sha(self.scenario),
            oracleSHA256=scorer.baseline.sha(self.oracle),
            timelines=[dict(profile='realistic', language='fr', sha256=scorer.baseline.sha(self.timeline))],
            movies=[dict(profile='realistic', language='fr', sha256='a' * 64, bytes=123)]))
        self.frames = [dict(id=uid(index + 10), actualTimeSeconds=index * 10 + 2,
            # Deliberately wrong requested times: actual decoded time is authoritative.
            requestedTimeSeconds=2, outcome='observed', textWasTruncated=False,
            text=text) for index, text in enumerate([
                '09:15 Atelier de dessin.', 'Message reçu : apporte les notes.',
                'Je lis les pages du carnet.', 'MORE: Choose dated observations.'])]

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding='utf-8')
        return path

    def report(self, credited=(0, 1, 2)):
        evidence = dict(durationSeconds=40, frames=copy.deepcopy(self.frames))
        acquisition = dict(id=uid(1), origin='synthetic', sourceKind='video', fileSHA256='a' * 64,
                           videoEvidence=copy.deepcopy(evidence))
        proposal = dict(routine=dict(isApproved=False, sourceLabel='SYNTHETIC', steps=[]),
            sourceSnapshots=[dict(acquisitionID=uid(1), sourceRevision='b' * 64,
                                  sourceLayer='videoFrame', origin='synthetic')], support=[])
        report = dict(schemaVersion=2, status='completed', stage='exactSourceValidation',
            fingerprint=dict(sha256='a' * 64, byteCount=123), videoEvidence=evidence, acquisition=acquisition,
            classification=dict(status='completed', attemptedBatchCount=1, respondedBatchCount=1, failedBatchCount=0),
            citationsValid=True, proposal=proposal)
        for index, frame_index in enumerate(credited):
            self.add_step(report, uid(index + 100), [frame_index])
        return report

    def add_step(self, report, step_id, frame_indices):
        # No literal title, kind or preference duration can earn extra coverage.
        report['proposal']['routine']['steps'].append(dict(id=step_id, title='An unrelated duplicate title',
            kind='custom', durationMinutes=47))
        report['proposal']['support'].append(dict(stepID=step_id, reason='inferredEvidence', citations=[
            dict(acquisitionID=uid(1), sourceRevision='b' * 64, sourceLayer='videoFrame', sampleID=self.frames[i]['id'],
                 quote=self.frames[i]['text'], startCharacterOffset=0, endCharacterOffset=len(self.frames[i]['text']))
            for i in frame_indices]))

    def evaluate(self, actual):
        path = self.write('actual.json', actual)
        return scorer.compare(self.manifest, self.timeline, self.oracle, path, self.scenario)

    def assert_status(self, report, readable, covered, status, whole, code):
        result, returned_code = self.evaluate(report)
        coverage = result['activityCoverage']
        self.assertEqual(returned_code, code)
        self.assertEqual((coverage['readableMomentCount'], coverage['coveredMomentCount']), (readable, covered))
        self.assertEqual((coverage['status'], coverage['wholeCorpusStatus']), (status, whole))
        return result

    def test_complete_location_coverage_keeps_semantic_and_personal_authority_unproven(self):
        result = self.assert_status(self.report(), 3, 3, 'complete', 'complete', 0)
        self.assertEqual(result['verdict'], 'pipeline-source-validated-draft-not-execution')
        self.assertEqual(result['baselineScorerExitCode'], 0)
        self.assertEqual(result['downstreamRoutineExecution'], 'not-run')
        self.assertNotIn('recap', [row['moment'] for row in result['activityCoverage']['moments']])
        self.assertIn('Not title/kind/detail accuracy', result['activityCoverage']['scope'])
        self.assertIn('personal Keep/Exclude/duration', result['activityCoverage']['scope'])

    def test_an_agenda_or_two_agenda_events_are_never_three_activities(self):
        for indices in [(0,), (0, 0)]:
            with self.subTest(indices=indices):
                result = self.assert_status(self.report(indices), 3, 1, 'partial', 'partial', 5)
                self.assertEqual(result['activityCoverage']['readableButUncitedMoments'], ['messages', 'reading'])
                self.assertEqual(result['baselineScorerExitCode'], 0)

    def test_merged_cross_moment_row_cannot_claim_every_cited_activity(self):
        actual = self.report(())
        self.add_step(actual, uid(100), [0, 1, 2])
        result = self.assert_status(actual, 3, 0, 'none', 'none', 5)
        self.assertEqual(result['activityCoverage']['uncreditedSteps'][0]['reason'],
                         'mixedMomentCitationsRequireSemanticReview')

    def test_unsampled_or_unreadable_moment_remains_a_source_gap_not_a_model_omission(self):
        for variant in ['notSampled', 'ocrFailed', 'truncated', 'noActualTime', 'booleanTime']:
            with self.subTest(variant=variant):
                actual = self.report((0, 1))
                if variant == 'notSampled':
                    del actual['videoEvidence']['frames'][2]
                elif variant == 'ocrFailed':
                    actual['videoEvidence']['frames'][2].update(outcome='ocrFailed', text='')
                elif variant == 'truncated':
                    actual['videoEvidence']['frames'][2]['textWasTruncated'] = True
                elif variant == 'noActualTime':
                    actual['videoEvidence']['frames'][2].pop('actualTimeSeconds')
                else:
                    actual['videoEvidence']['frames'][2]['actualTimeSeconds'] = True
                actual['acquisition']['videoEvidence'] = copy.deepcopy(actual['videoEvidence'])
                result = self.assert_status(actual, 2, 2, 'complete', 'partial', 5)
                self.assertEqual(result['activityCoverage']['captureMissingMoments'], ['reading'])
                self.assertEqual(result['activityCoverage']['readableButUncitedMoments'], [])

    def test_native_policy_omission_does_not_erase_readable_source_from_denominator(self):
        actual = self.report((0,))
        actual['omissions'] = [dict(acquisitionID=uid(1), sampleID=uid(11), reason='unsupportedVisualContext')]
        self.assert_status(actual, 3, 1, 'partial', 'partial', 5)

    def test_explicit_abstention_pipeline_failure_is_preserved_with_zero_coverage(self):
        actual = self.report(())
        actual.update(status='failed', stage='localRoutineProposal', errorCategory='insufficientEvidence')
        actual.pop('proposal'); actual.pop('citationsValid')
        result = self.assert_status(actual, 3, 0, 'none', 'none', 4)
        self.assertEqual(result['verdict'], 'pipeline-not-complete-no-execution-proof')
        self.assertEqual(result['pipeline']['errorCategory'], 'insufficientEvidence')

    def test_bad_linkage_and_non_activity_scene_citations_cannot_credit_positive_scene(self):
        mutations = [('acquisitionID', uid(2)), ('sourceRevision', 'c' * 64), ('sampleID', uid(999)),
                     ('sourceLayer', 'correction'), ('quote', 'Fabricated task.'),
                     ('startCharacterOffset', -1), ('endCharacterOffset', True)]
        for field, value in mutations:
            with self.subTest(field=field):
                actual = self.report((0,))
                actual['proposal']['support'][0]['citations'][0][field] = value
                self.assert_status(actual, 3, 0, 'none', 'none', 5)
        actual = self.report((3,))
        result = self.assert_status(actual, 3, 0, 'none', 'none', 5)
        self.assertIn('nonActivityScene', result['activityCoverage']['uncreditedSteps'][0]['rejectedCitationCategories'])
        actual = self.report((0,))
        actual['proposal']['support'][0]['citations'] += self.report((3,))['proposal']['support'][0]['citations']
        self.assert_status(actual, 3, 0, 'none', 'none', 5)

    def test_native_validation_failure_or_changed_projection_is_not_an_empty_success(self):
        for variant in ['invalidNativeClaim', 'approved', 'changedProjection']:
            with self.subTest(variant=variant):
                actual = self.report()
                if variant == 'invalidNativeClaim':
                    actual['citationsValid'] = False
                elif variant == 'approved':
                    actual['proposal']['routine']['isApproved'] = True
                else:
                    actual['acquisition']['videoEvidence']['frames'][0]['text'] = 'Different evidence.'
                result, code = self.evaluate(actual)
                self.assertEqual(result['activityCoverage']['status'], 'not-evaluable')
                self.assertNotEqual(code, 0)

    def test_duplicate_native_rows_are_rejected_instead_of_arbitrarily_matched(self):
        for kind in ['frame', 'step', 'support']:
            with self.subTest(kind=kind):
                actual = self.report()
                if kind == 'frame':
                    actual['videoEvidence']['frames'].append(copy.deepcopy(actual['videoEvidence']['frames'][0]))
                    actual['acquisition']['videoEvidence'] = copy.deepcopy(actual['videoEvidence'])
                elif kind == 'step':
                    actual['proposal']['routine']['steps'].append(copy.deepcopy(actual['proposal']['routine']['steps'][0]))
                else:
                    actual['proposal']['support'].append(copy.deepcopy(actual['proposal']['support'][0]))
                with self.assertRaisesRegex(ValueError, 'Duplicate native identifiers'):
                    self.evaluate(actual)

    def test_source_fingerprint_rejection_keeps_original_diagnostic_and_skips_coverage(self):
        actual = self.report()
        actual['fingerprint']['sha256'] = 'f' * 64
        result, code = self.evaluate(actual)
        self.assertEqual(code, 3)
        self.assertEqual(result['verdict'], 'source-binding-rejected-no-oracle-comparison')
        self.assertEqual(result['activityCoverage']['status'], 'not-evaluable')

    def test_scenario_or_timeline_drift_cannot_rename_cited_moments(self):
        changed = json.loads(self.scenario.read_text())
        changed['scenes'][0]['moment'] = 'messages'
        self.write('scenario.json', changed)
        with self.assertRaisesRegex(ValueError, 'provenance'):
            self.evaluate(self.report())


if __name__ == '__main__':
    unittest.main()
