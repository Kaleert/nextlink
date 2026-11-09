import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  late Map<String, String> _localizedStrings;
  Map<String, String> _uiStrings = const {};

  static final _uiLoads = <String, Future<Map<String, String>>>{};
  static String languageForSetting(String setting) {
    final language = switch (setting) {
      'Русский' => 'ru',
      'Українська' => 'uk',
      'English' => 'en',
      _ => WidgetsBinding.instance.platformDispatcher.locale.languageCode,
    };
    return ['ru', 'uk', 'en'].contains(language) ? language : 'en';
  }

  static Future<Map<String, String>> uiCatalog(String language) =>
      _uiLoads.putIfAbsent(language, () async {
        final data = jsonDecode(
          await rootBundle.loadString('assets/lang/ui_$language.json'),
        ) as Map;
        return data.map((key, value) => MapEntry('$key', '$value'));
      });
  static String format(
    Map<String, String> catalog,
    String source,
    List<Object?> args,
  ) {
    final result = catalog[source] ?? source;
    return result.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < args.length ? '${args[index]}' : match[0]!;
    });
  }

  static String text(
    BuildContext context,
    String source, {
    List<Object?> args = const [],
  }) => format(of(context)?._uiStrings ?? const {}, source, args);

  Future<bool> load() async {
    String jsonString = await rootBundle.loadString(
      'assets/lang/${locale.languageCode}.json',
    );
    Map<String, dynamic> jsonMap = json.decode(jsonString);

    _localizedStrings = jsonMap.map((key, value) {
      return MapEntry(key, value.toString());
    });

    _uiStrings = await uiCatalog(locale.languageCode);
    return true;
  }

  String keyFor(String value) {
    for (final entry in _localizedStrings.entries) {
      if (entry.value == value) return entry.key;
    }
    return value;
  }

  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ru', 'uk'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
