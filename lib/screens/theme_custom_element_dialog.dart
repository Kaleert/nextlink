import '../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';

const themeActions = <String, String>{
  'none': 'Без действия',
  'toggle': 'Включить / выключить VPN',
  'connect': 'Подключить VPN',
  'disconnect': 'Отключить VPN',
  'reconnect': 'Переподключить VPN',
  'servers': 'Выбор сервера',
  'settings': 'Настройки',
  'profiles': 'Профили',
  'rules': 'Правила',
  'apps': 'Приложения',
  'url': 'URL / команда nextlink://',
  'copy': 'Скопировать текст',
};

class ThemeCustomElementDialog extends StatefulWidget {
  final Map<String, dynamic>? element;
  const ThemeCustomElementDialog({super.key, this.element});
  @override
  State<ThemeCustomElementDialog> createState() =>
      _ThemeCustomElementDialogState();
}

class _ThemeCustomElementDialogState extends State<ThemeCustomElementDialog> {
  late final label = TextEditingController(
    text: widget.element?['label']?.toString() ?? 'Моя кнопка',
  );
  late final target = TextEditingController(
    text:
        widget.element?['url']?.toString() ??
        widget.element?['value']?.toString() ??
        '',
  );
  late String action = widget.element == null
      ? 'toggle'
      : themeActions.containsKey(widget.element?['action'])
      ? widget.element!['action'] as String
      : 'none';
  late String type =
      const [
        'button',
        'text',
        'card',
        'divider',
        'spacer',
      ].contains(widget.element?['type'])
      ? widget.element!['type'] as String
      : 'button';
  String? error;
  @override
  void dispose() {
    label.dispose();
    target.dispose();
    super.dispose();
  }

  void save() {
    final text = target.text.trim();
    final uri = Uri.tryParse(text);
    if (label.text.trim().isEmpty && !['divider', 'spacer'].contains(type)) {
      setState(() => error = 'Введите надпись');
      return;
    }
    if (action == 'url' &&
        (uri == null ||
            !['http', 'https', 'tg', 'nextlink'].contains(uri.scheme))) {
      setState(() => error = 'Укажите http(s), tg или nextlink:// ссылку');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      ...?widget.element,
      'id':
          widget.element?['id'] ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      'label': label.text.trim(),
      'type': type,
      'action': action,
      'url': text,
      'value': text,
      'placement': widget.element?['placement'] ?? 'overlay',
      'x': widget.element?['x'] ?? .15,
      'y': widget.element?['y'] ?? .48,
      'width': widget.element?['width'] ?? .7,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Theme.of(context).colorScheme.surface
        .withValues(alpha: .75),
    title: Text(
      widget.element == null
          ? AppLocalizations.text(context, "Добавить элемент")
          : AppLocalizations.text(context, "Мой элемент"),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: label,
            decoration: InputDecoration(
              labelText: AppLocalizations.text(context, "Надпись"),
            ),
            maxLines: 3,
          ),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: InputDecoration(
              labelText: AppLocalizations.text(context, "Вид"),
            ),
            items: [
              DropdownMenuItem(
                value: 'button',
                child: Text(AppLocalizations.text(context, "Кнопка")),
              ),
              DropdownMenuItem(
                value: 'text',
                child: Text(AppLocalizations.text(context, "Текст")),
              ),
              DropdownMenuItem(
                value: 'card',
                child: Text(AppLocalizations.text(context, "Карточка")),
              ),
              DropdownMenuItem(
                value: 'divider',
                child: Text(AppLocalizations.text(context, "Разделитель")),
              ),
              DropdownMenuItem(
                value: 'spacer',
                child: Text(AppLocalizations.text(context, "Отступ")),
              ),
            ],
            onChanged: (v) => setState(() => type = v ?? 'button'),
          ),
          DropdownButtonFormField<String>(
            initialValue: action,
            decoration: InputDecoration(
              labelText: AppLocalizations.text(context, "Действие"),
            ),
            isExpanded: true,
            items: themeActions.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      AppLocalizations.text(context, e.value),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => action = v ?? 'none'),
          ),
          if (action == 'url' || action == 'copy')
            TextField(
              controller: target,
              decoration: InputDecoration(
                labelText: action == 'copy'
                    ? AppLocalizations.text(context, "Текст для копирования")
                    : AppLocalizations.text(context, "Ссылка или URL-команда"),
              ),
              maxLines: 2,
            ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.text(
              context,
              "Динамические надписи: {{vpn}}, {{timer}}, {{traffic}}, {{ip}}, {{server}}, {{ping}}. Значения обновляются вместе с VPN.",
            ),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        child: Text(AppLocalizations.text(context, "Готово")),
      ),
    ],
  );
}
