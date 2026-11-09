import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'core_release_manifest.dart';
import 'wg_release.dart';

class RemoteCoreRelease {
  final Uri url;
  final String? version, hash;
  final int? size;
  const RemoteCoreRelease(this.url, {this.version, this.hash, this.size});
  bool get archive => url.path.endsWith('.zip') || url.path.endsWith('.tar.gz');
}

class CoreUpdateResult {
  final bool hasUpdate;
  final Map<String, dynamic> cache;
  CoreUpdateResult(this.hasUpdate, this.cache);
}

/// Server versions are descriptive; actual artifact hashes decide whether a
/// binary changed. HTTP validators avoid fetching unchanged raw artifacts.
class CoreUpdateChecker {
  final http.Client client;
  CoreUpdateChecker(this.client);
  Future<RemoteCoreRelease> resolve({
    required String core,
    required String custom,
    required String architecture,
  }) async {
    final Uri source;
    Uri? fallback;
    if (core == 'singbox' && custom.trim().isEmpty) {
      source = Uri.parse(
        'https://github.com/Kaleert/nextlink-cores/releases/download/cores-v1/singbox-manifest.json',
      );
      fallback = Uri.parse(
        'https://uk.kaleert.pro/download/sing-box/$architecture/libsingbox.so',
      );
    } else if (core == 'singbox') {
      final raw = custom.trim().replaceAll('{arch}', architecture);
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty)
        throw const FormatException('Укажите HTTP(S)-ссылку на Sing-box');
      source = uri.path.endsWith('/')
          ? uri.replace(path: '${uri.path}awg-manifest.json')
          : uri;
    } else {
      source = WgRelease.source(
        custom.trim().isEmpty ? '${WgRelease.baseUrl}/awg-manifest.json' : custom,
        architecture,
      );
    }
    if (!source.path.endsWith('.json')) return RemoteCoreRelease(source);
    final response = await client
        .get(source, headers: {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404 && fallback != null)
      return RemoteCoreRelease(fallback);
    if (response.statusCode != 200)
      throw HttpException('Манифест ядра: HTTP ${response.statusCode}');
    final manifest = CoreReleaseManifest.parse(response.body, architecture);
    return RemoteCoreRelease(
      source.resolve(manifest.file),
      version: manifest.version,
      hash: manifest.sha256,
      size: manifest.size,
    );
  }

  static Future<String> fileHash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
  static String signature(FileStat stat) =>
      '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
  static Map<String, dynamic> transfer(
    Uri url,
    String hash,
    Map<String, String> headers,
    int size,
  ) => {
    'source': url.toString(),
    'remoteHash': hash,
    'etag': headers['etag'],
    'modified': headers['last-modified'],
    'remoteSize': size,
  };
  Future<CoreUpdateResult> check(
    File installed,
    RemoteCoreRelease release, {
    Map<String, dynamic> cache = const {},
    Map<String, dynamic> receipt = const {},
  }) async {
    final stat = await installed.stat();
    if (stat.type != FileSystemEntityType.file)
      throw const FileSystemException('Ядро не установлено');
    final localSignature = signature(stat);
    final localHash =
        cache['localSignature'] == localSignature &&
            cache['localHash'] is String
        ? cache['localHash'] as String
        : await fileHash(installed);
    final source = release.url.toString();
    final previous = cache['source'] == source
        ? cache
        : receipt['source'] == source
        ? receipt
        : <String, dynamic>{};
    String remoteHash;
    Map<String, dynamic> remote;
    if (release.hash != null) {
      remoteHash = release.hash!;
      remote = {
        'source': source,
        'remoteHash': remoteHash,
        'remoteSize': release.size,
      };
    } else {
      final etag = previous['etag'] as String?;
      final modified = previous['modified'] as String?;
      final headers = <String, String>{
        'Cache-Control': 'no-cache',
        if (etag != null) 'If-None-Match': etag,
        if (etag == null && modified != null) 'If-Modified-Since': modified,
      };
      final head = await client
          .head(release.url, headers: headers)
          .timeout(const Duration(seconds: 20));
      final same =
          head.statusCode == 304 ||
          head.statusCode == 200 &&
              (etag != null && head.headers['etag'] == etag ||
                  etag == null &&
                      modified != null &&
                      head.headers['last-modified'] == modified &&
                      int.tryParse(head.headers['content-length'] ?? '') ==
                          previous['remoteSize']);
      if (same && previous['remoteHash'] is String) {
        remoteHash = previous['remoteHash'] as String;
        remote = Map<String, dynamic>.from(previous);
      } else {
        if (![200, 304, 405, 501].contains(head.statusCode))
          throw HttpException('Проверка ядра: HTTP ${head.statusCode}');
        final request = http.Request('GET', release.url)
          ..headers['Cache-Control'] = 'no-cache';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          await response.stream.drain<void>();
          throw HttpException('Проверка ядра: HTTP ${response.statusCode}');
        }
        var bytes = 0;
        final digest = await sha256
            .bind(
              response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
                bytes += chunk.length;
                return chunk;
              }),
            )
            .first;
        if (response.contentLength != null && response.contentLength != bytes)
          throw const HttpException('Неполный ответ при проверке ядра');
        remoteHash = digest.toString();
        remote = transfer(release.url, remoteHash, response.headers, bytes);
      }
    }
    final after = await installed.stat();
    if (signature(after) != localSignature)
      throw const FileSystemException('Ядро изменилось во время проверки');
    final installedHash = release.archive
        ? receipt['localHash'] == localHash && receipt['source'] == source
              ? receipt['remoteHash'] as String?
              : null
        : localHash;
    // A legacy archive installation has no artifact receipt: no guessed update.
    return CoreUpdateResult(
      installedHash != null && installedHash != remoteHash,
      {...remote, 'localHash': localHash, 'localSignature': localSignature},
    );
  }
}
