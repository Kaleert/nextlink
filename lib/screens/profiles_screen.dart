import '../core/localization/app_localizations.dart';
import '../shared/widgets/theme_region.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/profiles_provider.dart';
import '../core/providers/subscription_provider.dart';
import '../core/theme/theme_provider.dart';
import '../shared/widgets/glass_alert_dialog.dart';
import '../shared/widgets/glass_dropdown.dart';
import 'automation_history_screen.dart';

const _profileTriggers = <String, String>{
  'any_network': 'Любая сеть доступна',
  'wifi': 'Подключение к Wi-Fi',
  'mobile': 'Подключение к мобильной сети',
  'wifi_to_mobile': 'Переход Wi-Fi → мобильная сеть',
  'network_change': 'Смена сети',
  'hotspot': 'Включение точки доступа',
  'timer': 'Смена сервера по таймеру',
  'timeout': 'Таймаут подключения',
};

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    AppProfile? profile,
  ]) async {
    final result = await showDialog<AppProfile>(
      useRootNavigator: false,
      context: context,
      builder: (_) => _ProfileEditorDialog(profile: profile),
    );
    if (result == null || !context.mounted) return;
    final notifier = ref.read(profilesProvider.notifier);
    if (profile == null) {
      await notifier.addProfile(result);
    } else {
      await notifier.updateProfile(result);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppProfile profile,
  ) async {
    final theme = ref.read(themeProvider).currentTheme;
    final confirmed = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => GlassAlertDialog(
        surfaceColor: theme.surface,
        title: ThemeRegion.auto(
          id: "widget_profiles_screen_0",
          label: "Text · profiles_screen.dart",
          child: Text(AppLocalizations.text(context, "Удалить профиль?")),
        ),
        content: ThemeRegion.auto(
          id: "widget_profiles_screen_1",
          label: "Text · profiles_screen.dart",
          child: Text(
            AppLocalizations.text(
              context,
              "Профиль «{0}» будет удалён.",
              args: [profile.name],
            ),
          ),
        ),
        actions: [
          ThemeRegion.auto(
            id: "widget_profiles_screen_2",
            label: "IconButton · profiles_screen.dart",
            child: IconButton(
              tooltip: AppLocalizations.text(context, "История автоматизации"),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AutomationHistoryScreen(),
                ),
              ),
              icon: ThemeRegion.auto(
                id: "widget_profiles_screen_3",
                label: "Icon · profiles_screen.dart",
                child: const Icon(Icons.history_rounded),
              ),
            ),
          ),
          ThemeRegion.auto(
            id: "widget_profiles_screen_4",
            label: "TextButton · profiles_screen.dart",
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: ThemeRegion.auto(
                id: "widget_profiles_screen_5",
                label: "Text · profiles_screen.dart",
                child: Text(AppLocalizations.text(context, "Отмена")),
              ),
            ),
          ),
          ThemeRegion.auto(
            id: "widget_profiles_screen_6",
            label: "TextButton · profiles_screen.dart",
            child: TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: ThemeRegion.auto(
                id: "widget_profiles_screen_7",
                label: "Text · profiles_screen.dart",
                child: Text(AppLocalizations.text(context, "Удалить")),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(profilesProvider.notifier).removeProfile(profile.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).currentTheme;
    final profiles = ref.watch(profilesProvider);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: ThemeRegion.auto(
          id: "widget_profiles_screen_8",
          label: "Text · profiles_screen.dart",
          child: Text(AppLocalizations.text(context, "Профили")),
        ),
        actions: [
          ThemeRegion.auto(
            id: "widget_profiles_screen_9",
            label: "IconButton · profiles_screen.dart",
            child: IconButton(
              tooltip: AppLocalizations.text(context, "Добавить профиль"),
              onPressed: () => _edit(context, ref),
              icon: ThemeRegion.auto(
                id: "widget_profiles_screen_10",
                label: "Icon · profiles_screen.dart",
                child: const Icon(Icons.add_rounded),
              ),
            ),
          ),
        ],
      ),
      body: ThemeRegion(
        id: 'screen_profiles',
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                ThemeRegion.auto(
                  id: "widget_profiles_screen_11",
                  label: "Text · profiles_screen.dart",
                  child: Text(
                    AppLocalizations.text(
                      context,
                      "Профили работают независимо. В Android условия отслеживает фоновый сервис с отдельным уведомлением. Тумблер включает условия профиля; нажатие на карточку открывает редактор. Удерживайте карточку, чтобы удалить её. Если условия нескольких профилей совпали, первым применяется верхний.",
                    ),
                    style: TextStyle(color: theme.textDim, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                if (profiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: ThemeRegion.auto(
                      id: "widget_profiles_screen_12",
                      label: "Column · profiles_screen.dart",
                      child: Column(
                        children: [
                          ThemeRegion.auto(
                            id: "widget_profiles_screen_13",
                            label: "Text · profiles_screen.dart",
                            child: Text(
                              AppLocalizations.text(
                                context,
                                "Пока нет автоматизаций",
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ThemeRegion.auto(
                            id: "widget_profiles_screen_14",
                            label: "OutlinedButton · profiles_screen.dart",
                            child: OutlinedButton.icon(
                              onPressed: () => _edit(context, ref),
                              icon: ThemeRegion.auto(
                                id: "widget_profiles_screen_15",
                                label: "Icon · profiles_screen.dart",
                                child: const Icon(Icons.add),
                              ),
                              label: ThemeRegion.auto(
                                id: "widget_profiles_screen_16",
                                label: "Text · profiles_screen.dart",
                                child: Text(
                                  AppLocalizations.text(
                                    context,
                                    "Создать профиль",
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final profile in profiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: (profile.isEnabled ? theme.primary : theme.surface)
                          .withValues(alpha: profile.isEnabled ? .12 : .4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: profile.isEnabled
                              ? theme.primary.withValues(alpha: .35)
                              : Colors.white10,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _edit(context, ref, profile),
                        onLongPress: () => _delete(context, ref, profile),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: ThemeRegion.auto(
                            id: "widget_profiles_screen_17",
                            label: "Column · profiles_screen.dart",
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ThemeRegion.auto(
                                  id: "widget_profiles_screen_18",
                                  label: "Row · profiles_screen.dart",
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ThemeRegion.auto(
                                          id: "widget_profiles_screen_19",
                                          label: "Text · profiles_screen.dart",
                                          child: Text(
                                            profile.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      ThemeRegion.auto(
                                        id: "widget_profiles_screen_20",
                                        label: "Switch · profiles_screen.dart",
                                        child: Switch.adaptive(
                                          value: profile.isEnabled,
                                          onChanged: profile.triggers.isEmpty
                                              ? null
                                              : (value) => ref
                                                    .read(
                                                      profilesProvider.notifier,
                                                    )
                                                    .setEnabled(
                                                      profile.id,
                                                      value,
                                                    ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ThemeRegion.auto(
                                  id: "widget_profiles_screen_21",
                                  label: "Text · profiles_screen.dart",
                                  child: Text(
                                    profile.triggers.isEmpty
                                        ? AppLocalizations.text(
                                            context,
                                            "Добавьте условия срабатывания",
                                          )
                                        : profile.triggers
                                              .map(
                                                (t) => AppLocalizations.text(
                                                  context,
                                                  _profileTriggers[t] ?? t,
                                                ),
                                              )
                                              .join(' · '),
                                  ),
                                ),
                                if (profile.serverKeys.isNotEmpty)
                                  ThemeRegion.auto(
                                    id: "widget_profiles_screen_22",
                                    label: "Text · profiles_screen.dart",
                                    child: Text(
                                      AppLocalizations.text(
                                        context,
                                        "Резервная группа: {0} серверов",
                                        args: [profile.serverKeys.length],
                                      ),
                                      style: TextStyle(
                                        color: theme.textDim,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (profile.hasTrigger('timer'))
                                  ThemeRegion.auto(
                                    id: "widget_profiles_screen_23",
                                    label: "Text · profiles_screen.dart",
                                    child: Text(
                                      AppLocalizations.text(
                                        context,
                                        "Каждые {0} мин.",
                                        args: [profile.intervalMinutes],
                                      ),
                                      style: TextStyle(color: theme.textDim),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                ThemeRegion.auto(
                                  id: "widget_profiles_screen_24",
                                  label: "Text · profiles_screen.dart",
                                  child: Text(
                                    profile.serverKey == null
                                        ? AppLocalizations.text(
                                            context,
                                            "Действие: следующий сервер",
                                          )
                                        : AppLocalizations.text(
                                            context,
                                            "Действие: подключить выбранный сервер",
                                          ),
                                    style: TextStyle(
                                      color: theme.textDim,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                ThemeRegion.auto(
                                  id: "widget_profiles_screen_25",
                                  label: "Row · profiles_screen.dart",
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      ThemeRegion.auto(
                                        id: "widget_profiles_screen_26",
                                        label:
                                            "IconButton · profiles_screen.dart",
                                        child: IconButton(
                                          tooltip: AppLocalizations.text(
                                            context,
                                            "Удалить профиль",
                                          ),
                                          onPressed: () =>
                                              _delete(context, ref, profile),
                                          icon: ThemeRegion.auto(
                                            id: "widget_profiles_screen_27",
                                            label:
                                                "Icon · profiles_screen.dart",
                                            child: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      ThemeRegion.auto(
                                        id: "widget_profiles_screen_28",
                                        label:
                                            "TextButton · profiles_screen.dart",
                                        child: TextButton.icon(
                                          onPressed: () =>
                                              _edit(context, ref, profile),
                                          icon: ThemeRegion.auto(
                                            id: "widget_profiles_screen_29",
                                            label:
                                                "Icon · profiles_screen.dart",
                                            child: const Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                            ),
                                          ),
                                          label: ThemeRegion.auto(
                                            id: "widget_profiles_screen_30",
                                            label:
                                                "Text · profiles_screen.dart",
                                            child: Text(
                                              AppLocalizations.text(
                                                context,
                                                "Изменить",
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
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileEditorDialog extends ConsumerStatefulWidget {
  final AppProfile? profile;
  const _ProfileEditorDialog({this.profile});

  @override
  ConsumerState<_ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<_ProfileEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _interval;
  late final Set<String> _triggers;
  late String _serverKey;
  late final Set<String> _serverKeys;
  String? _triggerError;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile?.name ?? '');
    _interval = TextEditingController(
      text: '${widget.profile?.intervalMinutes ?? 30}',
    );
    _triggers = {...?widget.profile?.triggers}
      ..removeWhere((t) => !_profileTriggers.containsKey(t));
    _serverKey = widget.profile?.serverKey ?? '';
    _serverKeys = {...?widget.profile?.serverKeys};
  }

  @override
  void dispose() {
    _name.dispose();
    _interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    final servers = {
      for (final subscription in ref.watch(subscriptionProvider))
        for (final server in subscription.servers) server.uniqueKey: server,
    };
    return GlassAlertDialog(
      surfaceColor: theme.surface,
      title: ThemeRegion.auto(
        id: "widget_profiles_screen_31",
        label: "Text · profiles_screen.dart",
        child: Text(
          widget.profile == null
              ? AppLocalizations.text(context, "Новый профиль")
              : AppLocalizations.text(context, "Редактировать профиль"),
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: ThemeRegion.auto(
              id: "widget_profiles_screen_32",
              label: "Column · profiles_screen.dart",
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThemeRegion.auto(
                    id: "widget_profiles_screen_33",
                    label: "TextFormField · profiles_screen.dart",
                    child: TextFormField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.text(
                          context,
                          "Название профиля",
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Введите название'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ThemeRegion.auto(
                    id: "widget_profiles_screen_34",
                    label: "Text · profiles_screen.dart",
                    child: Text(
                      AppLocalizations.text(context, "Условия срабатывания"),
                    ),
                  ),
                  ThemeRegion.auto(
                    id: "widget_profiles_screen_35",
                    label: "Text · profiles_screen.dart",
                    child: Text(
                      AppLocalizations.text(
                        context,
                        "Можно включить несколько. Выключите условие, чтобы удалить триггер.",
                      ),
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ),
                  for (final trigger in _profileTriggers.entries)
                    ThemeRegion.auto(
                      id: "widget_profiles_screen_36",
                      label: "SwitchListTile · profiles_screen.dart",
                      child: SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: ThemeRegion.auto(
                          id: "widget_profiles_screen_37",
                          label: "Text · profiles_screen.dart",
                          child: Text(
                            AppLocalizations.text(context, trigger.value),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        value: _triggers.contains(trigger.key),
                        onChanged: (enabled) => setState(() {
                          enabled
                              ? _triggers.add(trigger.key)
                              : _triggers.remove(trigger.key);
                          _triggerError = null;
                        }),
                      ),
                    ),
                  if (_triggerError != null)
                    ThemeRegion.auto(
                      id: "widget_profiles_screen_38",
                      label: "Text · profiles_screen.dart",
                      child: Text(
                        _triggerError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ThemeRegion.auto(
                    id: "widget_profiles_screen_39",
                    label: "Text · profiles_screen.dart",
                    child: Text(
                      AppLocalizations.text(context, "Действие"),
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                  GlassDropdown<String>(
                    value: _serverKey,
                    surfaceColor: theme.surface,
                    accentColor: theme.primary,
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: ThemeRegion.auto(
                          id: "widget_profiles_screen_40",
                          label: "Text · profiles_screen.dart",
                          child: Text(
                            AppLocalizations.text(context, "Следующий сервер"),
                          ),
                        ),
                      ),
                      if (_serverKey.isNotEmpty &&
                          !servers.containsKey(_serverKey))
                        DropdownMenuItem(
                          value: _serverKey,
                          child: ThemeRegion.auto(
                            id: "widget_profiles_screen_41",
                            label: "Text · profiles_screen.dart",
                            child: Text(
                              AppLocalizations.text(
                                context,
                                "Сервер удалён — выберите другой",
                              ),
                            ),
                          ),
                        ),
                      for (final entry in servers.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: ThemeRegion.auto(
                            id: "widget_profiles_screen_42",
                            label: "Text · profiles_screen.dart",
                            child: Text(
                              entry.value.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _serverKey = value ?? '';
                      _serverError = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  ThemeRegion.auto(
                    id: "widget_profiles_screen_43",
                    label: "Text · profiles_screen.dart",
                    child: Text(
                      AppLocalizations.text(
                        context,
                        "Группа резервных серверов",
                      ),
                    ),
                  ),
                  ThemeRegion.auto(
                    id: "widget_profiles_screen_44",
                    label: "Text · profiles_screen.dart",
                    child: Text(
                      AppLocalizations.text(
                        context,
                        "Пустая группа — все серверы. При выборе конкретных серверов переключение и резерв ограничены этой группой.",
                      ),
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ),
                  for (final entry in servers.entries)
                    ThemeRegion.auto(
                      id: "widget_profiles_screen_45",
                      label: "SwitchListTile · profiles_screen.dart",
                      child: SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: ThemeRegion.auto(
                          id: "widget_profiles_screen_46",
                          label: "Text · profiles_screen.dart",
                          child: Text(
                            entry.value.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        value: _serverKeys.contains(entry.key),
                        onChanged: (value) => setState(() {
                          value
                              ? _serverKeys.add(entry.key)
                              : _serverKeys.remove(entry.key);
                        }),
                      ),
                    ),
                  if (_serverError != null)
                    ThemeRegion.auto(
                      id: "widget_profiles_screen_47",
                      label: "Text · profiles_screen.dart",
                      child: Text(
                        _serverError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_triggers.contains('timer'))
                    ThemeRegion.auto(
                      id: "widget_profiles_screen_48",
                      label: "TextFormField · profiles_screen.dart",
                      child: TextFormField(
                        controller: _interval,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.text(
                            context,
                            "Интервал (минуты)",
                          ),
                        ),
                        validator: (value) {
                          final number = int.tryParse(value ?? '');
                          return number == null || number < 1 || number > 1440
                              ? 'От 1 до 1440 минут'
                              : null;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        ThemeRegion.auto(
          id: "widget_profiles_screen_49",
          label: "TextButton · profiles_screen.dart",
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: ThemeRegion.auto(
              id: "widget_profiles_screen_50",
              label: "Text · profiles_screen.dart",
              child: Text(AppLocalizations.text(context, "Отмена")),
            ),
          ),
        ),
        ThemeRegion.auto(
          id: "widget_profiles_screen_51",
          label: "TextButton · profiles_screen.dart",
          child: TextButton(
            onPressed: () {
              final valid = _formKey.currentState!.validate();
              if (_triggers.isEmpty)
                setState(() => _triggerError = 'Включите хотя бы одно условие');
              if (!valid || _triggers.isEmpty) return;
              if (_serverKey.isNotEmpty && !servers.containsKey(_serverKey)) {
                setState(() => _serverError = 'Выберите доступный сервер');
                return;
              }
              Navigator.pop(
                context,
                AppProfile(
                  id:
                      widget.profile?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  name: _name.text.trim(),
                  triggers: _triggers.toList(),
                  serverKey: _serverKey.isEmpty ? null : _serverKey,
                  serverKeys: _serverKeys.toList(),
                  intervalMinutes: int.tryParse(_interval.text) ?? 30,
                  isEnabled: widget.profile?.isEnabled ?? false,
                ),
              );
            },
            child: ThemeRegion.auto(
              id: "widget_profiles_screen_52",
              label: "Text · profiles_screen.dart",
              child: Text(
                widget.profile == null
                    ? AppLocalizations.text(context, "Создать")
                    : AppLocalizations.text(context, "Сохранить"),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
