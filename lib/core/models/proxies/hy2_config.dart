import 'proxy_config.dart';

class HysteriaConfig extends ProxyConfig {
  String password;
  String sni;
  bool insecure;
  String obfs;
  String obfsPassword;

  HysteriaConfig({
    required super.name,
    required super.address,
    required super.port,
    required this.password,
    this.sni = '',
    this.insecure = false,
    this.obfs = 'none',
    this.obfsPassword = '',
  }) : super(protocol: 'Hysteria2');

  static HysteriaConfig parseUri(String uriString) {
    if (!uriString.trim().toLowerCase().startsWith('hy2://') &&
        !uriString.trim().toLowerCase().startsWith('hysteria2://')) {
      throw FormatException('Неверный формат Hysteria2 ссылки');
    }

    final uri = Uri.parse(uriString.trim());
    final query = uri.queryParameters;

    final config = HysteriaConfig(
      name: uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'Unnamed HY2',
      password: uri.userInfo,
      address: uri.host,
      port: uri.port,
      sni: query['sni'] ?? '',
      insecure:
          query['insecure'] == '1' ||
          query['allowInsecure'] == '1' ||
          query['insecure'] == 'true',
      obfs: query['obfs'] ?? 'none',
      obfsPassword: query['obfs-password'] ?? '',
    );
    config.fp = query['fp'] ?? '';
    return config;
  }

  @override
  String toUri() {
    final queryParams = <String, String>{
      if (sni.isNotEmpty) 'sni': sni,
      if (insecure) 'insecure': '1',
      if (obfs.isNotEmpty && obfs != 'none') 'obfs': obfs,
      if (obfsPassword.isNotEmpty) 'obfs-password': obfsPassword,
      if (fp.isNotEmpty) 'fp': fp,
    };

    final uri = Uri(
      scheme: 'hysteria2',
      userInfo: password,
      host: address,
      port: port,
      queryParameters: queryParams.isEmpty ? null : queryParams,
      fragment: Uri.encodeComponent(name),
    );
    return uri.toString();
  }

  @override
  Map<String, dynamic> toOutboundJson() {
    return {
      "tag": "proxy",
      "protocol": "hysteria2",
      "settings": {
        "server": address,
        "port": port,
        "password": password,
        "obfs": obfs,
        "obfsPassword": obfsPassword,
      },
      "streamSettings": {
        "network": "quic",
        "security": "tls",
        "tlsSettings": {
          "serverName": sni.isNotEmpty ? sni : address,
          "allowInsecure": insecure,
          "alpn": ["h3"],
        },
      },
    };
  }
}
