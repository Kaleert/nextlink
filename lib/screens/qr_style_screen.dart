import '../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/qr_export_style.dart';
import '../core/providers/settings_provider.dart';
import '../core/utils/config_share_qr.dart';
import '../shared/widgets/styled_qr.dart';
import '../shared/widgets/glass_dropdown.dart';
import '../shared/widgets/theme_color_palette.dart';

class QrStyleScreen extends ConsumerStatefulWidget {
  const QrStyleScreen({super.key});
  @override
  ConsumerState<QrStyleScreen> createState() => _QrStyleScreenState();
}

class _QrStyleScreenState extends ConsumerState<QrStyleScreen> {
  late QrExportStyle style;
  @override
  void initState() {
    super.initState();
    style = ref.read(settingsProvider).qrStyle;
  }

  Future<void> color(bool foreground) async {
    final value = await showDialog<Color>(
      context: context,
      builder: (_) =>
          ThemeColorPalette(initial: foreground ? style.ink : style.paper),
    );
    if (value != null && mounted)
      setState(
        () => style = foreground
            ? style.copyWith(foreground: value.toARGB32())
            : style.copyWith(background: value.toARGB32()),
      );
  }

  Widget choice(
    String title,
    String value,
    Map<String, String> items,
    ValueChanged<String> change,
  ) => Row(
    children: [
      Expanded(child: Text(AppLocalizations.text(context, title))),
      GlassDropdown<String>(
        value: value,
        surfaceColor: Theme.of(context).colorScheme.surface,
        accentColor: Theme.of(context).colorScheme.primary,
        items: items.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(AppLocalizations.text(context, e.value)),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) change(v);
        },
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final qr = ConfigShareQr.prepare(
      'https://nextlink.example/import',
      errorLevel: style.errorLevel,
    )!;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.text(context, "Оформление QR")),
        actions: [
          IconButton(
            tooltip: AppLocalizations.text(context, "Сбросить оформление"),
            onPressed: () => setState(() => style = const QrExportStyle()),
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: AppLocalizations.text(context, "Сохранить оформление"),
            onPressed: () {
              ref
                  .read(settingsProvider.notifier)
                  .update(ref.read(settingsProvider).copyWith(qrStyle: style));
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: StyledQr(code: qr.code, style: style, dimension: 220),
            ),
            const SizedBox(height: 18),
            Text(
              AppLocalizations.text(
                context,
                "Общие настройки для всех QR-кодов: просмотр и экспорт PNG.",
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => color(true),
                    icon: Icon(Icons.circle, color: style.ink),
                    label: Text(AppLocalizations.text(context, "Цвет кода")),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => color(false),
                    icon: Icon(Icons.circle, color: style.paper),
                    label: Text(AppLocalizations.text(context, "Цвет фона")),
                  ),
                ),
              ],
            ),
            if (!style.readable)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  AppLocalizations.text(
                    context,
                    "Низкий контраст: некоторым сканерам будет сложно прочитать QR. Сохранение доступно.",
                  ),
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              ),
            choice(
              AppLocalizations.text(context, "Маркеры в углах"),
              style.eyes,
              {'square': 'Квадраты', 'circle': 'Круги'},
              (v) => setState(() => style = style.copyWith(eyes: v)),
            ),
            choice(
              AppLocalizations.text(context, "Модули кода"),
              style.modules,
              {'square': 'Квадраты', 'circle': 'Круги'},
              (v) => setState(() => style = style.copyWith(modules: v)),
            ),
            choice(
              AppLocalizations.text(context, "Коррекция ошибок"),
              style.correction,
              {'L': 'L · 7%', 'M': 'M · 15%', 'Q': 'Q · 25%', 'H': 'H · 30%'},
              (v) => setState(() => style = style.copyWith(correction: v)),
            ),
            Text(
              AppLocalizations.text(
                context,
                "Свободное поле: {0} модулей",
                args: [style.quietZone],
              ),
            ),
            Slider(
              value: style.quietZone.toDouble(),
              min: 4,
              max: 12,
              divisions: 8,
              onChanged: (v) =>
                  setState(() => style = style.copyWith(quietZone: v.round())),
            ),
            choice(
              AppLocalizations.text(context, "Размер PNG"),
              style.size.toString(),
              {
                for (final n in {512, 1024, 1536, 2048, style.size})
                  '$n': '$n × $n',
              },
              (v) => setState(() => style = style.copyWith(size: int.parse(v))),
            ),
          ],
        ),
      ),
    );
  }
}
