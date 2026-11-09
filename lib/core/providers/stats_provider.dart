import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StatsPeriod { today, week, month, allTime }

enum StatsNetworkType { all, wifi, mobile }

class DailyTrafficRecord {
  final int wifiRx;
  final int wifiTx;
  final int mobileRx;
  final int mobileTx;

  const DailyTrafficRecord({
    this.wifiRx = 0,
    this.wifiTx = 0,
    this.mobileRx = 0,
    this.mobileTx = 0,
  });

  int get totalWifi => wifiRx + wifiTx;
  int get totalMobile => mobileRx + mobileTx;
  int get totalRx => wifiRx + mobileRx;
  int get totalTx => wifiTx + mobileTx;
  int get total => totalWifi + totalMobile;

  DailyTrafficRecord add({
    int wifiRx = 0,
    int wifiTx = 0,
    int mobileRx = 0,
    int mobileTx = 0,
  }) => DailyTrafficRecord(
    wifiRx: this.wifiRx + wifiRx,
    wifiTx: this.wifiTx + wifiTx,
    mobileRx: this.mobileRx + mobileRx,
    mobileTx: this.mobileTx + mobileTx,
  );

  Map<String, dynamic> toMap() => {
    'wifiRx': wifiRx,
    'wifiTx': wifiTx,
    'mobileRx': mobileRx,
    'mobileTx': mobileTx,
  };

  factory DailyTrafficRecord.fromMap(Map map) => DailyTrafficRecord(
    wifiRx: _asInt(map['wifiRx']),
    wifiTx: _asInt(map['wifiTx']),
    mobileRx: _asInt(map['mobileRx']),
    mobileTx: _asInt(map['mobileTx']),
  );
}

class DailyAppTrafficRecord {
  final int wifiBytes;
  final int mobileBytes;

  const DailyAppTrafficRecord({this.wifiBytes = 0, this.mobileBytes = 0});

  int get totalBytes => wifiBytes + mobileBytes;

  DailyAppTrafficRecord add(int bytes, {required bool mobile}) => mobile
      ? DailyAppTrafficRecord(
          wifiBytes: wifiBytes,
          mobileBytes: mobileBytes + bytes,
        )
      : DailyAppTrafficRecord(
          wifiBytes: wifiBytes + bytes,
          mobileBytes: mobileBytes,
        );

  Map<String, dynamic> toMap() => {
    'wifiBytes': wifiBytes,
    'mobileBytes': mobileBytes,
  };

  factory DailyAppTrafficRecord.fromMap(Map map) => DailyAppTrafficRecord(
    wifiBytes: _asInt(map['wifiBytes']),
    mobileBytes: _asInt(map['mobileBytes']),
  );
}

int _asInt(dynamic value) => value is num ? value.toInt() : 0;

class TrafficStatsState {
  final Map<String, DailyTrafficRecord> dailyRecords;
  final Map<String, int> appBytesMap;
  final Map<String, Map<String, DailyAppTrafficRecord>> dailyAppRecords;
  final int lifetimeWifiRx;
  final int lifetimeWifiTx;
  final int lifetimeMobileRx;
  final int lifetimeMobileTx;
  final String? nativeSessionId;
  final int nativeRxBytes;
  final int nativeTxBytes;
  final Map<String, int> nativeAppBytes;
  final int nativeAppRxBytes;
  final int nativeAppTxBytes;

  const TrafficStatsState({
    this.dailyRecords = const {},
    this.appBytesMap = const {},
    this.dailyAppRecords = const {},
    this.lifetimeWifiRx = 0,
    this.lifetimeWifiTx = 0,
    this.lifetimeMobileRx = 0,
    this.lifetimeMobileTx = 0,
    this.nativeSessionId,
    this.nativeRxBytes = 0,
    this.nativeTxBytes = 0,
    this.nativeAppBytes = const {},
    this.nativeAppRxBytes = 0,
    this.nativeAppTxBytes = 0,
  });

