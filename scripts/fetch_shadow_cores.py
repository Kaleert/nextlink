#!/usr/bin/env python3
"""Fetch pinned Android arm64 Shadow cores from public upstream releases.

sing-box/AWG are authenticated by the manifest's SHA-256 and byte length.
Xray is pinned to a release tag, but not a cryptographic digest. For stricter
reproducibility provide NEXTLINK_XRAY_SHA256 (ZIP hash) as CI env/variable.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import urllib.error
import urllib.request
import zipfile
import time

ABI = 'arm64-v8a'
TAG = os.environ.get('NEXTLINK_CORES_TAG', 'cores-v1')
XRAY_VERSION = os.environ.get('NEXTLINK_XRAY_VERSION', 'v26.10.31')
BASE = f'https://github.com/Kaleert/nextlink-cores/releases/download/{TAG}/'
DEST = Path('dist/shadow/android') / ABI
RULE_DEST = Path('dist/shadow')


def fetch(url: str, max_bytes: int = 100_000_000, min_bytes: int = 1024) -> bytes:
    error = None
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'Nextlink-CI/1.0', 'Accept': 'application/octet-stream'})
            with urllib.request.urlopen(request, timeout=65) as response:
                data = response.read(max_bytes + 1)
            if len(data) > max_bytes:
                raise ValueError(f'Download too large: {url}')
            if len(data) < min_bytes:
                raise ValueError(f'Download too small: {url}')
            return data
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            error = exc
            if attempt < 2:
                time.sleep(2 ** (attempt + 1))
    raise RuntimeError(f'Failed downloading {url}: {error}')


def elf_arm64(data: bytes, name: str) -> None:
    if len(data) < 1024 or data[:4] != b'\x7fELF':
        raise ValueError(f'{name}: not ELF')
    if data[4] != 2 or data[5] != 1 or struct.unpack_from('<H', data, 18)[0] != 183:
        raise ValueError(f'{name}: expected 64-bit little-endian AArch64 ELF')


def manifest_core(manifest_name: str, target: str) -> None:
    payload = json.loads(fetch(BASE + manifest_name, max_bytes=1_000_000, min_bytes=2))
    files = payload['files']
    entry = files[ABI]
    filename = entry['file']
    if not isinstance(filename, str) or '/' in filename or '\\' in filename or filename in ('.', '..'):
        raise ValueError('Unsafe manifest path')
    expected_hash, expected_size = entry['sha256'], entry['size']
    if not isinstance(expected_size, int) or expected_size <= 1024 or not isinstance(expected_hash, str) or len(expected_hash) != 64:
        raise ValueError('Invalid manifest hash/size')
    binary = fetch(BASE + filename)
    if len(binary) != expected_size or hashlib.sha256(binary).hexdigest().lower() != expected_hash.lower():
        raise ValueError(f'{manifest_name}: checksum/size mismatch')
    elf_arm64(binary, target)
    (DEST / target).write_bytes(binary)
    print(f'{target}: verified SHA-256 {expected_hash}')


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    RULE_DEST.mkdir(parents=True, exist_ok=True)
    manifest_core('singbox-manifest.json', 'libsingbox.so')
    manifest_core('awg-manifest.json', 'libawg.so')

    url = f'https://github.com/XTLS/Xray-core/releases/download/{XRAY_VERSION}/Xray-android-arm64-v8a.zip'
    archive = fetch(url)
    expected = os.environ.get('NEXTLINK_XRAY_SHA256', '').strip().lower()
    if expected and hashlib.sha256(archive).hexdigest() != expected:
        raise ValueError('Xray ZIP SHA-256 mismatch')
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        binary = z.read('xray')
    elf_arm64(binary, 'libxray.so')
    (DEST / 'libxray.so').write_bytes(binary)
    print(f'libxray.so: {XRAY_VERSION} (ZIP sha256 {hashlib.sha256(archive).hexdigest()})')

    base = 'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/'
    for name in ('geoip.dat', 'geosite.dat'):
        data = fetch(base + name)
        (RULE_DEST / name).write_bytes(data)
        print(f'{name}: sha256 {hashlib.sha256(data).hexdigest()}')
    print('Prepared:', DEST)


if __name__ == '__main__':
    main()
