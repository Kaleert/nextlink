import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'theme_widget_style.dart';

class ThemeImageBackground extends StatefulWidget {
  final Map<String, dynamic> image;
  final Widget child;
  final double radius;
  const ThemeImageBackground({
    super.key,
    required this.image,
    required this.child,
    required this.radius,
  });
  @override
  State<ThemeImageBackground> createState() => _ThemeImageBackgroundState();
}

class _ThemeImageBackgroundState extends State<ThemeImageBackground> {
  Uint8List? bytes;
  @override
  void initState() {
    super.initState();
    decode();
  }

  @override
  void didUpdateWidget(ThemeImageBackground old) {
    super.didUpdateWidget(old);
    if (old.image['data'] != widget.image['data']) decode();
  }

  void decode() {
    try {
      final data = widget.image['data'] as String?;
      bytes = data == null || data.length > 12 * 1024 * 1024
          ? null
          : base64Decode(data);
    } catch (_) {
      bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (bytes == null) return widget.child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.memory(
              bytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(
                alpha: ((widget.image['dim'] as num?)?.toDouble() ?? .25).clamp(
                  0,
                  1,
                ),
              ),
            ),
          ),
          styleThemeWidget(widget.child, color: Colors.transparent),
        ],
      ),
    );
  }
}
