import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/providers/map_selection_provider.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/core/models/subscription.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('runtime choice persists separately, restores, and never inserts a manual server', () async {
    final source = ProxyParser.parse(
      'vless://00000000-0000-0000-0000-000000000001@auto.example.org:443#Auto',
    )..isActive = true;
    final selected = ProxyParser.parse(
      'vless://00000000-0000-0000-0000-000000000001@pl.example.org:443#Warsaw',
    );
    final saved = jsonEncode([
      Subscription(
        id: 'sub',
        name: 'Sub',
        url: 'https://example.org/sub',
        updatedTime: '',
        servers: [source],
      ).toMap(),
    ]);
    SharedPreferences.setMockInitialValues({'saved_subscriptions': saved});
    final c = ProviderContainer();
    await c.read(subscriptionProvider.notifier).ready;
    await c
        .read(mapSelectionProvider.notifier)
        .choose(
          MapServerSelection(
            selected,
            anchorKey: source.uniqueKey,
            sourceKey: source.uniqueKey,
          ),
        );
    expect(c.read(subscriptionProvider).length, 1);
    expect(c.read(subscriptionProvider).single.servers.length, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_subscriptions'), saved);
    c.dispose();
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(mapSelectionProvider.notifier).ready;
    expect(
      restored.read(mapSelectionProvider)!.server.address,
      'pl.example.org',
    );
    expect(
      restored.read(mapSelectionProvider)!.appliesTo(source.uniqueKey),
      true,
    );
    expect(restored.read(mapSelectionProvider)!.appliesTo('other'), false);
    await restored.read(subscriptionProvider.notifier).ready;
    restored
        .read(subscriptionProvider.notifier)
        .setActiveServer(
          'sub',
          restored.read(subscriptionProvider).single.servers.single,
        );
    await Future<void>.delayed(Duration.zero);
    expect(restored.read(mapSelectionProvider), isNull);
    expect(restored.read(subscriptionProvider).single.servers.length, 1);
  });
}
