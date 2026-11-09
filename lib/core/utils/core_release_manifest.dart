import 'dart:convert';

class CoreReleaseManifest {
  final String version, file, sha256;
  final int size;
  CoreReleaseManifest(this.version, this.file, this.sha256, this.size);
  static CoreReleaseManifest parse(String text, String architecture) {
    if (text.length > 1024 * 1024)
      throw const FormatException('Манифест ядра слишком большой');
    final data = jsonDecode(text);
    if (data is! Map ||
        data['files'] is! Map ||
        data['version'] is! String ||
        (data['version'] as String).trim().isEmpty)
      throw const FormatException('Неверный манифест ядра');
    final entry = data['files'][architecture];
    if (entry is! Map)
      throw const FormatException('В манифесте нет архитектуры устройства');
    final file = entry['file'];
    final hash = entry['sha256'];
    final size = entry['size'];
    if (file is! String ||
        file.isEmpty ||
        Uri.tryParse(file) == null ||
        Uri.parse(file).hasScheme ||
        file.startsWith('/') ||
        file.contains('\\') ||
        Uri.decodeComponent(file).split('/').contains('..'))
      throw const FormatException('Неверный путь ядра в манифесте');
    if (hash is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
        size is! int ||
        size < 1000)
      throw const FormatException('Неверные размер или контрольная сумма ядра');
    return CoreReleaseManifest(
      data['version'].trim(),
      file,
      hash.toLowerCase(),
      size,
    );
  }

  Map<String, dynamic> artifact() => {
    'file': file,
    'sha256': sha256,
    'size': size,
  };
}
