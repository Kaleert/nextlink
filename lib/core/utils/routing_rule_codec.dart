import 'dart:convert';

/// Portable routing conditions. Fields within a family are OR; families are AND.
class RoutingRuleCodec {
  static Map<String, dynamic> decode(
    Map raw, {
    Map<String, dynamic> definitions = const {},
    int depth = 0,
  }) {
    if (depth > 32)
      throw const FormatException('Слишком глубокая вложенность правил');
    if (raw['action'] != null && !['route', 'reject'].contains(raw['action']))
      throw FormatException(
        'Действие ${raw['action']} нужно импортировать полным конфигом',
      );
    if (raw['type'] == 'logical') {
      final mode = raw['mode'];
      final rules = raw['rules'];
      if (!['and', 'or'].contains(mode) || rules is! List || rules.isEmpty)
        throw const FormatException('Неверная логическая группа');
      return {
        '__logical': {
          'mode': mode,
          'rules': rules
              .map(
                (r) => decode(
                  Map<String, dynamic>.from(r as Map),
                  definitions: definitions,
                  depth: depth + 1,
                ),
              )
              .toList(),
        },
        if (raw['invert'] == true) '__invert': true,
      };
    }
    final result = <String, dynamic>{};
    final xray = raw.containsKey('outboundTag') || raw['type'] == 'field';
    void add(String key, dynamic value) {
      final list = value is List ? value : [value];
      (result[key] ??= <String>[]).addAll(list.map((v) => v.toString()));
    }

    for (final e in raw.entries) {
      final key = e.key.toString();
      if ([
        'outboundTag',
        'outbound',
        'action',
        'balancerTag',
        'type',
      ].contains(key))
        continue;
      if (key == 'invert') {
        if (e.value == true) result['__invert'] = true;
        continue;
      }
      if ([
        'ip_is_private',
        'source_ip_is_private',
        'network_is_expensive',
        'network_is_constrained',
      ].contains(key)) {
        if (e.value is! bool) throw FormatException('$key: требуется bool');
        result[key] = e.value;
        continue;
      }
      if (key == 'inboundTag') {
        add('inbound', e.value);
        continue;
      }
      if (key == 'ipVersion') {
        add('ip_version', e.value);
        continue;
      }
      if (key == 'domain') {
        for (final value in (e.value is List ? e.value as List : [e.value])) {
          final v = value.toString();
          if (xray) {
            if (v.startsWith('full:')) {
              add('domain', v.substring(5));
            } else if (v.startsWith('domain:')) {
              add('domain_suffix', v.substring(7));
            } else if (v.startsWith('regexp:')) {
              add('domain_regex', v.substring(7));
            } else if (v.startsWith('keyword:')) {
              add('domain_keyword', v.substring(8));
            } else if (v.startsWith('geosite:')) {
              add('geosite', v.substring(8));
            } else {
              add('domain_keyword', v);
            }
          } else {
            add('domain', v);
          }
        }
      } else if (key == 'ip' || key == 'source') {
        for (final value in (e.value is List ? e.value as List : [e.value])) {
          final v = value.toString();
          if (v.startsWith('geoip:') && key == 'ip') {
            add('geoip', v.substring(6));
          } else {
            add(key == 'ip' ? 'ip_cidr' : 'source_ip_cidr', v);
          }
        }
      } else if (['port', 'sourcePort', 'network'].contains(key)) {
        add(
          key == 'sourcePort' ? 'source_port' : key,
          e.value is String
              ? (e.value as String).split(',').map((s) => s.trim()).toList()
              : e.value,
        );
      } else if ([
        'domain_suffix',
        'domain_regex',
        'domain_keyword',
        'ip_cidr',
        'source_ip_cidr',
        'source_port',
        'protocol',
        'geosite',
        'geoip',
        'process_name',
        'process_path',
        'process_path_regex',
        'package_name',
        'user',
        'user_id',
        'inbound',
        'ip_version',
        'clash_mode',
      ].contains(key)) {
        add(key, e.value);
      } else if (key == 'port_range' || key == 'source_port_range') {
        add(key == 'port_range' ? 'port' : 'source_port', e.value);
      } else if (key == 'rule_set') {
        for (final value in (e.value is List ? e.value as List : [e.value])) {
          final v = value.toString();
          if (definitions.containsKey(v)) {
            add('rule_set', v);
            final attached = result['__ruleSets'] ??= <String, dynamic>{};
            void attach(String tag) {
              if (attached.containsKey(tag)) return;
              final definition = definitions[tag];
              if (definition is! Map)
                throw FormatException('Отсутствует описание rule-set: $tag');
              attached[tag] = definition;
              void walk(dynamic node) {
                if (node is Map) {
                  final refs = node['rule_set'];
                  for (final ref
                      in refs is List
                          ? refs
                          : refs == null
                          ? []
                          : [refs]) {
                    attach(ref.toString());
                  }
                  for (final entry in node.entries) {
                    if (entry.key != 'rule_set') walk(entry.value);
                  }
                } else if (node is List) {
                  for (final child in node) {
                    walk(child);
                  }
                }
              }

              walk(definition['rules']);
            }

            attach(v);
          } else if (v.startsWith('geosite-')) {
            add('geosite', v.substring(8));
          } else if (v.startsWith('geoip-')) {
            add('geoip', v.substring(6));
          } else {
            if (!definitions.containsKey(v))
              throw FormatException('Отсутствует описание rule-set: $v');
            add('rule_set', v);
            (result['__ruleSets'] ??= <String, dynamic>{})[v] = definitions[v];
          }
        }
      } else {
        throw FormatException(
          'Условие правила «$key» пока не поддерживается импортом',
        );
      }
    }
    if (raw['action'] != null && !['route', 'reject'].contains(raw['action'])) {
      throw FormatException(
        'Действие ${raw['action']} нужно импортировать полным конфигом',
      );
    }
    return result;
  }

