import 'country_flag.dart';
import '../../core/localization/app_localizations.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart';
import 'theme_element.dart';
import 'theme_press_effect.dart';
import 'custom_theme_elements.dart';
import 'theme_edit_session.dart';
import 'theme_widget_style.dart';
import 'theme_image_background.dart';

const themeScreenRegions = <String, String>{
  'screen_settings': 'Настройки: содержимое',
  'screen_subscriptions': 'Подписки: содержимое',
  'screen_apps': 'Приложения: содержимое',
  'screen_statistics': 'Статистика: содержимое',
  'screen_profiles': 'Профили: содержимое',
  'screen_rules': 'Правила: содержимое',
  'screen_chains': 'Цепочки: содержимое',
  'screen_diagnostics': 'Диагностика: содержимое',
  'screen_backup': 'Резервная копия: содержимое',
  'screen_history': 'История автоматизации: содержимое',
  'screen_config_editor': 'Конструктор конфигурации',
  'screen_chain_editor': 'Редактор цепочки',
  'screen_wg_editor': 'Редактор WireGuard',
  'screen_json_editor': 'Редактор JSON',
};

class ThemeRegionRegistry {
  static final labels = <String, String>{
    ...themeScreenRegions,
    'home_subscriptions_button': 'Подписки',
    'home_rules_button': 'Правила',
    'home_apps_button': 'Приложения',
    'home_settings_button': 'Настройки',
    'home_profiles_button': 'Профили',
    'home_power_button': 'Кнопка VPN и таймер',
    'home_system_info': 'IP и память ядра',
    'home_map_canvas': 'Земной шар',
  };
  static String labelFor(String id) {
    if (labels.containsKey(id)) return labels[id]!;
    for (final prefix in ['settings_row_', 'app_route_']) {
      if (id.startsWith(prefix)) {
        try {
          return utf8.decode(
            base64Url.decode(base64Url.normalize(id.substring(prefix.length))),
          );
        } catch (_) {}
      }
    }
    return id;
  }

  static String named(String group, String label, {String? stableKey}) {
    final id =
        '${group}_${base64Url.encode(utf8.encode(stableKey ?? label)).replaceAll('=', '')}';
    labels[id] = label;
    return id;
  }
}

/// Regions add per-component theme controls outside the home screen.
/// Hidden screen regions retain an escape hatch for restoring their content.
class ThemeRegion extends ConsumerStatefulWidget {
  final String id;
  final Widget child;
  final String? label;
  final bool automatic;
  final bool canvas;
  const ThemeRegion({
    super.key,
    required this.id,
    required this.child,
    this.label,
    this.canvas = false,
  }) : automatic = false;
  const ThemeRegion.auto({
    super.key,
    required this.id,
    required this.child,
    this.label,
    this.canvas = false,
  }) : automatic = true;
  @override
  ConsumerState<ThemeRegion> createState() => _ThemeRegionState();
}

String _describeWidget(Widget widget, String fallback) {
  final texts = <String>[];
  void read(Widget? w, int depth) {
    if (w == null || depth > 10 || texts.length >= 2) return;
    String? text;
    if (w is Text) text = w.data;
    if (w is IconButton) text = w.tooltip;
    if (w is Tooltip) text = w.message;
    if (w is TextField)
      text =
          w.decoration?.labelText ??
          w.decoration?.hintText ??
          w.controller?.text;
    if (w is ThemeRegion && !w.automatic)
      text = w.label ?? ThemeRegionRegistry.labelFor(w.id);
    if (text != null && text.trim().isNotEmpty) {
      texts.add(text.trim());
      return;
    }
    if (w is FlagText)
      read(w.original, depth + 1);
    else if (w is Container)
      read(w.child, depth + 1);
    else if (w is ThemeRegion)
      read(w.child, depth + 1);
    else if (w is ThemeElement)
      read(w.child, depth + 1);
    else if (w is ThemePressEffect)
      read(w.child, depth + 1);
    else if (w is ButtonStyleButton)
      read(w.child, depth + 1);
    else if (w is ListTile)
      read(w.title, depth + 1);
    else if (w is SingleChildRenderObjectWidget)
      read(w.child, depth + 1);
    else if (w is Flex) {
      for (final c in w.children) read(c, depth + 1);
    } else if (w is Stack) {
      for (final c in w.children) read(c, depth + 1);
    } else if (w is Wrap) {
      for (final c in w.children) read(c, depth + 1);
    }
  }

  read(widget, 0);
  if (texts.isEmpty) return fallback;
  final content = texts.join(' · ');
  final clipped = content.length > 100
      ? '${content.substring(0, 100)}…'
      : content;
  return widget is Text ? clipped : '$fallback: $clipped';
}

