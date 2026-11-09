import '../core/localization/app_localizations.dart';
import '../shared/widgets/theme_region.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/settings_provider.dart';
import '../shared/widgets/styled_qr.dart';
import 'qr_style_screen.dart';

import '../core/utils/config_share_payload.dart';
import '../core/utils/config_share_qr.dart';
import '../core/theme/theme_provider.dart';
import '../shared/widgets/custom_notification.dart';
import '../shared/widgets/glass_alert_dialog.dart';

Future<void> showConfigShareSheet(
  BuildContext context,
  ConfigSharePayload payload,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  builder: (_) => _ShareSheet(payload: payload),
);

class _ShareSheet extends ConsumerStatefulWidget {
  final ConfigSharePayload payload;
  const _ShareSheet({required this.payload});
  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  static const _channel = MethodChannel('pro.kaleert.nextlink/theme_files');
  bool _busy = false;
  Future<void> _send({
    String? text,
    String? contents,
    String? extension,
    Uint8List? bytes,
    String? mime,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _channel.invokeMethod<void>('shareConfig', {
        'name': widget.payload.name,
        'text': text,
        'contents': contents,
        'extension': extension,
        'bytes': bytes,
        'mime': mime,
      });
    } catch (e) {
      if (mounted)
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Не удалось поделиться: {0}",
            args: [e],
          ),
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _qr() async {
    final style = ref.read(settingsProvider).qrStyle;
    final prepared = ConfigShareQr.prepare(
      widget.payload.qr,
      errorLevel: style.errorLevel,
    );
    if (prepared == null) {
      final theme = ref.read(themeProvider).currentTheme;
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (ctx) => GlassAlertDialog(
          surfaceColor: theme.surface,
          title: Text(
            AppLocalizations.text(context, "Конфигурация не помещается в QR"),
          ),
          content: Text(
            AppLocalizations.text(
              context,
              "Даже после сжатия данных слишком много для одного QR-кода. Передайте конфигурацию JSON-файлом — все правила и параметры сохранятся.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.text(context, "Закрыть")),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _send(
                  contents: widget.payload.json,
                  extension: 'json',
                  mime: 'application/json',
                );
              },
              child: Text(
                AppLocalizations.text(context, "Отправить JSON-файл"),
              ),
            ),
          ],
        ),
      );
      return;
    }
    final theme = ref.read(themeProvider).currentTheme;
    await showDialog<void>(
      useRootNavigator: false,
      context: context,
      builder: (ctx) => GlassAlertDialog(
        surfaceColor: theme.surface,
        title: ThemeRegion.auto(
          id: "widget_config_share_sheet_0",
          label: "Text · config_share_sheet.dart",
          child: Text(
            widget.payload.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 300,
            child: ThemeRegion.auto(
              id: "widget_config_share_sheet_1",
              label: "Column · config_share_sheet.dart",
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StyledQr(code: prepared.code, style: style),
                  const SizedBox(height: 12),
                  ThemeRegion.auto(
                    id: "widget_config_share_sheet_2",
                    label: "Text · config_share_sheet.dart",
                    child: Text(
                      prepared.compressed
                          ? AppLocalizations.text(
                              context,
                              "Сжатый QR · импорт через NextLink",
                            )
                          : AppLocalizations.text(
                              context,
                              "Подписка или конфигурация",
                            ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          ThemeRegion.auto(
            id: "widget_config_share_sheet_3",
            label: "TextButton · config_share_sheet.dart",
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: ThemeRegion.auto(
                id: "widget_config_share_sheet_4",
                label: "Text · config_share_sheet.dart",
                child: Text(AppLocalizations.text(context, "Закрыть")),
              ),
            ),
          ),
          ThemeRegion.auto(
            id: "widget_config_share_sheet_5",
            label: "TextButton · config_share_sheet.dart",
            child: TextButton.icon(
              icon: ThemeRegion.auto(
                id: "widget_config_share_sheet_6",
                label: "Icon · config_share_sheet.dart",
                child: const Icon(Icons.ios_share_rounded),
              ),
              label: ThemeRegion.auto(
                id: "widget_config_share_sheet_7",
                label: "Text · config_share_sheet.dart",
                child: const Text('PNG'),
              ),
              onPressed: () async {
                try {
                  final bytes = await renderStyledQr(prepared.code, style);
                  await _send(
                    bytes: bytes,
                    extension: 'png',
                    mime: 'image/png',
                  );
                } catch (e) {
                  if (mounted)
                    CustomNotification.show(
                      context,
                      AppLocalizations.text(
                        context,
                        "Не удалось создать QR: {0}",
                        args: [e],
                      ),
                      isError: true,
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    final p = widget.payload;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: theme.blurSigma,
          sigmaY: theme.blurSigma,
        ),
        child: Material(
          color: theme.surface.withValues(alpha: theme.glassOpacity),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ThemeRegion.auto(
                id: "widget_config_share_sheet_8",
                label: "Column · config_share_sheet.dart",
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemeRegion.auto(
                      id: "widget_config_share_sheet_9",
                      label: "Text · config_share_sheet.dart",
                      child: Text(
                        AppLocalizations.text(
                          context,
                          "Поделиться · {0}",
                          args: [p.name],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: Text(
                        AppLocalizations.text(
                          context,
                          "Оформление всех QR-кодов",
                        ),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const QrStyleScreen(),
                        ),
                      ),
                    ),
                    if (p.url.isNotEmpty)
                      ThemeRegion.auto(
                        id: "widget_config_share_sheet_10",
                        label: "ListTile · config_share_sheet.dart",
                        child: ListTile(
                          dense: true,
                          leading: ThemeRegion.auto(
                            id: "widget_config_share_sheet_11",
                            label: "Icon · config_share_sheet.dart",
                            child: const Icon(Icons.link_rounded),
                          ),
                          title: ThemeRegion.auto(
                            id: "widget_config_share_sheet_12",
                            label: "Text · config_share_sheet.dart",
                            child: Text(
                              AppLocalizations.text(context, "Ссылка"),
                            ),
                          ),
                          onTap: _busy ? null : () => _send(text: p.url),
                        ),
                      ),
                    ThemeRegion.auto(
                      id: "widget_config_share_sheet_13",
                      label: "ListTile · config_share_sheet.dart",
                      child: ListTile(
                        dense: true,
                        leading: ThemeRegion.auto(
                          id: "widget_config_share_sheet_14",
                          label: "Icon · config_share_sheet.dart",
                          child: const Icon(Icons.data_object_rounded),
                        ),
                        title: ThemeRegion.auto(
                          id: "widget_config_share_sheet_15",
                          label: "Text · config_share_sheet.dart",
                          child: Text(
                            AppLocalizations.text(context, "JSON-файл"),
                          ),
                        ),
                        onTap: _busy
                            ? null
                            : () => _send(
                                contents: p.json,
                                extension: 'json',
                                mime: 'application/json',
                              ),
                      ),
                    ),
                    ThemeRegion.auto(
                      id: "widget_config_share_sheet_16",
                      label: "ListTile · config_share_sheet.dart",
                      child: ListTile(
                        dense: true,
                        leading: ThemeRegion.auto(
                          id: "widget_config_share_sheet_17",
                          label: "Icon · config_share_sheet.dart",
                          child: const Icon(Icons.text_snippet_outlined),
                        ),
                        title: ThemeRegion.auto(
                          id: "widget_config_share_sheet_18",
                          label: "Text · config_share_sheet.dart",
                          child: Text(
                            AppLocalizations.text(context, "JSON текстом"),
                          ),
                        ),
                        onTap: _busy ? null : () => _send(text: p.json),
                      ),
                    ),
                    if (p.conf != null)
                      ThemeRegion.auto(
                        id: "widget_config_share_sheet_19",
                        label: "ListTile · config_share_sheet.dart",
                        child: ListTile(
                          dense: true,
                          leading: ThemeRegion.auto(
                            id: "widget_config_share_sheet_20",
                            label: "Icon · config_share_sheet.dart",
                            child: const Icon(Icons.description_outlined),
                          ),
                          title: ThemeRegion.auto(
                            id: "widget_config_share_sheet_21",
                            label: "Text · config_share_sheet.dart",
                            child: const Text('WireGuard / AmneziaWG .conf'),
                          ),
                          onTap: _busy
                              ? null
                              : () => _send(
                                  contents: p.conf,
                                  extension: 'conf',
                                  mime: 'text/plain',
                                ),
                        ),
                      ),
                    if (p.qr.isNotEmpty)
                      ThemeRegion.auto(
                        id: "widget_config_share_sheet_22",
                        label: "ListTile · config_share_sheet.dart",
                        child: ListTile(
                          dense: true,
                          leading: ThemeRegion.auto(
                            id: "widget_config_share_sheet_23",
                            label: "Icon · config_share_sheet.dart",
                            child: const Icon(Icons.qr_code_rounded),
                          ),
                          title: ThemeRegion.auto(
                            id: "widget_config_share_sheet_24",
                            label: "Text · config_share_sheet.dart",
                            child: Text(
                              AppLocalizations.text(context, "QR-код / PNG"),
                            ),
                          ),
                          onTap: _busy ? null : _qr,
                        ),
                      ),
                    if (p.url.isNotEmpty)
                      ThemeRegion.auto(
                        id: "widget_config_share_sheet_25",
                        label: "ListTile · config_share_sheet.dart",
                        child: ListTile(
                          dense: true,
                          leading: ThemeRegion.auto(
                            id: "widget_config_share_sheet_26",
                            label: "Icon · config_share_sheet.dart",
                            child: const Icon(Icons.copy_rounded),
                          ),
                          title: ThemeRegion.auto(
                            id: "widget_config_share_sheet_27",
                            label: "Text · config_share_sheet.dart",
                            child: Text(
                              AppLocalizations.text(
                                context,
                                "Скопировать ссылку",
                              ),
                            ),
                          ),
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: p.url));
                            if (mounted)
                              CustomNotification.show(
                                context,
                                AppLocalizations.text(
                                  context,
                                  "Ссылка скопирована",
                                ),
                              );
                          },
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
  }
}
