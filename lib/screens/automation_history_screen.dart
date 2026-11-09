import '../core/localization/app_localizations.dart';
import '../shared/widgets/theme_region.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AutomationHistoryScreen extends StatefulWidget {
  const AutomationHistoryScreen({super.key});
  @override
  State<AutomationHistoryScreen> createState() =>
      _AutomationHistoryScreenState();
}

class _AutomationHistoryScreenState extends State<AutomationHistoryScreen> {
  static const _channel = MethodChannel('pro.kaleert.nextlink/vpn');
  List<Map<String, dynamic>> _events = [];
  String? _error;
  Timer? _timer;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final text =
          await _channel.invokeMethod<String>('getAutomationHistory') ?? '[]';
      final events = (jsonDecode(text) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted)
        setState(() {
          _events = events;
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = AppLocalizations.text(
            context,
            'История доступна в Android-версии',
          ),
        );
    } finally {
      _loading = false;
    }
  }

  String _reason(String value) =>
      const {
        'wifi': 'Подключение к Wi-Fi',
        'mobile': 'Мобильная сеть',
        'network_change': 'Смена сети',
        'wifi_to_mobile': 'Wi-Fi → мобильная сеть',
        'hotspot': 'Раздача интернета',
        'any_network': 'Сеть доступна',
        'timer': 'Таймер',
        'timeout': 'Таймаут',
        'rollback': 'Возврат',
      }[value] ??
      value;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: ThemeRegion.auto(
        id: "widget_automation_history_screen_0",
        label: "Text · automation_history_screen.dart",
        child: Text(AppLocalizations.text(context, "История автоматизации")),
      ),
      actions: [
        ThemeRegion.auto(
          id: "widget_automation_history_screen_1",
          label: "IconButton · automation_history_screen.dart",
          child: IconButton(
            tooltip: AppLocalizations.text(context, "Обновить"),
            onPressed: _load,
            icon: ThemeRegion.auto(
              id: "widget_automation_history_screen_2",
              label: "Icon · automation_history_screen.dart",
              child: const Icon(Icons.refresh),
            ),
          ),
        ),
      ],
    ),
    body: ThemeRegion(
      id: 'screen_history',
      child: _events.isEmpty
          ? Center(
              child: ThemeRegion.auto(
                id: "widget_automation_history_screen_3",
                label: "Text · automation_history_screen.dart",
                child: Text(
                  _error ??
                      AppLocalizations.text(context, "Срабатываний пока нет"),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                final time = DateTime.fromMillisecondsSinceEpoch(
                  (event['time'] as num).toInt(),
                ).toLocal().toString().split('.').first;
                return ThemeRegion.auto(
                  id: "widget_automation_history_screen_4",
                  label: "Card · automation_history_screen.dart",
                  child: Card(
                    child: ThemeRegion.auto(
                      id: "widget_automation_history_screen_5",
                      label: "ListTile · automation_history_screen.dart",
                      child: ListTile(
                        leading: ThemeRegion.auto(
                          id: "widget_automation_history_screen_6",
                          label: "Icon · automation_history_screen.dart",
                          child: const Icon(Icons.bolt_rounded),
                        ),
                        title: ThemeRegion.auto(
                          id: "widget_automation_history_screen_7",
                          label: "Text · automation_history_screen.dart",
                          child: Text(
                            '${event['profile']} · ${AppLocalizations.text(context, _reason(event['reason'] ?? ''))}',
                          ),
                        ),
                        subtitle: ThemeRegion.auto(
                          id: "widget_automation_history_screen_8",
                          label: "Text · automation_history_screen.dart",
                          child: Text(
                            '$time\n${event['server']}\n${AppLocalizations.text(context, '${event['result']}')}',
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
