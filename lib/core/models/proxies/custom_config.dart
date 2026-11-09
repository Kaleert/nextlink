// lib/core/models/proxies/custom_config.dart

import 'dart:convert';

import 'proxy_config.dart';

class CustomConfig extends ProxyConfig {
  String jsonString;

  CustomConfig({
    required String protocol,
    required super.name,
    required this.jsonString,
  }) : super(protocol: protocol, address: 'JSON Config', port: 0);

  static CustomConfig parseJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr);
      String protocol = 'CUSTOM';
      if ((map['endpoints'] as List?)?.isNotEmpty == true) {
        protocol =
            map['endpoints'][0]['type']?.toString().toUpperCase() ?? 'CUSTOM';
      } else if (map.containsKey('outbounds') &&
          (map['outbounds'] as List).isNotEmpty) {
        protocol =
            (map['outbounds'][0]['protocol'] ?? map['outbounds'][0]['type'])
                ?.toString()
                .toUpperCase() ??
            'CUSTOM';
      } else {
        protocol =
            (map['protocol'] ?? map['type'])?.toString().toUpperCase() ??
            'CUSTOM';
      }
      String name =
          map['remarks'] ?? map['name'] ?? map['tag'] ?? 'JSON Config';
      final result = CustomConfig(
        protocol: protocol,
        name: name,
        jsonString: jsonStr,
      );
      final endpoint =
          (map['endpoints'] as List?)?.firstOrNull ??
          (map['peers'] != null ? map : null);
      final peer = (endpoint?['peers'] as List?)?.firstOrNull;
      if (peer is Map && peer['address'] is String) {
        result.address = peer['address'];
        result.port = (peer['port'] as num?)?.toInt() ?? 0;
      }
      return result;
    } catch (e) {
      throw FormatException('Невалидный JSON: $e');
    }
  }

  @override
  String toUri() => '';

  @override
  Map<String, dynamic> toOutboundJson() => jsonDecode(jsonString);

  // --- ДОБАВЛЕНО ДЛЯ СОХРАНЕНИЯ В ПАМЯТЬ ---
  @override
  String get uniqueKey => jsonString;

  @override
  Map<String, dynamic> toMap() {
    return {
      'classType': 'CustomConfig',
      'jsonString': jsonString,
      'isActive': isActive,
      'rawJsonOverride': rawJsonOverride,
      'name': name,
    };
  }
}
