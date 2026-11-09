import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nextlink/screens/config_share_sheet.dart';
import 'package:nextlink/core/utils/config_share_payload.dart';

void main() {
  testWidgets('JSON is shared as a file and QR export creates an opaque PNG', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const payload = ConfigSharePayload(
      name: 'Test profile',
      json: '{"outbounds":[]}',
      url: 'https://example.org/sub/test',
      qr: 'https://example.org/sub/test',
    );
    final calls = <Map>[];
    const channel = MethodChannel('pro.kaleert.nextlink/theme_files');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'shareConfig');
      calls.add(call.arguments as Map);
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
    await tester.tap(find.text('JSON-файл'));
    await tester.pumpAndSettle();
    expect(calls.single['contents'], payload.json);
    expect(calls.single['extension'], 'json');
    expect(calls.single['mime'], 'application/json');
    await tester.tap(find.text('QR-код / PNG'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await tester.tap(find.text('PNG'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    final bytes = calls.last['bytes'] as Uint8List;
    expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1024);
      expect(frame.image.height, 1024);
      final rgba = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(rgba!.buffer.asUint8List().take(4).toList(), [255, 255, 255, 255]);
      frame.image.dispose();
      codec.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
}
