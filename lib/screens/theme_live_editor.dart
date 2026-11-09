import '../core/localization/app_localizations.dart';
export '../shared/widgets/theme_color_palette.dart' show ThemeColorPalette;
import '../shared/widgets/theme_color_palette.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/theme_config.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../shared/widgets/theme_edit_session.dart';
import 'theme_screen_preview.dart';
import 'theme_custom_element_dialog.dart';
import 'theme_image_cropper.dart';

/// Theme changes stay in a draft. Interaction is an explicit, separate mode.
class ThemeLiveEditor extends StatefulWidget {
  final ThemeConfig theme;
  final Widget Function(String)? screenBuilder;
  const ThemeLiveEditor({super.key, required this.theme, this.screenBuilder});
  @override
  State<ThemeLiveEditor> createState() => _ThemeLiveEditorState();
}

class _ThemeLiveEditorState extends State<ThemeLiveEditor> {
  late final ThemeEditSession session;
  late final ProviderContainer preview;
  ThemeConfig? _themeForData;
  ThemeData? _themeData;
  final canvasKey = GlobalKey();
  String scene = 'screen_home';
  Offset? previous;
  Offset? _layerPoint;
  bool moveElements = true;
  bool interacting = false;
  ScrollPosition? scrollPosition;
  @override
  void initState() {
    super.initState();
    preview = ProviderContainer(
      parent: ProviderScope.containerOf(context, listen: false),
      overrides: [
        themeProvider.overrideWith(
          (ref) => ThemeNotifier.preview(widget.theme),
        ),
      ],
    );
    session = ThemeEditSession(widget.theme, (value) {
      preview.read(themeProvider.notifier).setTheme(value);
    });
  }

  @override
  void dispose() {
    session.dispose();
    preview.dispose();
    super.dispose();
  }

  void selectAt(Offset position) {
    _layerPoint = position;
    final nodes = session.at(position);
    if (nodes.isNotEmpty) session.select(nodes.first.id);
  }

  List<ThemeEditableNode> _layers() {
    final selected = session.nodes[session.selected];
    final point = _layerPoint ?? selected?.rect(session.theme)?.center;
    final layers = point == null ? <ThemeEditableNode>[] : session.at(point);
    if (selected != null && !layers.any((n) => n.id == selected.id))
      layers.add(selected);
    return layers;
  }

  void _cycleLayer(int direction) {
    final layers = _layers();
    if (layers.isEmpty) return;
    final index = layers.indexWhere((n) => n.id == session.selected);
    session.select(
      layers[(index + direction + layers.length) % layers.length].id,
    );
  }

