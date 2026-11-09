import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/core/providers/server_locations_provider.dart';
import 'package:nextlink/screens/theme_live_editor.dart';
import 'package:nextlink/shared/widgets/theme_edit_session.dart';
import 'package:nextlink/shared/widgets/theme_region.dart';
import 'package:nextlink/shared/widgets/server_globe.dart';

void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 860);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets(
    'arrows cycle overlapping layers and the selected name describes its content',
    (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ThemeLiveEditor(
              theme: ThemeConfig(name: 'Test'),
              screenBuilder: (_) => Scaffold(
                body: ThemeRegion(
                  id: 'screen_home',
                  label: 'Главный экран',
                  canvas: true,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: Colors.black),
                      ),
                      Center(
                        child: ThemeRegion.auto(
                          id: 'card',
                          label: 'Container · fixture.dart',
                          child: Container(
                            width: 180,
                            height: 100,
                            color: Colors.black,
                            child: const Center(child: Text('Мои подписки')),
                          ),
                        ),
                      ),
                      Center(
                        child: ThemeRegion(
                          id: 'action',
                          label: 'Открыть подписки',
                          child: IconButton(
                            tooltip: 'Открыть подписки',
                            onPressed: () {},
                            icon: const Icon(Icons.subscriptions),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byTooltip('Открыть подписки')));
      await tester.pumpAndSettle();
      final session = tester
          .widget<ThemeEditingScope>(find.byType(ThemeEditingScope))
          .session;
      expect(session.selected, 'action');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('selected-theme-layer')))
            .data,
        'Открыть подписки',
      );
      await tester.tap(find.byTooltip('Следующий слой'));
      await tester.pumpAndSettle();
      expect(session.nodes[session.selected]?.sourceId, 'card');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('selected-theme-layer')))
            .data,
        contains('Мои подписки'),
      );
      await tester.tap(find.byTooltip('Следующий слой'));
      await tester.pumpAndSettle();
      expect(session.selected, 'screen_home');
      await tester.tap(find.byTooltip('Предыдущий слой'));
      await tester.pumpAndSettle();
      expect(session.nodes[session.selected]?.sourceId, 'card');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'map button is selectable separately from the full-screen map background',
    (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          serverLocationsProvider.overrideWith((ref) => Stream.value({})),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ThemeLiveEditor(
              theme: ThemeConfig(name: 'Test'),
              screenBuilder: (_) =>
                  const Scaffold(body: ServerGlobe(fullScreen: true)),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byTooltip('Приблизить')));
      await tester.pumpAndSettle();
      final session = tester
          .widget<ThemeEditingScope>(find.byType(ThemeEditingScope))
          .session;
      final selected = session.nodes[session.selected]!;
      expect(selected.id, isNot('home_map_canvas'));
      expect(selected.isCanvas, false);
      expect(selected.label, contains('Приблизить'));
      expect(selected.rect(session.theme)!.width, lessThan(80));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
