import 'dart:convert';
import 'dart:io';

import 'proxy_config.dart';

/// A WireGuard/WARP or AmneziaWG profile. Keys and obfuscation are retained
/// when persisting, sharing, or editing the original configuration.
class WireGuardConfig extends ProxyConfig {
  final String source;
  final Map<String, String> interface;
  final List<Map<String, String>> peers;

  WireGuardConfig._(this.source, this.interface, this.peers, String name)
    : super(
        protocol: _isAwg(interface)
            ? 'AMNEZIAWG'
            : (peers.any(
                    (p) =>
                        p['endpoint']?.contains('cloudflare') == true ||
                        p.containsKey('reserved'),
                  )
                  ? 'WARP'
                  : 'WIREGUARD'),
        name: name,
        address: _endpoint(peers.first['endpoint']!).$1,
        port: _endpoint(peers.first['endpoint']!).$2,
      );

  /// Import ready-to-use JSON profiles; account/registration data alone is not a tunnel.
  static WireGuardConfig fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> normalize(Map value) => {
      for (final e in value.entries)
        e.key.toString().toLowerCase().replaceAll(RegExp(r'[_\-]'), ''):
            e.value,
    };
    final root = normalize(json);
    final iface = root['interface'] is Map
        ? normalize(root['interface'] as Map)
        : root['settings'] is Map
        ? normalize(root['settings'] as Map)
        : root;
    String list(dynamic value) =>
        value is List ? value.join(', ') : value?.toString() ?? '';
    String addresses(dynamic value) {
      final values = value is Map
          ? value.values.toList()
          : value is List
          ? value
          : list(value).split(',');
      return values
          .map((v) {
            final address = v.toString().trim();
            final ip = InternetAddress.tryParse(address);
            return ip == null
                ? address
                : '$address/${ip.type == InternetAddressType.IPv4 ? 32 : 128}';
          })
          .where((v) => v.isNotEmpty)
          .join(', ');
    }

