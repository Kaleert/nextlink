import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxies/proxy_config.dart';
import '../models/proxies/proxy_parser.dart';

/// One last runtime choice, outside subscriptions and the manual server list.
class MapServerSelection {
  final ProxyConfig server;
  final String? anchorKey, sourceKey;
  const MapServerSelection(this.server, {this.anchorKey, this.sourceKey});
  bool appliesTo(String? activeKey) => anchorKey == activeKey;
  Map<String, dynamic> toMap() => {
    'server': server.toMap(),
    'anchorKey': anchorKey,
    'sourceKey': sourceKey,
  };
  factory MapServerSelection.fromMap(Map map) => MapServerSelection(
    ProxyParser.fromMap(Map<String, dynamic>.from(map['server'])),
    anchorKey: map['anchorKey'] as String?,
    sourceKey: map['sourceKey'] as String?,
  );
}

class MapSelectionNotifier extends StateNotifier<MapServerSelection?> {
  late final Future<void> ready;
  Future<void> _writes = Future.value();
  MapSelectionNotifier() : super(null) {
    ready = _load();
  }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = prefs.getString('map_runtime_selection');
      if (saved != null && mounted)
        state = MapServerSelection.fromMap(jsonDecode(saved) as Map);
    } catch (_) {
      /* Invalid old choices must not prevent starting the VPN. */
    }
  }

  Future<void> choose(MapServerSelection? selection) async {
    await ready;
    return setCurrent(selection);
  }

  Future<void> setCurrent(MapServerSelection? selection) {
    if (!mounted) return Future.value();
    state = selection;
    _writes = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (selection == null)
        await prefs.remove('map_runtime_selection');
      else
        await prefs.setString(
          'map_runtime_selection',
          jsonEncode(selection.toMap()),
        );
    });
    return _writes;
  }
}

final mapSelectionProvider =
    StateNotifierProvider<MapSelectionNotifier, MapServerSelection?>(
      (ref) => MapSelectionNotifier(),
    );