class _ThemeRegionState extends ConsumerState<ThemeRegion> {
  ThemeEditSession? _session;
  String? _registered;
  @override
  void dispose() {
    if (_session?.nodes[_registered]?.context == context)
      _session?.nodes.remove(_registered);
    super.dispose();
  }

  String runtimeId() {
    if (!widget.automatic) return widget.id;
    final parts = <String>[];
    context.visitAncestorElements((e) {
      final w = e.widget;
      if (w is IndexedSemantics) parts.add('i${w.index}');
      if (w is ThemeElement && !w.id.startsWith('widget_')) {
        parts.add(w.id);
        return false;
      }
      return true;
    });
    final key = widget.child.key;
    if (key is ValueKey) {
      var hash = 2166136261;
      for (final code in key.value.toString().codeUnits) {
        hash = ((hash ^ code) * 16777619) & 0xffffffff;
      }
      parts.add('k${hash.toRadixString(16)}');
    }
    return parts.isEmpty ? widget.id : '${widget.id}@${parts.join(':')}';
  }

  String _description(String fallback) {
    final value = _describeWidget(widget.child, fallback);
    if (value != fallback) return value;
    String? parent;
    context.visitAncestorElements((element) {
      final w = element.widget;
      if (w is ThemeRegion && !w.automatic && w.label != null) {
        parent = w.label;
        return false;
      }
      if (w is ThemeElement && ThemeRegionRegistry.labels.containsKey(w.id)) {
        parent = ThemeRegionRegistry.labels[w.id];
        return false;
      }
      return true;
    });
    return parent == null || parent == fallback
        ? fallback
        : '$parent · $fallback';
  }

