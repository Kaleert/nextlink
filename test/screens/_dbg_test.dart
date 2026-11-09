import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/localization/app_localizations.dart';
import 'package:nextlink/screens/client_tour_screen.dart';

class _CachedLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _CachedLocalizationsDelegate(this.instance);
  final AppLocalizations instance;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) async => instance;
  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

void main() {
  testWidgets('debug overlay', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final loc = AppLocalizations(const Locale('ru'));
    await tester.runAsync(() => loc.load());
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [
            _CachedLocalizationsDelegate(loc),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: TextButton(
              onPressed: () {
                final n = Navigator.of(
                  tester.element(find.text('Open')),
                  rootNavigator: true,
                );
                n.overlay!.insert(
                  OverlayEntry(builder: (_) => const Text('PLAIN')),
                );
                ClientTour.show(
                  tester.element(find.text('Open')),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    debugPrint('DBG before any=${find.byWidgetPredicate((w) => true).evaluate().length} material=${find.byType(Material).evaluate().length}');
    await tester.tap(find.text('Open'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint(
      'DBG overlay=${find.byType(Overlay).evaluate().length} material=${find.byType(Material).evaluate().length} '
      'exc=${tester.takeException()} '
      'any=${find.byWidgetPredicate((w) => true).evaluate().length}',
    );
    final nav = Navigator.of(tester.element(find.text('Open')), rootNavigator: true);
    debugPrint('DBG overlayState=${nav.overlay}');
    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    debugPrint('DBG texts=$texts');
  });
}
