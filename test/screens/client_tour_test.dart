import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/localization/app_localizations.dart';
import 'package:nextlink/main.dart';
import 'package:nextlink/screens/client_tour_screen.dart';
import 'package:nextlink/screens/profiles_screen.dart';
import 'package:nextlink/screens/subscriptions_screen.dart';
import 'package:nextlink/shared/widgets/tour_anchor.dart';

/// Real screens need the same localization delegates as the application.
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

Future<Widget> _app(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> prefs = const {},
  bool disableAnimations = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final loc = AppLocalizations(const Locale('ru'));
  await tester.runAsync(() => loc.load());
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: [
        _CachedLocalizationsDelegate(loc),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: home,
    ),
  );
}

class _Launcher extends StatelessWidget {
  const _Launcher({required this.replay});
  final bool replay;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () =>
          replay ? ClientTour.show(context) : ClientTour.maybeShow(context),
      child: const Text('Open'),
    ),
  );
}

const _cardKey = ValueKey('tour-card');

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> prefs = const {},
}) async {
  await tester.pumpWidget(await _app(tester, home, prefs: prefs));
  // Let the localization delegate resolve before the first interaction.
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets(
    'first run starts with the globe, skips steps, goes back and never repeats',
    (tester) async {
      await _pump(tester, const _Launcher(replay: false));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Серверы на глобусе'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tour-skip-step')));
      await tester.pumpAndSettle();
      expect(find.text('Цепочки прямо на карте'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getInt(ClientTour.progressKey),
        1,
      );
      await tester.tap(find.byKey(const ValueKey('tour-back')));
      await tester.pumpAndSettle();
      expect(find.text('Серверы на глобусе'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tour-skip-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(_cardKey), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          ClientTour.completedKey,
        ),
        true,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(_cardKey), findsNothing);
    },
  );

  testWidgets(
    'resume and finish; manual replay starts from the beginning on a narrow screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pump(
        tester,
        const _Launcher(replay: false),
        prefs: {ClientTour.progressKey: ClientTour.steps.length - 2},
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text(ClientTour.steps[ClientTour.steps.length - 2].title),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pumpAndSettle();
      expect(find.text(ClientTour.steps.last.title), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(_cardKey), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          ClientTour.completedKey,
        ),
        true,
      );
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          ClientTour.progressKey,
        ),
        false,
      );
      await _pump(tester, const _Launcher(replay: true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Серверы на глобусе'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tour-skip-all')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every home step highlights a real control', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _pump(
      tester,
      const HomeScreen(),
      prefs: {ClientTour.completedKey: true},
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    for (final step in ClientTour.steps.where((s) => s.scene == 'home')) {
      final rect = TourAnchor.rect(step.target);
      if (step.target == 'widget_globe_controls_20' && rect == null) continue;
      expect(rect, isNotNull, reason: step.target);
      expect(rect!.isEmpty, isFalse, reason: step.target);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile and subscription steps highlight real controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _pump(tester, const ProfilesScreen());
    await tester.pump(const Duration(milliseconds: 300));
    expect(TourAnchor.rect('widget_profiles_screen_9'), isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await _pump(tester, const SubscriptionsScreen());
    await tester.pump(const Duration(milliseconds: 300));
    expect(TourAnchor.rect('widget_subscriptions_screen_49'), isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hint card never covers the highlighted control', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _pump(tester, const HomeScreen());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(_cardKey), findsOneWidget);
    for (var i = 0; i < ClientTour.steps.length; i++) {
      final step = ClientTour.steps[i];
      await tester.pump(const Duration(milliseconds: 200));
      final card = tester.getRect(find.byKey(_cardKey));
      final highlight = find.byKey(ValueKey('coach-target-${step.target}'));
      if (highlight.evaluate().isNotEmpty) {
        final target = tester.getRect(highlight);
        expect(
          card.intersect(target).isEmpty,
          isTrue,
          reason: '${step.target} is covered by the hint card',
        );
      }
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(_cardKey), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