  static Map<String, dynamic> singBox(
    Map<String, dynamic> conditions,
    String tag,
  ) {
    final logical = conditions['__logical'];
    if (logical is Map)
      return {
        'type': 'logical',
        'mode': logical['mode'],
        'rules': (logical['rules'] as List).map((r) {
          final compiled = singBox(Map<String, dynamic>.from(r), '');
          compiled.remove('outbound');
          return compiled;
        }).toList(),
        if (conditions['__invert'] == true) 'invert': true,
        'outbound': tag,
      };
    final domains = <Map<String, dynamic>>[];
    final ips = <Map<String, dynamic>>[];
    final rest = <String, dynamic>{};
    for (final e in conditions.entries) {
      if (e.key.startsWith('__')) continue;
      if (e.key.startsWith('domain')) {
        domains.add({e.key: e.value});
      } else if (e.key == 'geosite') {
        domains.add({
          'rule_set': (e.value as List).map((v) => 'geosite-$v').toList(),
        });
      } else if (e.key == 'geoip') {
        ips.add({
          'rule_set': (e.value as List).map((v) => 'geoip-$v').toList(),
        });
      } else if (e.key == 'ip_cidr') {
        ips.add({e.key: e.value});
      } else if (e.key == 'port' || e.key == 'source_port') {
        final ports = <int>[];
        final ranges = <String>[];
        for (final v in e.value as List) {
          final s = v.toString();
          final n = int.tryParse(s);
          if (n != null && n >= 1 && n <= 65535) {
            ports.add(n);
          } else if (RegExp(r'^\d+[-:]\d+$').hasMatch(s)) {
            ranges.add(s.replaceAll('-', ':'));
          } else {
            throw FormatException('Некорректный порт: $s');
          }
        }
        if (ports.isNotEmpty) rest[e.key] = ports;
        if (ranges.isNotEmpty) rest['${e.key}_range'] = ranges;
      } else if (e.key == 'user_id') {
        rest[e.key] = (e.value as List)
            .map((v) => int.parse(v.toString()))
            .toList();
      } else if (e.key == 'ip_version') {
        rest[e.key] = int.parse((e.value as List).single.toString());
      } else if (e.key == 'clash_mode') {
        rest[e.key] = (e.value as List).single;
      } else {
        rest[e.key] = e.value;
      }
    }
    Map<String, dynamic> any(List<Map<String, dynamic>> values) =>
        values.length == 1
        ? values.single
        : {'type': 'logical', 'mode': 'or', 'rules': values};
    final groups = [
      if (domains.isNotEmpty) any(domains),
      if (ips.isNotEmpty) any(ips),
      if (rest.isNotEmpty) rest,
    ];
    return {
      ...(groups.length <= 1
          ? (groups.isEmpty ? <String, dynamic>{} : groups.single)
          : {'type': 'logical', 'mode': 'and', 'rules': groups}),
      if (conditions['__invert'] == true) 'invert': true,
      'outbound': tag,
    };
  }

