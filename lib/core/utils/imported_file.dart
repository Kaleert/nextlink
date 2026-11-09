import 'dart:convert';

/// JSON files may contain either a theme or a tunnel configuration.
bool isThemeDocument(String content) {
  try {
    final decoded = jsonDecode(content.replaceFirst('\uFEFF', '').trim());
    if (decoded is! Map) return false;
    final theme = decoded['theme'] is Map ? decoded['theme'] as Map : decoded;
    if (theme.containsKey('outbounds') ||
        theme.containsKey('endpoints') ||
        theme.containsKey('private_key') ||
        theme.containsKey('Interface'))
      return false;
    return [
      'background',
      'surface',
      'primary',
      'primaryDark',
      'accent',
    ].any(theme.containsKey);
  } catch (_) {
    return false;
  }
}

bool isBackupDocument(String content) {
  try {
    final decoded = jsonDecode(content.replaceFirst('\uFEFF', '').trim());
    return decoded is Map && decoded['format'] == 'nextlink-backup';
  } catch (_) {
    return false;
  }
}
