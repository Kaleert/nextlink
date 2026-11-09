import '../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';

/// A compact translucent track with the current theme's accent gradient.
class AppProgressBar extends StatefulWidget {
  final double? value;
  final String? label;
  final Color? color;
  const AppProgressBar({super.key, this.value, this.label, this.color});

  @override
  State<AppProgressBar> createState() => _AppProgressBarState();
}

class _AppProgressBarState extends State<AppProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(AppProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.value == null && !MediaQuery.disableAnimationsOf(context)) {
      if (!_animation.isAnimating) _animation.repeat(reverse: true);
    } else {
      _animation.stop();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    Widget fill() => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(colors: [color.withValues(alpha: .6), color]),
      ),
    );
    return Semantics(
      label: widget.label ?? AppLocalizations.text(context, "Загрузка"),
      value: widget.value == null
          ? null
          : '${(widget.value!.clamp(0, 1) * 100).round()}%',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              border: Border.all(color: color.withValues(alpha: .16)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.value == null
                ? AnimatedBuilder(
                    animation: _animation,
                    builder: (_, __) => Align(
                      alignment: Alignment(-1 + 2 * _animation.value, 0),
                      child: FractionallySizedBox(
                        widthFactor: .3,
                        heightFactor: 1,
                        child: fill(),
                      ),
                    ),
                  )
                : TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0, end: widget.value!.clamp(0, 1)),
                    builder: (_, value, __) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: value,
                        heightFactor: 1,
                        child: fill(),
                      ),
                    ),
                  ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.label!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
