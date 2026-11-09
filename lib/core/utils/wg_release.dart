import 'core_release_manifest.dart';

class WgRelease {
  static const baseUrl = 'https://github.com/Kaleert/nextlink-cores/releases/download/cores-v1';
  static const version = '1.260910.0-nextlink-linker1';
  static Uri source(String custom, String architecture) {
    final text =
        (custom.trim().isEmpty ? '$baseUrl/awg-manifest.json' : custom.trim())
            .replaceAll('{arch}', architecture);
    var uri = Uri.tryParse(text);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty)
      throw const FormatException('Укажите HTTP(S)-ссылку на WG');
    final last = uri.path.split('/').last;
    if (uri.path.endsWith('/') || !last.contains('.'))
      uri = uri.replace(
        path:
            '${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}awg-manifest.json',
      );
    return uri;
  }

  static void validateBinary(
    List<int> bytes,
    String architecture, {
    String coreName = 'WG',
  }) {
    if (bytes.length < 1000 ||
        bytes[0] != 0x7f ||
        bytes[1] != 0x45 ||
        bytes[2] != 0x4c ||
        bytes[3] != 0x46 ||
        bytes[5] != 1)
      throw FormatException(
        '$coreName: нужен ELF-бинарник, а не страница или архив',
      );
    final machine = bytes[18] | bytes[19] << 8;
    final expected = {
      'arm64-v8a': 183,
      'armeabi-v7a': 40,
      'x86_64': 62,
      'amd64': 62,
    }[architecture];
    if (expected == null ||
        machine != expected ||
        bytes[4] != (architecture == 'armeabi-v7a' ? 1 : 2))
      throw FormatException(
        'Бинарник $coreName не подходит для архитектуры устройства',
      );
  }

  static Map<String, dynamic> artifact(String manifest, String architecture) {
    return CoreReleaseManifest.parse(manifest, architecture).artifact();
  }
}
