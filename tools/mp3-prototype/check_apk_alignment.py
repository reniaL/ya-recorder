"""Check every APK native library's ELF LOAD and uncompressed ZIP alignment."""
import argparse
import json
from pathlib import Path
import struct
import zipfile


def load_alignments(data):
    if data[:4] != b"\x7fELF" or data[5] != 1:
        raise ValueError("expected little-endian ELF")
    if data[4] == 2:
        offset = struct.unpack_from("<Q", data, 32)[0]
        size, count = struct.unpack_from("<HH", data, 54)
        alignment_offset, alignment_format = 48, "<Q"
    elif data[4] == 1:
        offset = struct.unpack_from("<I", data, 28)[0]
        size, count = struct.unpack_from("<HH", data, 42)
        alignment_offset, alignment_format = 28, "<I"
    else:
        raise ValueError("unknown ELF class")
    return [struct.unpack_from(alignment_format, data, offset + i * size + alignment_offset)[0]
            for i in range(count) if struct.unpack_from("<I", data, offset + i * size)[0] == 1]


def check(apk):
    rows = []
    with zipfile.ZipFile(apk) as archive, open(apk, "rb") as file:
        for info in archive.infolist():
            if not (info.filename.startswith("lib/") and info.filename.endswith(".so")):
                continue
            alignments = load_alignments(archive.read(info))
            file.seek(info.header_offset)
            header = file.read(30)
            name_size, extra_size = struct.unpack_from("<HH", header, 26)
            data_offset = info.header_offset + 30 + name_size + extra_size
            passed = bool(alignments) and all(a >= 16384 and a % 16384 == 0 for a in alignments)
            if info.compress_type == zipfile.ZIP_STORED:
                passed = passed and data_offset % 16384 == 0
            rows.append({"library": info.filename, "loadAlignments": alignments,
                         "compressed": info.compress_type != zipfile.ZIP_STORED,
                         "zipDataOffset": data_offset, "passed": passed})
    if not rows:
        raise ValueError("APK has no native libraries")
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    rows = check(args.apk)
    report = json.dumps(rows, indent=2)
    print(report)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report + "\n", encoding="utf-8")
    raise SystemExit(0 if all(row["passed"] for row in rows) else 1)
