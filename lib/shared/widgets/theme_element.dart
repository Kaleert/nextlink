import 'package:flutter/material.dart';

import '../../core/models/theme_config.dart';
import 'theme_motion.dart';
import 'tour_anchor.dart';

/// Applies the same component transforms to interactive and static elements.
class ThemeElement extends StatelessWidget {
  final ThemeConfig theme;
  final String id;
  final Widget child;
  final bool isCanvas;
  const ThemeElement({
    super.key,
    required this.theme,
    required this.id,
    required this.child,
    this.isCanvas = false,
  });
  @override
  Widget build(BuildContext context) {
    final locked = isCanvas || id.startsWith('screen_');
    final motion = theme.componentMotions[id];
    final content =
        !locked && theme.animationsEnabled && motion != null && motion != 'none'
        ? ThemeMotion(
            style: motion,
            enabled: true,
            durationMs: theme.animationDurationMs,
            child: child,
          )
        : child;
    return Opacity(
      opacity: theme.opacityFor(id),
      child: Transform.translate(
        offset: locked ? Offset.zero : theme.offsetFor(id),
        child: Transform.scale(
          scale: locked ? 1 : theme.scaleFor(id),
          child: TourAnchor.wrap(id, content),
        ),
      ),
    );
  }
}
