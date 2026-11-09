import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/wg_release.dart';

void main() {
  test('custom WG URLs support direct binaries, manifests, directories and architecture placeholders', () {
    expect(
      WgRelease.source('', 'arm64-v8a').toString(),
      '${WgRelease.baseUrl}/awg-manifest.json',
    );
    expect(
      WgRelease.source('https://example.org/wg', 'arm64-v8a').path,
      '/wg/awg-manifest.json',
    );
    expect(
      WgRelease.source('https://example.org/{arch}/core.so', 'arm64-v8a').path,
      '/arm64-v8a/core.so',
    );
    expect(
      WgRelease.source('https://example.org/custom.json', 'x86_64').path,
      '/custom.json',
    );
    expect(
      () => WgRelease.source('file:///etc/passwd', 'amd64'),
      throwsFormatException,
    );
  });
  test(
    'WG ELF validation rejects wrong architectures and HTML downloads',
    () async {
      final bytes = List<int>.filled(1024, 0);
      bytes.setRange(0, 6, [0x7f, 0x45, 0x4c, 0x46, 2, 1]);
      bytes[18] = 183; // ELF64, little-endian, AArch64.
      WgRelease.validateBinary(bytes, 'arm64-v8a');
      expect(
        () => WgRelease.validateBinary(bytes, 'x86_64'),
        throwsFormatException,
      );
      expect(
        () => WgRelease.validateBinary(List.filled(2000, 32), 'arm64-v8a'),
        throwsFormatException,
      );
    },
  );
  test(
    'staged WG manifest matches all published binaries',
    () async {
      final manifest = await File('dist/wg/awg-manifest.json').readAsString();
      for (final arch in ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'amd64']) {
        final artifact = WgRelease.artifact(manifest, arch);
        final file = File('dist/wg/${artifact['file']}');
        expect(await file.length(), artifact['size']);
        expect(
          (await sha256.bind(file.openRead()).first).toString(),
          artifact['sha256'],
        );
      }
    },
    skip: File('dist/wg/awg-manifest.json').existsSync() ? false : 'Build WG artifacts with scripts/build_amnezia_core.sh to run this integration check.',
  );
  test('WG manifest rejects path escapes and unsupported versions', () {
    final bad = jsonEncode({
      'version': WgRelease.version,
      'files': {
        'arm64-v8a': {'file': '../escape', 'size': 100000, 'sha256': '0' * 64},
      },
    });
    expect(() => WgRelease.artifact(bad, 'arm64-v8a'), throwsFormatException);
    expect(
      () => WgRelease.artifact(
        jsonEncode({'version': 'old', 'files': {}}),
        'arm64-v8a',
      ),
      throwsFormatException,
    );
  });
}
