import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Repeating effects are ticker-aware and stop when disabled or offscreen.
class ThemeMotion extends StatefulWidget {
  final String style;
  final bool enabled;
  final int durationMs;
  final Widget child;
  const ThemeMotion({
    super.key,
    required this.style,
    this.durationMs = 3000,
    required this.enabled,
    required this.child,
  });
  @override
  State<ThemeMotion> createState() => _ThemeMotionState();
}

class _ThemeMotionState extends State<ThemeMotion>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  @override
  void initState() {
    super.initState();
    sync();
  }

  @override
  void didUpdateWidget(ThemeMotion old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled ||
        old.style != widget.style ||
        old.durationMs != widget.durationMs)
      sync();
  }

  void sync() {
    controller.duration = Duration(
      milliseconds: widget.durationMs.clamp(800, 30000),
    );
    if (widget.enabled && widget.style != 'none') {
      controller.repeat(reverse: true);
    } else {
      controller.stop();
      controller.value = 0;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (_, child) {
      final v = Curves.easeInOut.transform(controller.value);
      return switch (widget.enabled ? widget.style : 'none') {
        'pulse' => Transform.scale(scale: 1 + v * .05, child: child),
        'float' => Transform.translate(offset: Offset(0, -8 * v), child: child),
        'swing' => Transform.rotate(
          angle: math.sin(v * math.pi * 2) * .035,
          child: child,
        ),
        'fade' => Opacity(opacity: .65 + v * .35, child: child),
        _ => child!,
      };
    },
  );
}
