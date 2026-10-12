#!/usr/bin/env python3
"""Local synthetic capture controller. The fixture/truth payload is never model input."""
import argparse
from datetime import date, timedelta
import hashlib
import json
import os
from pathlib import Path
import plistlib
import random
import re
import secrets
import selectors
import signal
import subprocess
import time

GENERATOR_VERSION = 'seeded-fixture-v1'


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def fixture_content(seed):
    """Stable versioned generator; saved content is the exact replay receipt."""
    if not re.fullmatch(r'[0-9a-f]{16}', seed):
        raise ValueError('A seed is exactly 16 lowercase hexadecimal characters.')
    rng = random.Random(int(seed, 16))
    senders = ['Maya Chen', 'Alex Rivera', 'Robin Shah', 'Sam Laurent', 'Juniper Lee', 'Taylor Brooks']
    objects = ['blue notebook', 'green folder', 'red sketchbook', 'yellow pencil case', 'purple map', 'orange scarf']
    venues = ['Cedar room', 'River studio', 'North library', 'Willow hall', 'Garden cafe', 'Oak workshop']
    subjects = ['Notebook handoff', 'Map collection', 'Workshop supplies', 'Library plans', 'Sketchbook return', 'Studio visit']
    activities = ['Planning session', 'Drawing workshop', 'Book discussion', 'Garden meeting', 'Walking group', 'Photo review']
    first_day = date(2026, 10, 1) + timedelta(days=rng.randrange(120))
    messages, events = [], []
    for index in range(1, 31):
        observed_day = (first_day + timedelta(days=(index - 1) // 6)).isoformat()
        sender = rng.choice(senders)
        subject = f'{rng.choice(subjects)} {index:02d}'
        item = rng.choice(objects)
        venue = rng.choice(venues)
        hour, minute = rng.randrange(8, 18), rng.choice([0, 15, 30, 45])
        clock = f'{hour:02d}:{minute:02d}'
        body = f'Please bring the {item} to {venue} at {clock} on {observed_day}.'
        fields = {'sender': sender, 'subject': subject, 'date': observed_day,
                  'time': clock, 'body': body}
        messages.append(make_item(index, 'message', fields,
                                   f'{sender} · {observed_day}', body))
        event_subject = f'{rng.choice(activities)} {index:02d}'
        event_hour = rng.randrange(8, 18)
        event_minute = rng.choice([0, 15, 30])
        event_time = f'{event_hour:02d}:{event_minute:02d}'
        end_minutes = event_hour * 60 + event_minute + rng.choice([30, 45, 60])
        end_time = f'{end_minutes // 60:02d}:{end_minutes % 60:02d}'
        location = rng.choice(venues)
        reminder = f'Bring the {rng.choice(objects)}'
        event_body = 'Synthetic agenda entry. No connected calendar or invitation.'
        fields = {'subject': event_subject, 'date': observed_day, 'time': event_time,
                  'endTime': end_time, 'location': location, 'reminder': reminder, 'body': event_body}
        events.append(make_item(index, 'event', fields,
                                f'{event_time} · {observed_day}', f'{location} · {reminder}'))
    return {'schemaVersion': 1, 'generatorVersion': GENERATOR_VERSION,
            'seed': seed, 'messages': messages, 'events': events}


def make_item(index, kind, fields, subtitle, preview):
    item = {'index': index, 'sourceID': f'fixture.{kind}.{index:02d}',
            'title': fields['subject'], 'subtitle': subtitle, 'preview': preview,
            'body': fields['body'], 'fields': fields}
    item['sourceRevision'] = hashlib.sha256(canonical_json(item).encode('utf-8')).hexdigest()
    return item


def stamp():
    return {'monotonicSeconds': time.monotonic(), 'unixSeconds': time.time()}


def main():
    parser = argparse.ArgumentParser(description='Record a booted iOS simulator while XCTest drives two native synthetic fixture apps. Local artifacts only; capture does not imply model or digest success.')
    parser.add_argument('--variant', choices=['baseline', 'heldout', 'digest'], default='baseline')
    parser.add_argument('--seed', help='Replay a generator-v1 seed: exactly 16 hexadecimal characters; default is a fresh random seed.')
    parser.add_argument('--device', required=True, help='UUID of a booted iOS simulator')
    parser.add_argument('--run', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    device = args.device
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', args.run):
        parser.error('--run must be a short filename-safe run identifier')
    seed = args.seed.lower() if args.seed is not None else secrets.token_hex(8)
    if not re.fullmatch(r'[0-9a-f]{16}', seed):
        parser.error('--seed must contain exactly 16 hexadecimal characters')
    content = fixture_content(seed)
    content_json = canonical_json(content)
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True))
    if not any(item['udid'] == device and item['state'] == 'Booted' and item.get('isAvailable')
               for runtime, items in devices['devices'].items() if '.iOS-' in runtime for item in items):
        parser.error('--device must identify an available, booted iOS simulator')
    products = root / '.build/benchmark/Build/Products'
    candidates = list(products.glob('MorningObservationBenchmark_*.xctestrun'))
    if len(candidates) != 1:
        parser.error('Build MorningObservationBenchmark into .build/benchmark first; expected one generated xctestrun')
    out = root / 'work/observation-benchmark' / args.run
    out.mkdir(parents=True, exist_ok=False)
    # This is an oracle/rendering fixture, NOT material for inference. Keep it separate from recording.mov.
    (out / 'fixture-content.json').write_text(content_json + '\n', encoding='utf-8')
    with candidates[0].open('rb') as handle:
        configuration = plistlib.load(handle)
    target = configuration['MorningObservationBenchmarkUITests']
    target.setdefault('EnvironmentVariables', {}).update({
        'MO_OBSERVATION_BENCHMARK': '1',
        'MO_OBSERVATION_BENCHMARK_VARIANT': args.variant,
        'MO_OBSERVATION_BENCHMARK_SEED': seed,
        'MO_OBSERVATION_BENCHMARK_CONTENT': content_json,
    })
    configured = products / f'Observation-{args.run}.xctestrun'
    with configured.open('wb') as handle:
        plistlib.dump(configuration, handle)
    for app in ('MorningBenchmarkInbox', 'MorningBenchmarkCalendar'):
        subprocess.run(['xcrun', 'simctl', 'install', device,
                        str(products / 'Debug-iphonesimulator' / (app + '.app'))], check=True)
    metadata = {'schemaVersion': 2, 'variant': args.variant, 'origin': 'synthetic',
                'seed': seed, 'generatorVersion': GENERATOR_VERSION,
                'fixtureContentSHA256': hashlib.sha256(content_json.encode('utf-8')).hexdigest(),
                'recordCommandBefore': stamp(),
                'alignment': 'Recording-start notification bounds first frame; controller truth and fixture content are scored separately, never model input.',
                'replay': 'Use the same seed and generator version; fixture-content.json preserves the exact rendered payload. Runtime timings and recording bytes are not deterministic.'}
    movie = out / 'recording.mov'
    recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(movie)],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    metadata['recordCommandAfter'] = stamp()
    selector = selectors.DefaultSelector()
    selector.register(recorder.stdout, selectors.EVENT_READ)
    log = bytearray()
    test = None
    try:
        deadline = time.monotonic() + 30
        while b'Recording started' not in log:
            if time.monotonic() >= deadline or recorder.poll() is not None:
                raise RuntimeError('Simulator recording never reported its first frame.')
            for key, _ in selector.select(0.25):
                data = os.read(key.fileobj.fileno(), 4096)
                if data:
                    log.extend(data)
        metadata['recordingStartedObserved'] = stamp()
        print(f'Real simulator recording started; seed {seed}; running the independent action sequence.', flush=True)
        with (out / 'xcode-test.log').open('wb') as output:
            metadata['testCommandBefore'] = stamp()
            test = subprocess.Popen(['xcodebuild', 'test-without-building', '-xctestrun', str(configured),
                '-destination', f'platform=iOS Simulator,id={device}', '-parallel-testing-enabled', 'NO',
                '-collect-test-diagnostics', 'never', '-resultBundlePath', str(out / 'test.xcresult')],
                cwd=root, stdout=output, stderr=subprocess.STDOUT)
            metadata['testExitCode'] = test.wait(timeout=900)
            metadata['testCommandAfter'] = stamp()
    finally:
        if test is not None and test.poll() is None:
            test.terminate()
            test.wait(timeout=30)
        metadata['recordingStopRequested'] = stamp()
        if recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
        selector.close()
        remaining, _ = recorder.communicate(timeout=60)
        log.extend(remaining)
        metadata['recordingExitCode'] = recorder.returncode
        metadata['recordingFinalizedObserved'] = stamp()
        (out / 'recorder.log').write_bytes(log)
        (out / 'capture-metadata.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print(json.dumps({'output': str(out), 'seed': seed, 'testExit': metadata.get('testExitCode'),
                      'recordingExit': recorder.returncode,
                      'movieBytes': movie.stat().st_size if movie.exists() else 0}, indent=2), flush=True)
    return metadata.get('testExitCode', 1)


if __name__ == '__main__':
    raise SystemExit(main())
