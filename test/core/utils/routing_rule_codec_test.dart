import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/routing_rule_codec.dart';
import 'package:nextlink/core/providers/rules_provider.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';
import 'package:nextlink/core/engine/config_builder.dart';

void main() {
  test('unconditional Sing-box rule becomes a valid Xray catch-all', () {
    final conditions = RoutingRuleCodec.decode({'outbound': 'direct'});
    expect(RoutingRuleCodec.xray(conditions, 'direct'), {
      'type': 'field', 'outboundTag': 'direct', 'network': 'tcp,udp',
    });
  });
  test('compound domain + IP + port conditions survive persistence and both builders', () {
    final conditions = RoutingRuleCodec.decode({
      'type': 'field',
      'domain': [r'regexp:.*\.ru$', 'domain:example.org'],
      'ip': ['10.0.0.0/8'],
      'port': '80,443,8000-8010',
      'network': 'tcp',
      'outboundTag': 'direct',
    });
    final original = AppRule(
      id: 'rule',
      type: 'Составное правило',
      value: jsonEncode(conditions),
      action: 'DIRECT',
      conditions: conditions,
    );
    final restored = AppRule.fromMap(jsonDecode(jsonEncode(original.toMap())));
    final proxy = VlessConfig.parseUri(
      'vless://00000000-0000-0000-0000-000000000001@example.com:443?security=tls#Test',
    );
    final sb = SingBoxConfigBuilder(
      activeProxy: proxy,
      settings: SettingsState(),
      customRules: [restored],
    ).build();
    final sbRule = (sb['route']['rules'] as List).firstWhere(
      (r) => r['type'] == 'logical' && r['mode'] == 'and',
    );
    expect(sbRule['outbound'], 'direct');
    expect(sbRule['rules'][0]['mode'], 'or');
    expect(sbRule['rules'][1]['ip_cidr'], ['10.0.0.0/8']);
    expect(sbRule['rules'][2]['port_range'], ['8000:8010']);
    final xr = XrayConfigBuilder(
      activeProxy: proxy,
      settings: SettingsState(),
      customRules: [restored],
    ).build();
    final xrRule = (xr['routing']['rules'] as List).firstWhere(
      (r) => r['domain'] is List && r['domain'].contains(r'regexp:.*\.ru$'),
    );
    expect(xrRule['ip'], ['10.0.0.0/8']);
    expect(xrRule['port'], '80,443,8000-8010');
    expect(xrRule['outboundTag'], 'direct');
  });
  test(
    'geosite and literal domain remain alternatives inside the AND rule',
    () {
      final conditions = RoutingRuleCodec.decode({
        'domain': ['geosite:ru', 'full:example.org'],
        'port': 443,
        'outboundTag': 'direct',
      });
      final sb = RoutingRuleCodec.singBox(conditions, 'direct');
      expect(sb['mode'], 'and');
      expect(sb['rules'][0]['mode'], 'or');
      expect(RoutingRuleCodec.ruleSets(sb), ['geosite-ru']);
      final xr = RoutingRuleCodec.xray(conditions, 'direct');
      expect(xr['domain'], containsAll(['geosite:ru', 'full:example.org']));
    },
  );
  test(
    'unsupported conditions fail explicitly instead of weakening a rule',
    () {
      expect(
        () => RoutingRuleCodec.decode({
          'domain': ['example.org'],
          'unknown_condition': ['x'],
          'outbound': 'proxy',
        }),
        throwsFormatException,
      );
      expect(
        () => RoutingRuleCodec.decode({
          'type': 'logical',
          'mode': 'or',
          'rules': [],
          'outbound': 'direct',
        }),
        throwsFormatException,
      );
    },
  );
}
