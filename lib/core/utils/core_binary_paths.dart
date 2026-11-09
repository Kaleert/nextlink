import 'dart:io';

import '../models/proxies/proxy_config.dart';

class CoreBinaryPaths {
  static bool needsAwg(ProxyConfig proxy) =>
      proxy.protocol == 'AMNEZIAWG' ||
      proxy.finalJson['type'] == 'awg' ||
      (proxy.finalJson['endpoints'] as List? ?? []).any(
        (e) => e['type'] == 'awg',
      ) ||
      (proxy.finalJson['outbounds'] as List? ?? []).any(
        (e) => e['type'] == 'awg',
      );
  static Future<String> singBox(
    String appDir,
    Iterable<ProxyConfig> proxies, {
    bool custom = false,
  }) async {
    if (!custom && proxies.any(needsAwg)) {
      final downloaded = File(
        '$appDir/${Platform.isAndroid ? "libawg.so" : "amnezia-box"}',
      );
      if (await downloaded.exists() && await downloaded.length() > 1000)
        return downloaded.path;
      throw const FileSystemException(
        'Ядро WG не загружено. Откройте Настройки → Центр ресурсов → AmneziaWG / WARP',
      );
    }
    return '$appDir/${Platform.isAndroid ? 'libsingbox.so' : 'sing-box'}';
  }
}
