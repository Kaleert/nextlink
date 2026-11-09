import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppProfile {
  final String id;
  final String name;
  final List<String> triggers;
  final String? serverKey;
  final List<String> serverKeys;
  final int intervalMinutes;
  final bool isEnabled;

  AppProfile({
    required this.id,
    required this.name,
    String? trigger,
    List<String>? triggers,
    this.serverKey,
    this.serverKeys = const [],
    this.intervalMinutes = 30,
    this.isEnabled = false,
  }) : triggers =
           triggers ?? (trigger == null ? [] : [_normalizeTrigger(trigger)]);

  String get trigger => triggers.isEmpty ? 'manual_trigger' : triggers.first;
  bool hasTrigger(String value) => triggers.contains(value);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'trigger': trigger,
    'triggers': triggers,
    'serverKey': serverKey,
    'serverKeys': serverKeys,
    'intervalMinutes': intervalMinutes,
    'isEnabled': isEnabled,
  };

  factory AppProfile.fromMap(Map<String, dynamic> map) => AppProfile(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    triggers: map['triggers'] is List
        ? (map['triggers'] as List)
              .map((value) => _normalizeTrigger(value?.toString()))
              .toSet()
              .toList()
        : [_normalizeTrigger(map['trigger']?.toString())],
    serverKey: map['serverKey']?.toString(),
    serverKeys: (map['serverKeys'] as List? ?? [])
        .whereType<String>()
        .toSet()
        .toList(),
    intervalMinutes: ((map['intervalMinutes'] as num?)?.toInt() ?? 30).clamp(
      1,
      1440,
    ),
    isEnabled: map['isEnabled'] ?? false,
  );

  static String _normalizeTrigger(String? trigger) => switch (trigger) {
    'Любая сеть' => 'any_network',
    'Неизвестная сеть' => 'wifi',
    'Ручной запуск' => 'manual_trigger',
    'any_network' ||
    'wifi' ||
    'mobile' ||
    'wifi_to_mobile' ||
    'network_change' ||
    'hotspot' ||
    'timer' ||
    'timeout' ||
    'quick_tile' ||
    'manual_trigger' => trigger!,
    _ => 'manual_trigger',
  };

  AppProfile copyWith({
    String? id,
    String? name,
    String? trigger,
    List<String>? triggers,
    String? serverKey,
    List<String>? serverKeys,
    int? intervalMinutes,
    bool? isEnabled,
  }) {
    return AppProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      triggers: triggers ?? (trigger == null ? this.triggers : [trigger]),
      serverKey: serverKey ?? this.serverKey,
      serverKeys: serverKeys ?? this.serverKeys,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class ProfilesNotifier extends StateNotifier<List<AppProfile>> {
  late final Future<void> ready;

  ProfilesNotifier() : super([]) {
    ready = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('saved_app_profiles');
    if (data == null) return;
    try {
      final decoded = jsonDecode(data) as List;
      final profiles = decoded.map(
        (e) => AppProfile.fromMap(Map<String, dynamic>.from(e as Map)),
      );
      if (!mounted) return;
      state = profiles
          .where(
            (p) =>
                !(p.id == '1' &&
                    p.name == 'Основной' &&
                    !p.isEnabled &&
                    p.serverKey == null &&
                    p.triggers.every((t) => t == 'manual_trigger')),
          )
          .map((p) {
            final triggers = p.triggers
                .where((t) => t != 'manual_trigger' && t != 'quick_tile')
                .toList();
            return p.copyWith(
              triggers: triggers,
              isEnabled: p.isEnabled && triggers.isNotEmpty,
            );
          })
          .toList();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_app_profiles',
      jsonEncode(state.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> rebindServerKeys(Map<String, String> replacements) async {
    await ready;
    if (!mounted) return;
    state = state
        .map(
          (p) => p.copyWith(
            serverKey: replacements[p.serverKey] ?? p.serverKey,
            serverKeys: p.serverKeys
                .map((key) => replacements[key] ?? key)
                .toSet()
                .toList(),
          ),
        )
        .toList();
    await _save();
  }

  Future<void> addProfile(AppProfile profile) async {
    await ready;
    if (!mounted) return;
    state = [...state, profile];
    await _save();
  }

  Future<void> updateProfile(AppProfile updated) async {
    await ready;
    if (!mounted) return;
    state = state
        .map((profile) => profile.id == updated.id ? updated : profile)
        .toList();
    await _save();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await ready;
    if (!mounted) return;
    state = state
        .map(
          (profile) =>
              profile.id == id ? profile.copyWith(isEnabled: enabled) : profile,
        )
        .toList();
    await _save();
  }

  Future<void> removeProfile(String id) async {
    await ready;
    if (!mounted) return;
    state = state.where((p) => p.id != id).toList();
    await _save();
  }
}

final profilesProvider =
    StateNotifierProvider<ProfilesNotifier, List<AppProfile>>(
      (ref) => ProfilesNotifier(),
    );
