import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/providers/automation_provider.dart';
import 'package:nextlink/core/providers/profiles_provider.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/models/subscription.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';

void main() {
  test(
    'background compiler rebuilds native targets from refreshed credentials',
    () async {
      final dir = await Directory.systemTemp.createTemp('nextlink-plan-');
      try {
        await File('${dir.path}/libxray.so')
            .writeAsString('fake binary for existence check');
        final old = VlessConfig.parseUri(
          'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Server',
        );
        final refreshed = VlessConfig.parseUri(
          'vless://00000000-0000-0000-0000-000000000002@example.org:443?security=tls#Server',
        );
        Future<Map<String, dynamic>> compile(server) => compileAutomationPlan(
          profiles: [
            AppProfile(
              id: 'p',
              name: 'P',
              triggers: ['timer'],
              isEnabled: true,
            ),
          ],
          subscriptions: [
            Subscription(
              id: 'sub',
              name: 'Sub',
              url: 'https://example.org/sub',
              updatedTime: '',
              servers: [server],
            ),
          ],
          settings: SettingsState(preferredCore: 'XRAY'),
          rules: [],
          appDir: dir.path,
        );
        final first = await compile(old);
        final next = await compile(refreshed);
        expect(first['servers'].single['key'], old.uniqueKey);
        expect(next['servers'].single['key'], refreshed.uniqueKey);
        final encoded = jsonEncode(next);
        expect(encoded, contains('00000000-0000-0000-0000-000000000002'));
        expect(
          encoded,
          isNot(contains('00000000-0000-0000-0000-000000000001')),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