  static Map<String, dynamic> xray(
    Map<String, dynamic> conditions,
    String tag,
  ) {
    final rule = <String, dynamic>{'type': 'field', 'outboundTag': tag};
    final domains = <String>[];
    final ips = <String>[];
    for (final e in conditions.entries) {
      if (e.key.startsWith('__')) continue;
      final values = (e.value as List).map((v) => v.toString()).toList();
      final prefix = const {
        'domain': 'full:',
        'domain_suffix': 'domain:',
        'domain_keyword': 'keyword:',
        'domain_regex': 'regexp:',
        'geosite': 'geosite:',
      }[e.key];
      if (prefix != null) {
        domains.addAll(values.map((v) => '$prefix$v'));
      } else if (e.key == 'ip_cidr') {
        ips.addAll(values);
      } else if (e.key == 'geoip') {
        ips.addAll(values.map((v) => 'geoip:$v'));
      } else if (e.key == 'source_ip_cidr') {
        rule['source'] = values;
      } else if (e.key == 'port' || e.key == 'source_port') {
        rule[e.key == 'port' ? 'port' : 'sourcePort'] = values
            .map((v) => v.replaceAll(':', '-'))
            .join(',');
      } else if (e.key == 'inbound') {
        rule['inboundTag'] = values;
      } else if (e.key == 'network') {
        rule['network'] = values.join(',');
      } else {
        rule[e.key] = values;
      }
    }
    if (domains.isNotEmpty) rule['domain'] = domains;
    if (ips.isNotEmpty) rule['ip'] = ips;
    if (rule.length == 2) rule['network'] = 'tcp,udp';
    return rule;
  }

  static Map<String, Map<String, dynamic>> definitions(Map<String, dynamic> c) {
    final out = <String, Map<String, dynamic>>{};
    void visit(Map node) {
      for (final e in (node['__ruleSets'] as Map? ?? {}).entries) {
        final def = Map<String, dynamic>.from(e.value);
        final existing = out[e.key];
        if (existing != null && jsonEncode(existing) != jsonEncode(def))
          throw FormatException('Конфликт rule-set: ${e.key}');
        out[e.key.toString()] = def;
      }
      final group = node['__logical'];
      if (group is Map)
        for (final child in group['rules'] as List) {
          visit(child as Map);
        }
    }

    visit(c);
    return out;
  }

