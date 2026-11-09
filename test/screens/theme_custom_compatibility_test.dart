import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/screens/theme_custom_element_dialog.dart';

void main() {
  for (final type in ['divider', 'spacer']) {
    testWidgets('legacy $type opens and saves without losing old attributes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? result;
      final old = <String, dynamic>{
        'id': 'old',
        'type': type,
        'label': '',
        'height': 17.5,
        'radius': 9,
        'gradient': true,
        'screen': 'home',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => ThemeCustomElementDialog(element: old),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(result!['type'], type);
      expect(result!['height'], 17.5);
      expect(result!['radius'], 9);
      expect(result!['screen'], 'home');
      expect(result!['action'], 'none');
    });
  }
  testWidgets(
    'unknown imported types and actions have safe editor selections',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ThemeCustomElementDialog(
            element: {
              'id': 'x',
              'type': 'old-addon',
              'action': 'obsolete',
              'label': 'Imported',
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final fields = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      expect(fields[0].initialValue, 'button');
      expect(fields[1].initialValue, 'none');
    },
  );
}
