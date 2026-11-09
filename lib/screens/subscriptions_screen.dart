import 'qr_import_screen.dart';
import 'config_share_sheet.dart';
import '../core/utils/config_share_payload.dart';
import '../shared/widgets/theme_region.dart';

import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../shared/widgets/glass_dropdown.dart';
import '../shared/widgets/glass_alert_dialog.dart';
import '../core/theme/theme_provider.dart';
import 'config_constructor_screen.dart';
import '../core/models/proxies/proxy_parser.dart';
import '../core/models/proxies/proxy_config.dart';
import '../core/models/proxies/vless_config.dart';
import '../core/models/proxies/vmess_config.dart';
import '../core/models/proxies/trojan_config.dart';
import '../core/models/proxies/hy2_config.dart';
import '../core/models/proxies/ss_config.dart';
import '../core/models/proxies/custom_config.dart';
import '../core/models/proxies/wireguard_config.dart';
import 'wireguard_editor_screen.dart';
import '../core/models/subscription.dart';
import '../core/providers/subscription_provider.dart';
import '../core/providers/settings_provider.dart';
import 'json_editor_screen.dart';
import '../shared/widgets/custom_notification.dart';
import '../shared/widgets/app_progress_bar.dart';
import '../core/localization/app_localizations.dart';

import '../core/utils/ping_utils.dart';

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  final _subNameCtrl = TextEditingController();
  final _subUrlCtrl = TextEditingController();
  bool _isLoading = false;

  final Set<String> _syncingSubs = {};

  @override
  void dispose() {
    _subNameCtrl.dispose();
    _subUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pingServer(ProxyConfig server) async {
    HapticFeedback.lightImpact();
    final settings = ref.read(settingsProvider);
    setState(() => server.isPinging = true);
    final res = await PingUtils.pingServerEx(server, settings);
    ref.read(subscriptionProvider.notifier).refreshState();
    if (mounted) {
      setState(() {});
      if (!res.isSuccess && res.error != null) {
        CustomNotification.show(context, res.error!, isError: true);
      }
    }
  }

  Future<void> _pingAll(Subscription sub) async {
    HapticFeedback.mediumImpact();
    final settings = ref.read(settingsProvider);
    setState(() {
      for (var srv in sub.servers) {
        srv.isPinging = true;
      }
    });
    await PingUtils.pingAllEx(
      sub.servers,
      settings,
      onProgress: () {
        if (mounted) {
          ref.read(subscriptionProvider.notifier).refreshState();
          setState(() {});
        }
      },
    );
    if (mounted) {
      final failedCount = sub.servers
          .where((s) => s.ping < 0 && s.ping != -100)
          .length;
      if (failedCount > 0) {
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Ошибка пинга: недоступно {0} из {1} серверов",
            args: [failedCount, sub.servers.length],
          ),
          isError: true,
        );
      }
    }
  }

  String _getTransport(ProxyConfig config) {
    if (config is WireGuardConfig) return 'udp';
    if (config is CustomConfig) return 'RAW';
    if (config is VlessConfig) return config.network;
    if (config is VmessConfig) return config.network;
    if (config is TrojanConfig) return config.network;
    if (config is HysteriaConfig) return 'quic';
    if (config is ShadowsocksConfig) return 'tcp';
    return 'tcp';
  }

  void _showServerActionMenu(String subId, ProxyConfig server) {
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: ThemeRegion.auto(
            id: "widget_subscriptions_screen_0",
            label: "Container · subscriptions_screen.dart",
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surface.withOpacity(0.24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: ThemeRegion.auto(
                id: "widget_subscriptions_screen_1",
                label: "Column · subscriptions_screen.dart",
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemeRegion.auto(
                      id: "widget_subscriptions_screen_2",
                      label: "Container · subscriptions_screen.dart",
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
                    ThemeRegion.auto(
                      id: "widget_subscriptions_screen_3",
                      label: "Text · subscriptions_screen.dart",
                      child: Text(
                        server.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildAddOption(Icons.ios_share_rounded, 'Поделиться', () {
                      Navigator.pop(context);
                      showConfigShareSheet(
                        this.context,
                        ConfigSharePayload.server(server),
                      );
                    }),
                    const SizedBox(height: 8),
                    if (server is! CustomConfig)
                      _buildAddOption(
                        Icons.edit_rounded,
                        loc.translate('rename'),
                        () async {
                          Navigator.pop(context);
                          final updatedConfig = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => server is WireGuardConfig
                                  ? WireGuardEditorScreen(initialConfig: server)
                                  : ConfigConstructorScreen(
                                      initialConfig: server,
                                    ),
                            ),
                          );
                          if (updatedConfig != null &&
                              updatedConfig is ProxyConfig) {
                            ref
                                .read(subscriptionProvider.notifier)
                                .updateProxy(subId, server, updatedConfig);
                          }
                        },
                      ),
                    if (server is! CustomConfig) const SizedBox(height: 8),
                    _buildAddOption(
                      Icons.data_object_rounded,
                      loc.translate('raw_json_tag'),
                      () async {
                        Navigator.pop(context);
                        final initialJson =
                            server.rawJsonOverride ??
                            (server is CustomConfig
                                ? server.jsonString
                                : jsonEncode(server.toOutboundJson()));
                        final newJson = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => JsonEditorScreen(
                              initialJson: initialJson,
                              serverName: server.name,
                            ),
                          ),
                        );
                        if (newJson != null && newJson is String) {
                          ref
                              .read(subscriptionProvider.notifier)
                              .updateProxyJson(subId, server, newJson);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildAddOption(
                      Icons.delete_outline_rounded,
                      loc.translate('delete'),
                      () {
                        Navigator.pop(context);
                        ref
                            .read(subscriptionProvider.notifier)
                            .deleteProxy(subId, server);
                        CustomNotification.show(
                          this.context,
                          AppLocalizations.text(
                            context,
                            "Конфигурация удалена",
                          ),
                        );
                      },
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSubActionMenu(Subscription sub) {
    if (sub.id == 'manual') return;
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: ThemeRegion.auto(
            id: "widget_subscriptions_screen_4",
            label: "Container · subscriptions_screen.dart",
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surface.withOpacity(0.24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: ThemeRegion.auto(
                id: "widget_subscriptions_screen_5",
                label: "Column · subscriptions_screen.dart",
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemeRegion.auto(
                      id: "widget_subscriptions_screen_6",
                      label: "Container · subscriptions_screen.dart",
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
                    ThemeRegion.auto(
                      id: "widget_subscriptions_screen_7",
                      label: "Text · subscriptions_screen.dart",
                      child: Text(
                        sub.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildAddOption(Icons.ios_share_rounded, 'Поделиться', () {
                      Navigator.pop(context);
                      showConfigShareSheet(
                        this.context,
                        ConfigSharePayload.subscription(sub),
                      );
                    }),
                    const SizedBox(height: 8),
                    _buildAddOption(
                      Icons.link_rounded,
                      loc.translate('copy_subscription_link'),
                      () async {
                        await Clipboard.setData(ClipboardData(text: sub.url));
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (mounted) {
                          CustomNotification.show(
                            this.context,
                            loc.translate('subscription_link_copied'),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildAddOption(
                      Icons.sync_rounded,
                      loc.translate('force_update'),
                      () async {
                        Navigator.pop(context);
                        try {
                          await ref
                              .read(subscriptionProvider.notifier)
                              .updateSubscription(sub.id);
                        } catch (e) {
                          if (mounted)
                            CustomNotification.show(
                              context,
                              '${loc.translate('server_error')}$e',
                              isError: true,
                            );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildAddOption(
                      Icons.edit_rounded,
                      loc.translate('rename'),
                      () {
                        Navigator.pop(context);
                        final ctrl = TextEditingController(text: sub.name);
                        showDialog(
                          useRootNavigator: false,
                          context: context,
                          builder: (c) => GlassAlertDialog(
                            surfaceColor: theme.surface,
                            title: ThemeRegion.auto(
                              id: "widget_subscriptions_screen_8",
                              label: "Text · subscriptions_screen.dart",
                              child: Text(
                                loc.translate('rename'),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            content: ThemeRegion.auto(
                              id: "widget_subscriptions_screen_9",
                              label: "TextField · subscriptions_screen.dart",
                              child: TextField(
                                controller: ctrl,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            actions: [
                              ThemeRegion.auto(
                                id: "widget_subscriptions_screen_10",
                                label: "TextButton · subscriptions_screen.dart",
                                child: TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: ThemeRegion.auto(
                                    id: "widget_subscriptions_screen_11",
                                    label: "Text · subscriptions_screen.dart",
                                    child: Text(
                                      loc.translate('cancel'),
                                      style: TextStyle(color: theme.textDim),
                                    ),
                                  ),
                                ),
                              ),
                              ThemeRegion.auto(
                                id: "widget_subscriptions_screen_12",
                                label: "TextButton · subscriptions_screen.dart",
                                child: TextButton(
                                  onPressed: () {
                                    ref
                                        .read(subscriptionProvider.notifier)
                                        .renameSubscription(sub.id, ctrl.text);
                                    Navigator.pop(c);
                                  },
                                  child: ThemeRegion.auto(
                                    id: "widget_subscriptions_screen_13",
                                    label: "Text · subscriptions_screen.dart",
                                    child: Text(
                                      loc.translate('save'),
                                      style: TextStyle(color: theme.primary),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildAddOption(
                      Icons.delete_forever_rounded,
                      loc.translate('delete_sub'),
                      () {
                        Navigator.pop(context);
                        ref
                            .read(subscriptionProvider.notifier)
                            .removeSubscription(sub.id);
                        CustomNotification.show(
                          this.context,
                          AppLocalizations.text(context, "Подписка удалена"),
                        );
                      },
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSubscriptionInfo(Subscription sub) {
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    final fields = <String, String>{
      loc.translate('subscription_url'): sub.url,
      if (sub.metadata['profile-web-page-url']?.isNotEmpty == true)
        loc.translate('web_page_url'): sub.metadata['profile-web-page-url']!,
      if ((sub.metadata['support-url'] ?? sub.metadata['support_url'])
              ?.isNotEmpty ==
          true)
        loc.translate('support_url'):
            (sub.metadata['support-url'] ?? sub.metadata['support_url'])!,
      for (final entry in sub.metadata.entries)
        if (!{
          'profile-title',
          'profile-web-page-url',
          'support-url',
          'support_url',
          'url',
          'content-disposition',
        }.contains(entry.key))
          entry.key: entry.value,
      if (sub.metadata['url']?.isNotEmpty == true) 'URL': sub.metadata['url']!,
    };

    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        surfaceColor: theme.surface,
        title: ThemeRegion.auto(
          id: "widget_subscriptions_screen_14",
          label: "Text · subscriptions_screen.dart",
          child: Text(loc.translate('subscription_info')),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
          child: SingleChildScrollView(
            child: ThemeRegion.auto(
              id: "widget_subscriptions_screen_15",
              label: "Column · subscriptions_screen.dart",
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: fields.entries.map((entry) {
                  final uri = Uri.tryParse(entry.value);
                  final isUrl =
                      uri != null && uri.hasScheme && uri.host.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ThemeRegion.auto(
                      id: "widget_subscriptions_screen_16",
                      label: "Column · subscriptions_screen.dart",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ThemeRegion.auto(
                            id: "widget_subscriptions_screen_17",
                            label: "Text · subscriptions_screen.dart",
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                color: theme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          InkWell(
                            onTap: isUrl
                                ? () async {
                                    Navigator.pop(dialogContext);
                                    try {
                                      await const MethodChannel(
                                        'pro.kaleert.nextlink/vpn',
                                      ).invokeMethod<void>(
                                        'openExternalUrl',
                                        entry.value,
                                      );
                                    } catch (_) {
                                      await Clipboard.setData(
                                        ClipboardData(text: entry.value),
                                      );
                                    }
                                  }
                                : null,
                            child: SelectableText(
                              entry.value,
                              style: TextStyle(
                                color: isUrl ? theme.text : theme.textDim,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        actions: [
          ThemeRegion.auto(
            id: "widget_subscriptions_screen_18",
            label: "TextButton · subscriptions_screen.dart",
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: ThemeRegion.auto(
                id: "widget_subscriptions_screen_19",
                label: "Text · subscriptions_screen.dart",
                child: Text(
                  loc.translate('cancel'),
                  style: TextStyle(color: theme.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importConfigs(String text) async {
    if (!mounted) return;
    CustomNotification.show(
      context,
      AppLocalizations.text(context, "Импортирую конфигурации…"),
    );
    final configs = ProxyParser.parseSubscription(text);
    if (configs.isEmpty)
      throw const FormatException('В файле нет поддерживаемых конфигураций');
    final added = await ref
        .read(subscriptionProvider.notifier)
        .addManualConfigs(configs);
    if (!mounted) return;
    CustomNotification.show(
      context,
      added == 0
          ? AppLocalizations.text(context, "Эти конфигурации уже добавлены")
          : AppLocalizations.text(
              context,
              "Добавлено конфигураций: {0}",
              args: [added],
            ),
    );
    if (configs.any((c) => c.protocol == 'AMNEZIAWG')) {
      CustomNotification.show(
        context,
        AppLocalizations.text(
          context,
          "Импортировано: {0}. для AmneziaWG нужно загруженное ядро Amnezia Box.",
          args: [added],
        ),
      );
    }
  }

  void _showAddMenu() {
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    HapticFeedback.heavyImpact();
    showDialog(
      useRootNavigator: false,
      context: context,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (menuContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: ThemeRegion.auto(
              id: "widget_subscriptions_screen_20",
              label: "Container · subscriptions_screen.dart",
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.surface.withOpacity(0.24),
                ),
                child: ThemeRegion.auto(
                  id: "widget_subscriptions_screen_21",
                  label: "Column · subscriptions_screen.dart",
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemeRegion.auto(
                        id: "widget_subscriptions_screen_22",
                        label: "Text · subscriptions_screen.dart",
                        child: Text(
                          loc.translate('add'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildAddOption(
                        Icons.qr_code_scanner_rounded,
                        'Через QR-код',
                        () async {
                          Navigator.pop(menuContext);
                          final raw = await Navigator.push<String>(
                            this.context,
                            MaterialPageRoute(
                              builder: (_) => const QrImportScreen(),
                            ),
                          );
                          if (raw == null || !mounted) return;
                          try {
                            final text = ConfigSharePayload.decodeQr(raw);
                            final uri = Uri.tryParse(text);
                            if (uri != null &&
                                ['https', 'http'].contains(uri.scheme) &&
                                uri.host.isNotEmpty) {
                              CustomNotification.show(
                                this.context,
                                AppLocalizations.text(
                                  context,
                                  "Добавляю подписку…",
                                ),
                              );
                              await ref
                                  .read(subscriptionProvider.notifier)
                                  .addSubscription('', text);
                              if (mounted)
                                CustomNotification.show(
                                  this.context,
                                  AppLocalizations.text(
                                    context,
                                    "Подписка добавлена",
                                  ),
                                );
                            } else {
                              await _importConfigs(text);
                            }
                          } catch (error) {
                            if (mounted)
                              CustomNotification.show(
                                this.context,
                                AppLocalizations.text(
                                  context,
                                  "Не удалось импортировать QR: {0}",
                                  args: [error],
                                ),
                                isError: true,
                              );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildAddOption(
                        Icons.paste_rounded,
                        loc.translate('from_clipboard'),
                        () async {
                          HapticFeedback.lightImpact();
                          Navigator.pop(menuContext);
                          final clipboardData = await Clipboard.getData(
                            'text/plain',
                          );
                          final text = clipboardData?.text?.trim() ?? '';
                          if (!mounted) return;
                          if (text.isEmpty) {
                            CustomNotification.show(
                              context,
                              loc.translate('clipboard_empty'),
                              isError: true,
                            );
                            return;
                          }
                          if (text.startsWith('http://') ||
                              text.startsWith('https://')) {
                            try {
                              CustomNotification.show(
                                context,
                                AppLocalizations.text(
                                  context,
                                  "Добавляю подписку…",
                                ),
                              );
                              final name = await ref
                                  .read(subscriptionProvider.notifier)
                                  .addSubscription('', text);
                              if (mounted)
                                CustomNotification.show(
                                  context,
                                  AppLocalizations.text(
                                    context,
                                    "Подписка «{0}» добавлена",
                                    args: [name],
                                  ),
                                );
                            } catch (e) {
                              if (mounted)
                                CustomNotification.show(
                                  context,
                                  '${loc.translate('server_error')}$e',
                                  isError: true,
                                );
                            }
                            return;
                          }
                          try {
                            await _importConfigs(text);
                          } catch (e) {
                            CustomNotification.show(
                              context,
                              '${loc.translate('parse_error').replaceFirst('$e', '')}$e',
                              isError: true,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildAddOption(
                        Icons.vpn_key_rounded,
                        'WireGuard / WARP / AmneziaWG',
                        () async {
                          Navigator.pop(menuContext);
                          final config = await Navigator.push<WireGuardConfig>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WireGuardEditorScreen(),
                            ),
                          );
                          if (config != null && mounted) {
                            await ref
                                .read(subscriptionProvider.notifier)
                                .addSingleProxy(config);
                            if (mounted)
                              CustomNotification.show(
                                context,
                                AppLocalizations.text(
                                  context,
                                  "Конфигурация добавлена",
                                ),
                              );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildAddOption(
                        Icons.file_open_rounded,
                        'Импорт .conf / .json (WireGuard, WARP, AmneziaWG)',
                        () async {
                          Navigator.pop(menuContext);
                          try {
                            final file =
                                await const MethodChannel(
                                  'pro.kaleert.nextlink/theme_files',
                                ).invokeMapMethod<String, dynamic>(
                                  'pickConfigFile',
                                );
                            if (file == null || !mounted) return;
                            await _importConfigs(file['contents'] as String);
                          } catch (error) {
                            if (mounted)
                              CustomNotification.show(
                                context,
                                AppLocalizations.text(
                                  context,
                                  "Ошибка импорта: {0}",
                                  args: [error],
                                ),
                                isError: true,
                              );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildAddOption(
                        Icons.link_rounded,
                        loc.translate('download_by_url'),
                        () {
                          Navigator.pop(menuContext);
                          _showUrlDownloadMenu();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildAddOption(
                        Icons.build_rounded,
                        loc.translate('manual_constructor'),
                        () async {
                          Navigator.pop(menuContext);
                          final newConfig = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ConfigConstructorScreen(),
                            ),
                          );
                          if (newConfig != null && newConfig is ProxyConfig) {
                            ref
                                .read(subscriptionProvider.notifier)
                                .addSingleProxy(newConfig);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms),
    );
  }

  Widget _buildAddOption(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color color = Colors.white,
  }) {
    final theme = ref.watch(themeProvider).currentTheme;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: ThemeRegion.auto(
          id: "widget_subscriptions_screen_23",
          label: "Row · subscriptions_screen.dart",
          child: Row(
            children: [
              ThemeRegion.auto(
                id: "widget_subscriptions_screen_24",
                label: "Icon · subscriptions_screen.dart",
                child: Icon(
                  icon,
                  color: color == Colors.white ? theme.primary : color,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ThemeRegion.auto(
                  id: "widget_subscriptions_screen_25",
                  label: "Text · subscriptions_screen.dart",
                  child: Text(
                    AppLocalizations.text(context, title),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ThemeRegion.auto(
                id: "widget_subscriptions_screen_26",
                label: "Icon · subscriptions_screen.dart",
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: color == Colors.white
                      ? theme.textDim
                      : color.withOpacity(0.8),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUrlDownloadMenu() {
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    HapticFeedback.lightImpact();
    _subNameCtrl.clear();
    _subUrlCtrl.clear();
    var tlsFingerprint = 'chrome';
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
                top: Radius.circular(32),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: ThemeRegion.auto(
                  id: "widget_subscriptions_screen_27",
                  label: "Container · subscriptions_screen.dart",
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.surface.withOpacity(0.26),
                      border: Border.all(color: theme.primary.withOpacity(0.2)),
                    ),
                    child: ThemeRegion.auto(
                      id: "widget_subscriptions_screen_28",
                      label: "Column · subscriptions_screen.dart",
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: ThemeRegion.auto(
                              id: "widget_subscriptions_screen_29",
                              label: "Container · subscriptions_screen.dart",
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
                          const SizedBox(height: 24),
                          ThemeRegion.auto(
                            id: "widget_subscriptions_screen_30",
                            label: "Text · subscriptions_screen.dart",
                            child: Text(
                              loc.translate('download_by_url'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ThemeRegion.auto(
                            id: "widget_subscriptions_screen_31",
                            label: "Container · subscriptions_screen.dart",
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ThemeRegion.auto(
                                id: "widget_subscriptions_screen_32",
                                label: "TextField · subscriptions_screen.dart",
                                child: TextField(
                                  controller: _subNameCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: loc.translate('sub_name_hint'),
                                    border: InputBorder.none,
                                    hintStyle: const TextStyle(
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ThemeRegion.auto(
                            id: "widget_subscriptions_screen_33",
                            label: "Container · subscriptions_screen.dart",
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ThemeRegion.auto(
                                id: "widget_subscriptions_screen_34",
                                label: "TextField · subscriptions_screen.dart",
                                child: TextField(
                                  controller: _subUrlCtrl,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                  ),
                                  decoration: InputDecoration(
                                    hintText: loc.translate('sub_url_hint'),
                                    border: InputBorder.none,
                                    hintStyle: const TextStyle(
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ThemeRegion.auto(
                            id: "widget_subscriptions_screen_35",
                            label: "Container · subscriptions_screen.dart",
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ThemeRegion.auto(
                                id: "widget_subscriptions_screen_36",
                                label: "Row · subscriptions_screen.dart",
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ThemeRegion.auto(
                                        id: "widget_subscriptions_screen_37",
                                        label:
                                            "Text · subscriptions_screen.dart",
                                        child: Text(
                                          loc.translate('tls_fingerprint'),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GlassDropdown<String>(
                                      value: tlsFingerprint,
                                      surfaceColor: theme.surface,
                                      accentColor: theme.primary,
                                      items:
                                          [
                                                'chrome',
                                                'firefox',
                                                'ios',
                                                'edge',
                                                'safari',
                                                'random',
                                              ]
                                              .map(
                                                (e) => DropdownMenuItem(
                                                  value: e,
                                                  child: ThemeRegion.auto(
                                                    id: "widget_subscriptions_screen_38",
                                                    label: "Text · subscriptions_screen.dart",
                                                    child: Text(
                                                      e,
                                                      style: TextStyle(
                                                        color: theme.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (value) {
                                        if (value != null)
                                          setModalState(
                                            () => tlsFingerprint = value,
                                          );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          GestureDetector(
                            onTap: () async {
                              if (_isLoading || _subUrlCtrl.text.trim().isEmpty)
                                return;
                              setModalState(() => _isLoading = true);
                              HapticFeedback.mediumImpact();
                              CustomNotification.show(
                                this.context,
                                AppLocalizations.text(
                                  context,
                                  "Добавляю подписку…",
                                ),
                              );
                              try {
                                final addedName = await ref
                                    .read(subscriptionProvider.notifier)
                                    .addSubscription(
                                      _subNameCtrl.text,
                                      _subUrlCtrl.text,
                                      tlsFingerprint: tlsFingerprint,
                                    );
                                if (mounted && context.mounted) {
                                  setModalState(() => _isLoading = false);
                                  Navigator.pop(context);
                                  CustomNotification.show(
                                    this.context,
                                    AppLocalizations.text(
                                      context,
                                      "Подписка «{0}» добавлена",
                                      args: [addedName],
                                    ),
                                  );
                                }
                              } catch (e) {
                                CustomNotification.show(
                                  this.context,
                                  e.toString(),
                                  isError: true,
                                );
                              } finally {
                                if (mounted && context.mounted)
                                  setModalState(() => _isLoading = false);
                              }
                            },
                            child: ThemeRegion.auto(
                              id: "widget_subscriptions_screen_39",
                              label: "Container · subscriptions_screen.dart",
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
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : ThemeRegion.auto(
                                          id: "widget_subscriptions_screen_40",
                                          label: "Text · subscriptions_screen.dart",
                                          child: Text(
                                            loc.translate('download'),
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

  @override
  Widget build(BuildContext context) {
    final subscriptions = ref.watch(subscriptionProvider);
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final visibleSubscriptions = subscriptions.where((sub) {
      if (sub.id == 'manual' && sub.servers.isEmpty) return false;
      return true;
    }).toList();
    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_subscriptions',
        child: ThemeRegion.auto(
          id: "widget_subscriptions_screen_41",
          label: "Stack · subscriptions_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: -100,
                right: -100,
                child: ThemeRegion.auto(
                  id: "widget_subscriptions_screen_42",
                  label: "Container · subscriptions_screen.dart",
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
                  id: "widget_subscriptions_screen_43",
                  label: "Container · subscriptions_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ThemeRegion.auto(
                      id: "widget_subscriptions_screen_44",
                      label: "Column · subscriptions_screen.dart",
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                            child: ThemeRegion.auto(
                              id: "widget_subscriptions_screen_45",
                              label: "Row · subscriptions_screen.dart",
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
                                      id: "widget_subscriptions_screen_46",
                                      label: "Container · subscriptions_screen.dart",
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
                                          id: "widget_subscriptions_screen_47",
                                          label: "Icon · subscriptions_screen.dart",
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
                                    id: "widget_subscriptions_screen_48",
                                    label: "Text · subscriptions_screen.dart",
                                    child: Text(
                                      loc.translate('subscriptions'),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _showAddMenu,
                                    child: ThemeRegion.auto(
                                      id: "widget_subscriptions_screen_49",
                                      label: "Container · subscriptions_screen.dart",
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.primary.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: theme.primary.withOpacity(
                                              0.5,
                                            ),
                                          ),
                                        ),
                                        child: ThemeRegion.auto(
                                          id: "widget_subscriptions_screen_50",
                                          label: "Icon · subscriptions_screen.dart",
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
                          Expanded(
                            child: visibleSubscriptions.isEmpty
                                ? Center(
                                    child: ThemeRegion.auto(
                                      id: "widget_subscriptions_screen_51",
                                      label:
                                          "Column · subscriptions_screen.dart",
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          ThemeRegion.auto(
                                            id: "widget_subscriptions_screen_52",
                                            label: "Icon · subscriptions_screen.dart",
                                            child: Icon(
                                              Icons.cloud_off_rounded,
                                              size: 64,
                                              color: theme.textDim.withOpacity(
                                                0.3,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          ThemeRegion.auto(
                                            id: "widget_subscriptions_screen_53",
                                            label: "Text · subscriptions_screen.dart",
                                            child: Text(
                                              loc.translate('no_subs'),
                                              style: TextStyle(
                                                color: theme.textDim,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 10,
                                    ),
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: visibleSubscriptions.length,
                                    itemBuilder: (context, index) {
                                      final sub = visibleSubscriptions[index];
                                      final isManualGroup = sub.id == 'manual';
                                      final settings = ref.watch(
                                        settingsProvider,
                                      );
                                      final sortedServers =
                                          List<ProxyConfig>.from(sub.servers);
                                      if (settings.subSortMode ==
                                          'По алфавиту') {
                                        sortedServers.sort(
                                          (a, b) => a.name
                                              .toLowerCase()
                                              .compareTo(b.name.toLowerCase()),
                                        );
                                      } else if (settings.subSortMode ==
                                          'По пингу') {
                                        sortedServers.sort((a, b) {
                                          if (a.ping <= 0 && b.ping <= 0)
                                            return 0;
                                          if (a.ping <= 0) return 1;
                                          if (b.ping <= 0) return -1;
                                          return a.ping.compareTo(b.ping);
                                        });
                                      }
                                      return ThemeRegion.auto(
                                        id: "widget_subscriptions_screen_54",
                                        label: "Container · subscriptions_screen.dart",
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.surface.withOpacity(
                                              0.34,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: Theme(
                                              data: Theme.of(context).copyWith(
                                                dividerColor:
                                                    Colors.transparent,
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: ExpansionTile(
                                                  initiallyExpanded:
                                                      !settings.collapseSubs,
                                                  tilePadding: EdgeInsets.zero,
                                                  title: GestureDetector(
                                                    onLongPress: () =>
                                                        _showSubActionMenu(sub),
                                                    child: ThemeRegion.auto(
                                                      id: "widget_subscriptions_screen_55",
                                                      label: "Container · subscriptions_screen.dart",
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: theme.surface
                                                              .withOpacity(0.5),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                        child: ThemeRegion.auto(
                                                          id: "widget_subscriptions_screen_56",
                                                          label: "Column · subscriptions_screen.dart",
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              ThemeRegion.auto(
                                                                id: "widget_subscriptions_screen_57",
                                                                label: "Row · subscriptions_screen.dart",
                                                                child: Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .spaceBetween,
                                                                  children: [
                                                                    Expanded(
                                                                      child: ThemeRegion.auto(
                                                                        id: "widget_subscriptions_screen_58",
                                                                        label: "Row · subscriptions_screen.dart",
                                                                        child: Row(
                                                                          children: [
                                                                            ThemeRegion.auto(
                                                                              id: "widget_subscriptions_screen_59",
                                                                              label: "Container · subscriptions_screen.dart",
                                                                              child: Container(
                                                                                padding: const EdgeInsets.all(6),
                                                                                decoration: BoxDecoration(
                                                                                  color: isManualGroup
                                                                                      ? Colors.blueAccent.withOpacity(0.2)
                                                                                      : theme.primary.withOpacity(0.2),
                                                                                  borderRadius: BorderRadius.circular(12),
                                                                                ),
                                                                                child: ThemeRegion.auto(
                                                                                  id: "widget_subscriptions_screen_60",
                                                                                  label: "Icon · subscriptions_screen.dart",
                                                                                  child: Icon(
                                                                                    isManualGroup ? Icons.build_rounded : Icons.cloud_sync_rounded,
                                                                                    color: isManualGroup ? Colors.blueAccent : theme.primary,
                                                                                    size: 18,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(
                                                                              width: 8,
                                                                            ),
                                                                            Expanded(
                                                                              child: ThemeRegion.auto(
                                                                                id: "widget_subscriptions_screen_61",
                                                                                label: "Column · subscriptions_screen.dart",
                                                                                child: Column(
                                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                                  children: [
                                                                                    ThemeRegion.auto(
                                                                                      id: "widget_subscriptions_screen_62",
                                                                                      label: "Text · subscriptions_screen.dart",
                                                                                      child: Text(
                                                                                        '${sub.name} (${sub.servers.length})',
                                                                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                                                                      ),
                                                                                    ),
                                                                                    if (sub.formattedUpdatedTime.isNotEmpty)
                                                                                      ThemeRegion.auto(
                                                                                        id: "widget_subscriptions_screen_63",
                                                                                        label: "Text · subscriptions_screen.dart",
                                                                                        child: Text(sub.formattedUpdatedTime, style: TextStyle(fontSize: 11, color: theme.textDim)),
                                                                                      ),
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    if (!isManualGroup)
                                                                      ThemeRegion.auto(
                                                                        id: "widget_subscriptions_screen_64",
                                                                        label: "Row · subscriptions_screen.dart",
                                                                        child: Row(
                                                                          children: [
                                                                            ThemeRegion.auto(
                                                                              id: "widget_subscriptions_screen_65",
                                                                              label: "IconButton · subscriptions_screen.dart",
                                                                              child: IconButton(
                                                                                visualDensity: VisualDensity.compact,
                                                                                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                                                                                padding: EdgeInsets.zero,
                                                                                iconSize: 18,
                                                                                tooltip: loc.translate(
                                                                                  'subscription_info',
                                                                                ),
                                                                                icon: ThemeRegion.auto(
                                                                                  id: "widget_subscriptions_screen_66",
                                                                                  label: "Icon · subscriptions_screen.dart",
                                                                                  child: Icon(Icons.info_outline_rounded, color: theme.textDim),
                                                                                ),
                                                                                onPressed: () => _showSubscriptionInfo(sub),
                                                                              ),
                                                                            ),
                                                                            StatefulBuilder(
                                                                              builder: (context, setState) {
                                                                                final isSyncing = _syncingSubs.contains(sub.id);
                                                                                return ThemeRegion.auto(
                                                                                  id: "widget_subscriptions_screen_67",
                                                                                  label: "IconButton · subscriptions_screen.dart",
                                                                                  child: IconButton(
                                                                                    visualDensity: VisualDensity.compact,
                                                                                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                                                                                    padding: EdgeInsets.zero,
                                                                                    iconSize: 18,
                                                                                    icon: isSyncing
                                                                                        ? SizedBox(
                                                                                            width: 18,
                                                                                            height: 18,
                                                                                            child: CircularProgressIndicator(color: theme.primary, strokeWidth: 2),
                                                                                          )
                                                                                        : ThemeRegion.auto(
                                                                                            id: "widget_subscriptions_screen_68",
                                                                                            label: "Icon · subscriptions_screen.dart",
                                                                                            child: Icon(Icons.sync_rounded, color: theme.textDim),
                                                                                          ),
                                                                                    onPressed: () async {
                                                                                      if (isSyncing) return;
                                                                                      HapticFeedback.lightImpact();
                                                                                      setState(() => _syncingSubs.add(sub.id));
                                                                                      CustomNotification.show(this.context, AppLocalizations.text(context, "Обновляю подписку…"));
                                                                                      try {
                                                                                        await ref.read(subscriptionProvider.notifier).updateSubscription(sub.id);
                                                                                        if (mounted) CustomNotification.show(context, loc.translate('updated'));
                                                                                      } catch (e) {
                                                                                        if (mounted) CustomNotification.show(context, '${loc.translate('error')}$e', isError: true);
                                                                                      } finally {
                                                                                        if (mounted) setState(() => _syncingSubs.remove(sub.id));
                                                                                      }
                                                                                    },
                                                                                  ),
                                                                                );
                                                                              },
                                                                            ),
                                                                            ThemeRegion.auto(
                                                                              id: "widget_subscriptions_screen_69",
                                                                              label: "IconButton · subscriptions_screen.dart",
                                                                              child: IconButton(
                                                                                visualDensity: VisualDensity.compact,
                                                                                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                                                                                padding: EdgeInsets.zero,
                                                                                iconSize: 18,
                                                                                icon: ThemeRegion.auto(
                                                                                  id: "widget_subscriptions_screen_70",
                                                                                  label: "Icon · subscriptions_screen.dart",
                                                                                  child: Icon(Icons.network_ping_rounded, color: theme.textDim),
                                                                                ),
                                                                                onPressed: () => _pingAll(sub),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                  ],
                                                                ),
                                                              ),
                                                              if (sub
                                                                  .announcement
                                                                  .isNotEmpty) ...[
                                                                const SizedBox(
                                                                  height: 8,
                                                                ),
                                                                ThemeRegion.auto(
                                                                  id: "widget_subscriptions_screen_71",
                                                                  label: "Container · subscriptions_screen.dart",
                                                                  child: Container(
                                                                    width: double
                                                                        .infinity,
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          10,
                                                                      vertical:
                                                                          8,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: theme
                                                                          .primary
                                                                          .withOpacity(
                                                                            0.07,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                    ),
                                                                    child: ThemeRegion.auto(
                                                                      id: "widget_subscriptions_screen_72",
                                                                      label: "Row · subscriptions_screen.dart",
                                                                      child: Row(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        children: [
                                                                          Padding(
                                                                            padding: const EdgeInsets.only(
                                                                              top: 1,
                                                                            ),
                                                                            child: ThemeRegion.auto(
                                                                              id: "widget_subscriptions_screen_73",
                                                                              label: "Icon · subscriptions_screen.dart",
                                                                              child: Icon(
                                                                                Icons.campaign_outlined,
                                                                                size: 16,
                                                                                color: theme.primary,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child: SelectableText(
                                                                              sub.announcement,
                                                                              style: TextStyle(
                                                                                color: theme.textDim,
                                                                                fontSize: 11,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                              if (!isManualGroup) ...[
                                                                const SizedBox(
                                                                  height: 12,
                                                                ),
                                                                ThemeRegion.auto(
                                                                  id: "widget_subscriptions_screen_74",
                                                                  label: "Row · subscriptions_screen.dart",
                                                                  child: Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceBetween,
                                                                    children: [
                                                                      ThemeRegion.auto(
                                                                        id: "widget_subscriptions_screen_75",
                                                                        label: "Text · subscriptions_screen.dart",
                                                                        child: Text(
                                                                          loc.translate(
                                                                            'traffic',
                                                                          ),
                                                                          style: TextStyle(
                                                                            color:
                                                                                theme.textDim,
                                                                            fontSize:
                                                                                13,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      ThemeRegion.auto(
                                                                        id: "widget_subscriptions_screen_76",
                                                                        label: "Text · subscriptions_screen.dart",
                                                                        child: Text(
                                                                          sub.total == 0
                                                                              ? loc.translate(
                                                                                  'unlimited',
                                                                                )
                                                                              : '${sub.usedGB.toStringAsFixed(2)} GB / ${sub.totalGB.toStringAsFixed(2)} GB',
                                                                          style: TextStyle(
                                                                            color: Colors.white.withOpacity(
                                                                              0.9,
                                                                            ),
                                                                            fontSize:
                                                                                13,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  height: 8,
                                                                ),
                                                                ClipRRect(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        10,
                                                                      ),
                                                                  child: AppProgressBar(
                                                                    value:
                                                                        sub.total ==
                                                                            0
                                                                        ? 1
                                                                        : (sub.upload + sub.download) /
                                                                              sub.total,
                                                                    color:
                                                                        sub.total ==
                                                                            0
                                                                        ? Colors
                                                                              .greenAccent
                                                                        : theme
                                                                              .primary,
                                                                  ),
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            10,
                                                            0,
                                                            10,
                                                            10,
                                                          ),
                                                      child: ThemeRegion.auto(
                                                        id: "widget_subscriptions_screen_77",
                                                        label: "Column · subscriptions_screen.dart",
                                                        child: Column(
                                                          children: sortedServers.map((
                                                            server,
                                                          ) {
                                                            final pingColor =
                                                                server.ping < 0
                                                                ? theme.textDim
                                                                : (server.ping <
                                                                          100
                                                                      ? Colors
                                                                            .greenAccent
                                                                      : (server.ping <
                                                                                200
                                                                            ? Colors.orangeAccent
                                                                            : theme.primary));
                                                            final jsonTag =
                                                                (server.rawJsonOverride !=
                                                                        null ||
                                                                    server
                                                                        is CustomConfig)
                                                                ? loc.translate(
                                                                    'raw_json_tag',
                                                                  )
                                                                : '';
                                                            return GestureDetector(
                                                              onTap: () {
                                                                HapticFeedback.lightImpact();
                                                                ref
                                                                    .read(
                                                                      subscriptionProvider
                                                                          .notifier,
                                                                    )
                                                                    .setActiveServer(
                                                                      sub.id,
                                                                      server,
                                                                    );
                                                              },
                                                              onLongPress: () =>
                                                                  _showServerActionMenu(
                                                                    sub.id,
                                                                    server,
                                                                  ),
                                                              child: AnimatedContainer(
                                                                duration:
                                                                    const Duration(
                                                                      milliseconds:
                                                                          300,
                                                                    ),
                                                                margin:
                                                                    const EdgeInsets.only(
                                                                      bottom: 8,
                                                                    ),
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          9,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      server
                                                                          .isActive
                                                                      ? theme
                                                                            .primary
                                                                            .withOpacity(
                                                                              0.12,
                                                                            )
                                                                      : theme
                                                                            .surface
                                                                            .withOpacity(
                                                                              0.3,
                                                                            ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        14,
                                                                      ),
                                                                  border: Border.all(
                                                                    color:
                                                                        server
                                                                            .isActive
                                                                        ? theme.primary.withOpacity(
                                                                            0.4,
                                                                          )
                                                                        : Colors.white.withOpacity(
                                                                            0.04,
                                                                          ),
                                                                    width:
                                                                        server
                                                                            .isActive
                                                                        ? 1.5
                                                                        : 1,
                                                                  ),
                                                                ),
                                                                child: ThemeRegion.auto(
                                                                  id: "widget_subscriptions_screen_78",
                                                                  label: "Row · subscriptions_screen.dart",
                                                                  child: Row(
                                                                    children: [
                                                                      ThemeRegion.auto(
                                                                        id: "widget_subscriptions_screen_79",
                                                                        label: "Container · subscriptions_screen.dart",
                                                                        child: Container(
                                                                          width:
                                                                              36,
                                                                          height:
                                                                              36,
                                                                          decoration: BoxDecoration(
                                                                            color:
                                                                                Colors.black26,
                                                                            borderRadius: BorderRadius.circular(
                                                                              10,
                                                                            ),
                                                                          ),
                                                                          child: Center(
                                                                            child: ThemeRegion.auto(
                                                                              id: "widget_subscriptions_screen_80",
                                                                              label: "Icon · subscriptions_screen.dart",
                                                                              child: Icon(
                                                                                Icons.dns_rounded,
                                                                                color: theme.textDim,
                                                                                size: 18,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            12,
                                                                      ),
                                                                      Expanded(
                                                                        child: ThemeRegion.auto(
                                                                          id: "widget_subscriptions_screen_81",
                                                                          label: "Column · subscriptions_screen.dart",
                                                                          child: Column(
                                                                            crossAxisAlignment:
                                                                                CrossAxisAlignment.start,
                                                                            children: [
                                                                              ThemeRegion.auto(
                                                                                id: "widget_subscriptions_screen_82",
                                                                                label: "Text · subscriptions_screen.dart",
                                                                                child: Text(
                                                                                  server.name,
                                                                                  style: TextStyle(
                                                                                    fontSize: 14,
                                                                                    fontWeight: FontWeight.w600,
                                                                                    color: server.isActive ? theme.text : Colors.white70,
                                                                                    fontFamilyFallback: [
                                                                                      'Courier New',
                                                                                      'monospace',
                                                                                    ],
                                                                                  ),
                                                                                  maxLines: 1,
                                                                                  overflow: TextOverflow.ellipsis,
                                                                                ),
                                                                              ),
                                                                              const SizedBox(
                                                                                height: 2,
                                                                              ),
                                                                              ThemeRegion.auto(
                                                                                id: "widget_subscriptions_screen_83",
                                                                                label: "Row · subscriptions_screen.dart",
                                                                                child: Row(
                                                                                  children: [
                                                                                    Flexible(
                                                                                      child: ThemeRegion.auto(
                                                                                        id: "widget_subscriptions_screen_84",
                                                                                        label: "Container · subscriptions_screen.dart",
                                                                                        child: Container(
                                                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                                                                                          child: ThemeRegion.auto(
                                                                                            id: "widget_subscriptions_screen_85",
                                                                                            label: "Text · subscriptions_screen.dart",
                                                                                            child: Text(
                                                                                              '${server.protocol.toUpperCase()} / ${_getTransport(server).toUpperCase()}$jsonTag',
                                                                                              style: TextStyle(fontSize: 9, color: theme.textDim, fontWeight: FontWeight.w700),
                                                                                              overflow: TextOverflow.ellipsis,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    const SizedBox(width: 8),
                                                                                    if (server.isPinging)
                                                                                      SizedBox(
                                                                                        width: 8,
                                                                                        height: 8,
                                                                                        child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.textDim),
                                                                                      )
                                                                                    else if (server.ping > 0) ...[
                                                                                      ThemeRegion.auto(
                                                                                        id: "widget_subscriptions_screen_86",
                                                                                        label: "Icon · subscriptions_screen.dart",
                                                                                        child: Icon(Icons.circle, size: 5, color: pingColor),
                                                                                      ),
                                                                                      const SizedBox(width: 4),
                                                                                      ThemeRegion.auto(
                                                                                        id: "widget_subscriptions_screen_87",
                                                                                        label: "Text · subscriptions_screen.dart",
                                                                                        child: Text(
                                                                                          loc.translate('ping_ms').replaceFirst('\$ms', server.ping.toString().replaceAll(RegExp(r'\s*ms|\s*мс'), '')),
                                                                                          style: TextStyle(fontSize: 11, color: pingColor, fontWeight: FontWeight.w600),
                                                                                        ),
                                                                                      ),
                                                                                    ] else if (server.ping < 0 && server.ping != -100) ...[
                                                                                      ThemeRegion.auto(
                                                                                        id: "widget_subscriptions_screen_88",
                                                                                        label: "Icon · subscriptions_screen.dart",
                                                                                        child: const Icon(Icons.circle, size: 5, color: Colors.redAccent),
                                                                                      ),
                                                                                      const SizedBox(width: 4),
                                                                                      ThemeRegion.auto(
                                                                                        id: "widget_subscriptions_screen_89",
                                                                                        label: "Text · subscriptions_screen.dart",
                                                                                        child: const Text(
                                                                                          'Err',
                                                                                          style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600),
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      GestureDetector(
                                                                        onTap: () =>
                                                                            _pingServer(
                                                                              server,
                                                                            ),
                                                                        child: ThemeRegion.auto(
                                                                          id: "widget_subscriptions_screen_90",
                                                                          label: "Container · subscriptions_screen.dart",
                                                                          child: Container(
                                                                            padding: const EdgeInsets.all(
                                                                              8,
                                                                            ),
                                                                            child: ThemeRegion.auto(
                                                                              id: "widget_subscriptions_screen_91",
                                                                              label: "Icon · subscriptions_screen.dart",
                                                                              child: Icon(
                                                                                Icons.flash_on_rounded,
                                                                                size: 18,
                                                                                color: theme.textDim.withOpacity(0.4),
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
                                                          }).toList(),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ).animate().fade(delay: (index * 100).ms).slideY(begin: 0.1);
                                    },
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
}
