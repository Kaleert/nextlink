// lib/core/models/proxies/proxy_config.dart

import 'dart:convert';

abstract class ProxyConfig {
  final String protocol;
  String name;
  String address;
  int port;

  // -100 means no ping attempt has been made; negative values below it are failures.
  int ping = -100;
  bool isPinging = false;
  bool isActive = false;
  String? rawJsonOverride;
  String fp = '';

  ProxyConfig({
    required this.protocol,
    required this.name,
    required this.address,
    required this.port,
  });

  String toUri();
  Map<String, dynamic> toOutboundJson();

  Map<String, dynamic> get finalJson {
    if (rawJsonOverride != null && rawJsonOverride!.isNotEmpty) {
      try {
        return jsonDecode(rawJsonOverride!);
      } catch (e) {}
    }
    return toOutboundJson();
  }

  // --- ДОБАВЛЕНО ДЛЯ СОХРАНЕНИЯ В ПАМЯТЬ ---
  String get uniqueKey => toUri().split('#').first;

  Map<String, dynamic> toMap() {
    return {
      'classType': 'StandardConfig',
      'uri': toUri(),
      'isActive': isActive,
      'rawJsonOverride': rawJsonOverride,
      'name': name,
      'fp': fp,
    };
  }
}
