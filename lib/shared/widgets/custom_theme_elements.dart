import 'country_flag.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/models/theme_config.dart';
import 'theme_element.dart';
import 'theme_press_effect.dart';
import 'theme_edit_session.dart';
import 'theme_image_background.dart';

class ThemeActionRegistry {
  static Future<void> Function(Map<String, dynamic>)? run;
  static final data = ValueNotifier<Map<String, String>>({
    'vpn': '—',
    'timer': '00:00',
    'traffic': '0 MB',
    'ip': '—',
    'server': '—',
    'ping': '—',
  });
}

/// Theme-defined content uses the same transforms and press effects as built-ins.
class CustomThemeElements extends StatelessWidget {
  final ThemeConfig theme;
  final String screen;
  final Future<void> Function(Map<String, dynamic>)? onAction;
  final Map<String, String> variables;
  final bool overlay;
  const CustomThemeElements({
    super.key,
    required this.theme,
    this.screen = 'home',
    this.onAction,
    this.variables = const {},
    this.overlay = false,
  });

  @override
  Widget build(BuildContext context) {
    if (variables.isEmpty)
      return ValueListenableBuilder<Map<String, String>>(
        valueListenable: ThemeActionRegistry.data,
        builder: (_, values, __) => CustomThemeElements(
          theme: theme,
          screen: screen,
          onAction: onAction,
          variables: values,
          overlay: overlay,
        ),
      );
    final elements = theme.customElements.where(
      (e) =>
          (e['screen'] ?? 'home') == screen &&
          ((e['placement'] == 'overlay') == overlay),
    );
    if (overlay)
      return LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            for (final e in elements)
              if (!theme.hiddenElements.contains('custom_${e['id']}'))
                Positioned(
                  left:
                      ((e['x'] as num?)?.toDouble() ?? .15).clamp(0, .95) *
                      c.maxWidth,
                  top:
                      ((e['y'] as num?)?.toDouble() ?? .48).clamp(0, .95) *
                      c.maxHeight,
                  width:
                      ((e['width'] as num?)?.toDouble() ?? .7).clamp(.1, 1) *
                      c.maxWidth,
                  child: _element(context, e),
                ),
          ],
        ),
      );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in elements)
          if (!theme.hiddenElements.contains('custom_${e['id']}'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _element(context, e),
            ),
      ],
    );
  }

  Widget _element(BuildContext context, Map<String, dynamic> e) {
    final id = 'custom_${e['id']}';
    final color = Color(
      theme.componentColors[id] ??
          (e['color'] as num?)?.toInt() ??
          theme.primary.toARGB32(),
    );
    final height = ((e['height'] as num?)?.toDouble() ?? 16)
        .clamp(0, 240)
        .toDouble();
    final type = e['type'] ?? 'button';
    final radius =
        (theme.componentRadii[id] ??
                (e['radius'] as num?)?.toDouble() ??
                theme.cardRadius)
            .clamp(0, 80)
            .toDouble();
    final alignment = switch (e['align']) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };
    final template = theme.componentTexts[id] ?? e['label']?.toString() ?? '';
    final label = template.replaceAllMapped(
      RegExp(
        r'\{\{(vpn|timer|traffic|ip|server|ping|flag|country|location)\}\}',
      ),
      (m) => variables[m[1]] ?? '—',
    );
    final originalText = Text(
      label,
      textAlign: switch (e['align']) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      },
      style: TextStyle(
        color: color,
        fontSize: ((e['fontSize'] as num?)?.toDouble() ?? 14).clamp(8, 64),
        fontWeight: FontWeight.w600,
      ),
    );
    final Widget text = FlagText.containsFlags(label)
        ? FlagText(original: originalText)
        : originalText;
    final action = e['action'];
    final handler = onAction ?? ThemeActionRegistry.run;
    final VoidCallback? pressed =
        action == null || action == 'none' || handler == null
        ? null
        : () {
            handler(e);
          };
    Widget child;
    if (type == 'spacer') {
      child = SizedBox(height: height);
    } else if (type == 'divider') {
      child = Divider(color: color, thickness: height.clamp(1, 8));
    } else if (type == 'text') {
      child = Align(alignment: alignment, child: text);
      if (pressed != null) child = InkWell(onTap: pressed, child: child);
    } else {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: theme.blurSigma,
            sigmaY: theme.blurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: e['gradient'] == true
                  ? null
                  : theme.surface.withValues(alpha: theme.glassOpacity),
              gradient: e['gradient'] == true
                  ? LinearGradient(
                      colors: [
                        color.withValues(alpha: .2),
                        theme.meshIdle2.withValues(alpha: .2),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: color.withValues(alpha: .45),
                width: theme.borderWidth,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: pressed,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: type == 'card' ? 20 : 10,
                  ),
                  child: Align(alignment: alignment, child: text),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (theme.componentBackgrounds[id] case final Map<String, dynamic> image)
      child = ThemeImageBackground(image: image, radius: radius, child: child);
    return _CustomSelection(
      id: id,
      label: label,
      child: ThemeElement(
        theme: theme,
        id: id,
        child: ThemePressEffect(
          componentId: id,
          style: theme.componentAnimations[id] ?? 'soft',
          enabled: theme.animationsEnabled,
          durationMs: theme.pressDurationMs,
          child: child,
        ),
      ),
    );
  }
}

class _CustomSelection extends StatefulWidget {
  final String id, label;
  final Widget child;
  const _CustomSelection({
    required this.id,
    required this.label,
    required this.child,
  });
  @override
  State<_CustomSelection> createState() => _CustomSelectionState();
}

class _CustomSelectionState extends State<_CustomSelection> {
  ThemeEditSession? session;
  @override
  void dispose() {
    session?.nodes.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = ThemeEditingScope.of(context);
    if (session != next) {
      session?.nodes.remove(widget.id);
      session = next;
    }
    session?.nodes[widget.id] = ThemeEditableNode(
      widget.id,
      widget.id,
      widget.label,
      context,
      [],
      interactive: themeWidgetIsInteractive(widget.child),
    );
    return widget.child;
  }
}
