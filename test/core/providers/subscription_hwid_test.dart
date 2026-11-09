import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/core/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'panel receives stable X-Hwid rather than X-Device-ID; actual configs load',
    () async {
      SharedPreferences.setMockInitialValues({});
      final ids = <String>[];
      final client = MockClient((req) async {
        final headers = req.headers.map((k, v) => MapEntry(k.toLowerCase(), v));
        expect(headers.containsKey('x-device-id'), false);
        expect(headers['x-device-os'], isNotEmpty);
        ids.add(headers['x-hwid']!);
        expect(RegExp(r'^[a-zA-Z0-9=-]{10,64}$').hasMatch(ids.last), true);
        return http.Response(
          'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Server',
          200,
        );
      });
      final c = ProviderContainer(
        overrides: [subscriptionHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(c.dispose);
      final notifier = c.read(subscriptionProvider.notifier);
      await notifier.addSubscription('Test', 'https://example.org/sub');
      final sub = c.read(subscriptionProvider).last;
      await notifier.updateSubscription(sub.id);
      expect(ids.length, 2);
      expect(ids.first, ids.last);
      expect(c.read(subscriptionProvider).last.servers.single.name, 'Server');
    },
  );
  for (final header in ['x-hwid-not-supported', 'x-hwid-limit']) {
    test('$header preserves the existing subscription', () async {
      SharedPreferences.setMockInitialValues({});
      var rejected = false;
      final c = ProviderContainer(
        overrides: [
          subscriptionHttpClientProvider.overrideWithValue(
            MockClient(
              (_) async => http.Response(
                'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Server',
                200,
                headers: rejected ? {header: 'true'} : {},
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final notifier = c.read(subscriptionProvider.notifier);
      await notifier.addSubscription('Test', 'https://example.org/sub');
      final sub = c.read(subscriptionProvider).last;
      rejected = true;
      await expectLater(
        notifier.updateSubscription(sub.id),
        throwsA(
          predicate(
            (error) =>
                '$error'.contains('HWID') ||
                '$error'.contains('лимит устройств'),
          ),
        ),
      );
      expect(c.read(subscriptionProvider).last.servers.single.name, 'Server');
    });
  }
  test('headerless dummy App not supported profile is rejected', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(SettingsState(sendHwid: false).toMap()),
    });
    final c = ProviderContainer(
      overrides: [
        subscriptionHttpClientProvider.overrideWithValue(
          MockClient((req) async {
            expect(
              req.headers.keys.any((k) => k.toLowerCase() == 'x-hwid'),
              false,
            );
            return http.Response(
              '[{"remarks":"App not supported","outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"0.0.0.0","port":1}]}}]}]',
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      c
          .read(subscriptionProvider.notifier)
          .addSubscription('Test', 'https://example.org/sub'),
      throwsA(
        predicate(
          (error) =>
              '$error'.contains('HWID') || '$error'.contains('лимит устройств'),
        ),
      ),
    );
    expect(c.read(subscriptionProvider).expand((s) => s.servers), isEmpty);
  });
}
