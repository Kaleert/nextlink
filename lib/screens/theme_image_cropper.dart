import '../core/localization/app_localizations.dart';

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

Future<Uint8List?> pickThemeImage() async {
  Uint8List? bytes;
  if (Platform.isAndroid) {
    final result = await const MethodChannel('pro.kaleert.nextlink/theme_files')
        .invokeMethod<Map>('pickThemeImage');
    bytes = result?['bytes'] as Uint8List?;
  } else if (Platform.isLinux) {
    final result = await Process.run('zenity', [
      '--file-selection',
      '--title=Фон элемента',
      '--file-filter=Изображения | *.png *.jpg *.jpeg *.webp *.gif',
    ]);
    if (result.exitCode == 0) {
      final file = File(result.stdout.toString().trim());
      if (await file.length() > 16 * 1024 * 1024)
        throw const FormatException('Изображение больше 16 МБ');
      bytes = await file.readAsBytes();
    }
  } else {
    throw const FormatException(
      'Выбор изображения пока доступен на Android и Linux',
    );
  }
  if (bytes == null) return null;
  if (bytes.length > 16 * 1024 * 1024)
    throw const FormatException('Изображение больше 16 МБ');
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 2048,
    targetHeight: 2048,
  );
  final frame = await codec.getNextFrame();
  frame.image.dispose();
  codec.dispose();
  return bytes;
}

class ThemeImageCropper extends StatefulWidget {
  final Uint8List bytes;
  final double aspectRatio;
  const ThemeImageCropper({
    super.key,
    required this.bytes,
    this.aspectRatio = 1.6,
  });
  @override
  State<ThemeImageCropper> createState() => _ThemeImageCropperState();
}

class _ThemeImageCropperState extends State<ThemeImageCropper> {
  final boundary = GlobalKey();
  final transform = TransformationController();
  bool busy = false;
  bool loaded = false;
  late double ratio = widget.aspectRatio.clamp(.25, 4);
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Future<void> crop() async {
    setState(() => busy = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final box =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await box.toImage(
        pixelRatio: (1024 / box.size.longestSide).clamp(1, 3),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (mounted) Navigator.pop(context, bytes!.buffer.asUint8List());
    } catch (error) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.text(
                context,
                "Не удалось обрезать: {0}",
                args: [error],
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff080808),
    appBar: AppBar(
      title: Text(AppLocalizations.text(context, "Обрезка фона")),
      actions: [
        TextButton(
          onPressed: busy || !loaded ? null : crop,
          child: Text(
            busy
                ? AppLocalizations.text(context, "Сохранение…")
                : AppLocalizations.text(context, "Готово"),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              AppLocalizations.text(
                context,
                "Перемещайте и увеличивайте изображение двумя пальцами. В рамке останется фон элемента.",
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: ClipRect(
                    child: RepaintBoundary(
                      key: boundary,
                      child: InteractiveViewer(
                        transformationController: transform,
                        minScale: 1,
                        maxScale: 6,
                        child: SizedBox.expand(
                          child: Image(
                            image: ResizeImage(
                              MemoryImage(widget.bytes),
                              width: 2048,
                              height: 2048,
                              policy: ResizeImagePolicy.fit,
                            ),
                            fit: BoxFit.cover,
                            frameBuilder: (context, child, frame, sync) {
                              if ((sync || frame != null) && !loaded)
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) setState(() => loaded = true);
                                });
                              return child;
                            },
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                AppLocalizations.text(
                                  context,
                                  "Не удалось открыть изображение",
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in {
                'Элемент': widget.aspectRatio,
                '1:1': 1.0,
                '16:9': 16 / 9,
                '4:3': 4 / 3,
              }.entries)
                TextButton(
                  onPressed: () => setState(() {
                    ratio = entry.value.clamp(.25, 4);
                    transform.value = Matrix4.identity();
                  }),
                  child: Text(entry.key),
                ),
            ],
          ),
          TextButton(
            onPressed: () => transform.value = Matrix4.identity(),
            child: Text(AppLocalizations.text(context, "Сбросить кадр")),
          ),
        ],
      ),
    ),
  );
}
