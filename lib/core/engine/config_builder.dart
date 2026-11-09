import '../utils/routing_rule_codec.dart';
import '../utils/lan_proxy_inbounds.dart';
import '../models/proxies/proxy_config.dart';
import '../models/proxies/vless_config.dart';
import '../models/proxies/wireguard_config.dart';
import '../providers/settings_provider.dart';
import '../providers/rules_provider.dart';
import '../providers/chains_provider.dart';

abstract class ConfigBuilder {
  final ProxyConfig activeProxy;
  final SettingsState settings;
  final List<AppRule> customRules;

  ConfigBuilder({
    required this.activeProxy,
    required this.settings,
    required this.customRules,
  });

  Map<String, dynamic> build();
}

// ============================================================================
// SING-BOX BUILDER
// ============================================================================
class SingBoxConfigBuilder extends ConfigBuilder {
  final bool isTest;
  final ProxyChain? activeChain;

  SingBoxConfigBuilder({
    required super.activeProxy,
    required super.settings,
    required super.customRules,
    this.isTest = false,
    this.activeChain,
  });

  void _applySingBoxFragment(List<Map<String, dynamic>> outbounds) {
    if (!settings.fragment) return;
    for (final outbound in outbounds) {
      final type = outbound['type']?.toString().toLowerCase();
      if (type == null || type == 'hysteria2' || type == 'tuic') continue;
      final tls = outbound['tls'];
      if (tls is Map && tls['enabled'] != false) {
        tls['record_fragment'] = true;
      }
    }
  }

