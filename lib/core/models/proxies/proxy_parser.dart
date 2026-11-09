import 'dart:convert';

import 'proxy_config.dart';
import 'vless_config.dart';
import 'vmess_config.dart';
import 'hy2_config.dart';
import 'trojan_config.dart';
import 'ss_config.dart';
import 'custom_config.dart';
import 'wireguard_config.dart';

class ProxyParser {
  static ProxyConfig parse(String link) {
    final cleanLink = link.replaceFirst('\uFEFF', '').trim();
    if (cleanLink.toLowerCase().startsWith('[interface]') ||
        RegExp(
          r'^(wireguard|wg|warp|awg|amneziawg)://',
          caseSensitive: false,
        ).hasMatch(cleanLink)) {
      return WireGuardConfig.parse(cleanLink);
    }

    if (cleanLink.startsWith('{')) {
      return _parseJsonConfig(
        Map<String, dynamic>.from(jsonDecode(cleanLink) as Map),
      );
    }

    final lowerLink = cleanLink.toLowerCase();
    if (lowerLink.startsWith('vless://'))
      return VlessConfig.parseUri(cleanLink);
    if (lowerLink.startsWith('vmess://'))
      return VmessConfig.parseUri(cleanLink);
    if (lowerLink.startsWith('hy2://') || lowerLink.startsWith('hysteria2://'))
      return HysteriaConfig.parseUri(cleanLink);
    if (lowerLink.startsWith('trojan://'))
      return TrojanConfig.parseUri(cleanLink);
    if (lowerLink.startsWith('ss://'))
      return ShadowsocksConfig.parseUri(cleanLink);

    String errText = cleanLink.length > 20
        ? '${cleanLink.substring(0, 20)}...'
        : cleanLink;
    throw FormatException('Неизвестный формат: $errText');
  }

  static List<ProxyConfig> parseSubscription(String rawSubData) {
    final List<ProxyConfig> servers = [];
    String decodedText = rawSubData.replaceFirst('\uFEFF', '').trim();
    if (decodedText.toLowerCase().startsWith('[interface]')) {
      return [WireGuardConfig.parse(decodedText)];
    }

    if (!decodedText.startsWith('{') && !decodedText.startsWith('[')) {
      try {
        String normalized = decodedText
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .replaceAll(' ', '');
        while (normalized.length % 4 != 0) normalized += '=';
        decodedText = utf8
            .decode(base64Decode(normalized), allowMalformed: true)
            .trim();
      } catch (e) {}
    }

    if (decodedText.toLowerCase().startsWith('[interface]'))
      return [WireGuardConfig.parse(decodedText)];
    if (decodedText.startsWith('{') || decodedText.startsWith('[')) {
      final parsedJson = jsonDecode(decodedText);

      if (parsedJson is List) {
        for (var item in parsedJson) {
          if (item is Map && _isServiceOutbound(item)) continue;
          servers.add(_parseJsonConfig(Map<String, dynamic>.from(item as Map)));
        }
        return servers;
      } else if (parsedJson is Map<String, dynamic>) {
        if (parsedJson.containsKey('outbounds') &&
            (parsedJson.containsKey('routing') ||
                parsedJson.containsKey('route') ||
                parsedJson.containsKey('dns'))) {
          servers.add(_parseJsonConfig(parsedJson));
          return servers;
        } else if (parsedJson.containsKey('outbounds') &&
            parsedJson['outbounds'] is List) {
          for (var item in parsedJson['outbounds']) {
            if (item is Map && _isServiceOutbound(item)) continue;
            servers.add(
              _parseJsonConfig(Map<String, dynamic>.from(item as Map)),
            );
          }
          return servers;
        } else {
          servers.add(_parseJsonConfig(parsedJson));
          return servers;
        }
      }
    }

    final lines = decodedText.split(RegExp(r'\r?\n'));
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        servers.add(parse(line));
      } catch (e) {
        print('Ignored invalid subscription entry');
      }
    }

    return servers;
  }

  static bool _isServiceOutbound(Map map) => const {
    'freedom',
    'blackhole',
    'dns',
    'direct',
    'block',
  }.contains(map['protocol'] ?? map['type']);

  static ProxyConfig _parseJsonConfig(Map<String, dynamic> map) {
    if (map.containsKey('outbounds') || map.containsKey('endpoints')) {
      return CustomConfig.parseJson(jsonEncode(map));
    }
    final kind = (map['type'] ?? map['protocol'])?.toString().toLowerCase();
    final fields = map.keys
        .map((k) => k.toLowerCase().replaceAll('_', ''))
        .toSet();
    if (['wireguard', 'awg'].contains(kind) &&
        map['address'] is List &&
        map['peers'] is List) {
      return CustomConfig.parseJson(jsonEncode(map));
    }
    if (['wireguard', 'warp', 'awg', 'amneziawg'].contains(kind) ||
        fields.contains('privatekey') ||
        fields.contains('interface')) {
      return WireGuardConfig.fromJson(map);
    }
    if (![
      'vless',
      'vmess',
      'hysteria',
      'hysteria2',
      'trojan',
      'shadowsocks',
      'socks',
      'http',
      'tuic',
      'ssh',
      'shadowtls',
      'selector',
      'urltest',
    ].contains(kind)) {
      throw const FormatException(
        'JSON не содержит поддерживаемой конфигурации VPN. Для WARP нужны приватный ключ, адрес туннеля и Peer с Endpoint.',
      );
    }
    return CustomConfig.parseJson(jsonEncode(map));
  }

  static ProxyConfig fromMap(Map<String, dynamic> map) {
    ProxyConfig config;

    if (map['classType'] == 'WireGuardConfig') {
      config = WireGuardConfig.parse(map['configText'] as String);
    } else if (map['classType'] == 'CustomConfig') {
      config = CustomConfig.parseJson(map['jsonString']);
    } else {
      config = parse(map['uri']);
    }

    config.name = map['name'] ?? config.name;
    config.isActive = map['isActive'] ?? false;
    config.rawJsonOverride = map['rawJsonOverride'];
    config.fp = map['fp'] ?? config.fp;

    return config;
  }
}
