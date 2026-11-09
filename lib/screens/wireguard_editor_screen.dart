import '../core/localization/app_localizations.dart';
import '../shared/widgets/theme_region.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/proxies/wireguard_config.dart';

class WireGuardEditorScreen extends StatefulWidget {
  final WireGuardConfig? initialConfig;
  const WireGuardEditorScreen({super.key, this.initialConfig});
  @override
  State<WireGuardEditorScreen> createState() => _WireGuardEditorScreenState();
}

class _WireGuardEditorScreenState extends State<WireGuardEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _config;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initialConfig?.name ?? 'WireGuard / WARP',
    );
    _config = TextEditingController(text: widget.initialConfig?.source ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _config.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final value = WireGuardConfig.parse(
        _config.text.trim(),
        name: _name.text.trim(),
      );
      Navigator.pop(context, value);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: ThemeRegion.auto(
        id: "widget_wireguard_editor_screen_0",
        label: "Text · wireguard_editor_screen.dart",
        child: const Text('WireGuard / WARP'),
      ),
      actions: [
        ThemeRegion.auto(
          id: "widget_wireguard_editor_screen_1",
          label: "IconButton · wireguard_editor_screen.dart",
          child: IconButton(
            tooltip: AppLocalizations.text(context, "Вставить конфигурацию"),
            icon: ThemeRegion.auto(
              id: "widget_wireguard_editor_screen_2",
              label: "Icon · wireguard_editor_screen.dart",
              child: const Icon(Icons.paste_rounded),
            ),
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              if (mounted && data?.text != null)
                setState(() {
                  _config.text = data!.text!;
                  _error = null;
                });
            },
          ),
        ),
        ThemeRegion.auto(
          id: "widget_wireguard_editor_screen_3",
          label: "IconButton · wireguard_editor_screen.dart",
          child: IconButton(
            tooltip: AppLocalizations.text(context, "Сохранить"),
            onPressed: _save,
            icon: ThemeRegion.auto(
              id: "widget_wireguard_editor_screen_4",
              label: "Icon · wireguard_editor_screen.dart",
              child: const Icon(Icons.check_rounded),
            ),
          ),
        ),
      ],
    ),
    body: ThemeRegion(
      id: 'screen_wg_editor',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ThemeRegion.auto(
            id: "widget_wireguard_editor_screen_5",
            label: "TextField · wireguard_editor_screen.dart",
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: AppLocalizations.text(context, "Название"),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ThemeRegion.auto(
            id: "widget_wireguard_editor_screen_6",
            label: "Text · wireguard_editor_screen.dart",
            child: Text(
              AppLocalizations.text(
                context,
                "Вставьте готовый .conf с секциями [Interface] и [Peer] или ссылку wireguard://. Для WARP нужны действительные ключи и адреса вашей конфигурации.",
              ),
            ),
          ),
          const SizedBox(height: 12),
          ThemeRegion.auto(
            id: "widget_wireguard_editor_screen_7",
            label: "TextField · wireguard_editor_screen.dart",
            child: TextField(
              controller: _config,
              minLines: 14,
              maxLines: 28,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: AppLocalizations.text(context, "Конфигурация"),
                alignLabelWithHint: true,
                errorText: _error,
                errorMaxLines: 5,
                hintText: '[Interface]\nPrivateKey = …\nAddress = …\n\n[Peer]\nPublicKey = …\nEndpoint = host:port\nAllowedIPs = 0.0.0.0/0, ::/0',
              ),
            ),
          ),
          const SizedBox(height: 16),
          ThemeRegion.auto(
            id: "widget_wireguard_editor_screen_8",
            label: "Text · wireguard_editor_screen.dart",
            child: Text(
              AppLocalizations.text(
                context,
                "Поддерживается AmneziaWG 3.1: Jc/Jmin/Jmax, S1–S4, H1–H4, I1–I5, HeaderProtectionKey, параметры padding и таймингов. В Android используется отдельно загружаемое ядро Amnezia Box. Ключи и параметры должны совпадать с сервером.",
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
