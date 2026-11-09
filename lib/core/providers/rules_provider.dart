import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppRule {
  final String id;
  final String type; // GeoSite, GeoIP, Domain Keyword, Port
  final String value; // например "youtube, netflix" или "ru"
  final String action; // PROXY, DIRECT, BLOCK
  final Map<String, dynamic>? conditions;

  AppRule({
    required this.id,
    required this.type,
    required this.value,
    required this.action,
    this.conditions,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'value': value,
    'action': action,
    if (conditions != null) 'conditions': conditions,
  };

  factory AppRule.fromMap(Map<String, dynamic> map) => AppRule(
    id: map['id'] ?? '',
    type: map['type'] ?? 'GeoSite',
    value: map['value'] ?? '',
    action: map['action'] ?? 'PROXY',
    conditions: map['conditions'] is Map
        ? Map<String, dynamic>.from(map['conditions'])
        : null,
  );
}

class RulesNotifier extends StateNotifier<List<AppRule>> {
  late final Future<void> ready;
  RulesNotifier() : super([]) {
    ready = _load();
  }

  List<AppRule> _dedupe(List<AppRule> list) {
    final seen = <String>{};
    return list.where((rule) {
      final key =
          '${rule.type.toLowerCase()}:${rule.value.toLowerCase().trim()}';
      return seen.add(key);
    }).toList();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('custom_rules');
    if (data != null) {
      try {
        final List decoded = jsonDecode(data);
        final loaded = decoded.map((e) => AppRule.fromMap(e)).toList();
        state = _dedupe(loaded);
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_rules',
      jsonEncode(state.map((e) => e.toMap()).toList()),
    );
  }

  void addRule(AppRule rule) {
    // Дедупликация: если правило с тем же типом и значением уже есть, обновляем его
    final key = '${rule.type.toLowerCase()}:${rule.value.toLowerCase().trim()}';
    final existingIndex = state.indexWhere(
      (r) => '${r.type.toLowerCase()}:${r.value.toLowerCase().trim()}' == key,
    );

    if (existingIndex != -1) {
      final updated = [...state];
      updated[existingIndex] = rule;
      state = _dedupe(updated);
    } else {
      state = _dedupe([...state, rule]);
    }
    _save();
  }

  void addRules(Iterable<AppRule> rules) {
    var updated = [...state];
    for (final rule in rules) {
      final key =
          '${rule.type.toLowerCase()}:${rule.value.toLowerCase().trim()}';
      final index = updated.indexWhere(
        (existing) =>
            '${existing.type.toLowerCase()}:${existing.value.toLowerCase().trim()}' ==
            key,
      );
      if (index < 0) {
        updated.add(rule);
      } else {
        updated[index] = rule;
      }
    }
    state = _dedupe(updated);
    _save();
  }

  Future<void> applyPreset(List<AppRule> rules) async {
    await ready;
    final keys = rules
        .map((r) => '${r.type.toLowerCase()}:${r.value.toLowerCase().trim()}')
        .toSet();
    state = _dedupe([
      ...rules,
      ...state.where(
        (r) => !keys.contains(
          '${r.type.toLowerCase()}:${r.value.toLowerCase().trim()}',
        ),
      ),
    ]);
    await _save();
  }

  void removeRule(String id) {
    state = state.where((r) => r.id != id).toList();
    _save();
  }
}

final rulesProvider = StateNotifierProvider<RulesNotifier, List<AppRule>>(
  (ref) => RulesNotifier(),
);
