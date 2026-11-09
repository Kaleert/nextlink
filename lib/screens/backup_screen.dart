import '../core/localization/app_localizations.dart';
import '../shared/widgets/theme_region.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_backup.dart';
import '../core/providers/automation_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/subscription_provider.dart';
import '../core/providers/chains_provider.dart';
import '../core/providers/rules_provider.dart';
import '../core/providers/profiles_provider.dart';
import '../core/theme/theme_provider.dart';
import '../shared/widgets/custom_notification.dart';
import '../shared/widgets/glass_alert_dialog.dart';

class BackupScreen extends ConsumerStatefulWidget {
  final String? initialContents;
  const BackupScreen({super.key, this.initialContents});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  static const _files = MethodChannel('pro.kaleert.nextlink/theme_files');
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialContents != null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(true, contents: widget.initialContents);
      });
  }

  Future<void> _run(bool restore, {String? contents}) async {
    if (_busy) return;
    setState(() => _busy = true);
    AutomationSynchronizer? automation;
    try {
      if (!restore) {
        await ref.read(subscriptionProvider.notifier).ready;
        await ref.read(profilesProvider.notifier).ready;
        await ref.read(settingsProvider.notifier).ready;
        await ref.read(themeProvider.notifier).ensureLoaded();
        final content = await AppBackup.export();
        final saved = await _files.invokeMethod<bool>('saveBackupFile', {
          'name':
              'NextLink_${DateTime.now().toIso8601String().substring(0, 10)}.nlbackup.json',
          'contents': content,
        });
        if (saved == true && mounted)
          CustomNotification.show(
            context,
            AppLocalizations.text(context, "Резервная копия сохранена"),
          );
      } else {
        final text =
            contents ??
            (await _files.invokeMapMethod<String, dynamic>(
                  'pickBackupFile',
                ))?['contents']
                as String?;
        if (text == null || !mounted) return;
        final data = AppBackup.validate(text);
        final confirmed = await showDialog<bool>(
          useRootNavigator: false,
          context: context,
          builder: (ctx) => GlassAlertDialog(
            surfaceColor: ref.read(themeProvider).currentTheme.surface,
            title: ThemeRegion.auto(
              id: "widget_backup_screen_0",
              label: "Text · backup_screen.dart",
              child: Text(
                AppLocalizations.text(context, "Восстановить копию?"),
              ),
            ),
            content: ThemeRegion.auto(
              id: "widget_backup_screen_1",
              label: "Text · backup_screen.dart",
              child: Text(
                AppLocalizations.text(
                  context,
                  "Настройки будут заменены. Подписок: {0}, профилей: {1}, тем: {2}. Текущее VPN-подключение остановится.",
                  args: [
                    (data['subscriptions'] as List).length,
                    (data['profiles'] as List).length,
                    (data['themes'] as List).length,
                  ],
                ),
              ),
            ),
            actions: [
              ThemeRegion.auto(
                id: "widget_backup_screen_2",
                label: "TextButton · backup_screen.dart",
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: ThemeRegion.auto(
                    id: "widget_backup_screen_3",
                    label: "Text · backup_screen.dart",
                    child: Text(AppLocalizations.text(context, "Отмена")),
                  ),
                ),
              ),
              ThemeRegion.auto(
                id: "widget_backup_screen_4",
                label: "TextButton · backup_screen.dart",
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: ThemeRegion.auto(
                    id: "widget_backup_screen_5",
                    label: "Text · backup_screen.dart",
                    child: Text(AppLocalizations.text(context, "Восстановить")),
                  ),
                ),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final synchronizer = ref.read(automationSyncProvider);
        synchronizer.suspend();
        automation = synchronizer;
        await const MethodChannel('pro.kaleert.nextlink/vpn')
            .invokeMethod('stopAutomation');
        await const MethodChannel('pro.kaleert.nextlink/vpn')
            .invokeMethod('stopVpn');
        await AppBackup.restore(data);
        ref.invalidate(settingsProvider);
        ref.invalidate(subscriptionProvider);
        ref.invalidate(chainsProvider);
        ref.invalidate(rulesProvider);
        ref.invalidate(profilesProvider);
        ref.invalidate(themeProvider);
        if (mounted)
          CustomNotification.show(
            context,
            AppLocalizations.text(context, "Резервная копия восстановлена"),
          );
      }
    } catch (error) {
      if (mounted)
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Ошибка резервной копии: {0}",
            args: [error],
          ),
          isError: true,
        );
    } finally {
      automation?.resume();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: ThemeRegion.auto(
        id: "widget_backup_screen_6",
        label: "Text · backup_screen.dart",
        child: Text(AppLocalizations.text(context, "Резервная копия")),
      ),
    ),
    body: ThemeRegion(
      id: 'screen_backup',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ThemeRegion.auto(
            id: "widget_backup_screen_7",
            label: "Text · backup_screen.dart",
            child: Text(
              AppLocalizations.text(
                context,
                "Настройки, подписки, цепочки, правила, профили и темы сохраняются в одном JSON-файле. Файл содержит ссылки подписок и ключи подключений — храните его как конфигурацию VPN.",
              ),
            ),
          ),
          const SizedBox(height: 24),
          ThemeRegion.auto(
            id: "widget_backup_screen_8",
            label: "OutlinedButton · backup_screen.dart",
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(false),
              icon: ThemeRegion.auto(
                id: "widget_backup_screen_9",
                label: "Icon · backup_screen.dart",
                child: const Icon(Icons.save_alt),
              ),
              label: ThemeRegion.auto(
                id: "widget_backup_screen_10",
                label: "Text · backup_screen.dart",
                child: Text(AppLocalizations.text(context, "Сохранить копию")),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ThemeRegion.auto(
            id: "widget_backup_screen_11",
            label: "OutlinedButton · backup_screen.dart",
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(true),
              icon: ThemeRegion.auto(
                id: "widget_backup_screen_12",
                label: "Icon · backup_screen.dart",
                child: const Icon(Icons.restore),
              ),
              label: ThemeRegion.auto(
                id: "widget_backup_screen_13",
                label: "Text · backup_screen.dart",
                child: Text(
                  AppLocalizations.text(context, "Восстановить из файла"),
                ),
              ),
            ),
          ),
          if (_busy)
            Padding(
              padding: EdgeInsets.all(16),
              child: ThemeRegion.auto(
                id: "widget_backup_screen_14",
                label: "Text · backup_screen.dart",
                child: Text(
                  AppLocalizations.text(context, "Выполняется операция…"),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
