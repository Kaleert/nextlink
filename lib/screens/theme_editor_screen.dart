import 'theme_live_editor.dart';
import '../shared/widgets/theme_region.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:ui';

import '../core/models/theme_config.dart';
import '../shared/widgets/glass_dropdown.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../core/localization/app_localizations.dart';
import '../shared/widgets/animated_background.dart';

Future<bool> _confirmThemeDeletion(
  BuildContext context,
  ThemeConfig theme,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: theme.surface.withOpacity(.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
        side: BorderSide(color: theme.primary.withOpacity(.3)),
      ),
      title: Text(AppLocalizations.text(context, "Удалить тему?")),
      content: Text(
        AppLocalizations.text(
          context,
          "Тема «{0}» будет удалена с устройства.",
          args: [theme.name],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppLocalizations.text(context, "Отмена")),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppLocalizations.text(context, "Удалить")),
        ),
      ],
    ),
  );
  return confirmed == true;
}

PageRouteBuilder<void> themeEditorRoute({ThemeConfig? theme}) =>
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withOpacity(.18),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) =>
          ThemeEditorScreen(initialTheme: theme),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );

class ThemeGalleryScreen extends ConsumerWidget {
  const ThemeGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(themeProvider);
    final themes = [
      ThemeConfig.defaultTheme,
      ThemeConfig.emeraldGreen,
      ThemeConfig.oceanicBlue,
      ThemeConfig.neonOrigami,
      ...state.customThemes,
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: state.currentTheme.surface.withValues(alpha: .65),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: const SizedBox.expand(),
          ),
        ),
        title: Text(AppLocalizations.text(context, "Темы NextLink")),
        actions: [
          IconButton(
            tooltip: AppLocalizations.text(context, "Создать тему"),
            onPressed: () => Navigator.push(context, themeEditorRoute()),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedMeshBackground(isConnected: false),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: .24)),
            ),
          ),
          ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
              16,
              MediaQuery.paddingOf(context).bottom + 28,
            ),
            itemCount: themes.length,
            itemBuilder: (context, index) {
              final theme = themes[index];
              final selected = theme.name == state.currentTheme.name;
              final isCustom = state.customThemes.any(
                (item) => item.name == theme.name,
              );
              final localizedName = theme.name.startsWith('theme_')
                  ? (AppLocalizations.of(context)?.translate(theme.name) ??
                        theme.name)
                  : theme.name;
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: theme.surface.withOpacity(.55),
                  borderRadius: BorderRadius.circular(theme.cardRadius),
                  border: Border.all(
                    color: selected
                        ? theme.primary.withOpacity(.75)
                        : Colors.white.withOpacity(.12),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 68,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.background,
                              theme.meshIdle1,
                              theme.primaryDark.withOpacity(.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(
                            theme.cardRadius - 6,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text(
                                localizedName,
                                style: TextStyle(
                                  color: theme.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.auto_awesome_rounded,
                                color: theme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        theme.description.isEmpty
                            ? AppLocalizations.text(
                                context,
                                "Авторская тема NextLink",
                              )
                            : (theme.isBuiltIn
                                  ? AppLocalizations.text(
                                      context,
                                      theme.description,
                                    )
                                  : theme.description),
                        style: TextStyle(color: theme.textDim),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.text(
                          context,
                          "Автор: {0}",
                          args: [
                            theme.author.isEmpty ? 'NextLink' : theme.author,
                          ],
                        ),
                        style: TextStyle(
                          color: theme.textDim.withOpacity(.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref
                                    .read(themeProvider.notifier)
                                    .setTheme(theme);
                              },
                              icon: Icon(
                                selected
                                    ? Icons.check_rounded
                                    : Icons.palette_outlined,
                              ),
                              label: Text(
                                selected
                                    ? AppLocalizations.text(
                                        context,
                                        "Применена",
                                      )
                                    : AppLocalizations.text(
                                        context,
                                        "Применить",
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: AppLocalizations.text(
                              context,
                              "Редактировать",
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: theme.primary.withOpacity(.16),
                              foregroundColor: theme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: theme.primary.withOpacity(.42),
                                ),
                              ),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              themeEditorRoute(theme: theme),
                            ),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          if (isCustom) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: AppLocalizations.text(
                                context,
                                "Удалить тему",
                              ),
                              onPressed: () async {
                                if (!await _confirmThemeDeletion(
                                  context,
                                  theme,
                                ))
                                  return;
                                ref
                                    .read(themeProvider.notifier)
                                    .removeTheme(theme.name);
                              },
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ThemeEditorScreen extends ConsumerStatefulWidget {
  final ThemeConfig? initialTheme;
  const ThemeEditorScreen({super.key, this.initialTheme});

  @override
  ConsumerState<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends ConsumerState<ThemeEditorScreen> {
  static const _fileChannel = MethodChannel('pro.kaleert.nextlink/theme_files');
  late ThemeConfig _draft;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _author;
  final _knownElements = {
    ...Map.fromEntries(
      ThemeRegionRegistry.labels.entries.where(
        (e) => !e.key.startsWith('widget_'),
      ),
    ),
    'home_profiles_button': 'Кнопка профилей',
    'home_subscriptions_button': 'Кнопка подписок',
    'home_app_title': 'Название приложения',
    'home_rules_button': 'Кнопка правил',
    'home_apps_button': 'Кнопка приложений',
    'home_settings_button': 'Кнопка настроек',
    'home_status': 'Статус VPN',
    'home_power_button': 'Кнопка VPN и таймер',
    'home_traffic': 'Плашка трафика',
    'home_server_card': 'Карточка сервера',
    'home_server_globe': 'Глобус серверов',
    'home_system_info': 'IP и память ядра',
    'home_ping': 'Плашка пинга',
  };

  List<String> _completeOrder(List<String> source) {
    final order = source.toList();
    for (final id in _knownElements.keys) {
      if (!order.contains(id)) order.add(id);
    }
    return order;
  }

  @override
  void initState() {
    super.initState();
    final source = widget.initialTheme ?? ThemeConfig.defaultTheme;
    for (final element in source.customElements) {
      _knownElements['custom_${element['id']}'] =
          element['label']?.toString() ?? 'Элемент темы';
    }
    for (final id in source.componentOrder) {
      _knownElements.putIfAbsent(id, () => ThemeRegionRegistry.labelFor(id));
    }
    final savedOrder = _completeOrder(source.componentOrder);
    _draft = source.copyWith(
      name: source.name.startsWith('theme_') ? 'Моя тема' : source.name,
      componentOrder: savedOrder,
    );
    _name = TextEditingController(text: _draft.name);
    _description = TextEditingController(text: _draft.description);
    _author = TextEditingController(text: _draft.author);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _author.dispose();
    super.dispose();
  }

  void _change(ThemeConfig Function(ThemeConfig) update) => setState(() {
    _draft = update(_draft);
    for (final e in _draft.customElements) {
      _knownElements['custom_${e['id']}'] =
          e['label']?.toString() ?? 'Элемент темы';
    }
    _draft = _draft.copyWith(
      componentOrder: _completeOrder(_draft.componentOrder),
    );
  });

  Future<void> _pickColor(
    String title,
    Color current,
    ValueChanged<Color> onPick,
  ) async {
    final value = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeColorPalette(initial: current),
    );
    if (value != null && mounted) onPick(value);
  }

  Future<void> _addElement() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.text(context, "Новый элемент")),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 28,
          decoration: InputDecoration(
            labelText: AppLocalizations.text(context, "Текст плашки"),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.text(context, "Отмена")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.text(context, "Добавить")),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    _change(
      (t) => t.copyWith(
        customElements: [
          ...t.customElements,
          {
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'label': label,
            'color': t.primary.value,
          },
        ],
      ),
    );
  }

  Future<void> _editElement(Map<String, dynamic> element) async {
    final label = TextEditingController(
      text: element['label']?.toString() ?? '',
    );
    final url = TextEditingController(text: element['url']?.toString() ?? '');
    var action = element['action']?.toString() ?? 'none';
    var type = element['type']?.toString() ?? 'button';
    var screen = element['screen']?.toString() ?? 'home';
    var alignment = element['align']?.toString() ?? 'center';
    var gradient = element['gradient'] == true;
    var fontSize = ((element['fontSize'] as num?)?.toDouble() ?? 14)
        .clamp(8, 64)
        .toDouble();
    var height = ((element['height'] as num?)?.toDouble() ?? 16)
        .clamp(0, 240)
        .toDouble();
    var radius = ((element['radius'] as num?)?.toDouble() ?? _draft.cardRadius)
        .clamp(0, 80)
        .toDouble();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, updateDialog) => AlertDialog(
          title: Text(AppLocalizations.text(context, "Плашка и действие")),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.text(context, "Текст"),
                  ),
                ),
                GlassDropdown<String>(
                  value: type,
                  surfaceColor: _draft.surface,
                  accentColor: _draft.primary,
                  items:
                      const {
                            'button': 'Кнопка',
                            'card': 'Карточка',
                            'text': 'Текст',
                            'divider': 'Разделитель',
                            'spacer': 'Отступ',
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                AppLocalizations.text(context, e.value),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => updateDialog(() => type = v ?? 'button'),
                ),
                GlassDropdown<String>(
                  value: screen,
                  surfaceColor: _draft.surface,
                  accentColor: _draft.primary,
                  items: {'home': 'Главная', ...themeScreenRegions}.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            AppLocalizations.text(context, e.value),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => updateDialog(() => screen = v ?? 'home'),
                ),
                GlassDropdown<String>(
                  value: alignment,
                  surfaceColor: _draft.surface,
                  accentColor: _draft.primary,
                  items:
                      const {
                            'left': 'Слева',
                            'center': 'По центру',
                            'right': 'Справа',
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                AppLocalizations.text(context, e.value),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) =>
                      updateDialog(() => alignment = v ?? 'center'),
                ),
                Text(
                  AppLocalizations.text(
                    context,
                    "Размер текста: {0}",
                    args: [fontSize.round()],
                  ),
                ),
                Slider(
                  value: fontSize,
                  min: 8,
                  max: 64,
                  onChanged: (v) => updateDialog(() => fontSize = v),
                ),
                Text(
                  AppLocalizations.text(
                    context,
                    "Скругление: {0}",
                    args: [radius.round()],
                  ),
                ),
                Slider(
                  value: radius,
                  min: 0,
                  max: 80,
                  onChanged: (v) => updateDialog(() => radius = v),
                ),
                if (type == 'spacer' || type == 'divider') ...[
                  Text(
                    AppLocalizations.text(
                      context,
                      "Размер: {0}",
                      args: [height.round()],
                    ),
                  ),
                  Slider(
                    value: height,
                    min: 0,
                    max: 240,
                    onChanged: (v) => updateDialog(() => height = v),
                  ),
                ],
                SwitchListTile(
                  title: Text(AppLocalizations.text(context, "Градиент")),
                  value: gradient,
                  onChanged: (v) => updateDialog(() => gradient = v),
                ),
                GlassDropdown<String>(
                  value: action,
                  surfaceColor: _draft.surface,
                  accentColor: _draft.primary,
                  items:
                      const {
                            'none': 'Текст без действия',
                            'toggle': 'Включить / выключить VPN',
                            'servers': 'Выбор сервера',
                            'settings': 'Настройки',
                            'rules': 'Правила',
                            'url': 'Открыть ссылку',
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                AppLocalizations.text(context, e.value),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => updateDialog(() => action = v ?? 'none'),
                ),
                if (action == 'url')
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(labelText: 'https://…'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.text(context, "Отмена")),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.text(context, "Сохранить")),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && label.text.trim().isNotEmpty && mounted) {
      _change(
        (t) => t.copyWith(
          customElements: t.customElements
              .map(
                (item) => item['id'] == element['id']
                    ? {
                        ...item,
                        'label': label.text.trim(),
                        'action': action,
                        'url': url.text.trim(),
                        'type': type,
                        'screen': screen,
                        'align': alignment,
                        'gradient': gradient,
                        'fontSize': fontSize,
                        'height': height,
                        'radius': radius,
                      }
                    : item,
              )
              .toList(),
        ),
      );
      await _pickColor(
        'Цвет плашки',
        Color((element['color'] as num?)?.toInt() ?? _draft.primary.toARGB32()),
        (color) => _change(
          (t) => t.copyWith(
            customElements: t.customElements
                .map(
                  (item) => item['id'] == element['id']
                      ? {...item, 'color': color.toARGB32()}
                      : item,
                )
                .toList(),
          ),
        ),
      );
    }
    label.dispose();
    url.dispose();
  }

  Future<void> _exportFile() async {
    final theme = _draft.copyWith(
      name: _name.text.trim(),
      author: _author.text.trim(),
      description: _description.text.trim(),
    );
    try {
      await _fileChannel.invokeMethod('saveThemeFile', {
        'name':
            '${theme.name.replaceAll(RegExp(r'[^a-zA-Z0-9А-Яа-я _-]'), '_')}.nlt',
        'contents': const JsonEncoder.withIndent('  ').convert(theme.toMap()),
      });
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.text(
                context,
                "Ошибка экспорта: {0}",
                args: [error],
              ),
            ),
          ),
        );
    }
  }

  void _moveCustomElement(Map<String, dynamic> element, int delta) {
    final elements = _draft.customElements.toList();
    final current = elements.indexWhere((item) => item['id'] == element['id']);
    final target = current + delta;
    if (current < 0 || target < 0 || target >= elements.length) return;
    final moved = elements.removeAt(current);
    elements.insert(target, moved);
    _change((t) => t.copyWith(customElements: elements));
  }

  Future<void> _importFile() async {
    try {
      await ref.read(themeProvider.notifier).ensureLoaded();
      final result = await _fileChannel.invokeMethod<Map>('pickThemeFile');
      if (result == null || result['contents'] == null) return;
      final decoded = jsonDecode(result['contents'].toString());
      final map = decoded is Map && decoded['theme'] is Map
          ? Map<String, dynamic>.from(decoded['theme'])
          : Map<String, dynamic>.from(decoded as Map);
      if (![
        'background',
        'surface',
        'primary',
        'primaryDark',
        'accent',
      ].any(map.containsKey)) {
        throw const FormatException('В JSON нет полей темы NextLink');
      }
      final imported = ThemeConfig.fromMap(map).copyWith(
        componentOrder: _completeOrder(
          (map['componentOrder'] as List? ?? const [])
              .map((value) => value.toString())
              .toList(),
        ),
      );
      setState(() {
        _draft = imported;
        _name.text = imported.name;
        _description.text = imported.description;
        _author.text = imported.author;
      });
    } on PlatformException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.text(
                context,
                "Не удалось открыть файл: {0}",
                args: [error.message ?? error.code],
              ),
            ),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.text(
                context,
                "Неверный файл темы: {0}",
                args: [error],
              ),
            ),
          ),
        );
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final theme = _draft.copyWith(
      name: name,
      description: _description.text.trim(),
      author: _author.text.trim(),
    );
    ref.read(themeProvider.notifier).updateTheme(theme);
    ref.read(themeProvider.notifier).setTheme(theme);
    Navigator.pop(context);
  }

  Widget _colorRow(String label, Color color, ValueChanged<Color> set) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(AppLocalizations.text(context, label)),
        trailing: InkWell(
          onTap: () => _pickColor(label, color, set),
          child: Container(
            width: 42,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white30),
            ),
          ),
        ),
      );

  Widget _positionEditor(String id) {
    final offset = _draft.offsetFor(id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.text(context, "Положение — перетащите элемент"),
          ),
          const SizedBox(height: 8),
          Container(
            height: 112,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: (112 + offset.dx).clamp(0, 190),
                  top: (40 + offset.dy).clamp(0, 76),
                  child: GestureDetector(
                    onPanUpdate: (details) => _change((theme) {
                      final old = theme.offsetFor(id);
                      return theme.copyWith(
                        componentOffsets: {
                          ...theme.componentOffsets,
                          id: Offset(
                            (old.dx + details.delta.dx).clamp(-112, 112),
                            (old.dy + details.delta.dy).clamp(-40, 40),
                          ),
                        },
                      );
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _draft.primary.withOpacity(.28),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _draft.primary.withOpacity(.8),
                        ),
                      ),
                      child: Text(_knownElements[id] ?? id, maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _change((theme) {
                final offsets = {...theme.componentOffsets}..remove(id);
                return theme.copyWith(componentOffsets: offsets);
              }),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(AppLocalizations.text(context, "Сбросить позицию")),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hidden = _draft.hiddenElements.toSet();
    return Theme(
      data: AppTheme.buildTheme(_draft),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: _draft.surface.withValues(alpha: .65),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _draft.blurSigma,
                sigmaY: _draft.blurSigma,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          title: Text(AppLocalizations.text(context, "Редактор тем")),
          actions: [
            PopupMenuButton<String>(
              tooltip: AppLocalizations.text(context, "Открыть тему"),
              icon: const Icon(Icons.palette_outlined),
              onSelected: (name) {
                final state = ref.read(themeProvider);
                final themes = [
                  ThemeConfig.defaultTheme,
                  ThemeConfig.emeraldGreen,
                  ThemeConfig.oceanicBlue,
                  ThemeConfig.neonOrigami,
                  ...state.customThemes,
                ];
                final selected = themes.firstWhere(
                  (item) => item.name == name,
                  orElse: () => _draft,
                );
                setState(() {
                  _draft = selected.copyWith(
                    componentOrder: _completeOrder(selected.componentOrder),
                  );
                  _name.text = selected.name.startsWith('theme_')
                      ? 'Моя тема'
                      : selected.name;
                  _description.text = selected.description;
                  _author.text = selected.author;
                });
              },
              itemBuilder: (context) {
                final state = ref.watch(themeProvider);
                final themes = [
                  ThemeConfig.defaultTheme,
                  ThemeConfig.emeraldGreen,
                  ThemeConfig.oceanicBlue,
                  ThemeConfig.neonOrigami,
                  ...state.customThemes,
                ];
                return themes
                    .map(
                      (theme) => PopupMenuItem(
                        value: theme.name,
                        child: Text(theme.name),
                      ),
                    )
                    .toList();
              },
            ),
            IconButton(
              tooltip: AppLocalizations.text(context, "Импорт .nlt / .json"),
              onPressed: _importFile,
              icon: const Icon(Icons.file_open_rounded),
            ),
            IconButton(
              tooltip: AppLocalizations.text(context, "Экспорт .nlt"),
              onPressed: _exportFile,
              icon: const Icon(Icons.save_alt_rounded),
            ),
            IconButton(
              tooltip: AppLocalizations.text(context, "Сохранить"),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedMeshBackground(
                  isConnected: false,
                  themeOverride: _draft,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: .24)),
              ),
            ),
            ListView(
              padding: EdgeInsets.fromLTRB(
                18,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                18,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.touch_app_rounded),
                  label: Text(
                    AppLocalizations.text(
                      context,
                      "Редактировать прямо на экране",
                    ),
                  ),
                  onPressed: () async {
                    final result = await Navigator.push<ThemeConfig>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemeLiveEditor(theme: _draft),
                      ),
                    );
                    if (mounted && result != null) _change((_) => result);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.text(context, "Название темы"),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  AppLocalizations.text(context, "Предпросмотр"),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _draft.background,
                    gradient: _draft.useGradients
                        ? LinearGradient(
                            colors: [_draft.background, _draft.meshIdle1],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(_draft.cardRadius),
                    border: Border.all(color: _draft.primary.withOpacity(.55)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: _draft.gradientTitle && _draft.useGradients
                              ? [_draft.primary, _draft.primaryDark]
                              : [_draft.text, _draft.text],
                        ).createShader(bounds),
                        child: Text(
                          'NextLink',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _draft.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: _draft.useGradients
                              ? LinearGradient(
                                  colors: [_draft.primary, _draft.primaryDark],
                                )
                              : null,
                          color: _draft.surface,
                          borderRadius: BorderRadius.circular(
                            _draft.cardRadius,
                          ),
                        ),
                        child: Text(
                          AppLocalizations.text(
                            context,
                            "Подключено · Германия",
                          ),
                          style: TextStyle(
                            color: _draft.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _draft.background.withOpacity(.92),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _draft.primary.withOpacity(.72),
                            ),
                          ),
                          child: Text(
                            '00:42',
                            style: TextStyle(
                              color: _draft.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._draft.customElements.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            e['label']?.toString() ?? '',
                            style: TextStyle(
                              color: Color(
                                (e['color'] as num?)?.toInt() ??
                                    _draft.primary.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _section(AppLocalizations.text(context, "Цвета и заливка"), [
                  _colorRow(
                    AppLocalizations.text(context, "Фон"),
                    _draft.background,
                    (c) => _change((t) => t.copyWith(background: c)),
                  ),
                  _colorRow(
                    AppLocalizations.text(context, "Поверхности"),
                    _draft.surface,
                    (c) => _change((t) => t.copyWith(surface: c)),
                  ),
                  _colorRow(
                    AppLocalizations.text(context, "Акцент"),
                    _draft.primary,
                    (c) => _change((t) => t.copyWith(primary: c)),
                  ),
                  _colorRow(
                    AppLocalizations.text(context, "Второй цвет акцента"),
                    _draft.primaryDark,
                    (c) => _change((t) => t.copyWith(primaryDark: c)),
                  ),
                  _colorRow(
                    AppLocalizations.text(context, "Основной текст"),
                    _draft.text,
                    (c) => _change((t) => t.copyWith(text: c)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppLocalizations.text(context, "Градиенты")),
                    value: _draft.useGradients,
                    onChanged: (v) =>
                        _change((t) => t.copyWith(useGradients: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      AppLocalizations.text(
                        context,
                        "Градиент в названии приложения",
                      ),
                    ),
                    value: _draft.gradientTitle,
                    onChanged: (v) =>
                        _change((t) => t.copyWith(gradientTitle: v)),
                  ),
                ]),
                _section(
                  AppLocalizations.text(context, "Описание и авторство"),
                  [
                    TextField(
                      controller: _author,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.text(context, "Автор"),
                      ),
                    ),
                    TextField(
                      controller: _description,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.text(context, "Описание"),
                      ),
                    ),
                  ],
                ),
                _section(AppLocalizations.text(context, "Форма и анимация"), [
                  ListTile(
                    title: Text(
                      AppLocalizations.text(context, "Скругление карточек"),
                    ),
                    subtitle: Slider(
                      value: _draft.cardRadius.clamp(8, 36),
                      min: 8,
                      max: 36,
                      divisions: 14,
                      label: _draft.cardRadius.toStringAsFixed(0),
                      onChanged: (v) =>
                          _change((t) => t.copyWith(cardRadius: v)),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppLocalizations.text(context, "Шрифт")),
                    subtitle: GlassDropdown<String>(
                      value: _draft.fontFamily,
                      surfaceColor: _draft.surface,
                      accentColor: _draft.primary,
                      items:
                          <String, String>{
                                'sans-serif': AppLocalizations.text(
                                  context,
                                  "Системный Sans",
                                ),
                                'serif': 'Noto Serif',
                                'monospace': 'Roboto Mono',
                                'Inter': 'Inter',
                                'Manrope': 'Manrope',
                                'Rubik': 'Rubik',
                                'JetBrains Mono': 'JetBrains Mono',
                                'Nunito': 'Nunito',
                                if (![
                                  'sans-serif',
                                  'serif',
                                  'monospace',
                                  'Inter',
                                  'Manrope',
                                  'Rubik',
                                  'JetBrains Mono',
                                  'Nunito',
                                ].contains(_draft.fontFamily))
                                  _draft.fontFamily: _draft.fontFamily,
                              }.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    AppLocalizations.text(context, e.value),
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null)
                          _change((t) => t.copyWith(fontFamily: v));
                      },
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      AppLocalizations.text(context, "Анимированный фон"),
                    ),
                    value: _draft.animationsEnabled,
                    onChanged: (v) =>
                        _change((t) => t.copyWith(animationsEnabled: v)),
                  ),
                  if (_draft.animationsEnabled)
                    ListTile(
                      title: Text(
                        AppLocalizations.text(context, "Скорость анимации"),
                      ),
                      subtitle: Slider(
                        value: (_draft.animationDurationMs / 1000).clamp(2, 20),
                        min: 2,
                        max: 20,
                        divisions: 18,
                        label: AppLocalizations.text(
                          context,
                          "{0} сек",
                          args: [_draft.animationDurationMs ~/ 1000],
                        ),
                        onChanged: (v) => _change(
                          (t) =>
                              t.copyWith(animationDurationMs: v.round() * 1000),
                        ),
                      ),
                    ),
                ]),
                _section(AppLocalizations.text(context, "Стиль фона"), [
                  GlassDropdown<String>(
                    value: _draft.backgroundStyle,
                    surfaceColor: _draft.surface,
                    accentColor: _draft.primary,
                    items:
                        const {
                              'mesh': 'Плавающие пятна',
                              'linear': 'Движущийся градиент',
                              'radial': 'Радиальное свечение',
                              'off': 'Однотонный фон',
                            }.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  AppLocalizations.text(context, e.value),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null)
                        _change((t) => t.copyWith(backgroundStyle: v));
                    },
                  ),
                  if (_draft.backgroundStyle == 'linear')
                    _range(
                      AppLocalizations.text(context, "Угол градиента"),
                      _draft.gradientAngle,
                      -180,
                      180,
                      (v) => _change((t) => t.copyWith(gradientAngle: v)),
                    ),
                ]),
                _section(
                  AppLocalizations.text(context, "Поверхности и размеры"),
                  [
                    _range(
                      AppLocalizations.text(context, "Прозрачность плашек"),
                      _draft.glassOpacity,
                      .08,
                      1,
                      (v) => _change((t) => t.copyWith(glassOpacity: v)),
                    ),
                    _range(
                      AppLocalizations.text(context, "Размытие"),
                      _draft.blurSigma,
                      0,
                      64,
                      (v) => _change((t) => t.copyWith(blurSigma: v)),
                    ),
                    _range(
                      AppLocalizations.text(context, "Толщина обводки"),
                      _draft.borderWidth,
                      0,
                      3,
                      (v) => _change((t) => t.copyWith(borderWidth: v)),
                    ),
                    _range(
                      AppLocalizations.text(context, "Масштаб текста"),
                      _draft.textScale,
                      .8,
                      1.3,
                      (v) => _change((t) => t.copyWith(textScale: v)),
                    ),
                    _range(
                      AppLocalizations.text(context, "Яркость фоновых пятен"),
                      _draft.backgroundIntensity,
                      0,
                      1,
                      (v) => _change((t) => t.copyWith(backgroundIntensity: v)),
                    ),
                    _range(
                      AppLocalizations.text(context, "Размер кнопки VPN"),
                      _draft.powerButtonSize,
                      140,
                      240,
                      (v) => _change((t) => t.copyWith(powerButtonSize: v)),
                    ),
                    _range(
                      AppLocalizations.text(
                        context,
                        "Длительность нажатия, мс",
                      ),
                      _draft.pressDurationMs.toDouble(),
                      80,
                      500,
                      (v) => _change(
                        (t) => t.copyWith(pressDurationMs: v.round()),
                      ),
                    ),
                  ],
                ),
                _section(
                  AppLocalizations.text(context, "Элементы интерфейса"),
                  [
                    Text(
                      AppLocalizations.text(
                        context,
                        "Порядок меняет кнопки главного экрана. Для других экранов доступны смещение, масштаб, видимость, прозрачность и анимация. Дополнительные элементы появляются после посещения их экрана.",
                      ),
                    ),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: _draft.componentOrder.length,
                      onReorder: (oldIndex, newIndex) {
                        final order = _draft.componentOrder.toList();
                        if (newIndex > oldIndex) newIndex--;
                        final item = order.removeAt(oldIndex);
                        order.insert(newIndex, item);
                        _change((t) => t.copyWith(componentOrder: order));
                      },
                      itemBuilder: (context, index) {
                        final id = _draft.componentOrder[index];
                        final label = _knownElements[id];
                        if (label == null)
                          return SizedBox.shrink(
                            key: ValueKey('missing-$index'),
                          );
                        final animation =
                            _draft.componentAnimations[id] ?? 'soft';
                        return ExpansionTile(
                          key: ValueKey(id),
                          leading:
                              [
                                'home_rules_button',
                                'home_apps_button',
                                'home_settings_button',
                              ].contains(id)
                              ? ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(
                                    Icons.drag_indicator_rounded,
                                  ),
                                )
                              : const Icon(Icons.widgets_outlined),
                          title: Text(AppLocalizations.text(context, label)),
                          children: [
                            if (!id.startsWith('screen_')) _positionEditor(id),
                            if (!id.startsWith('screen_'))
                              _range(
                                AppLocalizations.text(
                                  context,
                                  "Масштаб элемента",
                                ),
                                _draft.scaleFor(id),
                                .65,
                                1.35,
                                (v) => _change(
                                  (t) => t.copyWith(
                                    componentScales: {
                                      ...t.componentScales,
                                      id: v,
                                    },
                                  ),
                                ),
                              ),
                            _range(
                              AppLocalizations.text(
                                context,
                                "Непрозрачность элемента",
                              ),
                              _draft.opacityFor(id),
                              .1,
                              1,
                              (v) => _change(
                                (t) => t.copyWith(
                                  componentOpacities: {
                                    ...t.componentOpacities,
                                    id: v,
                                  },
                                ),
                              ),
                            ),
                            SwitchListTile(
                              title: Text(
                                AppLocalizations.text(
                                  context,
                                  "Показывать элемент",
                                ),
                              ),
                              value: !hidden.contains(id),
                              onChanged: (visible) => _change((t) {
                                final next = t.hiddenElements.toSet();
                                visible ? next.remove(id) : next.add(id);
                                return t.copyWith(
                                  hiddenElements: next.toList(),
                                );
                              }),
                            ),
                            _colorRow(
                              AppLocalizations.text(context, "Цвет элемента"),
                              _draft.colorFor(id),
                              (color) => _change(
                                (t) => t.copyWith(
                                  componentColors: {
                                    ...t.componentColors,
                                    id: color.value,
                                  },
                                ),
                              ),
                            ),
                            ListTile(
                              title: Text(
                                AppLocalizations.text(context, "Скругление"),
                              ),
                              subtitle: Slider(
                                value: _draft.radiusFor(id),
                                min: 6,
                                max: 42,
                                divisions: 18,
                                onChanged: (radius) => _change(
                                  (t) => t.copyWith(
                                    componentRadii: {
                                      ...t.componentRadii,
                                      id: radius,
                                    },
                                  ),
                                ),
                              ),
                            ),
                            if ([
                                  'home_power_button',
                                  'home_traffic',
                                  'home_ping',
                                  'home_server_card',
                                  'home_settings_button',
                                  'home_apps_button',
                                  'home_rules_button',
                                ].contains(id) ||
                                !id.startsWith('home_'))
                              ListTile(
                                title: Text(
                                  AppLocalizations.text(
                                    context,
                                    "Анимация нажатия",
                                  ),
                                ),
                                trailing: DropdownButton<String>(
                                  value:
                                      [
                                        'none',
                                        'soft',
                                        'bounce',
                                        'shrink',
                                        'grow',
                                      ].contains(animation)
                                      ? animation
                                      : 'soft',
                                  items: [
                                    DropdownMenuItem(
                                      value: 'shrink',
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Сжатие",
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'grow',
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Увеличение",
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'none',
                                      child: Text(
                                        AppLocalizations.text(context, "Нет"),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'soft',
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Мягкая",
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'bounce',
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Пружина",
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null)
                                      _change(
                                        (t) => t.copyWith(
                                          componentAnimations: {
                                            ...t.componentAnimations,
                                            id: value,
                                          },
                                        ),
                                      );
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    ..._draft.customElements.map(
                      (e) => ListTile(
                        title: Text(e['label']?.toString() ?? ''),
                        subtitle: Text(
                          e['action'] == null || e['action'] == 'none'
                              ? AppLocalizations.text(
                                  context,
                                  "Плашка на главном экране",
                                )
                              : AppLocalizations.text(
                                  context,
                                  "Действие: {0}",
                                  args: [e['action']],
                                ),
                        ),
                        onTap: () => _editElement(e),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: AppLocalizations.text(context, "Вверх"),
                              icon: const Icon(Icons.keyboard_arrow_up_rounded),
                              onPressed: () => _moveCustomElement(e, -1),
                            ),
                            IconButton(
                              tooltip: AppLocalizations.text(context, "Вниз"),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                              onPressed: () => _moveCustomElement(e, 1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editElement(e),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _change(
                                (t) => t.copyWith(
                                  customElements: t.customElements
                                      .where((item) => item['id'] != e['id'])
                                      .toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addElement,
                      icon: const Icon(Icons.add),
                      label: Text(
                        AppLocalizations.text(
                          context,
                          "Добавить текстовую плашку",
                        ),
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: _importFile,
                  icon: const Icon(Icons.file_open),
                  label: Text(
                    AppLocalizations.text(
                      context,
                      "Импортировать .nlt или .json",
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _save,
                  child: Text(
                    AppLocalizations.text(context, "Сохранить и применить"),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _range(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text('$label · ${value.toStringAsFixed(value < 4 ? 2 : 0)}'),
    subtitle: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      onChanged: onChanged,
    ),
  );

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.text(context, title),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}
