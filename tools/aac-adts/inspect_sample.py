"""Verify a device sample with ffprobe and a full ffmpeg decode (no conversion)."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess


def inspect(sample, ffprobe, ffmpeg):
    result = subprocess.run([ffprobe, "-v", "error", "-show_format", "-show_streams",
                             "-of", "json", str(sample)], check=True, capture_output=True, text=True)
    metadata = json.loads(result.stdout)
    streams = metadata["streams"]
    if metadata["format"]["format_name"] != "aac" or len(streams) != 1:
        raise ValueError("Expected an ADTS AAC file with one audio stream")
    audio = streams[0]
    if audio["codec_name"] != "aac" or audio["profile"] != "LC" or int(audio["sample_rate"]) != 44100:
        raise ValueError("Expected AAC-LC at 44100 Hz")
    # -xerror makes decode errors fail rather than producing a partial success.
    subprocess.run([ffmpeg, "-v", "error", "-xerror", "-i", str(sample),
                    "-f", "null", "-"], check=True)
    return {"sample": str(sample), "ffprobe": metadata, "fullFfmpegDecode": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample", type=Path)
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe"))
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.ffprobe or not args.ffmpeg:
        parser.error("Pass --ffprobe and --ffmpeg paths, or put them on PATH")
    report = json.dumps(inspect(args.sample, args.ffprobe, args.ffmpeg), indent=2)
    if args.output:
        args.output.write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
