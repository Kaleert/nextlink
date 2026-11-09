import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/core/theme/theme_provider.dart';
import 'package:nextlink/screens/theme_live_editor.dart';
import 'package:nextlink/shared/widgets/theme_region.dart';
import 'package:nextlink/shared/widgets/theme_edit_session.dart';

void main() {
  testWidgets(
    'live drag is undoable, cannot activate real controls, and only saves a draft',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      if (Platform.environment.containsKey('NEXTLINK_THEME_SCREENSHOT')) {
        await tester.runAsync(() async {
          final fonts = FontLoader('Nunito')
            ..addFont(rootBundle.load('assets/fonts/Nunito-400.ttf'));
          await fonts.load();
        });
      }
      tester.view.physicalSize = const Size(420, 860);
      addTearDown(tester.view.resetPhysicalSize);
      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith(
            (ref) => ThemeNotifier.preview(ThemeConfig(name: 'Original')),
          ),
        ],
      );
      addTearDown(container.dispose);
      var presses = 0;
      ThemeConfig? result;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.push<ThemeConfig>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemeLiveEditor(
                          theme: ThemeConfig(name: 'Draft'),
                          screenBuilder: (_) => Scaffold(
                            body: Center(
                              child: ThemeRegion.auto(
                                id: 'widget_action',
                                child: FilledButton(
                                  onPressed: () => presses++,
                                  child: const Text('Actual action'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final region = find.byWidgetPredicate(
        (w) => w is ThemeRegion && w.id == 'widget_action',
      );
      final point = tester.getCenter(region);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(presses, 0);
      final scope = tester.widget<ThemeEditingScope>(
        find.byType(ThemeEditingScope),
      );
      expect(scope.session.selected, 'widget_action');
      if (Platform.environment['NEXTLINK_THEME_SCREENSHOT']
          case final String path) {
        await tester.runAsync(() async {
          final layer =
              tester.binding.renderViews.first.debugLayer! as OffsetLayer;
          final image = await layer.toImage(
            const Rect.fromLTWH(0, 0, 420, 860),
          );
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(path).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.dragFrom(tester.getCenter(region), const Offset(24, 15));
      await tester.pumpAndSettle();
      expect(
        scope.session.theme.offsetFor('widget_action').distance,
        greaterThan(5),
      );
      expect(presses, 0);
      await tester.tap(find.byTooltip('Отменить изменение'));
      await tester.pumpAndSettle();
      expect(scope.session.theme.offsetFor('widget_action'), Offset.zero);
      await tester.tap(find.byTooltip('Повторить изменение'));
      await tester.pumpAndSettle();
      expect(
        scope.session.theme.offsetFor('widget_action').distance,
        greaterThan(5),
      );
      await tester.tap(find.text('Нажимать'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(region));
      await tester.pumpAndSettle();
      expect(presses, 1);
      await tester.tap(find.text('Редактировать'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(region));
      await tester.pumpAndSettle();
      expect(presses, 1);
      await tester.tap(find.byTooltip('Принять в черновик'));
      await tester.pumpAndSettle();
      expect(result!.componentOffsets, isNotEmpty);
      expect(container.read(themeProvider).currentTheme.name, 'Original');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'interaction opens a nested dialog and editing can select its content',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 860);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ThemeLiveEditor(
              theme: ThemeConfig(name: 'Draft'),
              screenBuilder: (_) => Scaffold(
                body: Builder(
                  builder: (context) => ExpansionTile(
                    title: const Text('Section'),
                    children: [
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          useRootNavigator: false,
                          builder: (_) => const AlertDialog(
                            content: ThemeRegion.auto(
                              id: 'dialog_text',
                              child: Text('Dialog content'),
                            ),
                          ),
                        ),
                        child: const Text('Open dialog'),
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
      await tester.tap(find.text('Нажимать'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Section'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog content'), findsOneWidget);
      await tester.tap(find.text('Редактировать'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.text('Dialog content')));
      await tester.pumpAndSettle();
      final scope = tester.widget<ThemeEditingScope>(
        find.byType(ThemeEditingScope),
      );
      expect(scope.session.selected, 'dialog_text');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'layout reordering preserves button actions and text overrides round trip',
    (tester) async {
      var action = '';
      final config = ThemeConfig(
        name: 'Reordered',
        layoutOrders: {
          'group': ['second', 'first'],
        },
        componentTexts: {'first_label': 'Changed'},
      );
      final restored = ThemeConfig.fromMap(config.toMap());
      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith((ref) => ThemeNotifier.preview(restored)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeRegion(
                id: 'group',
                child: Row(
                  children: [
                    ThemeRegion(
                      id: 'first',
                      child: TextButton(
                        onPressed: () => action = 'first',
                        child: const ThemeRegion(
                          id: 'first_label',
                          child: Text('First'),
                        ),
                      ),
                    ),
                    ThemeRegion(
                      id: 'second',
                      child: TextButton(
                        onPressed: () => action = 'second',
                        child: const Text('Second'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Second')).dx,
        lessThan(tester.getTopLeft(find.text('Changed')).dx),
      );
      await tester.tap(find.text('Second'));
      expect(action, 'second');
      expect(restored.componentTexts['first_label'], 'Changed');
      expect(tester.takeException(), isNull);
    },
  );
}
