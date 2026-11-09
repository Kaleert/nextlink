import '../shared/widgets/theme_region.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/theme_provider.dart';
import '../core/localization/app_localizations.dart';
import '../core/providers/stats_provider.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen>
    with WidgetsBindingObserver {
  StatsPeriod _selectedPeriod = StatsPeriod.today;
  StatsNetworkType _selectedNetType = StatsNetworkType.all;
  final Map<String, String> _appNames = {};
  final Map<String, Uint8List> _appIcons = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppDetails();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadAppDetails() async {
    try {
      final apps = await const MethodChannel('pro.kaleert.nextlink/apps')
          .invokeListMethod<dynamic>('getInstalledApps');
      if (!mounted || apps == null) return;
      setState(() {
        for (final item in apps) {
          if (item is! Map) continue;
          final package = item['package']?.toString();
          if (package == null) continue;
          _appNames[package] = item['name']?.toString() ?? package;
          final icon = item['icon'];
          if (icon is Uint8List && icon.isNotEmpty) _appIcons[package] = icon;
        }
      });
    } catch (_) {}
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
      value /= 1024;
      idx++;
    }
    final digits = value >= 100 || idx == 0 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(digits)} ${units[idx]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final statsState = ref.watch(statsProvider);
    final statsNotifier = ref.read(statsProvider.notifier);

    final traffic = statsNotifier.getTrafficForPeriod(
      _selectedPeriod,
      _selectedNetType,
      snapshot: statsState,
    );
    final totalBytes = traffic.total;

    final appTraffic = statsNotifier.getAppTrafficForPeriod(
      _selectedPeriod,
      _selectedNetType,
      snapshot: statsState,
    );
    final appEntries = appTraffic.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_statistics',
        child: ThemeRegion.auto(
          id: "widget_statistics_screen_0",
          label: "Stack · statistics_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: 100,
                right: -100,
                child: ThemeRegion.auto(
                  id: "widget_statistics_screen_1",
                  label: "Container · statistics_screen.dart",
                  child: Container(
                    width: 300,
                    height: 300,
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
                  id: "widget_statistics_screen_2",
                  label: "Container · statistics_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),

              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ThemeRegion.auto(
                      id: "widget_statistics_screen_3",
                      label: "Column · statistics_screen.dart",
                      child: Column(
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                            child: ThemeRegion.auto(
                              id: "widget_statistics_screen_4",
                              label: "Row · statistics_screen.dart",
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.pop(context);
                                    },
                                    child: ThemeRegion.auto(
                                      id: "widget_statistics_screen_5",
                                      label:
                                          "Container · statistics_screen.dart",
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.surface.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white10,
                                          ),
                                        ),
                                        child: ThemeRegion.auto(
                                          id: "widget_statistics_screen_6",
                                          label:
                                              "Icon · statistics_screen.dart",
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
                                    id: "widget_statistics_screen_7",
                                    label: "Text · statistics_screen.dart",
                                    child: Text(
                                      loc.translate('statistics'),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.mediumImpact();
                                      statsNotifier.clear();
                                    },
                                    child: ThemeRegion.auto(
                                      id: "widget_statistics_screen_8",
                                      label:
                                          "Container · statistics_screen.dart",
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.surface.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white10,
                                          ),
                                        ),
                                        child: ThemeRegion.auto(
                                          id: "widget_statistics_screen_9",
                                          label:
                                              "Icon · statistics_screen.dart",
                                          child: Icon(
                                            Icons.delete_outline_rounded,
                                            color: theme.textDim,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ).animate().fade().slideY(begin: -0.2),

                          // Переключатели периода и сети
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 8.0,
                            ),
                            child: ThemeRegion.auto(
                              id: "widget_statistics_screen_10",
                              label: "Column · statistics_screen.dart",
                              child: Column(
                                children: [
                                  // Фильтр по типу сети
                                  ThemeRegion.auto(
                                    id: "widget_statistics_screen_11",
                                    label: "Row · statistics_screen.dart",
                                    child: Row(
                                      children: [
                                        _buildNetTypeChip(
                                          'Все сети',
                                          StatsNetworkType.all,
                                          theme,
                                        ),
                                        const SizedBox(width: 8),
                                        _buildNetTypeChip(
                                          'Wi-Fi',
                                          StatsNetworkType.wifi,
                                          theme,
                                        ),
                                        const SizedBox(width: 8),
                                        _buildNetTypeChip(
                                          'Мобильная',
                                          StatsNetworkType.mobile,
                                          theme,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Фильтр по периоду
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: ThemeRegion.auto(
                                      id: "widget_statistics_screen_12",
                                      label: "Row · statistics_screen.dart",
                                      child: Row(
                                        children: [
                                          _buildPeriodChip(
                                            'Сегодня',
                                            StatsPeriod.today,
                                            theme,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildPeriodChip(
                                            'За неделю',
                                            StatsPeriod.week,
                                            theme,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildPeriodChip(
                                            'За месяц',
                                            StatsPeriod.month,
                                            theme,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildPeriodChip(
                                            'Всё время',
                                            StatsPeriod.allTime,
                                            theme,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ).animate().fade(delay: 100.ms),

                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 10,
                              ),
                              physics: const BouncingScrollPhysics(),
                              children: [
                                // Главная карточка
                                ThemeRegion.auto(
                                  id: "widget_statistics_screen_13",
                                  label: "Container · statistics_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(32),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          theme.primary.withOpacity(0.2),
                                          const Color(0xFF140505),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(32),
                                      border: Border.all(
                                        color: theme.primary.withOpacity(0.3),
                                      ),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_statistics_screen_14",
                                      label: "Column · statistics_screen.dart",
                                      child: Column(
                                        children: [
                                          ThemeRegion.auto(
                                            id: "widget_statistics_screen_15",
                                            label:
                                                "Text · statistics_screen.dart",
                                            child: Text(
                                              AppLocalizations.text(
                                                context,
                                                "ТРАФИК ЗА ПЕРИОД",
                                              ),
                                              style: TextStyle(
                                                color: theme.textDim,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          ThemeRegion.auto(
                                            id: "widget_statistics_screen_16",
                                            label:
                                                "Text · statistics_screen.dart",
                                            child: Text(
                                              _formatBytes(totalBytes),
                                              style: const TextStyle(
                                                fontSize: 44,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 32),
                                          ThemeRegion.auto(
                                            id: "widget_statistics_screen_17",
                                            label:
                                                "Row · statistics_screen.dart",
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                ThemeRegion.auto(
                                                  id: "widget_statistics_screen_18",
                                                  label: "Column · statistics_screen.dart",
                                                  child: Column(
                                                    children: [
                                                      ThemeRegion.auto(
                                                        id: "widget_statistics_screen_19",
                                                        label: "Container · statistics_screen.dart",
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                8,
                                                              ),
                                                          decoration:
                                                              BoxDecoration(
                                                                color: Colors
                                                                    .greenAccent
                                                                    .withOpacity(
                                                                      0.2,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                          child: ThemeRegion.auto(
                                                            id: "widget_statistics_screen_20",
                                                            label: "Icon · statistics_screen.dart",
                                                            child: const Icon(
                                                              Icons
                                                                  .arrow_downward_rounded,
                                                              color: Colors
                                                                  .greenAccent,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      ThemeRegion.auto(
                                                        id: "widget_statistics_screen_21",
                                                        label: "Text · statistics_screen.dart",
                                                        child: Text(
                                                          loc.translate(
                                                            'downloaded',
                                                          ),
                                                          style: TextStyle(
                                                            color:
                                                                theme.textDim,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                      ThemeRegion.auto(
                                                        id: "widget_statistics_screen_22",
                                                        label: "Text · statistics_screen.dart",
                                                        child: Text(
                                                          _formatBytes(
                                                            traffic.totalRx,
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                ThemeRegion.auto(
                                                  id: "widget_statistics_screen_23",
                                                  label: "Container · statistics_screen.dart",
                                                  child: Container(
                                                    width: 1,
                                                    height: 40,
                                                    color: Colors.white10,
                                                  ),
                                                ),
                                                ThemeRegion.auto(
                                                  id: "widget_statistics_screen_24",
                                                  label: "Column · statistics_screen.dart",
                                                  child: Column(
                                                    children: [
                                                      ThemeRegion.auto(
                                                        id: "widget_statistics_screen_25",
                                                        label: "Container · statistics_screen.dart",
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                8,
                                                              ),
                                                          decoration:
                                                              BoxDecoration(
                                                                color: theme
                                                                    .primary
                                                                    .withOpacity(
                                                                      0.2,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                          child: ThemeRegion.auto(
                                                            id: "widget_statistics_screen_26",
                                                            label: "Icon · statistics_screen.dart",
                                                            child: Icon(
                                                              Icons
                                                                  .arrow_upward_rounded,
                                                              color:
                                                                  theme.primary,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      ThemeRegion.auto(
                                                        id: "widget_statistics_screen_27",
                                                        label: "Text · statistics_screen.dart",
                                                        child: Text(
                                                          loc.translate(
                                                            'uploaded',
                                                          ),
                                                          style: TextStyle(
                                                            color:
                                                                theme.textDim,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                      ThemeRegion.auto(
                                                        id: "widget_statistics_screen_28",
                                                        label: "Text · statistics_screen.dart",
                                                        child: Text(
                                                          _formatBytes(
                                                            traffic.totalTx,
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ).animate().fade(delay: 150.ms).slideY(begin: 0.1),

                                const SizedBox(height: 30),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 8,
                                    bottom: 16,
                                  ),
                                  child: ThemeRegion.auto(
                                    id: "widget_statistics_screen_29",
                                    label: "Column · statistics_screen.dart",
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ThemeRegion.auto(
                                          id: "widget_statistics_screen_30",
                                          label:
                                              "Text · statistics_screen.dart",
                                          child: Text(
                                            loc.translate('by_apps'),
                                            style: TextStyle(
                                              color: theme.textDim,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ).animate().fade(delay: 200.ms),

                                if (appEntries.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 40,
                                    ),
                                    child: Center(
                                      child: ThemeRegion.auto(
                                        id: "widget_statistics_screen_32",
                                        label:
                                            "Column · statistics_screen.dart",
                                        child: Column(
                                          children: [
                                            ThemeRegion.auto(
                                              id: "widget_statistics_screen_33",
                                              label: "Text · statistics_screen.dart",
                                              child: Text(
                                                AppLocalizations.text(
                                                  context,
                                                  "Статистика появится после передачи данных через VPN",
                                                ),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: theme.textDim,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ...appEntries.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final pkg = entry.value.key;
                                    final appBytes = entry.value.value;
                                    final appName = pkg == 'nextlink.unknown'
                                        ? 'Неопределённое приложение / система'
                                        : (_appNames[pkg] ?? pkg);
                                    final appIcon = _appIcons[pkg];
                                    final percent = totalBytes > 0
                                        ? (appBytes / totalBytes).clamp(
                                            0.0,
                                            1.0,
                                          )
                                        : 0.0;

                                    return ThemeRegion.auto(
                                      id: "widget_statistics_screen_34",
                                      label:
                                          "Container · statistics_screen.dart",
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: theme.surface.withOpacity(0.4),
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.05,
                                            ),
                                          ),
                                        ),
                                        child: ThemeRegion.auto(
                                          id: "widget_statistics_screen_35",
                                          label: "Row · statistics_screen.dart",
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: appIcon == null
                                                    ? ThemeRegion.auto(
                                                        id: "widget_statistics_screen_36",
                                                        label: "Container · statistics_screen.dart",
                                                        child: Container(
                                                          width: 42,
                                                          height: 42,
                                                          color: theme.primary
                                                              .withOpacity(
                                                                0.15,
                                                              ),
                                                          child: ThemeRegion.auto(
                                                            id: "widget_statistics_screen_37",
                                                            label: "Icon · statistics_screen.dart",
                                                            child: Icon(
                                                              Icons
                                                                  .apps_rounded,
                                                              color:
                                                                  theme.primary,
                                                              size: 20,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    : Image.memory(
                                                        appIcon,
                                                        width: 42,
                                                        height: 42,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, _, _) =>
                                                            ThemeRegion.auto(
                                                              id: "widget_statistics_screen_38",
                                                              label: "Icon · statistics_screen.dart",
                                                              child: Icon(
                                                                Icons
                                                                    .apps_rounded,
                                                                color: theme
                                                                    .primary,
                                                              ),
                                                            ),
                                                      ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: ThemeRegion.auto(
                                                  id: "widget_statistics_screen_39",
                                                  label: "Column · statistics_screen.dart",
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      ThemeRegion.auto(
                                                        id: "widget_statistics_screen_40",
                                                        label: "Row · statistics_screen.dart",
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Expanded(
                                                              child: ThemeRegion.auto(
                                                                id: "widget_statistics_screen_41",
                                                                label: "Column · statistics_screen.dart",
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    ThemeRegion.auto(
                                                                      id: "widget_statistics_screen_42",
                                                                      label: "Text · statistics_screen.dart",
                                                                      child: Text(
                                                                        appName,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: const TextStyle(
                                                                          fontSize:
                                                                              14,
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                          color:
                                                                              Colors.white,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    ThemeRegion.auto(
                                                                      id: "widget_statistics_screen_43",
                                                                      label: "Text · statistics_screen.dart",
                                                                      child: Text(
                                                                        pkg,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              10,
                                                                          color:
                                                                              theme.textDim,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                            ThemeRegion.auto(
                                                              id: "widget_statistics_screen_44",
                                                              label: "Text · statistics_screen.dart",
                                                              child: Text(
                                                                _formatBytes(
                                                                  appBytes,
                                                                ),
                                                                style: const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                        child: LinearProgressIndicator(
                                                          value: percent,
                                                          minHeight: 5,
                                                          backgroundColor:
                                                              Colors.black45,
                                                          valueColor:
                                                              AlwaysStoppedAnimation<
                                                                Color
                                                              >(theme.primary),
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
                                    ).animate().fade(delay: (200 + index * 30).ms).slideX(begin: 0.05);
                                  }),
                              ],
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
      ),
    );
  }

  Widget _buildPeriodChip(String label, StatsPeriod period, dynamic theme) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedPeriod = period);
      },
      child: ThemeRegion.auto(
        id: "widget_statistics_screen_45",
        label: "Container · statistics_screen.dart",
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.primary.withOpacity(0.2) : Colors.black38,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? theme.primary.withOpacity(0.5)
                  : Colors.white10,
            ),
          ),
          child: ThemeRegion.auto(
            id: "widget_statistics_screen_46",
            label: "Text · statistics_screen.dart",
            child: Text(
              AppLocalizations.text(context, label),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? theme.primary : Colors.white60,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetTypeChip(String label, StatsNetworkType type, dynamic theme) {
    final isSelected = _selectedNetType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedNetType = type);
        },
        child: ThemeRegion.auto(
          id: "widget_statistics_screen_47",
          label: "Container · statistics_screen.dart",
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.primary.withOpacity(0.2)
                  : Colors.black38,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? theme.primary.withOpacity(0.5)
                    : Colors.white10,
              ),
            ),
            child: Center(
              child: ThemeRegion.auto(
                id: "widget_statistics_screen_48",
                label: "Text · statistics_screen.dart",
                child: Text(
                  AppLocalizations.text(context, label),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? theme.primary : Colors.white60,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
