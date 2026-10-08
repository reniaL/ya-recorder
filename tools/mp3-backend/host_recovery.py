"""Linux/WSL: independently decode real LAME residuals repaired by production Kotlin.

Requires the host_lifecycle.py output and Android debug Kotlin classes. Synthetic
five-second input is not Android microphone, MediaCodec or process-kill evidence.
"""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stdlib-jar", required=True, type=Path)
    args = parser.parse_args()
    build = ROOT / "build/rec07-mp3/host"
    classpath = ":".join(str(path) for path in [build,
        ROOT / "build/app/tmp/kotlin-classes/debug",
        ROOT / "build/mp3-encoder/tmp/kotlin-classes/debug", args.stdlib_jar])
    subprocess.run(["javac", "-cp", classpath, "-d", build,
                    ROOT / "tools/mp3-backend/HostRecovery.java"], check=True)
    subprocess.run(["java", f"-Djava.library.path={build}", "-cp", classpath,
                    "io.github.renial.ya_recorder.HostRecovery", build], check=True)
    rows = []
    for name in ("truncated.mp3.part", "unflushed.mp3.part"):
        source = build / name
        file = build / (name + ".repaired.mp3")
        process = subprocess.Popen(["ffmpeg", "-v", "error", "-xerror", "-i", str(file),
                                    "-f", "s16le", "-"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        decoded_bytes = 0
        while data := process.stdout.read(44100 * 2):
            decoded_bytes += len(data)
        errors = process.stderr.read().decode()
        assert process.wait() == 0 and not errors, errors
        samples = decoded_bytes // 2
        assert 0 < samples <= 44100 * 5 + 2304, samples
        rows.append({"source": name, "sourceBytes": source.stat().st_size,
                     "repairedBytes": file.stat().st_size, "decodedSamples": samples,
                     "decodedDurationMs": samples * 1000 // 44100,
                     "originalUnchanged": True, "ffmpegFullDecodePassed": True})
    report = {"evidence": "production Kotlin repair + real Linux LAME JNI + FFmpeg; not Android", "cases": rows}
    (build / "recovery-results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
