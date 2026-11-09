import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/config_share_payload.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';
import 'package:nextlink/core/models/proxies/custom_config.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  test('ordinary URI remains compatible with other clients', () {
    final server = VlessConfig.parseUri(
      'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Test',
    );
    final share = ConfigSharePayload.server(server);
    expect(share.url, server.toUri());
    expect(share.qr, share.url);
    expect(ProxyParser.parseSubscription(share.json), hasLength(1));
    expect(
      QrValidator.validate(data: share.qr).status,
      QrValidationStatus.valid,
    );
  });
  test(
    'JSON overrides are preserved rather than exporting an obsolete URI',
    () {
      final server = VlessConfig.parseUri(
        'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Test',
      );
      final json = server.toOutboundJson();
      json['tag'] = 'Changed';
      server.rawJsonOverride = jsonEncode(json);
      final share = ConfigSharePayload.server(server);
      expect(jsonDecode(share.json)['tag'], 'Changed');
      expect(
        jsonDecode(ConfigSharePayload.decodeQr(share.url))['tag'],
        'Changed',
      );
      expect(share.qr, share.json);
    },
  );
  test('custom JSON round-trips through an import link', () {
    final server = CustomConfig.parseJson(
      '{"outbounds":[{"type":"socks","server":"example.org","server_port":1080,"tag":"proxy"}]}',
    );
    final share = ConfigSharePayload.server(server);
    expect(
      ProxyParser.parseSubscription(ConfigSharePayload.decodeQr(share.url)),
      hasLength(1),
    );
    expect(
      () => ConfigSharePayload.decodeQr('nextlink://disconnect'),
      throwsFormatException,
    );
  });
}
