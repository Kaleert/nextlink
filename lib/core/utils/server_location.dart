import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxies/custom_config.dart';
import '../models/proxies/proxy_config.dart';
import '../models/proxies/proxy_parser.dart';
import 'ip_location.dart';

class ServerEndpoint {
  final String host, label, serverKey, serverName;
  final bool grouped;
  const ServerEndpoint(
    this.host,
    this.label,
    this.serverKey,
    this.serverName,
    this.grouped,
  );
}

/// Read endpoint addresses, never infer a city from a flag or display name.
List<ServerEndpoint> serverEndpoints(ProxyConfig server) {
  final raw =
      server.rawJsonOverride ??
      (server is CustomConfig ? server.jsonString : null);
  final found = <String, String>{};
  void add(dynamic host, dynamic label) {
    if (host is! String || host.trim().isEmpty || host.contains(' ')) return;
    var normalized = host.trim().toLowerCase();
    if (InternetAddress.tryParse(normalized) == null) {
      final parsed = Uri.tryParse('udp://$normalized');
      if (parsed == null || parsed.host.isEmpty || parsed.path.isNotEmpty)
        return;
      normalized = parsed.host.replaceAll(RegExp(r'^\[|\]$'), '');
    }
    found.putIfAbsent(normalized, () => '$label');
  }

  void outbound(Map map) {
    if (const {
      'freedom',
      'blackhole',
      'dns',
      'direct',
      'block',
      'selector',
      'urltest',
    }.contains(map['protocol'] ?? map['type']))
      return;
    final label = map['tag'] ?? server.name;
    add(map['server'], label);
    final settings = map['settings'];
    if (settings is Map) {
      add(settings['address'], label);
      for (final key in ['vnext', 'servers', 'peers']) {
        if (settings[key] is List) {
          for (final peer in settings[key]) {
            if (peer is Map)
              add(peer['address'] ?? peer['server'] ?? peer['endpoint'], label);
          }
        }
      }
    }
    if (map['peers'] is List) {
      for (final peer in map['peers']) {
        if (peer is Map) add(peer['address'], label);
      }
    }
  }

  if (raw != null) {
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        for (final key in ['outbounds', 'endpoints']) {
          if (data[key] is List)
            for (final item in data[key]) {
              if (item is Map) outbound(item);
            }
        }
        if (found.isEmpty) outbound(data);
      }
    } catch (_) {}
  }
  if (found.isEmpty && server.port > 0) add(server.address, server.name);
  return [
    for (final entry in found.entries)
      ServerEndpoint(
        entry.key,
        entry.value,
        server.uniqueKey,
        server.name,
        found.length > 1,
      ),
  ];
}

bool isPublicLocationAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.isLoopback || address.isLinkLocal || address.isMulticast)
    return false;
  if (b.length == 4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        b[0] == 169 && b[1] == 254 ||
        b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
        b[0] == 192 && b[1] == 168 ||
        b[0] == 100 && b[1] >= 64 && b[1] <= 127);
  }
  // Includes unspecified, unique-local and IPv4-mapped addresses.
  return b[0] & 0xe0 == 0x20;
}

class ServerLocationLookup {
  final http.Client client;
  final Future<List<InternetAddress>> Function(String) resolve;
  final _pending = <String, Future<IpLocation>>{};
  final _cached = <String, (DateTime, IpLocation)>{};
  bool _closed = false;
  ServerLocationLookup({
    http.Client? client,
    Future<List<InternetAddress>> Function(String)? resolve,
  }) : client = client ?? http.Client(),
       resolve = resolve ?? InternetAddress.lookup;

  Future<IpLocation> lookup(String host) {
    final cached = _cached[host];
    if (cached != null && DateTime.now().isBefore(cached.$1))
      return Future.value(cached.$2);
    return _pending.putIfAbsent(
      host,
      () => _load(host).whenComplete(() {
        _pending.remove(host);
      }),
    );
  }

