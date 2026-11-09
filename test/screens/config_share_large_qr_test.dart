import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/shared/widgets/styled_qr.dart';
import 'package:nextlink/screens/config_share_sheet.dart';
import 'package:nextlink/core/utils/config_share_payload.dart';

void main() {
  testWidgets(
    'large random config offers the exact JSON file and never paints an invalid QR',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final random = Random(52);
      final data = jsonEncode({
        'data': base64Encode(List.generate(12000, (_) => random.nextInt(256))),
      });
      final payload = ConfigSharePayload(
        name: 'Large',
        json: data,
        url: '',
        qr: data,
      );
      const channel = MethodChannel('pro.kaleert.nextlink/theme_files');
      Map? sent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        sent = call.arguments as Map;
        return null;
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showConfigShareSheet(context, payload),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QR-код / PNG'));
      await tester.pumpAndSettle();
      expect(find.text('Конфигурация не помещается в QR'), findsOneWidget);
      expect(find.byType(StyledQr), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Отправить JSON-файл'));
      await tester.pumpAndSettle();
      expect(sent!['contents'], data);
      expect(sent!['extension'], 'json');
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
  testWidgets(
    'compressible full JSON displays a square QR without an overflow exception',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final data = jsonEncode({
        'outbounds': List.generate(
          35,
          (i) => {
            'tag': 'Server$i',
            'type': 'vless',
            'server': 'server$i.example.org',
            'uuid': '00000000-0000-0000-0000-000000000001',
          },
        ),
      });
      final payload = ConfigSharePayload(
        name: 'Large JSON',
        json: data,
        url: '',
        qr: data,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showConfigShareSheet(context, payload),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QR-код / PNG'));
      await tester.pumpAndSettle();
      expect(find.text('Сжатый QR · импорт через NextLink'), findsOneWidget);
      expect(find.byType(StyledQr), findsOneWidget);
      expect(tester.getSize(find.byType(StyledQr)), const Size(248, 248));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