  @override
  Widget build(BuildContext context) {
    final id = runtimeId();
    var rootGroup = true;
    context.visitAncestorElements((e) {
      if (e.widget is ThemeRegion) {
        rootGroup = false;
        return false;
      }
      return true;
    });
    final isCanvas =
        widget.canvas ||
        id.startsWith('screen_') ||
        rootGroup &&
            (widget.child is Stack ||
                widget.child is Column ||
                widget.child is Container);
    final session = ThemeEditingScope.of(context);
    if (_registered != id || _session != session) {
      _session?.nodes.remove(_registered);
      _registered = id;
      _session = session;
    }
    var label = widget.label ?? ThemeRegionRegistry.labelFor(id);
    if (widget.automatic && label.contains(' · ')) {
      label =
          const {
            'Text': 'Надпись',
            'Icon': 'Значок',
            'TextField': 'Поле ввода',
            'TextFormField': 'Поле ввода',
            'IconButton': 'Кнопка со значком',
            'TextButton': 'Кнопка',
            'FilledButton': 'Кнопка',
            'OutlinedButton': 'Кнопка',
            'ElevatedButton': 'Кнопка',
            'ListTile': 'Строка',
            'SwitchListTile': 'Строка с переключателем',
            'CheckboxListTile': 'Строка с флажком',
            'Switch': 'Переключатель',
            'Checkbox': 'Флажок',
            'Slider': 'Ползунок',
            'Container': 'Плашка',
            'Card': 'Карточка',
            'Row': 'Горизонтальная группа',
            'Column': 'Вертикальная группа',
            'Wrap': 'Группа с переносом',
            'Stack': 'Слои',
          }[label.split(' · ').first] ??
          'Элемент';
    }
    ThemeRegionRegistry.labels[id] = widget.child is Text
        ? ((widget.child as Text).data ?? label)
        : label;
    if (session != null) {
      session.nodes[id] = ThemeEditableNode(
        id,
        widget.id,
        ThemeRegionRegistry.labels[id]!,
        context,
        layoutChildIds(widget.child),
        supportsText: widget.child is Text,
        isCanvas: isCanvas,
        interactive: themeWidgetIsInteractive(widget.child),
        describe: widget.automatic ? () => _description(label) : null,
      );
    }
    final config = ref.watch(themeProvider).currentTheme;
    if (config.hiddenElements.contains(id)) {
      if (!id.startsWith('screen_')) return const SizedBox.shrink();
      return Center(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.visibility_outlined),
          label: Text(
            AppLocalizations.text(context, "Показать скрытое содержимое"),
          ),
          onPressed: () {
            final updated = config.copyWith(
              hiddenElements: config.hiddenElements
                  .where((e) => e != id)
                  .toList(),
            );
            ref.read(themeProvider.notifier).updateTheme(updated);
          },
        ),
      );
    }
    Widget result = reorderThemeLayout(widget.child, config.layoutOrders[id]);
    if (config.componentTexts.containsKey(id) && result is Text) {
      final text = result;
      result = Text(
        config.componentTexts[id]!,
        style: text.style,
        strutStyle: text.strutStyle,
        textAlign: text.textAlign,
        textDirection: text.textDirection,
        locale: text.locale,
        softWrap: text.softWrap,
        overflow: text.overflow,
        textScaler: text.textScaler,
        maxLines: text.maxLines,
        semanticsLabel: text.semanticsLabel,
        textWidthBasis: text.textWidthBasis,
        textHeightBehavior: text.textHeightBehavior,
        selectionColor: text.selectionColor,
      );
    }
    if (id.startsWith('screen_') &&
        config.customElements.any((e) => e['screen'] == id)) {
      result = Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .25,
            ),
            child: SingleChildScrollView(
              child: CustomThemeElements(theme: config, screen: id),
            ),
          ),
          Expanded(child: result),
        ],
      );
    }
    if ((id.startsWith('screen_') || isCanvas && widget.child is Stack) &&
        config.customElements.any(
          (e) =>
              e['placement'] == 'overlay' &&
              (e['screen'] ?? 'home') ==
                  (id.startsWith('screen_') ? id : 'home'),
        )) {
      result = Stack(
        fit: StackFit.passthrough,
        children: [
          result,
          Positioned.fill(
            child: CustomThemeElements(
              theme: config,
              screen: id.startsWith('screen_') ? id : 'home',
              overlay: true,
            ),
          ),
        ],
      );
    }
    if (config.componentColors.containsKey(id) ||
        config.componentRadii.containsKey(id)) {
      result = styleThemeWidget(
        result,
        color: config.componentColors.containsKey(id)
            ? config.colorFor(id)
            : null,
        radius: config.componentRadii[id],
      );
    }
    final imageFlags = result is Text && FlagText.containsFlags(result.data);
    if (imageFlags) {
      result = FlagText(
        original: result,
        color: config.componentColors.containsKey(id)
            ? config.colorFor(id)
            : null,
      );
    }
    if (config.componentColors.containsKey(id)) {
      final color = config.colorFor(id);
      if ((widget.child is Text && !imageFlags) || widget.child is Icon) {
        result = ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: result,
        );
      }
      result = Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: color),
          primaryColor: color,
        ),
        child: result,
      );
    }
    if (config.componentBackgrounds[id] case final Map<String, dynamic> image) {
      result = ThemeImageBackground(
        image: image,
        radius: config.radiusFor(id),
        child: result,
      );
    }
    if (config.componentRadii.containsKey(id))
      result = ClipRRect(
        borderRadius: BorderRadius.circular(config.radiusFor(id)),
        child: result,
      );
    if (config.componentAnimations.containsKey(id))
      result = ThemePressEffect(
        componentId: id,
        style: config.componentAnimations[id]!,
        enabled: config.animationsEnabled,
        durationMs: config.pressDurationMs,
        child: result,
      );
    return ThemeElement(
      theme: config,
      id: id,
      isCanvas: isCanvas,
      child: result,
    );
  }
}

