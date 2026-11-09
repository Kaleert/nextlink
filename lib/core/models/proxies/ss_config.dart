import 'dart:convert';

import 'proxy_config.dart';

class ShadowsocksConfig extends ProxyConfig {
  String method;
  String password;

  ShadowsocksConfig({
    required super.name,
    required super.address,
    required super.port,
    required this.method,
    required this.password,
  }) : super(protocol: 'Shadowsocks');

  static ShadowsocksConfig parseUri(String uriString) {
    final uri = Uri.parse(uriString.trim());
    String method = 'aes-256-gcm';
    String password = '';

    // У Shadowsocks userInfo часто закодирован в Base64 (method:password)
    try {
      String userInfo = uri.userInfo;
      if (!userInfo.contains(':')) {
        String normalized = userInfo;
        while (normalized.length % 4 != 0) normalized += '=';
        userInfo = utf8.decode(base64Decode(normalized));
      }
      final parts = userInfo.split(':');
      if (parts.length == 2) {
        method = parts[0];
        password = parts[1];
      }
    } catch (_) {}

    return ShadowsocksConfig(
      name: uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'Unnamed SS',
      address: uri.host,
      port: uri.port,
      method: method,
      password: password,
    );
  }

  @override
  String toUri() {
    final userPassB64 = base64Encode(utf8.encode('$method:$password'));
    final uri = Uri(
      scheme: 'ss',
      userInfo: userPassB64,
      host: address,
      port: port,
      fragment: Uri.encodeComponent(name),
    );
    return uri.toString();
  }

  @override
  Map<String, dynamic> toOutboundJson() {
    return {
      "tag": "proxy",
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": address,
            "port": port,
            "method": method,
            "password": password,
            "ota": false,
          },
        ],
      },
    };
  }
}