  Future<IpLocation> _load(String host) async {
    var location = const IpLocation();
    try {
      final literal = InternetAddress.tryParse(host);
      final addresses = literal != null
          ? [literal]
          : await resolve(host).timeout(const Duration(seconds: 4));
      final address = addresses.where(isPublicLocationAddress).firstOrNull;
      if (address == null || _closed) return location;
      final ip = address.address;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'server_geo_$ip';
      Map<String, dynamic>? data;
      final saved = prefs.getString(cacheKey);
      if (saved != null) {
        try {
          final entry = jsonDecode(saved) as Map;
          if (DateTime.now().millisecondsSinceEpoch - (entry['time'] as num) <
              const Duration(days: 7).inMilliseconds) {
            data = Map<String, dynamic>.from(entry['data']);
          }
        } catch (_) {}
      }
      if (data == null) {
        if (_closed) return location;
        final response = await client
            .get(Uri.https('ipwho.is', '/$ip'))
            .timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) return location;
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        if (IpLocation.fromResponse(ip, data).hasCoordinates) {
          // Bound persistent storage even after many different subscriptions.
          final keys =
              prefs
                  .getKeys()
                  .where((key) => key.startsWith('server_geo_'))
                  .toList()
                ..sort();
          if (keys.length >= 512 && !keys.contains(cacheKey))
            await prefs.remove(keys.first);
          await prefs.setString(
            cacheKey,
            jsonEncode({
              'time': DateTime.now().millisecondsSinceEpoch,
              'data': data,
            }),
          );
        }
      }
      location = IpLocation.fromResponse(ip, data);
    } catch (_) {
      /* Unresolved hosts stay in the list without invented coordinates. */
    }
    if (_cached.length >= 512) _cached.remove(_cached.keys.first);
    _cached[host] = (
      DateTime.now().add(
        location.hasCoordinates
            ? const Duration(hours: 6)
            : const Duration(minutes: 5),
      ),
      location,
    );
    return location;
  }

  void close() {
    _closed = true;
    client.close();
  }
}

/// A map location of an automatic group must connect to that specific member.
/// Keep DNS and direct/block rules; route the group's proxy traffic to the tag.
ProxyConfig connectionForEndpoint(ProxyConfig config, ServerEndpoint endpoint) {
  if (!endpoint.grouped) return config;
  final raw =
      config.rawJsonOverride ??
      (config is CustomConfig ? config.jsonString : null);
  if (raw == null)
    throw const FormatException('Не удалось выбрать узел группы');
  final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  final outbounds = (data['outbounds'] as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final selected = outbounds
      .where((o) => o['tag'] == endpoint.label)
      .firstOrNull;
  if (selected == null)
    throw const FormatException('Не удалось выбрать узел группы');
  final tag = endpoint.label;
  if (selected.containsKey('protocol')) {
    final routing = Map<String, dynamic>.from(data['routing'] as Map? ?? {});
    final balancers = (routing['balancers'] as List? ?? []).whereType<Map>();
    final affected = {
      for (final b in balancers)
        if ((b['selector'] as List? ?? []).any(
          (prefix) => tag.startsWith('$prefix'),
        ))
          b['tag'],
    };
    routing['rules'] = [
      for (final rule in routing['rules'] as List? ?? [])
        if (rule is Map && affected.contains(rule['balancerTag']))
          {
            ...(Map<String, dynamic>.from(rule)..remove('balancerTag')),
            'outboundTag': tag,
          }
        else
          rule,
    ];
    data['routing'] = routing;
    // Xray's default is its first outbound.
    data['outbounds'] = [selected, ...outbounds.where((o) => o['tag'] != tag)];
  } else {
    final route = Map<String, dynamic>.from(data['route'] as Map? ?? {});
    final affected = <String>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (final o in outbounds) {
        if (!const {'selector', 'urltest'}.contains(o['type'])) continue;
        if ((o['outbounds'] as List? ?? []).any(
          (member) => member == tag || affected.contains(member),
        )) {
          if (affected.add('${o['tag']}')) changed = true;
        }
      }
    }
    dynamic pinRule(dynamic rule) {
      if (rule is! Map) return rule;
      return {
        ...rule,
        if (affected.contains(rule['outbound'])) 'outbound': tag,
        if (rule['rules'] is List)
          'rules': [for (final child in rule['rules']) pinRule(child)],
      };
    }

    route['final'] = tag;
    if (route['rules'] is List)
      route['rules'] = [for (final rule in route['rules']) pinRule(rule)];
    data['route'] = route;
  }
  data['remarks'] = '${config.name} · $tag';
  return CustomConfig.parseJson(jsonEncode(data));
}

