import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/providers/server_locations_provider.dart';
import 'package:nextlink/shared/widgets/server_globe.dart';

void main() {
  test(
    'automatic core downloads and updates are opt-in and persist independently',
    () {
      final defaults = SettingsState.fromMap({});
      expect(defaults.autoUpdateCores, isFalse);
      expect(defaults.autoInstallCoreUpdates, isFalse);
      expect(
        SettingsState.fromMap(defaults.copyWith(autoUpdateCores: true).toMap())
            .autoUpdateCores,
        isTrue,
      );
      final restored = SettingsState.fromMap(
        defaults.copyWith(autoInstallCoreUpdates: true).toMap(),
      );
      expect(restored.autoInstallCoreUpdates, isTrue);
      expect(restored.autoUpdateCores, isFalse);
      expect(
        SettingsState.fromMap({'autoUpdateCores': true}).autoUpdateCores,
        isFalse,
      );
    },
  );
  testWidgets(
    'empty globe rotates with two fingers and pinches without a jump',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverLocationsProvider.overrideWith((ref) => Stream.value({})),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ServerGlobe(fullScreen: true)),
          ),
        ),
      );
      await tester.pump();
      dynamic painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .firstWhere((p) => p.runtimeType.toString() == '_GlobePainter');
      final initial = (painter().projection as GlobeProjection).longitude;
      final first = await tester.startGesture(
        const Offset(200, 260),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(280, 260),
        pointer: 2,
      );
      await first.moveBy(const Offset(40, 0));
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(
        (painter().projection as GlobeProjection).longitude,
        isNot(initial),
      );
      final zoom = painter().zoom as double;
      await first.moveBy(const Offset(-35, 0));
      await second.moveBy(const Offset(35, 0));
      await tester.pump();
      expect(painter().zoom as double, greaterThan(zoom));
      await first.up();
      await second.up();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
