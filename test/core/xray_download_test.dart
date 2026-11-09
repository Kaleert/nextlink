import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('Xray ARM64: GitHub API -> ZIP -> binary', () async {
    final client = http.Client();
    addTearDown(client.close);

    const repo = 'XTLS/Xray-core';
    const filename = 'Xray-android-arm64-v8a.zip';

    // 1. Получаем последний релиз.
    late http.Response api;

    for (var attempt = 0; attempt < 3; attempt++) {
      api = await client
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {
              'User-Agent': 'NextLink-Test',
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (api.statusCode == 200) break;

      if (![502, 503, 504].contains(api.statusCode)) break;

      print('GitHub API HTTP ${api.statusCode}, attempt ${attempt + 1}/3');

      if (attempt < 2) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }

    expect(api.statusCode, 200, reason: 'GitHub API');

    final release = jsonDecode(api.body) as Map<String, dynamic>;
    final assets = release['assets'] as List<dynamic>;

    print('Release: ${release['tag_name']}');
    print('Available assets:');
    for (final asset in assets) {
      print('  ${asset['name']}');
    }

    // 2. Ищем точный архив.
    final asset = assets.cast<Map<String, dynamic>>().firstWhere(
      (a) => a['name'] == filename,
    );

    print('Selected: ${asset['name']}');
    print('Asset ID: ${asset['id']}');

    // 3. Качаем через Assets API.
    final request = http.Request('GET', Uri.parse(asset['url'] as String));

    request.headers.addAll({
      'Accept': 'application/octet-stream',
      'User-Agent': 'NextLink-Test',
      'X-GitHub-Api-Version': '2022-11-28',
    });

    final response = await client.send(request);
    expect(response.statusCode, 200);

    final bytes = await response.stream.toBytes();

    print('Downloaded: ${bytes.length} bytes');

    expect(bytes.length, greaterThan(1000000));

    // 4. Проверяем ZIP.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4b);

    final archive = ZipDecoder().decodeBytes(bytes);

    final binaries = archive.files.where((f) {
      final name = f.name.split('/').last.toLowerCase();
      return f.isFile && (name == 'xray' || name == 'xray.exe');
    }).toList();

    expect(
      binaries,
      isNotEmpty,
      reason: 'В архиве отсутствует исполняемый файл Xray',
    );

    print('Binary: ${binaries.first.name}');
    print('SUCCESS: Xray archive is valid');
  }, tags: ['network'], timeout: Timeout(Duration(minutes: 3)));
}
