#!/usr/bin/env python3
"""Offline citation coverage of the frozen synthetic routine corpus.

Does not run extraction, inference, approval or effects. The original scorer's
verdict is retained; this additional score never supplies truth to a model.
Exit 5 means incomplete citation coverage (including capture gaps), not that the
model should invent missing moments. Exit 0 still requires semantic review and
is NOT MORE product acceptance. Inputs are bounded by the original scorer.
"""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import uuid


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('routine_fixture_baseline', HERE / 'score-routine-fixture.py')
baseline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(baseline)
CORPUS = HERE.parent / 'Benchmarks/routine-fixture-v1'


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def identifier(value):
    if not isinstance(value, str):
        raise ValueError('A native identifier is missing')
    try:
        return str(uuid.UUID(value))
    except ValueError as error:
        raise ValueError('A native identifier is malformed') from error


def unique_rows(rows, key):
    if not isinstance(rows, list):
        raise ValueError('Expected a native row list')
    indexed = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError('A native row is malformed')
        value = identifier(row.get(key))
        if value in indexed:
            raise ValueError('Duplicate native identifiers cannot be silently merged')
        indexed[value] = row
    return indexed


def expectations(scenario, oracle, timeline, manifest, scenario_path):
    """Bind the hidden expectation to the rendered timeline, never to titles."""
    if (manifest.get('scenarioSHA256') != baseline.sha(scenario_path)
            or scenario.get('origin') != 'synthetic' or oracle.get('origin') != 'synthetic'
            or scenario.get('fixtureID') != oracle.get('fixtureID')
            or timeline.get('profile') not in scenario.get('profiles', {})
            or timeline.get('language') not in scenario.get('languages', [])):
        raise ValueError('Scenario/oracle/timeline provenance does not match the frozen corpus')
    source = scenario.get('scenes', [])
    scenes = {row['id']: row for row in source}
    if not source or len(scenes) != len(source):
        raise ValueError('The source has no unambiguous scene sequence')
    moments = {}
    keys = set()
    for step in oracle.get('steps', []):
        key, supporting = step['key'], step.get('supportingScenes', [])
        if key in keys or not isinstance(supporting, list) or len(supporting) != len(set(supporting)):
            raise ValueError('The oracle moment keys/scenes are ambiguous')
        keys.add(key)
        if not supporting:  # e.g. recap: explicitly added by the person, not video inference.
            if any(row.get('moment') == key for row in source):
                raise ValueError('A source moment is incorrectly marked as user-added')
            continue
        if any(scene not in scenes or scenes[scene].get('moment') != key
               or scenes[scene].get('negative') for scene in supporting):
            raise ValueError('An expected activity is not tied to positive source scenes')
        moments[key] = supporting
    positive = {row['moment'] for row in source if row.get('moment') is not None}
    if not moments or set(moments) != positive:
        raise ValueError('The expected activities do not cover the source moment identities')
    actual_scenes = timeline.get('scenes', [])
    if not actual_scenes or len({row['sceneID'] for row in actual_scenes}) != len(actual_scenes):
        raise ValueError('Timeline scene identities are missing or duplicated')
    isolated = timeline.get('isIsolatedDiagnostic') is True
    if isolated != (timeline.get('notLongSourceCoverage') is True):
        raise ValueError('An isolated clip must declare its limited scope')
    if not isolated and [row['sceneID'] for row in actual_scenes] != [row['id'] for row in source]:
        raise ValueError('A long timeline does not contain the frozen source sequence')
    cursor = 0
    for row in actual_scenes:
        scene = scenes.get(row['sceneID'])
        start, end = row.get('startSeconds'), row.get('endSeconds')
        if (scene is None or row.get('moment') != scene.get('moment')
                or row.get('negative') != scene.get('negative')
                or not number(start) or not number(end) or start != cursor or end <= start):
            raise ValueError('Timeline scenes are not an exact non-overlapping source projection')
        if not isolated and end - start != scene['seconds'][timeline['profile']]:
            raise ValueError('A source scene was retimed without a distinct isolated scope')
        cursor = end
    if cursor != timeline.get('durationSeconds'):
        raise ValueError('The timeline duration does not match its scenes')
    return moments


def readable(frame):
    return (frame.get('outcome') == 'observed' and frame.get('textWasTruncated', False) is False
            and isinstance(frame.get('text'), str) and bool(frame['text'].strip()))


def scene_at(frame, timeline):
    actual_time = frame.get('actualTimeSeconds')
    return baseline.within(actual_time, timeline['scenes']) if number(actual_time) else None


