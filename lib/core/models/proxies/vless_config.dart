import 'proxy_config.dart';

class VlessConfig extends ProxyConfig {
  String uuid;
  String network;
  String security;
  String flow;

  String sni;
  String alpn;
  String pbk;
  String sid;
  String spx;

  String path;
  String host;
  String serviceName;

  VlessConfig({
    required super.name,
    required super.address,
    required super.port,
    required this.uuid,
    this.network = 'tcp',
    this.security = 'none',
    this.flow = '',
    this.sni = '',
    this.alpn = '',
    this.pbk = '',
    this.sid = '',
    this.spx = '',
    this.path = '',
    this.host = '',
    this.serviceName = '',
  }) : super(protocol: 'VLESS');

  static VlessConfig parseUri(String uriString) {
    if (!uriString.trim().toLowerCase().startsWith('vless://')) {
      throw FormatException('Неверный формат VLESS ссылки');
    }

    final uri = Uri.parse(uriString.trim());
    final query = uri.queryParameters;

    final config = VlessConfig(
      name: uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'Unnamed VLESS',
      uuid: uri.userInfo,
      address: uri.host,
      port: uri.port,
      network: query['type'] ?? 'tcp',
      security: query['security'] ?? 'none',
      flow: query['flow'] ?? '',
      sni:
          query['sni'] ??
          query['peer'] ??
          '', // peer - это старое название sni в некоторых клиентах
      alpn: query['alpn'] ?? '',
      pbk: query['pbk'] ?? '',
      sid: query['sid'] ?? '',
      spx: query['spx'] ?? '',
      path: query['path'] ?? '',
      host: query['host'] ?? '',
      serviceName: query['serviceName'] ?? '',
    );
    config.fp = query['fp'] ?? '';
    return config;
  }

  @override
  String toUri() {
    final queryParams = <String, String>{
      if (network.isNotEmpty && network != 'tcp') 'type': network,
      if (security.isNotEmpty && security != 'none') 'security': security,
      if (flow.isNotEmpty) 'flow': flow,
      if (sni.isNotEmpty) 'sni': sni,
      if (alpn.isNotEmpty) 'alpn': alpn,
      if (pbk.isNotEmpty) 'pbk': pbk,
      if (sid.isNotEmpty) 'sid': sid,
      if (fp.isNotEmpty) 'fp': fp,
      if (spx.isNotEmpty) 'spx': spx,
      if (path.isNotEmpty) 'path': path,
      if (host.isNotEmpty) 'host': host,
      if (serviceName.isNotEmpty) 'serviceName': serviceName,
    };

    final uri = Uri(
      scheme: 'vless',
      userInfo: uuid,
      host: address,
      port: port,
      queryParameters: queryParams.isEmpty ? null : queryParams,
      fragment: Uri.encodeComponent(name),
    );
    return uri.toString();
  }

  @override
  Map<String, dynamic> toOutboundJson() {
    final settings = {
      "vnext": [
        {
          "address": address,
          "port": port,
          "users": [
            {
              "id": uuid,
              "encryption": "none",
              if (flow.isNotEmpty && flow != 'none') "flow": flow,
            },
          ],
        },
      ],
    };

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
        "serviceName": serviceName,
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
      var tlsObj = <String, dynamic>{
        "serverName": sni.isNotEmpty ? sni : address,
      };
      if (fp.isNotEmpty) {
        tlsObj["fingerprint"] = fp == 'random' ? 'randomized' : fp;
      }
      if (alpn.isNotEmpty) {
        tlsObj["alpn"] = alpn.split(',');
      }
      streamSettings["tlsSettings"] = tlsObj;
    } else if (security == "reality") {
      streamSettings["realitySettings"] = {
        "serverName": sni.isNotEmpty ? sni : address,
        "fingerprint": fp == 'random'
            ? 'randomized'
            : (fp.isEmpty ? 'randomized' : fp),
        "show": false,
        "publicKey": pbk,
        "shortId": sid,
        "spiderX": spx.isNotEmpty
            ? spx
            : path, // В XHTTP spiderX часто равен path
      };
    }

    return {
      "tag": "proxy",
      "protocol": "vless",
      "settings": settings,
      "streamSettings": streamSettings,
    };
  }
}
