import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemePressEffect extends ConsumerStatefulWidget {
  final Widget child;
  final String componentId;
  final String style;
  final bool enabled;
  final int durationMs;

  const ThemePressEffect({
    super.key,
    required this.child,
    this.componentId = '',
    required this.style,
    required this.enabled,
    required this.durationMs,
  });

  @override
  ConsumerState<ThemePressEffect> createState() => _ThemePressEffectState();
}

class _ThemePressEffectState extends ConsumerState<ThemePressEffect> {
  bool _pressed = false;

  double get _pressedScale => switch (widget.style) {
    'soft' => .96,
    'bounce' => .90,
    'shrink' => .84,
    'grow' => 1.06,
    _ => 1.0,
  };

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: widget.enabled && widget.style != 'none' && _pressed
            ? _pressedScale
            : 1,
        duration: Duration(milliseconds: widget.durationMs.clamp(80, 500)),
        curve: widget.style == 'bounce'
            ? Curves.elasticOut
            : Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
