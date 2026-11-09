import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pro.kaleert.nextlink/vpn');
  Future<void> emit(Map<String, dynamic> value) async {
    final completed = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onVpnState', value),
          ),
          (_) => completed.complete(),
        );
    await completed.future;
  }

  test(
    'native notification events reconcile UI, pause, timer and stale messages',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({'autoUpdateCores': false}),
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'isRunning' ? false : null,
          );
      final container = ProviderContainer();
      addTearDown(() {
        container.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      container.read(vpnProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await emit({
        'status': 'connected',
        'serverName': 'Tile server',
        'elapsedSeconds': 14,
        'revision': 2,
      });
      expect(container.read(vpnProvider).status, VpnState.connected);
      expect(container.read(vpnProvider).serviceServerName, 'Tile server');
      expect(container.read(vpnProvider).connectedSeconds, 14);
      await emit({
        'status': 'paused',
        'serverName': 'Tile server',
        'elapsedSeconds': 14,
        'revision': 3,
      });
      expect(container.read(vpnProvider).status, VpnState.paused);
      await emit({'status': 'connected', 'elapsedSeconds': 15, 'revision': 2});
      expect(container.read(vpnProvider).status, VpnState.paused);
      await emit({'status': 'stopped', 'elapsedSeconds': 14, 'revision': 4});
      expect(container.read(vpnProvider).status, VpnState.disconnected);
      expect(container.read(vpnProvider).connectedSeconds, 0);
    },
  );
}
