import '../shared/widgets/theme_region.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../shared/widgets/glass_dropdown.dart';
import '../shared/widgets/app_route_selector.dart';
import '../shared/widgets/app_progress_bar.dart';
import '../core/theme/theme_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/localization/app_localizations.dart';

class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> {
  static const _channel = MethodChannel('pro.kaleert.nextlink/apps');
  List<Map<String, dynamic>> _installedApps = [];
  bool _isLoading = false;
  bool _supportsUidBlocking = false;
  String? _loadError;
  int _nextOffset = 0;
  int? _totalApps;
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name', 'package', 'action'

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      while (mounted) {
        final page = await _channel.invokeMapMethod<String, dynamic>(
          'getInstalledAppsPage',
          {'offset': _nextOffset, 'limit': 24},
        );
        if (!mounted) return;
        if (page == null) throw const FormatException('Empty app page');
        final apps = (page['apps'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final next = (page['nextOffset'] as num).toInt();
        final hasMore = page['hasMore'] == true;
        if (hasMore && next <= _nextOffset)
          throw const FormatException('Invalid app page offset');
        setState(() {
          final byPackage = {
            for (final app in _installedApps) app['package']: app,
          };
          for (final app in apps) {
            byPackage[app['package']] = app;
          }
          _installedApps = byPackage.values.toList();
          _nextOffset = next;
          _supportsUidBlocking = page['supportsUidBlocking'] == true;
          _totalApps = (page['total'] as num).toInt();
          _isLoading = hasMore;
        });
        if (!hasMore) return;
        // Paint the received batch before requesting more icons over the channel.
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить приложения';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = ref.watch(themeProvider).currentTheme;
    final notifier = ref.read(settingsProvider.notifier);
    final loc = AppLocalizations.of(context)!;

    // Функция получения текущего правила приложения
    String getAppRule(String pkg) {
      return settings.perAppRules[pkg] ?? settings.perAppDefaultRule;
    }

    // Фильтрация
    var filteredApps = _installedApps.where((app) {
      final name = app['name']?.toString().toLowerCase() ?? '';
      final pkg = app['package']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase()) ||
          pkg.contains(_searchQuery.toLowerCase());
    }).toList();

    // Сортировка
    filteredApps.sort((a, b) {
      if (_sortBy == 'name') {
        return a['name'].toString().toLowerCase().compareTo(
          b['name'].toString().toLowerCase(),
        );
      } else if (_sortBy == 'package') {
        return a['package'].toString().toLowerCase().compareTo(
          b['package'].toString().toLowerCase(),
        );
      } else {
        // Сортировка по действию (Proxy -> Direct)
        final ruleA = getAppRule(a['package']);
        final ruleB = getAppRule(b['package']);
        final order = {'proxy': 0, 'direct': 1, 'block': 2};
        final res = (order[ruleA] ?? 1).compareTo(order[ruleB] ?? 1);
        if (res != 0) return res;
        return a['name'].toString().toLowerCase().compareTo(
          b['name'].toString().toLowerCase(),
        );
      }
    });

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_apps',
        child: ThemeRegion.auto(
          id: "widget_apps_screen_0",
          label: "Stack · apps_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: -50,
                right: 100,
                child: ThemeRegion.auto(
                  id: "widget_apps_screen_1",
                  label: "Container · apps_screen.dart",
                  child: Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.meshIdle1,
                    ),
                  ),
                ),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: ThemeRegion.auto(
                  id: "widget_apps_screen_2",
                  label: "Container · apps_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),

              SafeArea(
                child: ThemeRegion.auto(
                  id: "widget_apps_screen_3",
                  label: "Column · apps_screen.dart",
                  child: Column(
                    children: [
                      // === HEADER ===
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        child: ThemeRegion.auto(
                          id: "widget_apps_screen_4",
                          label: "Row · apps_screen.dart",
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(context);
                                },
                                child: ThemeRegion.auto(
                                  id: "widget_apps_screen_5",
                                  label: "Container · apps_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.surface.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_apps_screen_6",
                                      label: "Icon · apps_screen.dart",
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: theme.text,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ThemeRegion.auto(
                                id: "widget_apps_screen_7",
                                label: "Text · apps_screen.dart",
                                child: Text(
                                  loc.translate('apps'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 44),
                            ],
                          ),
                        ),
                      ).animate().fade().slideY(begin: -0.2),

                      // === УПРАВЛЕНИЕ ===
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 8.0,
                        ),
                        child: ThemeRegion.auto(
                          id: "widget_apps_screen_8",
                          label: "Column · apps_screen.dart",
                          child: Column(
                            children: [
                              // Главный переключатель и Базовое правило
                              ThemeRegion.auto(
                                id: "widget_apps_screen_9",
                                label: "Container · apps_screen.dart",
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: theme.surface.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: ThemeRegion.auto(
                                    id: "widget_apps_screen_10",
                                    label: "Column · apps_screen.dart",
                                    child: Column(
                                      children: [
                                        ThemeRegion.auto(
                                          id: "widget_apps_screen_11",
                                          label: "Row · apps_screen.dart",
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: ThemeRegion.auto(
                                                  id: "widget_apps_screen_12",
                                                  label:
                                                      "Text · apps_screen.dart",
                                                  child: Text(
                                                    loc.translate(
                                                      'per_app_proxy',
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              ThemeRegion.auto(
                                                id: "widget_apps_screen_13",
                                                label:
                                                    "Switch · apps_screen.dart",
                                                child: Switch(
                                                  value: settings.perAppEnabled,
                                                  activeColor: theme.primary,
                                                  onChanged:
                                                      notifier.togglePerApp,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (settings.perAppEnabled) ...[
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: 8.0,
                                            ),
                                            child: Divider(
                                              color: Colors.white10,
                                              height: 1,
                                            ),
                                          ),
                                          ThemeRegion.auto(
                                            id: "widget_apps_screen_14",
                                            label: "Row · apps_screen.dart",
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: ThemeRegion.auto(
                                                    id: "widget_apps_screen_15",
                                                    label: "Column · apps_screen.dart",
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        ThemeRegion.auto(
                                                          id: "widget_apps_screen_16",
                                                          label: "Text · apps_screen.dart",
                                                          child: Text(
                                                            AppLocalizations.text(
                                                              context,
                                                              "Режим по умолчанию",
                                                            ),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  theme.textDim,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        ThemeRegion.auto(
                                                          id: "widget_apps_screen_17",
                                                          label: "Text · apps_screen.dart",
                                                          child: Text(
                                                            settings.perAppDefaultRule ==
                                                                    'proxy'
                                                                ? AppLocalizations.text(
                                                                    context,
                                                                    "Всё через Proxy",
                                                                  )
                                                                : settings.perAppDefaultRule ==
                                                                      'block'
                                                                ? AppLocalizations.text(
                                                                    context,
                                                                    "Всё заблокировано",
                                                                  )
                                                                : AppLocalizations.text(
                                                                    context,
                                                                    "Всё через Direct",
                                                                  ),
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                PopupMenuButton<String>(
                                                  tooltip:
                                                      AppLocalizations.text(
                                                        context,
                                                        "Режим по умолчанию",
                                                      ),
                                                  initialValue: settings
                                                      .perAppDefaultRule,
                                                  onSelected: notifier
                                                      .setPerAppDefaultRule,
                                                  itemBuilder: (_) => [
                                                    PopupMenuItem(
                                                      value: 'proxy',
                                                      child: Text(
                                                        AppLocalizations.text(
                                                          context,
                                                          "По умолчанию: Proxy",
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'direct',
                                                      child: Text(
                                                        AppLocalizations.text(
                                                          context,
                                                          "По умолчанию: Direct",
                                                        ),
                                                      ),
                                                    ),
                                                    if (_supportsUidBlocking)
                                                      PopupMenuItem(
                                                        value: 'block',
                                                        child: Text(
                                                          AppLocalizations.text(
                                                            context,
                                                            "По умолчанию: Block",
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                // Кнопка Инверсии
                                                GestureDetector(
                                                  onTap: () {
                                                    HapticFeedback.mediumImpact();
                                                    notifier
                                                        .invertPerAppRules();
                                                  },
                                                  child: ThemeRegion.auto(
                                                    id: "widget_apps_screen_18",
                                                    label: "Container · apps_screen.dart",
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: theme.primary
                                                            .withOpacity(0.2),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        border: Border.all(
                                                          color: theme.primary
                                                              .withOpacity(0.5),
                                                        ),
                                                      ),
                                                      child: ThemeRegion.auto(
                                                        id: "widget_apps_screen_19",
                                                        label: "Row · apps_screen.dart",
                                                        child: Row(
                                                          children: [
                                                            ThemeRegion.auto(
                                                              id: "widget_apps_screen_20",
                                                              label: "Icon · apps_screen.dart",
                                                              child: Icon(
                                                                Icons
                                                                    .swap_horiz_rounded,
                                                                size: 16,
                                                                color: theme
                                                                    .primary,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            ThemeRegion.auto(
                                                              id: "widget_apps_screen_21",
                                                              label: "Text · apps_screen.dart",
                                                              child: Text(
                                                                AppLocalizations.text(
                                                                  context,
                                                                  "Инверт.",
                                                                ),
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: theme
                                                                      .primary,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Поиск и Сортировка
                              ThemeRegion.auto(
                                id: "widget_apps_screen_22",
                                label: "Row · apps_screen.dart",
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ThemeRegion.auto(
                                        id: "widget_apps_screen_23",
                                        label: "Container · apps_screen.dart",
                                        child: Container(
                                          height: 48,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black38,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: Colors.white10,
                                            ),
                                          ),
                                          child: ThemeRegion.auto(
                                            id: "widget_apps_screen_24",
                                            label:
                                                "TextField · apps_screen.dart",
                                            child: TextField(
                                              onChanged: (v) => setState(
                                                () => _searchQuery = v,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                              decoration: InputDecoration(
                                                icon: ThemeRegion.auto(
                                                  id: "widget_apps_screen_25",
                                                  label:
                                                      "Icon · apps_screen.dart",
                                                  child: Icon(
                                                    Icons.search_rounded,
                                                    color: theme.textDim,
                                                    size: 20,
                                                  ),
                                                ),
                                                hintText: loc.translate(
                                                  'search_apps',
                                                ),
                                                hintStyle: const TextStyle(
                                                  color: Colors.white24,
                                                  fontSize: 14,
                                                ),
                                                filled: false,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                border: InputBorder.none,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ThemeRegion.auto(
                                      id: "widget_apps_screen_26",
                                      label: "Container · apps_screen.dart",
                                      child: Container(
                                        height: 48,
                                        clipBehavior: Clip.antiAlias,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black38,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white10,
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: GlassDropdown<String>(
                                            value: _sortBy,
                                            surfaceColor: theme.surface,
                                            accentColor: theme.primary,
                                            textColor: Colors.white,
                                            icon: ThemeRegion.auto(
                                              id: "widget_apps_screen_27",
                                              label: "Icon · apps_screen.dart",
                                              child: Icon(
                                                Icons.sort_rounded,
                                                color: theme.textDim,
                                                size: 18,
                                              ),
                                            ),
                                            items: [
                                              DropdownMenuItem(
                                                value: 'name',
                                                child: ThemeRegion.auto(
                                                  id: "widget_apps_screen_28",
                                                  label:
                                                      "Text · apps_screen.dart",
                                                  child: Text(
                                                    AppLocalizations.text(
                                                      context,
                                                      "Имя",
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: 'package',
                                                child: ThemeRegion.auto(
                                                  id: "widget_apps_screen_29",
                                                  label:
                                                      "Text · apps_screen.dart",
                                                  child: Text(
                                                    AppLocalizations.text(
                                                      context,
                                                      "Пакет",
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: 'action',
                                                child: ThemeRegion.auto(
                                                  id: "widget_apps_screen_30",
                                                  label:
                                                      "Text · apps_screen.dart",
                                                  child: Text(
                                                    AppLocalizations.text(
                                                      context,
                                                      "Действие",
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                            onChanged: (v) {
                                              if (v != null)
                                                setState(() => _sortBy = v);
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fade(delay: 100.ms),

                      if (_isLoading)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 4,
                          ),
                          child: AppProgressBar(
                            value: _totalApps == null || _totalApps == 0
                                ? null
                                : _nextOffset / _totalApps!,
                            label: _totalApps == null
                                ? AppLocalizations.text(
                                    context,
                                    "Загрузка приложений…",
                                  )
                                : AppLocalizations.text(
                                    context,
                                    "Загружено {0} из {1}",
                                    args: [_nextOffset, _totalApps],
                                  ),
                          ),
                        ),
                      if (_loadError != null)
                        ThemeRegion.auto(
                          id: "widget_apps_screen_31",
                          label: "Row · apps_screen.dart",
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: ThemeRegion.auto(
                                  id: "widget_apps_screen_32",
                                  label: "Text · apps_screen.dart",
                                  child: Text(
                                    _loadError!,
                                    style: TextStyle(color: theme.textDim),
                                  ),
                                ),
                              ),
                              ThemeRegion.auto(
                                id: "widget_apps_screen_33",
                                label: "TextButton · apps_screen.dart",
                                child: TextButton(
                                  onPressed: _loadApps,
                                  child: ThemeRegion.auto(
                                    id: "widget_apps_screen_34",
                                    label: "Text · apps_screen.dart",
                                    child: Text(
                                      AppLocalizations.text(
                                        context,
                                        "Повторить",
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          physics: const BouncingScrollPhysics(),
                          itemCount: filteredApps.length,
                          itemBuilder: (context, index) {
                            final app = filteredApps[index];
                            final pkg = app['package'] as String;
                            final isService = app['isVpnServiceApp'] == true;
                            final rule = isService ? 'direct' : getAppRule(pkg);

                            // Определяем цвет карточки на основе правила
                            Color cardColor = theme.surface.withOpacity(0.4);
                            Color borderColor = Colors.white.withOpacity(0.05);
                            if (settings.perAppRules.containsKey(pkg)) {
                              if (rule == 'proxy') {
                                cardColor = theme.primary.withOpacity(0.05);
                                borderColor = theme.primary.withOpacity(0.3);
                              } else if (rule == 'block') {
                                cardColor = Colors.redAccent.withOpacity(0.05);
                                borderColor = Colors.redAccent.withOpacity(0.3);
                              } else if (rule == 'direct') {
                                cardColor = Colors.orangeAccent.withOpacity(
                                  0.05,
                                );
                                borderColor = Colors.orangeAccent.withOpacity(
                                  0.3,
                                );
                              }
                            }

                            return ThemeRegion.auto(
                                  id: "widget_apps_screen_35",
                                  label: "Container · apps_screen.dart",
                                  child: Container(
                                    key: ValueKey(pkg),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_apps_screen_36",
                                      label: "Column · apps_screen.dart",
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ThemeRegion.auto(
                                            id: "widget_apps_screen_37",
                                            label: "Row · apps_screen.dart",
                                            child: Row(
                                              children: [
                                                // ИКОНКА ПРИЛОЖЕНИЯ
                                                ThemeRegion.auto(
                                                  id: "widget_apps_screen_38",
                                                  label: "Container · apps_screen.dart",
                                                  child: Container(
                                                    width: 40,
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      color: Colors.black26,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    child:
                                                        (app['icon']
                                                                    as Uint8List? ??
                                                                Uint8List(0))
                                                            .isNotEmpty
                                                        ? ClipRRect(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                            child: Image.memory(
                                                              app['icon'],
                                                              fit: BoxFit.cover,
                                                            ),
                                                          )
                                                        : ThemeRegion.auto(
                                                            id: "widget_apps_screen_39",
                                                            label: "Icon · apps_screen.dart",
                                                            child: const Icon(
                                                              Icons
                                                                  .android_rounded,
                                                              color: Colors
                                                                  .white54,
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: ThemeRegion.auto(
                                                    id: "widget_apps_screen_40",
                                                    label: "Column · apps_screen.dart",
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        ThemeRegion.auto(
                                                          id: "widget_apps_screen_41",
                                                          label: "Text · apps_screen.dart",
                                                          child: Text(
                                                            app['name']!,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        ThemeRegion.auto(
                                                          id: "widget_apps_screen_42",
                                                          label: "Text · apps_screen.dart",
                                                          child: Text(
                                                            pkg,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color:
                                                                  theme.textDim,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          ThemeRegion(
                                            id: ThemeRegionRegistry.named(
                                              'app_route',
                                              'Правило: ${app['name']}',
                                              stableKey: pkg,
                                            ),
                                            child: AppRouteSelector(
                                              value: rule,
                                              supportsBlock:
                                                  _supportsUidBlocking,
                                              enabled: !isService,
                                              proxyColor: theme.primary,
                                              onChanged: (mode) {
                                                HapticFeedback.selectionClick();
                                                notifier.setPerAppRule(
                                                  pkg,
                                                  mode,
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                                .animate()
                                .fade(
                                  delay: (index < 10
                                      ? (100 + index * 20).ms
                                      : 0.ms),
                                )
                                .slideX(begin: 0.05);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
