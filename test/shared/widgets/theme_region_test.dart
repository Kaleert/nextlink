import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/core/theme/theme_provider.dart';
import 'package:nextlink/shared/widgets/theme_region.dart';

void main() {
  testWidgets(
    'hidden screen content can be restored without resetting the theme',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      final notifier = container.read(themeProvider.notifier);
      await notifier.ensureLoaded();
      notifier.setTheme(
        ThemeConfig(name: 'My theme', hiddenElements: ['screen_apps']),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: ThemeRegion(id: 'screen_apps', child: Text('Applications')),
            ),
          ),
        ),
      );
      expect(find.text('Applications'), findsNothing);
      await tester.tap(find.text('Показать скрытое содержимое'));
      await tester.pumpAndSettle();
      expect(find.text('Applications'), findsOneWidget);
      expect(container.read(themeProvider).currentTheme.name, 'My theme');
      expect(
        container.read(themeProvider).currentTheme.hiddenElements,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
  test(
    'named region IDs persist across visits and support Cyrillic labels',
    () {
      final first = ThemeRegionRegistry.named(
        'settings_row',
        'Скорость анимации',
      );
      expect(
        ThemeRegionRegistry.named('settings_row', 'Скорость анимации'),
        first,
      );
      expect(ThemeRegionRegistry.labels[first], 'Скорость анимации');
    },
  );
  test('preview theme changes never alter saved theme selection', () async {
    SharedPreferences.setMockInitialValues({'current_theme_name': 'Original'});
    final preview = ThemeNotifier.preview(ThemeConfig(name: 'Draft'));
    await preview.ensureLoaded();
    preview.setTheme(ThemeConfig(name: 'Changed draft'));
    await Future<void>.delayed(Duration.zero);
    expect(
      (await SharedPreferences.getInstance()).getString('current_theme_name'),
      'Original',
    );
    preview.dispose();
  });
}
