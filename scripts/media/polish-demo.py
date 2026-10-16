#!/usr/bin/env python3
"""Calibrated overlay edit for MORE-five-minute-v3. Media stays outside Git.

Requires macOS, Xcode command-line Swift, ffmpeg/ffprobe, Pillow and numpy.
No network services, uploads, generative frames, retiming or audio processing.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SIZE = (1920, 1080)
FPS = 30
SOURCE_HASH = "07dde8b6e714352c2dadd85aac1b4086ef1f45992690579e0add3302210f5f55"
PHONE = (730, 44, 1191, 1037)
SCREEN = (743, 120, 1179, 1010)
# Only editorial cuts, not native permission sheets or the natural reel scroll.
CUTS = (46.0, 57.0, 76.0, 152.0, 157.0, 175.0)
MOON_START = 286.0
DUO_START = 290.0
SOURCE_MOON = (778, 505, 908, 640)
TARGET_MOON = (506, 231, 825, 565)


def run(*args):
    return subprocess.check_output(list(map(str, args)))


def probe(path):
    return json.loads(run("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path))


def audio_packets(path):
    return json.loads(run("ffprobe", "-v", "error", "-select_streams", "a:0", "-show_packets",
        "-show_data_hash", "sha256", "-show_entries",
        "packet=pts,dts,duration,size,data_hash,side_data_list", "-of", "json", path))["packets"]


def frame_at(path, seconds):
    data = run("ffmpeg", "-v", "error", "-ss", seconds, "-i", path,
        "-frames:v", 1, "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1")
    return Image.frombytes("RGB", SIZE, data)


def smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3 - 2 * value)


def moon_layer(frame, box, threshold):
    """Keep the actual filmed dots, rejecting the dark sky around the crescent."""
    crop = frame.crop(box).convert("RGBA")
    pixels = np.array(crop)
    level = pixels[:, :, :3].max(axis=2).astype(float)
    alpha = np.clip((level - threshold) / 14, 0, 1)
    # Connect the crescent's dense dots, then reject isolated stars in the crop.
    connected = Image.fromarray(np.where(alpha > 0.03, 255, 0).astype("uint8"))
    connected = connected.filter(ImageFilter.MaxFilter(17))
    seed = (crop.width // 5, crop.height // 2)
    assert connected.getpixel(seed) == 255, "Expected a seed inside the filmed crescent"
    ImageDraw.floodfill(connected, seed, 128, thresh=0)
    alpha *= np.array(connected) == 128
    pixels[:, :, 3] = np.round(alpha * 255).astype("uint8")
    return Image.fromarray(pixels)


class Edit:
    def __init__(self, source, work):
        exporter = work / "export-brand"
        subprocess.run(["xcrun", "swiftc", str(ROOT / "Sources/MorningCore/MorningBrand.swift"),
            str(ROOT / "scripts/media/ExportDemoBrand.swift"), "-o", str(exporter)], check=True)
        subprocess.run([str(exporter), str(work)], check=True)
        self.logos = {mode: Image.open(work / f"wordmark-{mode}.png").convert("RGBA").resize(
            (190, 50), Image.Resampling.LANCZOS) for mode in ("day", "night")}
        icon_dir = ROOT / "Resources/Assets.xcassets/AppIcon.appiconset"
        self.icons = {}
        for mode, filename in (("day", "AppIcon.png"), ("night", "AppIcon-Dark.png")):
            icon = Image.open(icon_dir / filename).convert("RGBA").resize((52, 52), Image.Resampling.LANCZOS)
            mask = Image.new("L", (208, 208))
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, 207, 207), radius=46, fill=255)
            icon.putalpha(mask.resize((52, 52), Image.Resampling.LANCZOS))
            self.icons[mode] = icon
        self.phone_mask = Image.new("L", SIZE)
        ImageDraw.Draw(self.phone_mask).rounded_rectangle(PHONE, radius=82, fill=255)
        self.night = Image.new("RGB", SIZE, "#0C1226")
        self.black = Image.new("RGB", SIZE)
        self.night_still = frame_at(source, MOON_START)
        self.duo_still = frame_at(source, DUO_START + 1)
        self.small_moon = moon_layer(self.night_still, SOURCE_MOON, 40)
        self.large_moon = moon_layer(self.duo_still, TARGET_MOON, 75)
        self.cut_frames = {round(t * FPS) for t in CUTS}
        self.previous_screen = None
        self.outgoing = None
        self.cut_age = 99

    def brand(self, frame, time):
        # Sample the existing paper so the patch follows the film's original fades.
        ImageDraw.Draw(frame).rectangle((50, 64, 345, 119), fill=frame.getpixel((400, 70)))
        frame.paste(self.icons["day"], (60, 65), self.icons["day"])
        frame.paste(self.logos["day"], (128, 66), self.logos["day"])
        night_mix = smooth((time - 240) / 7)
        if night_mix:
            night = self.night.copy()
            night.paste(frame, (0, 0), self.phone_mask)
            # Preserve the original caption, including its exact timing and fades.
            caption = np.array(frame.crop((50, 125, 700, 165))).mean(axis=2)
            paper = float(np.mean(frame.getpixel((700, 140))))
            alpha = np.clip((paper - caption) / max(1, paper - 65), 0, 1)
            mask = Image.fromarray(np.round(alpha * 255).astype("uint8"))
            night.paste(Image.new("RGB", mask.size, "#F3ECDD"), (50, 125), mask)
            night.paste(self.icons["night"], (60, 65), self.icons["night"])
            night.paste(self.logos["night"], (128, 66), self.logos["night"])
            frame = Image.blend(frame, night, night_mix)
        return frame

    def ending(self, time):
        if time < 287.2:
            # Black out everything except the source moon; no crescent disappears.
            frame = Image.blend(self.brand(self.night_still.copy(), MOON_START), self.black,
                smooth((time - MOON_START) / 1.2))
            frame.paste(self.small_moon, SOURCE_MOON[:2], self.small_moon)
            return frame
        if time < DUO_START:
            progress = smooth((time - 287.35) / 2.15)
            x = SOURCE_MOON[0] + (TARGET_MOON[0] - SOURCE_MOON[0]) * progress
            y = SOURCE_MOON[1] + (TARGET_MOON[1] - SOURCE_MOON[1]) * progress - 35 * math.sin(progress * math.pi)
            width = round(self.small_moon.width + (self.large_moon.width - self.small_moon.width) * progress)
            height = round(self.small_moon.height + (self.large_moon.height - self.small_moon.height) * progress)
            small = self.small_moon.resize((width, height), Image.Resampling.LANCZOS)
            large = self.large_moon.resize((width, height), Image.Resampling.LANCZOS)
            moon = Image.blend(small, large, smooth((progress - 0.35) / 0.65))
            frame = self.black.copy()
            frame.paste(moon, (round(x), round(y)), moon)
            return frame
        reveal = smooth((time - DUO_START) / 1.0)
        frame = Image.blend(self.black, self.duo_still, reveal)
        frame.paste(self.large_moon, TARGET_MOON[:2], self.large_moon)
        return frame

    def apply(self, frame, number):
        time = number / FPS
        if number in self.cut_frames:
            self.outgoing = self.previous_screen
            self.cut_age = 0
        incoming = frame.crop(SCREEN)
        if self.outgoing is not None and self.cut_age < 7:
            # A short dissolve inside the display leaves the bezel and timeline fixed.
            frame.paste(Image.blend(self.outgoing, incoming, smooth((self.cut_age + 1) / 7)), SCREEN[:2])
            self.cut_age += 1
        self.previous_screen = incoming
        if MOON_START <= time < DUO_START + 1.0:
            return self.ending(time)
        if time < MOON_START:
            return self.brand(frame, time)
        # A small identity in the existing black margin, without covering the Duo.
        fade = smooth((time - 291.0) / 0.5) * (1 - smooth((time - 297.5) / 2.5))
        logo = self.logos["night"].copy()
        logo.putalpha(logo.getchannel("A").point(lambda a: round(a * fade)))
        frame.paste(logo, (60, 25), logo)
        return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--start", type=float, default=0)
    parser.add_argument("--end", type=float, default=300)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output.exists() or source == output:
        parser.error("Output must be a new file; the original is never overwritten.")
    if not 0 <= args.start < args.end <= 300:
        parser.error("Expected a frame-aligned range inside the original 300 seconds.")
    if any(abs(t * FPS - round(t * FPS)) > 1e-5 for t in (args.start, args.end)):
        parser.error("Range endpoints must align with 30fps frames.")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != SOURCE_HASH:
        parser.error("This edit is calibrated for the supplied MORE-five-minute-v3.mp4 (SHA-256 mismatch).")
    metadata = probe(source)
    video = next(s for s in metadata["streams"] if s["codec_type"] == "video")
    assert (video["width"], video["height"], video["r_frame_rate"], video["nb_frames"]) == (1920, 1080, "30/1", "9000")
    duration = args.end - args.start
    first, last = round(args.start * FPS), round(args.end * FPS)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".more-demo-", dir=output.parent) as directory:
        work = Path(directory)
        edit = Edit(source, work)
        temporary = work / "render.mp4"
        decode = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(args.start), "-i", str(source),
            "-t", str(duration), "-an", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], stdout=subprocess.PIPE)
        audio_seek = ["-ss", str(args.start)] if args.start else []
        encode = subprocess.Popen(["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
            "-s", "1920x1080", "-r", "30", "-i", "pipe:0", *audio_seek, "-i", str(source),
            "-map", "0:v:0", "-map", "1:a:0", "-t", str(duration), "-c:v", "libx264", "-preset", "fast",
            "-crf", "17", "-threads", "4", "-pix_fmt", "yuv420p", "-colorspace", "bt709",
            "-color_primaries", "bt709", "-color_trc", "bt709", "-c:a", "copy", "-movflags", "+faststart",
            str(temporary)], stdin=subprocess.PIPE)
        try:
            for number in range(first, last):
                data = decode.stdout.read(SIZE[0] * SIZE[1] * 3)
                if len(data) != SIZE[0] * SIZE[1] * 3:
                    raise RuntimeError(f"Incomplete source frame {number}")
                frame = edit.apply(Image.frombytes("RGB", SIZE, data), number)
                encode.stdin.write(frame.tobytes())
                if number % 900 == 0:
                    print(f"Rendered {number / FPS:.0f}s / {args.end:.0f}s", flush=True)
            encode.stdin.close()
            decode.stdout.close()
            if decode.wait() or encode.wait():
                raise RuntimeError("ffmpeg did not complete successfully")
        finally:
            for process in (decode, encode):
                if process.poll() is None:
                    process.terminate()
                    process.wait()
        result = probe(temporary)
        rendered_video = next(s for s in result["streams"] if s["codec_type"] == "video")
        assert int(rendered_video["nb_frames"]) == last - first
        assert abs(float(rendered_video["duration"]) - duration) < 0.001
        if first == 0 and last == 9000:
            assert abs(float(result["format"]["duration"]) - duration) < 0.001
        report = {"source_sha256": digest, "frames": last - first, "duration": duration,
            "resolution": list(SIZE), "fps": FPS, "range": [args.start, args.end]}
        if first == 0 and last == 9000:
            before, after = audio_packets(source), audio_packets(temporary)
            assert before == after, "Audio packet bytes or timestamps changed"
            report["audio_packets_identical"] = len(before)
        temporary.rename(output)
        output.with_suffix(".verification.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
