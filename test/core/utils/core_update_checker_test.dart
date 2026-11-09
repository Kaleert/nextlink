import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextlink/core/utils/core_update_checker.dart';

void main() {
  late Directory dir;
  late File installed;
  final original = List<int>.filled(1400, 17);
  final newer = List<int>.filled(1400, 18);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nextlink-update-');
    installed = File('${dir.path}/core');
    await installed.writeAsBytes(original);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  String manifest(String core, List<int> bytes, {String version = '99.0.0'}) =>
      jsonEncode({
        'version': version,
        'files': {
          'arm64-v8a': {
            'file': 'lib$core-arm64-v8a.so',
            'size': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
          },
        },
      });
  test('new manifest versions are accepted and actual artifact hashes decide updates', () async {
    final client = MockClient(
      (request) async => http.Response(manifest('awg', newer), 200),
    );
    addTearDown(client.close);
    final checker = CoreUpdateChecker(client);
    final release = await checker.resolve(
      core: 'awg',
      custom: '',
      architecture: 'arm64-v8a',
    );
    expect(release.version, '99.0.0');
    expect(
      release.url.path,
      '/Kaleert/nextlink-cores/releases/download/cores-v1/libawg-arm64-v8a.so',
    );
    expect((await checker.check(installed, release)).hasUpdate, true);
    await installed.writeAsBytes(newer);
    expect((await checker.check(installed, release)).hasUpdate, false);
  });
  test('Sing-box manifest uses server URL and checksum instead of an app-pinned release', () async {
    final client = MockClient(
      (request) async =>
          http.Response(manifest('singbox', original, version: '2027.1'), 200),
    );
    addTearDown(client.close);
    final checker = CoreUpdateChecker(client);
    final release = await checker.resolve(
      core: 'singbox',
      custom: '',
      architecture: 'arm64-v8a',
    );
    expect(release.version, '2027.1');
    expect((await checker.check(installed, release)).hasUpdate, false);
  });
  test('missing Sing-box manifest falls back to hashes; unchanged ETag avoids another download', () async {
    var gets = 0;
    var etag = '"first"';
    var content = original;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('.json')) return http.Response('', 404);
      if (request.method == 'HEAD')
        return http.Response(
          '',
          request.headers['if-none-match'] == etag ? 304 : 200,
          headers: {'etag': etag, 'content-length': '${content.length}'},
        );
      gets++;
      return http.Response.bytes(
        content,
        200,
        headers: {'etag': etag, 'content-length': '${content.length}'},
      );
    });
    addTearDown(client.close);
    final checker = CoreUpdateChecker(client);
    final release = await checker.resolve(
      core: 'singbox',
      custom: '',
      architecture: 'arm64-v8a',
    );
    final first = await checker.check(installed, release);
    expect(first.hasUpdate, false);
    expect(gets, 1);
    expect(
      (await checker.check(installed, release, cache: first.cache)).hasUpdate,
      false,
    );
    expect(gets, 1);
    etag = '"reuploaded-same-bytes"';
    final same = await checker.check(installed, release, cache: first.cache);
    expect(same.hasUpdate, false);
    expect(gets, 2);
    etag = '"new-binary"';
    content = newer;
    expect(
      (await checker.check(installed, release, cache: same.cache)).hasUpdate,
      true,
    );
    expect(gets, 3);
  });
  test(
    'a fresh installation receipt avoids downloading the binary to check it',
    () async {
      final uri = Uri.parse('https://example.org/core.so');
      final receipt = {
        ...CoreUpdateChecker.transfer(
          uri,
          sha256.convert(original).toString(),
          {'etag': '"v1"'},
          original.length,
        ),
        'localHash': await CoreUpdateChecker.fileHash(installed),
      };
      final client = MockClient((request) async {
        expect(request.method, 'HEAD');
        expect(request.headers['if-none-match'], '"v1"');
        return http.Response('', 304);
      });
      addTearDown(client.close);
      expect(
        (await CoreUpdateChecker(
          client,
        ).check(installed, RemoteCoreRelease(uri), receipt: receipt)).hasUpdate,
        false,
      );
    },
  );
  test('archives compare the downloaded archive receipt with the server, not the extracted binary', () async {
    final uri = Uri.parse('https://example.org/core.zip');
    final archiveHash = sha256.convert([1, 2, 3]).toString();
    final client = MockClient((_) async => http.Response('', 304));
    addTearDown(client.close);
    final release = RemoteCoreRelease(uri);
    final receipt = {
      ...CoreUpdateChecker.transfer(uri, archiveHash, {'etag': '"zip1"'}, 3),
      'localHash': await CoreUpdateChecker.fileHash(installed),
    };
    expect(
      (await CoreUpdateChecker(
        client,
      ).check(installed, release, receipt: receipt)).hasUpdate,
      false,
    );
  });
  test('failed probes never modify the installed core', () async {
    final client = MockClient((_) async => http.Response('', 503));
    addTearDown(client.close);
    await expectLater(
      CoreUpdateChecker(client).check(
        installed,
        RemoteCoreRelease(Uri.parse('https://example.org/core.so')),
      ),
      throwsA(isA<HttpException>()),
    );
    expect(await installed.readAsBytes(), original);
  });
  test('a replaced file during the probe is not reported as an update based on stale data', () async {
    final client = MockClient((request) async {
      if (request.method == 'HEAD') {
        await installed.writeAsBytes(List.filled(1500, 22));
        return http.Response('', 200);
      }
      return http.Response.bytes(newer, 200);
    });
    addTearDown(client.close);
    await expectLater(
      CoreUpdateChecker(client).check(
        installed,
        RemoteCoreRelease(Uri.parse('https://example.org/core.so')),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
  test(
    'manifest paths and hashes are validated even with a newer version',
    () async {
      final malformed = jsonDecode(manifest('awg', newer));
      malformed['files']['arm64-v8a']['file'] = '../outside';
      final client = MockClient(
        (_) async => http.Response(jsonEncode(malformed), 200),
      );
      addTearDown(client.close);
      await expectLater(
        CoreUpdateChecker(client)
            .resolve(core: 'awg', custom: '', architecture: 'arm64-v8a'),
        throwsFormatException,
      );
    },
  );
}
