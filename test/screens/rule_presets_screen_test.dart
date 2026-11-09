import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/localization/app_localizations.dart';
import 'package:nextlink/core/providers/rules_provider.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/screens/rules_screen.dart';

class _Locale extends LocalizationsDelegate<AppLocalizations> {
  final AppLocalizations value;
  const _Locale(this.value);
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(value);
  @override
  bool shouldReload(_Locale old) => false;
}

void main() {
  testWidgets('preset preview applies after confirmation and enables routing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final loc = AppLocalizations(const Locale('en'));
    await tester.runAsync(() => loc.load());
    final container = ProviderContainer();
    await container.read(rulesProvider.notifier).ready;
    await container.read(settingsProvider.notifier).ready;
    container
        .read(settingsProvider.notifier)
        .update(container.read(settingsProvider).copyWith(useRouting: false));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: [_Locale(loc)],
          home: const RulesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rule presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RU direct'));
    await tester.pumpAndSettle();
    expect(container.read(rulesProvider), isEmpty);
    expect(find.textContaining('xn--p1ai'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(container.read(rulesProvider), hasLength(2));
    expect(container.read(settingsProvider).useRouting, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
