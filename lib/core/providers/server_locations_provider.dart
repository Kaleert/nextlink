import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/ip_location.dart';
import '../models/proxies/proxy_config.dart';
import 'chains_provider.dart';
import '../utils/server_location.dart';
import 'subscription_provider.dart';

final serverLocationLookupProvider = Provider((ref) {
  final lookup = ServerLocationLookup();
  ref.onDispose(lookup.close);
  return lookup;
});

final globeServersProvider = Provider<List<ProxyConfig>>((ref) {
  final unique = <String, ProxyConfig>{};
  for (final sub in ref.watch(subscriptionProvider)) {
    for (final server in sub.servers) unique[server.uniqueKey] = server;
  }
  for (final chain in ref.watch(chainsProvider)) {
    for (final node in chain.nodes)
      unique.putIfAbsent(node.uniqueKey, () => node);
  }
  return unique.values.toList();
});

final automaticSubscriptionConfigsProvider = Provider<List<ProxyConfig>>(
  (ref) => [
    for (final sub in ref.watch(subscriptionProvider))
      if (sub.url.isNotEmpty)
        for (final config in sub.servers)
          if (hasAutomaticRouting(config)) config,
  ],
);

final serverLocationsProvider =
    StreamProvider.autoDispose<Map<String, IpLocation>>((ref) async* {
      // Pings and active-server changes don't restart DNS/geolocation requests.
      final signature = ref.watch(
        globeServersProvider.select(
          (servers) => jsonEncode([
            for (final server in servers)
              for (final endpoint in serverEndpoints(server)) endpoint.host,
          ]),
        ),
      );
      final hosts = (jsonDecode(signature) as List)
          .cast<String>()
          .toSet()
          .toList();
      final lookup = ref.read(serverLocationLookupProvider);
      var cancelled = false;
      ref.onDispose(() => cancelled = true);
      final locations = <String, IpLocation>{};
      yield locations;
      // Small batches respect the API's rate limit and progressively paint markers.
      for (var i = 0; i < hosts.length && !cancelled; i += 3) {
        final batch = hosts.skip(i).take(3).toList();
        final result = await Future.wait(batch.map(lookup.lookup));
        if (cancelled) return;
        for (var j = 0; j < batch.length; j++) locations[batch[j]] = result[j];
        yield Map.unmodifiable(locations);
        if (i + 3 < hosts.length)
          await Future<void>.delayed(const Duration(milliseconds: 4200));
      }
    });
