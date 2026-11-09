import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/shared/widgets/custom_theme_elements.dart';

void main() {
  testWidgets(
    'screen selection and visibility apply to custom controls and their actions',
    (tester) async {
      var taps = 0;
      final theme = ThemeConfig.defaultTheme.copyWith(
        customElements: [
          {'id': 'home', 'label': 'Home only', 'action': 'toggle'},
          {
            'id': 'settings',
            'screen': 'screen_settings',
            'type': 'card',
            'label': 'My settings',
            'action': 'url',
            'gradient': true,
          },
          {
            'id': 'hidden',
            'screen': 'screen_settings',
            'type': 'text',
            'label': 'Hidden',
          },
          {
            'id': 'space',
            'screen': 'screen_settings',
            'type': 'spacer',
            'height': 12,
          },
        ],
        hiddenElements: ['custom_hidden'],
        componentColors: {'custom_settings': 0xFFFF0000},
        componentRadii: {'custom_settings': 5},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomThemeElements(
              theme: theme,
              screen: 'screen_settings',
              onAction: (e) async {
                taps++;
              },
            ),
          ),
        ),
      );
      expect(find.text('Home only'), findsNothing);
      expect(find.text('Hidden'), findsNothing);
      await tester.tap(find.text('My settings'));
      expect(taps, 1);
      expect(
        tester.widget<Text>(find.text('My settings')).style!.color,
        const Color(0xFFFF0000),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