  @override
  Map<String, dynamic> build() {
    Map<String, dynamic> rawJson = Map<String, dynamic>.from(
      activeProxy.finalJson,
    );

    if (['wireguard', 'awg'].contains(rawJson['type'])) {
      final endpoint = {...rawJson, 'tag': rawJson['tag'] ?? 'proxy'};
      rawJson = {
        'endpoints': [endpoint],
        'route': {'final': endpoint['tag']},
      };
    }
    if (rawJson.containsKey('endpoints') && rawJson['dns'] == null) {
      rawJson['dns'] = {
        'servers': [
          {'type': 'udp', 'tag': 'direct-dns', 'server': '1.1.1.1'},
        ],
        'final': 'direct-dns',
      };
    }

    rawJson.remove('remarks');
    rawJson.remove('isActive');
    rawJson.remove('isPinging');
    rawJson.remove('ping');
    rawJson.remove('rawJsonOverride');
    rawJson.remove('classType');

    // Some subscriptions (including Xray subscriptions with routing profiles)
    // are returned as Xray JSON even though their Hysteria outbounds require
    // Sing-box. Normalize the Xray schema before the regular Sing-box builder
    // runs so that routing rules and balancers are not silently discarded.
    if (rawJson.containsKey('outbounds') &&
        rawJson['outbounds'] is List &&
        rawJson.containsKey('routing')) {
      rawJson = _normalizeXraySubscription(rawJson);
    }

    final httpPort = isTest ? settings.httpPort + 2 : settings.httpPort;
    final socksPort = isTest ? settings.socksPort + 2 : settings.socksPort;
    const listenIp = "127.0.0.1";

    if (rawJson.containsKey('endpoints') ||
        rawJson.containsKey('route') ||
        (rawJson.containsKey('dns') && !rawJson.containsKey('routing'))) {
      if (rawJson['dns'] != null &&
          rawJson['dns'] is Map &&
          rawJson['dns'].containsKey('fakeip')) {
        final dnsObj = Map<String, dynamic>.from(rawJson['dns']);
        final fakeipParams = dnsObj.remove('fakeip');
        if (fakeipParams is Map) {
          final servers = List<Map<String, dynamic>>.from(
            dnsObj['servers'] ?? [],
          );
          servers.add({
            "tag": "fakeip-dns-auto",
            "type": "fakeip",
            "inet4_range": fakeipParams["inet4_range"] ?? "198.18.0.0/15",
            "inet6_range": fakeipParams["inet6_range"] ?? "fc00::/18",
          });
          dnsObj['servers'] = servers;
          final dnsRules = List<Map<String, dynamic>>.from(
            dnsObj['rules'] ?? [],
          );
          dnsRules.insert(0, {
            "query_type": ["A", "AAAA"],
            "server": "fakeip-dns-auto",
          });
          dnsObj['rules'] = dnsRules;
          rawJson['dns'] = dnsObj;
        }
      }

      final inbounds = (rawJson['inbounds'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final outbounds = (rawJson['outbounds'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (rawJson.containsKey('endpoints')) {
        if (!outbounds.any((e) => e['tag'] == 'direct'))
          outbounds.add({'type': 'direct', 'tag': 'direct'});
        if (!outbounds.any((e) => e['tag'] == 'block'))
          outbounds.add({'type': 'block', 'tag': 'block'});
        rawJson['outbounds'] = outbounds;
      }

      final dnsOutboundTags = outbounds
          .where((o) => o['type'] == 'dns')
          .map((o) => o['tag']?.toString())
          .whereType<String>()
          .toSet();
      outbounds.removeWhere((o) => o['type'] == 'dns');
      // Persist the filtered copy, including chain edits, for every full config.
      rawJson['outbounds'] = outbounds;

      // --- ВНЕДРЕНИЕ ЦЕПОЧЕК ДЛЯ КАСТОМНЫХ КОНФИГОВ (SING-BOX) ---
      if (activeChain != null && activeChain!.nodes.length > 1) {
        final lastChainTag = 'chain-node-${activeChain!.nodes.length - 2}';
        for (int i = 0; i < activeChain!.nodes.length - 1; i++) {
          final node = activeChain!.nodes[i];
          Map<String, dynamic> rawNode = Map<String, dynamic>.from(
            node.finalJson,
          );
          if ((rawNode['endpoints'] as List?)?.isNotEmpty == true) {
            rawNode = Map<String, dynamic>.from(
              rawNode['endpoints'].first as Map,
            );
          }
          if (rawNode.containsKey('outbounds') &&
              rawNode['outbounds'] is List) {
            final outboundsList = rawNode['outbounds'] as List;
            rawNode = outboundsList.firstWhere(
              (o) =>
                  o['protocol'] != 'freedom' &&
                  o['protocol'] != 'blackhole' &&
                  o['type'] != 'direct' &&
                  o['type'] != 'block' &&
                  o['type'] != 'dns',
              orElse: () => outboundsList.isNotEmpty
                  ? outboundsList.first
                  : {"type": "vless"},
            );
          }
          final convertedNode = _convertProxy(rawNode, proxyOverride: node);
          convertedNode['tag'] = 'chain-node-$i';
          if (i > 0) {
            convertedNode['detour'] = 'chain-node-${i - 1}';
          }
          outbounds.insert(i, convertedNode);
        }

        // Xray subscription JSON commonly calls Hysteria v2 "hysteria" while
        // the generated Sing-box outbound is normalized to "hysteria2".
        // Include both spellings when wiring custom-config outbounds into a chain.
        final proxyProtocols = {
          'vless',
          'vmess',
          'trojan',
          'shadowsocks',
          'hysteria',
          'hysteria2',
          'tuic',
          'wireguard',
          'ssh',
          'shadowtls',
          'http',
          'socks',
        };
        for (var o in outbounds) {
          final type = o['type']?.toString();
          if (type != null &&
              proxyProtocols.contains(type) &&
              !o.containsKey('detour') &&
              !o['tag'].toString().startsWith('chain-node-')) {
            o['detour'] = lastChainTag;
          }
        }
      }

      if (activeChain != null && activeChain!.nodes.length > 1) {
        for (final endpoint in (rawJson['endpoints'] as List? ?? [])) {
          endpoint['detour'] = 'chain-node-${activeChain!.nodes.length - 2}';
        }
      }
      _applySingBoxFragment(outbounds);

      final existingInTags = inbounds
          .map((i) => i['tag']?.toString())
          .whereType<String>()
          .toSet();
      String httpTag = existingInTags.contains('http') ? 'app-http' : 'http';
      String socksTag = existingInTags.contains('socks')
          ? 'app-socks'
          : 'socks';

      inbounds.addAll([
        ...LanProxyInbounds.singBox(settings, isTest: isTest),
        {
          "type": "http",
          "tag": httpTag,
          "listen": listenIp,
          "listen_port": httpPort,
        },
        {
          "type": "socks",
          "tag": socksTag,
          "listen": listenIp,
          "listen_port": socksPort,
        },
      ]);
      rawJson['inbounds'] = inbounds;

      String? mainTarget;
      final routeObj = Map<String, dynamic>.from(
        rawJson['route'] as Map<String, dynamic>? ?? {"rules": []},
      );
      final balancers = (routeObj['balancers'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final endpointTags = (rawJson['endpoints'] as List? ?? [])
          .map((e) => e['tag']?.toString())
          .whereType<String>()
          .toSet();
      final outboundTags =
          outbounds.map((o) => o['tag']?.toString()).whereType<String>().toSet()
            ..addAll(endpointTags);
      final balancerTags = {
        ...balancers.map((b) => b['tag']?.toString()).whereType<String>(),
        ...outbounds
            .where((o) => ['urltest', 'selector'].contains(o['type']))
            .map((o) => o['tag']?.toString())
            .whereType<String>(),
      };

      if (endpointTags.isNotEmpty &&
          ['direct', 'block'].contains(routeObj['final'])) {
        mainTarget = endpointTags.first;
      } else if (outboundTags.contains(routeObj['final'])) {
        mainTarget = routeObj['final'];
      } else if (endpointTags.isNotEmpty) {
        mainTarget = endpointTags.first;
      } else if (balancers.isNotEmpty) {
        mainTarget = balancers.first['tag'];
      } else if (balancerTags.isNotEmpty) {
        mainTarget = balancerTags.first;
      } else {
        mainTarget = outbounds.firstWhere(
          (o) =>
              !['direct', 'block', 'dns'].contains(o['type']?.toString()) &&
              !o['tag'].toString().startsWith('chain-node-'),
          orElse: () =>
              outbounds.isNotEmpty ? outbounds.first : {"tag": "proxy"},
        )['tag'];
      }

      // Делаем глубокую копию правил для безопасности
      final rules = (routeObj['rules'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      bool isProxyIp =
          RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(activeProxy.address) ||
          activeProxy.address.contains(':');

      final safetyBridge = [
        if (isProxyIp)
          {
            "ip_cidr": [
              "${activeProxy.address}/${activeProxy.address.contains(':') ? 128 : 32}",
            ],
            "outbound": "direct",
          }
        else
          {
            "domain": [activeProxy.address],
            "outbound": "direct",
          },
        {"port": 53, "action": "hijack-dns"},
      ];

      final customSbRules = customRules
          .map((r) {
            String rawValue = r.value;
            String? chainTag;
            if (r.action == 'CHAIN') {
              final sep = rawValue.indexOf('=>');
              if (sep >= 0) {
                chainTag = rawValue.substring(sep + 2).trim();
                rawValue = rawValue.substring(0, sep).trim();
              }
            }
            final String tag = r.action == 'PROXY'
                ? (mainTarget ?? 'proxy')
                : (r.action == 'CHAIN'
                      ? (chainTag ?? 'proxy')
                      : r.action.toLowerCase());
            if (r.conditions != null)
              return RoutingRuleCodec.singBox(r.conditions!, tag);
            List<String> values = rawValue
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            Map<String, dynamic> rule = {"outbound": tag};

            if (r.type == 'GeoSite')
              rule["rule_set"] = values.map((e) => "geosite-$e").toList();
            if (r.type == 'GeoIP')
              rule["rule_set"] = values.map((e) => "geoip-$e").toList();
            if (r.type == 'Domain Keyword') rule["domain_keyword"] = values;
            if (r.type == 'Port') {
              List<int> ports = values
                  .map((e) => int.tryParse(e))
                  .whereType<int>()
                  .toList();
              if (ports.isNotEmpty) rule["port"] = ports;
            }
            return rule.length > 1 ? rule : <String, dynamic>{};
          })
          .where((e) => e.isNotEmpty)
          .toList();

      final usedRuleSets = <String>{
        for (final rule in customSbRules) ...RoutingRuleCodec.ruleSets(rule),
      };
      for (final r in customRules) {
        if (r.type == 'GeoSite' || r.type == 'GeoIP') {
          final prefix = r.type == 'GeoSite' ? 'geosite' : 'geoip';
          for (final v in r.value.split(',')) {
            final n = v.trim();
            if (n.isNotEmpty) usedRuleSets.add('$prefix-$n');
          }
        }
      }

      List<String> getRuleSetList(dynamic rs) {
        if (rs == null) return [];
        if (rs is String) return [rs];
        if (rs is List) return rs.map((e) => e.toString()).toList();
        return [];
      }

      // --- МИГРАЦИЯ ПРАВИЛ ИЗ ПОДПИСКИ (SING-BOX) ---
      for (var rule in rules) {
        if (dnsOutboundTags.contains(rule['outbound'])) {
          rule.remove('outbound');
          rule['action'] = 'hijack-dns';
        }

        if (rule.containsKey('inbound')) {
          final inbs = (rule['inbound'] is List)
              ? (rule['inbound'] as List).map((e) => e.toString()).toList()
              : [rule['inbound'].toString()];
          if (!inbs.contains(httpTag)) inbs.add(httpTag);
          if (!inbs.contains(socksTag)) inbs.add(socksTag);
          rule['inbound'] = inbs;
        }

        if (rule.containsKey('geosite')) {
          final gs = rule['geosite'];
          List<String> values = gs is List
              ? gs.map((e) => e.toString()).toList()
              : [gs.toString()];
          final tags = values.map((v) => 'geosite-$v').toList();
          final currentRs = getRuleSetList(rule['rule_set']);
          currentRs.addAll(tags);
          rule['rule_set'] = currentRs;
          rule.remove('geosite');
          usedRuleSets.addAll(tags);
        }
        if (rule.containsKey('geoip')) {
          final gi = rule['geoip'];
          List<String> values = gi is List
              ? gi.map((e) => e.toString()).toList()
              : [gi.toString()];
          final tags = values.map((v) => 'geoip-$v').toList();
          final currentRs = getRuleSetList(rule['rule_set']);
          currentRs.addAll(tags);
          rule['rule_set'] = currentRs;
          rule.remove('geoip');
          usedRuleSets.addAll(tags);
        }
      }

      if (usedRuleSets.isNotEmpty) {
        final ruleSetList =
            (routeObj['rule_set'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final r in customRules) {
          if (r.conditions == null) continue;
          for (final def in RoutingRuleCodec.definitions(
            r.conditions!,
          ).values) {
            final existing = ruleSetList
                .where((v) => v['tag'] == def['tag'])
                .toList();
            if (existing.isEmpty) {
              ruleSetList.add(def);
            } else if (existing.single.toString() != def.toString()) {
              throw FormatException('Конфликт rule-set: ${def['tag']}');
            }
          }
        }
        for (final name in usedRuleSets) {
          if (ruleSetList.any((e) => e['tag'] == name)) continue;
          final isGeoSite = name.startsWith('geosite-');
          final base = isGeoSite
              ? 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set'
              : 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set';
          ruleSetList.add({
            "tag": name,
            "type": "remote",
            "format": "binary",
            "url": "$base/$name.srs",
            "download_detour": "direct",
            "update_interval": "7d",
          });
        }
        routeObj['rule_set'] = ruleSetList;
      }

      final interceptTarget =
          endpointTags.isNotEmpty && routeObj['final'] != null
          ? routeObj['final']
          : mainTarget;
      final interceptRule =
          (mainTarget != null &&
              (outboundTags.contains(mainTarget) ||
                  balancerTags.contains(mainTarget)))
          ? {
              "inbound": [httpTag, socksTag],
              "outbound": interceptTarget,
            }
          : null;

      routeObj['rules'] = [
        {
          "inbound": [httpTag, socksTag],
          "action": "sniff",
          "sniffer": ["http", "tls", "quic"],
        },
        ...safetyBridge,
        if (settings.blockQuic)
          {"network": "udp", "port": 443, "outbound": "block"},
        if (!settings.ipv6)
          {
            "ip_cidr": ["::/0"],
            "outbound": "block",
          },
        if (settings.useRouting && settings.bypassLan)
          {"ip_is_private": true, "outbound": "direct"},
        ...customSbRules,
        ...rules,
        if (interceptRule != null) interceptRule,
      ];

      routeObj['auto_detect_interface'] = false;
      if (routeObj['rules'] is List) {
        (routeObj['rules'] as List).removeWhere(
          (r) =>
              r is Map && (r.containsKey('geosite') || r.containsKey('geoip')),
        );
      }

      rawJson['route'] =
          routeObj; // Применяем обновленный routeObj к итоговому конфигу
      rawJson.remove('experimental');
      rawJson['log'] = {"level": settings.logLevel};

      if (rawJson['dns'] != null) {
        rawJson['dns'] = Map<String, dynamic>.from(rawJson['dns'] as Map);
        if (rawJson['dns']['rules'] is List) {
          final dnsRules = (rawJson['dns']['rules'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          for (final rule in dnsRules) {
            final inbound = rule['inbound'];
            if (inbound == null) continue;
            rule['inbound'] = {
              ...(inbound is List ? inbound : [inbound]),
              httpTag,
              socksTag,
            }.toList();
          }
          rawJson['dns']['rules'] = dnsRules;
          (rawJson['dns']['rules'] as List).removeWhere(
            (r) =>
                r is Map &&
                (r.containsKey('geosite') || r.containsKey('geoip')),
          );
        }
        if (rawJson['dns']['servers'] is List) {
          for (var server in rawJson['dns']['servers']) {
            if (server is Map && server['detour'] == 'direct') {
              server.remove('detour');
            }
          }
        }
      }

      return _promoteEndpoints(rawJson);
    }

    final List<Map<String, dynamic>> compiledOutbounds = [];

    if (activeChain != null && activeChain!.nodes.isNotEmpty) {
      for (int i = 0; i < activeChain!.nodes.length; i++) {
        final node = activeChain!.nodes[i];
        Map<String, dynamic> rawNode = Map<String, dynamic>.from(
          node.finalJson,
        );
        rawNode.remove('remarks');
        rawNode.remove('isActive');
        rawNode.remove('isPinging');
        rawNode.remove('ping');
        rawNode.remove('rawJsonOverride');
        rawNode.remove('classType');

        if ((rawNode['endpoints'] as List?)?.isNotEmpty == true) {
          rawNode = Map<String, dynamic>.from(
            rawNode['endpoints'].first as Map,
          );
        }
        if (rawNode.containsKey('outbounds') && rawNode['outbounds'] is List) {
          final outboundsList = rawNode['outbounds'] as List;
          rawNode = outboundsList.firstWhere(
            (o) => o['protocol'] != 'freedom' && o['protocol'] != 'blackhole',
            orElse: () => outboundsList.isNotEmpty
                ? outboundsList.first
                : {"protocol": "vless"},
          );
        }

        final convertedNode = _convertProxy(rawNode, proxyOverride: node);
        final String nodeTag = (i == activeChain!.nodes.length - 1)
            ? 'proxy'
            : 'chain-node-$i';
        convertedNode['tag'] = nodeTag;

        if (i > 0) {
          final String prevTag = 'chain-node-${i - 1}';
          convertedNode['detour'] = prevTag;
        }

        compiledOutbounds.add(convertedNode);
      }
    } else {
      Map<String, dynamic> proxyOutbound = Map<String, dynamic>.from(rawJson);
      if (proxyOutbound.containsKey('outbounds') &&
          proxyOutbound['outbounds'] is List) {
        final outboundsList = proxyOutbound['outbounds'] as List;
        proxyOutbound = outboundsList.firstWhere(
          (o) => o['protocol'] != 'freedom' && o['protocol'] != 'blackhole',
          orElse: () => outboundsList.isNotEmpty
              ? outboundsList.first
              : {"protocol": "vless"},
        );
      }

      final convertedOutbound = _convertProxy(proxyOutbound);
      convertedOutbound['tag'] = 'proxy';

      bool isVision =
          activeProxy is VlessConfig &&
          (activeProxy as VlessConfig).flow.contains('vision');
      String outType =
          convertedOutbound['type']?.toString().toLowerCase() ?? '';
      bool supportsMux = [
        'vless',
        'vmess',
        'trojan',
        'shadowsocks',
      ].contains(outType);

      if (settings.singboxMux && !isVision && supportsMux) {
        convertedOutbound['multiplex'] = {
          "enabled": true,
          "protocol": settings.singboxMuxProtocol,
          "max_connections": settings.singboxMuxMaxConnections,
          "min_streams": settings.singboxMuxMinStreams,
        };
      }

      if (settings.tcpFastOpen) convertedOutbound['tcp_fast_open'] = true;

      compiledOutbounds.add(convertedOutbound);
    }

    _applySingBoxFragment(compiledOutbounds);

    final Set<String> availableOutboundTags = {'proxy', 'direct', 'block'};

    var rules = <Map<String, dynamic>>[];
    var ruleSets = <Map<String, dynamic>>[];

    if (settings.sniffing && settings.packetAnalysis) {
      rules.add({
        "inbound": ["http", "socks"],
        "action": "sniff",
        "sniffer": ["http", "tls", "quic"],
      });
    }

    if (settings.blockQuic) {
      rules.add({"network": "udp", "port": 443, "outbound": "block"});
    }
    rules.add({"port": 53, "action": "hijack-dns"});
    if (!settings.ipv6)
      rules.add({
        "ip_cidr": ["::/0"],
        "outbound": "block",
      });

    for (var r in customRules) {
      String rawValue = r.value;
      String? chainTag;
      if (r.action == 'CHAIN') {
        final sep = rawValue.indexOf('=>');
        if (sep >= 0) {
          chainTag = rawValue.substring(sep + 2).trim();
          rawValue = rawValue.substring(0, sep).trim();
        }
      }

      String tag;
      if (r.action == 'PROXY') {
        tag = 'proxy';
      } else if (r.action == 'CHAIN') {
        tag = (chainTag != null && availableOutboundTags.contains(chainTag))
            ? chainTag
            : 'proxy';
      } else {
        tag = r.action.toLowerCase();
      }

      if (r.conditions != null) {
        final compiled = RoutingRuleCodec.singBox(r.conditions!, tag);
        for (final def in RoutingRuleCodec.definitions(r.conditions!).values) {
          if (!ruleSets.any((v) => v['tag'] == def['tag'])) ruleSets.add(def);
        }

        for (final name in RoutingRuleCodec.ruleSets(compiled)) {
          if (ruleSets.any((rs) => rs['tag'] == name)) continue;
          final source = name.startsWith('geosite-')
              ? 'sing-geosite'
              : 'sing-geoip';
          ruleSets.add({
            'tag': name,
            'type': 'remote',
            'format': 'binary',
            'url':
                'https://raw.githubusercontent.com/SagerNet/$source/rule-set/$name.srs',
          });
        }
        rules.add(compiled);
        continue;
      }
      List<String> values = rawValue
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (values.isEmpty) continue;

      if (r.type == 'GeoSite') {
        final tags = <String>[];
        for (final v in values) {
          final t = 'geosite-${v.toLowerCase()}';
          if (!ruleSets.any((rs) => rs['tag'] == t)) {
            ruleSets.add({
              "tag": t,
              "type": "remote",
              "format": "binary",
              "url":
                  "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-$v.srs",
            });
          }
          tags.add(t);
        }
        rules.add({"rule_set": tags, "outbound": tag});
      } else if (r.type == 'GeoIP') {
        final tags = <String>[];
        for (final v in values) {
          final t = 'geoip-${v.toLowerCase()}';
          if (!ruleSets.any((rs) => rs['tag'] == t)) {
            ruleSets.add({
              "tag": t,
              "type": "remote",
              "format": "binary",
              "url":
                  "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-$v.srs",
            });
          }
          tags.add(t);
        }
        rules.add({"rule_set": tags, "outbound": tag});
      } else if (r.type == 'Domain Keyword') {
        rules.add({"domain_keyword": values, "outbound": tag});
      } else if (r.type == 'Port') {
        List<int> ports = values
            .map((e) => int.tryParse(e))
            .whereType<int>()
            .toList();
        if (ports.isNotEmpty) rules.add({"port": ports, "outbound": tag});
      }
    }

    final bypassAddresses = <String>{};
    if (activeChain != null && activeChain!.nodes.isNotEmpty) {
      for (final n in activeChain!.nodes) {
        if (n.address.isNotEmpty && n.address != 'JSON Config') {
          bypassAddresses.add(n.address);
        }
      }
    } else if (activeProxy.protocol != 'CUSTOM' &&
        activeProxy.address.isNotEmpty &&
        activeProxy.address != 'JSON Config') {
      bypassAddresses.add(activeProxy.address);
    }

    for (final addr in bypassAddresses) {
      bool isIp =
          RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(addr) || addr.contains(':');
      if (isIp) {
        rules.add({
          "ip_cidr": ["$addr/${addr.contains(':') ? 128 : 32}"],
          "outbound": "direct",
        });
      } else {
        rules.add({
          "domain": [addr],
          "outbound": "direct",
        });
      }
    }

    if (settings.useRouting) {
      if (settings.bypassLan) {
        rules.add({"ip_is_private": true, "outbound": "direct"});
        rules.add({"geosite": "private", "outbound": "direct"});
      }
      if (settings.ruleOrder == 'Proxy -> Direct -> Block') {
        rules.add({"outbound": "proxy"});
      }
    }

    final dnsServers = [
      {
        "tag": "remote-dns",
        "type": settings.remoteDns.startsWith('http') ? 'https' : 'udp',
        "server": settings.remoteDns,
      },
      if (settings.useLocalDns)
        {
          "tag": "local-dns",
          "type": settings.localDnsServer.startsWith('http') ? 'https' : 'udp',
          "server": settings.localDnsServer,
        },
      {"tag": "direct-dns", "type": "udp", "server": "8.8.8.8"},
      if (settings.fakeDns)
        {
          "tag": "fakeip-dns",
          "type": "fakeip",
          "inet4_range": "198.18.0.0/15",
          "inet6_range": "fc00::/18",
        },
    ];

    rules.removeWhere(
      (r) => r.containsKey('geosite') || r.containsKey('geoip'),
    );

    return _promoteEndpoints({
      "log": {"level": settings.logLevel},
      "dns": {
        "servers": dnsServers,
        "final": "remote-dns",
        "strategy": _singBoxDnsStrategy,
        "rules": [
          for (final addr in bypassAddresses)
            if (!RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(addr) &&
                !addr.contains(':'))
              {
                "domain": [addr],
                "server": "direct-dns",
              },
          if (settings.fakeDns)
            {
              "query_type": ["A", "AAAA"],
              "server": "fakeip-dns",
            },
        ],
      },
      "inbounds": [
        ...LanProxyInbounds.singBox(settings, isTest: isTest),
        {
          "type": "http",
          "tag": "http",
          "listen": listenIp,
          "listen_port": httpPort,
        },
        {
          "type": "socks",
          "tag": "socks",
          "listen": listenIp,
          "listen_port": socksPort,
        },
      ],
      "outbounds": [
        ...compiledOutbounds,
        {"type": "direct", "tag": "direct"},
        {"type": "block", "tag": "block"},
      ],
      "route": {
        "rules": rules,
        if (ruleSets.isNotEmpty) "rule_set": ruleSets,
        "auto_detect_interface": false,
        "default_domain_resolver": "remote-dns",
        "final": "proxy",
      },
    });
  }

  Map<String, dynamic> _promoteEndpoints(Map<String, dynamic> config) {
    final outbounds = List<Map<String, dynamic>>.from(
      config['outbounds'] as List? ?? [],
    );
    final endpoints = List<Map<String, dynamic>>.from(
      config['endpoints'] as List? ?? [],
    );
    for (final outbound in outbounds.where(
      (e) => ['wireguard', 'awg'].contains(e['type']),
    )) {
      final legacy =
          outbound.containsKey('local_address') ||
          outbound.containsKey('peer_public_key') ||
          outbound.containsKey('server');
      final endpoint = legacy && outbound['type'] == 'wireguard'
          ? Map<String, dynamic>.from(
              (WireGuardConfig.fromJson(outbound).toOutboundJson()['endpoints']
                          as List)
                      .first
                  as Map,
            )
          : Map<String, dynamic>.from(outbound);
      endpoint['tag'] = outbound['tag'];
      for (final key in ['detour', 'domain_resolver', 'connect_timeout']) {
        if (outbound.containsKey(key)) endpoint[key] = outbound[key];
      }
      if (endpoint['domain_resolver'] == 'direct-dns' &&
          !(config['dns']?['servers'] as List? ?? []).any(
            (s) => s['tag'] == 'direct-dns',
          )) {
        endpoint.remove('domain_resolver');
      }
      endpoints.add(endpoint);
    }
    outbounds.removeWhere((e) => ['wireguard', 'awg'].contains(e['type']));
    config['outbounds'] = outbounds;
    if (endpoints.isNotEmpty) config['endpoints'] = endpoints;
    return config;
  }

  String get _singBoxDnsStrategy {
    if (settings.ipType == 'IPv6') return 'ipv6_only';
    if (settings.ipType == 'Auto') return 'prefer_ipv4';
    return 'ipv4_only';
  }

  Map<String, dynamic> _convertProxy(
    Map<String, dynamic> xray, {
    ProxyConfig? proxyOverride,
  }) {
    if (xray['type'] != null) return Map<String, dynamic>.from(xray);
    final proxy = proxyOverride ?? activeProxy;
    final protocol = xray['protocol']?.toString().toLowerCase() ?? 'vless';
    final stream = xray['streamSettings'] ?? {};
    final security = stream['security'] ?? 'none';
    final Map<String, dynamic> base = {"tag": "proxy"};

    if (protocol == 'hysteria2' || protocol == 'hysteria') {
      final stngs = xray['settings'] ?? {};
      final tls = stream['tlsSettings'] ?? {};
      final hyStngs = stream['hysteriaSettings'] ?? {};

      base.addAll({
        "type": "hysteria2",
        "server": stngs['server'] ?? stngs['address'] ?? proxy.address,
        "server_port": stngs['port'] ?? proxy.port,
        "password": stngs['password'] ?? hyStngs['auth'] ?? '',
        "up_mbps": 100,
        "down_mbps": 100,
        "tls": {
          "enabled": true,
          "server_name":
              tls['serverName'] ??
              stngs['sni'] ??
              stngs['server'] ??
              stngs['address'] ??
              proxy.address,
          "insecure": tls['allowInsecure'] ?? false,
          "alpn": ["h3"],
        },
      });

      if (stngs['obfs'] != null && stngs['obfs'] != 'none') {
        base['obfs'] = {
          "type": stngs['obfs'],
          "password": stngs['obfsPassword'],
        };
      }
      return base;
    }

    if (protocol == 'shadowsocks' || protocol == 'ss') {
      final stngs = xray['settings'] ?? {};
      final srv = (stngs['servers'] as List?)?.isNotEmpty == true
          ? stngs['servers'][0]
          : null;
      if (srv == null) return xray;

      base.addAll({
        "type": "shadowsocks",
        "server": srv['address'] ?? proxy.address,
        "server_port": srv['port'] ?? proxy.port,
        "method": srv['method'] ?? 'aes-256-gcm',
        "password": srv['password'] ?? '',
      });
      if (srv['plugin'] != null && srv['plugin'].toString().isNotEmpty) {
        final pluginStr = srv['plugin'].toString();
        final parts = pluginStr.split(';');
        base['plugin'] = parts.first;
        if (parts.length > 1) {
          base['plugin_opts'] = parts.sublist(1).join(';');
        }
      }
      return base;
    }

    if (protocol == 'vless' || protocol == 'vmess' || protocol == 'trojan') {
      final stngs = xray['settings'] ?? {};
      final vnext = stngs['vnext']?[0] ?? stngs['servers']?[0];
      if (vnext == null) return xray;
      final user = vnext['users']?[0] ?? vnext;

      base.addAll({
        "type": protocol,
        "server": vnext['address'],
        "server_port": vnext['port'],
      });

      if (protocol == 'vless') base['uuid'] = user['id'];
      if (protocol == 'vmess') {
        base['uuid'] = user['id'];
        base['security'] = user['security'] ?? 'auto';
        base['alter_id'] = user['alterId'] ?? 0;
      }
      if (protocol == 'trojan') base['password'] = user['password'];

      if (user['flow'] != null && user['flow'] != "")
        base['flow'] = user['flow'];

      if (security == 'tls' || security == 'reality') {
        final tlsSettings =
            stream['tlsSettings'] ?? stream['realitySettings'] ?? {};
        String fp = tlsSettings['fingerprint'] ?? "";
        if (fp.isEmpty) fp = proxy.fp;
        if (fp.isEmpty) fp = 'chrome';

        final tlsObj = {
          "enabled": true,
          "server_name": tlsSettings['serverName'] ?? vnext['address'],
          "utls": {"enabled": true, "fingerprint": fp},
        };
        if (security == 'reality') {
          tlsObj['reality'] = {
            "enabled": true,
            "public_key": tlsSettings['publicKey'],
            "short_id": tlsSettings['shortId'],
          };
        }
        base['tls'] = tlsObj;
      }

      if (stream['network'] == 'ws') {
        base['transport'] = {
          "type": "ws",
          "path": stream['wsSettings']?['path'] ?? "/",
          "headers": stream['wsSettings']?['headers'] ?? {},
        };
      } else if (stream['network'] == 'grpc') {
        base['transport'] = {
          "type": "grpc",
          "service_name": stream['grpcSettings']?['serviceName'] ?? "",
        };
      } else if (stream['network'] == 'xhttp' ||
          stream['network'] == 'splithttp' ||
          stream['network'] == 'httpupgrade') {
        // --- ФИКС ДЛЯ ОШИБКИ 400 Bad Request В SING-BOX HTTPUPGRADE / XHTTP ---
        final xStngs =
            stream['xhttpSettings'] ?? stream['httpupgradeSettings'] ?? {};
        String path = xStngs['path']?.toString() ?? "/";
        String host = xStngs['host']?.toString() ?? "";
        Map<String, dynamic> headers = {};

        if (xStngs['headers'] != null && xStngs['headers'] is Map) {
          headers = Map<String, dynamic>.from(xStngs['headers']);
          if (host.isEmpty) {
            final hostKey = headers.keys.firstWhere(
              (k) => k.toLowerCase() == 'host',
              orElse: () => '',
            );
            if (hostKey.isNotEmpty) host = headers[hostKey].toString();
          }
        }

        if (host.isEmpty) {
          final tls = stream['tlsSettings'] ?? stream['realitySettings'] ?? {};
          host = tls['serverName']?.toString() ?? "";
        }

        if (host.isEmpty) {
          host = proxyOverride?.address ?? activeProxy.address;
        }

        // ВАЖНО: Удаляем Host из словаря headers! Sing-box сам добавит его из поля 'host' объекта transport.
        // Если оставить его в headers, запрос будет дублировать Host: ..., что вызывает 400 Bad Request на сервере.
        Map<String, dynamic> finalHeaders = {};
        headers.forEach((key, value) {
          if (key.toLowerCase() != 'host') {
            finalHeaders[key] = value is List ? value : [value.toString()];
          }
        });

        base['transport'] = {
          "type": "httpupgrade", // Sing-box лучше всего эмулирует xhttp через httpupgrade
          "path": path,
          "host": host,
        };
        if (finalHeaders.isNotEmpty) {
          base['transport']['headers'] = finalHeaders;
        }
      }
      return base;
    }

    return xray;
  }

  Map<String, dynamic> _normalizeXraySubscription(Map<String, dynamic> source) {
    final outbounds = <Map<String, dynamic>>[];
    final originalOutbounds = (source['outbounds'] as List).whereType<Map>();

    for (final item in originalOutbounds) {
      final outbound = Map<String, dynamic>.from(item);
      final protocol = outbound['protocol']?.toString().toLowerCase();
      final tag = outbound['tag']?.toString();
      if (tag == null) continue;

      if (protocol == 'freedom') {
        outbounds.add({'type': 'direct', 'tag': tag});
      } else if (protocol == 'blackhole') {
        outbounds.add({'type': 'block', 'tag': tag});
      } else if (protocol == 'dns') {
        outbounds.add({'type': 'dns', 'tag': tag});
      } else {
        final converted = _convertProxy(outbound);
        converted['tag'] = tag;
        outbounds.add(converted);
      }
    }

    final availableTags = outbounds.map((o) => o['tag'].toString()).toSet();
    final routing = Map<String, dynamic>.from(source['routing'] as Map? ?? {});
    for (final item in (routing['balancers'] as List? ?? const [])) {
      if (item is! Map) continue;
      final balancer = Map<String, dynamic>.from(item);
      final tag = balancer['tag']?.toString();
      if (tag == null || tag.isEmpty) continue;
      final selectors = (balancer['selector'] as List? ?? const [])
          .map((e) => e.toString())
          .where(availableTags.contains)
          .toList();
      if (selectors.isEmpty) continue;

      final strategy = balancer['strategy'];
      final strategySettings = strategy is Map && strategy['settings'] is Map
          ? Map<String, dynamic>.from(strategy['settings'] as Map)
          : <String, dynamic>{};
      outbounds.add({
        'type': 'urltest',
        'tag': tag,
        'outbounds': selectors,
        'url': 'https://www.gstatic.com/generate_204',
        'interval': strategySettings['interval'] ?? '3m',
        'tolerance': strategySettings['tolerance'] is num
            ? strategySettings['tolerance']
            : 0,
      });
      availableTags.add(tag);
    }

    final rules = <Map<String, dynamic>>[];
    for (final item in (routing['rules'] as List? ?? const [])) {
      if (item is! Map) continue;
      final input = Map<String, dynamic>.from(item);
      final rule = <String, dynamic>{};

      void copyList(String from, String to) {
        final value = input[from];
        if (value is List && value.isNotEmpty)
          rule[to] = List<dynamic>.from(value);
        else if (value is String && value.isNotEmpty)
          rule[to] = [value];
      }

      copyList('domain', 'domain');
      final domains = (input['domain'] as List? ?? const []).map(
        (e) => e.toString(),
      );
      final geosite = <String>[];
      for (final domain in domains) {
        if (domain.startsWith('full:')) {
          (rule['domain'] as List).remove(domain);
          (rule.putIfAbsent('domain', () => <String>[]) as List).add(
            domain.substring(5),
          );
        } else if (domain.startsWith('domain:')) {
          (rule['domain'] as List).remove(domain);
          (rule.putIfAbsent('domain_suffix', () => <String>[]) as List).add(
            domain.substring(7),
          );
        } else if (domain.startsWith('keyword:')) {
          (rule['domain'] as List).remove(domain);
          (rule.putIfAbsent('domain_keyword', () => <String>[]) as List).add(
            domain.substring(8),
          );
        } else if (domain.startsWith('regexp:')) {
          (rule['domain'] as List).remove(domain);
          (rule.putIfAbsent('domain_regex', () => <String>[]) as List).add(
            domain.substring(7),
          );
        } else if (domain.startsWith('geosite:')) {
          (rule['domain'] as List).remove(domain);
          geosite.add('geosite-${domain.substring(8)}');
        }
      }
      rule.removeWhere((key, value) => value is List && value.isEmpty);
      if (geosite.isNotEmpty) rule['rule_set'] = geosite;

      final ips = input['ip'];
      final ipValues = ips is List
          ? ips.map((e) => e.toString()).toList()
          : (ips is String ? [ips] : <String>[]);
      final geoIp = ipValues
          .where((e) => e.startsWith('geoip:'))
          .map((e) => 'geoip-${e.substring(6)}')
          .toList();
      final cidr = ipValues.where((e) => !e.startsWith('geoip:')).toList();
      if (cidr.isNotEmpty) rule['ip_cidr'] = cidr;
      if (geoIp.isNotEmpty) {
        final existing = (rule['rule_set'] as List? ?? const []).toList();
        rule['rule_set'] = [...existing, ...geoIp];
      }

      final networks = input['network'];
      if (networks is String && networks.isNotEmpty) {
        rule['network'] = networks
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (input['port'] != null) {
        final port = input['port'];
        if (port is num)
          rule['port'] = port.toInt();
        else if (port is List) {
          final ports = port
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList();
          if (ports.isNotEmpty) rule['port'] = ports;
        } else if (port is String) {
          final ports = port
              .split(',')
              .map((e) => int.tryParse(e.trim()))
              .whereType<int>()
              .toList();
          if (ports.isNotEmpty) rule['port'] = ports;
        }
      }
      if (input['protocol'] is List) rule['protocol'] = input['protocol'];
      if (input['source'] is List) rule['source_ip_cidr'] = input['source'];
      if (input['sourcePort'] is List)
        rule['source_port'] = input['sourcePort'];

      final target = input['outboundTag'] ?? input['balancerTag'];
      if (target != null && availableTags.contains(target.toString())) {
        rule['outbound'] = target.toString();
      }
      if (rule.isNotEmpty) rules.add(rule);
    }

    final usedRuleSets = rules
        .expand(
          (rule) =>
              (rule['rule_set'] as List? ?? const []).map((e) => e.toString()),
        )
        .toSet();
    final route = <String, dynamic>{
      'rules': rules,
      'rule_set': [
        ...(routing['rule_set'] as List? ?? const []),
        for (final name in usedRuleSets)
          if (!(routing['rule_set'] as List? ?? const []).any(
            (e) => e is Map && e['tag'] == name,
          ))
            {
              'tag': name,
              'type': 'remote',
              'format': 'binary',
              'url':
                  'https://raw.githubusercontent.com/SagerNet/${name.startsWith('geosite-') ? 'sing-geosite' : 'sing-geoip'}/rule-set/$name.srs',
              'download_detour': 'direct',
              'update_interval': '7d',
            },
      ],
      'auto_detect_interface': true,
    };
    final result = Map<String, dynamic>.from(source)
      ..remove('routing')
      // The source inbounds use Xray's `protocol` schema; the Sing-box builder
      // creates fresh HTTP/SOCKS inbounds with the correct `type` schema.
      ..remove('inbounds')
      ..remove('burstObservatory')
      ..remove('observatory')
      ..remove('policy')
      ..remove('api')
      ..remove('stats')
      ..remove('reverse')
      ..remove('fakedns')
      ..remove('transport')
      ..remove('meta')
      ..['outbounds'] = outbounds
      // Xray DNS uses a different schema. The rules below still route DNS
      // through the generated Sing-box DNS handler.
      ..['dns'] = {
        'servers': [
          {
            'type': 'https',
            'tag': 'subscription-dns',
            'server': '8.8.8.8',
            'server_port': 443,
            'path': '/dns-query',
            'tls': {'enabled': true, 'server_name': 'dns.google'},
          },
        ],
        'final': 'subscription-dns',
        'strategy': _singBoxDnsStrategy,
      }
      ..['route'] = route;
    return result;
  }
}

// ============================================================================
// XRAY BUILDER (НАТИВНАЯ ПОДДЕРЖКА ЦЕПОЧЕК!)
// ============================================================================
class XrayConfigBuilder extends ConfigBuilder {
  final bool isTest;
  final ProxyChain? activeChain;

  XrayConfigBuilder({
    required super.activeProxy,
    required super.settings,
    required super.customRules,
    this.isTest = false,
    this.activeChain,
  });

  String get _xrayQueryStrategy {
    if (settings.ipType == 'IPv6') return 'UseIPv6';
    if (settings.ipType == 'Auto') return 'UseIP';
    return 'UseIPv4';
  }

  void _applyXrayFragment(List<Map<String, dynamic>> outbounds) {
    if (!settings.fragment) return;

    final existingTags = outbounds
        .map((outbound) => outbound['tag']?.toString())
        .whereType<String>()
        .toSet();
    var fragmentTag = 'nextlink-fragment';
    var suffix = 1;
    while (existingTags.contains(fragmentTag)) {
      fragmentTag = 'nextlink-fragment-$suffix';
      suffix++;
    }

    var fragmentApplied = false;
    for (final outbound in outbounds) {
      final protocol = outbound['protocol']?.toString().toLowerCase();
      if (protocol == null ||
          {'freedom', 'blackhole', 'dns'}.contains(protocol)) {
        continue;
      }
      final streamSettings = Map<String, dynamic>.from(
        outbound['streamSettings'] as Map? ?? const {},
      );
      final sockopt = Map<String, dynamic>.from(
        streamSettings['sockopt'] as Map? ?? const {},
      );
      if (sockopt['dialerProxy'] != null) continue;
      sockopt['dialerProxy'] = fragmentTag;
      streamSettings['sockopt'] = sockopt;
      outbound['streamSettings'] = streamSettings;
      fragmentApplied = true;
    }

    if (fragmentApplied) {
      outbounds.add({
        'tag': fragmentTag,
        'protocol': 'freedom',
        'settings': {
          'fragment': {
            'packets': _fragmentPackets,
            'length': _fragmentRange(settings.fragmentLength, '10-50'),
            'interval': _fragmentRange(settings.fragmentInterval, '5-10'),
          },
        },
      });
    }
  }

  String get _fragmentPackets {
    final value = settings.fragmentPackets.trim();
    return value == 'tlshello' || RegExp(r'^\d+(?:-\d+)?$').hasMatch(value)
        ? value
        : 'tlshello';
  }

  String _fragmentRange(String value, String fallback) {
    final normalized = value.trim();
    return RegExp(r'^\d+(?:-\d+)?$').hasMatch(normalized)
        ? normalized
        : fallback;
  }

  @override
  Map<String, dynamic> build() {
    Map<String, dynamic> rawJson = Map<String, dynamic>.from(
      activeProxy.finalJson,
    );

    rawJson.removeWhere(
      (key, value) => [
        'remarks',
        'isActive',
        'isPinging',
        'ping',
        'rawJsonOverride',
        'classType',
      ].contains(key),
    );

    final httpPort = isTest ? settings.httpPort + 2 : settings.httpPort;
    final socksPort = isTest ? settings.socksPort + 2 : settings.socksPort;
    const listenIp = "127.0.0.1";

    if (rawJson.containsKey('routing') || rawJson.containsKey('outbounds')) {
      List<Map<String, dynamic>> compiledOutbounds = [];

      // --- ПОДДЕРЖКА ЦЕПОЧЕК ДЛЯ XRAY ДЛЯ КАСТОМНЫХ КОНФИГОВ И ПОДПИСОК ---
      if (activeChain != null && activeChain!.nodes.length > 1) {
        final lastChainTag = 'chain-node-${activeChain!.nodes.length - 2}';

        for (int i = 0; i < activeChain!.nodes.length - 1; i++) {
          final node = activeChain!.nodes[i];
          Map<String, dynamic> rawNode = Map<String, dynamic>.from(
            node.finalJson,
          );

          rawNode.removeWhere(
            (key, value) => [
              'remarks',
              'isActive',
              'isPinging',
              'ping',
              'rawJsonOverride',
              'classType',
              'proxySettings',
            ].contains(key),
          );

          if (rawNode.containsKey('outbounds') &&
              rawNode['outbounds'] is List) {
            final outboundsList = rawNode['outbounds'] as List;
            rawNode = outboundsList.firstWhere(
              (o) =>
                  o['protocol'] != 'freedom' &&
                  o['protocol'] != 'blackhole' &&
                  o['protocol'] != 'dns',
              orElse: () => outboundsList.isNotEmpty
                  ? outboundsList.first
                  : {"protocol": "vless"},
            );
            rawNode.remove('proxySettings');
          }

          final String nodeTag = 'chain-node-$i';
          rawNode['tag'] = nodeTag;

          // В Xray 1.8+ цепочки реализуются через dialerProxy
          if (i > 0) {
            final String prevTag = 'chain-node-${i - 1}';
            rawNode['streamSettings'] ??= {};
            rawNode['streamSettings']['sockopt'] ??= {};
            rawNode['streamSettings']['sockopt']['dialerProxy'] = prevTag;
          }

          compiledOutbounds.add(rawNode);
        }

        Map<String, dynamic> originalJson = Map<String, dynamic>.from(rawJson);
        if (originalJson.containsKey('outbounds') &&
            originalJson['outbounds'] is List) {
          final outboundsList = originalJson['outbounds'] as List;
          final proxyProtocols = {
            'vless',
            'vmess',
            'trojan',
            'shadowsocks',
            'hysteria',
            'hysteria2',
            'tuic',
            'wireguard',
            'ssh',
            'shadowtls',
            'http',
            'socks',
          };

          for (var o in outboundsList) {
            if (o is Map<String, dynamic>) {
              o.remove('proxySettings');
              if (proxyProtocols.contains(o['protocol']?.toString())) {
                o['streamSettings'] ??= {};
                o['streamSettings']['sockopt'] ??= {};
                o['streamSettings']['sockopt']['dialerProxy'] = lastChainTag;
              }
              compiledOutbounds.add(o);
            }
          }
        }
      } else {
        if (rawJson.containsKey('outbounds') && rawJson['outbounds'] is List) {
          final outboundsList = rawJson['outbounds'] as List;
          for (var o in outboundsList) {
            if (o is Map<String, dynamic>) {
              o.remove('proxySettings');
              compiledOutbounds.add(o);
            }
          }
        } else {
          Map<String, dynamic> proxyOutbound = Map<String, dynamic>.from(
            rawJson,
          );
          proxyOutbound.remove('proxySettings');
          proxyOutbound['tag'] ??= 'proxy';
          compiledOutbounds.add(proxyOutbound);
        }
      }

      for (var outbound in compiledOutbounds) {
        outbound.remove('proxySettings');
      }

      if (settings.xrayMux) {
        rawJson['mux'] = {
          'enabled': true,
          'concurrency': settings.xrayMuxConcurrency.clamp(1, 128),
        };
      }

      if (settings.fragment) {
        _applyXrayFragment(compiledOutbounds);
      }

      rawJson.remove('fakedns');
      if (rawJson['dns'] != null && rawJson['dns']['servers'] != null) {
        (rawJson['dns']['servers'] as List).removeWhere(
          (e) => e == 'fakedns' || e == 'localhost',
        );
      }

      rawJson['dns'] = {
        "queryStrategy": _xrayQueryStrategy,
        "servers": ["https://8.8.8.8/dns-query", "https://1.1.1.1/dns-query"],
      };

      final String httpTag = 'http';
      final String socksTag = 'socks';

      rawJson['inbounds'] = [
        ...LanProxyInbounds.xray(settings, isTest: isTest),
        {
          "tag": httpTag,
          "port": httpPort,
          "listen": listenIp,
          "protocol": "http",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
          },
        },
        {
          "tag": socksTag,
          "port": socksPort,
          "listen": listenIp,
          "protocol": "socks",
          "settings": {"auth": "noauth", "udp": true},
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
          },
        },
      ];

      rawJson['log'] = {"loglevel": settings.logLevel};

      final routing = Map<String, dynamic>.from(
        rawJson['routing'] as Map<String, dynamic>? ?? {"rules": []},
      );
      final balancers = (routing['balancers'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final outboundTags = compiledOutbounds
          .map((o) => o['tag']?.toString())
          .whereType<String>()
          .toSet();
      final balancerTags = balancers
          .map((b) => b['tag']?.toString())
          .whereType<String>()
          .toSet();

      if (!outboundTags.contains('direct')) {
        compiledOutbounds.add({"tag": "direct", "protocol": "freedom"});
        outboundTags.add('direct');
      }
      if (!outboundTags.contains('block')) {
        compiledOutbounds.add({
          "tag": "block",
          "protocol": "blackhole",
          "settings": {
            "response": {"type": "none"},
          },
        });
        outboundTags.add('block');
      }
      if (!outboundTags.contains('dns-out')) {
        compiledOutbounds.add({"tag": "dns-out", "protocol": "dns"});
        outboundTags.add('dns-out');
      }
      outboundTags.addAll(
        compiledOutbounds
            .map((outbound) => outbound['tag']?.toString())
            .whereType<String>(),
      );
      rawJson['outbounds'] = compiledOutbounds;

      String? mainTarget;
      if (balancers.isNotEmpty) {
        mainTarget = balancers.first['tag'];
      } else {
        mainTarget = outboundTags.contains('proxy')
            ? 'proxy'
            : (outboundTags.isNotEmpty ? outboundTags.first : 'proxy');
      }

      // Делаем глубокую копию правил для безопасности
      final rules = (routing['rules'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (var rule in rules) {
        // --- МИГРАЦИЯ ПРАВИЛ XRAY ИЗ ПОДПИСКИ ---
        if (rule.containsKey('inboundTag')) {
          final inbs = (rule['inboundTag'] is List)
              ? List<String>.from(rule['inboundTag'])
              : [rule['inboundTag'].toString()];
          if (!inbs.contains(httpTag)) inbs.add(httpTag);
          if (!inbs.contains(socksTag)) inbs.add(socksTag);
          rule['inboundTag'] = inbs;
        } else {
          rule['inboundTag'] = [socksTag, httpTag];
        }
      }

      final bypassAddresses = <String>{};
      if (activeChain != null && activeChain!.nodes.isNotEmpty) {
        for (final n in activeChain!.nodes) {
          if (n.address.isNotEmpty && n.address != 'JSON Config')
            bypassAddresses.add(n.address);
        }
      } else if (activeProxy.protocol != 'CUSTOM' &&
          activeProxy.address.isNotEmpty &&
          activeProxy.address != 'JSON Config') {
        bypassAddresses.add(activeProxy.address);
      }

      final safetyBridge = [
        for (final addr in bypassAddresses)
          if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(addr) ||
              addr.contains(':'))
            {
              "type": "field",
              "ip": ["$addr/${addr.contains(':') ? 128 : 32}"],
              "outboundTag": "direct",
            }
          else
            {
              "type": "field",
              "domain": ["full:$addr"],
              "outboundTag": "direct",
            },
        {
          "type": "field",
          "port": 53,
          "network": "udp,tcp",
          "outboundTag": "dns-out",
        },
      ];

      final ipv6Block = !settings.ipv6
          ? {
              "type": "field",
              "ip": ["::/0"],
              "outboundTag": "block",
            }
          : null;

      final customXrayRules = customRules
          .map((r) {
            String rawValue = r.value;
            String? chainTag;
            if (r.action == 'CHAIN') {
              final sep = rawValue.indexOf('=>');
              if (sep >= 0) {
                chainTag = rawValue.substring(sep + 2).trim();
                rawValue = rawValue.substring(0, sep).trim();
              }
            }
            final String tag;
            if (r.action == 'PROXY') {
              tag = mainTarget ?? 'proxy';
            } else if (r.action == 'CHAIN') {
              final bool valid =
                  chainTag != null && outboundTags.contains(chainTag);
              tag = valid ? chainTag : (mainTarget ?? 'proxy');
            } else {
              tag = r.action.toLowerCase();
            }
            if (r.conditions != null)
              return {
                '__xrayRules': RoutingRuleCodec.xrayRules(r.conditions!, tag),
              };
            List<String> values = rawValue
                .split(',')
                .map((e) => e.trim())
                .toList();

            if (r.type == 'GeoSite')
              return {
                "type": "field",
                "domain": values.map((e) => "geosite:$e").toList(),
                "outboundTag": tag,
              };
            if (r.type == 'GeoIP')
              return {
                "type": "field",
                "ip": values.map((e) => "geoip:$e").toList(),
                "outboundTag": tag,
              };
            if (r.type == 'Domain Keyword')
              return {
                "type": "field",
                "domain": values.map((e) => "keyword:$e").toList(),
                "outboundTag": tag,
              };
            if (r.type == 'Port') {
              List<int> ports = values
                  .map((e) => int.tryParse(e))
                  .whereType<int>()
                  .toList();
              if (ports.isNotEmpty)
                return {
                  "type": "field",
                  "port": r.value.replaceAll(' ', ''),
                  "outboundTag": tag,
                };
            }
            return <String, dynamic>{};
          })
          .expand((r) => RoutingRuleCodec.expandXray(r))
          .where((e) => e.isNotEmpty)
          .toList();

      Map<String, dynamic>? catchAllRule;
      if (mainTarget != null) {
        if (balancerTags.contains(mainTarget))
          catchAllRule = {
            "type": "field",
            "inboundTag": [socksTag, httpTag],
            "balancerTag": mainTarget,
          };
        else if (outboundTags.contains(mainTarget))
          catchAllRule = {
            "type": "field",
            "inboundTag": [socksTag, httpTag],
            "outboundTag": mainTarget,
          };
      }

      routing['domainStrategy'] = 'IPIfNonMatch';

      routing['rules'] = [
        ...safetyBridge,
        if (settings.blockQuic)
          {
            "type": "field",
            "network": "udp",
            "port": 443,
            "outboundTag": "block",
          },
        if (ipv6Block != null) ipv6Block,
        if (settings.useRouting && settings.bypassLan) ...[
          {
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": "direct",
          },
          {
            "type": "field",
            "domain": ["geosite:private"],
            "outboundTag": "direct",
          },
        ],
        ...customXrayRules,
        ...rules,
        if (catchAllRule != null) catchAllRule,
      ];

      rawJson['routing'] = routing; // Применяем обратно
      return rawJson;
    }

    // --- Обработка ПРОСТЫХ ССЫЛОК (с поддержкой цепочек Xray) ---
    List<Map<String, dynamic>> compiledOutbounds = [];
    if (activeChain != null && activeChain!.nodes.isNotEmpty) {
      for (int i = 0; i < activeChain!.nodes.length; i++) {
        final node = activeChain!.nodes[i];
        Map<String, dynamic> rawNode = Map<String, dynamic>.from(
          node.finalJson,
        );

        rawNode.removeWhere(
          (key, value) => [
            'remarks',
            'isActive',
            'isPinging',
            'ping',
            'rawJsonOverride',
            'classType',
            'proxySettings',
          ].contains(key),
        );
        rawNode.remove('proxySettings');

        if (rawNode.containsKey('outbounds') && rawNode['outbounds'] is List) {
          final outboundsList = rawNode['outbounds'] as List;
          rawNode = outboundsList.firstWhere(
            (o) =>
                o['protocol'] != 'freedom' &&
                o['protocol'] != 'blackhole' &&
                o['protocol'] != 'dns',
            orElse: () => outboundsList.isNotEmpty
                ? outboundsList.first
                : {"protocol": "vless"},
          );
          rawNode.remove('proxySettings');
        }

        final String nodeTag = (i == activeChain!.nodes.length - 1)
            ? 'proxy'
            : 'chain-node-$i';
        rawNode['tag'] = nodeTag;

        if (i > 0) {
          rawNode['streamSettings'] ??= {};
          rawNode['streamSettings']['sockopt'] ??= {};
          rawNode['streamSettings']['sockopt']['dialerProxy'] =
              'chain-node-${i - 1}';
        }
        compiledOutbounds.add(rawNode);
      }
    } else {
      Map<String, dynamic> proxyOutbound = Map<String, dynamic>.from(rawJson);
      proxyOutbound.remove('proxySettings');
      if (proxyOutbound.containsKey('outbounds') &&
          proxyOutbound['outbounds'] is List) {
        final outboundsList = proxyOutbound['outbounds'] as List;
        proxyOutbound = outboundsList.firstWhere(
          (o) =>
              o['protocol'] != 'freedom' &&
              o['protocol'] != 'blackhole' &&
              o['protocol'] != 'dns',
          orElse: () => outboundsList.isNotEmpty
              ? outboundsList.first
              : {"protocol": "vless"},
        );
        proxyOutbound.remove('proxySettings');
      }
      proxyOutbound['tag'] = 'proxy';
      proxyOutbound["streamSettings"] ??= {};
      compiledOutbounds.add(proxyOutbound);
    }

    for (var outbound in compiledOutbounds) {
      outbound.remove('proxySettings');
    }

    _applyXrayFragment(compiledOutbounds);

    final bypassAddresses = <String>{};
    if (activeChain != null && activeChain!.nodes.isNotEmpty) {
      for (final n in activeChain!.nodes) {
        if (n.address.isNotEmpty && n.address != 'JSON Config')
          bypassAddresses.add(n.address);
      }
    } else if (activeProxy.protocol != 'CUSTOM' &&
        activeProxy.address.isNotEmpty &&
        activeProxy.address != 'JSON Config') {
      bypassAddresses.add(activeProxy.address);
    }

    return {
      "log": {"loglevel": settings.logLevel},
      if (settings.xrayMux)
        "mux": {
          'enabled': true,
          'concurrency': settings.xrayMuxConcurrency.clamp(1, 128),
        },
      "dns": {
        "queryStrategy": _xrayQueryStrategy,
        "servers": ["https://8.8.8.8/dns-query", "https://1.1.1.1/dns-query"],
      },
      "inbounds": [
        ...LanProxyInbounds.xray(settings, isTest: isTest),
        {
          "tag": "http",
          "port": httpPort,
          "listen": listenIp,
          "protocol": "http",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
          },
        },
        {
          "tag": "socks",
          "port": socksPort,
          "listen": listenIp,
          "protocol": "socks",
          "settings": {"auth": "noauth", "udp": true},
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
          },
        },
      ],
      "outbounds": [
        ...compiledOutbounds,
        {"tag": "direct", "protocol": "freedom"},
        {
          "tag": "block",
          "protocol": "blackhole",
          "settings": {
            "response": {"type": "none"},
          },
        },
        {"tag": "dns-out", "protocol": "dns"},
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          if (settings.blockQuic)
            {
              "type": "field",
              "network": "udp",
              "port": 443,
              "outboundTag": "block",
            },
          if (!settings.ipv6)
            {
              "type": "field",
              "ip": ["::/0"],
              "outboundTag": "block",
            },
          {"type": "field", "port": 853, "outboundTag": "block"},
          {
            "type": "field",
            "inboundTag": ["socks", "http"],
            "port": 53,
            "network": "udp,tcp",
            "outboundTag": "dns-out",
          },
          for (final addr in bypassAddresses)
            if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(addr) ||
                addr.contains(':'))
              {
                "type": "field",
                "ip": ["$addr/${addr.contains(':') ? 128 : 32}"],
                "outboundTag": "direct",
              }
            else
              {
                "type": "field",
                "domain": ["full:$addr"],
                "outboundTag": "direct",
              },
          if (settings.useRouting && settings.bypassLan) ...[
            {
              "type": "field",
              "ip": ["geoip:private"],
              "outboundTag": "direct",
            },
            {
              "type": "field",
              "domain": ["geosite:private"],
              "outboundTag": "direct",
            },
          ],

          ...customRules
              .map((r) {
                String rawValue = r.value;
                if (r.action == 'CHAIN') {
                  final sep = rawValue.indexOf('=>');
                  if (sep >= 0) rawValue = rawValue.substring(0, sep).trim();
                }
                final String tag = (r.action == 'PROXY' || r.action == 'CHAIN')
                    ? 'proxy'
                    : r.action.toLowerCase();
                if (r.conditions != null)
                  return {
                    '__xrayRules': RoutingRuleCodec.xrayRules(
                      r.conditions!,
                      tag,
                    ),
                  };
                List<String> values = rawValue
                    .split(',')
                    .map((e) => e.trim())
                    .toList();

                if (r.type == 'GeoSite')
                  return {
                    "type": "field",
                    "domain": values.map((e) => "geosite:$e").toList(),
                    "outboundTag": tag,
                  };
                if (r.type == 'GeoIP')
                  return {
                    "type": "field",
                    "ip": values.map((e) => "geoip:$e").toList(),
                    "outboundTag": tag,
                  };
                if (r.type == 'Domain Keyword')
                  return {
                    "type": "field",
                    "domain": values.map((e) => "keyword:$e").toList(),
                    "outboundTag": tag,
                  };
                if (r.type == 'Port')
                  return {
                    "type": "field",
                    "port": r.value.replaceAll(' ', ''),
                    "outboundTag": tag,
                  };
                return {};
              })
              .expand((r) => RoutingRuleCodec.expandXray(r))
              .where((e) => e.isNotEmpty),

          {"type": "field", "network": "tcp,udp", "outboundTag": "proxy"},
        ],
      },
    };
  }
}
