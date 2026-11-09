import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/models/proxies/custom_config.dart';
import 'package:nextlink/core/models/proxies/proxy_parser.dart';
import 'package:nextlink/core/utils/server_location.dart';
import 'package:nextlink/core/utils/ip_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'raw balancer exposes actual endpoints, not direct or a name-derived city',
    () {
      final config = CustomConfig.parseJson(
        jsonEncode({
          'remarks': 'Frankfurt',
          'routing': {'balancers': []},
          'outbounds': [
            {
              'tag': 'Warsaw',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {'address': 'pl.example.org', 'port': 443},
                ],
              },
            },
            {
              'tag': 'Actual Frankfurt',
              'type': 'hysteria2',
              'server': 'de.example.org',
            },
            {'tag': 'direct', 'protocol': 'freedom'},
          ],
        }),
      );
      final nodes = serverEndpoints(config);
      expect(nodes.map((e) => e.host), ['pl.example.org', 'de.example.org']);
      expect(nodes.every((e) => e.grouped), true);
      expect(nodes.first.label, 'Warsaw');
    },
  );
  test('selecting an Xray balancer member pins proxy rules and keeps direct/block rules', () {
    final config = CustomConfig.parseJson(
      jsonEncode({
        'remarks': 'Auto',
        'routing': {
          'balancers': [
            {
              'tag': 'auto',
              'selector': ['node-'],
            },
          ],
          'rules': [
            {
              'type': 'field',
              'domain': [r'regexp:.*\.ru$'],
              'outboundTag': 'direct',
            },
            {
              'type': 'field',
              'protocol': ['bittorrent'],
              'outboundTag': 'block',
            },
            {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'},
          ],
        },
        'outbounds': [
          {
            'tag': 'node-de',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {'address': 'de.example.org', 'port': 443},
              ],
            },
          },
          {
            'tag': 'node-pl',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {'address': 'pl.example.org', 'port': 443},
              ],
            },
          },
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
      }),
    );
    final pinned = connectionForEndpoint(config, serverEndpoints(config).last);
    final data = pinned.toOutboundJson();
    expect(data['outbounds'][0]['tag'], 'node-pl');
    expect(data['routing']['rules'][0]['outboundTag'], 'direct');
    expect(data['routing']['rules'][1]['outboundTag'], 'block');
    expect(data['routing']['rules'][2]['outboundTag'], 'node-pl');
    expect(data['routing']['rules'][2].containsKey('balancerTag'), false);
    final node = chainNodeForEndpoint(config, serverEndpoints(config).last);
    expect(node.finalJson['tag'], 'node-pl');
    expect(node.finalJson.containsKey('outbounds'), false);
    expect(node.finalJson.containsKey('routing'), false);
    expect(hasAutomaticRouting(config), true);
    expect(hasAutomaticRouting(node), false);
    final endpoints = serverEndpoints(config);
    final hops = chainNodesForEndpoints([
      (config, endpoints.first),
      (config, endpoints.last),
    ]);
    expect(hops.first.finalJson.containsKey('routing'), false);
    expect(hops.last.finalJson['routing']['rules'][0]['outboundTag'], 'direct');
    expect(hops.last.finalJson['routing']['rules'][1]['outboundTag'], 'block');
    expect(
      hops.last.finalJson['routing']['rules'][2]['outboundTag'],
      'node-pl',
    );
    expect(hops.last.finalJson['outbounds'][0]['tag'], 'node-pl');
    expect(concreteServerEndpoint(config), isNull);
    expect(concreteServerEndpoint(hops.last)?.host, 'pl.example.org');

    expect(config.toOutboundJson()['outbounds'][0]['tag'], 'node-de');
  });
  test('selecting a sing-box member pins nested selector rules', () {
    final config = CustomConfig.parseJson(
      jsonEncode({
        'remarks': 'Auto',
        'route': {
          'final': 'auto',
          'rules': [
            {
              'domain_suffix': ['ru'],
              'outbound': 'direct',
            },
            {
              'type': 'logical',
              'mode': 'or',
              'rules': [
                {
                  'domain': ['example.org'],
                  'outbound': 'auto',
                },
              ],
            },
          ],
        },
        'outbounds': [
          {
            'tag': 'auto',
            'type': 'urltest',
            'outbounds': ['de', 'pl'],
          },
          {'tag': 'de', 'type': 'vless', 'server': 'de.example.org'},
          {'tag': 'pl', 'type': 'hysteria2', 'server': 'pl.example.org'},
          {'tag': 'direct', 'type': 'direct'},
        ],
      }),
    );
    final pinned = connectionForEndpoint(
      config,
      serverEndpoints(config).last,
    ).toOutboundJson();
    expect(pinned['route']['final'], 'pl');
    expect(pinned['route']['rules'][0]['outbound'], 'direct');
    expect(pinned['route']['rules'][1]['rules'][0]['outbound'], 'pl');
  });
  test('ordinary URI and WireGuard JSON endpoints are discovered', () {
    final config = ProxyParser.parse(
      'vless://00000000-0000-0000-0000-000000000001@de.example.org:443?security=tls#Warsaw',
    );
    expect(serverEndpoints(config).single.host, 'de.example.org');
    final wg = CustomConfig.parseJson(
      jsonEncode({
        'outbounds': [
          {
            'protocol': 'wireguard',
            'settings': {
              'peers': [
                {'endpoint': '1.1.1.1:2408'},
              ],
            },
          },
        ],
      }),
    );
    expect(serverEndpoints(wg).single.host, '1.1.1.1');
  });
  test('coordinates and metadata validate the response IP and ranges', () {
    final response = {
      'success': true,
      'ip': '1.1.1.1',
      'country_code': 'DE',
      'city': 'Frankfurt',
      'latitude': 50.1,
      'longitude': 8.68,
      'timezone': {'id': 'Europe/Berlin', 'utc': '+01:00'},
      'calling_code': '49',
    };
    final location = IpLocation.fromResponse('1.1.1.1', response);
    expect(location.hasCoordinates, true);
    expect(location.utc, '+01:00');
    expect(location.city, 'Frankfurt');
    expect(IpLocation.fromResponse('8.8.8.8', response).hasCoordinates, false);
    expect(
      IpLocation.fromResponse('1.1.1.1', {
        ...response,
        'latitude': 91,
      }).hasCoordinates,
      false,
    );
  });
  test(
    'private endpoint addresses never reach the external geolocation API',
    () async {
      var requests = 0;
      final lookup = ServerLocationLookup(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(lookup.close);
      for (final ip in [
        '127.0.0.1',
        '10.0.0.2',
        '192.168.1.1',
        '172.16.0.1',
        '100.64.0.1',
        '::1',
        'fc00::1',
      ]) {
        expect((await lookup.lookup(ip)).hasCoordinates, false);
      }
      expect(requests, 0);
    },
  );
  test(
    'lookup coalesces concurrent requests and persists a cache per IP',
    () async {
      var requests = 0;
      final client = MockClient((req) async {
        requests++;
        expect(req.url.host, 'ipwho.is');
        expect(req.url.path, '/1.1.1.1');
        return http.Response(
          jsonEncode({
            'success': true,
            'ip': '1.1.1.1',
            'country_code': 'DE',
            'city': 'Frankfurt',
            'latitude': 50.1,
            'longitude': 8.68,
          }),
          200,
        );
      });
      final lookup = ServerLocationLookup(
        client: client,
        resolve: (_) async => [InternetAddress('1.1.1.1')],
      );
      await Future.wait([
        lookup.lookup('de.example.org'),
        lookup.lookup('de.example.org'),
      ]);
      expect(requests, 1);
      lookup.close();
      final cached = ServerLocationLookup(
        client: MockClient(
          (_) async => throw StateError('should use disk cache'),
        ),
      );
      addTearDown(cached.close);
      expect((await cached.lookup('1.1.1.1')).city, 'Frankfurt');
    },
  );
}
