import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/shared/widgets/server_globe.dart';
import 'package:nextlink/core/providers/subscription_provider.dart';
import 'package:nextlink/core/providers/server_locations_provider.dart';
import 'package:nextlink/core/models/subscription.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';
import 'package:nextlink/core/utils/ip_location.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/providers/chains_provider.dart';
import 'package:nextlink/core/models/proxies/custom_config.dart';

void main() {
  test(
    'projection hides far-side markers and centers the selected hemisphere',
    () {
      const p = GlobeProjection(0, 0);
      final (center, depth) = p.project(0, 0, const Size(200, 200));
      expect(center, const Offset(100, 100));
      expect(depth, 1);
      expect(p.project(0, 180, const Size(200, 200)).$2, lessThan(0));
    },
  );
  test('screen-space clustering separates cities when zoom increases', () {
    expect(
      clusterGlobePoints(const [
        Offset(10, 10),
        Offset(20, 10),
        Offset(90, 10),
      ]),
      [
        [0, 1],
        [2],
      ],
    );
    expect(
      clusterGlobePoints(const [
        Offset(100, 100),
        Offset(200, 100),
        Offset(900, 100),
      ]),
      [
        [0],
        [1],
        [2],
      ],
    );
  });
  test('globe defaults on, and off survives settings persistence', () {
    expect(SettingsState.fromMap({}).showServerGlobe, true);
    expect(
      SettingsState.fromMap(
        SettingsState().copyWith(showServerGlobe: false).toMap(),
      ).showServerGlobe,
      false,
    );
  });
  testWidgets(
    'fullscreen globe zooms, clusters nearby servers and connects the chosen server',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = [
        ProxyParser.parse(
          'vless://00000000-0000-0000-0000-000000000001@de.example.org:443?security=tls#Frankfurt',
        )..ping = 42,
        ProxyParser.parse(
          'vless://00000000-0000-0000-0000-000000000001@pl.example.org:443?security=tls#Warsaw',
        ),
      ];
      SharedPreferences.setMockInitialValues({
        'saved_subscriptions': jsonEncode([
          Subscription(
            id: 'test',
            name: 'Test',
            url: '',
            updatedTime: '',
            servers: configs,
          ).toMap(),
        ]),
      });
      final boundary = GlobalKey();
      String? connectedHost;
      ProxyChain? connectedChain;
      bool editing = false;
      final container = ProviderContainer(
        overrides: [
          serverLocationsProvider.overrideWith(
            (ref) => Stream.value({
              'de.example.org': const IpLocation(
                ip: '1.1.1.1',
                countryCode: 'DE',
                country: 'Germany',
                city: 'Frankfurt am Main',
                latitude: 50.11,
                longitude: 8.68,
                utc: '+01:00',
              ),
              'pl.example.org': const IpLocation(
                ip: '8.8.8.8',
                countryCode: 'PL',
                country: 'Poland',
                city: 'Warsaw',
                latitude: 52.23,
                longitude: 21.01,
              ),
            }),
          ),
        ],
      );
      container.read(subscriptionProvider);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      container.read(subscriptionProvider).last.servers.first.ping = 42;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(primary: Color(0xffff344e)),
            ),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 320,
                    height: 650,
                    child: ServerGlobe(
                      fullScreen: true,
                      currentLocation: const IpLocation(
                        ip: '9.9.9.9',
                        countryCode: 'AU',
                        country: 'Australia',
                        city: 'Sydney',
                      ),
                      onConnect: (server, sourceKey) async {
                        connectedHost = server.address;
                      },
                      onEditingChanged: (value) => editing = value,
                      onConnectChain: (chain) async {
                        connectedChain = chain;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sydney · Australia'), findsOneWidget);
      expect(find.text('Локации · 2/2'), findsNothing);
      // Full-screen canvas can zoom far beyond the old 2.5x limit.
      for (var i = 0; i < 4; i++)
        await tester.tap(find.byTooltip('Приблизить'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) await tester.tap(find.byTooltip('Отдалить'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/verification').create(recursive: true);
        await File('build/verification/server-globe.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      final projected =
          const GlobeProjection(
            .35,
            .55,
          ).project(50.11, 8.68, const Size(528, 1072.5)).$1 +
          const Offset((320 - 528) / 2, (650 - 1072.5) / 2);
      await tester.tapAt(tester.getTopLeft(find.byKey(boundary)) + projected);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Серверы рядом'), findsOneWidget);
      expect(find.text('Frankfurt'), findsOneWidget);
      expect(find.text('Warsaw'), findsOneWidget);
      expect(find.byType(LocationDetails), findsNothing);
      expect(find.textContaining('42 ms'), findsOneWidget);
      await tester.tap(find.text('Warsaw'));
      await tester.pumpAndSettle();
      expect(connectedHost, 'pl.example.org');
      await tester.tap(find.byTooltip('Строить цепочку'));
      await tester.pumpAndSettle();
      expect(editing, true);
      expect(find.text('Маршрут цепочки'), findsOneWidget);
      for (final name in ['Frankfurt', 'Warsaw']) {
        await tester.tapAt(tester.getTopLeft(find.byKey(boundary)) + projected);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Вход · Frankfurt'), findsOneWidget);
      expect(find.textContaining('Выход · Warsaw'), findsOneWidget);
      // Reorder through the real list callback, preserving node identities.
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorder!(0, 2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подключить'));
      await tester.pumpAndSettle();
      expect(find.text('Название цепочки'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Map chain');
      await tester.tap(find.text('Сохранить').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(editing, false);
      expect(connectedChain?.name, 'Map chain');
      expect(connectedChain?.nodes.map((n) => n.address), [
        'pl.example.org',
        'de.example.org',
      ]);
      expect(container.read(chainsProvider).single.name, 'Map chain');
      expect(container.read(subscriptionProvider).last.servers.length, 2);
      final savedId = container.read(chainsProvider).single.id;
      await tester.tap(find.byTooltip('Мои цепочки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Map chain'));
      await tester.pumpAndSettle();
      expect(find.text('Map chain'), findsOneWidget);
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorder!(0, 2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edited chain');
      await tester.tap(find.text('Сохранить').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(chainsProvider).length, 1);
      expect(container.read(chainsProvider).single.id, savedId);
      expect(container.read(chainsProvider).single.name, 'Edited chain');
      expect(
        container.read(chainsProvider).single.nodes.map((n) => n.address),
        ['de.example.org', 'pl.example.org'],
      );
      await tester.tap(find.byTooltip('Мои цепочки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Подключить'));
      await tester.pumpAndSettle();
      expect(connectedChain?.name, 'Edited chain');
      await tester.tap(find.byTooltip('Мои цепочки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить цепочку'));
      await tester.pumpAndSettle();
      expect(find.text('Удалить цепочку?'), findsOneWidget);
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(container.read(chainsProvider), isEmpty);

      expect(find.text('Серверы рядом'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
  testWidgets(
    'original subscription Auto connects unchanged even without geolocation',
    (tester) async {
      final original = CustomConfig.parseJson(
        jsonEncode({
          'remarks': 'Auto original',
          'routing': {
            'balancers': [
              {
                'tag': 'auto',
                'selector': ['node-'],
              },
            ],
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
      SharedPreferences.setMockInitialValues({
        'saved_subscriptions': jsonEncode([
          Subscription(
            id: 'sub',
            name: 'Sub',
            url: 'https://example.org/sub',
            updatedTime: '',
            servers: [original],
          ).toMap(),
        ]),
      });
      final container = ProviderContainer(
        overrides: [
          serverLocationsProvider.overrideWith((ref) => Stream.value({})),
        ],
      );
      await tester.runAsync(() async {
        await container.read(subscriptionProvider.notifier).ready;
      });
      String? chosen, source;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ServerGlobe(
                fullScreen: true,
                onConnect: (server, key) async {
                  chosen = server.uniqueKey;
                  source = key;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Авто из подписок'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto original'));
      await tester.pumpAndSettle();
      expect(chosen, original.uniqueKey);
      expect(source, original.uniqueKey);
      expect(container.read(subscriptionProvider).single.servers.length, 1);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
