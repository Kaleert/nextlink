import 'core_binary_paths.dart';

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/proxies/proxy_config.dart';
import '../providers/settings_provider.dart';
import '../providers/rules_provider.dart';
import '../providers/chains_provider.dart';
import '../engine/config_builder.dart';

class PingResult {
  final int latencyMs;
  final String? error;
  final List<int> samples;

  PingResult({required this.latencyMs, this.error, this.samples = const []});
  bool get isSuccess => latencyMs > 0 && error == null;
}

class HttpProbeResult {
  final int statusCode;
  final int latencyMs;
  final String body;
  final Map<String, String> headers;
  final List<int> samples;

  const HttpProbeResult({
    required this.statusCode,
    required this.latencyMs,
    required this.body,
    required this.headers,
    this.samples = const [],
  });
}

class PingUtils {
  static bool _isTestCoreRunning = false;

  static Future<HttpProbeResult> httpRequestViaConfig({
    required ProxyConfig server,
    required SettingsState settings,
    required Uri uri,
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 15),
    bool followRedirects = true,
    int probeCount = 1,
    bool captureBody = true,
    bool allowBadCertificate = false,
    Future<HttpProbeResult> Function(int proxyPort)? withReadyProxy,
    void Function(String chunk)? onBodyChunk,
    void Function(int statusCode, Map<String, String> headers)?
    onResponseHeaders,
  }) async {
    while (_isTestCoreRunning) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _isTestCoreRunning = true;

    const platform = MethodChannel('pro.kaleert.nextlink/vpn');
    var started = false;
    try {
      final appDir = await getApplicationSupportDirectory();
      final xrayPath =
          '${appDir.path}/${Platform.isAndroid ? 'libxray.so' : 'xray'}';
      final sbPath = await CoreBinaryPaths.singBox(appDir.path, [
        server,
      ], custom: settings.singboxUrl.isNotEmpty);
      final hasHy2 = server.protocol.toUpperCase().contains('HYSTERIA');
      final hasXhttp = jsonEncode(server.finalJson)
          .toLowerCase()
          .contains('"xhttp"');
      final useSingBox =
          (server.finalJson.containsKey('endpoints') ||
              ['wireguard', 'awg'].contains(server.finalJson['type'])) ||
          hasHy2 ||
          (!hasXhttp && settings.preferredCore.toUpperCase() == 'SINGBOX');
      final coreType = useSingBox ? 'SINGBOX' : 'XRAY';
      final config = useSingBox
          ? SingBoxConfigBuilder(
              activeProxy: server,
              settings: settings,
              customRules: [],
              isTest: true,
            ).build()
          : XrayConfigBuilder(
              activeProxy: server,
              settings: settings,
              customRules: [],
              isTest: true,
            ).build();
      final startError = await platform.invokeMethod<String>('startTestCore', {
        'config': jsonEncode(config),
        'coreType': coreType,
        'xrayPath': xrayPath,
        'sbPath': sbPath,
      });
      if (startError != null && startError.isNotEmpty) {
        throw Exception(startError);
      }
      started = true;

      final proxyPort = settings.httpPort + 2;
      var proxyReady = false;
      for (var attempt = 0; attempt < 30; attempt++) {
        try {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            proxyPort,
            timeout: const Duration(milliseconds: 250),
          );
          socket.destroy();
          proxyReady = true;
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      if (!proxyReady) throw Exception('Тестовое ядро не открыло HTTP-порт');
      if (withReadyProxy != null) return await withReadyProxy(proxyPort);

      final client = HttpClient()
        ..connectionTimeout = timeout
        ..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
      if (allowBadCertificate) {
        client.badCertificateCallback = (_certificate, _host, _port) => true;
      }
      try {
        final samples = <int>[];
        var statusCode = 0;
        var responseBody = '';
        final responseHeaders = <String, String>{};
        for (var index = 0; index < probeCount.clamp(1, 10); index++) {
          final stopwatch = Stopwatch()..start();
          final request = await client.openUrl(method, uri).timeout(timeout);
          request.followRedirects = followRedirects;
          headers.forEach(request.headers.set);
          if (body != null && body.isNotEmpty) request.write(body);
          final response = await request.close().timeout(timeout);
          statusCode = response.statusCode;
          responseHeaders.clear();
          response.headers.forEach(
            (name, values) => responseHeaders[name] = values.join(', '),
          );
          onResponseHeaders?.call(statusCode, Map.of(responseHeaders));
          if (captureBody) {
            final responseText = StringBuffer();
            await for (final chunk
                in response.transform(utf8.decoder).timeout(timeout)) {
              onBodyChunk?.call(chunk);
              if (responseText.length < 1024 * 1024) {
                final remaining = 1024 * 1024 - responseText.length;
                responseText.write(
                  chunk.length <= remaining
                      ? chunk
                      : chunk.substring(0, remaining),
                );
              }
            }
            responseBody = responseText.toString();
          } else {
            await response.drain<void>().timeout(timeout);
          }
          final elapsed = stopwatch.elapsedMilliseconds;
          samples.add(elapsed > 0 ? elapsed : 1);
          stopwatch.stop();
        }
        return HttpProbeResult(
          statusCode: statusCode,
          latencyMs: samples.last,
          body: responseBody,
          headers: responseHeaders,
          samples: samples,
        );
      } finally {
        client.close(force: true);
      }
    } finally {
      try {
        if (started) {
          await platform.invokeMethod<void>('stopTestCore');
        }
      } finally {
        _isTestCoreRunning = false;
      }
    }
  }

  static Future<PingResult> pingUrlViaConfig(
    ProxyConfig server,
    SettingsState settings,
    Uri uri, {
    Duration timeout = const Duration(seconds: 8),
    int probeCount = 1,
  }) async {
    try {
      final response = await httpRequestViaConfig(
        server: server,
        settings: settings,
        uri: uri,
        timeout: timeout,
        probeCount: probeCount,
        captureBody: false,
      );
      return PingResult(
        latencyMs: response.latencyMs,
        samples: response.samples,
      );
    } catch (error) {
      return PingResult(latencyMs: -1, error: error.toString());
    }
  }

  static (String?, int?) _extractHostAndPort(ProxyConfig server) {
    if (server.address.isNotEmpty &&
        server.address != 'JSON Config' &&
        server.port > 0) {
      return (server.address, server.port);
    }
    try {
      final jsonMap = server.finalJson;
      if (jsonMap.containsKey('outbounds') && (jsonMap['outbounds'] is List)) {
        final outbounds = jsonMap['outbounds'] as List;
        if (outbounds.isNotEmpty && outbounds[0] is Map) {
          final first = outbounds[0] as Map<String, dynamic>;
          final settings = first['settings'];

          if (settings is Map) {
            if (settings.containsKey('vnext') &&
                (settings['vnext'] is List) &&
                (settings['vnext'] as List).isNotEmpty) {
              final vnext = settings['vnext'][0];
              if (vnext is Map) {
                final addr = vnext['address']?.toString();
                final port = int.tryParse(vnext['port']?.toString() ?? '');
                if (addr != null && addr.isNotEmpty && port != null && port > 0)
                  return (addr, port);
              }
            }
            if (settings.containsKey('servers') &&
                (settings['servers'] is List) &&
                (settings['servers'] as List).isNotEmpty) {
              final srv = settings['servers'][0];
              if (srv is Map) {
                final addr =
                    srv['address']?.toString() ?? srv['server']?.toString();
                final port = int.tryParse(
                  srv['port']?.toString() ??
                      srv['server_port']?.toString() ??
                      '',
                );
                if (addr != null && addr.isNotEmpty && port != null && port > 0)
                  return (addr, port);
              }
            }
          }
          final addr =
              first['server']?.toString() ?? first['address']?.toString();
          final port = int.tryParse(
            first['server_port']?.toString() ?? first['port']?.toString() ?? '',
          );
          if (addr != null && addr.isNotEmpty && port != null && port > 0)
            return (addr, port);
        }
      }
      final addr =
          jsonMap['server']?.toString() ?? jsonMap['address']?.toString();
      final port = int.tryParse(
        jsonMap['server_port']?.toString() ?? jsonMap['port']?.toString() ?? '',
      );
      if (addr != null && addr.isNotEmpty && port != null && port > 0)
        return (addr, port);
    } catch (_) {}
    return (null, null);
  }

  static Future<PingResult> _doTcpPing(
    String targetHost,
    int port,
    Duration timeout,
    ProxyConfig server,
    void Function()? onProbeStart,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(targetHost)
          .timeout(timeout);
      if (addresses.isEmpty) {
        stopwatch.stop();
        server.ping = -1;
        return PingResult(
          latencyMs: -1,
          error: 'DNS не смог разрешить адрес $targetHost',
        );
      }

      stopwatch.reset();
      stopwatch.start();
      onProbeStart?.call();
      final socket = await Socket.connect(
        addresses.first,
        port,
        timeout: timeout,
      );
      stopwatch.stop();
      socket.destroy();

      final ms = stopwatch.elapsedMilliseconds > 0
          ? stopwatch.elapsedMilliseconds
          : 1;
      server.ping = ms;
      return PingResult(latencyMs: ms);
    } catch (e) {
      stopwatch.stop();
      server.ping = -1;
      final errStr = e
          .toString()
          .replaceAll('SocketException: ', '')
          .replaceAll('FormatException: ', '')
          .replaceAll('TimeoutException', 'Таймаут соединения');
      return PingResult(
        latencyMs: -1,
        error: 'TCP сбой ($targetHost:$port): $errStr',
      );
    }
  }

  /// ПИНГ ЧЕРЕЗ ТЕСТОВОЕ ЯДРО (БЫСТРЫЙ И УМНЫЙ)
  static Future<PingResult> _pingViaTestCore(
    ProxyConfig server,
    SettingsState settings,
    Duration timeout,
    List<AppRule> customRules,
    ProxyChain? activeChain,
    void Function()? onProbeStart,
    String? targetUrl,
    int redirectLimit,
  ) async {
    while (_isTestCoreRunning) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _isTestCoreRunning = true;

    try {
      final appDir = await getApplicationSupportDirectory();
      final xrayPath =
          '${appDir.path}/${Platform.isAndroid ? 'libxray.so' : 'xray'}';
      final sbPath = await CoreBinaryPaths.singBox(
        appDir.path,
        activeChain?.nodes ?? [server],
        custom: settings.singboxUrl.isNotEmpty,
      );

      bool hasHy2 = server.protocol.toUpperCase().contains('HYSTERIA');
      bool hasXhttp = jsonEncode(server.finalJson)
          .toLowerCase()
          .contains('"xhttp"');

      String coreToUse = settings.preferredCore.toUpperCase();
      if (server.finalJson.containsKey('endpoints') ||
          ['wireguard', 'awg'].contains(server.finalJson['type']))
        coreToUse = 'SINGBOX';
      else if (activeChain != null)
        coreToUse = 'SINGBOX';
      else if (hasHy2)
        coreToUse = 'SINGBOX';
      else if (hasXhttp)
        coreToUse = 'XRAY'; // Выбираем XRAY для чистого XHTTP, так как в нем он работает идеально

      String testConfigJson = (coreToUse == 'SINGBOX')
          ? jsonEncode(
              SingBoxConfigBuilder(
                activeProxy: server,
                settings: settings,
                customRules: customRules,
                activeChain: activeChain,
                isTest: true,
              ).build(),
            )
          : jsonEncode(
              XrayConfigBuilder(
                activeProxy: server,
                settings: settings,
                customRules: customRules,
                activeChain: activeChain,
                isTest: true,
              ).build(),
            );

      const platform = MethodChannel('pro.kaleert.nextlink/vpn');
      await platform.invokeMethod('startTestCore', {
        'config': testConfigJson,
        'coreType': coreToUse,
        'xrayPath': xrayPath,
        'sbPath': sbPath,
      });

      final testHttpPort = settings.httpPort + 2;
      final pingUrl = targetUrl?.trim().isNotEmpty == true
          ? targetUrl!.trim()
          : settings.pingUrl.isNotEmpty
          ? settings.pingUrl
          : 'http://www.gstatic.com/generate_204';

      int latency = -1;
      String? errorMsg;

      // Ждем первичного старта ядра (всего 300мс вместо прошлых 800)
      await Future.delayed(const Duration(milliseconds: 300));

      // Делаем до 4 попыток, если ядро еще не открыло порт (Connection refused)
      for (int i = 0; i < 4; i++) {
        if (!_isTestCoreRunning) break;

        final client = HttpClient();
        client.connectionTimeout = timeout;
        client.findProxy = (uri) => "PROXY 127.0.0.1:$testHttpPort";

        onProbeStart?.call();
        final sw = Stopwatch()..start();
        try {
          final req = await client.getUrl(Uri.parse(pingUrl)).timeout(timeout);
          req.followRedirects = true;
          req.maxRedirects = redirectLimit.clamp(0, 50);
          final res = await req.close().timeout(timeout);
          sw.stop();
          client.close(force: true);

          if (res.statusCode > 0 && res.statusCode < 500) {
            latency = sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : 1;
            errorMsg = null;
            break; // Успех, мгновенный выход
          } else {
            errorMsg = 'HTTP статус ${res.statusCode}';
            break; // Ядро работает, но сервер вернул ошибку -> не ретраим
          }
        } catch (e) {
          sw.stop();
          client.close(force: true);
          final errStr = e.toString();

          if (errStr.contains('Connection refused') ||
              errStr.contains('SocketException')) {
            // Ядро запускается, подождем еще немного
            errorMsg = 'Ядро запускается...';
            await Future.delayed(const Duration(milliseconds: 400));
            continue;
          }

          // Реальная ошибка соединения/таймаут -> не ретраим
          errorMsg = errStr
              .replaceAll('Exception: ', '')
              .replaceAll('SocketException: ', '');
          break;
        }
      }

      if (latency > 0) {
        server.ping = latency;
        return PingResult(latencyMs: latency);
      } else {
        server.ping = -1;
        return PingResult(
          latencyMs: -1,
          error: errorMsg ?? 'Таймаут (Ядро не смогло подключиться)',
        );
      }
    } finally {
      const platform = MethodChannel('pro.kaleert.nextlink/vpn');
      await platform.invokeMethod('stopTestCore');
      _isTestCoreRunning = false;
    }
  }

  static Future<PingResult> pingServerEx(
    ProxyConfig server,
    SettingsState settings, {
    Duration timeout = const Duration(seconds: 4),
    List<AppRule> customRules = const [],
    ProxyChain? activeChain,
    void Function()? onProbeStart,
    String? targetUrl,
    int redirectLimit = 5,
  }) async {
    server.isPinging = true;
    final mode = settings.pingType;

    try {
      if (mode == 'via Proxy' || targetUrl?.trim().isNotEmpty == true) {
        return await _pingViaTestCore(
          server,
          settings,
          timeout,
          customRules,
          activeChain,
          onProbeStart,
          targetUrl,
          redirectLimit,
        );
      }

      final (targetHost, targetPort) = _extractHostAndPort(server);
      if (targetHost == null || targetHost.isEmpty) {
        server.ping = -1;
        return PingResult(latencyMs: -1, error: 'Не указан адрес сервера');
      }

      if (mode == 'ICMP') {
        final stopwatch = Stopwatch();
        try {
          String ipStr = targetHost;
          try {
            final addrs = await InternetAddress.lookup(targetHost)
                .timeout(timeout);
            if (addrs.isNotEmpty) ipStr = addrs.first.address;
          } catch (_) {}

          onProbeStart?.call();
          stopwatch.start();
          ProcessResult process;
          try {
            process = await Process.run('ping', [
              '-c',
              '1',
              '-w',
              '2',
              ipStr,
            ]).timeout(timeout);
          } catch (_) {
            process = await Process.run('ping', [
              '-c',
              '1',
              ipStr,
            ]).timeout(timeout);
          }
          stopwatch.stop();

          if (process.exitCode == 0) {
            final output = process.stdout.toString();
            final match =
                RegExp(r'time=([\d.]+)').firstMatch(output) ??
                RegExp(r'rtt min/avg/max/mdev = [\d.]+/([\d.]+)')
                    .firstMatch(output);
            if (match != null) {
              final ms =
                  double.tryParse(match.group(1)!)?.toInt() ??
                  stopwatch.elapsedMilliseconds;
              final finalMs = ms > 0 ? ms : 1;
              server.ping = finalMs;
              return PingResult(latencyMs: finalMs);
            }
            final ms = stopwatch.elapsedMilliseconds > 0
                ? stopwatch.elapsedMilliseconds
                : 1;
            server.ping = ms;
            return PingResult(latencyMs: ms);
          } else {
            server.ping = -1;
            return PingResult(
              latencyMs: -1,
              error: 'ICMP: хост $targetHost недоступен',
            );
          }
        } catch (e) {
          stopwatch.stop();
          server.ping = -1;
          return PingResult(
            latencyMs: -1,
            error: 'ICMP ошибка: ${e.toString().replaceAll('Exception: ', '')}',
          );
        }
      } else {
        final portToUse = targetPort ?? server.port;
        return await _doTcpPing(
          targetHost,
          portToUse > 0 ? portToUse : 443,
          timeout,
          server,
          onProbeStart,
        );
      }
    } finally {
      server.isPinging = false;
    }
  }

  static Future<void> pingAllEx(
    List<ProxyConfig> servers,
    SettingsState settings, {
    int concurrency = 5,
    void Function()? onProgress,
  }) async {
    if (servers.isEmpty) return;

    // Тестовое ядро не может пинговать параллельно, снижаем concurrency до 1
    if (settings.pingType == 'via Proxy') {
      concurrency = 1;
    }

    for (var srv in servers) {
      srv.isPinging = true;
    }
    onProgress?.call();

    for (int i = 0; i < servers.length; i += concurrency) {
      final end = (i + concurrency < servers.length)
          ? i + concurrency
          : servers.length;
      final batch = servers.sublist(i, end);

      await Future.wait(batch.map((srv) => pingServerEx(srv, settings)));
      onProgress?.call();
      await Future.delayed(const Duration(milliseconds: 20));
    }
    for (var srv in servers) {
      srv.isPinging = false;
    }
    onProgress?.call();
  }
}
