"""Linux/WSL: run the actual Kotlin MP3 backend through JNI and independently decode.

Requires an Android debug Kotlin compilation, JDK 17+, cc and FFmpeg.
This is synthetic desktop validation, never Android microphone/device evidence.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stdlib-jar", required=True, type=Path)
    args = parser.parse_args()
    if not args.stdlib_jar.is_file():
        parser.error("Kotlin stdlib jar does not exist")
    # Reuse checksum, source extraction, project patch and independent decoder.
    source = ROOT / "tools/mp3-prototype/host_smoke.py"
    spec = importlib.util.spec_from_file_location("encoder_smoke", source)
    smoke = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(smoke)
    subprocess.run([sys.executable, str(source), "--long-seconds", "10"], check=True, capture_output=True)
    upstream_build = ROOT / "build/mp3-prototype/host"
    build = ROOT / "build/rec07-mp3/host"
    build.mkdir(parents=True, exist_ok=True)
    java_home = Path(smoke.run(["readlink", "-f", "/usr/bin/javac"]).strip()).parents[1]
    lame = upstream_build / "lame-4.0"
    cpp = ROOT / "android/mp3-encoder/src/main/cpp"
    library = build / "librec07_lame.so"
    smoke.run(["cc", "-shared", "-fPIC", "-O2", "-fvisibility=hidden", "-DHAVE_CONFIG_H",
               "-I", upstream_build, "-I", lame, "-I", lame / "include", "-I", lame / "libmp3lame",
               "-I", java_home / "include", "-I", java_home / "include/linux", "-I", cpp,
               *(lame / f"libmp3lame/{name}.c" for name in smoke.SOURCES),
               upstream_build / "VbrTag_project.c", cpp / "stream_encoder.c", cpp / "lame_jni.c",
               "-lm", "-o", library])
    classpath = ":".join(str(path) for path in [
        ROOT / "build/app/tmp/kotlin-classes/debug",
        ROOT / "build/mp3-encoder/tmp/kotlin-classes/debug", args.stdlib_jar,
    ])
    smoke.run(["javac", "-cp", classpath, "-d", build, ROOT / "tools/mp3-backend/HostMp3Lifecycle.java"])
    output = build / "recording-host.mp3.part"
    result = json.loads(smoke.run(["java", f"-Djava.library.path={build}", "-cp", f"{build}:{classpath}",
                                   "io.github.renial.ya_recorder.HostMp3Lifecycle", output]))
    result.update(smoke.check_decode(output, result["samples"]))
    result["evidence"] = "production Kotlin backend + real Linux JNI; accelerated synthetic PCM, not Android"
    (build / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        raise
