import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/main.dart';
import 'package:nextlink/core/providers/chains_provider.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/core/models/subscription.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native chain identity stays a chain; an explicit single-server switch still works', () async {
    final first = VlessConfig.parseUri(
      'vless://00000000-0000-0000-0000-000000000001@entry.example:443?security=tls#Entry',
    );
    final last = VlessConfig.parseUri(
      'vless://00000000-0000-0000-0000-000000000002@exit.example:443?security=tls#Exit',
    );
    final chain = ProxyChain(
      id: 'chain-test',
      name: 'Two hops',
      nodes: [first, last],
      isActive: true,
    );
    final sub = Subscription(
      id: 'manual',
      name: 'Manual',
      url: '',
      updatedTime: '',
      servers: [first, last],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({'autoUpdateCores': false}),
      'custom_proxy_chains': jsonEncode([chain.toMap()]),
      'saved_subscriptions': jsonEncode([sub.toMap()]),
    });
    const channel = MethodChannel('pro.kaleert.nextlink/vpn');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'isRunning' ? false : null,
    );
    final container = ProviderContainer();
    addTearDown(() {
      container.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
    await container.read(chainsProvider.notifier).ready;
    await container.read(subscriptionProvider.notifier).ready;
    container.read(vpnProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    Future<void> emit(String key, int revision) async {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onVpnState', {
            'status': 'connected',
            'serverName': 'Two hops',
            'serverKey': key,
            'sessionId': 'vpn',
            'elapsedMilliseconds': 12000,
            'revision': revision,
          }),
        ),
        (_) => done.complete(),
      );
      await done.future;
    }

    await emit('chain:chain-test', 1);
    expect(container.read(chainsProvider).single.isActive, true);
    expect(
      container.read(subscriptionProvider).single.servers.last.isActive,
      false,
    );
    await emit(last.uniqueKey, 2);
    expect(container.read(chainsProvider).single.isActive, false);
    expect(
      container.read(subscriptionProvider).single.servers.last.isActive,
      true,
    );
  });
}