  static List<Map<String, dynamic>> xrayRules(
    Map<String, dynamic> conditions,
    String tag,
  ) {
    final defs = definitions(conditions);
    List<List<Map<String, dynamic>>> expand(
      Map<String, dynamic> node,
      int depth,
    ) {
      if (depth > 32)
        throw const FormatException('Слишком глубокая вложенность rule-set');
      if (node['__invert'] == true)
        throw const FormatException('Отрицание условий требует Sing-box');
      final group = node['__logical'];
      if (group is Map) {
        final children = (group['rules'] as List).map(
          (r) => expand(Map<String, dynamic>.from(r), depth + 1),
        );
        if (group['mode'] == 'or') {
          final out = children.expand((c) => c).toList();
          if (out.length > 256)
            throw const FormatException('Сложное правило требует Sing-box');
          return out;
        }
        var out = <List<Map<String, dynamic>>>[[]];
        for (final branches in children) {
          if (out.length * branches.length > 256)
            throw const FormatException('Сложное правило требует Sing-box');
          out = [
            for (final left in out)
              for (final right in branches) [...left, ...right],
          ];
        }
        return out;
      }
      final nativeFields = node.keys
          .where(
            (k) =>
                !k.startsWith('__') &&
                ![
                  'domain',
                  'domain_suffix',
                  'domain_regex',
                  'domain_keyword',
                  'geosite',
                  'geoip',
                  'ip_cidr',
                  'source_ip_cidr',
                  'port',
                  'source_port',
                  'network',
                  'protocol',
                  'user',
                  'inbound',
                  'rule_set',
                ].contains(k),
          )
          .toList();
      if (nativeFields.isNotEmpty)
        throw FormatException(
          'Условия ${nativeFields.join(', ')} требуют Sing-box',
        );
      if (node['rule_set'] is List) {
        final leaf = {...node}
          ..remove('rule_set')
          ..remove('__ruleSets');
        final groups = <Map<String, dynamic>>[];
        for (final name in node['rule_set'] as List) {
          final def = defs[name];
          if (def == null || def['type'] != 'inline')
            throw FormatException(
              'Набор $name требует Sing-box (внешний rule-set)',
            );
          groups.add({
            '__logical': {
              'mode': 'or',
              'rules': (def['rules'] as List)
                  .map(
                    (r) =>
                        decode(r as Map, definitions: defs, depth: depth + 1),
                  )
                  .toList(),
            },
          });
        }
        return expand({
          '__logical': {
            'mode': 'and',
            'rules': [
              leaf,
              {
                '__logical': {'mode': 'or', 'rules': groups},
              },
            ],
          },
        }, depth + 1);
      }
      return [
        [
          {...node}..remove('__ruleSets'),
        ],
      ];
    }

    final clauses = expand(conditions, 0);
    final result = <Map<String, dynamic>>[];
    for (final clause in clauses) {
      final merged = <String, dynamic>{};
      final families = <String>{};
      for (final leaf in clause) {
        final leafFamilies = <String>{};
        for (final key in leaf.keys.where((k) => !k.startsWith('__'))) {
          final family = key.startsWith('domain') || key == 'geosite'
              ? 'domain'
              : key == 'ip_cidr' || key == 'geoip'
              ? 'ip'
              : key;
          leafFamilies.add(family);
        }
        if (leafFamilies.any(families.contains))
          throw const FormatException(
            'Пересечение условий одного типа требует Sing-box',
          );
        families.addAll(leafFamilies);
        merged.addAll(leaf);
      }
      result.add(xray(merged, tag));
    }
    return result;
  }

  static bool needsSingBox(Map<String, dynamic> c) {
    try {
      xrayRules(c, 'proxy');
      return false;
    } on FormatException {
      return true;
    }
  }

  static Iterable<Map<String, dynamic>> expandXray(Map rule) sync* {
    if (rule['__xrayRules'] is List) {
      for (final item in rule['__xrayRules'] as List) {
        yield Map<String, dynamic>.from(item);
      }
    } else {
      yield Map<String, dynamic>.from(rule);
    }
  }

  static Iterable<String> ruleSets(Map rule) sync* {
    if (rule['rule_set'] is List)
      yield* (rule['rule_set'] as List).map((v) => v.toString());
    for (final r in rule['rules'] as List? ?? []) {
      if (r is Map) yield* ruleSets(r);
    }
  }

  static String describe(Map<String, dynamic> conditions) =>
      jsonEncode(conditions);
}
