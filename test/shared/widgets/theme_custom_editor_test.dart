import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/core/theme/theme_provider.dart';
import 'package:nextlink/shared/widgets/theme_edit_session.dart';
import 'package:nextlink/shared/widgets/theme_region.dart';
import 'package:nextlink/shared/widgets/custom_theme_elements.dart';
import 'package:nextlink/shared/widgets/theme_image_background.dart';
import 'package:nextlink/shared/widgets/theme_motion.dart';
import 'package:nextlink/screens/theme_live_editor.dart';

void main() {
  testWidgets(
    'create an overlay button in the canvas, assign an action, and lock canvas dragging',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      Map<String, dynamic>? action;
      final previous = ThemeActionRegistry.run;
      ThemeActionRegistry.run = (element) async {
        action = element;
      };
      addTearDown(() => ThemeActionRegistry.run = previous);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ThemeLiveEditor(
              theme: ThemeConfig(name: 'Draft'),
              screenBuilder: (_) => const Scaffold(
                body: ThemeRegion(
                  id: 'screen_settings',
                  child: Stack(
                    fit: StackFit.expand,
                    children: [ColoredBox(color: Colors.black)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Главная'), findsNothing);
      final session = tester
          .widget<ThemeEditingScope>(find.byType(ThemeEditingScope))
          .session;
      session.select('screen_settings');
      session.beginGesture();
      session.drag(const Offset(100, 200), const Offset(120, 240));
      session.endGesture();
      expect(session.theme.componentOffsets, isEmpty);
      await tester.tap(find.text('Добавить элемент'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My VPN button');
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(session.theme.customElements, hasLength(1));
      expect(session.theme.customElements.single['screen'], 'screen_settings');
      final button = find.text('My VPN button');
      expect(button, findsWidgets);
      expect(find.byType(CustomThemeElements), findsWidgets);
      await tester.tap(find.text('Нажимать'));
      await tester.pumpAndSettle();
      await tester.tap(button.first);
      await tester.pumpAndSettle();
      expect(action?['action'], 'toggle');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dynamic labels update and portable backgrounds survive theme JSON',
    (tester) async {
      // One transparent PNG, embedded in the theme instead of a device-specific path.
      const data =
          'iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nGM4kfJ/QBDDqMWjFo9aPGrxqMWjFo9aPGrxyLEYAN+uxrvl7yUGAAAAAElFTkSuQmCC';
      final theme = ThemeConfig.fromMap(
        jsonDecode(
          jsonEncode(
            ThemeConfig(
              name: 'Portable',
              customElements: [
                {
                  'id': 'status',
                  'label': 'VPN {{vpn}} / {{timer}}',
                  'type': 'card',
                },
              ],
              componentBackgrounds: {
                'custom_status': {'data': data},
              },
              componentMotions: {'custom_status': 'pulse'},
            ).toMap(),
          ),
        ),
      );
      Widget view(String time) => MaterialApp(
        home: Scaffold(
          body: CustomThemeElements(
            theme: theme,
            variables: {'vpn': 'ON', 'timer': time},
          ),
        ),
      );
      await tester.pumpWidget(view('00:01'));
      await tester.pump();
      expect(find.text('VPN ON / 00:01'), findsOneWidget);
      expect(find.byType(ThemeImageBackground), findsOneWidget);
      expect(find.byType(ThemeMotion), findsOneWidget);
      await tester.pumpWidget(view('00:02'));
      await tester.pump();
      expect(find.text('VPN ON / 00:02'), findsOneWidget);
      expect(theme.componentBackgrounds['custom_status']!['data'], data);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('RGB channels show exact numbers and can be selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ThemeColorPalette(initial: Color(0xff123456))),
    );
    expect(find.text('R'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('52'), findsOneWidget);
    expect(find.text('86'), findsOneWidget);
    expect(find.text('#123456'), findsOneWidget);
  });
}
