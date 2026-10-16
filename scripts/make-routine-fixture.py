#!/usr/bin/env python3
"""Offline SYNTHETIC source pixels/movie + separately authored portable oracle.

No simulator, app, network, model, account or provider is used. Source rendering
accepts scenario data only; expected-parsed.json never supplies its pixels.
Requires already-installed Pillow, ffmpeg and ffprobe; installs nothing.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / 'Benchmarks/routine-fixture-v1'
SIZE = (780, 1688)
VERSION = 'drawn-routine-v1'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1_048_576), b''):
            value.update(block)
    return value.hexdigest()


def save_json(path, value):
    with path.open('x', encoding='utf-8') as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write('\n')


def font(size, bold=False):
    name = 'Arial Bold.ttf' if bold else 'Arial.ttf'
    candidates = [Path('/System/Library/Fonts/Supplemental') / name,
                  Path('/System/Library/Fonts/Helvetica.ttc')]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    raise RuntimeError('Install no fonts automatically: provide an existing system Arial/Helvetica font.')


def lines(text, face, width, draw):
    result = []
    for paragraph in text.split('\n'):
        current = ''
        for word in paragraph.split():
            trial = f'{current} {word}'.strip()
            if draw.textlength(trial, font=face) <= width:
                current = trial
            else:
                if not current or draw.textlength(word, font=face) > width:
                    raise ValueError(f'A source word does not fit: {word!r}')
                result.append(current)
                current = word
        result.append(current)
    return result


def draw_scene(scene, language, destination):
    """No oracle, expected label, hidden cue or profile timestamp enters pixels."""
    image = Image.new('RGB', SIZE, '#f5f2ed')
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, SIZE[0], 98), fill='#8e2638')
    small, body, heading, title = font(24), font(29), font(32, True), font(42, True)
    draw.text((36, 18), 'SYNTHETIC · ' + language.upper(), font=font(27, True), fill='white')
    draw.text((36, 57), 'No real account, send, write or like', font=small, fill='white')
    y = 125
    for line in lines(scene['app'], heading, 696, draw):
        draw.text((42, y), line, font=heading, fill='#1d4964'); y += 43
    draw.line((42, y + 8, 738, y + 8), fill='#b6bec1', width=2)
    y += 35
    for line in lines(scene['title'][language], title, 696, draw):
        draw.text((42, y), line, font=title, fill='#232c36'); y += 54
    y += 28
    for block in scene['blocks']:
        heads = lines(block['heading'][language], heading, 648, draw)
        content = lines(block['body'][language], body, 648, draw)
        height = 32 + len(heads) * 43 + 12 + len(content) * 41 + 24
        if y + height > 1560:
            raise ValueError(f"{scene['id']}/{language}: source text overflows; never silently truncate it")
        draw.rounded_rectangle((36, y, 744, y + height), radius=18, fill='white', outline='#dce0df', width=2)
        baseline = y + 20
        for line in heads:
            draw.text((60, baseline), line, font=heading, fill='#263f50'); baseline += 43
        baseline += 12
        for line in content:
            draw.text((60, baseline), line, font=body, fill='#26313e'); baseline += 41
        y += height + 24
    if scene.get('visual') and y + 210 < 1555:
        draw.rounded_rectangle((180, y + 15, 600, y + 205), radius=24, fill='#d6e5dd')
        if scene['visual'] == 'video':
            draw.polygon([(350, y + 65), (350, y + 155), (435, y + 110)], fill='#446f63')
        else:
            for x, height in [(310, 45), (350, 90), (390, 65), (430, 110)]:
                draw.rounded_rectangle((x, y + 145 - height, x + 16, y + 145), radius=7, fill='#446f63')
    draw.text((36, 1614), 'OFFLINE STORYBOARD · NOT NATIVE CAPTURE', font=font(23, True), fill='#793544')
    draw.text((36, 1650), 'Invented content · no audio · no external service', font=font(23), fill='#535c65')
    image.save(destination)
    return image


def validate(scenario, oracle):
    assert scenario['origin'] == oracle['origin'] == 'synthetic'
    assert scenario['fixtureID'] == oracle['fixtureID']
    assert scenario['privacy'] == dict(containsPersonalData=False, networkAllowed=False, realEffectsAllowed=False, audioIncluded=False)
    ids = [scene['id'] for scene in scenario['scenes']]
    assert len(ids) == len(set(ids))
    for scene in scenario['scenes']:
        assert re.fullmatch(r'[a-z0-9-]+', scene['id'])
        for profile in scenario['profiles']:
            assert isinstance(scene['seconds'][profile], int) and scene['seconds'][profile] > 0
    for profile, key in [('realistic', 'sourceRealisticSeconds'), ('accelerated', 'sourceAcceleratedSeconds')]:
        duration = sum(scene['seconds'][profile] for scene in scenario['scenes'])
        assert duration == oracle['timing'][key] and 0 < duration <= 31 * 60
    assert len(oracle['steps']) == 10 and len({step['id'] for step in oracle['steps']}) == 10
    assert sum(step['durationMinutes'] for step in oracle['steps']) == oracle['timing']['candidateMinutes']
    assert all(set(step['supportingScenes']) <= set(ids) for step in oracle['steps'])
    assert all(step['detail'][lang].startswith('SYNTHETIC') for step in oracle['steps'] for lang in scenario['languages'])
    assert oracle['approvalExpected'] is False
    assert [step['durationMinutes'] * 60 for step in oracle['steps']] == oracle['timing']['executionProfiles']['realisticBudgetSeconds']


def portable(oracle, language):
    # The public portable format intentionally cannot carry action targets,
    # send payloads, preferences or approval authority. Root owns any DEBUG adapter.
    return dict(format='morning-operator.routine', formatVersion=1, detail='includeDetails',
                sourceRoutineID='90000000-0000-4000-8000-000000000100', sourceRoutineVersion=1,
                sourceCreatedAt=datetime.fromisoformat('2026-10-16T07:45:00+02:00').timestamp(),
                approvalAtExport=False, sourceIsSynthetic=True,
                sourceLabel='Demo fixture — SYNTHETIC manual oracle; no OCR or model execution',
                steps=[dict(id=step['id'], title=step['title'][language], kind=step['kind'],
                            durationMinutes=step['durationMinutes'], isRequired=step['isRequired'],
                            detail=step['detail'][language]) for step in oracle['steps']])


def pages(scenario, language, destination):
    """Offline HTML only. No server is started and no .invalid URL is requested."""
    destination.mkdir()
    source = scenario['pages']
    title = html.escape(source['articleTitle'][language])
    common = '<meta charset="utf-8"><meta name="viewport" content="width=device-width"><p>SYNTHETIC — no real account or effect</p>'
    article = common + f'<article><h1>{title}</h1><p>Camille Vernet · Cedar News</p>'
    article += ''.join('<p>' + html.escape(part.strip()) + '.</p>' for part in source['articleBody'][language].split('.') if part.strip())
    (destination / 'reading-corner.html').write_text(article + '</article>', encoding='utf-8')
    listing = common + '<h1>Cedar News</h1><h2>1 · Greenhouse seedlings</h2>'
    listing += f'<h2><a href="{html.escape(source["origin"] + source["articlePath"])}">2 · {title}</a></h2><h2>3 · Workshop maps</h2>'
    (destination / 'index.html').write_text(listing, encoding='utf-8')


def render_movie(tool, probe, timeline, destination, fps):
    concat = destination.with_suffix('.ffconcat')
    with concat.open('x', encoding='utf-8') as output:
        output.write('ffconcat version 1.0\n')
        for scene in timeline:
            path = scene['image'].replace("'", "'\\''")
            output.write(f"file '{path}'\nduration {scene['endSeconds'] - scene['startSeconds']}\n")
        output.write(f"file '{timeline[-1]['image']}'\n")
    subprocess.run([tool, '-hide_banner', '-loglevel', 'error', '-nostdin', '-n', '-threads', '1',
                    '-f', 'concat', '-safe', '0', '-i', str(concat), '-vf', f'fps={fps}',
                    '-t', str(timeline[-1]['endSeconds']), '-an', '-c:v', 'libx264',
                    '-threads', '1', '-preset', 'ultrafast', '-tune', 'stillimage', '-crf', '28',
                    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(destination)], check=True)
    receipt = json.loads(subprocess.check_output([probe, '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(destination)]))
    actual = float(receipt['format']['duration'])
    assert abs(actual - timeline[-1]['endSeconds']) <= 1 / fps
    assert not any(stream['codec_type'] == 'audio' for stream in receipt['streams'])
    assert destination.stat().st_size <= 512 * 1024 * 1024
    save_json(destination.with_suffix('.ffprobe.json'), receipt)
    return dict(path=str(destination), sha256=digest(destination), bytes=destination.stat().st_size,
                ffprobeDurationSeconds=actual, frameRate=fps, audioStreams=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', required=True, help='New output under ignored work/routine-fixture/. Never overwrites.')
    parser.add_argument('--languages', nargs='+', choices=['fr', 'en'], default=['fr', 'en'])
    parser.add_argument('--profiles', nargs='+', choices=['realistic', 'accelerated'], default=['realistic', 'accelerated'])
    parser.add_argument('--images-only', action='store_true', help='No movie; manifest explicitly records movies not generated.')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', args.run):
        parser.error('--run must be a filename-safe new identifier')
    tool, probe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not args.images_only and not (tool and probe):
        parser.error('Already-installed ffmpeg and ffprobe are required; nothing is downloaded')
    scenario, oracle = read_json(CORPUS / 'scenario.json'), read_json(CORPUS / 'expected-parsed.json')
    validate(scenario, oracle)
    os.umask(0o077)
    out = ROOT / 'work/routine-fixture' / args.run
    out.mkdir(parents=True, exist_ok=False)
    manifest = dict(schemaVersion=1, generator=VERSION, origin='synthetic', sourceType=scenario['sourceType'],
                    generatorSHA256=digest(Path(__file__)),
                    scenarioSHA256=digest(CORPUS / 'scenario.json'), oracleSHA256=digest(CORPUS / 'expected-parsed.json'),
                    sourceGitRevision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                    sourceGitDirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
                    createdAt=datetime.now(timezone.utc).isoformat(), output=str(out), timelines=[], movies=[],
                    stageStatus=dict(rendering='in-progress', nativeCapture='not-run', realOCR='not-run',
                                     realClassification='not-run', directOracleImport='not-run', runtimeEffects='not-run'),
                    disclosure='Drawn pixels. Source and oracle are separate inputs. No native UI, model, provider, account or real effects.')
    for language in dict.fromkeys(args.languages):
        images = out / language
        images.mkdir()
        thumbnails = []
        for scene in scenario['scenes']:
            image = draw_scene(scene, language, images / f'{scene["id"]}.png')
            image.thumbnail((195, 422))
            thumbnails.append(image)
        sheet = Image.new('RGB', (195 * 5, 422 * math.ceil(len(thumbnails) / 5)), '#e7e7e7')
        for index, image in enumerate(thumbnails):
            sheet.paste(image, ((index % 5) * 195, (index // 5) * 422))
        sheet.save(images / 'contact-sheet.png')
        pages(scenario, language, images / 'offline-news')
        save_json(out / f'oracle-draft-{language}.more-routine.json', portable(oracle, language))
        for profile in dict.fromkeys(args.profiles):
            timeline, cursor = [], 0
            for scene in scenario['scenes']:
                duration = scene['seconds'][profile]
                timeline.append(dict(sceneID=scene['id'], moment=scene['moment'], startSeconds=cursor,
                                     endSeconds=cursor + duration, image=str(images / f'{scene["id"]}.png'),
                                     imageSHA256=digest(images / f'{scene["id"]}.png'), negative=scene.get('negative')))
                cursor += duration
            name = f'{profile}-{language}'
            save_json(out / f'{name}.timeline.json', dict(profile=profile, language=language, durationSeconds=cursor, scenes=timeline))
            manifest['timelines'].append(dict(profile=profile, language=language, path=str(out / f'{name}.timeline.json'),
                                             sha256=digest(out / f'{name}.timeline.json')))
            if not args.images_only:
                print(f'Encoding SYNTHETIC {name}: {cursor}s, one worker, no audio.', flush=True)
                movie = render_movie(tool, probe, timeline, out / f'{name}.mp4', fps=5)
                manifest['movies'].append(dict(profile=profile, language=language, **movie))
                print(f'Finalized {name}: ffprobe={movie["ffprobeDurationSeconds"]}s, {movie["bytes"]} bytes.', flush=True)
    manifest['stageStatus']['rendering'] = 'images-only' if args.images_only else 'completed'
    save_json(out / 'manifest.json', manifest)
    print(f'Artifacts: {out}\nNo extraction, inference, import or routine execution has run.', flush=True)


if __name__ == '__main__':
    main()
