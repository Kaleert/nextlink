import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/core/theme/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Neon Origami is available after restart and as an importable file',
    () async {
      SharedPreferences.setMockInitialValues({
        'current_theme_name': 'theme_neon_origami',
      });
      final notifier = ThemeNotifier();
      await notifier.ensureLoaded();
      expect(notifier.state.currentTheme.name, 'theme_neon_origami');
      expect(notifier.state.currentTheme.isBuiltIn, isTrue);
      expect(
        notifier.state.currentTheme.componentMotions['home_app_title'],
        'float',
      );
      final imported = ThemeConfig.fromMap(
        jsonDecode(File('Neon_Origami.nlt').readAsStringSync()),
      );
      expect(imported.primary, ThemeConfig.neonOrigami.primary);
      expect(
        imported.colorFor('home_power_button'),
        ThemeConfig.neonOrigami.colorFor('home_power_button'),
      );
      expect(
        1.05 /
            (imported.colorFor('home_power_button').computeLuminance() + .05),
        greaterThan(4.5),
      );
      expect(imported.glassOpacity, ThemeConfig.neonOrigami.glassOpacity);
      expect(imported.isBuiltIn, isFalse);
      notifier.dispose();
    },
  );
}
