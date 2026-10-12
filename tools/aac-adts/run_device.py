"""Build an isolated debug APK, run the foreground probe and export evidence."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "io.github.renial.ya_recorder.aacprobe"
ACTIVITY = "io.github.renial.ya_recorder.AacAdtsProbeActivity"
OUTPUT = ROOT / "build" / "aac-adts-probe"


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default=shutil.which("adb"))
    parser.add_argument("--flutter", default=shutil.which("flutter"))
    parser.add_argument("--serial")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--export-only", action="store_true", help="Export the report again after manual listening")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    apk = OUTPUT / "aac-adts-probe-debug.apk"
    if not args.skip_build and not args.export_only:
        if not args.flutter:
            parser.error("Flutter not found; pass --flutter")
        run([args.flutter, "build", "apk", "--debug", "--target", "tools/aac-adts/probe.dart",
             "--dart-define=AAC_PROBE_AUTORUN=true", "-PaacAdtsProbe=true"], cwd=ROOT)
        metadata = json.loads((ROOT / "build/app/outputs/apk/debug/output-metadata.json").read_text(encoding="utf-8"))
        if metadata["applicationId"] != PACKAGE:
            raise SystemExit("Probe build did not produce the isolated application ID")
        shutil.copy2(ROOT / "build/app/outputs/flutter-apk/app-debug.apk", apk)
    if args.build_only:
        print(f"Probe APK: {apk}")
        return
    if not args.adb:
        parser.error("adb not found; pass --adb")
    devices = run([args.adb, "devices"], capture_output=True, text=True).stdout
    serials = [line.split()[0] for line in devices.splitlines()[1:]
               if len(line.split()) >= 2 and line.split()[1] == "device"]
    serial = args.serial
    if serial is None:
        if len(serials) != 1:
            parser.error("Connect one authorized Android device, or select --serial")
        serial = serials[0]
    elif serial not in serials:
        parser.error("Selected device is not connected/authorized")
    adb = [args.adb, "-s", serial]
    if not args.export_only:
        run(adb + ["install", "-r", str(apk)])
        run(adb + ["shell", "pm", "grant", PACKAGE, "android.permission.RECORD_AUDIO"])
        run(adb + ["shell", "am", "force-stop", PACKAGE])
        run(adb + ["shell", "run-as", PACKAGE, "rm", "-f", "files/aac-adts-probe/last-report.json"])
        print("Keep the page foreground. Speak 1-4, pause for 2 seconds, then speak 5-8.", flush=True)
        run(adb + ["shell", "am", "start", "-n", f"{PACKAGE}/{ACTIVITY}"])
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        fetched = subprocess.run(adb + ["exec-out", "run-as", PACKAGE, "cat",
                                       "files/aac-adts-probe/last-report.json"], capture_output=True)
        if fetched.returncode == 0:
            try:
                report = json.loads(fetched.stdout)
                break
            except json.JSONDecodeError:
                pass  # The tiny report may still be writing.
        time.sleep(1)
    else:
        raise SystemExit("No report within 90 seconds. Check the probe page and device log.")
    (OUTPUT / "device-report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    if "filePath" in report:
        filename = Path(report["filePath"]).name
        if not re.fullmatch(r"sample-\d+\.aac", filename):
            raise SystemExit("Unexpected probe sample filename")
        with (OUTPUT / filename).open("wb") as sample:
            run(adb + ["exec-out", "run-as", PACKAGE, "cat", f"files/aac-adts-probe/{filename}"], stdout=sample)
    print(f"Exported device evidence: {OUTPUT}")
    print("Listening/actual seek accuracy remains manual; export the updated report after confirming on the page.")
    if not report.get("automatedChecksPassed"):
        raise SystemExit("Device automatic checks failed; see device-report.json")


if __name__ == "__main__":
    main()