bool hasAutomaticRouting(ProxyConfig config) {
  final data = config.finalJson;
  return (data['routing'] is Map &&
          (data['routing']['balancers'] as List? ?? []).isNotEmpty) ||
      (data['outbounds'] as List? ?? []).whereType<Map>().any(
        (o) => const {'selector', 'urltest'}.contains(o['type']),
      );
}

/// Chain hops are actual outbounds, not complete subscription configurations.
ProxyConfig chainNodeForEndpoint(ProxyConfig config, ServerEndpoint endpoint) {
  final data = config.finalJson;
  final candidates = [
    ...(data['outbounds'] as List? ?? []),
    ...(data['endpoints'] as List? ?? []),
  ].whereType<Map>();
  final node = candidates.where((o) => o['tag'] == endpoint.label).firstOrNull;
  if (node == null) {
    if (!endpoint.grouped &&
        !data.containsKey('outbounds') &&
        !data.containsKey('endpoints')) {
      return ProxyParser.fromMap(config.toMap());
    }
    throw const FormatException('Не удалось выбрать узел группы');
  }
  final outbound = Map<String, dynamic>.from(node);
  if (outbound['detour'] != null ||
      (outbound['streamSettings'] is Map &&
          outbound['streamSettings']['sockopt'] is Map &&
          outbound['streamSettings']['sockopt']['dialerProxy'] != null)) {
    throw const FormatException('Этот узел уже использует внутреннюю цепочку');
  }
  outbound['remarks'] = endpoint.grouped
      ? '${config.name} · ${endpoint.label}'
      : config.name;
  return CustomConfig.parseJson(jsonEncode(outbound));
}

List<ProxyConfig> chainNodesForEndpoints(
  List<(ProxyConfig, ServerEndpoint)> hops,
) {
  if (hops.length < 2) throw const FormatException('Добавьте минимум два узла');
  final nodes = [for (final hop in hops) chainNodeForEndpoint(hop.$1, hop.$2)];
  // The final hop owns routing and DNS, just like the existing chain editor.
  // Keep its concrete protocol for core selection while preserving the full config.
  final last = connectionForEndpoint(hops.last.$1, hops.last.$2);
  if (last.finalJson.containsKey('outbounds') ||
      last.finalJson.containsKey('endpoints')) {
    nodes.last.rawJsonOverride = jsonEncode(last.finalJson);
  }
  for (var i = 0; i < nodes.length; i++) nodes[i].fp = hops[i].$1.fp;
  return nodes;
}

/// Resolve a concrete stored hop without guessing an automatic group's member.
ServerEndpoint? concreteServerEndpoint(ProxyConfig config) {
  final endpoints = serverEndpoints(config);
  if (endpoints.length == 1) return endpoints.single;
  if (endpoints.isEmpty) return null;
  final data = config.finalJson;
  final storedTag = config.toOutboundJson()['tag'];
  if (config.rawJsonOverride != null && storedTag is String) {
    final pinned = endpoints.where((e) => e.label == storedTag).firstOrNull;
    if (pinned != null) return pinned;
  }
  final finalTag = data['route'] is Map ? data['route']['final'] : null;
  if (finalTag is String) {
    final exact = endpoints.where((e) => e.label == finalTag).firstOrNull;
    if (exact != null) return exact;
  }
  if (data['routing'] is Map &&
      (data['routing']['rules'] as List? ?? []).whereType<Map>().any(
        (r) => r['balancerTag'] != null,
      ))
    return null;
  if (hasAutomaticRouting(config)) return null;
  return endpoints.first;
}
