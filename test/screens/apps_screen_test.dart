import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/localization/app_localizations.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/screens/apps_screen.dart';
import 'package:nextlink/shared/widgets/app_route_selector.dart';
import 'package:nextlink/shared/widgets/app_progress_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> app(String name) => {
  'name': name,
  'package': 'test.${name.toLowerCase()}',
  'icon': Uint8List(0),
};

class _TestLocalizations extends LocalizationsDelegate<AppLocalizations> {
  final AppLocalizations value;
  const _TestLocalizations(this.value);
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(value);
  @override
  bool shouldReload(_TestLocalizations old) => false;
}

void main() {
  const channel = MethodChannel('pro.kaleert.nextlink/apps');
  testWidgets('first app batch is usable before remaining apps arrive', (
    tester,
  ) async {
    final loc = AppLocalizations(const Locale('en'));
    await tester.runAsync(() => loc.load());
    SharedPreferences.setMockInitialValues({});
    final nextPage = Completer<Map<String, dynamic>>();
    final offsets = <int>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'getInstalledAppsPage');
      expect(call.arguments['limit'], 24);
      offsets.add(call.arguments['offset'] as int);
      if (offsets.length == 1)
        return {
          'apps': [app('Alpha')],
          'nextOffset': 1,
          'total': 2,
          'hasMore': true,
        };
      return nextPage.future;
    });
    final container = ProviderContainer();
    await container.read(settingsProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: [_TestLocalizations(loc)],
          home: const AppsScreen(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(offsets, [0, 1]);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byType(AppProgressBar), findsOneWidget);
    await tester.tap(find.text('Direct'));
    await tester.pump();
    expect(
      container.read(settingsProvider).perAppRules['test.alpha'],
      'direct',
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AppRouteSelector),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.clipBehavior, Clip.antiAlias);
    nextPage.complete({
      'apps': [app('Beta')],
      'nextOffset': 2,
      'total': 2,
      'hasMore': false,
    });
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byType(AppProgressBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  testWidgets('UID blocking is selectable but NextLink cannot block itself', (
    tester,
  ) async {
    final loc = AppLocalizations(const Locale('en'));
    await tester.runAsync(() => loc.load());
    SharedPreferences.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'apps': [
          app('Alpha'),
          {...app('NextLink'), 'isVpnServiceApp': true},
        ],
        'supportsUidBlocking': true,
        'nextOffset': 2,
        'total': 2,
        'hasMore': false,
      },
    );
    final container = ProviderContainer();
    await container.read(settingsProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: [_TestLocalizations(loc)],
          home: const AppsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final alpha = find.byKey(const ValueKey('test.alpha'));
    await tester.tap(find.descendant(of: alpha, matching: find.text('Block')));
    await tester.pump();
    expect(container.read(settingsProvider).perAppRules['test.alpha'], 'block');
    final own = find.byKey(const ValueKey('test.nextlink'));
    await tester.tap(find.descendant(of: own, matching: find.text('Block')));
    await tester.pump();
    expect(
      container.read(settingsProvider).perAppRules['test.nextlink'],
      isNull,
    );
    container.read(settingsProvider.notifier).invertPerAppRules();
    expect(container.read(settingsProvider).perAppRules['test.alpha'], 'block');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  testWidgets('leaving during a page request cancels further loading', (
    tester,
  ) async {
    final loc = AppLocalizations(const Locale('en'));
    await tester.runAsync(() => loc.load());
    SharedPreferences.setMockInitialValues({});
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) {
      calls++;
      return pending.future;
    });
    final container = ProviderContainer();
    await container.read(settingsProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: [_TestLocalizations(loc)],
          home: const AppsScreen(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpWidget(const SizedBox());
    pending.complete({
      'apps': [app('Late')],
      'nextOffset': 1,
      'total': 2,
      'hasMore': true,
    });
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    container.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
}
