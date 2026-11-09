import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/core/providers/profiles_provider.dart';
import 'package:nextlink/core/models/subscription.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'partial failures are reported, only failed subscriptions are retried',
    () async {
      SharedPreferences.setMockInitialValues({
        'saved_subscriptions': jsonEncode([
          for (final id in ['ok', 'failed'])
            {
              'id': id,
              'name': id,
              'url': 'https://example.org/$id',
              'updatedTime': '',
              'servers': [],
            },
        ]),
      });
      final requests = <String>[];
      var failing = true;
      final client = MockClient((req) async {
        requests.add(req.url.path);
        if (req.url.path == '/failed' && failing)
          return http.Response('Unavailable', 503);
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
      final first = await notifier.updateAllSubscriptions();
      expect(first.success, false);
      expect(first.updatedIds, ['ok']);
      expect(first.failures.keys, ['failed']);
      final saved = c.read(subscriptionProvider).first.updatedTime;
      expect(DateTime.tryParse(saved), isNotNull);
      failing = false;
      requests.clear();
      final second = await notifier.updateAllSubscriptions(
        onlyIds: first.failures.keys.toSet(),
      );
      expect(second.success, true);
      expect(requests, ['/failed']);
      expect(c.read(subscriptionProvider).first.updatedTime, saved);
    },
  );
  test(
    'concurrent background callers share the actual failure result',
    () async {
      SharedPreferences.setMockInitialValues({
        'saved_subscriptions': jsonEncode([
          {
            'id': 'fail',
            'name': 'fail',
            'url': 'https://example.org/fail',
            'updatedTime': '',
            'servers': [],
          },
        ]),
      });
      final response = Completer<http.Response>();
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          subscriptionHttpClientProvider.overrideWithValue(
            MockClient((_) {
              calls++;
              return response.future;
            }),
          ),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(subscriptionProvider.notifier);
      await n.ready;
      final first = n.updateAllSubscriptions();
      final second = n.updateAllSubscriptions();
      await Future<void>.delayed(Duration.zero);
      response.complete(http.Response('', 503));
      final reports = await Future.wait([first, second]);
      expect(calls, 1);
      expect(reports.every((r) => !r.success), true);
    },
  );
  test(
    'a pinned profile follows changed credentials of the same server',
    () async {
      final old = VlessConfig.parseUri(
        'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Server',
      )..isActive = true;
      final next = VlessConfig.parseUri(
        'vless://00000000-0000-0000-0000-000000000002@example.org:443?security=tls#Server',
      );
      SharedPreferences.setMockInitialValues({
        'saved_subscriptions': jsonEncode([
          Subscription(
            id: 'sub',
            name: 'Sub',
            url: 'https://example.org/sub',
            updatedTime: '',
            servers: [old],
          ).toMap(),
        ]),
        'saved_app_profiles': jsonEncode([
          AppProfile(
            id: 'p',
            name: 'P',
            serverKey: old.uniqueKey,
            serverKeys: [old.uniqueKey],
            triggers: ['timer'],
            isEnabled: true,
          ).toMap(),
        ]),
      });
      final c = ProviderContainer(
        overrides: [
          subscriptionHttpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response(next.toUri(), 200)),
          ),
        ],
      );
      addTearDown(c.dispose);
      final report = await c
          .read(subscriptionProvider.notifier)
          .updateAllSubscriptions();
      expect(report.success, true);
      expect(c.read(profilesProvider).single.serverKey, next.uniqueKey);
      expect(c.read(profilesProvider).single.serverKeys, [next.uniqueKey]);
      expect(c.read(subscriptionProvider).single.servers.single.isActive, true);
    },
  );
}
