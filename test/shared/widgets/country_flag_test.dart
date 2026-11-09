import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nextlink/core/utils/country_flag_assets.dart';
import 'package:nextlink/core/models/theme_config.dart';
import 'package:nextlink/core/theme/theme_provider.dart';
import 'package:nextlink/shared/widgets/country_flag.dart';
import 'package:nextlink/shared/widgets/theme_region.dart';
import 'package:nextlink/shared/widgets/custom_theme_elements.dart';

void main() {
  test('every supported flag has a bundled 96x72 PNG', () {
    for (final code in CountryFlagAssets.codes) {
      final bytes = File(CountryFlagAssets.path(code)!).readAsBytesSync();
      expect(bytes.take(8).toList(), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ], reason: code);
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(16), 96, reason: code);
      expect(header.getUint32(20), 72, reason: code);
    }
    expect(CountryFlagAssets.path('../ru'), isNull);
    expect(CountryFlagAssets.path('ZZ'), isNull);
  });
  testWidgets(
    'server flag characters become images without being tinted by the theme',
    (tester) async {
      final theme = ThemeConfig.defaultTheme.copyWith(
        componentColors: {'server': 0xff00ff00},
      );
      const name = '🇬🇧 London / 🇫🇮 Helsinki';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeProvider.overrideWith((_) => ThemeNotifier.preview(theme)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ThemeRegion(
                id: 'server',
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CountryFlagImage), findsNWidgets(2));
      final codes = tester
          .widgetList<CountryFlagImage>(find.byType(CountryFlagImage))
          .map((f) => f.countryCode);
      expect(codes, ['GB', 'FI']);
      for (final flag in find.byType(CountryFlagImage).evaluate()) {
        final filters = <Widget>[];
        flag.visitAncestorElements((element) {
          if (element.widget is ColorFiltered) filters.add(element.widget);
          return true;
        });
        expect(filters, isEmpty);
      }
      final rich = tester.widget<Text>(
        find
            .descendant(of: find.byType(FlagText), matching: find.byType(Text))
            .last,
      );
      expect(rich.maxLines, 1);
      expect(rich.overflow, TextOverflow.ellipsis);
      expect(rich.semanticsLabel, name);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dynamic flag and server variables in a theme use images too', (
    tester,
  ) async {
    final theme = ThemeConfig.defaultTheme.copyWith(
      customElements: [
        {'id': 'ip', 'type': 'text', 'label': '{{flag}} {{ip}} · {{server}}'},
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomThemeElements(
            theme: theme,
            variables: const {
              'flag': '🇷🇺',
              'ip': '192.0.2.1',
              'server': '🇬🇧 London',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CountryFlagImage), findsNWidgets(2));
    expect(find.byType(Image), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
