import 'package:flutter/material.dart';

import '../../core/models/theme_config.dart';
import 'theme_element.dart';
import 'theme_press_effect.dart';

bool themeWidgetIsInteractive(Widget widget) {
  if (widget is IconButton ||
      widget is ButtonStyleButton ||
      widget is ListTile ||
      widget is TextField ||
      widget is GestureDetector ||
      widget is InkWell)
    return true;
  if (widget is ThemeElement) return themeWidgetIsInteractive(widget.child);
  if (widget is ThemePressEffect) return themeWidgetIsInteractive(widget.child);
  if (widget is Tooltip && widget.child != null)
    return themeWidgetIsInteractive(widget.child!);
  if (widget is Container && widget.child != null)
    return themeWidgetIsInteractive(widget.child!);
  if (widget is SingleChildRenderObjectWidget && widget.child != null)
    return themeWidgetIsInteractive(widget.child!);
  return false;
}

class ThemeEditableNode {
  final String id, sourceId;
  final String _label;
  final String Function()? describe;
  String get label => describe?.call() ?? _label;
  final bool interactive;
  final BuildContext context;
  final List<String> children;
  final bool supportsText;
  final bool isCanvas;
  ThemeEditableNode(
    this.id,
    this.sourceId,
    this._label,
    this.context,
    this.children, {
    this.supportsText = false,
    this.isCanvas = false,
    this.interactive = false,
    this.describe,
  });
  Rect? rect(ThemeConfig theme) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final scale = isCanvas ? 1.0 : theme.scaleFor(id);
    final size = box.size;
    final shift =
        (isCanvas ? Offset.zero : theme.offsetFor(id)) +
        Offset(size.width * (1 - scale) / 2, size.height * (1 - scale) / 2);
    return Rect.fromPoints(
      box.localToGlobal(shift),
      box.localToGlobal(
        shift + Offset(size.width * scale, size.height * scale),
      ),
    );
  }
}

class ThemeEditSession extends ChangeNotifier {
  ThemeConfig theme;
  final ValueChanged<ThemeConfig> onChange;
  final nodes = <String, ThemeEditableNode>{};
  final _undo = <ThemeConfig>[], _redo = <ThemeConfig>[];
  ThemeConfig? _gesture;
  String? selected;
  bool _scheduled = false;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    nodes.clear();
    super.dispose();
  }

  ThemeEditSession(this.theme, this.onChange);
  void refreshGeometry() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed && selected != null) notifyListeners();
    });
  }

  void update(ThemeConfig value) {
    if (_gesture == null) {
      _undo.add(theme);
      if (_undo.length > 80) _undo.removeAt(0);
      _redo.clear();
    }
    theme = value;
    onChange(value);
    notifyListeners();
    refreshGeometry();
  }

  void beginGesture() {
    _gesture = theme;
  }

  void endGesture() {
    if (_gesture != null) {
      _undo.add(_gesture!);
      _redo.clear();
      _gesture = null;
    }
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(theme);
    theme = _undo.removeLast();
    onChange(theme);
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(theme);
    theme = _redo.removeLast();
    onChange(theme);
    notifyListeners();
  }

  void select(String id) {
    selected = id;
    notifyListeners();
  }

  List<ThemeEditableNode> at(Offset point) {
    final result = nodes.values.where((n) {
      if (!n.context.mounted || ModalRoute.of(n.context)?.isCurrent == false)
        return false;
      final r = n.rect(theme);
      return r != null && r.width > 0 && r.height > 0 && r.contains(point);
    }).toList();
    int depth(ThemeEditableNode node) {
      var d = 0;
      node.context.visitAncestorElements((_) {
        d++;
        return true;
      });
      return d;
    }

    result.sort((a, b) {
      if (a.isCanvas != b.isCanvas) return a.isCanvas ? 1 : -1;
      if (a.interactive != b.interactive) return a.interactive ? -1 : 1;
      final ar = a.rect(theme)!, br = b.rect(theme)!;
      final area = (ar.width * ar.height).compareTo(br.width * br.height);
      return area != 0 ? area : depth(b).compareTo(depth(a));
    });
    return result;
  }

  void drag(Offset previous, Offset current) {
    final id = selected;
    final node = nodes[id];
    if (id == null || node == null || node.isCanvas) return;
    final box = node.context.findRenderObject();
    if (box is! RenderBox) return;
    final delta = box.globalToLocal(current) - box.globalToLocal(previous);
    update(
      theme.copyWith(
        componentOffsets: {
          ...theme.componentOffsets,
          id: theme.offsetFor(id) + delta,
        },
      ),
    );
  }

  void reorder(int direction) {
    final current = nodes[selected];
    if (current == null) return;
    String member = current.sourceId;
    ThemeEditableNode? group;
    current.context.visitAncestorElements((element) {
      if (element.widget is ThemeElement) {
        final w = element.widget as ThemeElement;
        if (!w.id.startsWith('widget_')) member = w.id;
      }
      for (final n in nodes.values.where(
        (n) => identical(n.context, element),
      )) {
        if (n.children.contains(member)) {
          group = n;
          return false;
        }
        member = n.sourceId;
      }
      return true;
    });
    if (group == null) return;
    final actual = [...group!.children];
    final order = theme.layoutOrders[group!.id] ?? actual;
    final sorted = [
      ...order.where(actual.contains),
      ...actual.where((id) => !order.contains(id)),
    ];
    final index = sorted.indexOf(member);
    final next = index + direction;
    if (index < 0 || next < 0 || next >= sorted.length) return;
    sorted.removeAt(index);
    sorted.insert(next, member);
    update(
      theme.copyWith(layoutOrders: {...theme.layoutOrders, group!.id: sorted}),
    );
  }

  void resetSelected() {
    final id = selected;
    if (id == null) return;
    update(
      theme.copyWith(
        componentOffsets: {...theme.componentOffsets}..remove(id),
        componentScales: {...theme.componentScales}..remove(id),
        componentColors: {...theme.componentColors}..remove(id),
        componentRadii: {...theme.componentRadii}..remove(id),
        componentOpacities: {...theme.componentOpacities}..remove(id),
        componentAnimations: {...theme.componentAnimations}..remove(id),
        componentTexts: {...theme.componentTexts}..remove(id),
        componentBackgrounds: {...theme.componentBackgrounds}..remove(id),
        componentMotions: {...theme.componentMotions}..remove(id),
        layoutOrders: {...theme.layoutOrders}..remove(id),
        hiddenElements: theme.hiddenElements.where((e) => e != id).toList(),
      ),
    );
  }
}

class ThemeEditingScope extends InheritedWidget {
  final ThemeEditSession session;
  const ThemeEditingScope({
    super.key,
    required this.session,
    required super.child,
  });
  static ThemeEditSession? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeEditingScope>()?.session;
  @override
  bool updateShouldNotify(ThemeEditingScope oldWidget) =>
      session != oldWidget.session;
}
