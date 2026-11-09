import 'proxy_config.dart';

class TrojanConfig extends ProxyConfig {
  String password;
  String network;
  String security;
  String sni;
  String host;
  String path;

  TrojanConfig({
    required super.name,
    required super.address,
    required super.port,
    required this.password,
    this.network = 'tcp',
    this.security = 'tls',
    this.sni = '',
    this.host = '',
    this.path = '',
  }) : super(protocol: 'Trojan');

  static TrojanConfig parseUri(String uriString) {
    final uri = Uri.parse(uriString.trim());
    final query = uri.queryParameters;

    final config = TrojanConfig(
      name: uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'Unnamed Trojan',
      password: uri.userInfo,
      address: uri.host,
      port: uri.port,
      network: query['type'] ?? 'tcp',
      security: query['security'] ?? 'tls',
      sni: query['sni'] ?? '',
      host: query['host'] ?? '',
      path: query['path'] ?? '',
    );
    config.fp = query['fp'] ?? '';
    return config;
  }

  @override
  String toUri() =>
      'trojan://$password@$address:$port?type=$network&security=$security&sni=$sni&fp=$fp#${Uri.encodeComponent(name)}';

  @override
  Map<String, dynamic> toOutboundJson() {
    final streamSettings = <String, dynamic>{
      "network": network,
      "security": security,
    };

    if (network == "ws") {
      streamSettings["wsSettings"] = {
        "path": path.isEmpty ? "/" : path,
        "headers": host.isNotEmpty ? {"Host": host} : {},
      };
    } else if (network == "grpc") {
      streamSettings["grpcSettings"] = {
        "serviceName": path,
        "multiMode": false,
      };
    } else if (network == "xhttp" ||
        network == "splithttp" ||
        network == "httpupgrade") {
      final settingsKey = network == "httpupgrade"
          ? "httpupgradeSettings"
          : "xhttpSettings";
      streamSettings[settingsKey] = {
        if (network != "httpupgrade") "mode": "auto",
        "path": path.isEmpty ? "/" : path,
        "host": host.isNotEmpty ? host : (sni.isNotEmpty ? sni : address),
      };
      if (host.isNotEmpty) {
        streamSettings[settingsKey]["headers"] = {"Host": host};
      }
    }

    if (security == "tls") {
      streamSettings["tlsSettings"] = {
        "serverName": sni.isNotEmpty ? sni : address,
        "fingerprint": fp.isEmpty ? "chrome" : fp,
      };
    }

    return {
      "tag": "proxy",
      "protocol": "trojan",
      "settings": {
        "servers": [
          {"address": address, "port": port, "password": password},
        ],
      },
      "streamSettings": streamSettings,
    };
  }
}
