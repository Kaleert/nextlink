import '../../core/theme/theme_surface_style.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

/// Alert dialog surface that matches the app's translucent blurred menus.
class GlassAlertDialog extends StatelessWidget {
  final Color surfaceColor;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  const GlassAlertDialog({
    super.key,
    required this.surfaceColor,
    this.title,
    this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: Theme.of(context).extension<ThemeSurfaceStyle>()?.blur ?? 26,
          sigmaY: Theme.of(context).extension<ThemeSurfaceStyle>()?.blur ?? 26,
        ),
        child: AlertDialog(
          backgroundColor: surfaceColor.withOpacity(
            Theme.of(context).extension<ThemeSurfaceStyle>()?.opacity ?? .52,
          ),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: Colors.white.withOpacity(0.08),
              width:
                  Theme.of(context)
                      .extension<ThemeSurfaceStyle>()
                      ?.borderWidth ??
                  1,
            ),
          ),
          title: title,
          content: content,
          actions: actions,
        ),
      ),
    );
  }
}
