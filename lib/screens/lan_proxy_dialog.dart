import '../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';

import '../core/providers/settings_provider.dart';
import '../core/utils/lan_proxy_inbounds.dart';
import '../shared/widgets/glass_alert_dialog.dart';

class LanProxyDialog extends StatefulWidget {
  final SettingsState settings;
  const LanProxyDialog({super.key, required this.settings});
  @override
  State<LanProxyDialog> createState() => _LanProxyDialogState();
}

class _LanProxyDialogState extends State<LanProxyDialog> {
  late final port = TextEditingController(
    text: widget.settings.lanPort.toString(),
  );
  late final username = TextEditingController(
    text: widget.settings.lanUsername,
  );
  late final password = TextEditingController(
    text: widget.settings.lanPassword,
  );
  bool visible = false;
  String? error;
  @override
  void dispose() {
    port.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void save() {
    final value = widget.settings.copyWith(
      lanPort: int.tryParse(port.text.trim()) ?? 0,
      lanUsername: username.text.trim(),
      lanPassword: password.text,
    );
    try {
      LanProxyInbounds.validate(value);
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => GlassAlertDialog(
    surfaceColor: Theme.of(context).colorScheme.surface,
    title: Text(AppLocalizations.text(context, "Доступ из LAN")),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppLocalizations.text(context, "Порт HTTP-прокси"),
              hintText: '2080',
            ),
          ),
          TextField(
            controller: username,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: AppLocalizations.text(context, "Имя пользователя"),
            ),
          ),
          TextField(
            controller: password,
            obscureText: !visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: AppLocalizations.text(context, "Пароль"),
              suffixIcon: IconButton(
                tooltip: visible
                    ? AppLocalizations.text(context, "Скрыть пароль")
                    : AppLocalizations.text(context, "Показать пароль"),
                onPressed: () => setState(() => visible = !visible),
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.text(
              context,
              "На другом устройстве укажите IP этого телефона и выбранный порт. Пустые логин и пароль отключают авторизацию. Изменения применятся при следующем подключении VPN.",
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppLocalizations.text(context, "Отмена")),
      ),
      TextButton(
        onPressed: save,
        child: Text(AppLocalizations.text(context, "Сохранить")),
      ),
    ],
  );
}
