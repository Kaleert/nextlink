import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart';
import '../../core/models/theme_config.dart';

class AnimatedMeshBackground extends ConsumerStatefulWidget {
  final bool isConnected;
  final ThemeConfig? themeOverride;

  const AnimatedMeshBackground({
    super.key,
    required this.isConnected,
    this.themeOverride,
  });

  @override
  ConsumerState<AnimatedMeshBackground> createState() =>
      _AnimatedMeshBackgroundState();
}

class _AnimatedMeshBackgroundState extends ConsumerState<AnimatedMeshBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late ProviderSubscription _themeSubscription;

  @override
  void initState() {
    super.initState();
    final initialTheme =
        widget.themeOverride ?? ref.read(themeProvider).currentTheme;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: initialTheme.animationDurationMs.clamp(1000, 20000),
      ),
    );
    if (initialTheme.animationsEnabled) _controller.repeat(reverse: true);
    _themeSubscription = ref.listenManual(themeProvider, (previous, next) {
      if (widget.themeOverride != null) return;
      final theme = next.currentTheme;
      _controller.duration = Duration(
        milliseconds: theme.animationDurationMs.clamp(1000, 20000),
      );
      if (theme.animationsEnabled) {
        if (!_controller.isAnimating) _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.5;
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedMeshBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final theme = widget.themeOverride;
    if (theme == null || identical(theme, oldWidget.themeOverride)) return;
    _controller.duration = Duration(
      milliseconds: theme.animationDurationMs.clamp(1000, 20000),
    );
    if (theme.animationsEnabled) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = .5;
    }
  }

  @override
  void dispose() {
    _themeSubscription.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeOverride ?? ref.watch(themeProvider).currentTheme;

    if (theme.backgroundStyle == 'off')
      return Container(color: theme.background);
    if (['linear', 'radial'].contains(theme.backgroundStyle)) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = theme.animationsEnabled ? _controller.value : .5;
          final angle = theme.gradientAngle * math.pi / 180 + (t - .5) * .8;
          final direction = Alignment(math.cos(angle), math.sin(angle));
          final colors = [
            theme.background,
            Color.lerp(
              theme.background,
              widget.isConnected ? theme.meshActive1 : theme.meshIdle1,
              theme.backgroundIntensity,
            )!,
            Color.lerp(
              theme.background,
              widget.isConnected ? theme.meshActive2 : theme.meshIdle2,
              theme.backgroundIntensity,
            )!,
            theme.background,
          ];
          return Container(
            decoration: BoxDecoration(
              color: theme.background,
              gradient: !theme.useGradients
                  ? null
                  : theme.backgroundStyle == 'radial'
                  ? RadialGradient(
                      center: Alignment((t - .5) * .8, -.25),
                      radius: .8 + t * .4,
                      colors: colors,
                    )
                  : LinearGradient(
                      begin: Alignment(-direction.x, -direction.y),
                      end: direction,
                      colors: colors,
                    ),
            ),
          );
        },
      );
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _MeshPainter(theme, widget.isConnected, _controller),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Soft radial fills replace a full-screen backdrop readback every frame.
/// The animation repaints this layer without rebuilding/relaying out widgets.
class _MeshPainter extends CustomPainter {
  final ThemeConfig theme;
  final bool connected;
  final Animation<double> animation;
  _MeshPainter(this.theme, this.connected, this.animation)
    : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);
    if (!theme.useGradients) return;
    final t = theme.animationsEnabled ? animation.value : .5;
    void orb(Offset center, double radius, Color color) {
      final bounds = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: theme.backgroundIntensity * .75),
              color.withValues(alpha: theme.backgroundIntensity * .35),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ).createShader(bounds),
      );
    }

    orb(
      Offset(size.width * (.5 + t * .5), size.height * t),
      260 + 70 * t,
      connected ? theme.meshActive1 : theme.meshIdle1,
    );
    orb(
      Offset(size.width * (.5 - (1 - t) * .8), size.height * (.8 * (1 - t))),
      350 - 50 * t,
      connected ? theme.meshActive2 : theme.meshIdle2,
    );
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.theme != theme || old.connected != connected;
}
