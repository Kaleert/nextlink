import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription.dart';
import '../models/theme_config.dart';
import '../providers/chains_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/rules_provider.dart';
import '../providers/settings_provider.dart';

class AppBackup {
  static const _lists = {
    'saved_subscriptions': 'subscriptions',
    'custom_proxy_chains': 'chains',
    'custom_rules': 'rules',
    'saved_app_profiles': 'profiles',
    'custom_themes': 'themes',
  };

  static Future<String> export() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'format': 'nextlink-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': jsonDecode(prefs.getString('app_settings') ?? '{}'),
      'currentTheme':
          prefs.getString('current_theme_name') ??
          ThemeConfig.defaultTheme.name,
      for (final e in _lists.entries)
        e.value: jsonDecode(prefs.getString(e.key) ?? '[]'),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static Map<String, dynamic> validate(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map ||
        decoded['format'] != 'nextlink-backup' ||
        decoded['version'] != 1)
      throw const FormatException('Это не резервная копия NextLink версии 1');
    final map = Map<String, dynamic>.from(decoded);
    if (map['settings'] is! Map || map['currentTheme'] is! String)
      throw const FormatException('Повреждены настройки копии');
    SettingsState.fromMap(Map<String, dynamic>.from(map['settings']));
    for (final key in _lists.values) {
      if (map[key] is! List) throw FormatException('Повреждён раздел $key');
      for (final item in map[key] as List) {
        final value = Map<String, dynamic>.from(item as Map);
        switch (key) {
          case 'subscriptions':
            Subscription.fromMap(value);
          case 'chains':
            ProxyChain.fromMap(value);
          case 'rules':
            AppRule.fromMap(value);
          case 'profiles':
            AppProfile.fromMap(value);
          case 'themes':
            ThemeConfig.fromMap(value);
        }
      }
    }
    return map;
  }

  static Future<void> restore(Map<String, dynamic> data) async {
    // Revalidate immediately before the first write. Unknown preference keys are never imported.
    final map = validate(jsonEncode(data));
    final prefs = await SharedPreferences.getInstance();
    final values = <String, String>{
      'app_settings': jsonEncode(map['settings']),
      'current_theme_name': map['currentTheme'],
      for (final e in _lists.entries) e.key: jsonEncode(map[e.value]),
    };
    final old = {for (final key in values.keys) key: prefs.getString(key)};
    try {
      for (final e in values.entries) {
        if (!await prefs.setString(e.key, e.value))
          throw StateError('Не удалось сохранить ${e.key}');
      }
    } catch (_) {
      for (final e in old.entries) {
        if (e.value == null) {
          await prefs.remove(e.key);
        } else {
          await prefs.setString(e.key, e.value!);
        }
      }
      rethrow;
    }
  }
}
