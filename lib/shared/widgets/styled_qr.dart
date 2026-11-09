import '../../core/localization/app_localizations.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/qr_export_style.dart';

class StyledQrPainter extends CustomPainter {
  final QrCode code;
  final QrExportStyle style;
  late final QrPainter painter = QrPainter.withQr(
    qr: code,
    eyeStyle: style.eyeStyle,
    dataModuleStyle: style.moduleStyle,
    gapless: true,
  );
  StyledQrPainter(this.code, this.style);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = style.paper);
    final side = size.shortestSide;
    final margin =
        side * style.quietZone / (code.moduleCount + style.quietZone * 2);
    canvas.save();
    canvas.translate(
      (size.width - side) / 2 + margin,
      (size.height - side) / 2 + margin,
    );
    painter.paint(canvas, Size.square(side - margin * 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(StyledQrPainter old) =>
      old.code != code || old.style != style;
}

class StyledQr extends StatelessWidget {
  final QrCode code;
  final QrExportStyle style;
  final double dimension;
  const StyledQr({
    super.key,
    required this.code,
    required this.style,
    this.dimension = 248,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.text(context, "QR-код для импорта"),
    image: true,
    child: SizedBox.square(
      dimension: dimension,
      child: CustomPaint(painter: StyledQrPainter(code, style)),
    ),
  );
}

Future<Uint8List> renderStyledQr(QrCode code, QrExportStyle style) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  StyledQrPainter(
    code,
    style,
  ).paint(canvas, Size.square(style.size.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(style.size, style.size);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
