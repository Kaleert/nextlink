import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/providers/profiles_provider.dart';
import 'package:nextlink/screens/profiles_screen.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'create, enable, edit, cancel and delete an independent profile',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      await container.read(profilesProvider.notifier).ready;
      final reserve = ProxyParser.parse(
        'vless://00000000-0000-0000-0000-000000000001@reserve.example:443#Reserve',
      );
      await container.read(subscriptionProvider.notifier).addManualConfigs([
        reserve,
      ]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfilesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Основной'), findsNothing);
      await tester.tap(find.byTooltip('Добавить профиль'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextFormField).first, 'Wi-Fi дома');
      await tester.tap(find.text('Подключение к Wi-Fi'));
      final groupSwitch = find.widgetWithText(SwitchListTile, 'Reserve');
      await tester.ensureVisible(groupSwitch);
      await tester.tap(groupSwitch);
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(container.read(profilesProvider).single.name, 'Wi-Fi дома');
      expect(container.read(profilesProvider).single.isEnabled, false);
      expect(container.read(profilesProvider).single.serverKeys, [
        reserve.uniqueKey,
      ]);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(container.read(profilesProvider).single.isEnabled, true);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Новое имя');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(container.read(profilesProvider).single.name, 'Новое имя');
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Удалить профиль'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(container.read(profilesProvider), isEmpty);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