String? themeChildId(Widget child) {
  if (child is ThemeRegion) return child.id;
  if (child is Flexible) return themeChildId(child.child);
  if (child is Positioned) return themeChildId(child.child);
  if (child is ThemeElement) return child.id;
  if (child is ThemePressEffect) return themeChildId(child.child);
  if (child is Padding) return themeChildId(child.child!);
  if (child is SizedBox && child.child != null)
    return themeChildId(child.child!);
  return null;
}

List<Widget>? themeLayoutChildren(Widget widget) => switch (widget) {
  Row w => w.children,
  Column w => w.children,
  Wrap w => w.children,
  Stack w => w.children,
  _ => null,
};
List<String> layoutChildIds(Widget widget) {
  final ids = (themeLayoutChildren(widget) ?? [])
      .map(themeChildId)
      .whereType<String>()
      .toList();
  return ids.toSet().length == ids.length ? ids : [];
}

Widget reorderThemeLayout(Widget widget, List<String>? order) {
  if (order == null || order.isEmpty) return widget;
  final original = themeLayoutChildren(widget);
  if (original == null) return widget;
  final ids = layoutChildIds(widget);
  if (ids.isEmpty) return widget;
  final movable = original.where((w) => themeChildId(w) != null).toList();
  movable.sort((a, b) {
    int rank(Widget w) {
      final i = order.indexOf(themeChildId(w)!);
      return i < 0 ? order.length + ids.indexOf(themeChildId(w)!) : i;
    }

    return rank(a).compareTo(rank(b));
  });
  var index = 0;
  final children = [
    for (final child in original)
      themeChildId(child) == null
          ? child
          : KeyedSubtree(
              key: ValueKey(themeChildId(movable[index])),
              child: movable[index++],
            ),
  ];
  if (widget is Row)
    return Row(
      key: widget.key,
      mainAxisAlignment: widget.mainAxisAlignment,
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: widget.crossAxisAlignment,
      textDirection: widget.textDirection,
      verticalDirection: widget.verticalDirection,
      textBaseline: widget.textBaseline,
      spacing: widget.spacing,
      children: children,
    );
  if (widget is Column)
    return Column(
      key: widget.key,
      mainAxisAlignment: widget.mainAxisAlignment,
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: widget.crossAxisAlignment,
      textDirection: widget.textDirection,
      verticalDirection: widget.verticalDirection,
      textBaseline: widget.textBaseline,
      spacing: widget.spacing,
      children: children,
    );
  if (widget is Wrap)
    return Wrap(
      key: widget.key,
      direction: widget.direction,
      alignment: widget.alignment,
      spacing: widget.spacing,
      runAlignment: widget.runAlignment,
      runSpacing: widget.runSpacing,
      crossAxisAlignment: widget.crossAxisAlignment,
      textDirection: widget.textDirection,
      verticalDirection: widget.verticalDirection,
      clipBehavior: widget.clipBehavior,
      children: children,
    );
  if (widget is Stack)
    return Stack(
      key: widget.key,
      alignment: widget.alignment,
      textDirection: widget.textDirection,
      fit: widget.fit,
      clipBehavior: widget.clipBehavior,
      children: children,
    );
  return widget;
}
