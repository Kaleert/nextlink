import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/engine/config_builder.dart';
import 'package:nextlink/core/models/proxies/proxy_config.dart';
import 'package:nextlink/core/providers/settings_provider.dart';

class MockProxyConfig extends ProxyConfig {
  final Map<String, dynamic> mockJson;

  MockProxyConfig(this.mockJson)
    : super(protocol: 'CUSTOM', name: 'Mock', address: '1.2.3.4', port: 443);

  @override
  Map<String, dynamic> toOutboundJson() => mockJson;

  @override
  String toUri() => 'mock://1.2.3.4:443#Mock';
}

void main() {
  group('SingBoxConfigBuilder Patching', () {
    test('removes legacy DNS outbounds and preserves DNS rule matching', () {
      final source = <String, dynamic>{
        'outbounds': [
          {'type': 'direct', 'tag': 'proxy'},
          {'type': 'dns', 'tag': 'dns-out'},
        ],
        'route': {
          'final': 'proxy',
          'rules': [
            {
              'domain': ['example.org'],
              'outbound': 'dns-out',
            },
          ],
        },
      };
      final result = SingBoxConfigBuilder(
        activeProxy: MockProxyConfig(source),
        settings: SettingsState(),
        customRules: const [],
      ).build();
      expect(
        (result['outbounds'] as List).any((o) => o['type'] == 'dns'),
        false,
      );
      final rule = (result['route']['rules'] as List).firstWhere(
        (r) =>
            r['domain'] is List &&
            (r['domain'] as List).contains('example.org'),
      );
      expect(rule['action'], 'hijack-dns');
      expect(rule.containsKey('outbound'), false);
      expect((source['outbounds'] as List).length, 2);
    });

    test('should patch routing rules with original inbound tags', () {
      final mockJson = {
        "inbounds": [
          {"type": "tun", "tag": "tun-in"},
        ],
        "route": {
          "rules": [
            {"inbound": "tun-in", "outbound": "proxy"},
          ],
        },
        "dns": {
          "rules": [
            {"inbound": "tun-in", "server": "dns-remote"},
          ],
        },
      };

      final settings = SettingsState(httpPort: 10809, socksPort: 10808);
      final builder = SingBoxConfigBuilder(
        activeProxy: MockProxyConfig(mockJson),
        settings: settings,
        customRules: const [],
      );

      final result = builder.build();

      final rules = result['route']['rules'] as List;
      // Index 0: sniff (if enabled), 1: port 53, 2: ipv6 block (if disabled), 3: bypass lan (if enabled)
      // Our patched rule should be at the end.
      final patchedRule = rules.last;
      expect(patchedRule['inbound'], containsAll(['tun-in', 'http', 'socks']));

      final dnsRules = result['dns']['rules'] as List;
      expect(
        dnsRules.first['inbound'],
        containsAll(['tun-in', 'http', 'socks']),
      );
    });

    test('should patch routing rules with balancer-in', () {
      final mockJson = {
        "route": {
          "rules": [
            {"inbound": "balancer-in", "outbound": "proxy"},
          ],
        },
      };

      final settings = SettingsState();
      final builder = SingBoxConfigBuilder(
        activeProxy: MockProxyConfig(mockJson),
        settings: settings,
        customRules: const [],
      );

      final result = builder.build();
      final rules = result['route']['rules'] as List;
      final patchedRule = rules.last;
      expect(
        patchedRule['inbound'],
        containsAll(['balancer-in', 'http', 'socks']),
      );
    });
  });

  group('XrayConfigBuilder Patching', () {
    test('should patch routing rules with original inbound tags', () {
      final mockJson = {
        "inbounds": [
          {"tag": "proxy-in", "protocol": "socks"},
        ],
        "routing": {
          "rules": [
            {"inboundTag": "proxy-in", "outboundTag": "proxy"},
          ],
        },
      };

      final settings = SettingsState();
      final builder = XrayConfigBuilder(
        activeProxy: MockProxyConfig(mockJson),
        settings: settings,
        customRules: const [],
      );

      final result = builder.build();

      final rules = result['routing']['rules'] as List;
      // Index 0: port 53, 1: ipv6 block (if disabled)
      // Our patched rule should be among the original rules.
      final patchedRule = rules.firstWhere((r) => r['outboundTag'] == 'proxy');
      expect(
        patchedRule['inboundTag'],
        containsAll(['proxy-in', 'http', 'socks']),
      );
    });
  });
}
