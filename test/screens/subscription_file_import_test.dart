import 'dart:async';

import 'package:nextlink/screens/qr_import_screen.dart';
import 'package:nextlink/core/utils/config_share_payload.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/localization/app_localizations.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/screens/subscriptions_screen.dart';

class _LocaleDelegate extends LocalizationsDelegate<AppLocalizations> {
  final AppLocalizations value;
  const _LocaleDelegate(this.value);
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(value);
  @override
  bool shouldReload(_LocaleDelegate old) => false;
}

void main() {
  testWidgets('file import survives closing add menu and reports saved WARP', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'saved_subscriptions': '[]'});
    final loc = AppLocalizations(const Locale('en'));
    await tester.runAsync(() => loc.load());
    const channel = MethodChannel('pro.kaleert.nextlink/theme_files');
    final file = Completer<Map<String, dynamic>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'pickConfigFile');
      return file.future;
    });
    final container = ProviderContainer();
    await container.read(subscriptionProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: [_LocaleDelegate(loc)],
          home: const SubscriptionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Import .conf / .json (WireGuard, WARP, AmneziaWG)'),
    );
    await tester.pumpAndSettle();
    final key = base64Encode(List.filled(32, 7));
    file.complete({
      'name': 'warp.json',
      'contents': jsonEncode({
        'type': 'wireguard',
        'private_key': key,
        'local_address': ['172.16.0.2/32'],
        'peer_public_key': key,
        'server': 'engage.cloudflareclient.com',
        'server_port': 2408,
        'reserved': [1, 2, 3],
      }),
    });
    await tester.pumpAndSettle();
    expect(
      container.read(subscriptionProvider).single.servers.single.protocol,
      'WARP',
    );
    expect(find.text('Configurations added: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
  testWidgets('QR route imports its result after the add dialog is closed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'saved_subscriptions': '[]'});
    final loc = AppLocalizations(const Locale('en'));
    await tester.runAsync(() => loc.load());
    final container = ProviderContainer();
    await container.read(subscriptionProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: [_LocaleDelegate(loc)],
          home: const SubscriptionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Via QR code'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImportScreen), findsOneWidget);
    final link =
        'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#QR%20Imported';
    Navigator.of(tester.element(find.byType(QrImportScreen)))
        .pop(ConfigSharePayload.importLink(link));
    await tester.pumpAndSettle();
    expect(
      container.read(subscriptionProvider).single.servers.single.name,
      'QR Imported',
    );
    expect(find.text('Configurations added: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
