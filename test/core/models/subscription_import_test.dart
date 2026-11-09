import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';
import 'package:nextlink/core/utils/imported_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('JSON file classification distinguishes WARP from themes', () {
    expect(
      isThemeDocument(jsonEncode({'private_key': 'key', 'type': 'wireguard'})),
      false,
    );
    expect(
      isThemeDocument(jsonEncode({'outbounds': [], 'primary': '#123456'})),
      false,
    );
    expect(
      isThemeDocument(
        jsonEncode({
          'theme': {'primary': '#123456'},
        }),
      ),
      true,
    );
    expect(isThemeDocument('\uFEFF{"background":"#000000"}'), true);
    expect(isBackupDocument('{"format":"nextlink-backup","version":1}'), true);
    expect(isBackupDocument('{"type":"wireguard"}'), false);
  });
  test(
    'file import creates missing manual section and awaits persistence',
    () async {
      SharedPreferences.setMockInitialValues({'saved_subscriptions': '[]'});
      final container = ProviderContainer();
      final notifier = container.read(subscriptionProvider.notifier);
      final key = base64Encode(List.filled(32, 7));
      final configs = ProxyParser.parseSubscription(
        jsonEncode({
          'type': 'wireguard',
          'private_key': key,
          'local_address': ['172.16.0.2/32'],
          'peer_public_key': key,
          'server': 'engage.cloudflareclient.com',
          'server_port': 2408,
          'reserved': [1, 2, 3],
        }),
      );
      // Deliberately import before the initial subscription load finishes.
      expect(await notifier.addManualConfigs(configs), 1);
      expect(
        container.read(subscriptionProvider).single.servers.single.protocol,
        'WARP',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(
          prefs.getString('saved_subscriptions')!,
        ) as List).single['servers'],
        isNotEmpty,
      );
      expect(await notifier.addManualConfigs(configs), 0);
      container.dispose();
    },
  );
}
