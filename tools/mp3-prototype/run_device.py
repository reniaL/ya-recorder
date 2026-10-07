"""Run an isolated prototype on an authorized Android device and collect evidence.

Example: python tools/mp3-prototype/run_device.py --seconds 3600 --source microphone
Use --apk to install/update ONLY the prototype package. No normal app data is touched.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "io.github.renial.ya_recorder.mp3prototype"


def adb_path():
    if shutil.which("adb"):
        return shutil.which("adb")
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    properties = ROOT / "android/local.properties"
    if not sdk and properties.exists():
        for line in properties.read_text().splitlines():
            if line.startswith("sdk.dir="):
                sdk = line.split("=", 1)[1].replace("\\\\", "\\").replace("\\:", ":")
    if sdk:
        return str(Path(sdk) / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb"))
    return "adb"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default=adb_path())
    parser.add_argument("--serial")
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--seconds", type=int, default=10)
    parser.add_argument("--source", choices=("microphone", "tone"), default="microphone")
    parser.add_argument("--bitrate", type=int, choices=(64, 96), default=64)
    parser.add_argument("--quality", type=int, choices=(2, 5), default=5)
    parser.add_argument("--encoder-delay-ms", type=int, default=0)
    parser.add_argument("--expect-overflow", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 7200 or not 0 <= args.encoder_delay_ms <= 500:
        parser.error("seconds must be 1..7200 and encoder delay 0..500")
    prefix = [args.adb] + (["-s", args.serial] if args.serial else [])

    def adb(*command, optional=False, binary=False):
        result = subprocess.run(prefix + list(command), capture_output=True, timeout=60)
        if result.returncode and not optional:
            raise RuntimeError(result.stderr.decode(errors="replace") or result.stdout.decode(errors="replace"))
        if result.returncode:
            return None
        return result.stdout if binary else result.stdout.decode(errors="replace").strip()

    # Fail before installing/launching when there is no selected device.
    adb("get-state")
    if args.apk:
        adb("install", "-r", str(args.apk.resolve()))
    adb("shell", "pm", "grant", PACKAGE, "android.permission.RECORD_AUDIO")
    api = int(adb("shell", "getprop", "ro.build.version.sdk"))
    if api >= 33:
        adb("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
    run_id = str(uuid.uuid4())
    destination = ROOT / "build/mp3-prototype/device" / run_id
    destination.mkdir(parents=True)
    metadata = {"startedAtUtc": datetime.now(timezone.utc).isoformat(), "runId": run_id,
                "serial": adb("get-serialno"), "model": adb("shell", "getprop", "ro.product.model"),
                "sdk": api, "pageSize": adb("shell", "getconf", "PAGESIZE"),
                "emulator": adb("shell", "getprop", "ro.kernel.qemu"), "arguments": vars(args).copy()}
    metadata["arguments"]["apk"] = str(args.apk) if args.apk else None
    (destination / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (destination / "battery-before.txt").write_text(adb("shell", "dumpsys", "battery"), encoding="utf-8")
    response = adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.PrototypeActivity",
                   "--ez", "autorun", "true", "--es", "runId", run_id,
                   "--ei", "seconds", str(args.seconds), "--ez", "tone", str(args.source == "tone").lower(),
                   "--ei", "bitrate", str(args.bitrate), "--ei", "quality", str(args.quality),
                   "--ei", "encoderDelayMs", str(args.encoder_delay_ms))
    (destination / "launch.txt").write_text(response, encoding="utf-8")
    deadline = time.monotonic() + args.seconds + 180
    result = None
    last_sample = None
    print(f"Run {run_id}; evidence: {destination}", flush=True)
    try:
        with (destination / "progress.jsonl").open("w", encoding="utf-8") as progress:
            while time.monotonic() < deadline:
                text = adb("exec-out", "run-as", PACKAGE, "cat", f"files/runs/{run_id}/result.json", optional=True)
                if text:
                    result = json.loads(text)
                    break
                text = adb("exec-out", "run-as", PACKAGE, "cat", f"files/runs/{run_id}/progress.json", optional=True)
                if text:
                    row = json.loads(text)
                    if row["acceptedSamples"] != last_sample:
                        progress.write(json.dumps(row) + "\n")
                        progress.flush()
                        last_sample = row["acceptedSamples"]
                        print(f"{last_sample / 44100:.1f}s, PSS {row['pssKb']} KB, queue high {row['queueHighWater']}", flush=True)
                time.sleep(5)
        if result is None:
            raise RuntimeError("No completed report before timeout; inspect launch/logcat. This is not a pass.")
        (destination / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        (destination / "battery-after.txt").write_text(adb("shell", "dumpsys", "battery"), encoding="utf-8")
        filename = result.get("output")
        if filename in ("audio.mp3", "audio.mp3.part"):
            data = adb("exec-out", "run-as", PACKAGE, "cat", f"files/runs/{run_id}/{filename}", optional=True, binary=True)
            if data:
                (destination / filename).write_bytes(data)
        print(json.dumps(result, indent=2), flush=True)
        if args.expect_overflow:
            if result["status"] != "failed" or "PCM queue overflow" not in result.get("error", ""):
                raise RuntimeError("Expected an explicit overflow failure")
        else:
            if result["status"] != "passed" or result["acceptedSamples"] != args.seconds * 44100:
                raise RuntimeError("Recording failed or stopped short of the requested duration")
            if result["encodedSamples"] != result["acceptedSamples"] or result["queueHighWater"] > 16:
                raise RuntimeError("Samples were lost or the queue exceeded its bound")
        print("Evidence collected. Listen to microphone output; review memory/CPU/battery and background behavior.")
    except BaseException:
        # Ask the activity's existing service to finish. Never force-stop/delete evidence.
        adb("shell", "am", "start", "-n", PACKAGE + "/.PrototypeActivity", "--ez", "stoprun", "true", optional=True)
        raise


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Device validation did not pass: {error}") from error
