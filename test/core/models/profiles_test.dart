import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/providers/profiles_provider.dart';
import 'package:nextlink/core/utils/profile_timer_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/utils/proxy_runtime.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';

void main() {
  test(
    'runtime TLS defaults preserve the saved server identity used by groups',
    () {
      final source = ProxyParser.parse(
        'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Server',
      );
      final key = source.uniqueKey;
      final runtime = proxyWithFallbackFingerprint(source, 'firefox');
      expect(source.uniqueKey, key);
      expect(source.fp, isEmpty);
      expect(runtime.fp, 'firefox');
      expect(
        AppProfile(id: 'p', name: 'Group', serverKeys: [key]).serverKeys.single,
        source.uniqueKey,
      );
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'empty profile list persists and no default profile reappears',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = ProfilesNotifier();
      await notifier.addProfile(
        AppProfile(id: 'a', name: 'A', triggers: ['wifi']),
      );
      await notifier.removeProfile('a');
      notifier.dispose();
      final restored = ProfilesNotifier();
      await restored.ready;
      expect(restored.state, isEmpty);
      restored.dispose();
    },
  );
  test(
    'migrates the untouched default and preserves user automations',
    () async {
      SharedPreferences.setMockInitialValues({
        'saved_app_profiles': jsonEncode([
          {'id': '1', 'name': 'Основной', 'trigger': 'manual_trigger'},
          {
            'id': '2',
            'name': 'Мой',
            'isActive': true,
            'isEnabled': true,
            'triggers': ['wifi', 'quick_tile'],
          },
        ]),
      });
      final notifier = ProfilesNotifier();
      await notifier.ready;
      expect(notifier.state.single.name, 'Мой');
      expect(notifier.state.single.triggers, ['wifi']);
      expect(notifier.state.single.isEnabled, true);
      expect(notifier.state.single.toMap().containsKey('isActive'), false);
      notifier.dispose();
    },
  );
  test(
    'multiple enabled timers fire independently and disabled ones reset',
    () {
      final schedule = ProfileTimerSchedule();
      final start = DateTime(2026, 11, 5);
      final a = AppProfile(
        id: 'a',
        name: 'A',
        triggers: ['timer'],
        isEnabled: true,
        intervalMinutes: 1,
      );
      final b = AppProfile(
        id: 'b',
        name: 'B',
        triggers: ['timer'],
        isEnabled: true,
        intervalMinutes: 2,
      );
      final profiles = [a, b];
      expect(schedule.nextDue(profiles, connected: true, now: start), isNull);
      expect(
        schedule
            .nextDue(
              profiles,
              connected: true,
              now: start.add(const Duration(minutes: 1)),
            )
            ?.id,
        'a',
      );
      expect(
        schedule
            .nextDue(
              profiles,
              connected: true,
              now: start.add(const Duration(minutes: 2)),
            )
            ?.id,
        'a',
      );
      expect(
        schedule
            .nextDue(
              profiles,
              connected: true,
              now: start.add(const Duration(minutes: 2, seconds: 1)),
            )
            ?.id,
        'b',
      );
      expect(
        schedule.nextDue(
          [a.copyWith(isEnabled: false), b],
          connected: true,
          now: start.add(const Duration(minutes: 2, seconds: 2)),
        ),
        isNull,
      );
      expect(
        schedule.nextDue(
          profiles,
          connected: true,
          now: start.add(const Duration(minutes: 3)),
        ),
        isNull,
      );
    },
  );
}
