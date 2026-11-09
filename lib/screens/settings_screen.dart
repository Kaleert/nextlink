import '../shared/widgets/theme_region.dart';

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/theme_provider.dart';
import '../core/localization/app_localizations.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/core_manager_provider.dart';
import '../core/providers/logger_provider.dart';
import '../core/utils/log_files.dart';
import '../shared/widgets/glass_input_dialog.dart';
import '../shared/widgets/glass_alert_dialog.dart';
import '../shared/widgets/animated_background.dart';
import '../shared/widgets/custom_notification.dart';
import '../shared/widgets/app_progress_bar.dart';
import 'logs_screen.dart';
import 'client_tour_screen.dart';
import 'lan_proxy_dialog.dart';
import 'qr_style_screen.dart';
import 'backup_screen.dart';
import 'theme_editor_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _versionClickCount = 0;
  bool _showSecrets = false;

  Future<void> _openInfoUrl(String url) async {
    try {
      await const MethodChannel('pro.kaleert.nextlink/vpn')
          .invokeMethod<void>('openExternalUrl', url);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted)
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Не удалось открыть ссылку. Ссылка скопирована",
          ),
          isError: true,
        );
    }
  }

  void _showGlassMenu(
    String title,
    List<String> options,
    String currentValue,
    void Function(String) onSelected, {
    String Function(String)? displayMapper,
  }) {
    final theme = ref.read(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: ThemeRegion.auto(
            id: "widget_settings_screen_0",
            label: "Container · settings_screen.dart",
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.surface.withOpacity(0.24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: SingleChildScrollView(
                child: ThemeRegion.auto(
                  id: "widget_settings_screen_1",
                  label: "Column · settings_screen.dart",
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemeRegion.auto(
                        id: "widget_settings_screen_2",
                        label: "Container · settings_screen.dart",
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ThemeRegion.auto(
                          id: "widget_settings_screen_3",
                          label: "Text · settings_screen.dart",
                          child: Text(
                            AppLocalizations.text(context, title),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...options.map((option) {
                        final displayLabel =
                            displayMapper?.call(option) ??
                            loc.translate(option);
                        final isSelected = option == currentValue;
                        return GestureDetector(
                          onTap: () {
                            onSelected(option);
                            Navigator.pop(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            child: ThemeRegion.auto(
                              id: "widget_settings_screen_4",
                              label: "Row · settings_screen.dart",
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ThemeRegion.auto(
                                      id: "widget_settings_screen_5",
                                      label: "Text · settings_screen.dart",
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          displayLabel,
                                        ),
                                        style: TextStyle(
                                          color: isSelected
                                              ? theme.primary
                                              : Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    ThemeRegion.auto(
                                      id: "widget_settings_screen_6",
                                      label: "Icon · settings_screen.dart",
                                      child: Icon(
                                        Icons.check_rounded,
                                        color: theme.primary,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomUrlDialog(
    String title,
    String currentUrl,
    ValueChanged<String> onSelected,
  ) {
    final theme = ref.read(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentUrl);
    showDialog(
      useRootNavigator: false,
      context: context,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (dialogContext) => GlassInputDialog(
        title: title,
        controller: controller,
        surfaceColor: theme.surface,
        accentColor: theme.primary,
        textDimColor: theme.textDim,
        saveLabel: loc.translate('save'),
        cancelLabel: loc.translate('cancel'),
        hintText: 'https://...',
        helperText: loc.translate('leave_empty_for_default'),
        onCancel: () => Navigator.pop(dialogContext),
        onSave: () {
          onSelected(controller.text);
          Navigator.pop(dialogContext);
        },
      ),
    );
  }

  void _showInputDialog(
    String title,
    String currentValue,
    void Function(String) onSelected, {
    bool isNumber = false,
  }) {
    final theme = ref.read(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentValue);
    showDialog(
      useRootNavigator: false,
      context: context,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (dialogContext) => GlassInputDialog(
        title: title,
        controller: controller,
        surfaceColor: theme.surface,
        accentColor: theme.primary,
        textDimColor: theme.textDim,
        saveLabel: loc.translate('save'),
        cancelLabel: loc.translate('cancel'),
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        onCancel: () => Navigator.pop(dialogContext),
        onSave: () {
          onSelected(controller.text);
          Navigator.pop(dialogContext);
        },
      ),
    );
  }

  Future<void> _confirmResetSettings() async {
    final theme = ref.read(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final shouldReset = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      barrierColor: Colors.black.withOpacity(0.18),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: ThemeRegion.auto(
              id: "widget_settings_screen_7",
              label: "Container · settings_screen.dart",
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: theme.surface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: ThemeRegion.auto(
                  id: "widget_settings_screen_8",
                  label: "Column · settings_screen.dart",
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThemeRegion.auto(
                        id: "widget_settings_screen_9",
                        label: "Text · settings_screen.dart",
                        child: Text(
                          loc.translate('confirm_reset_title'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ThemeRegion.auto(
                        id: "widget_settings_screen_10",
                        label: "Text · settings_screen.dart",
                        child: Text(
                          loc.translate('confirm_reset_body'),
                          style: TextStyle(color: theme.textDim),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ThemeRegion.auto(
                        id: "widget_settings_screen_11",
                        label: "Row · settings_screen.dart",
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ThemeRegion.auto(
                              id: "widget_settings_screen_12",
                              label: "TextButton · settings_screen.dart",
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: ThemeRegion.auto(
                                  id: "widget_settings_screen_13",
                                  label: "Text · settings_screen.dart",
                                  child: Text(loc.translate('cancel')),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ThemeRegion.auto(
                              id: "widget_settings_screen_14",
                              label: "TextButton · settings_screen.dart",
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.primary,
                                ),
                                child: ThemeRegion.auto(
                                  id: "widget_settings_screen_16",
                                  label: "Text · settings_screen.dart",
                                  child: Text(loc.translate('reset_settings')),
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
            ),
          ),
        ),
      ),
    );
    if (!mounted || shouldReset != true) return;
    final defaults = SettingsState();
    ref.read(settingsProvider.notifier).update(defaults);
    await LogFiles.configureRetention(
      maxFiles: defaults.maxLogFiles,
      maxStorageMb: defaults.maxLogStorageMb,
    );
    HapticFeedback.heavyImpact();
  }

  void _showThemeManager() {
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withOpacity(.18),
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ThemeGalleryScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final themeState = ref.watch(themeProvider);
    final loc = AppLocalizations.of(context)!;

    // Вспомогательная функция для обновления полей
    void update<T>(T val, SettingsState Function(SettingsState s, T v) u) =>
        notifier.updateField(val, u);

    return Scaffold(
      body: ThemeRegion(
        id: 'screen_settings',
        child: ThemeRegion.auto(
          id: "widget_settings_screen_17",
          label: "Stack · settings_screen.dart",
          child: Stack(
            children: [
              const AnimatedMeshBackground(isConnected: false),

              // Дополнительные сияния (glows)
              Positioned(
                top: 100,
                left: -50,
                child: ThemeRegion.auto(
                  id: "widget_settings_screen_18",
                  label: "Container · settings_screen.dart",
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: themeState.currentTheme.primary.withOpacity(0.05),
                      boxShadow: [
                        BoxShadow(
                          color: themeState.currentTheme.primary.withOpacity(
                            0.1,
                          ),
                          blurRadius: 100,
                          spreadRadius: 50,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 200,
                right: -100,
                child: ThemeRegion.auto(
                  id: "widget_settings_screen_19",
                  label: "Container · settings_screen.dart",
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blueAccent.withOpacity(0.03),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.05),
                          blurRadius: 150,
                          spreadRadius: 70,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: ThemeRegion.auto(
                  id: "widget_settings_screen_20",
                  label: "Column · settings_screen.dart",
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: ThemeRegion.auto(
                          id: "widget_settings_screen_21",
                          label: "Row · settings_screen.dart",
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: ThemeRegion.auto(
                                  id: "widget_settings_screen_22",
                                  label: "Container · settings_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_settings_screen_23",
                                      label: "Icon · settings_screen.dart",
                                      child: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              ThemeRegion.auto(
                                id: "widget_settings_screen_24",
                                label: "Text · settings_screen.dart",
                                child: Text(
                                  loc.translate('settings'),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          children: [
                            _buildExpandableSection(
                              title: loc.translate('interface'),
                              icon: Icons.palette_outlined,
                              children: [
                                _buildSwitchTile(
                                  title: AppLocalizations.text(
                                    context,
                                    'Глобус серверов',
                                  ),
                                  subtitle: AppLocalizations.text(
                                    context,
                                    'Локации серверов на главном экране',
                                  ),
                                  icon: Icons.public_rounded,
                                  value: settings.showServerGlobe,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(showServerGlobe: v),
                                  ),
                                ),

                                _buildMenuTile(
                                  title: AppLocalizations.text(
                                    context,
                                    "Оформление QR-кодов",
                                  ),
                                  subtitle: AppLocalizations.text(
                                    context,
                                    "Цвета, форма, поля и размер PNG",
                                  ),
                                  icon: Icons.qr_code_rounded,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const QrStyleScreen(),
                                    ),
                                  ),
                                ),

                                _buildMenuTile(
                                  title: loc.translate('language'),
                                  subtitle: settings.language == 'System'
                                      ? loc.translate('system_lang')
                                      : settings.language,
                                  icon: Icons.language_rounded,
                                  onTap: () => _showGlassMenu(
                                    loc.translate('select_language'),
                                    [
                                      'System',
                                      'Русский',
                                      'English',
                                      'Українська',
                                    ],
                                    settings.language,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(language: v),
                                    ),
                                    displayMapper: (v) => v == 'System'
                                        ? loc.translate('system_lang')
                                        : v,
                                  ),
                                ),
                                _buildMenuTile(
                                  title: loc.translate('theme'),
                                  subtitle:
                                      themeState.currentTheme.name.startsWith(
                                        'theme_',
                                      )
                                      ? loc.translate(
                                          themeState.currentTheme.name,
                                        )
                                      : themeState.currentTheme.name,
                                  icon: Icons.color_lens_outlined,
                                  onTap: _showThemeManager,
                                ),
                                _buildMenuTile(
                                  title: loc.translate('log_level'),
                                  subtitle: settings.logLevel.toUpperCase(),
                                  icon: Icons.bug_report_rounded,
                                  onTap: () => _showGlassMenu(
                                    loc.translate('log_level'),
                                    ['debug', 'info', 'warn', 'error'],
                                    settings.logLevel,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(logLevel: v),
                                    ),
                                  ),
                                ),
                                const Divider(color: Colors.white10, height: 1),
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: ThemeRegion.auto(
                                    id: "widget_settings_screen_25",
                                    label: "Column · settings_screen.dart",
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ThemeRegion.auto(
                                          id: "widget_settings_screen_26",
                                          label: "Row · settings_screen.dart",
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              ThemeRegion.auto(
                                                id: "widget_settings_screen_27",
                                                label: "Text · settings_screen.dart",
                                                child: Text(
                                                  loc.translate(
                                                    'interface_scale',
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              ThemeRegion.auto(
                                                id: "widget_settings_screen_28",
                                                label: "Text · settings_screen.dart",
                                                child: Text(
                                                  '${(settings.uiScale * 100).toInt()}%',
                                                  style: TextStyle(
                                                    color: themeState
                                                        .currentTheme
                                                        .primary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ThemeRegion.auto(
                                          id: "widget_settings_screen_29",
                                          label:
                                              "Slider · settings_screen.dart",
                                          child: Slider(
                                            value: settings.uiScale,
                                            min: 0.8,
                                            max: 1.2,
                                            divisions: 4,
                                            activeColor:
                                                themeState.currentTheme.primary,
                                            onChanged: (v) => update(
                                              v,
                                              (s, v) => s.copyWith(uiScale: v),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ).animate().fade(delay: 50.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('core_transport'),
                              icon: Icons.memory_rounded,
                              children: [
                                _buildMenuTile(
                                  title: loc.translate('preferred_core'),
                                  subtitle: settings.preferredCore,
                                  icon: Icons.settings_input_component_rounded,
                                  onTap: () => _showGlassMenu(
                                    loc.translate('preferred_core'),
                                    ['SINGBOX', 'XRAY'],
                                    settings.preferredCore,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(preferredCore: v),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('core_failover'),
                                  subtitle: loc.translate('core_failover_desc'),
                                  icon: Icons.swap_horizontal_circle_rounded,
                                  value: settings.coreFailover,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(coreFailover: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: 'TCP Fast Open',
                                  subtitle: loc.translate('tcp_fast_open_desc'),
                                  icon: Icons.speed_rounded,
                                  value: settings.tcpFastOpen,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(tcpFastOpen: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('fragmentation'),
                                  subtitle: loc.translate('fragmentation_desc'),
                                  icon: Icons.waves_rounded,
                                  value: settings.fragment,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(fragment: v),
                                  ),
                                ),
                                if (settings.fragment) ...[
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                                    child: ThemeRegion.auto(
                                      id: "widget_settings_screen_30",
                                      label: "Text · settings_screen.dart",
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Параметры пакетов применяются в Xray. Sing-box использует собственную фрагментацию TLS.",
                                        ),
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildMenuTile(
                                    title: 'Fragment packets',
                                    subtitle: settings.fragmentPackets,
                                    icon: Icons.all_inclusive_rounded,
                                    onTap: () => _showGlassMenu(
                                      'Fragment packets',
                                      ['tlshello', '1-3', '1'],
                                      settings.fragmentPackets,
                                      (v) => update(
                                        v,
                                        (s, v) =>
                                            s.copyWith(fragmentPackets: v),
                                      ),
                                    ),
                                  ),
                                  _buildMenuTile(
                                    title: 'Fragment length',
                                    subtitle: settings.fragmentLength,
                                    icon: Icons.straighten_rounded,
                                    onTap: () => _showInputDialog(
                                      'Fragment length',
                                      settings.fragmentLength,
                                      (v) => update(
                                        v.trim().isEmpty ? '10-50' : v.trim(),
                                        (s, v) => s.copyWith(fragmentLength: v),
                                      ),
                                    ),
                                  ),
                                  _buildMenuTile(
                                    title: 'Fragment interval',
                                    subtitle: settings.fragmentInterval,
                                    icon: Icons.timer_outlined,
                                    onTap: () => _showInputDialog(
                                      'Fragment interval',
                                      settings.fragmentInterval,
                                      (v) => update(
                                        v.trim().isEmpty ? '5-10' : v.trim(),
                                        (s, v) =>
                                            s.copyWith(fragmentInterval: v),
                                      ),
                                    ),
                                  ),
                                ],

                                const Padding(
                                  padding: EdgeInsets.only(left: 20, top: 10),
                                  child: ThemeRegion.auto(
                                    id: "widget_settings_screen_31",
                                    label: "Text · settings_screen.dart",
                                    child: Text(
                                      "XRAY MUX",
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('enable_mux'),
                                  subtitle: '',
                                  icon: Icons.call_split_rounded,
                                  value: settings.xrayMux,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(xrayMux: v),
                                  ),
                                ),
                                if (settings.xrayMux)
                                  _buildMenuTile(
                                    title: loc.translate('mux_concurrency'),
                                    subtitle: settings.xrayMuxConcurrency
                                        .toString(),
                                    icon: Icons.format_list_numbered_rounded,
                                    onTap: () => _showGlassMenu(
                                      loc.translate('mux_concurrency'),
                                      ['4', '8', '16', '32'],
                                      settings.xrayMuxConcurrency.toString(),
                                      (v) => update(
                                        int.parse(v),
                                        (s, v) =>
                                            s.copyWith(xrayMuxConcurrency: v),
                                      ),
                                    ),
                                  ),

                                const Padding(
                                  padding: EdgeInsets.only(left: 20, top: 10),
                                  child: ThemeRegion.auto(
                                    id: "widget_settings_screen_32",
                                    label: "Text · settings_screen.dart",
                                    child: Text(
                                      "SING-BOX MUX",
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('enable_mux'),
                                  subtitle: '',
                                  icon: Icons.call_split_rounded,
                                  value: settings.singboxMux,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(singboxMux: v),
                                  ),
                                ),
                                if (settings.singboxMux) ...[
                                  _buildMenuTile(
                                    title: loc.translate('mux_protocol'),
                                    subtitle: settings.singboxMuxProtocol,
                                    icon: Icons.account_tree_rounded,
                                    onTap: () => _showGlassMenu(
                                      loc.translate('mux_protocol'),
                                      ['smux', 'yamux', 'h2mux'],
                                      settings.singboxMuxProtocol,
                                      (v) => update(
                                        v,
                                        (s, v) =>
                                            s.copyWith(singboxMuxProtocol: v),
                                      ),
                                    ),
                                  ),
                                  _buildMenuTile(
                                    title: 'Mux connections',
                                    subtitle: settings.singboxMuxMaxConnections
                                        .toString(),
                                    icon: Icons.hub_rounded,
                                    onTap: () => _showGlassMenu(
                                      'Mux connections',
                                      ['1', '2', '4', '8'],
                                      settings.singboxMuxMaxConnections
                                          .toString(),
                                      (v) => update(
                                        int.parse(v),
                                        (s, v) => s.copyWith(
                                          singboxMuxMaxConnections: v,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildMenuTile(
                                    title: 'Mux streams',
                                    subtitle: settings.singboxMuxMinStreams
                                        .toString(),
                                    icon: Icons.format_list_numbered_rounded,
                                    onTap: () => _showGlassMenu(
                                      'Mux streams',
                                      ['1', '2', '4', '8', '16'],
                                      settings.singboxMuxMinStreams.toString(),
                                      (v) => update(
                                        int.parse(v),
                                        (s, v) =>
                                            s.copyWith(singboxMuxMinStreams: v),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ).animate().fade(delay: 100.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('tun_network'),
                              icon: Icons.vpn_lock_rounded,
                              children: [
                                _buildMenuTile(
                                  title: 'TUN MTU',
                                  subtitle: settings.tunMtu.toString(),
                                  icon: Icons.compress_rounded,
                                  onTap: () => _showGlassMenu(
                                    'MTU',
                                    ['1500', '9000'],
                                    settings.tunMtu.toString(),
                                    (v) => update(
                                      int.parse(v),
                                      (s, v) => s.copyWith(tunMtu: v),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('strict_route'),
                                  subtitle: loc.translate('strict_route_desc'),
                                  icon: Icons.security_rounded,
                                  value: settings.strictMode,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(strictMode: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('block_quic'),
                                  subtitle: loc.translate('block_quic_desc'),
                                  icon: Icons.block_flipped,
                                  value: settings.blockQuic,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(blockQuic: v),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: 'IP mode',
                                  subtitle: settings.ipType,
                                  icon: Icons.network_cell_rounded,
                                  onTap: () => _showGlassMenu(
                                    'IP mode',
                                    ['IPv4', 'IPv6', 'Auto'],
                                    settings.ipType,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(
                                        ipType: v,
                                        ipv6: v != 'IPv4',
                                      ),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('allow_lan'),
                                  subtitle: loc.translate('allow_lan_desc'),
                                  icon: Icons.wifi_tethering_rounded,
                                  value: settings.lanConn,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(lanConn: v),
                                  ),
                                ),
                                if (settings.lanConn)
                                  _buildMenuTile(
                                    title: AppLocalizations.text(
                                      context,
                                      "Порт и авторизация LAN",
                                    ),
                                    subtitle: AppLocalizations.text(
                                      context,
                                      "HTTP · {0} · {1}",
                                      args: [
                                        settings.lanPort,
                                        settings.lanUsername.isEmpty
                                            ? AppLocalizations.text(
                                                context,
                                                "Без авторизации",
                                              )
                                            : settings.lanUsername,
                                      ],
                                    ),
                                    icon: Icons.manage_accounts_outlined,
                                    onTap: () async {
                                      final result =
                                          await showDialog<SettingsState>(
                                            context: context,
                                            useRootNavigator: false,
                                            builder: (_) => LanProxyDialog(
                                              settings: settings,
                                            ),
                                          );
                                      if (result != null && mounted)
                                        update(
                                          result,
                                          (s, v) => s.copyWith(
                                            lanPort: v.lanPort,
                                            lanUsername: v.lanUsername,
                                            lanPassword: v.lanPassword,
                                          ),
                                        );
                                    },
                                  ),
                              ],
                            ).animate().fade(delay: 150.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('dns_settings'),
                              icon: Icons.dns_rounded,
                              children: [
                                _buildSwitchTile(
                                  title: loc.translate('fake_dns'),
                                  subtitle: loc.translate('fake_dns_desc'),
                                  icon: Icons.masks_rounded,
                                  value: settings.fakeDns,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(fakeDns: v),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: loc.translate('remote_dns'),
                                  subtitle: settings.remoteDns,
                                  icon: Icons.cloud_queue_rounded,
                                  onTap: () => _showInputDialog(
                                    loc.translate('remote_dns'),
                                    settings.remoteDns,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(remoteDns: v),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('use_local_dns'),
                                  subtitle: '',
                                  icon: Icons.home_work_rounded,
                                  value: settings.useLocalDns,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(useLocalDns: v),
                                  ),
                                ),
                                if (settings.useLocalDns)
                                  _buildMenuTile(
                                    title: loc.translate('local_dns_server'),
                                    subtitle: settings.localDnsServer,
                                    icon: Icons.router_rounded,
                                    onTap: () => _showInputDialog(
                                      loc.translate('local_dns_server'),
                                      settings.localDnsServer,
                                      (v) => update(
                                        v,
                                        (s, v) => s.copyWith(localDnsServer: v),
                                      ),
                                    ),
                                  ),
                              ],
                            ).animate().fade(delay: 200.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('routing'),
                              icon: Icons.alt_route_rounded,
                              children: [
                                _buildSwitchTile(
                                  title: loc.translate('use_routing'),
                                  subtitle: '',
                                  icon: Icons.route_rounded,
                                  value: settings.useRouting,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(useRouting: v),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: loc.translate('rule_order'),
                                  subtitle: settings.ruleOrder,
                                  icon: Icons.sort_rounded,
                                  onTap: () => _showGlassMenu(
                                    loc.translate('rule_order'),
                                    [
                                      'Block -> Direct -> Proxy',
                                      'Proxy -> Direct -> Block',
                                    ],
                                    settings.ruleOrder,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(ruleOrder: v),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('bypass_lan'),
                                  subtitle: loc.translate('bypass_lan_desc'),
                                  icon: Icons.shortcut_rounded,
                                  value: settings.bypassLan,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(bypassLan: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: 'Sniffing',
                                  subtitle: '',
                                  icon: Icons.travel_explore_rounded,
                                  value: settings.sniffing,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(sniffing: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('packet_analysis'),
                                  subtitle: loc.translate('sniffing_desc'),
                                  icon: Icons.manage_search_rounded,
                                  value: settings.packetAnalysis,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(packetAnalysis: v),
                                  ),
                                ),
                              ],
                            ).animate().fade(delay: 250.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('subscriptions'),
                              icon: Icons.subscriptions_rounded,
                              children: [
                                _buildSwitchTile(
                                  title: loc.translate('auto_update'),
                                  subtitle: '',
                                  icon: Icons.sync_rounded,
                                  value: settings.autoUpdateSubs,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(autoUpdateSubs: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: AppLocalizations.text(
                                    context,
                                    "Уведомлять об обновлении подписок",
                                  ),
                                  subtitle: AppLocalizations.text(
                                    context,
                                    "Показывать результат успешного фонового обновления",
                                  ),
                                  icon: Icons.notifications_outlined,
                                  value: settings.notifySubUpdate,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(notifySubUpdate: v),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: loc.translate('update_interval'),
                                  subtitle:
                                      '${settings.subUpdateIntervalHours} ${loc.translate('unit_hours')}',
                                  icon: Icons.timer_rounded,
                                  onTap: () => _showGlassMenu(
                                    loc.translate('update_interval'),
                                    ['1', '6', '12', '24'],
                                    settings.subUpdateIntervalHours.toString(),
                                    (v) => update(
                                      int.parse(v),
                                      (s, v) =>
                                          s.copyWith(subUpdateIntervalHours: v),
                                    ),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('update_on_start'),
                                  subtitle: '',
                                  icon: Icons.start_rounded,
                                  value: settings.updateOnStart,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(updateOnStart: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('ping_on_start'),
                                  subtitle: '',
                                  icon: Icons.speed_rounded,
                                  value: settings.pingOnStart,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(pingOnStart: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('prevent_duplicates'),
                                  subtitle: '',
                                  icon: Icons.copy_all_rounded,
                                  value: settings.preventDuplicates,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(preventDuplicates: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('collapse_subs'),
                                  subtitle: '',
                                  icon: Icons.unfold_less_rounded,
                                  value: settings.collapseSubs,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(collapseSubs: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: loc.translate('send_hwid'),
                                  subtitle: '',
                                  icon: Icons.fingerprint_rounded,
                                  value: settings.sendHwid,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(sendHwid: v),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: loc.translate('user_agent'),
                                  subtitle: settings.userAgent,
                                  icon: Icons.android_rounded,
                                  onTap: () => _showInputDialog(
                                    loc.translate('user_agent'),
                                    settings.userAgent,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(userAgent: v),
                                    ),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: loc.translate('sorting'),
                                  subtitle: loc.translate(settings.subSortMode),
                                  icon: Icons.sort_by_alpha_rounded,
                                  onTap: () => _showGlassMenu(
                                    loc.translate('sorting'),
                                    [
                                      'sorting_none',
                                      'sorting_ping',
                                      'sorting_alphabetical',
                                    ],
                                    settings.subSortMode,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(subSortMode: v),
                                    ),
                                  ),
                                ),
                              ],
                            ).animate().fade(delay: 350.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('ping'),
                              icon: Icons.network_check_rounded,
                              children: [
                                _buildMenuTile(
                                  title: loc.translate('ping_type'),
                                  subtitle: settings.pingType == 'via Proxy'
                                      ? loc.translate('ping_via_proxy')
                                      : settings.pingType,
                                  icon: Icons.compare_arrows_rounded,
                                  onTap: () => _showGlassMenu(
                                    loc.translate('ping_type'),
                                    ['via Proxy', 'TCP', 'ICMP'],
                                    settings.pingType,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(pingType: v),
                                    ),
                                    displayMapper: (v) => v == 'via Proxy'
                                        ? loc.translate('ping_via_proxy')
                                        : v,
                                  ),
                                ),
                                _buildMenuTile(
                                  title: loc.translate('ping_url'),
                                  subtitle: settings.pingUrl,
                                  icon: Icons.link_rounded,
                                  onTap: () => _showInputDialog(
                                    loc.translate('ping_url'),
                                    settings.pingUrl,
                                    (v) => update(
                                      v,
                                      (s, v) => s.copyWith(pingUrl: v),
                                    ),
                                  ),
                                ),
                              ],
                            ).animate().fade(delay: 400.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('resource_center'),
                              icon: Icons.folder_zip_rounded,
                              children: [
                                Consumer(
                                  builder: (context, ref, child) {
                                    final coreStatus = ref.watch(
                                      coreManagerProvider,
                                    );
                                    final coreNotifier = ref.read(
                                      coreManagerProvider.notifier,
                                    );
                                    return ThemeRegion.auto(
                                      id: "widget_settings_screen_33",
                                      label: "Column · settings_screen.dart",
                                      child: Column(
                                        children: [
                                          _buildCoreTileWithActions(
                                            title: 'Xray-core',
                                            status: coreStatus.xray,
                                            icon: Icons.memory_rounded,
                                            onDownload: () =>
                                                coreNotifier.downloadItem(
                                                  CoreType.xray,
                                                  force: true,
                                                ),
                                            onResume: () => coreNotifier
                                                .resumeDownload(CoreType.xray),
                                            onSetUrl: () =>
                                                _showCustomUrlDialog(
                                                  loc.translate('custom_url') +
                                                      ' Xray',
                                                  settings.xrayUrl,
                                                  (v) => update(
                                                    v,
                                                    (s, v) =>
                                                        s.copyWith(xrayUrl: v),
                                                  ),
                                                ),
                                            customUrl: settings.xrayUrl,
                                            loc: loc,
                                          ),
                                          const Divider(
                                            color: Colors.white10,
                                            height: 1,
                                          ),
                                          _buildCoreTileWithActions(
                                            title: 'Sing-box',
                                            status: coreStatus.singbox,
                                            icon: Icons.grid_view_rounded,
                                            onDownload: () =>
                                                coreNotifier.downloadItem(
                                                  CoreType.singbox,
                                                  force: true,
                                                ),
                                            onResume: () =>
                                                coreNotifier.resumeDownload(
                                                  CoreType.singbox,
                                                ),
                                            onSetUrl: () =>
                                                _showCustomUrlDialog(
                                                  loc.translate('custom_url') +
                                                      ' Sing-box',
                                                  settings.singboxUrl,
                                                  (v) => update(
                                                    v,
                                                    (s, v) => s.copyWith(
                                                      singboxUrl: v,
                                                    ),
                                                  ),
                                                ),
                                            customUrl: settings.singboxUrl,
                                            loc: loc,
                                          ),
                                          const Divider(
                                            color: Colors.white10,
                                            height: 1,
                                          ),
                                          _buildCoreTileWithActions(
                                            title: 'AmneziaWG / WARP',
                                            customUrl: settings.awgUrl,
                                            loc: loc,
                                            status: coreStatus.awg,
                                            icon: Icons.shield_outlined,
                                            onDownload: () =>
                                                coreNotifier.downloadItem(
                                                  CoreType.awg,
                                                  force: true,
                                                ),
                                            onResume: () => coreNotifier
                                                .resumeDownload(CoreType.awg),
                                            onSetUrl: () =>
                                                _showCustomUrlDialog(
                                                  'URL ядра WG',
                                                  settings.awgUrl,
                                                  (v) => update(
                                                    v,
                                                    (s, v) => s.copyWith(
                                                      awgUrl: v.trim(),
                                                    ),
                                                  ),
                                                ),
                                          ),
                                          _buildCoreTileWithActions(
                                            title: 'Rule Files (DAT)',
                                            status: coreStatus.rules,
                                            icon: Icons.rule_rounded,
                                            onDownload: () =>
                                                coreNotifier.downloadItem(
                                                  CoreType.rules,
                                                  force: true,
                                                ),
                                            onResume: () => coreNotifier
                                                .resumeDownload(CoreType.rules),
                                            onSetUrl: () =>
                                                _showCustomUrlDialog(
                                                  loc.translate('custom_url') +
                                                      ' rules',
                                                  settings.rulesUrl,
                                                  (v) => update(
                                                    v,
                                                    (s, v) =>
                                                        s.copyWith(rulesUrl: v),
                                                  ),
                                                ),
                                            customUrl: settings.rulesUrl,
                                            loc: loc,
                                          ),
                                          const Divider(
                                            color: Colors.white10,
                                            height: 1,
                                          ),
                                          ThemeRegion.auto(
                                            id: "widget_settings_screen_38",
                                            label: "Row · settings_screen.dart",
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: _buildActionButton(
                                                    title: loc.translate(
                                                      'check_all',
                                                    ),
                                                    icon: Icons.sync_rounded,
                                                    onTap: () => coreNotifier
                                                        .checkForUpdates(),
                                                    isLoading: coreStatus
                                                        .isCheckingUpdates,
                                                  ),
                                                ),
                                                ThemeRegion.auto(
                                                  id: "widget_settings_screen_39",
                                                  label: "Container · settings_screen.dart",
                                                  child: Container(
                                                    width: 1,
                                                    height: 40,
                                                    color: Colors.white10,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: _buildActionButton(
                                                    title: loc.translate(
                                                      'download_all',
                                                    ),
                                                    icon: Icons
                                                        .cloud_download_rounded,
                                                    onTap: () => coreNotifier
                                                        .downloadAll(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Divider(
                                            color: Colors.white10,
                                            height: 1,
                                          ),
                                          _buildSwitchTile(
                                            title: AppLocalizations.text(
                                              context,
                                              'Автообновление ядер',
                                            ),
                                            subtitle: AppLocalizations.text(
                                              context,
                                              'При запуске проверять и устанавливать обновления. При работающем VPN установка откладывается.',
                                            ),
                                            icon:
                                                Icons.system_update_alt_rounded,
                                            value:
                                                settings.autoInstallCoreUpdates,
                                            onChanged: (value) => update(
                                              value,
                                              (current, next) =>
                                                  current.copyWith(
                                                    autoInstallCoreUpdates:
                                                        next,
                                                  ),
                                            ),
                                          ),
                                          _buildSwitchTile(
                                            title: AppLocalizations.text(
                                              context,
                                              "Автозагрузка ресурсов",
                                            ),
                                            subtitle: AppLocalizations.text(
                                              context,
                                              "Загружать отсутствующие ядра и файлы правил при запуске",
                                            ),
                                            icon: Icons
                                                .download_for_offline_rounded,
                                            value: settings.autoUpdateCores,
                                            onChanged: (value) => update(
                                              value,
                                              (current, next) =>
                                                  current.copyWith(
                                                    autoUpdateCores: next,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ).animate().fade(delay: 450.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('additional_settings'),
                              icon: Icons.settings_suggest_rounded,
                              children: [
                                InkWell(
                                  onTap: () async {
                                    try {
                                      await const MethodChannel(
                                        'pro.kaleert.nextlink/vpn',
                                      ).invokeMethod<void>(
                                        'openVpnSystemSettings',
                                      );
                                    } catch (error) {
                                      if (mounted) {
                                        CustomNotification.show(
                                          context,
                                          AppLocalizations.text(
                                            context,
                                            "Не удалось открыть настройки VPN: {0}",
                                            args: [error],
                                          ),
                                          isError: true,
                                        );
                                      }
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_settings_screen_40",
                                      label: "Row · settings_screen.dart",
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: ThemeRegion.auto(
                                              id: "widget_settings_screen_41",
                                              label:
                                                  "Text · settings_screen.dart",
                                              child: Text(
                                                AppLocalizations.text(
                                                  context,
                                                  "Kill Switch · открыть системные настройки VPN",
                                                ),
                                                style: TextStyle(
                                                  color: themeState
                                                      .currentTheme
                                                      .primary,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                          ThemeRegion.auto(
                                            id: "widget_settings_screen_42",
                                            label:
                                                "Icon · settings_screen.dart",
                                            child: Icon(
                                              Icons.open_in_new_rounded,
                                              color: themeState
                                                  .currentTheme
                                                  .primary,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const Divider(color: Colors.white10, height: 1),
                                _buildSwitchTile(
                                  title: AppLocalizations.text(
                                    context,
                                    "VPN при открытии приложения",
                                  ),
                                  subtitle: AppLocalizations.text(
                                    context,
                                    "Подключаться к выбранному серверу при запуске и возвращении в NextLink",
                                  ),
                                  icon: Icons.bolt_rounded,
                                  value: settings.connectOnStart,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(connectOnStart: v),
                                  ),
                                ),
                                _buildSwitchTile(
                                  title: AppLocalizations.text(
                                    context,
                                    "VPN после перезагрузки",
                                  ),
                                  subtitle: AppLocalizations.text(
                                    context,
                                    "Восстановить последнее подключение. Сначала подключитесь вручную один раз.",
                                  ),
                                  icon: Icons.power_settings_new_rounded,
                                  value: settings.autoStart,
                                  onChanged: (v) => update(
                                    v,
                                    (s, v) => s.copyWith(autoStart: v),
                                  ),
                                ),
                              ],
                            ).animate().fade(delay: 500.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: loc.translate('other'),
                              icon: Icons.more_horiz_rounded,
                              children: [
                                ThemeRegion.auto(
                                  id: "widget_settings_screen_43",
                                  label: "ListTile · settings_screen.dart",
                                  child: ListTile(
                                    leading: ThemeRegion.auto(
                                      id: "widget_settings_screen_44",
                                      label: "Icon · settings_screen.dart",
                                      child: const Icon(
                                        Icons.settings_backup_restore_rounded,
                                      ),
                                    ),
                                    title: ThemeRegion.auto(
                                      id: "widget_settings_screen_45",
                                      label: "Text · settings_screen.dart",
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Резервная копия",
                                        ),
                                      ),
                                    ),
                                    subtitle: ThemeRegion.auto(
                                      id: "widget_settings_screen_46",
                                      label: "Text · settings_screen.dart",
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Сохранение и восстановление конфигурации приложения",
                                        ),
                                      ),
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const BackupScreen(),
                                      ),
                                    ),
                                  ),
                                ),

                                _buildMenuTile(
                                  title: loc.translate('max_log_files'),
                                  subtitle:
                                      '${settings.maxLogFiles} ${loc.translate('files_unit')}',
                                  icon: Icons.folder_copy_outlined,
                                  onTap: () => _showInputDialog(
                                    loc.translate('max_log_files'),
                                    '${settings.maxLogFiles}',
                                    (value) {
                                      final limit =
                                          (int.tryParse(value) ??
                                                  settings.maxLogFiles)
                                              .clamp(5, 100);
                                      update(
                                        limit,
                                        (state, value) =>
                                            state.copyWith(maxLogFiles: value),
                                      );
                                      unawaited(
                                        LogFiles.configureRetention(
                                          maxFiles: limit,
                                          maxStorageMb:
                                              settings.maxLogStorageMb,
                                        ),
                                      );
                                    },
                                    isNumber: true,
                                  ),
                                ),
                                const Divider(color: Colors.white10, height: 1),
                                _buildMenuTile(
                                  title: loc.translate('max_log_storage'),
                                  subtitle: '${settings.maxLogStorageMb} MB',
                                  icon: Icons.storage_rounded,
                                  onTap: () => _showInputDialog(
                                    loc.translate('max_log_storage'),
                                    '${settings.maxLogStorageMb}',
                                    (value) {
                                      final limit =
                                          (int.tryParse(value) ??
                                                  settings.maxLogStorageMb)
                                              .clamp(10, 200);
                                      update(
                                        limit,
                                        (state, value) => state.copyWith(
                                          maxLogStorageMb: value,
                                        ),
                                      );
                                      unawaited(
                                        LogFiles.configureRetention(
                                          maxFiles: settings.maxLogFiles,
                                          maxStorageMb: limit,
                                        ),
                                      );
                                    },
                                    isNumber: true,
                                  ),
                                ),
                                const Divider(color: Colors.white10, height: 1),
                                _buildMenuTile(
                                  title: loc.translate('diagnostics'),
                                  subtitle: '',
                                  icon: Icons.terminal_rounded,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LogsScreen(),
                                    ),
                                  ),
                                ),
                                const Divider(color: Colors.white10, height: 1),
                                _buildMenuTile(
                                  title: loc.translate('share_logs'),
                                  subtitle: '',
                                  icon: Icons.ios_share_rounded,
                                  onTap: () async {
                                    if (!mounted) return;
                                    try {
                                      var files = await LogFiles.listFiles();
                                      if (files.isEmpty) {
                                        await ref
                                            .read(loggerProvider.notifier)
                                            .saveSnapshot(
                                              appLogsTitle: loc.translate(
                                                'app_logs',
                                              ),
                                              crashLogTitle: loc.translate(
                                                'crash_log',
                                              ),
                                              noCrashesText: loc.translate(
                                                'no_crashes_yet',
                                              ),
                                            );
                                        files = await LogFiles.listFiles();
                                      }
                                      final selected = files
                                          .where(
                                            (file) => !file.isManualSnapshot,
                                          )
                                          .toList();
                                      final snapshots = files
                                          .where(
                                            (file) => file.isManualSnapshot,
                                          )
                                          .toList();
                                      if (snapshots.isNotEmpty) {
                                        selected.add(snapshots.first);
                                      }
                                      await LogFiles.shareFiles(
                                        selected,
                                        chooserTitle: loc.translate(
                                          'share_logs',
                                        ),
                                      );
                                    } catch (error) {
                                      if (mounted) {
                                        CustomNotification.show(
                                          context,
                                          '${loc.translate('error')}: $error',
                                          isError: true,
                                        );
                                      }
                                    }
                                  },
                                ),
                                const Divider(color: Colors.white10, height: 1),
                                _buildMenuTile(
                                  title: loc.translate('reset_settings'),
                                  subtitle: '',
                                  icon: Icons.refresh_rounded,
                                  onTap: _confirmResetSettings,
                                  subtitleColor:
                                      themeState.currentTheme.primary,
                                ),
                              ],
                            ).animate().fade(delay: 550.ms).slideY(begin: 0.1),

                            _buildExpandableSection(
                              title: AppLocalizations.text(
                                context,
                                "Информация",
                              ),
                              icon: Icons.info_outline_rounded,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    20,
                                    8,
                                  ),
                                  child: Text(
                                    AppLocalizations.text(
                                      context,
                                      "NextLink — VPN-клиент для Android с поддержкой Xray, Sing-box и AmneziaWG. Подписки, цепочки серверов, правила приложений, диагностика и настраиваемые темы.",
                                    ),
                                    style: TextStyle(
                                      color: themeState.currentTheme.textDim,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: 'GitHub',
                                  subtitle: 'Kaleert/NextLink',
                                  icon: Icons.code_rounded,
                                  onTap: () => _openInfoUrl(
                                    'https://github.com/Kaleert/NextLink',
                                  ),
                                ),
                                _buildMenuTile(
                                  title: AppLocalizations.text(
                                    context,
                                    "Telegram разработчика",
                                  ),
                                  subtitle: '@wuzeru (Kaleert)',
                                  icon: Icons.send_rounded,
                                  onTap: () =>
                                      _openInfoUrl('https://t.me/wuzeru'),
                                ),
                                _buildMenuTile(
                                  title: AppLocalizations.text(
                                    context,
                                    "Сообщество NextLink",
                                  ),
                                  subtitle: '@nextlink_community',
                                  icon: Icons.forum_outlined,
                                  onTap: () => _openInfoUrl(
                                    'https://t.me/nextlink_community',
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    20,
                                    4,
                                  ),
                                  child: Text(
                                    AppLocalizations.text(
                                      context,
                                      'А также спасибо тем, кто помогал тестить клиент:',
                                    ),
                                    style: TextStyle(
                                      color: themeState.currentTheme.textDim,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                _buildMenuTile(
                                  title: '@artemkot4',
                                  subtitle: 'Telegram',
                                  icon: Icons.favorite_border_rounded,
                                  onTap: () =>
                                      _openInfoUrl('https://t.me/artemkot4'),
                                ),
                                _buildMenuTile(
                                  title: '@fnj42',
                                  subtitle: 'Telegram',
                                  icon: Icons.favorite_border_rounded,
                                  onTap: () =>
                                      _openInfoUrl('https://t.me/fnj42'),
                                ),
                                _buildMenuTile(
                                  title: '@Neonteen',
                                  subtitle: 'Telegram',
                                  icon: Icons.favorite_border_rounded,
                                  onTap: () =>
                                      _openInfoUrl('https://t.me/Neonteen'),
                                ),
                                _buildMenuTile(
                                  title: AppLocalizations.text(
                                    context,
                                    'Обучение по NextLink',
                                  ),
                                  subtitle: AppLocalizations.text(
                                    context,
                                    'Повторить короткое знакомство с клиентом',
                                  ),
                                  icon: Icons.school_outlined,
                                  onTap: () => ClientTour.show(context),
                                ),
                                _buildUrlSchemeList(),
                              ],
                            ).animate().fade(delay: 575.ms).slideY(begin: 0.1),

                            if (_showSecrets)
                              _buildExpandableSection(
                                title: loc.translate('developer_settings'),
                                icon: Icons.developer_mode_rounded,
                                initiallyExpanded: true,
                                children: [
                                  _buildMenuTile(
                                    title: AppLocalizations.text(
                                      context,
                                      'Force Stop Cores',
                                    ),
                                    subtitle: AppLocalizations.text(
                                      context,
                                      'Kill all native processes',
                                    ),
                                    icon: Icons.dangerous_rounded,
                                    onTap: () async {
                                      const platform = MethodChannel(
                                        'pro.kaleert.nextlink/vpn',
                                      );
                                      await platform.invokeMethod('stopVpn');
                                      await platform.invokeMethod(
                                        'stopTestCore',
                                      );
                                    },
                                  ),
                                  const Divider(
                                    color: Colors.white10,
                                    height: 1,
                                  ),
                                  _buildMenuTile(
                                    title: AppLocalizations.text(
                                      context,
                                      'Core Version Info',
                                    ),
                                    subtitle: AppLocalizations.text(
                                      context,
                                      'Check native binaries',
                                    ),
                                    icon: Icons.info_outline_rounded,
                                    onTap: () async {
                                      const platform = MethodChannel(
                                        'pro.kaleert.nextlink/vpn',
                                      );
                                      final version = await platform
                                          .invokeMethod('getCoreVersion');
                                      if (mounted) {
                                        showDialog(
                                          useRootNavigator: false,
                                          context: context,
                                          builder: (c) => GlassAlertDialog(
                                            surfaceColor:
                                                themeState.currentTheme.surface,
                                            title: ThemeRegion.auto(
                                              id: "widget_settings_screen_47",
                                              label:
                                                  "Text · settings_screen.dart",
                                              child: Text(
                                                AppLocalizations.text(
                                                  context,
                                                  'Versions',
                                                ),
                                              ),
                                            ),
                                            content: ThemeRegion.auto(
                                              id: "widget_settings_screen_48",
                                              label:
                                                  "Text · settings_screen.dart",
                                              child: Text(
                                                version ??
                                                    AppLocalizations.text(
                                                      context,
                                                      'Unknown',
                                                    ),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            actions: [
                                              ThemeRegion.auto(
                                                id: "widget_settings_screen_49",
                                                label: "TextButton · settings_screen.dart",
                                                child: TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c),
                                                  child: ThemeRegion.auto(
                                                    id: "widget_settings_screen_50",
                                                    label: "Text · settings_screen.dart",
                                                    child: const Text("OK"),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),

                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  _versionClickCount++;
                                  if (_versionClickCount == 7) {
                                    setState(() => _showSecrets = true);
                                    HapticFeedback.vibrate();
                                  }
                                },
                                child: Opacity(
                                  opacity: 0.3,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: ThemeRegion.auto(
                                      id: "widget_settings_screen_51",
                                      label: "Text · settings_screen.dart",
                                      child: Text(
                                        'NextLink v1.0.0-beta+4${_showSecrets ? loc.translate('developer_tag') : ""}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
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

  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    final themeState = ref.watch(themeProvider);
    return ThemeRegion.auto(
      id: "widget_settings_screen_52",
      label: "Container · settings_screen.dart",
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                initiallyExpanded: initiallyExpanded,
                leading: ThemeRegion.auto(
                  id: "widget_settings_screen_53",
                  label: "Icon · settings_screen.dart",
                  child: Icon(icon, color: themeState.currentTheme.primary),
                ),
                title: ThemeRegion.auto(
                  id: "widget_settings_screen_54",
                  label: "Text · settings_screen.dart",
                  child: Text(
                    AppLocalizations.text(context, title),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                iconColor: Colors.white,
                collapsedIconColor: Colors.white54,
                children: [
                  const Divider(color: Colors.white10, height: 1),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUrlSchemeList() {
    const schemes = <(String, String)>[
      ('nextlink://connect', 'Начать VPN-соединение'),
      ('nextlink://open', 'Алиас команды connect'),
      ('nextlink://disconnect', 'Остановить VPN-соединение'),
      ('nextlink://close', 'Алиас команды disconnect'),
      ('nextlink://toggle', 'Включить или выключить VPN'),
      (
        'nextlink://add?url={url-encoded}',
        'Добавить подписку по URL или одиночную конфигурацию',
      ),
      (
        'nextlink://import/{base64url}',
        'Импортировать base64url текст подписки или конфигурации',
      ),
      (
        'nextlink://profile/{id}',
        'Однократно применить действие профиля по его ID',
      ),
      (
        'nextlink://routing/add/{base64url-json}',
        'Импорт правил маршрутизации из JSON',
      ),
      (
        'nextlink://routing/onadd/{base64url-json}',
        'Импорт и применение правил маршрутизации из JSON',
      ),
    ];
    final accent = ref.watch(themeProvider).currentTheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: ThemeRegion.auto(
        id: "widget_settings_screen_55",
        label: "Column · settings_screen.dart",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: ThemeRegion.auto(
                id: "widget_settings_screen_56",
                label: "Text · settings_screen.dart",
                child: Text(
                  AppLocalizations.text(
                    context,
                    "Нажмите на схему, чтобы скопировать её. Команды можно открывать из ярлыков и приложений автоматизации.",
                  ),
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ),
            ...schemes.map(
              (entry) => InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: entry.$1));
                  if (mounted) {
                    CustomNotification.show(
                      context,
                      AppLocalizations.text(context, "Схема скопирована"),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 6,
                  ),
                  child: ThemeRegion.auto(
                    id: "widget_settings_screen_57",
                    label: "Row · settings_screen.dart",
                    child: Row(
                      children: [
                        Expanded(
                          child: ThemeRegion.auto(
                            id: "widget_settings_screen_58",
                            label: "Column · settings_screen.dart",
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ThemeRegion.auto(
                                  id: "widget_settings_screen_59",
                                  label: "Text · settings_screen.dart",
                                  child: Text(
                                    entry.$1,
                                    style: TextStyle(
                                      color: accent,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                ThemeRegion.auto(
                                  id: "widget_settings_screen_60",
                                  label: "Text · settings_screen.dart",
                                  child: Text(
                                    entry.$2,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ThemeRegion.auto(
                          id: "widget_settings_screen_61",
                          label: "Icon · settings_screen.dart",
                          child: const Icon(
                            Icons.copy_rounded,
                            color: Colors.white54,
                            size: 16,
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
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final themeState = ref.watch(themeProvider);
    return ThemeRegion(
      id: ThemeRegionRegistry.named(
        'settings_row',
        title,
        stableKey: AppLocalizations.of(context)?.keyFor(title),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ThemeRegion.auto(
          id: "widget_settings_screen_62",
          label: "Row · settings_screen.dart",
          child: Row(
            children: [
              ThemeRegion.auto(
                id: "widget_settings_screen_63",
                label: "Icon · settings_screen.dart",
                child: Icon(
                  icon,
                  color: themeState.currentTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ThemeRegion.auto(
                  id: "widget_settings_screen_64",
                  label: "Column · settings_screen.dart",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThemeRegion.auto(
                        id: "widget_settings_screen_65",
                        label: "Text · settings_screen.dart",
                        child: Text(
                          AppLocalizations.text(context, title),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        ThemeRegion.auto(
                          id: "widget_settings_screen_66",
                          label: "Text · settings_screen.dart",
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: themeState.currentTheme.textDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ThemeRegion.auto(
                id: "widget_settings_screen_67",
                label: "Switch · settings_screen.dart",
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeColor: themeState.currentTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color? subtitleColor,
  }) {
    final themeState = ref.watch(themeProvider);
    return ThemeRegion(
      id: ThemeRegionRegistry.named(
        'settings_row',
        title,
        stableKey: AppLocalizations.of(context)?.keyFor(title),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ThemeRegion.auto(
            id: "widget_settings_screen_68",
            label: "Row · settings_screen.dart",
            child: Row(
              children: [
                ThemeRegion.auto(
                  id: "widget_settings_screen_69",
                  label: "Icon · settings_screen.dart",
                  child: Icon(
                    icon,
                    color: themeState.currentTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ThemeRegion.auto(
                    id: "widget_settings_screen_70",
                    label: "Column · settings_screen.dart",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ThemeRegion.auto(
                          id: "widget_settings_screen_71",
                          label: "Text · settings_screen.dart",
                          child: Text(
                            AppLocalizations.text(context, title),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          ThemeRegion.auto(
                            id: "widget_settings_screen_72",
                            label: "Text · settings_screen.dart",
                            child: Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    subtitleColor ??
                                    themeState.currentTheme.textDim,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ThemeRegion.auto(
                  id: "widget_settings_screen_73",
                  label: "Icon · settings_screen.dart",
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: themeState.currentTheme.textDim,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoreTileWithActions({
    required String title,
    required CoreItemStatus status,
    required IconData icon,
    required VoidCallback onDownload,
    required VoidCallback onResume,
    required VoidCallback onSetUrl,
    required String customUrl,
    required AppLocalizations loc,
  }) {
    final themeState = ref.watch(themeProvider);
    final bool isReady = status.isDownloaded && status.version != 'N/A';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ThemeRegion.auto(
        id: "widget_settings_screen_74",
        label: "Column · settings_screen.dart",
        child: Column(
          children: [
            ThemeRegion.auto(
              id: "widget_settings_screen_75",
              label: "Row · settings_screen.dart",
              child: Row(
                children: [
                  ThemeRegion.auto(
                    id: "widget_settings_screen_76",
                    label: "Icon · settings_screen.dart",
                    child: Icon(
                      icon,
                      color: isReady
                          ? Colors.greenAccent
                          : themeState.currentTheme.textDim,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ThemeRegion.auto(
                      id: "widget_settings_screen_77",
                      label: "Column · settings_screen.dart",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ThemeRegion.auto(
                            id: "widget_settings_screen_78",
                            label: "Text · settings_screen.dart",
                            child: Text(
                              AppLocalizations.text(context, title),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ThemeRegion.auto(
                            id: "widget_settings_screen_79",
                            label: "Text · settings_screen.dart",
                            child: Text(
                              isReady
                                  ? '${loc.translate('version')}${status.version}'
                                  : (status.isDownloading
                                        ? loc.translate('downloading')
                                        : loc.translate('not_downloaded')),
                              style: TextStyle(
                                fontSize: 12,
                                color: isReady
                                    ? themeState.currentTheme.textDim
                                    : themeState.currentTheme.primary
                                          .withOpacity(0.5),
                              ),
                            ),
                          ),
                          if (status.isDownloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: ThemeRegion.auto(
                                id: "widget_settings_screen_80",
                                label: "Text · settings_screen.dart",
                                child: Text(
                                  status.formattedProgress,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: themeState.currentTheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          if (status.hasUpdate)
                            Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: ThemeRegion.auto(
                                id: "widget_settings_screen_81",
                                label: "Text · settings_screen.dart",
                                child: Text(
                                  AppLocalizations.text(
                                    context,
                                    "Доступно обновление",
                                  ),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orangeAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          if (status.isPaused)
                            Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: ThemeRegion.auto(
                                id: "widget_settings_screen_82",
                                label: "Text · settings_screen.dart",
                                child: Text(
                                  AppLocalizations.text(
                                    context,
                                    "Загрузка приостановлена",
                                  ),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                            ),
                          if (status.lastError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: ThemeRegion.auto(
                                id: "widget_settings_screen_83",
                                label: "Text · settings_screen.dart",
                                child: Text(
                                  status.lastError!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (isReady)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ThemeRegion.auto(
                        id: "widget_settings_screen_84",
                        label: "Icon · settings_screen.dart",
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                      ),
                    ),
                  if (status.hasUpdate)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ThemeRegion.auto(
                        id: "widget_settings_screen_85",
                        label: "Icon · settings_screen.dart",
                        child: Icon(
                          Icons.new_releases_rounded,
                          color: Colors.orangeAccent,
                          size: 18,
                        ),
                      ),
                    ),
                  ThemeRegion.auto(
                    id: "widget_settings_screen_86",
                    label: "IconButton · settings_screen.dart",
                    child: IconButton(
                      icon: ThemeRegion.auto(
                        id: "widget_settings_screen_87",
                        label: "Icon · settings_screen.dart",
                        child: Icon(
                          Icons.link_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: onSetUrl,
                      tooltip: loc.translate('custom_url'),
                    ),
                  ),
                  status.isDownloading
                      ? ThemeRegion.auto(
                          id: "widget_settings_screen_88",
                          label: "IconButton · settings_screen.dart",
                          child: IconButton(
                            tooltip: status.isPaused
                                ? AppLocalizations.text(
                                    context,
                                    "Продолжить загрузку",
                                  )
                                : AppLocalizations.text(context, "Загрузка"),
                            icon: ThemeRegion.auto(
                              id: "widget_settings_screen_89",
                              label: "Icon · settings_screen.dart",
                              child: Icon(
                                status.isPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.downloading_rounded,
                                color: themeState.currentTheme.primary,
                              ),
                            ),
                            onPressed: status.isPaused ? onResume : null,
                          ),
                        )
                      : ThemeRegion.auto(
                          id: "widget_settings_screen_90",
                          label: "IconButton · settings_screen.dart",
                          child: IconButton(
                            icon: ThemeRegion.auto(
                              id: "widget_settings_screen_91",
                              label: "Icon · settings_screen.dart",
                              child: Icon(
                                status.isDownloaded
                                    ? Icons.system_update_alt_rounded
                                    : Icons.download_rounded,
                                size: 22,
                                color: themeState.currentTheme.primary,
                              ),
                            ),
                            onPressed: () async {
                              if (status.isDownloaded) {
                                final confirmed = await showDialog<bool>(
                                  useRootNavigator: false,
                                  context: context,
                                  barrierColor: Colors.black.withOpacity(.16),
                                  builder: (dialogContext) => GlassAlertDialog(
                                    surfaceColor:
                                        themeState.currentTheme.surface,
                                    title: ThemeRegion.auto(
                                      id: "widget_settings_screen_92",
                                      label: "Text · settings_screen.dart",
                                      child: Text(
                                        status.hasUpdate
                                            ? AppLocalizations.text(
                                                context,
                                                "Установить обновление?",
                                              )
                                            : AppLocalizations.text(
                                                context,
                                                "Заменить ресурс?",
                                              ),
                                      ),
                                    ),
                                    content: ThemeRegion.auto(
                                      id: "widget_settings_screen_93",
                                      label: "Text · settings_screen.dart",
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Будет загружен и установлен файл {0}.",
                                          args: [title],
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      ThemeRegion.auto(
                                        id: "widget_settings_screen_94",
                                        label:
                                            "TextButton · settings_screen.dart",
                                        child: TextButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            false,
                                          ),
                                          child: ThemeRegion.auto(
                                            id: "widget_settings_screen_95",
                                            label:
                                                "Text · settings_screen.dart",
                                            child: Text(
                                              AppLocalizations.text(
                                                context,
                                                "Отмена",
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      ThemeRegion.auto(
                                        id: "widget_settings_screen_96",
                                        label:
                                            "TextButton · settings_screen.dart",
                                        child: TextButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            true,
                                          ),
                                          child: ThemeRegion.auto(
                                            id: "widget_settings_screen_97",
                                            label:
                                                "Text · settings_screen.dart",
                                            child: Text(
                                              AppLocalizations.text(
                                                context,
                                                "Продолжить",
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                              }
                              onDownload();
                            },
                          ),
                        ),
                ],
              ),
            ),
            if (status.isDownloading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AppProgressBar(value: status.downloadProgress),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ThemeRegion.auto(
          id: "widget_settings_screen_98",
          label: "Row · settings_screen.dart",
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              if (!isLoading)
                ThemeRegion.auto(
                  id: "widget_settings_screen_99",
                  label: "Icon · settings_screen.dart",
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
              const SizedBox(width: 10),
              ThemeRegion.auto(
                id: "widget_settings_screen_100",
                label: "Text · settings_screen.dart",
                child: Text(
                  AppLocalizations.text(context, title),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
