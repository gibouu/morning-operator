#!/usr/bin/env python3
"""Compare an already-produced local extraction/classification/proposal report to hidden truth.

Never invokes extraction or inference and never edits their inputs. Without
--actual, produces a sampling forecast only (exit 4, no execution evidence).
An OCR marker is a literal text check, not proof of an action or semantic fact.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import unicodedata


def load(path):
    if path.stat().st_size > 32 * 1024 * 1024:
        raise ValueError('A report exceeds the bounded 32 MiB scorer input')
    return json.loads(path.read_text(encoding='utf-8'))


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1_048_576), b''):
            result.update(block)
    return result.hexdigest()


def normalized(text):
    text = unicodedata.normalize('NFKD', text.casefold())
    return ' '.join(''.join(c if c.isalnum() else ' ' for c in text if not unicodedata.combining(c)).split())


def within(time, scenes):
    if not isinstance(time, (int, float)) or not math.isfinite(time):
        return None
    return next((scene for scene in scenes if scene['startSeconds'] <= time < scene['endSeconds']), None)


def classification_summary(classification):
    return dict(status=(classification or {}).get('status', 'not-run'),
                attemptedBatchCount=(classification or {}).get('attemptedBatchCount', 0),
                respondedBatchCount=(classification or {}).get('respondedBatchCount', 0),
                failedBatchCount=(classification or {}).get('failedBatchCount', 0),
                diagnostics=(classification or {}).get('diagnostics', []),
                modelIdentifier=(classification or {}).get('modelIdentifier'),
                semanticFactAccuracy=None,
                warning='This adapter classifies visual context only. No numeric classifier confidence, installed app identity or action authority is available.')


def source_binding(actual, manifest, timeline):
    binding = dict(reportFilename=actual.get('sourceFilename'),
                   expectedFilename=f"{timeline['profile']}-{timeline['language']}.mp4",
                   reportDoesNotContainMovieHash=True,
                   warning='Verify the actual invocation separately; filename/duration are not a cryptographic binding of report to source.')
    if 'fingerprint' not in actual:
        return binding
    fingerprint = actual['fingerprint']
    movies = [movie for movie in manifest['movies']
              if movie['profile'] == timeline['profile'] and movie['language'] == timeline['language']]
    valid = (isinstance(fingerprint, dict) and isinstance(fingerprint.get('sha256'), str)
             and len(fingerprint['sha256']) == 64
             and all(char in '0123456789abcdef' for char in fingerprint['sha256'])
             and type(fingerprint.get('byteCount')) is int and fingerprint['byteCount'] >= 0)
    expected = movies[0] if len(movies) == 1 else None
    status = ('invalid-fingerprint' if not valid else 'manifest-movie-unavailable' if expected is None
              else 'matched' if fingerprint['sha256'] == expected['sha256'] and fingerprint['byteCount'] == expected['bytes']
              else 'mismatch')
    binding.update(reportDoesNotContainMovieHash=False, status=status,
                   reportedFingerprint=fingerprint,
                   expectedSHA256=expected['sha256'] if expected else None,
                   expectedByteCount=expected['bytes'] if expected else None,
                   warning='Compares the reported complete-file hash and byte count to the frozen manifest. Verify the native invocation separately; this is not capture authenticity or semantic accuracy.')
    return binding


def pipeline_summary(actual):
    # This is a distinct producer contract, not a relabeled classifier report.
    proposal = actual.get('proposal')
    routine = (proposal.get('routine') or {}) if isinstance(proposal, dict) else {}
    routine = routine if isinstance(routine, dict) else {}
    steps = routine.get('steps', [])
    steps = steps if isinstance(steps, list) else []
    return dict(status=actual.get('status'), stage=actual.get('stage'), scope=actual.get('scope'),
                elapsedSeconds=actual.get('elapsedSeconds'),
                errorCategory=actual.get('errorCategory'), nativeError=actual.get('nativeError'),
                contextCapability=actual.get('contextCapability'), proposalCapability=actual.get('proposalCapability'),
                extractionWarnings=actual.get('extractionWarnings', []), omissions=actual.get('omissions', []),
                preparedUnitCount=actual.get('preparedUnitCount'),
                preparedSubmittedCharacterCount=actual.get('preparedSubmittedCharacterCount', actual.get('submittedCharacterCount')),
                preparedModelRequestCount=actual.get('preparedModelRequestCount', actual.get('modelRequestCount')),
                proposalProgressTotalRequests=actual.get('proposalProgressTotalRequests'),
                proposalCompletedRequests=actual.get('proposalCompletedRequests'), actualProposalModelRequestCount=None,
                proposal=dict(present=isinstance(proposal, dict), applicationCitationsValid=actual.get('citationsValid'),
                              stepCount=len(steps) if isinstance(proposal, dict) else None,
                              routineIsApproved=routine.get('isApproved'),
                              sourceLabel=routine.get('sourceLabel'),
                              sourceSnapshots=proposal.get('sourceSnapshots', []) if isinstance(proposal, dict) else [],
                              support=proposal.get('support', []) if isinstance(proposal, dict) else [],
                              omissions=proposal.get('omissions', []) if isinstance(proposal, dict) else [],
                              steps=[{key: step.get(key) for key in ['id', 'title', 'kind', 'durationMinutes', 'automation']}
                                     for step in steps if isinstance(step, dict)] if len(steps) <= 10 else [],
                              stepsOmittedByScorer=len(steps) if len(steps) > 10 else 0,
                              warning='Source validation is the application report claim, not independent semantic fact accuracy, user approval or execution.'),
                userApproval='not-performed-by-this-opt-in', providerExecution='not-run-by-this-opt-in',
                warning='Preserves the complete pipeline outcome, including failure after completed context classification. Prepared work and the announced progress total are not attempted request counts. Completed callbacks count completed batches only; attempted requests remain unknown.')


def compare(manifest_path, timeline_path, oracle_path, actual_path):
    manifest, timeline, oracle = load(manifest_path), load(timeline_path), load(oracle_path)
    if sha(oracle_path) != manifest['oracleSHA256']:
        raise ValueError('The oracle changed after source generation; choose its matching frozen version')
    saved = [row for row in manifest['timelines'] if row['profile'] == timeline['profile'] and row['language'] == timeline['language']]
    if len(saved) != 1 or saved[0]['sha256'] != sha(timeline_path):
        raise ValueError('Timeline does not match its source-generation manifest')
    scenes = timeline['scenes']
    duration, language = timeline['durationSeconds'], timeline['language']
    count = min(24, max(1, math.ceil(min(duration, 86400) / 2)))
    times = [0] if count == 1 else [(duration - min(0.1, duration / 2)) * i / (count - 1) for i in range(count)]
    forecast = {scene['sceneID']: [] for scene in scenes}
    for index, time in enumerate(times):
        scene = within(time, scenes)
        if scene:
            forecast[scene['sceneID']].append(index)
    result = dict(schemaVersion=1, origin='synthetic', profile=timeline['profile'], language=language,
                  sourceSeconds=duration, oracleSHA256=sha(oracle_path), timelineSHA256=sha(timeline_path),
                  isIsolatedDiagnostic=timeline.get('isIsolatedDiagnostic', False),
                  notLongSourceCoverage=timeline.get('notLongSourceCoverage', False),
                  disclosure='Diagnostic comparison only; not a product acceptance, native capture, effect or personal-habit proof.',
                  samplingForecast=dict(policySnapshot='MediaObservationService/FrameSampling at a47fd03; max24, evenly spaced, last=duration−0.1',
                                        actualExecution=False, requestedSeconds=times, sceneSampleIndices=forecast,
                                        missedScenes=[key for key, values in forecast.items() if not values]),
                  sourceCoverage='Sparse point observations only. Never continuous foreground duration.',
                  realOCR='not-run', realClassification='not-run', downstreamRoutineExecution='not-run')
    if actual_path is None:
        result['verdict'] = 'forecast-only-no-real-pipeline-evidence'
        return result, 4
    actual = load(actual_path)
    is_pipeline = 'videoEvidence' in actual or ('status' in actual and 'stage' in actual)
    if is_pipeline and 'evidence' in actual:
        raise ValueError('Ambiguous report contract: both legacy evidence and full-pipeline fields are present')
    evidence = (actual.get('videoEvidence') if is_pipeline else actual.get('evidence')) or {}
    frames = evidence.get('frames', [])
    classification = actual.get('classification')
    binding = source_binding(actual, manifest, timeline)
    if is_pipeline:
        result['reportFormat'] = 'full-routine-pipeline-v1'
        result['pipeline'] = pipeline_summary(actual)
    if binding.get('status') in ['mismatch', 'invalid-fingerprint', 'manifest-movie-unavailable']:
        result.update(sourceBinding=binding, realClassification=classification_summary(classification),
                      realOCR=dict(status='not-compared-source-binding-rejected', frameCount=len(frames)),
                      verdict='source-binding-rejected-no-oracle-comparison')
        return result, 3
    decisions = {row['sampleID']: row for row in (classification or {}).get('decisions', [])}
    excerpts = {row['sampleID'] for row in ((classification or {}).get('inputSelection') or {}).get('excerpts', [])}
    observations = {scene['sceneID']: [] for scene in scenes}
    unmatched, rows = [], []
    for frame in frames:
        # Requested time never stands in for an absent native actualTimeSeconds.
        scene = within(frame.get('actualTimeSeconds'), scenes)
        if scene is None:
            unmatched.append(frame.get('id'))
            continue
        observations[scene['sceneID']].append(frame)
        decision = decisions.get(frame['id'])
        identity = (decision or {}).get('evidence', {}).get('identified', {}).get('app')
        quote = (decision or {}).get('evidenceQuote')
        confidence = [line['confidence'] for line in (frame.get('ocrLines') or []) if isinstance(line.get('confidence'), (float, int))]
        rows.append(dict(sampleID=frame['id'], sceneID=scene['sceneID'], actualTimeSeconds=frame['actualTimeSeconds'],
                         requestedTimeSeconds=frame.get('requestedTimeSeconds'), outcome=frame.get('outcome'),
                         textWasTruncated=frame.get('textWasTruncated', False), negative=scene.get('negative'),
                         nearSceneBoundary=min(frame['actualTimeSeconds'] - scene['startSeconds'], scene['endSeconds'] - frame['actualTimeSeconds']) <= 0.2,
                         selectedForModel=frame['id'] in excerpts, identity=identity,
                         exactQuoteRetained=(normalized(quote) in normalized(frame.get('text', ''))) if quote else None,
                         identityReason=(decision or {}).get('reason'),
                         classifierConfidence=None, classifierConfidenceAvailable=False,
                         ocrConfidenceMin=min(confidence) if confidence else None,
                         ocrConfidenceMax=max(confidence) if confidence else None))
    checks = []
    for check in oracle['ocrChecks']:
        if check['scene'] not in observations:
            continue
        samples = observations[check['scene']]
        observed = [sample for sample in samples if sample.get('outcome') == 'observed']
        text = ' '.join(sample.get('text', '') for sample in observed)
        checks.append(dict(id=check['id'], sceneID=check['scene'], sampled=bool(samples),
                           observedSampleCount=len(observed),
                           literalMarkerPresent=normalized(check['literal'][language]) in normalized(text) if observed else None))
    eligible = [check for check in checks if check['observedSampleCount'] > 0]
    matches = sum(check['literalMarkerPresent'] is True for check in eligible)
    result.update(realOCR=dict(reportSHA256=sha(actual_path), frameCount=len(frames),
                               actualDurationSeconds=evidence.get('durationSeconds'),
                               durationMatches=abs(evidence.get('durationSeconds', -1) - duration) <= 0.2,
                               unmappedActualTimeSampleIDs=unmatched,
                               missedScenes=[key for key, values in observations.items() if not values],
                               literalChecks=checks, sampledLiteralMatches=matches, sampledLiteralDenominator=len(eligible),
                               sampledLiteralRecall=matches / len(eligible) if eligible else None,
                               wholeSourceLiteralDenominator=len(checks),
                               warning='Conditional literal OCR recall excludes unsampled scenes; read both denominators. No action/draft/send correctness is inferred.'),
                  realClassification=classification_summary(classification),
                  sampleComparison=rows,
                  sourceBinding=binding,
                  verdict='diagnostic-report-not-full-acceptance')
    if is_pipeline:
        result['realOCR']['status'] = 'extracted' if isinstance(actual.get('videoEvidence'), dict) else 'not-run'
        valid_draft = (actual.get('status') == 'completed' and actual.get('citationsValid') is True
                       and result['pipeline']['proposal']['present']
                       and result['pipeline']['proposal']['routineIsApproved'] is False
                       and 1 <= (result['pipeline']['proposal']['stepCount'] or 0) <= 10
                       and binding.get('status') == 'matched'
                       and classification and classification.get('status') == 'completed'
                       and classification.get('attemptedBatchCount', 0) > 0
                       and classification.get('respondedBatchCount', 0) > 0
                       and classification.get('failedBatchCount') == 0)
        result['pipeline']['proposal']['validatedDraftReported'] = bool(valid_draft)
        result['verdict'] = ('pipeline-source-validated-draft-not-execution' if valid_draft
                             else 'pipeline-not-complete-no-execution-proof')
        return result, 0 if valid_draft else 4
    return result, 0 if classification and classification.get('status') == 'completed' else 4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--timeline', type=Path, required=True)
    parser.add_argument('--oracle', type=Path, default=Path(__file__).resolve().parents[1] / 'Benchmarks/routine-fixture-v1/expected-parsed.json')
    parser.add_argument('--actual', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result, code = compare(args.manifest, args.timeline, args.oracle, args.actual)
    with args.output.open('x', encoding='utf-8') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps(dict(output=str(args.output), verdict=result['verdict'], exitCode=code)))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