def status(covered, total):
    if covered == 0:
        return 'none'
    return 'complete' if covered == total else 'partial'


def citation_scene(citation, acquisition_id, revision, frames, timeline):
    """Corroborate native citation linkage, not Core's grapheme/policy validator."""
    try:
        if identifier(citation.get('acquisitionID')) != acquisition_id:
            return None, 'otherAcquisition'
        sample_id = identifier(citation.get('sampleID'))
    except (ValueError, AttributeError):
        return None, 'missingOrInvalidSourceIdentifier'
    if citation.get('sourceRevision') != revision or citation.get('sourceLayer') != 'videoFrame':
        return None, 'revisionOrLayerMismatch'
    frame = frames.get(sample_id)
    if frame is None or not readable(frame):
        return None, 'missingOrUnreadableFrame'
    quote = citation.get('quote')
    start, end = citation.get('startCharacterOffset'), citation.get('endCharacterOffset')
    # Swift offsets count extended grapheme clusters. Do not pretend Python's
    # code-point indexing revalidates them. Core's isCurrent claim remains separate.
    if (not isinstance(quote, str) or not quote.strip()
            or quote.encode('utf-8') not in frame['text'].encode('utf-8')
            or type(start) is not int or type(end) is not int or not 0 <= start < end <= len(frame['text'])):
        return None, 'quoteOrOffsetMismatch'
    scene = scene_at(frame, timeline)
    if scene is None:
        return None, 'missingActualSceneTime'
    if scene.get('negative') or scene.get('moment') is None:
        return scene, 'nonActivityScene'
    return scene, None


def coverage(actual, expected, timeline):
    result = dict(methodVersion='native-frame-moment-v1', status='not-evaluable', wholeCorpusStatus='not-evaluable',
                  expectedObservableMomentCount=len(expected), readableMomentCount=0, coveredMomentCount=0,
                  unit='Distinct source moments; never generated row count or executed actions.',
                  moments=[], uncreditedSteps=[], issues=[],
                  scope='Citation location coverage only. Not title/kind/detail accuracy, event-to-consultation correctness, measured usage, personal Keep/Exclude/duration compliance, effects, approval or MORE section 10 acceptance.',
                  readableDefinition='An observed, nontruncated positive-scene frame with nonempty OCR text and an actual decoded time. This does not establish that OCR captured every decisive task line, or that a model omission is its fault.',
                  offsetValidation='Native grapheme offsets and evidence policy are not reimplemented here. Exact quote bytes, source IDs/revision and actual frame time are corroborated; citationsValid remains the native report claim.',
                  mixedSupportPolicy='One proposed row can credit one moment only. Cross-moment support is left unassigned for semantic review; repeated rows of the same moment do not multiply coverage.')
    acquisition, evidence = actual.get('acquisition'), actual.get('videoEvidence')
    if not isinstance(acquisition, dict) or not isinstance(evidence, dict):
        result['issues'].append('nativeVideoAcquisitionUnavailable')
        return result
    if (actual.get('schemaVersion') != 2 or actual.get('mode') is not None
            or acquisition.get('origin') != 'synthetic' or acquisition.get('sourceKind') != 'video'
            or acquisition.get('correctedText') is not None or acquisition.get('frameReviews', []) != []
            or acquisition.get('fileSHA256') != actual.get('fingerprint', {}).get('sha256')
            or acquisition.get('videoEvidence') != evidence
            or not number(evidence.get('durationSeconds'))
            or abs(evidence['durationSeconds'] - timeline['durationSeconds']) > 0.2):
        result['issues'].append('nativeSourceProjectionMismatch')
        return result
    acquisition_id = identifier(acquisition.get('id'))
    frames = unique_rows(evidence.get('frames'), 'id')
    if len(frames) > 24:
        raise ValueError('The report exceeds the current native frame sampling bound')
    rows = {key: dict(moment=key, supportingSceneIDs=scenes, sampledFrameCount=0,
                     readableFrameCount=0, creditedStepIDs=[]) for key, scenes in expected.items()}
    for frame in frames.values():
        scene = scene_at(frame, timeline)
        if scene and scene.get('moment') in rows and not scene.get('negative'):
            row = rows[scene['moment']]
            row['sampledFrameCount'] += 1
            row['readableFrameCount'] += int(readable(frame))
    proposal = actual.get('proposal')
    if isinstance(proposal, dict):
        routine = proposal.get('routine') or {}
        steps = unique_rows(routine.get('steps'), 'id')
        support = unique_rows(proposal.get('support'), 'stepID')
        snapshots = unique_rows(proposal.get('sourceSnapshots'), 'acquisitionID')
        if (actual.get('citationsValid') is not True or routine.get('isApproved') is not False
                or len(steps) > 10 or set(support) != set(steps) or set(snapshots) != {acquisition_id}
                or snapshots[acquisition_id].get('origin') != 'synthetic'
                or snapshots[acquisition_id].get('sourceLayer') != 'videoFrame'):
            result['issues'].append('nativeDraftOrCitationValidationUnavailable')
            return result
        revision = snapshots[acquisition_id].get('sourceRevision')
        if (not isinstance(revision, str) or len(revision) != 64
                or any(char not in '0123456789abcdef' for char in revision)):
            result['issues'].append('invalidNativeSourceRevision')
            return result
        for step_id, row in support.items():
            citations = row.get('citations')
            if not isinstance(citations, list) or len(citations) > 512:
                raise ValueError('A step exceeds the native citation bound')
            candidates, rejected = set(), []
            for citation in citations:
                scene, error = citation_scene(citation, acquisition_id, revision, frames, timeline)
                if error:
                    rejected.append(error)
                elif scene['sceneID'] not in expected.get(scene['moment'], []):
                    rejected.append('sceneNotSupportingExpectedMoment')
                else:
                    candidates.add(scene['moment'])
            reason = ('invalidOrNonActivityCitation' if rejected else 'noVideoCitations' if not candidates
                      else 'mixedMomentCitationsRequireSemanticReview' if len(candidates) != 1 else None)
            if reason:
                result['uncreditedSteps'].append(dict(stepID=step_id, reason=reason,
                    candidateMoments=sorted(candidates), rejectedCitationCategories=sorted(set(rejected))))
            else:
                rows[next(iter(candidates))]['creditedStepIDs'].append(step_id)
    for row in rows.values():
        row['status'] = ('covered' if row['creditedStepIDs'] else 'readableButUncited' if row['readableFrameCount']
                         else 'sampledButUnreadable' if row['sampledFrameCount'] else 'notSampled')
    result['moments'] = list(rows.values())
    result['readableMomentCount'] = sum(row['readableFrameCount'] > 0 for row in rows.values())
    result['coveredMomentCount'] = sum(bool(row['creditedStepIDs']) for row in rows.values())
    result['status'] = status(result['coveredMomentCount'], result['readableMomentCount'])
    result['wholeCorpusStatus'] = status(result['coveredMomentCount'], len(expected))
    result['captureMissingMoments'] = [row['moment'] for row in rows.values() if not row['readableFrameCount']]
    result['readableButUncitedMoments'] = [row['moment'] for row in rows.values()
                                         if row['readableFrameCount'] and not row['creditedStepIDs']]
    return result


