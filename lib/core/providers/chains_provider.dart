import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxies/proxy_config.dart';
import '../models/proxies/proxy_parser.dart';

class ProxyChain {
  final String id;
  final String name;
  final bool isActive;
  final List<ProxyConfig> nodes;

  ProxyChain({
    required this.id,
    required this.name,
    this.isActive = false,
    required this.nodes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'isActive': isActive,
      'nodes': nodes.map((n) => n.toMap()).toList(),
    };
  }

  factory ProxyChain.fromMap(Map<String, dynamic> map) {
    return ProxyChain(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Chain',
      isActive: map['isActive'] ?? false,
      nodes: (map['nodes'] as List? ?? [])
          .map((n) => ProxyParser.fromMap(n))
          .toList(),
    );
  }

  ProxyChain copyWith({
    String? id,
    String? name,
    bool? isActive,
    List<ProxyConfig>? nodes,
  }) {
    return ProxyChain(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      nodes: nodes ?? this.nodes,
    );
  }
}

class ChainsNotifier extends StateNotifier<List<ProxyChain>> {
  late final Future<void> ready;
  ChainsNotifier() : super([]) {
    ready = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('custom_proxy_chains');
    if (data != null) {
      try {
        final List decoded = jsonDecode(data);
        state = decoded.map((e) => ProxyChain.fromMap(e)).toList();
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_proxy_chains',
      jsonEncode(state.map((e) => e.toMap()).toList()),
    );
  }

  void addChain(ProxyChain chain) {
    state = [...state, chain];
    _save();
  }

  void updateChain(ProxyChain updated) {
    state = state.map((c) => c.id == updated.id ? updated : c).toList();
    _save();
  }

  void removeChain(String id) {
    state = state.where((c) => c.id != id).toList();
    _save();
  }

  void setActiveChain(String? id) {
    state = state.map((c) {
      return c.copyWith(isActive: c.id == id);
    }).toList();
    _save();
  }
}

final chainsProvider = StateNotifierProvider<ChainsNotifier, List<ProxyChain>>(
  (ref) => ChainsNotifier(),
);
