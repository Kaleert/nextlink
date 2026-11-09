import '../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/theme_config.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../shared/widgets/theme_region.dart';
import '../main.dart' show HomeScreen;
import 'apps_screen.dart';
import 'settings_screen.dart';
import 'subscriptions_screen.dart';
import 'statistics_screen.dart';
import 'profiles_screen.dart';
import 'rules_screen.dart';
import 'chains_screen.dart';
import 'logs_screen.dart';
import 'backup_screen.dart';
import 'automation_history_screen.dart';
import 'wireguard_editor_screen.dart';
import 'config_constructor_screen.dart';
import 'chain_editor_screen.dart';
import 'json_editor_screen.dart';

class ThemeScreenPreview extends StatelessWidget {
  final ThemeConfig theme;
  final String regionId;
  const ThemeScreenPreview({
    super.key,
    required this.theme,
    required this.regionId,
  });
  @override
  Widget build(BuildContext context) {
    final screen = themePreviewScreen(regionId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.text(context, "Предпросмотр · без действий"),
        ),
      ),
      body: ProviderScope(
        overrides: [
          themeProvider.overrideWith((ref) => ThemeNotifier.preview(theme)),
        ],
        child: Theme(
          data: AppTheme.buildTheme(theme),
          child: IgnorePointer(child: screen),
        ),
      ),
    );
  }
}

Widget themePreviewScreen(String regionId) => switch (regionId) {
  'screen_home' => const HomeScreen(preview: true),
  'screen_apps' => const AppsScreen(),
  'screen_settings' => const SettingsScreen(),
  'screen_subscriptions' => const SubscriptionsScreen(),
  'screen_statistics' => const StatisticsScreen(),
  'screen_profiles' => const ProfilesScreen(),
  'screen_rules' => const RulesScreen(),
  'screen_chains' => const ChainsScreen(),
  'screen_diagnostics' => const LogsScreen(),
  'screen_backup' => const BackupScreen(),
  'screen_history' => const AutomationHistoryScreen(),
  'screen_wg_editor' => const WireGuardEditorScreen(),
  'screen_config_editor' => const ConfigConstructorScreen(),
  'screen_chain_editor' => const ChainEditorScreen(),
  'screen_json_editor' => const JsonEditorScreen(
    initialJson: '{"log": {"level": "info"}}',
    serverName: 'Предпросмотр',
  ),
  _ => Builder(
    builder: (context) => Center(
      child: Text(
        AppLocalizations.text(
          context,
          "Предпросмотр {0} доступен после открытия конфигурации",
          args: [ThemeRegionRegistry.labelFor(regionId)],
        ),
      ),
    ),
  ),
};