def compare(manifest_path, timeline_path, oracle_path, actual_path, scenario_path):
    original, original_code = baseline.compare(manifest_path, timeline_path, oracle_path, actual_path)
    original['baselineScorerExitCode'] = original_code
    if original.get('sourceBinding', {}).get('status') != 'matched':
        original['activityCoverage'] = dict(status='not-evaluable', wholeCorpusStatus='not-evaluable',
                                            issues=['matchedNativeSourceFingerprintRequired'])
        original['activityCoverageExitCode'] = original_code or 3
        return original, original['activityCoverageExitCode']
    manifest, timeline, oracle = [baseline.load(path) for path in (manifest_path, timeline_path, oracle_path)]
    expected = expectations(baseline.load(scenario_path), oracle, timeline, manifest, scenario_path)
    original['activityCoverage'] = coverage(baseline.load(actual_path), expected, timeline)
    complete = (original['activityCoverage']['status'] == 'complete'
                and original['activityCoverage']['wholeCorpusStatus'] == 'complete')
    code = original_code or (0 if complete else 5)
    original['activityCoverageExitCode'] = code
    return original, code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--timeline', type=Path, required=True)
    parser.add_argument('--oracle', type=Path, default=CORPUS / 'expected-parsed.json')
    parser.add_argument('--scenario', type=Path, default=CORPUS / 'scenario.json')
    parser.add_argument('--actual', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    # Resolve the parent only. Resolving the final component would turn a
    # dangling symlink into its target before O_NOFOLLOW could reject it.
    destination = args.output.parent.resolve() / args.output.name
    if not destination.is_relative_to((HERE.parent / 'work').resolve()):
        parser.error('Keep the new private report inside this checkout\'s ignored work directory')
    result, code = compare(args.manifest, args.timeline, args.oracle, args.actual, args.scenario)
    # Private metadata report, never replace an earlier result or follow a link.
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps(dict(verdict=result['verdict'], coverage=result['activityCoverage']['status'], exitCode=code)))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
