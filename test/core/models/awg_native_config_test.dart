import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/proxies/wireguard_config.dart';
import 'package:nextlink/core/engine/config_builder.dart';
import 'package:nextlink/core/providers/settings_provider.dart';

void main() {
  final binary = Platform.environment['NEXTLINK_AWG_TEST_BINARY'];
  test(
    'AWG 3.1 fields survive conversion and pass the actual native core check',
    () async {
      final key = base64Encode(List.filled(32, 7));
      final config = WireGuardConfig.parse('''
[Interface]
PrivateKey = $key
Address = 10.0.0.2, 2606:4700:110::2
Jc = 4
Jmin = 40
Jmax = 70
H1 = 100-200
HeaderProtectionKey = $key
ContentPaddingAddition = 0-16
RekeyAfterTime = 120-180
RandomTrailers = on
DisableCookies = off
[Peer]
PublicKey = $key
Endpoint = 127.0.0.1:51820
AllowedIPs = 0.0.0.0/0
''');
      final json = SingBoxConfigBuilder(
        activeProxy: config,
        settings: SettingsState(),
        customRules: [],
      ).build();
      final endpoint = json['endpoints'].single;
      expect(endpoint['header_protection_key'], key);
      expect(endpoint['content_padding_addition'], '0-16');
      expect(endpoint['random_trailers'], true);
      expect(endpoint['disable_cookies'], false);
      if (binary == null) return;
      final dir = await Directory.systemTemp.createTemp('nextlink-awg-check-');
      try {
        final file = File('${dir.path}/config.json');
        await file.writeAsString(jsonEncode(json));
        final result = await Process.run(binary, ['check', '-c', file.path]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
