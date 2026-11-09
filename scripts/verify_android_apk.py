#!/usr/bin/env python3
"""Release APK guardrails: ABI, native cores and asset isolation.

Only APK ZIP structure is checked; device execution still needs smoke testing.
"""
import argparse
import sys
import zipfile
from pathlib import Path

CORE_NAMES = ("libxray.so", "libsingbox.so", "libawg.so")
RULE_NAMES = ("geoip.dat", "geosite.dat")
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")


def check_apk(path: Path, abi: str, flavor: str) -> list[str]:
    errors: list[str] = []
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        for other in ABIS:
            if other == abi:
                continue
            native = [n for n in names if n.startswith(f"lib/{other}/")]
            if native:
                errors.append(f"unexpected ABI {other} ({len(native)} native files)")
        if f"lib/{abi}/libflutter.so" not in names:
            errors.append(f"missing Flutter runtime for {abi}")
        if flavor == "shadow":
            for name in CORE_NAMES:
                item = f"lib/{abi}/{name}"
                if item not in names:
                    errors.append(f"missing {item}")
                    continue
                with archive.open(item) as stream:
                    if stream.read(4) != b"\x7fELF":
                        errors.append(f"bad ELF magic: {item}")
            for name in RULE_NAMES:
                item = f"assets/preload/{name}"
                if item not in names:
                    errors.append(f"missing {item}")
                elif archive.getinfo(item).file_size < 1024:
                    errors.append(f"too small: {item}")
        else:
            for name in CORE_NAMES:
                if f"lib/{abi}/{name}" in names:
                    errors.append(f"original must not include {name}")
            if any(n.startswith("assets/preload/") for n in names):
                errors.append("original must not contain shadow preload assets")
        if any(n.startswith("assets/preload/") and n.endswith(".so") for n in names):
            errors.append("ELF duplicate in preload assets")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("apk", type=Path)
    ap.add_argument("--abi", required=True, choices=ABIS)
    ap.add_argument("--flavor", required=True, choices=("original", "shadow"))
    args = ap.parse_args()
    if not args.apk.is_file():
        ap.error(f"Missing APK: {args.apk}")
    try:
        errors = check_apk(args.apk, args.abi, args.flavor)
    except (OSError, zipfile.BadZipFile) as error:
        print(f"INVALID APK: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"PASS: {args.apk} ({args.flavor}, {args.abi})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
