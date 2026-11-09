import 'dart:convert';

import 'proxy_config.dart';

class VmessConfig extends ProxyConfig {
  String uuid;
  int alterId;
  String cipher; // 'auto', 'aes-128-gcm', 'chacha20-poly1305', 'none'

  String network; // 'tcp', 'ws', 'grpc', 'kcp'
  String type; // Тип обфускации или заголовка (none, http, srtp...)
  String host; // Host для HTTP/WS
  String path; // Путь для WS

  String tls; // 'tls' или пустая строка
  String sni;
  String alpn;

  VmessConfig({
    required super.name,
    required super.address,
    required super.port,
    required this.uuid,
    this.alterId = 0,
    this.cipher = 'auto',
    this.network = 'tcp',
    this.type = 'none',
    this.host = '',
    this.path = '',
    this.tls = '',
    this.sni = '',
    this.alpn = '',
  }) : super(protocol: 'VMess');

  static VmessConfig parseUri(String uriString) {
    if (!uriString.trim().toLowerCase().startsWith('vmess://')) {
      throw FormatException('Неверный формат VMess ссылки');
    }

    final base64String = uriString.trim().substring(8);

    String normalizedBase64 = base64String;
    while (normalizedBase64.length % 4 != 0) {
      normalizedBase64 += '=';
    }

    final decodedString = utf8.decode(base64Decode(normalizedBase64));

    final json = jsonDecode(decodedString) as Map<String, dynamic>;

    final config = VmessConfig(
      name: json['ps']?.toString() ?? 'Unnamed VMess',
      address: json['add']?.toString() ?? '',
      port: int.tryParse(json['port']?.toString() ?? '0') ?? 443,
      uuid: json['id']?.toString() ?? '',
      alterId: int.tryParse(json['aid']?.toString() ?? '0') ?? 0,
      cipher:
          json['scy']?.toString() ??
          'auto',
      network: json['net']?.toString() ?? 'tcp',
      type: json['type']?.toString() ?? 'none',
      host: json['host']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      tls: json['tls']?.toString() ?? '',
      sni: json['sni']?.toString() ?? '',
      alpn: json['alpn']?.toString() ?? '',
    );
    config.fp = json['fp']?.toString() ?? '';
    return config;
  }

  @override
  String toUri() {
    final json = {
      "v": "2",
      "ps": name,
      "add": address,
      "port": port,
      "id": uuid,
      "aid": alterId,
      "scy": cipher,
      "net": network,
      "type": type,
      "host": host,
      "path": path,
      "tls": tls,
      "sni": sni,
      "alpn": alpn,
      "fp": fp,
    };

    final jsonString = jsonEncode(json);
    final base64String = base64Encode(utf8.encode(jsonString));

    return 'vmess://$base64String';
  }

  @override
  Map<String, dynamic> toOutboundJson() {
    return {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": address,
            "port": port,
            "users": [
              {"id": uuid, "alterId": alterId, "security": cipher},
            ],
          },
        ],
      },
      "streamSettings": {
        "network": network,
        "security": tls == 'none' ? '' : tls,
        if (network == "ws")
          "wsSettings": {
            "path": path.isEmpty ? "/" : path,
            "headers": host.isNotEmpty ? {"Host": host} : {},
          },
        if (network == "grpc")
          "grpcSettings": {
            "serviceName": path.isNotEmpty ? path : '',
            "multiMode": false,
          },
        if (network == "xhttp" ||
            network == "splithttp" ||
            network == "httpupgrade")
          (network == "httpupgrade"
              ? "httpupgradeSettings"
              : "xhttpSettings"): {
            if (network != "httpupgrade") "mode": "auto",
            "path": path.isEmpty ? "/" : path,
            "host": host.isNotEmpty ? host : (sni.isNotEmpty ? sni : address),
            if (host.isNotEmpty) "headers": {"Host": host},
          },
        if (tls == "tls" || tls == "reality")
          "${tls}Settings": {
            "serverName": sni.isNotEmpty ? sni : address,
            "fingerprint": fp.isEmpty ? "chrome" : fp,
            if (alpn.isNotEmpty) "alpn": alpn.split(','),
          },
      },
    };
  }
}
