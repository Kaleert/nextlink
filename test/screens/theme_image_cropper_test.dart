import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/screens/theme_image_cropper.dart';

void main() {
  testWidgets('crop exports a real PNG with the chosen aspect ratio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nGM4kfJ/QBDDqMWjFo9aPGrxqMWjFo9aPGrxyLEYAN+uxrvl7yUGAAAAAElFTkSuQmCC',
    );
    Uint8List? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<Uint8List>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ThemeImageCropper(bytes: bytes),
                  ),
                );
              },
              child: const Text('Crop'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Crop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:1'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Готово'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Готово'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(result!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, frame.image.height);
      expect(frame.image.width, greaterThan(100));
      frame.image.dispose();
      codec.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