  Future<void> chooseElement() async {
    final nodes = session.nodes.values.toList();
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _Glass(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            children: [
              ListTile(
                title: Text(AppLocalizations.text(context, "Элементы экрана")),
              ),
              for (final node in nodes)
                ListTile(
                  dense: true,
                  title: Text(
                    node.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: Icon(
                    session.theme.hiddenElements.contains(node.id)
                        ? Icons.visibility_off_outlined
                        : Icons.widgets_outlined,
                  ),
                  onTap: () => Navigator.pop(context, node.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && id != null) {
      _layerPoint = session.nodes[id]?.rect(session.theme)?.center;
      session.select(id);
    }
  }

  Future<void> editCustom([Map<String, dynamic>? element]) async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ThemeCustomElementDialog(element: element),
    );
    if (!mounted || updated == null) return;
    String screen = 'home';
    for (final n in session.nodes.values) {
      if (n.id.startsWith('screen_') &&
          ModalRoute.of(n.context)?.isCurrent == true)
        screen = n.id;
    }
    final item = {...updated, 'screen': element?['screen'] ?? screen};
    final items = [...session.theme.customElements];
    final index = items.indexWhere((e) => e['id'] == item['id']);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
    session.update(session.theme.copyWith(customElements: items));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) session.select('custom_${item['id']}');
    });
  }

  Future<void> imageBackground(String id, {bool existing = false}) async {
    try {
      final bytes = existing
          ? base64Decode(
              session.theme.componentBackgrounds[id]!['data'] as String,
            )
          : await pickThemeImage();
      if (bytes == null || !mounted) return;
      final rect = session.nodes[id]?.rect(session.theme);
      final cropped = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => ThemeImageCropper(
            bytes: bytes,
            aspectRatio: rect == null || rect.height == 0
                ? 1.6
                : rect.width / rect.height,
          ),
        ),
      );
      if (!mounted || cropped == null) return;
      session.update(
        session.theme.copyWith(
          componentBackgrounds: {
            ...session.theme.componentBackgrounds,
            id: {'data': base64Encode(cropped), 'dim': .25},
          },
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.text(
                context,
                "Не удалось добавить фон: {0}",
                args: [error],
              ),
            ),
          ),
        );
    }
  }

  Future<void> editText(String id) async {
    final controller = TextEditingController(
      text: session.theme.componentTexts[id] ?? session.nodes[id]?.label ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: _Glass(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.text(context, "Текст элемента"),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.text(context, "Отмена")),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: Text(AppLocalizations.text(context, "Готово")),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The dialog route retains its field through the closing animation.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (mounted && value != null)
      session.update(
        session.theme.copyWith(
          componentTexts: {...session.theme.componentTexts, id: value},
        ),
      );
  }

  Future<void> editColor(String id) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeColorPalette(initial: session.theme.colorFor(id)),
    );
    if (mounted && color != null)
      session.update(
        session.theme.copyWith(
          componentColors: {
            ...session.theme.componentColors,
            id: color.toARGB32(),
          },
        ),
      );
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> changed,
  ) => Row(
    children: [
      SizedBox(width: 94, child: Text(AppLocalizations.text(context, label))),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChangeStart: (_) => session.beginGesture(),
          onChangeEnd: (_) => session.endGesture(),
          onChanged: changed,
        ),
      ),
      SizedBox(width: 42, child: Text(value.toStringAsFixed(1))),
    ],
  );
  Widget properties() {
    final id = session.selected;
    final node = session.nodes[id];
    if (id == null || node == null)
      return SizedBox(
        height: 235,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            AppLocalizations.text(
              context,
              "Коснитесь элемента на экране. Перетаскивайте, чтобы изменить положение. Список позволяет выбрать контейнер или скрытый элемент.",
            ),
          ),
        ),
      );
    final t = session.theme;
    final hidden = t.hiddenElements.contains(id);
    final layers = _layers();
    final layerIndex = layers.indexWhere((n) => n.id == id);
    return SizedBox(
      height: 235,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: AppLocalizations.text(context, 'Предыдущий слой'),
                  onPressed: layers.length < 2 ? null : () => _cycleLayer(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    AppLocalizations.text(
                      context,
                      'Слой {0} из {1}',
                      args: [layerIndex + 1, layers.length],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.text(context, 'Следующий слой'),
                  onPressed: layers.length < 2 ? null : () => _cycleLayer(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),

            Row(
              children: [
                Expanded(
                  child: Text(
                    node.label,
                    key: const ValueKey('selected-theme-layer'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.text(
                    context,
                    "Выбрать родительский элемент",
                  ),
                  onPressed: () {
                    node.context.visitAncestorElements((element) {
                      for (final n in session.nodes.values) {
                        if (identical(n.context, element)) {
                          session.select(n.id);
                          return false;
                        }
                      }
                      return true;
                    });
                  },
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: hidden
                      ? AppLocalizations.text(context, "Показать")
                      : AppLocalizations.text(context, "Скрыть"),
                  onPressed: () => session.update(
                    t.copyWith(
                      hiddenElements: hidden
                          ? t.hiddenElements.where((e) => e != id).toList()
                          : [...t.hiddenElements, id],
                    ),
                  ),
                  icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
                ),
                IconButton(
                  tooltip: AppLocalizations.text(context, "Сбросить элемент"),
                  onPressed: session.resetSelected,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (id.startsWith('custom_'))
                  OutlinedButton.icon(
                    onPressed: () => editCustom(
                      t.customElements.firstWhere(
                        (e) => 'custom_${e['id']}' == id,
                      ),
                    ),
                    icon: const Icon(Icons.bolt, size: 18),
                    label: Text(
                      AppLocalizations.text(context, "Текст и действие"),
                    ),
                  ),
                if (id.startsWith('custom_'))
                  IconButton(
                    tooltip: AppLocalizations.text(
                      context,
                      "Удалить мой элемент",
                    ),
                    onPressed: () => session.update(
                      t.copyWith(
                        customElements: t.customElements
                            .where((e) => 'custom_${e['id']}' != id)
                            .toList(),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                OutlinedButton.icon(
                  onPressed: () => imageBackground(id),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(
                    AppLocalizations.text(context, "Фон из картинки"),
                  ),
                ),
                if (t.componentBackgrounds.containsKey(id))
                  IconButton(
                    tooltip: AppLocalizations.text(context, "Обрезать фон"),
                    onPressed: () => imageBackground(id, existing: true),
                    icon: const Icon(Icons.crop),
                  ),
                if (t.componentBackgrounds.containsKey(id))
                  IconButton(
                    tooltip: AppLocalizations.text(context, "Удалить картинку"),
                    onPressed: () => session.update(
                      t.copyWith(
                        componentBackgrounds: {...t.componentBackgrounds}
                          ..remove(id),
                      ),
                    ),
                    icon: const Icon(Icons.hide_image_outlined),
                  ),
                if (node.supportsText)
                  OutlinedButton.icon(
                    onPressed: () => editText(id),
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(AppLocalizations.text(context, "Текст")),
                  ),
                OutlinedButton.icon(
                  onPressed: () => editColor(id),
                  icon: const Icon(Icons.palette_outlined, size: 18),
                  label: Text(AppLocalizations.text(context, "Цвет")),
                ),
                IconButton(
                  tooltip: AppLocalizations.text(context, "Раньше в группе"),
                  onPressed: () => session.reorder(-1),
                  icon: const Icon(Icons.move_up),
                ),
                IconButton(
                  tooltip: AppLocalizations.text(context, "Позже в группе"),
                  onPressed: () => session.reorder(1),
                  icon: const Icon(Icons.move_down),
                ),
              ],
            ),
            if (!node.isCanvas)
              slider(
                AppLocalizations.text(context, "Масштаб"),
                t.scaleFor(id),
                .65,
                1.35,
                (v) => session.update(
                  t.copyWith(componentScales: {...t.componentScales, id: v}),
                ),
              ),
            slider(
              AppLocalizations.text(context, "Непрозрачность"),
              t.opacityFor(id),
              .1,
              1,
              (v) => session.update(
                t.copyWith(
                  componentOpacities: {...t.componentOpacities, id: v},
                ),
              ),
            ),
            slider(
              AppLocalizations.text(context, "Скругление"),
              t.radiusFor(id),
              0,
              80,
              (v) => session.update(
                t.copyWith(componentRadii: {...t.componentRadii, id: v}),
              ),
            ),
            if (!node.isCanvas)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.text(context, "Постоянная анимация"),
                    ),
                  ),
                  DropdownButton<String>(
                    value: t.componentMotions[id] ?? 'none',
                    items: [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text(AppLocalizations.text(context, "Нет")),
                      ),
                      DropdownMenuItem(
                        value: 'pulse',
                        child: Text(
                          AppLocalizations.text(context, "Пульсация"),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'float',
                        child: Text(AppLocalizations.text(context, "Парение")),
                      ),
                      DropdownMenuItem(
                        value: 'swing',
                        child: Text(
                          AppLocalizations.text(context, "Покачивание"),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'fade',
                        child: Text(AppLocalizations.text(context, "Мерцание")),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null)
                        session.update(
                          t.copyWith(
                            componentMotions: {...t.componentMotions, id: v},
                          ),
                        );
                    },
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.text(context, "Анимация нажатия"),
                  ),
                ),
                DropdownButton<String>(
                  value: t.componentAnimations[id] ?? 'none',
                  items: [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text(AppLocalizations.text(context, "Нет")),
                    ),
                    DropdownMenuItem(
                      value: 'soft',
                      child: Text(AppLocalizations.text(context, "Сжатие")),
                    ),
                    DropdownMenuItem(
                      value: 'bounce',
                      child: Text(AppLocalizations.text(context, "Пружина")),
                    ),
                    DropdownMenuItem(
                      value: 'grow',
                      child: Text(AppLocalizations.text(context, "Увеличение")),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null)
                      session.update(
                        t.copyWith(
                          componentAnimations: {
                            ...t.componentAnimations,
                            id: v,
                          },
                        ),
                      );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final t = session.theme;
      final fullSize = MediaQuery.sizeOf(context);
      if (!identical(_themeForData, t)) {
        _themeForData = t;
        _themeData = AppTheme.buildTheme(t);
      }
      return Theme(
        data: _themeData!,
        child: Scaffold(
          backgroundColor: t.background,
          appBar: AppBar(
            title: Text(AppLocalizations.text(context, "На экране")),
            actions: [
              IconButton(
                tooltip: AppLocalizations.text(context, "Отменить изменение"),
                onPressed: session.undo,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: AppLocalizations.text(context, "Повторить изменение"),
                onPressed: session.redo,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: AppLocalizations.text(context, "Принять в черновик"),
                onPressed: () => Navigator.pop(context, session.theme),
                icon: const Icon(Icons.check),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.edit_outlined),
                      label: Text(
                        AppLocalizations.text(context, "Редактировать"),
                      ),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.touch_app_outlined),
                      label: Text(AppLocalizations.text(context, "Нажимать")),
                    ),
                  ],
                  selected: {interacting},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => setState(() {
                    FocusManager.instance.primaryFocus?.unfocus();
                    interacting = value.single;
                    previous = null;
                    scrollPosition = null;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => editCustom(),
                        icon: const Icon(Icons.add),
                        label: Text(
                          AppLocalizations.text(context, "Добавить элемент"),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: moveElements
                          ? AppLocalizations.text(
                              context,
                              "Перейти к прокрутке",
                            )
                          : AppLocalizations.text(
                              context,
                              "Перейти к перемещению элементов",
                            ),
                      onPressed: () =>
                          setState(() => moveElements = !moveElements),
                      icon: Icon(
                        moveElements
                            ? Icons.touch_app_outlined
                            : Icons.swipe_vertical_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.text(
                        context,
                        "Список элементов",
                      ),
                      onPressed: chooseElement,
                      icon: const Icon(Icons.layers_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    key: canvasKey,
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: fullSize.width,
                              height: fullSize.height,
                              child: MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  size: fullSize,
                                  padding: EdgeInsets.zero,
                                  viewPadding: EdgeInsets.zero,
                                ),
                                child: UncontrolledProviderScope(
                                  container: preview,
                                  child: ThemeEditingScope(
                                    session: session,
                                    child: IgnorePointer(
                                      ignoring: !interacting,
                                      child: Navigator(
                                        key: ValueKey(scene),
                                        onGenerateRoute: (_) =>
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  widget.screenBuilder?.call(
                                                    scene,
                                                  ) ??
                                                  themePreviewScreen(scene),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!interacting)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) {
                            if (moveElements) selectAt(d.globalPosition);
                          },
                          onPanStart: (d) {
                            if (!moveElements) {
                              final candidates = session.at(d.globalPosition);
                              scrollPosition = null;
                              for (final node in candidates) {
                                final scroll = Scrollable.maybeOf(node.context);
                                if (scroll != null) {
                                  scrollPosition = scroll.position;
                                  break;
                                }
                              }
                              return;
                            }
                            final selected = session.nodes[session.selected]
                                ?.rect(session.theme);
                            if (selected == null ||
                                !selected.contains(d.globalPosition))
                              selectAt(d.globalPosition);
                            previous = d.globalPosition;
                            session.beginGesture();
                          },
                          onPanUpdate: (d) {
                            if (!moveElements) {
                              final p = scrollPosition;
                              if (p != null && p.hasPixels) {
                                final box = canvasKey.currentContext
                                    ?.findRenderObject();
                                final scale = box is RenderBox
                                    ? box.size.height / fullSize.height
                                    : 1.0;
                                p.jumpTo(
                                  (p.pixels - d.delta.dy / scale).clamp(
                                    p.minScrollExtent,
                                    p.maxScrollExtent,
                                  ),
                                );
                                session.refreshGeometry();
                              }
                              return;
                            }
                            if (previous != null)
                              session.drag(previous!, d.globalPosition);
                            previous = d.globalPosition;
                          },
                          onPanEnd: (_) {
                            previous = null;
                            session.endGesture();
                          },
                          onPanCancel: () {
                            previous = null;
                            session.endGesture();
                          },
                        ),
                      if (!interacting &&
                          session.nodes[session.selected]?.rect(t) != null)
                        if (session.nodes[session.selected]?.rect(t)
                            case final Rect rect)
                          Builder(
                            builder: (context) {
                              final box = canvasKey.currentContext
                                  ?.findRenderObject();
                              if (box is! RenderBox)
                                return const SizedBox.shrink();
                              final offset = box.globalToLocal(rect.topLeft);
                              return Positioned(
                                left: offset.dx,
                                top: offset.dy,
                                width: rect.width,
                                height: rect.height,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: t.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                    ],
                  ),
                ),
              ),
              _Glass(
                child: interacting
                    ? Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          AppLocalizations.text(
                            context,
                            "Открывайте разделы и меню, затем нажмите «Редактировать». Кнопки и настройки здесь действуют как в приложении.",
                          ),
                        ),
                      )
                    : properties(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .66),
        child: child,
      ),
    ),
  );
}
