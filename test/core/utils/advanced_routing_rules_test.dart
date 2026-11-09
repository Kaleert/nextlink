import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/routing_rule_codec.dart';
import 'package:nextlink/core/providers/rules_provider.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/engine/config_builder.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';

void main() {
  test('nested rule-set dependencies are retained and expand for Xray', () {
    final c = RoutingRuleCodec.decode(
      {
        'rule_set': ['outer'],
      },
      definitions: {
        'outer': {
          'tag': 'outer',
          'type': 'inline',
          'rules': [
            {
              'rule_set': ['inner'],
            },
          ],
        },
        'inner': {
          'tag': 'inner',
          'type': 'inline',
          'rules': [
            {
              'domain_suffix': ['example.org'],
            },
          ],
        },
      },
    );
    expect(
      RoutingRuleCodec.definitions(c).keys,
      containsAll(['outer', 'inner']),
    );
    expect(RoutingRuleCodec.xrayRules(c, 'direct').single['domain'], [
      'domain:example.org',
    ]);
  });
  test('nested AND/OR rules expand into equivalent Xray branches', () {
    final c = RoutingRuleCodec.decode({
      'type': 'logical',
      'mode': 'and',
      'rules': [
        {
          'network': ['tcp'],
        },
        {
          'type': 'logical',
          'mode': 'or',
          'rules': [
            {
              'domain_suffix': ['example.org'],
            },
            {
              'domain_regex': ['.*\\.ru\$'],
            },
          ],
        },
      ],
      'outbound': 'direct',
    });
    final rules = RoutingRuleCodec.xrayRules(c, 'direct');
    expect(rules, hasLength(2));
    expect(
      rules.every((r) => r['network'] == 'tcp' && r['outboundTag'] == 'direct'),
      true,
    );
    expect(rules.first['domain'], ['domain:example.org']);
    expect(rules.last['domain'], [r'regexp:.*\.ru$']);
    final native = RoutingRuleCodec.singBox(c, 'direct');
    expect(native['mode'], 'and');
    expect(native['rules'][1]['mode'], 'or');
  });
  test('inversion and process filters are preserved for Sing-box', () {
    final c = RoutingRuleCodec.decode({
      'type': 'logical',
      'mode': 'or',
      'invert': true,
      'rules': [
        {
          'process_name': ['browser'],
        },
        {
          'package_name': ['org.telegram.messenger'],
        },
      ],
      'outbound': 'proxy',
    });
    final native = RoutingRuleCodec.singBox(c, 'proxy');
    expect(native['invert'], true);
    expect(native['rules'][0]['process_name'], ['browser']);
    expect(RoutingRuleCodec.needsSingBox(c), true);
    expect(() => RoutingRuleCodec.xrayRules(c, 'proxy'), throwsFormatException);
  });
  test(
    'a custom remote rule-set remains attached to the generated native config',
    () async {
      final c = RoutingRuleCodec.decode(
        {
          'rule_set': ['custom'],
          'outbound': 'direct',
        },
        definitions: {
          'custom': {
            'tag': 'custom',
            'type': 'remote',
            'format': 'binary',
            'url': 'https://example.org/rules.srs',
            'download_detour': 'direct',
          },
        },
      );
      final json = SingBoxConfigBuilder(
        activeProxy: VlessConfig.parseUri(
          'vless://00000000-0000-0000-0000-000000000001@example.org:443?security=tls#Test',
        ),
        settings: SettingsState(),
        customRules: [
          AppRule(
            id: '1',
            type: 'Compound',
            value: jsonEncode(c),
            action: 'DIRECT',
            conditions: c,
          ),
        ],
      ).build();
      expect(
        json['route']['rule_set'].single['url'],
        'https://example.org/rules.srs',
      );
      expect(RoutingRuleCodec.needsSingBox(c), true);
      final binary = Platform.environment['NEXTLINK_AWG_TEST_BINARY'];
      if (binary != null) {
        final dir = await Directory.systemTemp.createTemp('nextlink-rules-');
        try {
          final file = File('${dir.path}/config.json');
          await file.writeAsString(jsonEncode(json));
          final result = await Process.run(binary, ['check', '-c', file.path]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        } finally {
          await dir.delete(recursive: true);
        }
      }
    },
  );
  test('inline custom rule sets can be expanded for Xray', () {
    final c = RoutingRuleCodec.decode(
      {
        'rule_set': ['inline'],
        'port': 443,
        'outbound': 'direct',
      },
      definitions: {
        'inline': {
          'type': 'inline',
          'tag': 'inline',
          'rules': [
            {
              'domain_suffix': ['a.example'],
            },
            {
              'domain_suffix': ['b.example'],
            },
          ],
        },
      },
    );
    final rules = RoutingRuleCodec.xrayRules(c, 'direct');
    expect(rules, hasLength(2));
    expect(rules.every((r) => r['port'] == '443'), true);
  });
}
