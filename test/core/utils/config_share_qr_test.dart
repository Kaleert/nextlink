import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/config_share_qr.dart';
import 'package:nextlink/core/utils/config_share_payload.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  test('small protocol URLs keep their original QR data', () {
    const text =
        'vless://00000000-0000-0000-0000-000000000001@example.org:443#Test';
    final qr = ConfigShareQr.prepare(text)!;
    expect(qr.data, text);
    expect(qr.compressed, false);
    expect(qr.code.dataCache, isNotEmpty);
  });
  test('a large full configuration is compressed, encodes completely, and round trips', () {
    final text = jsonEncode({
      'outbounds': List.generate(
        30,
        (i) => {
          'tag': 'Server $i',
          'type': 'vless',
          'server': 'server$i.example.org',
          'uuid': '00000000-0000-0000-0000-000000000001',
          'tls': {'enabled': true},
        },
      ),
      'route': {
        'rules': List.generate(
          40,
          (i) => {
            'domain_suffix': ['domain$i.example.org'],
            'outbound': 'direct',
          },
        ),
      },
    });
    expect(utf8.encode(text).length, greaterThan(6000));
    final qr = ConfigShareQr.prepare(text)!;
    expect(qr.compressed, true);
    expect(qr.data, startsWith('nextlink://import-gzip/'));
    expect(qr.code.dataCache, isNotEmpty);
    expect(ConfigSharePayload.decodeQr(qr.data), text);
    expect(QrImage(qr.code).moduleCount, greaterThan(0));
  });
  test('byte capacity boundary is checked before QR painting', () {
    expect(ConfigShareQr.prepare('a' * 2953)!.compressed, false);
    expect(ConfigShareQr.prepare('a' * 2954)!.compressed, true);
  });
  test('irreducibly oversized input returns no code before opening or painting a QR view', () {
    final random = Random(42);
    final text = base64Encode(List.generate(12000, (_) => random.nextInt(256)));
    expect(ConfigShareQr.prepare(text), isNull);
  });
  test('UTF-8 byte length, not character count, determines capacity', () {
    final qr = ConfigShareQr.prepare('Ж' * 2000)!;
    expect(qr.compressed, true);
    expect(ConfigSharePayload.decodeQr(qr.data), 'Ж' * 2000);
  });
  test(
    'compressed QR rejects expansion beyond the import limit and bad checksums',
    () {
      final bomb = GZipEncoder().encode(
        List.filled(ConfigSharePayload.maxQrDecodedBytes + 1, 65),
      )!;
      final uri = 'nextlink://import-gzip/${base64UrlEncode(bomb)}';
      expect(() => ConfigSharePayload.decodeQr(uri), throwsFormatException);
      final good = ConfigSharePayload.compressedImportLink('{"outbounds":[]}')!;
      final encoded = Uri.parse(good).pathSegments.single;
      final broken = base64Url.decode(base64Url.normalize(encoded));
      broken[broken.length - 8] ^= 1;
      expect(
        () => ConfigSharePayload.decodeQr(
          'nextlink://import-gzip/${base64UrlEncode(broken)}',
        ),
        throwsFormatException,
      );
    },
  );
  test('compressed QR cannot smuggle a VPN command through the importer', () {
    expect(
      () => ConfigSharePayload.decodeQr(
        ConfigSharePayload.compressedImportLink('nextlink://disconnect')!,
      ),
      throwsFormatException,
    );
  });
}
