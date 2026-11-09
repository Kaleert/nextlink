import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/engine/config_builder.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';
import 'package:nextlink/core/utils/lan_proxy_inbounds.dart';

void main() {
  final proxy = VlessConfig.parseUri(
    'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Test',
  );
  final settings = SettingsState(
    lanConn: true,
    lanPort: 2080,
    lanUsername: 'lan-user',
    lanPassword: 'lan-pass',
  );
  test('both engines keep private ports unauthenticated and add a separate LAN listener', () {
    final fullSing =
        VlessConfig.parseUri(
            'vless://00000000-0000-0000-0000-000000000001@example.org:443#Full',
          )
          ..rawJsonOverride = jsonEncode({
            'outbounds': [
              {'type': 'direct', 'tag': 'proxy'},
            ],
            'route': {'final': 'proxy'},
          });
    final fullXray =
        VlessConfig.parseUri(
            'vless://00000000-0000-0000-0000-000000000001@example.org:443#Full',
          )
          ..rawJsonOverride = jsonEncode({
            'outbounds': [
              {'protocol': 'freedom', 'tag': 'proxy'},
            ],
            'routing': {'rules': []},
          });
    final configs = [
      SingBoxConfigBuilder(
        activeProxy: fullSing,
        settings: settings,
        customRules: [],
      ).build(),
      XrayConfigBuilder(
        activeProxy: fullXray,
        settings: settings,
        customRules: [],
      ).build(),
      SingBoxConfigBuilder(
        activeProxy: proxy,
        settings: settings,
        customRules: [],
      ).build(),
      XrayConfigBuilder(
        activeProxy: proxy,
        settings: settings,
        customRules: [],
      ).build(),
    ];
    for (final config in configs) {
      final inbounds = config['inbounds'] as List;
      final local = inbounds.where(
        (i) => i['tag'] == 'http' || i['tag'] == 'socks',
      );
      expect(local, hasLength(2));
      expect(
        local.every(
          (i) =>
              i['listen'] == '127.0.0.1' &&
              i['users'] == null &&
              i['settings']?['accounts'] == null,
        ),
        true,
      );
      final lan = inbounds.singleWhere((i) => i['tag'] == 'lan-http');
      expect(lan['listen'], '0.0.0.0');
      if (lan['type'] == 'http') {
        expect(lan['listen_port'], 2080);
        expect(lan['users'].single, {
          'username': 'lan-user',
          'password': 'lan-pass',
        });
      } else {
        expect(lan['port'], 2080);
        expect(lan['settings']['accounts'].single, {
          'user': 'lan-user',
          'pass': 'lan-pass',
        });
      }
    }
    expect(LanProxyInbounds.singBox(settings, isTest: true), isEmpty);
    expect(LanProxyInbounds.xray(settings, isTest: true), isEmpty);
    expect(
      LanProxyInbounds.singBox(settings.copyWith(lanConn: false)),
      isEmpty,
    );
  });
  test('port conflicts and partial credentials are rejected; LAN/WG settings round trip', () {
    for (final port in [0, 65536, 10808, 10809, 10810, 10811]) {
      expect(
        () => LanProxyInbounds.validate(settings.copyWith(lanPort: port)),
        throwsFormatException,
      );
    }
    expect(
      () => LanProxyInbounds.validate(settings.copyWith(lanPassword: '')),
      throwsFormatException,
    );
    final restored = SettingsState.fromMap(
      jsonDecode(
        jsonEncode(
          settings.copyWith(awgUrl: 'https://example.org/{arch}/wg.so').toMap(),
        ),
      ),
    );
    expect(restored.lanPort, 2080);
    expect(restored.lanUsername, 'lan-user');
    expect(restored.lanPassword, 'lan-pass');
    expect(restored.awgUrl, 'https://example.org/{arch}/wg.so');
  });
  test('native Sing-box enforces LAN HTTP authentication and proxies an authorized request', () async {
    final binary = Platform.environment['NEXTLINK_AWG_TEST_BINARY'];
    if (binary == null) return;
    final dir = await Directory.systemTemp.createTemp('nextlink-lan-');
    Process? process;
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target.listen((r) {
      r.response.write('LAN OK');
      r.response.close();
    });
    final reservations = <ServerSocket>[];
    try {
      for (var i = 0; i < 3; i++) {
        reservations.add(
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        );
      }
      final port = reservations[0].port;
      final http = reservations[1].port;
      final socks = reservations[2].port;
      for (final socket in reservations) {
        await socket.close();
      }
      final config = SingBoxConfigBuilder(
        activeProxy: proxy,
        settings: settings.copyWith(
          lanPort: port,
          httpPort: http,
          socksPort: socks,
        ),
        customRules: [],
      ).build();
      config['route']['rules'] = [];
      config['route']['final'] = 'direct';
      final path = '${dir.path}/config.json';
      await File(path).writeAsString(jsonEncode(config));
      process = await Process.start(binary, ['run', '-c', path]);
      final logs = StringBuffer();
      process.stdout.transform(utf8.decoder).listen(logs.write);
      process.stderr.transform(utf8.decoder).listen(logs.write);
      var ready = false;
      int? earlyExit;
      unawaited(
        process.exitCode.then((value) {
          earlyExit = value;
        }),
      );
      final startup = Stopwatch()..start();
      while (startup.elapsed < const Duration(seconds: 10) &&
          earlyExit == null) {
        try {
          final s = await Socket.connect(
            '127.0.0.1',
            port,
            timeout: const Duration(milliseconds: 100),
          );
          s.destroy();
          ready = true;
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      expect(ready, true, reason: 'Exit: $earlyExit\n$logs');
      Future<int> request(bool auth) async {
        final body = File('${dir.path}/response-${auth ? 1 : 0}.txt');
        final response = await Process.run('curl', [
          '--silent',
          '--show-error',
          '--max-time',
          '5',
          '--noproxy',
          '',
          '--proxy',
          'http://127.0.0.1:$port',
          if (auth) ...['--proxy-user', 'lan-user:lan-pass'],
          '--output',
          body.path,
          '--write-out',
          '%{http_code}',
          'http://127.0.0.1:${target.port}/',
        ]);
        if (auth) {
          expect(response.exitCode, 0, reason: '${response.stderr}\n$logs');
          expect(await body.readAsString(), contains('LAN OK'));
        }
        return int.parse(response.stdout.toString());
      }

      expect(await request(false), 407);
      expect(await request(true), 200);
    } finally {
      for (final socket in reservations) {
        await socket.close();
      }
      process?.kill();
      if (process != null) await process.exitCode;
      await target.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
