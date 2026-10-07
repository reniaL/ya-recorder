"""Linux/WSL: compile the SAME C encoder and validate it with an independent decoder.

Requires cc, ffprobe, ffmpeg. Accelerated synthetic input is NOT Android/device evidence.
No PCM/WAV intermediate is written; decoded PCM is checked incrementally in memory.
"""
import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "android/mp3-encoder/src/main/cpp"
ARCHIVE = ROOT / "android/mp3-encoder/third_party/lame/lame-4.0.tar.gz"
SHA256 = "3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb"
SOURCES = "bitstream encoder fft gain_analysis id3tag lame newmdct presets psymodel quantize quantize_pvt reservoir set_get tables takehiro util vbrquantize version mpglib_interface".split()


def run(args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout


def check_decode(file, expected_samples):
    metadata = json.loads(run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", file]))
    track = metadata["streams"][0]
    assert track["codec_name"] == "mp3" and track["sample_rate"] == "44100" and track["channels"] == 1, track
    process = subprocess.Popen(["ffmpeg", "-v", "error", "-xerror", "-i", str(file), "-f", "s16le", "-"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    count = 0
    cross = energy_in = energy_out = 0.0
    min_rms, max_rms = float("inf"), 0.0
    while data := process.stdout.read(44100 * 2):
        pcm = array.array("h")
        pcm.frombytes(data)
        if sys.byteorder != "little":
            pcm.byteswap()
        energy = 0.0
        for sample in pcm:
            reference = 12000 * math.sin(2 * math.pi * 440 * count / 44100)
            cross += sample * reference
            energy_in += reference * reference
            energy_out += sample * sample
            energy += sample * sample
            count += 1
        rms = math.sqrt(energy / len(pcm))
        # Exclude tiny final tail from the one-second continuity measurement.
        if len(pcm) == 44100:
            min_rms, max_rms = min(min_rms, rms), max(max_rms, rms)
    errors = process.stderr.read().decode()
    assert process.wait() == 0 and not errors, errors
    assert count == expected_samples, (count, expected_samples)
    correlation = cross / math.sqrt(energy_in * energy_out) if energy_in * energy_out > 0 else None
    if expected_samples >= 44100:
        assert correlation is not None and correlation > 0.98, correlation
    if min_rms != float("inf"):
        assert min_rms > 7000 and max_rms < 9500, (min_rms, max_rms)
    return {"decodedSamples": count, "correlation": correlation,
            "minOneSecondRms": None if min_rms == float("inf") else min_rms,
            "maxOneSecondRms": max_rms, "ffprobeDuration": track["duration"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--long-seconds", type=int, default=3600)
    args = parser.parse_args()
    if not 1 <= args.long_seconds <= 7200:
        parser.error("--long-seconds must be 1..7200")
    for tool in ("cc", "ffprobe", "ffmpeg"):
        if not shutil.which(tool):
            parser.error(f"missing {tool}; run on Linux or WSL")
    assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() == SHA256
    build = ROOT / "build/mp3-prototype/host"
    build.mkdir(parents=True, exist_ok=True)
    with tarfile.open(ARCHIVE) as archive:
        # The pinned archive is local and verified; reject links/path traversal.
        members = archive.getmembers()
        for member in members:
            target = (build / member.name).resolve()
            if not (member.isfile() or member.isdir()) or build.resolve() not in target.parents:
                raise ValueError(f"unsafe archive entry: {member.name}")
        archive.extractall(build, members=members)
    lame = build / "lame-4.0"
    source = (lame / "libmp3lame/VbrTag.c").read_text()
    assert "~(-1 << (n))" in source, "LAME VBR tag patch no longer applies"
    (build / "VbrTag_project.c").write_text(source.replace("~(-1 << (n))", "~(~0u << (n))"))
    (build / "config.h").write_bytes((CPP / "lame_config.h.in").read_bytes())
    executable = build / "encoder_smoke"
    run(["cc", "-O2", "-DHAVE_CONFIG_H", "-I", build, "-I", lame, "-I", lame / "include",
         "-I", lame / "libmp3lame", "-I", CPP, *(lame / f"libmp3lame/{name}.c" for name in SOURCES),
         build / "VbrTag_project.c", CPP / "stream_encoder.c", ROOT / "tools/mp3-prototype/encoder_smoke.c", "-lm", "-o", executable])
    results = []
    # Sub-frame and partial final chunks exercise padding/gapless tag handling.
    for samples, bitrate, quality in [(1, 64, 5), (44100 * 10 + 37, 64, 5),
                                      (44100 * 10 + 37, 96, 2), (44100 * args.long_seconds, 64, 5)]:
        output = build / f"tone-{samples}-{bitrate}-{quality}.mp3"
        result = json.loads(run([executable, output, samples, bitrate, quality]))
        result.update({"bitrateKbps": bitrate, "quality": quality,
                       "input": "accelerated synthetic tone on Linux host", "fileBytes": output.stat().st_size})
        result.update(check_decode(output, samples))
        results.append(result)
        print(json.dumps(result), flush=True)
    (build / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
