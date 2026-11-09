import 'dart:convert';
import 'dart:io';

import '../models/qr_export_style.dart';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  // === ИНТЕРФЕЙС ===
  final String language;
  final double uiScale;
  final bool showServerGlobe;
  final String theme;
  final QrExportStyle qrStyle;
  final String logLevel; // 'debug', 'info', 'warn', 'error'
  final int maxLogFiles;
  final int maxLogStorageMb;

  // === ЯДРА И ПОВЕДЕНИЕ ===
  final String preferredCore; // 'XRAY', 'SINGBOX'
  final bool autoUpdateCores;
  final bool autoInstallCoreUpdates;
  final bool coreFailover;
  final bool autoStart;

  // === TUNNEL & СЕТЬ ===
  final int tunMtu; // 1500, 9000
  final bool strictMode; // Strict Route
  final bool blockQuic; // Блокировка UDP 443
  final bool tcpFastOpen;
  final bool ipv6;
  final String ipType; // 'IPv4', 'IPv6', 'Auto'

  // === ПОРТЫ И ПРОКСИ ===
  final int socksPort;
  final int httpPort;
  final int lanPort;
  final String lanUsername;
  final String lanPassword;
  final bool lanConn; // Разрешить доступ из локальной сети
  final bool bypassLan; // Обход локальной сети (Direct)

  // === DNS ===
  final bool fakeDns; // Fake-IP
  final bool useLocalDns;
  final String remoteDns;
  final String localDnsServer;

  // === МАРШРУТИЗАЦИЯ ===
  final bool useRouting;
  final String ruleOrder;
  final bool sniffing;
  final bool packetAnalysis;

  // === ТРАНСПОРТ И ОБФУСКАЦИЯ ===
  final bool fragment;
  final String fragmentPackets;
  final String fragmentLength;
  final String fragmentInterval;
  final String tlsFingerprint;

  // XRAY MUX
  final bool xrayMux;
  final int xrayMuxConcurrency;

  // SING-BOX MUX
  final bool singboxMux;
  final String singboxMuxProtocol;
  final int singboxMuxMaxConnections;
  final int singboxMuxMinStreams;

  // === PER-APP ===
  final bool perAppEnabled;
  final String perAppDefaultRule;
  final Map<String, String> perAppRules;

  // === ПОДПИСКИ ===
  final bool autoUpdateSubs;
  final int subUpdateIntervalHours;
  final bool notifySubUpdate;
  final bool updateOnStart;
  final bool pingOnStart;
  final bool connectOnStart;
  final bool preventDuplicates;
  final bool collapseSubs;
  final bool sendHwid;
  final String userAgent;
  final String subSortMode;

  // === ПИНГ ===
  final String pingType;
  final String pingUrl;

  // === URL ЗАГРУЗОК ===
  final String xrayUrl;
  final String singboxUrl;
  final String awgUrl;
  final String rulesUrl;

  SettingsState({
    this.language = 'System',
    this.uiScale = 1.0,
    this.showServerGlobe = true,
    this.theme = 'Crimson Red (Default)',
    this.logLevel = 'info',
    this.qrStyle = const QrExportStyle(),
    this.maxLogFiles = 20,
    this.maxLogStorageMb = 20,
    this.preferredCore = 'SINGBOX',
    this.autoUpdateCores = false,
    this.autoInstallCoreUpdates = false,
    this.coreFailover = true,
    this.autoStart = false,
    this.tunMtu = 1500,
    this.strictMode = true,
    this.blockQuic = false,
    this.tcpFastOpen = false,
    this.ipv6 = false,
    this.ipType = 'IPv4',
    this.socksPort = 10808,
    this.httpPort = 10809,
    this.lanConn = false,
    this.lanPort = 2080,
    this.lanUsername = '',
    this.lanPassword = '',
    this.bypassLan = true,
    this.fakeDns = false,
    this.useLocalDns = false,
    this.remoteDns = '1.1.1.1',
    this.localDnsServer = '8.8.8.8', // Безопасные дефолты
    this.useRouting = true,
    this.ruleOrder = 'Block -> Direct -> Proxy',
    this.sniffing = true,
    this.packetAnalysis = true,
    this.fragment = false,
    this.fragmentPackets = 'tlshello',
    this.fragmentLength = '10-50',
    this.fragmentInterval = '5-10',
    this.tlsFingerprint = 'chrome',
    this.xrayMux = false,
    this.xrayMuxConcurrency = 8,
    this.singboxMux = false,
    this.singboxMuxProtocol = 'smux',
    this.singboxMuxMaxConnections = 4,
    this.singboxMuxMinStreams = 4, // Выключили MUX по умолчанию
    this.perAppEnabled = false,
    this.perAppDefaultRule = 'proxy',
    this.perAppRules = const {},
    this.autoUpdateSubs = false,
    this.subUpdateIntervalHours = 1,
    this.notifySubUpdate = false,
    this.updateOnStart = false,
    this.pingOnStart = false,
    this.connectOnStart = false,
    this.preventDuplicates = true,
    this.collapseSubs = false,
    this.sendHwid = true,
    this.userAgent = 'Happ/2.4.0',
    this.subSortMode = 'sorting_none',
    this.pingType = 'via Proxy',
    this.pingUrl = 'http://www.gstatic.com/generate_204',
    this.xrayUrl = '',
    this.singboxUrl = '',
    this.awgUrl = '',
    this.rulesUrl = '',
  });

  Map<String, dynamic> toMap() => {
    'language': language,
    'uiScale': uiScale,
    'showServerGlobe': showServerGlobe,
    'theme': theme,
    'logLevel': logLevel,
    'qrStyle': qrStyle.toMap(),
    'maxLogFiles': maxLogFiles,
    'maxLogStorageMb': maxLogStorageMb,
    'preferredCore': preferredCore,
    'autoUpdateCores': autoUpdateCores,
    'coreDownloadOptInVersion': 1,
    'autoInstallCoreUpdates': autoInstallCoreUpdates,
    'coreFailover': coreFailover,
    'autoStart': autoStart,
    'tunMtu': tunMtu,
    'strictMode': strictMode,
    'blockQuic': blockQuic,
    'tcpFastOpen': tcpFastOpen,
    'ipv6': ipv6,
    'ipType': ipType,
    'socksPort': socksPort,
    'httpPort': httpPort,
    'lanConn': lanConn,
    'lanPort': lanPort,
    'lanUsername': lanUsername,
    'lanPassword': lanPassword,
    'bypassLan': bypassLan,
    'fakeDns': fakeDns,
    'useLocalDns': useLocalDns,
    'remoteDns': remoteDns,
    'localDnsServer': localDnsServer,
    'useRouting': useRouting,
    'ruleOrder': ruleOrder,
    'sniffing': sniffing,
    'packetAnalysis': packetAnalysis,
    'fragment': fragment,
    'fragmentPackets': fragmentPackets,
    'fragmentLength': fragmentLength,
    'fragmentInterval': fragmentInterval,
    'tlsFingerprint': tlsFingerprint,
    'xrayMux': xrayMux,
    'xrayMuxConcurrency': xrayMuxConcurrency,
    'singboxMux': singboxMux,
    'singboxMuxProtocol': singboxMuxProtocol,
    'singboxMuxMaxConnections': singboxMuxMaxConnections,
    'singboxMuxMinStreams': singboxMuxMinStreams,
    'perAppEnabled': perAppEnabled,
    'perAppDefaultRule': perAppDefaultRule,
    'perAppRules': perAppRules,
    'autoUpdateSubs': autoUpdateSubs,
    'subUpdateIntervalHours': subUpdateIntervalHours,
    'notifySubUpdate': notifySubUpdate,
    'updateOnStart': updateOnStart,
    'pingOnStart': pingOnStart,
    'connectOnStart': connectOnStart,
    'preventDuplicates': preventDuplicates,
    'collapseSubs': collapseSubs,
    'sendHwid': sendHwid,
    'userAgent': userAgent,
    'subSortMode': subSortMode,
    'pingType': pingType,
    'pingUrl': pingUrl,
    'xrayUrl': xrayUrl,
    'singboxUrl': singboxUrl,
    'awgUrl': awgUrl,
    'rulesUrl': rulesUrl,
  };

  factory SettingsState.fromMap(Map<String, dynamic> map) => SettingsState(
    language: map['language'] ?? 'System',
    uiScale: (map['uiScale'] ?? 1.0).toDouble(),
    showServerGlobe: map['showServerGlobe'] ?? true,
    theme: map['theme'] ?? 'Crimson Red (Default)',
    qrStyle: QrExportStyle.fromMap(
      map['qrStyle'] is Map ? map['qrStyle'] : const {},
    ),
    logLevel: map['logLevel'] ?? 'info',
    maxLogFiles: map['maxLogFiles'] ?? 20,
    maxLogStorageMb: map['maxLogStorageMb'] ?? 20,
    preferredCore: map['preferredCore'] ?? 'SINGBOX',
    // Legacy true was the default, not an explicit opt-in.
    autoUpdateCores:
        map['coreDownloadOptInVersion'] == 1 && map['autoUpdateCores'] == true,
    autoInstallCoreUpdates: map['autoInstallCoreUpdates'] ?? false,
    coreFailover: map['coreFailover'] ?? true,
    autoStart: map['autoStart'] ?? false,
    tunMtu: map['tunMtu'] ?? 1500,
    strictMode: map['strictMode'] ?? true,
    blockQuic: map['blockQuic'] ?? false,
    tcpFastOpen: map['tcpFastOpen'] ?? false,
    ipv6: map['ipv6'] ?? false,
    ipType: map['ipType'] ?? 'IPv4',
    socksPort: map['socksPort'] ?? 10808,
    httpPort: map['httpPort'] ?? 10809,
    lanConn: map['lanConn'] ?? false,
    lanPort: map['lanPort'] ?? 2080,
    lanUsername: map['lanUsername'] ?? '',
    lanPassword: map['lanPassword'] ?? '',
    bypassLan: map['bypassLan'] ?? true,
    fakeDns: map['fakeDns'] ?? false,
    useLocalDns: map['useLocalDns'] ?? false,
    remoteDns: map['remoteDns'] ?? '1.1.1.1',
    localDnsServer: map['localDnsServer'] ?? '8.8.8.8',
    useRouting: map['useRouting'] ?? true,
    ruleOrder: map['ruleOrder'] ?? 'Block -> Direct -> Proxy',
    sniffing: map['sniffing'] ?? true,
    packetAnalysis: map['packetAnalysis'] ?? true,
    fragment: map['fragment'] ?? false,
    fragmentPackets: map['fragmentPackets'] ?? 'tlshello',
    fragmentLength: map['fragmentLength'] ?? '10-50',
    fragmentInterval: map['fragmentInterval'] ?? '5-10',
    tlsFingerprint: map['tlsFingerprint'] ?? 'chrome',
    xrayMux: map['xrayMux'] ?? false,
    xrayMuxConcurrency: map['xrayMuxConcurrency'] ?? 8,
    singboxMux: map['singboxMux'] ?? false,
    singboxMuxProtocol: map['singboxMuxProtocol'] ?? 'smux',
    singboxMuxMaxConnections: map['singboxMuxMaxConnections'] ?? 4,
    singboxMuxMinStreams: map['singboxMuxMinStreams'] ?? 4,
    perAppEnabled: map['perAppEnabled'] ?? false,
    perAppDefaultRule:
        ['proxy', 'direct', 'block'].contains(map['perAppDefaultRule'])
        ? map['perAppDefaultRule']
        : 'proxy',
    perAppRules: Map<String, String>.from(map['perAppRules'] ?? {}).map(
      (packageName, rule) => MapEntry(
        packageName,
        ['proxy', 'direct', 'block'].contains(rule) ? rule : 'proxy',
      ),
    ),
    autoUpdateSubs: map['autoUpdateSubs'] ?? false,
    subUpdateIntervalHours: map['subUpdateIntervalHours'] ?? 1,
    notifySubUpdate: map['notifySubUpdate'] ?? false,
    updateOnStart: map['updateOnStart'] ?? false,
    pingOnStart: map['pingOnStart'] ?? false,
    connectOnStart: map['connectOnStart'] ?? false,
    preventDuplicates: map['preventDuplicates'] ?? true,
    collapseSubs: map['collapseSubs'] ?? false,
    sendHwid: map['sendHwid'] ?? true,
    userAgent: map['userAgent'] == null || map['userAgent'] == 'NextLink/1.0.0'
        ? 'Happ/2.4.0'
        : map['userAgent'],
    subSortMode: map['subSortMode'] ?? 'sorting_none',
    pingType: map['pingType'] ?? 'via Proxy',
    pingUrl: map['pingUrl'] ?? 'http://www.gstatic.com/generate_204',
    xrayUrl: map['xrayUrl'] ?? '',
    singboxUrl: map['singboxUrl'] ?? '',
    awgUrl: map['awgUrl'] ?? '',
    rulesUrl: map['rulesUrl'] ?? '',
  );

  SettingsState copyWith({
    String? language,
    double? uiScale,
    bool? showServerGlobe,
    String? theme,
    String? logLevel,
    QrExportStyle? qrStyle,
    int? maxLogFiles,
    int? maxLogStorageMb,
    String? preferredCore,
    bool? autoUpdateCores,
    bool? autoInstallCoreUpdates,
    bool? coreFailover,
    bool? autoStart,
    int? tunMtu,
    bool? strictMode,
    bool? blockQuic,
    bool? tcpFastOpen,
    bool? ipv6,
    String? ipType,
    int? socksPort,
    int? httpPort,
    bool? lanConn,
    int? lanPort,
    String? lanUsername,
    String? lanPassword,
    bool? bypassLan,
    bool? fakeDns,
    bool? useLocalDns,
    String? remoteDns,
    String? localDnsServer,
    bool? useRouting,
    String? ruleOrder,
    bool? sniffing,
    bool? packetAnalysis,
    bool? fragment,
    String? fragmentPackets,
    String? fragmentLength,
    String? fragmentInterval,
    String? tlsFingerprint,
    bool? xrayMux,
    int? xrayMuxConcurrency,
    bool? singboxMux,
    String? singboxMuxProtocol,
    int? singboxMuxMaxConnections,
    int? singboxMuxMinStreams,
    bool? perAppEnabled,
    String? perAppDefaultRule,
    Map<String, String>? perAppRules,
    bool? autoUpdateSubs,
    int? subUpdateIntervalHours,
    bool? notifySubUpdate,
    bool? updateOnStart,
    bool? pingOnStart,
    bool? connectOnStart,
    bool? preventDuplicates,
    bool? collapseSubs,
    bool? sendHwid,
    String? userAgent,
    String? subSortMode,
    String? pingType,
    String? pingUrl,
    String? xrayUrl,
    String? singboxUrl,
    String? awgUrl,
    String? rulesUrl,
  }) {
    return SettingsState(
      language: language ?? this.language,
      uiScale: uiScale ?? this.uiScale,
      showServerGlobe: showServerGlobe ?? this.showServerGlobe,
      theme: theme ?? this.theme,
      logLevel: logLevel ?? this.logLevel,
      qrStyle: qrStyle ?? this.qrStyle,
      maxLogFiles: maxLogFiles ?? this.maxLogFiles,
      maxLogStorageMb: maxLogStorageMb ?? this.maxLogStorageMb,
      preferredCore: preferredCore ?? this.preferredCore,
      autoUpdateCores: autoUpdateCores ?? this.autoUpdateCores,
      autoInstallCoreUpdates:
          autoInstallCoreUpdates ?? this.autoInstallCoreUpdates,
      coreFailover: coreFailover ?? this.coreFailover,
      autoStart: autoStart ?? this.autoStart,
      tunMtu: tunMtu ?? this.tunMtu,
      strictMode: strictMode ?? this.strictMode,
      blockQuic: blockQuic ?? this.blockQuic,
      tcpFastOpen: tcpFastOpen ?? this.tcpFastOpen,
      ipv6: ipv6 ?? this.ipv6,
      ipType: ipType ?? this.ipType,
      socksPort: socksPort ?? this.socksPort,
      httpPort: httpPort ?? this.httpPort,
      lanConn: lanConn ?? this.lanConn,
      lanPort: lanPort ?? this.lanPort,
      lanUsername: lanUsername ?? this.lanUsername,
      lanPassword: lanPassword ?? this.lanPassword,
      bypassLan: bypassLan ?? this.bypassLan,
      fakeDns: fakeDns ?? this.fakeDns,
      useLocalDns: useLocalDns ?? this.useLocalDns,
      remoteDns: remoteDns ?? this.remoteDns,
      localDnsServer: localDnsServer ?? this.localDnsServer,
      useRouting: useRouting ?? this.useRouting,
      ruleOrder: ruleOrder ?? this.ruleOrder,
      sniffing: sniffing ?? this.sniffing,
      packetAnalysis: packetAnalysis ?? this.packetAnalysis,
      fragment: fragment ?? this.fragment,
      fragmentPackets: fragmentPackets ?? this.fragmentPackets,
      fragmentLength: fragmentLength ?? this.fragmentLength,
      fragmentInterval: fragmentInterval ?? this.fragmentInterval,
      tlsFingerprint: tlsFingerprint ?? this.tlsFingerprint,
      xrayMux: xrayMux ?? this.xrayMux,
      xrayMuxConcurrency: xrayMuxConcurrency ?? this.xrayMuxConcurrency,
      singboxMux: singboxMux ?? this.singboxMux,
      singboxMuxProtocol: singboxMuxProtocol ?? this.singboxMuxProtocol,
      singboxMuxMaxConnections:
          singboxMuxMaxConnections ?? this.singboxMuxMaxConnections,
      singboxMuxMinStreams: singboxMuxMinStreams ?? this.singboxMuxMinStreams,
      perAppEnabled: perAppEnabled ?? this.perAppEnabled,
      perAppDefaultRule: perAppDefaultRule ?? this.perAppDefaultRule,
      perAppRules: perAppRules ?? this.perAppRules,
      autoUpdateSubs: autoUpdateSubs ?? this.autoUpdateSubs,
      subUpdateIntervalHours:
          subUpdateIntervalHours ?? this.subUpdateIntervalHours,
      notifySubUpdate: notifySubUpdate ?? this.notifySubUpdate,
      updateOnStart: updateOnStart ?? this.updateOnStart,
      pingOnStart: pingOnStart ?? this.pingOnStart,
      connectOnStart: connectOnStart ?? this.connectOnStart,
      preventDuplicates: preventDuplicates ?? this.preventDuplicates,
      collapseSubs: collapseSubs ?? this.collapseSubs,
      sendHwid: sendHwid ?? this.sendHwid,
      userAgent: userAgent ?? this.userAgent,
      subSortMode: subSortMode ?? this.subSortMode,
      pingType: pingType ?? this.pingType,
      pingUrl: pingUrl ?? this.pingUrl,
      xrayUrl: xrayUrl ?? this.xrayUrl,
      singboxUrl: singboxUrl ?? this.singboxUrl,
      awgUrl: awgUrl ?? this.awgUrl,
      rulesUrl: rulesUrl ?? this.rulesUrl,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  late final Future<void> ready;

  SettingsNotifier() : super(SettingsState()) {
    ready = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('app_settings');
    if (data != null) {
      try {
        state = SettingsState.fromMap(jsonDecode(data));
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_settings', jsonEncode(state.toMap()));
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('pro.kaleert.nextlink/vpn')
            .invokeMethod<void>('scheduleSubscriptionUpdates');
      } on MissingPluginException {
        // Unit tests and platforms without an Android scheduler.
      }
    }
  }

  void update(SettingsState newState) {
    state = newState;
    _save();
  }

  void updateField<T>(
    T value,
    SettingsState Function(SettingsState, T) updater,
  ) {
    state = updater(state, value);
    _save();
  }

  void togglePerApp(bool val) => update(state.copyWith(perAppEnabled: val));
  void setPerAppDefaultRule(String rule) => update(
    state.copyWith(
      perAppDefaultRule: ['proxy', 'direct', 'block'].contains(rule)
          ? rule
          : 'proxy',
    ),
  );
  void setPerAppRule(String pkg, String rule) {
    final newRules = Map<String, String>.from(state.perAppRules);
    newRules[pkg] = ['proxy', 'direct', 'block'].contains(rule)
        ? rule
        : 'proxy';
    update(state.copyWith(perAppRules: newRules));
  }

  void invertPerAppRules() {
    final newRules = Map<String, String>.from(state.perAppRules);
    newRules.forEach((key, value) {
      if (value == 'proxy')
        newRules[key] = 'direct';
      else if (value == 'direct')
        newRules[key] = 'proxy';
    });
    final newDefault = state.perAppDefaultRule == 'block'
        ? 'block'
        : state.perAppDefaultRule == 'proxy'
        ? 'direct'
        : 'proxy';
    update(
      state.copyWith(perAppRules: newRules, perAppDefaultRule: newDefault),
    );
  }

  void setLanguage(String val) => update(state.copyWith(language: val));
  void setUiScale(double val) => update(state.copyWith(uiScale: val));
  void setTheme(String theme) => update(state.copyWith(theme: theme));
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
