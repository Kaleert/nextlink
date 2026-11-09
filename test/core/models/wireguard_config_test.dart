import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/proxies/wireguard_config.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';
import 'package:nextlink/core/engine/config_builder.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/providers/chains_provider.dart';

final key = base64Encode(List.filled(32, 7));
String profile({String extra = '', String reserved = 'Reserved = 1, 2, 255'}) =>
    '''
[Interface]
PrivateKey = $key
Address = 172.16.0.2/32, 2606:4700:110::2/128
DNS = 1.1.1.1
MTU = 1280
$extra
[Peer]
PublicKey = $key
Endpoint = [2606:4700:d0::1]:2408
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
$reserved
''';
void main() {
  test(
    'bare Interface IPs acquire host prefixes without changing the source',
    () {
      final source = profile(extra: 'Jc = 4', reserved: '').replaceFirst(
        '172.16.0.2/32, 2606:4700:110::2/128',
        '172.16.0.2, 2606:4700:110::2',
      );
      final config = WireGuardConfig.parse(source);
      expect(config.protocol, 'AMNEZIAWG');
      expect(config.finalJson['endpoints'].single['address'], [
        '172.16.0.2/32',
        '2606:4700:110::2/128',
      ]);
      expect(config.toUri(), source);
      expect(
        ProxyParser.fromMap(config.toMap())
            .finalJson['endpoints']
            .single['address'],
        ['172.16.0.2/32', '2606:4700:110::2/128'],
      );
    },
  );
  test(
    'explicit prefixes survive and malformed addresses and routes still fail',
    () {
      final mixed = profile().replaceFirst(
        '172.16.0.2/32, 2606:4700:110::2/128',
        '172.16.0.2/24, 2606:4700:110::2',
      );
      expect(
        WireGuardConfig.parse(mixed).finalJson['endpoints'].single['address'],
        ['172.16.0.2/24', '2606:4700:110::2/128'],
      );
      expect(
        () => WireGuardConfig.parse(
          profile().replaceFirst('172.16.0.2/32', '300.16.0.2'),
        ),
        throwsFormatException,
      );
      expect(
        () => WireGuardConfig.parse(
          profile().replaceFirst('172.16.0.2/32', '172.16.0.2/99'),
        ),
        throwsFormatException,
      );
      expect(
        () => WireGuardConfig.parse(
          profile().replaceFirst(
            'AllowedIPs = 0.0.0.0/0, ::/0',
            'AllowedIPs = 172.16.0.2',
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test('imports legacy Sing-box WARP JSON with BOM and retains keys', () {
    final source = {
      'type': 'wireguard',
      'tag': 'WARP JSON',
      'private_key': key,
      'local_address': ['172.16.0.2/32', '2606:4700:110::2/128'],
      'peer_public_key': key,
      'server': 'engage.cloudflareclient.com',
      'server_port': 2408,
      'reserved': [1, 2, 255],
      'mtu': 1280,
    };
    final config = ProxyParser.parseSubscription('\uFEFF${jsonEncode(source)}')
        .single;
    expect(config, isA<WireGuardConfig>());
    expect(config.protocol, 'WARP');
    expect(
      ProxyParser.parseSubscription(
        jsonEncode({
          'outbounds': [
            source,
            {'type': 'direct', 'tag': 'direct'},
            {'type': 'dns', 'tag': 'dns-out'},
          ],
        }),
      ).single.protocol,
      'WARP',
    );
    final restored = ProxyParser.fromMap(config.toMap());
    expect(restored.name, 'WARP JSON');
    final endpoint = restored.finalJson['endpoints'].single;
    expect(endpoint['private_key'], key);
    expect(endpoint['peers'].single['reserved'], [1, 2, 255]);
    expect(endpoint['peers'].single['address'], 'engage.cloudflareclient.com');
  });
  test(
    'migrates full legacy Sing-box WireGuard outbound and preserves route tag',
    () {
      final source = {
        'outbounds': [
          {
            'type': 'wireguard',
            'tag': 'warp',
            'private_key': key,
            'local_address': ['172.16.0.2/32'],
            'peer_public_key': key,
            'server': '162.159.192.1',
            'server_port': 2408,
            'reserved': [1, 2, 3],
          },
          {'type': 'direct', 'tag': 'direct'},
        ],
        'route': {'final': 'warp', 'rules': []},
      };
      final config = ProxyParser.parseSubscription(jsonEncode(source)).single;
      final built = SingBoxConfigBuilder(
        activeProxy: config,
        settings: SettingsState(),
        customRules: [],
      ).build();
      expect(built['endpoints'].single['tag'], 'warp');
      expect(
        built['endpoints'].single['peers'].single['address'],
        '162.159.192.1',
      );
      expect(
        (built['outbounds'] as List).any((o) => o['type'] == 'wireguard'),
        false,
      );
      expect(built['route']['final'], 'warp');
    },
  );
  test(
    'imports JSON Interface and Peer and rejects incomplete account data',
    () {
      final source = {
        'Interface': {
          'PrivateKey': key,
          'Address': ['172.16.0.2'],
          'DNS': ['1.1.1.1'],
        },
        'Peer': {
          'PublicKey': key,
          'Endpoint': '[2606:4700:d0::1]:2408',
          'Reserved': [1, 2, 3],
        },
      };
      final config = ProxyParser.parseSubscription(jsonEncode(source)).single;
      expect(config.finalJson['endpoints'].single['address'], [
        '172.16.0.2/32',
      ]);
      expect(
        () => ProxyParser.parseSubscription(
          jsonEncode({'account_id': 'not-a-tunnel'}),
        ),
        throwsFormatException,
      );
      expect(
        () => ProxyParser.parseSubscription(jsonEncode({'private_key': key})),
        throwsFormatException,
      );
    },
  );

  test('WARP import retains IPv6, reserved bytes, keys, and persistence', () {
    final config = WireGuardConfig.parse(profile(), name: 'My WARP');
    expect(config.protocol, 'WARP');
    expect(config.address, '2606:4700:d0::1');
    expect(config.port, 2408);
    final restored = ProxyParser.fromMap(config.toMap());
    expect(restored.name, 'My WARP');
    expect(restored.uniqueKey, config.uniqueKey);
    final endpoint = restored.finalJson['endpoints'].first;
    expect(endpoint['address'], hasLength(2));
    expect(endpoint['peers'].first['reserved'], [1, 2, 255]);
    expect(endpoint['private_key'], key);
  });
  test('raw and base64 subscription .conf are one profile', () {
    expect(ProxyParser.parseSubscription(profile()), hasLength(1));
    expect(
      ProxyParser.parseSubscription(base64Encode(utf8.encode(profile()))),
      hasLength(1),
    );
  });
  test(
    'invalid keys and reserved bytes fail instead of partially importing',
    () {
      expect(
        () => WireGuardConfig.parse(
          profile().replaceFirst('PrivateKey = $key', 'PrivateKey = invalid'),
        ),
        throwsFormatException,
      );
      expect(
        () => WireGuardConfig.parse(profile(reserved: 'Reserved = 1, 2, 256')),
        throwsFormatException,
      );
      expect(
        () => WireGuardConfig.parse(
          profile().replaceFirst('0.0.0.0/0', '0.0.0.0/100'),
        ),
        throwsFormatException,
      );
    },
  );
  test('Reserved in Interface and split-tunnel DNS are preserved', () {
    final text = profile(reserved: '')
        .replaceFirst('MTU = 1280', 'MTU = 1280\nReserved = AQID')
        .replaceFirst('0.0.0.0/0, ::/0', '10.0.0.0/8')
        .replaceFirst('DNS = 1.1.1.1', 'DNS = 10.9.0.1');
    final config = WireGuardConfig.parse(text);
    final json = config.finalJson;
    expect(json['endpoints'].first['peers'].first['reserved'], [1, 2, 3]);
    expect(json['route']['final'], 'direct');
    expect(json['route']['rules'].first['action'], 'resolve');
    expect(json['route']['rules'][1]['ip_cidr'], ['10.0.0.0/8']);
    expect(json['dns']['servers'][1]['detour'], 'proxy');
    expect(json['dns']['servers'][0]['detour'], isNull);
  });
  test('standalone endpoint JSON is routed through Sing-box endpoint', () {
    final endpoint = WireGuardConfig.parse(profile())
        .finalJson['endpoints']
        .first;
    final config = ProxyParser.parse(jsonEncode(endpoint));
    final result = SingBoxConfigBuilder(
      activeProxy: config,
      settings: SettingsState(),
      customRules: [],
    ).build();
    expect(result['endpoints'].first['type'], 'wireguard');
    expect(result['route']['rules'].last['outbound'], 'proxy');
  });
  test('unsupported AWG 3 parameters fail explicitly', () {
    expect(
      () => WireGuardConfig.parse(profile(extra: 'HeaderProtectionKey = 1234')),
      throwsFormatException,
    );
  });
  test('WireGuard URI imports percent-encoded keys and IPv6', () {
    final uri =
        'wireguard://${Uri.encodeComponent(key)}@[::1]:51820?publickey=${Uri.encodeComponent(key)}&address=10.0.0.2%2F32#Local';
    final config = ProxyParser.parse(uri);
    expect(config.address, '::1');
    expect(config.name, 'Local');
  });
  test('builder routes imported endpoint via proxy without losing peers', () {
    final result = SingBoxConfigBuilder(
      activeProxy: WireGuardConfig.parse(profile()),
      settings: SettingsState(),
      customRules: [],
    ).build();
    expect(result['endpoints'].first['type'], 'wireguard');
    expect(result['route']['final'], 'proxy');
    final rules = result['route']['rules'] as List;
    expect(rules.last['outbound'], 'proxy');
    final resolveIndex = rules.indexWhere((r) => r['action'] == 'resolve');
    final allowedIndex = rules.indexWhere(
      (r) => (r['ip_cidr'] as List? ?? []).contains('0.0.0.0/0'),
    );
    expect(resolveIndex, greaterThanOrEqualTo(0));
    expect(resolveIndex, lessThan(allowedIndex));
    expect(
      rules.any(
        (r) =>
            r['outbound'] == 'proxy' &&
            (r['ip_cidr'] as List? ?? []).contains('0.0.0.0/0'),
      ),
      true,
    );
    expect(result['outbounds'].any((o) => o['type'] == 'wireguard'), false);
    expect(
      result['inbounds'].map((i) => i['type']),
      containsAll(['http', 'socks']),
    );
  });
  test('AWG preserves padding, magic ranges, and junk packet fields', () {
    final config = WireGuardConfig.parse(
      profile(
        extra: 'Jc = 4\nJmin = 40\nJmax = 70\nS1 = 15\nS2 = 18\nH1 = 100-200\nI1 = <b 0xabcdef>',
      ),
    );
    expect(config.protocol, 'AMNEZIAWG');
    final endpoint = config.finalJson['endpoints'].first;
    expect(endpoint['type'], 'awg');
    expect(endpoint['jc'], 4);
    expect(endpoint['h1'], '100-200');
    expect(endpoint['i1'], '<b 0xabcdef>');
    expect(
      SingBoxConfigBuilder(
        activeProxy: config,
        settings: SettingsState(singboxUrl: 'https://example.com/awg-core'),
        customRules: [],
      ).build()['endpoints'].first['type'],
      'awg',
    );
  });
  test('WireGuard endpoint can be the first hop of a Sing-box chain', () {
    final wg = WireGuardConfig.parse(profile());
    final vless = VlessConfig.parseUri(
      'vless://00000000-0000-0000-0000-000000000001@example.com:443?security=tls#Exit',
    );
    final result = SingBoxConfigBuilder(
      activeProxy: vless,
      activeChain: ProxyChain(id: '1', name: 'WG to VLESS', nodes: [wg, vless]),
      settings: SettingsState(),
      customRules: [],
    ).build();
    expect(result['endpoints'].first['tag'], 'chain-node-0');
    expect(
      (result['outbounds'] as List).firstWhere(
        (o) => o['tag'] == 'proxy',
      )['detour'],
      'chain-node-0',
    );
  });
}