  TrafficStatsState copyWith({
    Map<String, DailyTrafficRecord>? dailyRecords,
    Map<String, int>? appBytesMap,
    Map<String, Map<String, DailyAppTrafficRecord>>? dailyAppRecords,
    int? lifetimeWifiRx,
    int? lifetimeWifiTx,
    int? lifetimeMobileRx,
    int? lifetimeMobileTx,
    String? nativeSessionId,
    int? nativeRxBytes,
    int? nativeTxBytes,
    Map<String, int>? nativeAppBytes,
    int? nativeAppRxBytes,
    int? nativeAppTxBytes,
  }) => TrafficStatsState(
    dailyRecords: dailyRecords ?? this.dailyRecords,
    appBytesMap: appBytesMap ?? this.appBytesMap,
    dailyAppRecords: dailyAppRecords ?? this.dailyAppRecords,
    lifetimeWifiRx: lifetimeWifiRx ?? this.lifetimeWifiRx,
    lifetimeWifiTx: lifetimeWifiTx ?? this.lifetimeWifiTx,
    lifetimeMobileRx: lifetimeMobileRx ?? this.lifetimeMobileRx,
    lifetimeMobileTx: lifetimeMobileTx ?? this.lifetimeMobileTx,
    nativeSessionId: nativeSessionId ?? this.nativeSessionId,
    nativeRxBytes: nativeRxBytes ?? this.nativeRxBytes,
    nativeTxBytes: nativeTxBytes ?? this.nativeTxBytes,
    nativeAppBytes: nativeAppBytes ?? this.nativeAppBytes,
    nativeAppRxBytes: nativeAppRxBytes ?? this.nativeAppRxBytes,
    nativeAppTxBytes: nativeAppTxBytes ?? this.nativeAppTxBytes,
  );

  Map<String, dynamic> toMap() => {
    'dailyRecords': dailyRecords.map(
      (key, value) => MapEntry(key, value.toMap()),
    ),
    'appBytesMap': appBytesMap,
    'dailyAppRecords': dailyAppRecords.map(
      (day, apps) => MapEntry(
        day,
        apps.map((pkg, record) => MapEntry(pkg, record.toMap())),
      ),
    ),
    'lifetimeWifiRx': lifetimeWifiRx,
    'lifetimeWifiTx': lifetimeWifiTx,
    'lifetimeMobileRx': lifetimeMobileRx,
    'lifetimeMobileTx': lifetimeMobileTx,
    'nativeSessionId': nativeSessionId,
    'nativeRxBytes': nativeRxBytes,
    'nativeTxBytes': nativeTxBytes,
    'nativeAppBytes': nativeAppBytes,
    'nativeAppRxBytes': nativeAppRxBytes,
    'nativeAppTxBytes': nativeAppTxBytes,
  };

  factory TrafficStatsState.fromMap(Map<String, dynamic> map) {
    final dailyRecords = <String, DailyTrafficRecord>{};
    final rawDaily = map['dailyRecords'];
    if (rawDaily is Map) {
      for (final entry in rawDaily.entries) {
        if (entry.value is Map) {
          dailyRecords[entry.key.toString()] = DailyTrafficRecord.fromMap(
            entry.value as Map,
          );
        }
      }
    }
    final dailyApps = <String, Map<String, DailyAppTrafficRecord>>{};
    final rawAppsByDay = map['dailyAppRecords'];
    if (rawAppsByDay is Map) {
      for (final dayEntry in rawAppsByDay.entries) {
        if (dayEntry.value is! Map) continue;
        final apps = <String, DailyAppTrafficRecord>{};
        for (final appEntry in (dayEntry.value as Map).entries) {
          if (appEntry.value is Map) {
            apps[appEntry.key.toString()] = DailyAppTrafficRecord.fromMap(
              appEntry.value as Map,
            );
          }
        }
        dailyApps[dayEntry.key.toString()] = apps;
      }
    }
    Map<String, int> intMap(dynamic raw) => raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), _asInt(value)))
        : <String, int>{};

    return TrafficStatsState(
      dailyRecords: dailyRecords,
      appBytesMap: intMap(map['appBytesMap']),
      dailyAppRecords: dailyApps,
      lifetimeWifiRx: _asInt(map['lifetimeWifiRx']),
      lifetimeWifiTx: _asInt(map['lifetimeWifiTx']),
      lifetimeMobileRx: _asInt(map['lifetimeMobileRx']),
      lifetimeMobileTx: _asInt(map['lifetimeMobileTx']),
      nativeSessionId: map['nativeSessionId']?.toString(),
      nativeRxBytes: _asInt(map['nativeRxBytes']),
      nativeTxBytes: _asInt(map['nativeTxBytes']),
      nativeAppBytes: intMap(map['nativeAppBytes']),
      nativeAppRxBytes: _asInt(map['nativeAppRxBytes']),
      nativeAppTxBytes: _asInt(map['nativeAppTxBytes']),
    );
  }
}

class StatsNotifier extends StateNotifier<TrafficStatsState> {
  late final Future<void> _loaded;
  Future<void> _saveQueue = Future<void>.value();

