import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';
import 'package:nextlink/core/models/proxies/custom_config.dart';
import 'package:nextlink/core/providers/chains_provider.dart';
import 'package:nextlink/core/providers/server_locations_provider.dart';
import 'package:nextlink/core/utils/ip_location.dart';
import 'package:nextlink/shared/widgets/server_globe.dart';

final de = ProxyParser.parse(
  'vless://00000000-0000-0000-0000-000000000001@de.example.org:443#DE',
);
final pl = ProxyParser.parse(
  'vless://00000000-0000-0000-0000-000000000001@pl.example.org:443#PL',
);

void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<int> greenPixels(WidgetTester tester, GlobalKey key) async =>
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      var count = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] == 101 && bytes[i + 1] == 230 && bytes[i + 2] == 163)
          count++;
      }
      image.dispose();
      return count;
    }) ??
    0;

void main() {
  test(
    'chain map uses the actual exit and preserves unresolved hops as unknown',
    () {
      final chain = ProxyChain(id: 'x', name: 'X', nodes: [de, pl]);
      const exit = IpLocation(
        ip: '9.9.9.9',
        city: 'Paris',
        latitude: 48.86,
        longitude: 2.35,
      );
      final route = chainMapLocations(chain, {
        'de.example.org': const IpLocation(latitude: 50.11, longitude: 8.68),
      }, exit: exit);
      expect(route.first.latitude, 50.11);
      expect(route.last.city, 'Paris');
      final unknown = chainMapLocations(chain, {});
      expect(unknown.every((p) => !p.hasCoordinates), true);
    },
  );
  testWidgets(
    'actual connected chain paints a route; disconnect removes it despite selection',
    (tester) async {
      phone(tester);
      final semantics = tester.ensureSemantics();

      final chain = ProxyChain(
        id: 'live',
        name: 'Live route',
        isActive: true,
        nodes: [de, pl],
      );
      SharedPreferences.setMockInitialValues({
        'custom_proxy_chains': jsonEncode([chain.toMap()]),
      });
      final container = ProviderContainer(
        overrides: [
          serverLocationsProvider.overrideWith(
            (ref) => Stream.value({
              'de.example.org': const IpLocation(
                latitude: 50.11,
                longitude: 8.68,
              ),
              'pl.example.org': const IpLocation(
                latitude: 52.23,
                longitude: 21.01,
              ),
            }),
          ),
        ],
      );
      await tester.runAsync(() async {
        await container.read(chainsProvider.notifier).ready;
      });
      var connected = true;
      late StateSetter update;
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return Center(
                    child: RepaintBoundary(
                      key: key,
                      child: SizedBox(
                        width: 320,
                        height: 650,
                        child: ServerGlobe(
                          fullScreen: true,
                          connected: connected,
                          connectedServerKey: 'chain:live',
                          onConnectChain: (chain) async {},
                          onDisconnect: () async {
                            expect(container.read(chainsProvider).length, 1);
                            update(() => connected = false);
                          },
                          currentLocation: const IpLocation(
                            ip: '9.9.9.9',
                            latitude: 48.86,
                            longitude: 2.35,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('.*Подключенная цепочка: Live route.*')),
        findsOneWidget,
      );
      expect(await greenPixels(tester, key), greaterThan(100));
      update(() => connected = false);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('.*Подключенная цепочка.*')),
        findsNothing,
      );
      expect(await greenPixels(tester, key), 0);
      expect(container.read(chainsProvider).single.isActive, true);
      update(() => connected = true);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Мои цепочки'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Отключить'), findsOneWidget);
      await tester.tap(find.byTooltip('Удалить цепочку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(connected, false);
      expect(container.read(chainsProvider), isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      semantics.dispose();
    },
  );
  testWidgets(
    'stored automatic hop with no coordinates survives map editing unchanged',
    (tester) async {
      phone(tester);
      final auto = CustomConfig.parseJson(
        jsonEncode({
          'remarks': 'Opaque Auto',
          'routing': {
            'balancers': [
              {
                'tag': 'auto',
                'selector': ['node-'],
              },
            ],
            'rules': [
              {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'},
            ],
          },
          'dns': {
            'servers': ['1.1.1.1'],
          },
          'outbounds': [
            {
              'tag': 'node-de',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {'address': 'de.example.org', 'port': 443},
                ],
              },
            },
            {
              'tag': 'node-pl',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {'address': 'pl.example.org', 'port': 443},
                ],
              },
            },
          ],
        }),
      );
      final chain = ProxyChain(
        id: 'saved',
        name: 'Original saved',
        nodes: [auto],
      );
      SharedPreferences.setMockInitialValues({
        'custom_proxy_chains': jsonEncode([chain.toMap()]),
      });
      final container = ProviderContainer(
        overrides: [
          serverLocationsProvider.overrideWith((ref) => Stream.value({})),
        ],
      );
      await tester.runAsync(() async {
        await container.read(chainsProvider.notifier).ready;
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ServerGlobe(fullScreen: true, onConnect: (s, k) async {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Мои цепочки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original saved'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Локация пока неизвестна'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed saved');
      await tester.tap(find.text('Сохранить').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final saved = container.read(chainsProvider).single;
      expect(saved.id, 'saved');
      expect(saved.name, 'Renamed saved');
      expect(saved.nodes.last.toMap(), auto.toMap());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
