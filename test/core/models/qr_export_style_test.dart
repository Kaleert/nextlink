import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/qr_export_style.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/utils/config_share_qr.dart';
import 'package:nextlink/shared/widgets/styled_qr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('global QR settings and Block survive settings serialization', () {
    const style = QrExportStyle(
      foreground: 0xff152345,
      background: 0xffffeedd,
      size: 512,
      quietZone: 8,
      eyes: 'circle',
      modules: 'circle',
      correction: 'H',
    );
    final saved = SettingsState(
      qrStyle: style,
      perAppDefaultRule: 'block',
      perAppRules: {'test.app': 'block'},
    );
    final loaded = SettingsState.fromMap(saved.toMap());
    expect(loaded.qrStyle.toMap(), style.toMap());
    expect(loaded.perAppDefaultRule, 'block');
    expect(loaded.perAppRules['test.app'], 'block');
  });
  test('inverted colors survive loading with safe size and margins', () {
    final style = QrExportStyle.fromMap({
      'foreground': 0xffffffff,
      'background': 0xff000000,
      'quietZone': -1,
      'size': 99999,
    });
    expect(style.readable, isTrue);
    expect(style.quietZone, 4);
    expect(style.size, 2048);
  });
  test('red on black has sufficient contrast and colors are never reset', () {
    const red = QrExportStyle(foreground: 0xffff0000, background: 0xff000000);
    expect(red.readable, isTrue);
    expect(QrExportStyle.fromMap(red.toMap()).toMap(), red.toMap());
    const low = QrExportStyle(foreground: 0xff111111, background: 0xff111111);
    expect(low.readable, isFalse);
    expect(QrExportStyle.fromMap(low.toMap()).toMap(), low.toMap());
  });
  test('correction level affects actual encoded QR', () {
    final low = ConfigShareQr.prepare('https://example.org/subscription')!;
    final high = ConfigShareQr.prepare(
      'https://example.org/subscription',
      errorLevel: const QrExportStyle(correction: 'H').errorLevel,
    )!;
    expect(high.code.moduleCount, greaterThan(low.code.moduleCount));
  });
  test('preview background stays within the QR bounds', () async {
    final qr = ConfigShareQr.prepare('https://example.org')!;
    final recorder = ui.PictureRecorder();
    StyledQrPainter(
      qr.code,
      const QrExportStyle(),
    ).paint(ui.Canvas(recorder), const ui.Size.square(32));
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(data.getUint8((50 * 64 + 50) * 4 + 3), 0);
    expect(data.getUint8(3), 255);
    image.dispose();
    picture.dispose();
  });
  test('PNG uses selected size, opaque paper and full quiet zone', () async {
    const style = QrExportStyle(
      foreground: 0xff152345,
      background: 0xffffeedd,
      size: 512,
      quietZone: 8,
      eyes: 'circle',
      modules: 'circle',
    );
    final qr = ConfigShareQr.prepare('https://example.org/sub')!;
    final bytes = await renderStyledQr(qr.code, style);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    final data = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final margin = (512 * 8 / (qr.code.moduleCount + 16)).floor();
    for (var y = 0; y < margin; y++) {
      for (var x = 0; x < 512; x++) {
        final at = (y * 512 + x) * 4;
        expect(data.sublist(at, at + 4), [255, 238, 221, 255]);
      }
    }
    expect(data, contains(21)); // ink red channel
    frame.image.dispose();
    codec.dispose();
  });
}
