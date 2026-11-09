import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/theme_config.dart';

class ThemeState {
  final ThemeConfig currentTheme;
  final List<ThemeConfig> customThemes;

  ThemeState({required this.currentTheme, this.customThemes = const []});

  ThemeState copyWith({
    ThemeConfig? currentTheme,
    List<ThemeConfig>? customThemes,
  }) {
    return ThemeState(
      currentTheme: currentTheme ?? this.currentTheme,
      customThemes: customThemes ?? this.customThemes,
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  late final Future<void> _loadFuture;
  final bool _persist;

  ThemeNotifier()
    : _persist = true,
      super(ThemeState(currentTheme: ThemeConfig.defaultTheme)) {
    _loadFuture = _load();
  }

  ThemeNotifier.preview(ThemeConfig theme)
    : _persist = false,
      super(ThemeState(currentTheme: theme)) {
    _loadFuture = Future.value();
  }

  Future<void> ensureLoaded() => _loadFuture;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // Load custom themes
    final customsJson = prefs.getString('custom_themes');
    List<ThemeConfig> customs = [];
    if (customsJson != null) {
      try {
        final List decoded = jsonDecode(customsJson);
        customs = decoded.map((e) => ThemeConfig.fromMap(e)).toList();
      } catch (_) {}
    }

    // Load current theme name
    final currentName =
        prefs.getString('current_theme_name') ?? 'theme_crimson_red';

    ThemeConfig? current;
    if (currentName == 'theme_crimson_red' ||
        currentName == 'Crimson Red (Default)')
      current = ThemeConfig.defaultTheme;
    else if (currentName == 'theme_emerald_green' ||
        currentName == 'Emerald Green')
      current = ThemeConfig.emeraldGreen;
    else if (currentName == 'theme_oceanic_blue' ||
        currentName == 'Oceanic Blue')
      current = ThemeConfig.oceanicBlue;
    else if (currentName == 'theme_neon_origami')
      current = ThemeConfig.neonOrigami;
    else {
      current = customs.firstWhere(
        (t) => t.name == currentName,
        orElse: () => ThemeConfig.defaultTheme,
      );
    }

    state = ThemeState(currentTheme: current, customThemes: customs);
  }

  Future<void> _save() async {
    if (!_persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_theme_name', state.currentTheme.name);
    await prefs.setString(
      'custom_themes',
      jsonEncode(state.customThemes.map((e) => e.toMap()).toList()),
    );
  }

  void setTheme(ThemeConfig theme) {
    state = state.copyWith(currentTheme: theme);
    _save();
  }

  void addTheme(ThemeConfig theme) {
    final themes = [...state.customThemes];
    final index = themes.indexWhere((item) => item.name == theme.name);
    if (index >= 0) {
      themes[index] = theme;
    } else {
      themes.add(theme);
    }
    state = state.copyWith(customThemes: themes);
    _save();
  }

  void updateTheme(ThemeConfig theme) {
    addTheme(theme);
    if (state.currentTheme.name == theme.name) {
      state = state.copyWith(currentTheme: theme);
    }
    _save();
  }

  void removeTheme(String name) {
    state = state.copyWith(
      customThemes: state.customThemes.where((t) => t.name != name).toList(),
    );
    if (state.currentTheme.name == name) {
      setTheme(ThemeConfig.defaultTheme);
    }
    _save();
  }

  ThemeConfig importThemeFromJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map)
        throw const FormatException('Expected a JSON object');
      final envelope = Map<String, dynamic>.from(decoded);
      final map = envelope['theme'] is Map
          ? Map<String, dynamic>.from(envelope['theme'] as Map)
          : envelope;
      if (![
        'background',
        'surface',
        'primary',
        'primaryDark',
        'accent',
      ].any(map.containsKey)) {
        throw const FormatException(
          'This JSON file does not contain NextLink theme fields',
        );
      }
      final importedName = map['name']?.toString().trim();
      if (importedName == null || importedName.isEmpty) {
        map['name'] = 'Импортированная тема';
      }
      final theme = ThemeConfig.fromMap(map);
      addTheme(theme);
      return theme;
    } catch (e) {
      throw Exception('Invalid theme JSON: $e');
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>(
  (ref) => ThemeNotifier(),
);
