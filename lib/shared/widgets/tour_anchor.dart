import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Geometry of the real controls, after the user's theme transforms.
class TourAnchor extends StatefulWidget {
  static const targets = {
    'home_map_canvas',
    'widget_globe_controls_22',
    'widget_globe_controls_21',
    'widget_globe_controls_20',
    'home_ping',
    'home_traffic',
    'home_ip_details',
    'home_rules_button',
    'home_apps_button',
    'widget_main_22',
    'widget_profiles_screen_9',
    'home_subscriptions_button',
    'widget_subscriptions_screen_49',
    'home_power_button',
    'home_settings_button',
  };
  static final _contexts = <String, Set<BuildContext>>{};
  static Widget wrap(String id, Widget child) {
    final source = id.split('@').first;
    return targets.contains(source)
        ? TourAnchor(id: source, child: child)
        : child;
  }

  static Rect? rect(String id) {
    for (final context in _contexts[id] ?? <BuildContext>{}) {
      if (!context.mounted || ModalRoute.of(context)?.isCurrent == false)
        continue;
      var visible = true;
      context.visitAncestorElements((e) {
        if (e.widget case Opacity(opacity: 0)) visible = false;
        return visible;
      });
      if (!visible) continue;
      final box = context.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          !box.size.isEmpty) {
        return MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
      }
    }
    return null;
  }

  final String id;
  final Widget child;
  const TourAnchor({super.key, required this.id, required this.child});
  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    (TourAnchor._contexts[widget.id] ??= {}).add(context);
  }

  @override
  void didUpdateWidget(covariant TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      TourAnchor._contexts[old.id]?.remove(context);
      (TourAnchor._contexts[widget.id] ??= {}).add(context);
    }
  }

  @override
  void dispose() {
    final contexts = TourAnchor._contexts[widget.id];
    contexts?.remove(context);
    if (contexts?.isEmpty == true) TourAnchor._contexts.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