  StatsNotifier() : super(const TrafficStatsState()) {
    _loaded = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('traffic_stats_history_v2');
    if (data == null) return;
    try {
      state = TrafficStatsState.fromMap(jsonDecode(data));
    } catch (_) {}
  }

  Future<void> _save() {
    final data = jsonEncode(state.toMap());
    _saveQueue = _saveQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('traffic_stats_history_v2', data);
    });
    return _saveQueue;
  }

  String _todayKey([DateTime? timestamp]) {
    final now = timestamp ?? DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> updateFromNative(
    int rxBytes,
    int txBytes, {
    bool isWifi = false,
    bool isMobile = false,
    String? sessionId,
    Map<String, int>? appBytes,
    DateTime? timestamp,
  }) async {
    await _loaded;
    final sameSession = sessionId != null && sessionId == state.nativeSessionId;
    final adoptingLegacyHistory =
        sessionId != null &&
        state.nativeSessionId == null &&
        state.dailyRecords.isNotEmpty;
    int delta(int current, int previous) =>
        current >= previous ? current - previous : current;
    final rxDelta = sameSession
        ? delta(rxBytes, state.nativeRxBytes)
        : adoptingLegacyHistory
        ? 0
        : rxBytes;
    final txDelta = sameSession
        ? delta(txBytes, state.nativeTxBytes)
        : adoptingLegacyHistory
        ? 0
        : txBytes;
    final appDeltas = <String, int>{};
    for (final entry in (appBytes ?? const <String, int>{}).entries) {
      final previous = sameSession ? (state.nativeAppBytes[entry.key] ?? 0) : 0;
      final bytes = delta(entry.value, previous);
      if (bytes > 0) appDeltas[entry.key] = bytes;
    }
    final appRxBudget = appBytes == null
        ? 0
        : delta(rxBytes, sameSession ? state.nativeAppRxBytes : 0);
    final appTxBudget = appBytes == null
        ? 0
        : delta(txBytes, sameSession ? state.nativeAppTxBytes : 0);
    if (appBytes != null) {
      _fitAppTrafficToVpnDelta(appDeltas, appRxBudget + appTxBudget);
    }

    await recordTraffic(
      deltaRx: rxDelta,
      deltaTx: txDelta,
      isWifi: isWifi,
      isMobile: isMobile,
      appTrafficDeltas: appDeltas,
      persist: false,
      timestamp: timestamp,
    );
    state = state.copyWith(
      nativeSessionId: sessionId,
      nativeRxBytes: rxBytes,
      nativeTxBytes: txBytes,
      nativeAppBytes: appBytes ?? state.nativeAppBytes,
      nativeAppRxBytes: appBytes == null ? state.nativeAppRxBytes : rxBytes,
      nativeAppTxBytes: appBytes == null ? state.nativeAppTxBytes : txBytes,
    );
    await _save();
  }

  Future<void> recordTraffic({
    required int deltaRx,
    required int deltaTx,
    required bool isWifi,
    required bool isMobile,
    Map<String, int> appTrafficDeltas = const {},
    bool persist = true,
    DateTime? timestamp,
  }) async {
    await _loaded;
    if (deltaRx <= 0 && deltaTx <= 0 && appTrafficDeltas.isEmpty) return;

    final wifi = isWifi || (!isWifi && !isMobile);
    final mobile = isMobile && !isWifi;
    final day = _todayKey(timestamp);
    final daily = Map<String, DailyTrafficRecord>.from(state.dailyRecords);
    daily[day] = (daily[day] ?? const DailyTrafficRecord()).add(
      wifiRx: wifi ? deltaRx : 0,
      wifiTx: wifi ? deltaTx : 0,
      mobileRx: mobile ? deltaRx : 0,
      mobileTx: mobile ? deltaTx : 0,
    );

    final appTotals = Map<String, int>.from(state.appBytesMap);
    final appRecords = Map<String, Map<String, DailyAppTrafficRecord>>.from(
      state.dailyAppRecords,
    );
    final todayApps = Map<String, DailyAppTrafficRecord>.from(
      appRecords[day] ?? const {},
    );
    for (final entry in appTrafficDeltas.entries) {
      if (entry.value <= 0) continue;
      appTotals[entry.key] = (appTotals[entry.key] ?? 0) + entry.value;
      todayApps[entry.key] =
          (todayApps[entry.key] ?? const DailyAppTrafficRecord()).add(
            entry.value,
            mobile: mobile,
          );
    }
    appRecords[day] = todayApps;

    state = state.copyWith(
      dailyRecords: daily,
      appBytesMap: appTotals,
      dailyAppRecords: appRecords,
      lifetimeWifiRx: state.lifetimeWifiRx + (wifi ? deltaRx : 0),
      lifetimeWifiTx: state.lifetimeWifiTx + (wifi ? deltaTx : 0),
      lifetimeMobileRx: state.lifetimeMobileRx + (mobile ? deltaRx : 0),
      lifetimeMobileTx: state.lifetimeMobileTx + (mobile ? deltaTx : 0),
    );
    if (persist) await _save();
  }

  List<String> _keysForPeriod(
    StatsPeriod period, [
    TrafficStatsState? snapshot,
  ]) {
    final stats = snapshot ?? state;
    final now = DateTime.now();
    if (period == StatsPeriod.allTime) return stats.dailyRecords.keys.toList();
    final days = switch (period) {
      StatsPeriod.today => 1,
      StatsPeriod.week => 7,
      StatsPeriod.month => 30,
      StatsPeriod.allTime => 0,
    };
    return List.generate(days, (index) {
      final date = now.subtract(Duration(days: index));
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    });
  }

  DailyTrafficRecord getTrafficForPeriod(
    StatsPeriod period,
    StatsNetworkType netType, {
    TrafficStatsState? snapshot,
  }) {
    var wifiRx = 0, wifiTx = 0, mobileRx = 0, mobileTx = 0;
    final stats = snapshot ?? state;
    for (final key in _keysForPeriod(period, stats)) {
      final day = stats.dailyRecords[key];
      if (day == null) continue;
      if (netType != StatsNetworkType.mobile) {
        wifiRx += day.wifiRx;
        wifiTx += day.wifiTx;
      }
      if (netType != StatsNetworkType.wifi) {
        mobileRx += day.mobileRx;
        mobileTx += day.mobileTx;
      }
    }
    return DailyTrafficRecord(
      wifiRx: wifiRx,
      wifiTx: wifiTx,
      mobileRx: mobileRx,
      mobileTx: mobileTx,
    );
  }

  Map<String, int> getAppTrafficForPeriod(
    StatsPeriod period,
    StatsNetworkType netType, {
    TrafficStatsState? snapshot,
  }) {
    final stats = snapshot ?? state;
    final result = <String, int>{};
    for (final dayKey in _keysForPeriod(period, stats)) {
      for (final entry in (stats.dailyAppRecords[dayKey] ?? const {}).entries) {
        final bytes = switch (netType) {
          StatsNetworkType.all => entry.value.totalBytes,
          StatsNetworkType.wifi => entry.value.wifiBytes,
          StatsNetworkType.mobile => entry.value.mobileBytes,
        };
        if (bytes > 0) result[entry.key] = (result[entry.key] ?? 0) + bytes;
      }
    }
    final vpnTotal = getTrafficForPeriod(
      period,
      netType,
      snapshot: stats,
    ).total;
    _fitAppTrafficToVpnDelta(result, vpnTotal);
    return result;
  }

  void _fitAppTrafficToVpnDelta(Map<String, int> appBytes, int vpnBytes) {
    final appTotal = appBytes.values.fold<int>(0, (sum, bytes) => sum + bytes);
    if (appTotal <= vpnBytes) return;
    if (vpnBytes <= 0 || appTotal <= 0) {
      appBytes.clear();
      return;
    }

    final entries = appBytes.entries.toList();
    var assigned = 0;
    for (final entry in entries) {
      final scaled = entry.value * vpnBytes ~/ appTotal;
      appBytes[entry.key] = scaled;
      assigned += scaled;
    }
    var remainder = vpnBytes - assigned;
    for (final entry in entries) {
      if (remainder == 0) break;
      appBytes[entry.key] = (appBytes[entry.key] ?? 0) + 1;
      remainder--;
    }
  }

  Future<void> clear() async {
    await _loaded;
    state = TrafficStatsState(
      nativeSessionId: state.nativeSessionId,
      nativeRxBytes: state.nativeRxBytes,
      nativeTxBytes: state.nativeTxBytes,
      nativeAppBytes: state.nativeAppBytes,
      nativeAppRxBytes: state.nativeAppRxBytes,
      nativeAppTxBytes: state.nativeAppTxBytes,
    );
    await _save();
  }
}

final statsProvider = StateNotifierProvider<StatsNotifier, TrafficStatsState>(
  (ref) => StatsNotifier(),
);