    final conf = StringBuffer('[Interface]\n');
    conf.writeln(
      'PrivateKey = ${iface['privatekey'] ?? iface['secretkey'] ?? root['privatekey'] ?? ''}',
    );
    conf.writeln(
      'Address = ${addresses(iface['localaddress'] ?? iface['address'] ?? iface['addresses'])}',
    );
    for (final key in [
      'dns',
      'mtu',
      'listenport',
      'headerprotectionkey',
      'contentpaddingaddition',
      'rekeyaftertime',
      'rekeytimeout',
      'rejectaftertime',
      'keepalivetimeout',
      'maxhandshakeattempts',
      'randomtrailers',
      'disablecookies',
      'jc',
      'jmin',
      'jmax',
      's1',
      's2',
      's3',
      's4',
      'h1',
      'h2',
      'h3',
      'h4',
      'i1',
      'i2',
      'i3',
      'i4',
      'i5',
    ]) {
      final value =
          iface[key] ??
          (iface['awg'] is Map ? normalize(iface['awg'] as Map)[key] : null);
      if (value != null) conf.writeln('$key = ${list(value)}');
    }
    final rawPeers = iface['peers'] ?? root['peers'] ?? root['peer'];
    final peers = rawPeers is List
        ? rawPeers
        : rawPeers is Map
        ? [rawPeers]
        : [root];
    for (final raw in peers) {
      if (raw is! Map)
        throw const FormatException('Peer должен быть JSON-объектом');
      final peer = normalize(raw);
      var endpoint = peer['endpoint'];
      if (endpoint is Map)
        endpoint = endpoint['v4'] ?? endpoint['v6'] ?? endpoint['host'];
      final host = peer['server'] ?? peer['address'];
      final port = peer['serverport'] ?? peer['port'];
      if (endpoint == null && host != null && port != null) {
        final server = host.toString().replaceAll('[', '').replaceAll(']', '');
        endpoint = '${server.contains(':') ? '[$server]' : server}:$port';
      }
      conf.writeln('[Peer]');
      conf.writeln(
        'PublicKey = ${peer['publickey'] ?? peer['peerpublickey'] ?? root['peerpublickey'] ?? ''}',
      );
      conf.writeln('Endpoint = ${endpoint ?? ''}');
      conf.writeln(
        'AllowedIPs = ${list(peer['allowedips'] ?? ['0.0.0.0/0', '::/0'])}',
      );
      final reserved =
          peer['reserved'] ?? iface['reserved'] ?? root['reserved'];
      if (reserved != null) conf.writeln('Reserved = ${list(reserved)}');
      final psk = peer['presharedkey'] ?? root['presharedkey'];
      if (psk != null) conf.writeln('PresharedKey = $psk');
      final keepalive =
          peer['persistentkeepaliveinterval'] ??
          peer['persistentkeepalive'] ??
          peer['keepalive'];
      if (keepalive != null) conf.writeln('PersistentKeepalive = $keepalive');
    }
    return parse(
      conf.toString(),
      name: (root['name'] ?? root['remarks'] ?? root['tag'])?.toString(),
    );
  }

  static bool _isAwg(Map<String, String> values) => values.keys.any(
    (k) => RegExp(
      r'^(jc|jmin|jmax|s[1-4]|h[1-4]|i[1-5]|headerprotectionkey|contentpaddingaddition|rekeyaftertime|rekeytimeout|rejectaftertime|keepalivetimeout|maxhandshakeattempts|randomtrailers|disablecookies)$',
    ).hasMatch(k),
  );

  static (String, int) _endpoint(String value) {
    final uri = Uri.tryParse('udp://${value.trim()}');
    if (uri == null ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
        'Endpoint должен иметь вид host:port или [IPv6]:port',
      );
    }
    return (uri.host.replaceAll('[', '').replaceAll(']', ''), uri.port);
  }

  static List<String> _list(String? value) => (value ?? '')
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  static void _key(String? key, String label) {
    try {
      if (key != null && base64Decode(key).length == 32) return;
    } catch (_) {}
    throw FormatException(
      '$label должен быть ключом WireGuard (32 байта в base64)',
    );
  }

  static WireGuardConfig parse(String text, {String? name}) {
    if (!text.trimLeft().startsWith('[')) return _parseUri(text);
    final interface = <String, String>{};
    final peers = <Map<String, String>>[];
    Map<String, String>? section;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty || line.startsWith(';')) continue;
      if (line.toLowerCase() == '[interface]') {
        section = interface;
        continue;
      }
      if (line.toLowerCase() == '[peer]') {
        section = <String, String>{};
        peers.add(section);
        continue;
      }
      final split = line.indexOf('=');
      if (section == null || split <= 0)
        throw const FormatException('Некорректный файл WireGuard');
      final key = line.substring(0, split).trim().toLowerCase();
      final value = line.substring(split + 1).trim();
      section[key] =
          section.containsKey(key) &&
              ['address', 'dns', 'allowedips'].contains(key)
          ? '${section[key]},$value'
          : value;
    }
    for (final field in const ['headerprotectionkey']) {
      if (interface[field] != null) _key(interface[field], field);
    }
    for (final field in const [
      'contentpaddingaddition',
      'rekeyaftertime',
      'rekeytimeout',
      'rejectaftertime',
      'keepalivetimeout',
      'maxhandshakeattempts',
    ]) {
      final raw = interface[field];
      if (raw == null) continue;
      final parts = raw.split('-').map(int.tryParse).toList();
      if (parts.isEmpty ||
          parts.length > 2 ||
          parts.any((n) => n == null || n < 0 || n > 65535) ||
          (parts.length == 2 && parts[0]! > parts[1]!))
        throw FormatException('$field: нужно число или диапазон 0–65535');
    }
    for (final field in const ['randomtrailers', 'disablecookies']) {
      if (interface[field] != null &&
          ![
            'on',
            'off',
            'true',
            'false',
            '0',
            '1',
          ].contains(interface[field]!.toLowerCase()))
        throw FormatException('$field: on или off');
    }
    _key(interface['privatekey'], 'PrivateKey');
    if (_list(interface['address']).isEmpty)
      throw const FormatException('В Interface не задан Address');
    if (peers.isEmpty) throw const FormatException('В конфигурации нет Peer');
    interface['address'] = _list(interface['address'])
        .map((address) {
          // Exporters may omit host prefixes in Interface.Address. AllowedIPs
          // remains strict because it describes networks, rather than local hosts.
          final ip = InternetAddress.tryParse(address);
          final prefix = ip == null
              ? address
              : '$address/${ip.type == InternetAddressType.IPv4 ? 32 : 128}';
          _prefix(prefix);
          return prefix;
        })
        .join(', ');
    for (final field in [
      'mtu',
      'listenport',
      'jc',
      'jmin',
      'jmax',
      's1',
      's2',
      's3',
      's4',
    ]) {
      if (interface[field] == null) continue;
      final n = int.tryParse(interface[field]!);
      if (n == null || n < 0 || n > 65535)
        throw FormatException('$field должен быть целым числом от 0 до 65535');
    }
    if ((int.tryParse(interface['jmax'] ?? '') ?? 0) <
        (int.tryParse(interface['jmin'] ?? '') ?? 0)) {
      throw const FormatException('Jmax не может быть меньше Jmin');
    }
    for (final peer in peers) {
      if (peer['reserved'] == null && interface['reserved'] != null)
        peer['reserved'] = interface['reserved']!;
      final keepalive = int.tryParse(peer['persistentkeepalive'] ?? '0');
      if (keepalive == null || keepalive < 0 || keepalive > 65535)
        throw const FormatException('PersistentKeepalive: диапазон 0–65535');
      _key(peer['publickey'], 'PublicKey');
      if (peer.containsKey('presharedkey'))
        _key(peer['presharedkey'], 'PresharedKey');
      _endpoint(peer['endpoint'] ?? '');
      if (_list(peer['allowedips']).isEmpty)
        throw const FormatException('В Peer не задан AllowedIPs');
      for (final prefix in _list(peer['allowedips'])) {
        _prefix(prefix);
      }
      if (peer['reserved'] != null) _reserved(peer['reserved']!);
    }
    return WireGuardConfig._(
      text,
      interface,
      peers,
      name ?? (_isAwg(interface) ? 'AmneziaWG' : 'WireGuard / WARP'),
    );
  }

  static void _prefix(String value) {
    final parts = value.split('/');
    final ip = InternetAddress.tryParse(parts.first);
    final bits = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (ip == null ||
        bits == null ||
        bits < 0 ||
        bits > (ip.type == InternetAddressType.IPv4 ? 32 : 128)) {
      throw FormatException('Некорректный IP-префикс: $value');
    }
  }

  static List<int> _reserved(String raw) {
    final text = raw.replaceAll('[', '').replaceAll(']', '').trim();
    List<int> result;
    try {
      result = text.contains(',')
          ? text.split(',').map((s) => int.parse(s.trim())).toList()
          : base64Decode(text);
    } catch (_) {
      throw const FormatException('Reserved: нужны три байта или base64');
    }
    if (result.length != 3 || result.any((v) => v < 0 || v > 255)) {
      throw const FormatException(
        'Reserved должен содержать ровно три байта от 0 до 255',
      );
    }
    return result;
  }

  static WireGuardConfig _parseUri(String text) {
    final uri = Uri.parse(text.trim());
    final q = {
      for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value,
    };
    if (uri.userInfo.isEmpty || uri.host.isEmpty || !uri.hasPort) {
      throw const FormatException(
        'Нужен готовый WireGuard/WARP конфиг с ключами и Endpoint',
      );
    }
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final conf = StringBuffer(
      '[Interface]\nPrivateKey = ${Uri.decodeComponent(uri.userInfo)}\nAddress = ${q['address'] ?? q['ip'] ?? ''}\n',
    );
    if (['awg', 'amneziawg'].contains(uri.scheme) && !q.containsKey('jc'))
      conf.writeln('Jc = 0');
    for (final k in [
      'dns',
      'mtu',
      'headerprotectionkey',
      'contentpaddingaddition',
      'rekeyaftertime',
      'rekeytimeout',
      'rejectaftertime',
      'keepalivetimeout',
      'maxhandshakeattempts',
      'randomtrailers',
      'disablecookies',
      'jc',
      'jmin',
      'jmax',
      's1',
      's2',
      's3',
      's4',
      'h1',
      'h2',
      'h3',
      'h4',
      'i1',
      'i2',
      'i3',
      'i4',
      'i5',
    ]) {
      if (q.containsKey(k)) conf.writeln('$k = ${q[k]}');
    }
    conf.writeln(
      '[Peer]\nPublicKey = ${q['publickey'] ?? q['public_key'] ?? ''}\nEndpoint = $host:${uri.port}\nAllowedIPs = ${q['allowedips'] ?? '0.0.0.0/0, ::/0'}',
    );
    if (q['presharedkey'] != null)
      conf.writeln('PresharedKey = ${q['presharedkey']}');
    if (q['reserved'] != null) conf.writeln('Reserved = ${q['reserved']}');
    conf.writeln('PersistentKeepalive = ${q['keepalive'] ?? '25'}');
    return parse(
      conf.toString(),
      name: uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : uri.scheme == 'warp'
          ? 'WARP'
          : null,
    );
  }

  static bool _covered(String address, List<String> prefixes) {
    final ip = InternetAddress.tryParse(address);
    if (ip == null) return false;
    for (final prefix in prefixes) {
      final parts = prefix.split('/');
      final network = InternetAddress.tryParse(parts.first)!;
      if (network.type != ip.type) continue;
      final bits = int.parse(parts.last);
      var matches = true;
      for (var i = 0; i < bits; i++) {
        final mask = 1 << (7 - i % 8);
        if ((network.rawAddress[i ~/ 8] & mask) !=
            (ip.rawAddress[i ~/ 8] & mask)) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  @override
  String toUri() => source;

  @override
  Map<String, dynamic> toOutboundJson() {
    final awg = _isAwg(interface);
    final allowed = peers
        .expand((p) => _list(p['allowedips']))
        .toSet()
        .toList();
    final dns = _list(interface['dns'])
        .where((v) => InternetAddress.tryParse(v) != null)
        .toList();
    return {
      'endpoints': [
        {
          'type': awg ? 'awg' : 'wireguard',
          'tag': 'proxy',
          'address': _list(interface['address']),
          'private_key': interface['privatekey'],
          'mtu': int.tryParse(interface['mtu'] ?? '') ?? 1280,
          if (interface['listenport'] != null)
            'listen_port': int.parse(interface['listenport']!),
          if (awg) ...{
            for (final e in interface.entries)
              if (RegExp(r'^(jc|jmin|jmax|s[1-4]|h[1-4]|i[1-5])$')
                  .hasMatch(e.key))
                e.key: RegExp(r'^(jc|jmin|jmax|s[1-4])$').hasMatch(e.key)
                    ? int.parse(e.value)
                    : e.value,
            for (final e in const {
              'headerprotectionkey': 'header_protection_key',
              'contentpaddingaddition': 'content_padding_addition',
              'rekeyaftertime': 'rekey_after_time',
              'rekeytimeout': 'rekey_timeout',
              'rejectaftertime': 'reject_after_time',
              'keepalivetimeout': 'keepalive_timeout',
              'maxhandshakeattempts': 'max_handshake_attempts',
            }.entries)
              if (interface[e.key] != null) e.value: interface[e.key],
            for (final e in const {
              'randomtrailers': 'random_trailers',
              'disablecookies': 'disable_cookies',
            }.entries)
              if (interface[e.key] != null)
                e.value: [
                  'on',
                  'true',
                  '1',
                ].contains(interface[e.key]!.toLowerCase()),
          },
          'peers': peers
              .map(
                (p) => {
                  'address': _endpoint(p['endpoint']!).$1,
                  'port': _endpoint(p['endpoint']!).$2,
                  'public_key': p['publickey'],
                  'allowed_ips': _list(p['allowedips']),
                  if (p['presharedkey'] != null)
                    (awg ? 'preshared_key' : 'pre_shared_key'):
                        p['presharedkey'],
                  'persistent_keepalive_interval':
                      int.tryParse(p['persistentkeepalive'] ?? '') ?? 0,
                  if (p['reserved'] != null)
                    'reserved': _reserved(p['reserved']!),
                },
              )
              .toList(),
          'domain_resolver': 'direct-dns',
        },
      ],
      'dns': {
        'servers': [
          {'type': 'udp', 'tag': 'direct-dns', 'server': '1.1.1.1'},
          for (var i = 0; i < dns.length; i++)
            {
              'type': 'udp',
              'tag': 'wg-dns-$i',
              'server': dns[i],
              if (_covered(dns[i], allowed)) 'detour': 'proxy',
            },
        ],
        'final': dns.isEmpty ? 'direct-dns' : 'wg-dns-0',
      },
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': {
        'final': allowed.contains('0.0.0.0/0') && allowed.contains('::/0')
            ? 'proxy'
            : 'direct',
        'default_domain_resolver': dns.isEmpty ? 'direct-dns' : 'wg-dns-0',
        'rules': [
          // SOCKS/HTTP destinations can be domains. Resolve them before matching
          // AllowedIPs, otherwise split tunnels silently fall through to direct.
          {'action': 'resolve'},
          {'ip_cidr': allowed, 'outbound': 'proxy'},
        ],
      },
    };
  }

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'classType': 'WireGuardConfig',
    'configText': source,
  };
}
