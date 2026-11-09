import '../core/models/rule_preset.dart';
import '../core/providers/settings_provider.dart';
import '../shared/widgets/glass_alert_dialog.dart';
import '../shared/widgets/custom_notification.dart';
import '../shared/widgets/theme_region.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/theme_provider.dart';
import '../core/models/theme_config.dart';
import '../core/localization/app_localizations.dart';
import '../core/providers/rules_provider.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showPresets() async {
    final theme = ref.read(themeProvider).currentTheme;
    final preset = await showDialog<RulePreset>(
      context: context,
      builder: (ctx) => GlassAlertDialog(
        surfaceColor: theme.surface,
        title: Text(AppLocalizations.text(context, "Пресеты правил")),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: RulePreset.all
                .map(
                  (p) => ListTile(
                    title: Text(AppLocalizations.text(ctx, p.title)),
                    subtitle: Text(AppLocalizations.text(ctx, p.description)),
                    leading: const Icon(Icons.auto_fix_high_rounded),
                    onTap: () => Navigator.pop(ctx, p),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (preset == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassAlertDialog(
        surfaceColor: theme.surface,
        title: Text(AppLocalizations.text(ctx, preset.title)),
        content: Text(
          AppLocalizations.text(
            context,
            "{0}\n\n{1}\n\n{2}",
            args: [
              AppLocalizations.text(ctx, preset.description),
              preset.rules.map((r) => '${r.value} → ${r.action}').join('\n'),
              AppLocalizations.text(
                ctx,
                'Правила добавятся в начало списка. Маршрутизация будет включена; применятся после переподключения VPN.',
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
            child: Text(AppLocalizations.text(context, "Применить")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(rulesProvider.notifier).applyPreset(preset.rules);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(useRouting: true));
    CustomNotification.show(
      context,
      AppLocalizations.text(context, "Пресет применён. Переподключите VPN."),
    );
  }

  void _showAddRuleMenu() {
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    HapticFeedback.lightImpact();

    String selectedType = 'GeoSite';
    String selectedAction = 'PROXY';
    final valueController = TextEditingController();

    final types = ['GeoSite', 'GeoIP', 'Domain Keyword', 'Port'];
    final actions = ['PROXY', 'DIRECT', 'BLOCK'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.12),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: ThemeRegion.auto(
                  id: "widget_rules_screen_0",
                  label: "Container · rules_screen.dart",
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.surface.withOpacity(0.24),
                    ),
                    child: ThemeRegion.auto(
                      id: "widget_rules_screen_1",
                      label: "Column · rules_screen.dart",
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: ThemeRegion.auto(
                              id: "widget_rules_screen_2",
                              label: "Container · rules_screen.dart",
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ThemeRegion.auto(
                            id: "widget_rules_screen_3",
                            label: "Text · rules_screen.dart",
                            child: Text(
                              loc.translate('new_rule'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ThemeRegion.auto(
                            id: "widget_rules_screen_4",
                            label: "Text · rules_screen.dart",
                            child: Text(
                              loc.translate('match_condition'),
                              style: TextStyle(
                                color: theme.textDim,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: types.length,
                              itemBuilder: (context, index) {
                                final type = types[index];
                                final isSelected = type == selectedType;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setModalState(() => selectedType = type);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? theme.primary.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected
                                            ? theme.primary
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_rules_screen_5",
                                      label: "Text · rules_screen.dart",
                                      child: Text(
                                        type,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? theme.primary
                                              : theme.textDim,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          ThemeRegion.auto(
                            id: "widget_rules_screen_6",
                            label: "Container · rules_screen.dart",
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ThemeRegion.auto(
                                id: "widget_rules_screen_7",
                                label: "TextField · rules_screen.dart",
                                child: TextField(
                                  controller: valueController,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                  ),
                                  decoration: InputDecoration.collapsed(
                                    hintText: selectedType == 'Port'
                                        ? '80, 443'
                                        : (selectedType == 'GeoSite'
                                              ? 'ru, youtube'
                                              : AppLocalizations.text(
                                                  context,
                                                  "значение...",
                                                )),
                                    hintStyle: const TextStyle(
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ThemeRegion.auto(
                            id: "widget_rules_screen_8",
                            label: "Text · rules_screen.dart",
                            child: Text(
                              loc.translate('action_label'),
                              style: TextStyle(
                                color: theme.textDim,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ThemeRegion.auto(
                            id: "widget_rules_screen_9",
                            label: "Row · rules_screen.dart",
                            child: Row(
                              children: actions.map((action) {
                                final isSelected = action == selectedAction;
                                Color actionColor = theme.primary;
                                if (action == 'DIRECT')
                                  actionColor = Colors.greenAccent;
                                if (action == 'BLOCK')
                                  actionColor = Colors.grey;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setModalState(
                                        () => selectedAction = action,
                                      );
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? actionColor.withOpacity(0.2)
                                            : Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isSelected
                                              ? actionColor
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Center(
                                        child: ThemeRegion.auto(
                                          id: "widget_rules_screen_10",
                                          label: "Text · rules_screen.dart",
                                          child: Text(
                                            action,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? actionColor
                                                  : theme.textDim,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 32),
                          GestureDetector(
                            onTap: () {
                              if (valueController.text.trim().isEmpty) return;
                              HapticFeedback.mediumImpact();

                              final newRule = AppRule(
                                id: DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                                type: selectedType,
                                value: valueController.text.trim(),
                                action: selectedAction,
                              );
                              ref.read(rulesProvider.notifier).addRule(newRule);

                              Navigator.pop(context);
                            },
                            child: ThemeRegion.auto(
                              id: "widget_rules_screen_11",
                              label: "Container · rules_screen.dart",
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [theme.primary, theme.primaryDark],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: ThemeRegion.auto(
                                    id: "widget_rules_screen_12",
                                    label: "Text · rules_screen.dart",
                                    child: Text(
                                      loc.translate('save'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getActionColor(String action, ThemeConfig theme) {
    switch (action.toUpperCase()) {
      case 'DIRECT':
        return Colors.greenAccent;
      case 'BLOCK':
        return Colors.grey;
      case 'PROXY':
      default:
        return theme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final rules = ref.watch(rulesProvider);

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_rules',
        child: ThemeRegion.auto(
          id: "widget_rules_screen_13",
          label: "Stack · rules_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: 100,
                right: -150,
                child: ThemeRegion.auto(
                  id: "widget_rules_screen_14",
                  label: "Container · rules_screen.dart",
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
                  id: "widget_rules_screen_15",
                  label: "Container · rules_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),
              SafeArea(
                child: ThemeRegion.auto(
                  id: "widget_rules_screen_16",
                  label: "Column · rules_screen.dart",
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        child: ThemeRegion.auto(
                          id: "widget_rules_screen_17",
                          label: "Row · rules_screen.dart",
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(context);
                                },
                                child: ThemeRegion.auto(
                                  id: "widget_rules_screen_18",
                                  label: "Container · rules_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.surface.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_rules_screen_19",
                                      label: "Icon · rules_screen.dart",
                                      child: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ThemeRegion.auto(
                                id: "widget_rules_screen_20",
                                label: "Text · rules_screen.dart",
                                child: Text(
                                  loc.translate('rules'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _showAddRuleMenu,
                                child: ThemeRegion.auto(
                                  id: "widget_rules_screen_21",
                                  label: "Container · rules_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.primary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: theme.primary.withOpacity(0.5),
                                      ),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_rules_screen_22",
                                      label: "Icon · rules_screen.dart",
                                      child: Icon(
                                        Icons.add_rounded,
                                        color: theme.primary,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 6,
                        ),
                        child: OutlinedButton.icon(
                          onPressed: _showPresets,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            AppLocalizations.text(context, "Пресеты правил"),
                          ),
                        ),
                      ),
                      ThemeRegion.auto(
                        id: "widget_rules_screen_23",
                        label: "Container · rules_screen.dart",
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.surface.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: theme.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.primary.withOpacity(0.5),
                              ),
                            ),
                            labelColor: theme.primary,
                            unselectedLabelColor: theme.textDim,
                            dividerColor: Colors.transparent,
                            labelPadding: EdgeInsets.zero,
                            tabs: [
                              Tab(
                                child: ThemeRegion.auto(
                                  id: "widget_rules_screen_24",
                                  label: "Text · rules_screen.dart",
                                  child: Text(
                                    loc.translate('interface'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              Tab(
                                child: ThemeRegion.auto(
                                  id: "widget_rules_screen_25",
                                  label: "Text · rules_screen.dart",
                                  child: Text(
                                    loc.translate('raw_json'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fade(delay: 100.ms),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            rules.isEmpty
                                ? Center(
                                    child: ThemeRegion.auto(
                                      id: "widget_rules_screen_26",
                                      label: "Text · rules_screen.dart",
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Нет активных правил",
                                        ),
                                        style: TextStyle(
                                          color: theme.textDim,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 8,
                                    ),
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: rules.length,
                                    itemBuilder: (context, index) {
                                      final rule = rules[index];
                                      final actionColor = _getActionColor(
                                        rule.action,
                                        theme,
                                      );
                                      return ThemeRegion.auto(
                                        id: "widget_rules_screen_27",
                                        label: "Container · rules_screen.dart",
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.surface.withOpacity(
                                              0.4,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(
                                                0.05,
                                              ),
                                            ),
                                          ),
                                          child: ThemeRegion.auto(
                                            id: "widget_rules_screen_28",
                                            label: "Row · rules_screen.dart",
                                            child: Row(
                                              children: [
                                                ThemeRegion.auto(
                                                  id: "widget_rules_screen_29",
                                                  label: "Container · rules_screen.dart",
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white10,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: ThemeRegion.auto(
                                                      id: "widget_rules_screen_30",
                                                      label: "Text · rules_screen.dart",
                                                      child: Text(
                                                        rule.type,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.white70,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: ThemeRegion.auto(
                                                    id: "widget_rules_screen_31",
                                                    label: "Text · rules_screen.dart",
                                                    child: Text(
                                                      rule.value,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors.white,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                ThemeRegion.auto(
                                                  id: "widget_rules_screen_32",
                                                  label: "Container · rules_screen.dart",
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: actionColor
                                                          .withOpacity(0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: actionColor
                                                            .withOpacity(0.5),
                                                      ),
                                                    ),
                                                    child: ThemeRegion.auto(
                                                      id: "widget_rules_screen_33",
                                                      label: "Text · rules_screen.dart",
                                                      child: Text(
                                                        rule.action,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: actionColor,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () {
                                                    HapticFeedback.lightImpact();
                                                    ref
                                                        .read(
                                                          rulesProvider
                                                              .notifier,
                                                        )
                                                        .removeRule(rule.id);
                                                  },
                                                  child: ThemeRegion.auto(
                                                    id: "widget_rules_screen_34",
                                                    label: "Icon · rules_screen.dart",
                                                    child: const Icon(
                                                      Icons.close_rounded,
                                                      color: Colors.white38,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ).animate().fade(delay: (20 * index).ms).slideX(begin: 0.05);
                                    },
                                  ),
                            Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: ThemeRegion.auto(
                                id: "widget_rules_screen_35",
                                label: "Container · rules_screen.dart",
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: ThemeRegion.auto(
                                    id: "widget_rules_screen_36",
                                    label: "TextField · rules_screen.dart",
                                    child: const TextField(
                                      maxLines: null,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                      ),
                                      decoration: InputDecoration.collapsed(
                                        hintText: '{\n  "routing": {\n    "rules": [\n      {\n        "type": "field",\n        "outboundTag": "direct",\n        "domain": ["geosite:cn"]\n      }\n    ]\n  }\n}',
                                        hintStyle: TextStyle(
                                          color: Colors.white24,
                                        ),
                                      ),
                                    ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
