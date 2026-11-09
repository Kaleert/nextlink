import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/utils/app_backup.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/core/providers/profiles_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'backup round trip preserves profiles, groups, custom themes and settings',
    () async {
      final profile = AppProfile(
        id: 'group',
        name: 'Рабочие',
        triggers: ['wifi', 'timeout'],
        serverKeys: ['a', 'b'],
        isEnabled: true,
      );
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({
          'autoUpdateCores': false,
          'pingUrl': 'https://example.org/',
        }),
        'saved_app_profiles': jsonEncode([profile.toMap()]),
        'custom_themes': jsonEncode([
          ThemeConfig(
            name: 'Custom',
            author: 'Me',
            componentOffsets: {},
          ).toMap(),
        ]),
        'current_theme_name': 'Custom',
      });
      final json = await AppBackup.export();
      final data = AppBackup.validate(json);
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await AppBackup.restore(data);
      expect(
        jsonDecode(prefs.getString('app_settings')!)['pingUrl'],
        'https://example.org/',
      );
      final restored = AppProfile.fromMap(
        jsonDecode(prefs.getString('saved_app_profiles')!)[0],
      );
      expect(restored.serverKeys, ['a', 'b']);
      expect(restored.triggers, ['wifi', 'timeout']);
      expect(restored.isEnabled, true);
      expect(prefs.getString('current_theme_name'), 'Custom');
    },
  );
  test('invalid backups cannot partially overwrite settings', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings': '{"pingUrl":"original"}',
    });
    final good = jsonDecode(await AppBackup.export()) as Map<String, dynamic>;
    good['profiles'] = 'corrupt';
    await expectLater(AppBackup.restore(good), throwsFormatException);
    expect(
      (await SharedPreferences.getInstance()).getString('app_settings'),
      '{"pingUrl":"original"}',
    );
    expect(
      () => AppBackup.validate('{"format":"other","version":1}'),
      throwsFormatException,
    );
  });
}
