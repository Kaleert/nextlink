import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;

import 'shared/widgets/country_flag.dart';
import 'shared/widgets/server_globe.dart';
import 'core/utils/ip_location.dart';
import 'shared/widgets/theme_region.dart';
import 'core/utils/routing_rule_codec.dart';
import 'core/utils/vpn_session_clock.dart';
import 'core/utils/proxy_runtime.dart';
import 'screens/backup_screen.dart';
import 'core/providers/automation_provider.dart';
import 'core/utils/core_binary_paths.dart';
import 'core/utils/imported_file.dart';
import 'core/utils/config_share_payload.dart';
import 'core/utils/profile_timer_schedule.dart';

import 'dart:ui';
import 'dart:async';
import 'dart:io' show Platform, HttpClient;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/rules_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/localization/app_localizations.dart';
import 'shared/widgets/animated_background.dart';
import 'screens/subscriptions_screen.dart';
import 'screens/chains_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/apps_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/client_tour_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/profiles_screen.dart';
import 'shared/widgets/custom_notification.dart';
import 'shared/widgets/theme_press_effect.dart';
import 'shared/widgets/theme_element.dart';
import 'shared/widgets/custom_theme_elements.dart';
import 'core/models/subscription.dart';
import 'core/providers/subscription_provider.dart';
import 'core/providers/map_selection_provider.dart';
import 'core/providers/chains_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/stats_provider.dart';
import 'core/providers/logger_provider.dart';
import 'core/providers/core_manager_provider.dart';
import 'core/providers/profiles_provider.dart';
import 'core/utils/ping_utils.dart';
import 'core/utils/vpn_readiness.dart';
import 'shared/widgets/adaptive_home_header.dart';
import 'shared/widgets/tour_anchor.dart';
import 'core/utils/crash_log.dart';
import 'core/models/proxies/proxy_config.dart';
import 'core/models/theme_config.dart';
import 'core/models/proxies/proxy_parser.dart';
import 'core/engine/config_builder.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          'flag-icons',
        ], await rootBundle.loadString('assets/flags/LICENSE'));
      });
      unawaited(CrashLog.initialize());
      FlutterError.onError = FlutterError.presentError;
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          CrashLog.recordFatal(error, stack, source: 'PlatformDispatcher'),
        );
        debugPrint('Unhandled Dart error: $error\n$stack');
        return false;
      };

      try {
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } catch (_) {}

      runApp(const ProviderScope(child: NextLinkApp()));
    },
    (error, stack) {
      unawaited(CrashLog.recordFatal(error, stack, source: 'runZonedGuarded'));
      debugPrint('Unhandled Dart zone error: $error\n$stack');
    },
  );
}

@pragma('vm:entry-point')
Future<void> subscriptionUpdateMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  const worker = MethodChannel('pro.kaleert.nextlink/subscription_worker');
  Map<String, dynamic> result = {'success': false};
  try {
    await container.read(settingsProvider.notifier).ready;
    if (container.read(settingsProvider).autoUpdateSubs) {
      final ids = await worker.invokeListMethod<String>('retryIds');
      final report = await container
          .read(subscriptionProvider.notifier)
          .updateAllSubscriptions(
            onlyIds: ids == null || ids.isEmpty ? null : ids.toSet(),
          );
      result = report.toMap();
      try {
        await refreshBackgroundAutomationPlan(container);
      } catch (_) {
        debugPrint('Subscription worker: automation plan refresh deferred');
      }
    } else {
      result = {'success': true, 'failedIds': <String>[]};
    }
  } catch (error) {
    debugPrint('Subscription worker failed: ${error.runtimeType}');
    result = {...result, 'success': false};
  } finally {
    container.dispose();
    await worker.invokeMethod<void>('complete', result);
  }
}

class NextLinkApp extends ConsumerWidget {
  const NextLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(automationSyncProvider);
    final settings = ref.watch(settingsProvider);
    final themeState = ref.watch(themeProvider);

    Locale? locale;
    if (settings.language == 'Русский') {
      locale = const Locale('ru');
    } else if (settings.language == 'English') {
      locale = const Locale('en');
    } else if (settings.language == 'Українська') {
      locale = const Locale('uk');
    }

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'NextLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(themeState.currentTheme),
      locale: locale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('ru', ''),
        Locale('uk', ''),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        for (var supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale?.languageCode) {
            return supportedLocale;
          }
        }
        return supportedLocales.first;
      },
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              settings.uiScale * themeState.currentTheme.textScale,
            ),
          ),
          child: child!,
        );
      },
      home: const HomeScreen(),
    );
  }
}

// ================= VPN STATE MANAGER =================
enum VpnState { disconnected, connecting, connected, paused }

class VpnStateData {
  final VpnState status;
  final String? serviceServerName;
  final String? serviceServerKey;
  final int connectedSeconds;
  final String speed;
  final String ping;
  final int totalBytes;

  final bool isSwitching;
  final bool isRetrying;
  final String? targetServerName;
  final String? oldServerName;
  final int? oldConnectedSeconds;

  VpnStateData({
    this.status = VpnState.disconnected,
    this.serviceServerName,
    this.serviceServerKey,
    this.connectedSeconds = 0,
    this.speed = '0 B/s',
    this.ping = '---',
    this.totalBytes = 0,
    this.isSwitching = false,
    this.isRetrying = false,
    this.targetServerName,
    this.oldServerName,
    this.oldConnectedSeconds,
  });

  String get formattedTraffic {
    if (totalBytes <= 0) return "0.0 MB";
    if (totalBytes >= 1024 * 1024 * 1024) {
      return "${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
    }
    return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  String get formattedTime => _formatDuration(connectedSeconds);
  String get formattedOldTime => _formatDuration(oldConnectedSeconds ?? 0);

  String _formatDuration(int seconds) {
    final h = (seconds / 3600).floor().toString().padLeft(2, '0');
    final m = ((seconds % 3600) / 60).floor().toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return h == '00' ? '$m:$s' : '$h:$m:$s';
  }

  VpnStateData copyWith({
    VpnState? status,
    String? serviceServerName,
    String? serviceServerKey,
    int? connectedSeconds,
    String? speed,
    String? ping,
    int? totalBytes,
    bool? isSwitching,
    bool? isRetrying,
    String? targetServerName,
    String? oldServerName,
    int? oldConnectedSeconds,
  }) {
    return VpnStateData(
      status: status ?? this.status,
      serviceServerName: serviceServerName ?? this.serviceServerName,
      serviceServerKey: serviceServerKey ?? this.serviceServerKey,
      connectedSeconds: connectedSeconds ?? this.connectedSeconds,
      speed: speed ?? this.speed,
      ping: ping ?? this.ping,
      totalBytes: totalBytes ?? this.totalBytes,
      isSwitching: isSwitching ?? this.isSwitching,
      isRetrying: isRetrying ?? this.isRetrying,
      targetServerName: targetServerName ?? this.targetServerName,
      oldServerName: oldServerName ?? this.oldServerName,
      oldConnectedSeconds: oldConnectedSeconds ?? this.oldConnectedSeconds,
    );
  }
}

class VpnNotifier extends StateNotifier<VpnStateData> {
  final _sessionClock = VpnSessionClock();
  static const _platform = MethodChannel('pro.kaleert.nextlink/vpn');
  static const _statsChannel = MethodChannel('pro.kaleert.nextlink/stats');
  final Ref ref;
  bool _isBusy = false;
  bool _applyingNativeSelection = false;
  bool _isCancelling = false;
  Timer? _nativeSyncTimer;
  bool _nativeSyncInFlight = false;
  bool _trafficDrainInFlight = false;
  int _lastNativeRevision = -1;
  String? _nativeServerKey;

  VpnNotifier(this.ref) : super(VpnStateData()) {
    _initNativeListeners();
    unawaited(_initializeNativeState());
    _listenToServerAndChainChanges();
    if (Platform.isAndroid) {
      _nativeSyncTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => syncNativeState(),
      );
    }
  }

  Future<void> _initializeNativeState() async {
    await ref.read(mapSelectionProvider.notifier).ready;
    await _syncWithNative();
    await _consumeInitialUrl();
  }

  Future<void> activateProfile(
    AppProfile profile, {
    bool connectIfDisconnected = false,
    bool rotateServer = false,
  }) async {
    if (_isBusy || state.isSwitching || state.status == VpnState.connecting)
      return;
    final subscriptions = ref.read(subscriptionProvider);
    final servers = [
      for (final subscription in subscriptions)
        for (final server in subscription.servers)
          if (profile.serverKeys.isEmpty ||
              profile.serverKeys.contains(server.uniqueKey) ||
              server.uniqueKey == profile.serverKey)
            (subscription.id, server),
    ];
    if (servers.isNotEmpty) {
      final selectedIndex = profile.serverKey == null
          ? -1
          : servers.indexWhere(
              (item) => item.$2.uniqueKey == profile.serverKey,
            );
      if (profile.serverKey != null && selectedIndex < 0) {
        AppLogger.log(
          ref,
          'PROFILE',
          'Server for profile ${profile.name} is missing',
        );
        return;
      }
      final activeIndex = servers.indexWhere((item) => item.$2.isActive);
      final targetIndex = selectedIndex >= 0
          ? selectedIndex
          : rotateServer && activeIndex >= 0
          ? (activeIndex + 1) % servers.length
          : activeIndex >= 0
          ? activeIndex
          : 0;
      final target = servers[targetIndex];
      ref.read(chainsProvider.notifier).setActiveChain(null);
      ref
          .read(subscriptionProvider.notifier)
          .setActiveServer(target.$1, target.$2);
      if (connectIfDisconnected && state.status == VpnState.disconnected) {
        await toggle();
      }
    }
  }

  Future<void> _consumeInitialUrl() async {
    try {
      final initialUrl = await _platform.invokeMethod<String>('getInitialUrl');
      if (initialUrl != null && initialUrl.isNotEmpty) {
        await _handleUrlScheme(initialUrl);
      }
    } catch (_) {}
  }

  Future<void> _handleUrlScheme(String rawUrl) async {
    try {
      final uri = Uri.parse(rawUrl);
      final pathSegments = uri.pathSegments;
      final action = uri.host.isNotEmpty
          ? uri.host.toLowerCase()
          : pathSegments.isNotEmpty
          ? pathSegments.first.toLowerCase()
          : '';
      switch (action) {
        case 'connect':
        case 'open':
        case 'start':
          if (state.status == VpnState.disconnected) await toggle();
          return;
        case 'disconnect':
        case 'close':
        case 'stop':
          if (state.status != VpnState.disconnected) await toggle();
          return;
        case 'toggle':
          await toggle();
          return;
        case 'quicktile':
          await toggle();
          return;
        case 'servers':
          appNavigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const SubscriptionsScreen()),
          );
          return;
        case 'add':
          final target =
              uri.queryParameters['url'] ??
              (uri.pathSegments.length > 1
                  ? Uri.decodeComponent(uri.pathSegments.skip(1).join('/'))
                  : '');
          if (target.isNotEmpty) await _importFromUrl(target);
          return;
        case 'import':
        case 'import-gzip':
          if (uri.pathSegments.isNotEmpty)
            await _importConfigText(
              ConfigSharePayload.decodeQr(uri.toString()),
            );
          return;
        case 'file-error':
          await _notifyImport(
            uri.queryParameters['message'] ?? 'Не удалось прочитать файл',
            isError: true,
          );
          return;
        case 'file':
          if (uri.pathSegments.isEmpty) return;
          final content = utf8.decode(
            base64Url.decode(base64Url.normalize(uri.pathSegments.last)),
          );
          if (isBackupDocument(content)) {
            if (appNavigatorKey.currentState == null)
              await WidgetsBinding.instance.endOfFrame;
            appNavigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => BackupScreen(initialContents: content),
              ),
            );
          } else if (isThemeDocument(content)) {
            final notifier = ref.read(themeProvider.notifier);
            await notifier.ensureLoaded();
            final theme = notifier.importThemeFromJson(content);
            notifier.setTheme(theme);
            await _notifyImport('Тема «${theme.name}» добавлена и применена');
          } else {
            await _importConfigText(content);
          }
          return;
        case 'theme':
          if (uri.pathSegments.isEmpty) return;
          final encoded = uri.pathSegments.first;
          final themeJson = utf8.decode(
            base64Url.decode(base64Url.normalize(encoded)),
            allowMalformed: false,
          );
          final themeNotifier = ref.read(themeProvider.notifier);
          await themeNotifier.ensureLoaded();
          final importedTheme = themeNotifier.importThemeFromJson(themeJson);
          themeNotifier.setTheme(importedTheme);
          await _notifyImport(
            'Тема «${importedTheme.name}» добавлена и применена',
          );
          AppLogger.log(
            ref,
            'THEME',
            'Imported and applied theme: ${importedTheme.name}',
          );
          return;
        case 'profile':
          final profileId = uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : uri.queryParameters['id'];
          await ref.read(profilesProvider.notifier).ready;
          final profiles = ref.read(profilesProvider);
          final matches = profiles
              .where((profile) => profile.id == profileId)
              .toList();
          if (matches.isNotEmpty)
            await activateProfile(
              matches.first,
              rotateServer: matches.first.serverKey == null,
            );
          return;
        case 'routing':
          if (uri.pathSegments.length > 1 &&
              {'add', 'onadd'}.contains(uri.pathSegments.first)) {
            await _importRoutingRules(uri.pathSegments[1]);
          }
          return;
      }
      AppLogger.log(ref, 'LINK', 'Unsupported URL scheme: $rawUrl');
    } catch (error) {
      AppLogger.log(ref, 'LINK', 'URL command failed: $error');
      await _notifyImport(
        'Не удалось выполнить импорт или команду: $error',
        isError: true,
      );
    }
  }

  Future<void> _notifyImport(String message, {bool isError = false}) async {
    if (appNavigatorKey.currentState?.overlay == null)
      await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay != null && overlay.mounted)
      CustomNotification.show(
        overlay.context,
        message,
        isError: isError,
        overlay: overlay,
      );
  }

  Future<void> _importFromUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty)
      throw const FormatException('Некорректная ссылка');
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      await _notifyImport('Добавляю подписку…');
      final name = await ref
          .read(subscriptionProvider.notifier)
          .addSubscription('', url);
      await _notifyImport('Подписка «$name» добавлена');
    } else {
      final count = await ref
          .read(subscriptionProvider.notifier)
          .addManualConfigs([ProxyParser.parse(url)]);
      await _notifyImport(
        count == 0
            ? 'Эта конфигурация уже добавлена'
            : 'Конфигурация добавлена',
      );
    }
  }

  Future<void> _importRoutingRules(String encoded) async {
    try {
      final jsonText = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
        allowMalformed: true,
      );
      final decoded = jsonDecode(jsonText);
      final dynamic rawRules;
      final definitions = <String, dynamic>{};
      if (decoded is List) {
        rawRules = decoded;
      } else if (decoded is Map) {
        final route = decoded['routing'] ?? decoded['route'] ?? decoded;
        rawRules = route is Map ? route['rules'] : null;
        if (route is Map)
          for (final definition in route['rule_set'] as List? ?? []) {
            if (definition is Map && definition['tag'] is String)
              definitions[definition['tag']] = Map<String, dynamic>.from(
                definition,
              );
          }
      } else {
        rawRules = null;
      }
      if (rawRules is! List) {
        throw const FormatException('В JSON не найден массив routing.rules');
      }

      final imported = <AppRule>[];
      for (final rawRule in rawRules) {
        if (rawRule is! Map) continue;
        final actionValue =
            (rawRule['outboundTag'] ??
                    rawRule['outbound'] ??
                    rawRule['action'] ??
                    '')
                .toString()
                .toLowerCase();
        final action = actionValue == 'direct'
            ? 'DIRECT'
            : actionValue == 'block' ||
                  actionValue == 'blackhole' ||
                  actionValue == 'reject'
            ? 'BLOCK'
            : 'PROXY';

        final conditions = RoutingRuleCodec.decode(
          rawRule,
          definitions: definitions,
        );
        final type = 'Составное правило';
        final values = [RoutingRuleCodec.describe(conditions)];
        imported.add(
          AppRule(
            id: '${DateTime.now().microsecondsSinceEpoch}-${imported.length}',
            type: type,
            value: values.join(', '),
            action: action,
            conditions: conditions,
          ),
        );
      }

      if (imported.isEmpty) {
        throw const FormatException('В JSON не найдено правил маршрутизации.');
      }
      final notifier = ref.read(rulesProvider.notifier);
      notifier.addRules(imported);
      AppLogger.log(ref, 'LINK', 'Imported ${imported.length} routing rules');
      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        final skipped = rawRules.length - imported.length;
        CustomNotification.show(
          context,
          skipped > 0
              ? AppLocalizations.text(
                  context,
                  "Импортировано правил: {0}; пропущено: {1}.",
                  args: [imported.length, skipped],
                )
              : AppLocalizations.text(
                  context,
                  "Импортировано правил: {0}.",
                  args: [imported.length],
                ),
        );
      }
    } catch (error) {
      AppLogger.log(ref, 'LINK', 'Routing import failed: $error');
      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Не удалось импортировать правила маршрутизации.",
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _importConfigText(String content) async {
    final trimmed = content.replaceFirst('\uFEFF', '').trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      await _importFromUrl(trimmed);
      return;
    }
    await _notifyImport('Импортирую конфигурации…');
    final configs = ProxyParser.parseSubscription(trimmed);
    if (configs.isEmpty)
      throw const FormatException('Нет поддерживаемых конфигураций VPN');
    final count = await ref
        .read(subscriptionProvider.notifier)
        .addManualConfigs(configs);
    await _notifyImport(
      count == 0
          ? 'Эти конфигурации уже добавлены'
          : 'Добавлено конфигураций: $count',
    );
  }

  ProxyChain? _getActiveChain([List<ProxyChain>? list]) {
    final chains = list ?? ref.read(chainsProvider) ?? [];
    for (final c in chains) {
      if (c.isActive && c.nodes.isNotEmpty) return c;
    }
    return null;
  }

  ProxyConfig? _storedActiveServer([List<Subscription>? list]) {
    for (final sub in list ?? ref.read(subscriptionProvider)) {
      for (final server in sub.servers) if (server.isActive) return server;
    }
    return null;
  }

  ProxyConfig? _getActiveServer([List<Subscription>? list]) {
    final active = _storedActiveServer(list);
    final selection = ref.read(mapSelectionProvider);
    return selection != null && selection.appliesTo(active?.uniqueKey)
        ? selection.server
        : active;
  }

  ProxyConfig _proxyForCore(ProxyConfig server) {
    final selection = ref.read(mapSelectionProvider);
    final source = selection?.server.uniqueKey == server.uniqueKey
        ? selection?.sourceKey
        : null;
    for (final sub in ref.read(subscriptionProvider)) {
      if (sub.servers.any(
        (s) => s.uniqueKey == server.uniqueKey || s.uniqueKey == source,
      ))
        return proxyWithFallbackFingerprint(server, sub.tlsFingerprint);
    }
    return proxyWithFallbackFingerprint(
      server,
      ref.read(settingsProvider).tlsFingerprint,
    );
  }

  ProxyChain? _chainForCore(ProxyChain? chain) =>
      chain?.copyWith(nodes: chain.nodes.map(_proxyForCore).toList());

  void _initNativeListeners() {
    _statsChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == "onStatsUpdate") {
        final String speed = call.arguments["speed"] ?? "0 B/s";
        final String ping = call.arguments["ping"] ?? "---";
        final int total = call.arguments["total"] ?? 0;
        final int? rx = (call.arguments["rx"] as num?)?.toInt();
        final int? tx = (call.arguments["tx"] as num?)?.toInt();

        state = state.copyWith(speed: speed, ping: ping, totalBytes: total);

        if (Platform.isAndroid) {
          await _drainTrafficJournal();
        } else if (rx != null && tx != null) {
          final rawApps = call.arguments["appBytes"];
          Map<String, int>? appBytes;
          if (rawApps is Map) {
            appBytes = <String, int>{};
            for (final entry in rawApps.entries) {
              if (entry.value is num) {
                appBytes[entry.key.toString()] = (entry.value as num).toInt();
              }
            }
          }
          await ref
              .read(statsProvider.notifier)
              .updateFromNative(
                rx,
                tx,
                isWifi: call.arguments["isWifi"] == true,
                isMobile: call.arguments["isMobile"] == true,
                sessionId: call.arguments["sessionId"]?.toString(),
                appBytes: appBytes,
              );
        }
      }
    });

    const MethodChannel('pro.kaleert.nextlink/vpn').setMethodCallHandler((
      call,
    ) async {
      if (!mounted) return null;
      if (call.method == 'updateSubscriptionsInBackground') {
        final ids = (call.arguments as Map?)?['ids'] as List?;
        final report = await ref
            .read(subscriptionProvider.notifier)
            .updateAllSubscriptions(
              onlyIds: ids == null || ids.isEmpty
                  ? null
                  : ids.map((v) => v.toString()).toSet(),
            );
        try {
          await ref.read(automationSyncProvider).flush();
        } catch (_) {
          debugPrint('Subscription update: automation plan refresh deferred');
        }
        return report.toMap();
      }
      if (call.method == 'onVpnState' && call.arguments is Map) {
        _applyNativeState(Map<String, dynamic>.from(call.arguments as Map));
        return null;
      }
      if (call.method == 'onUrlScheme') {
        final url = call.arguments?.toString();
        if (url != null) await _handleUrlScheme(url);
        return null;
      }
      if (call.method == 'onVpnStopped') {
        if (!state.isSwitching && !state.isRetrying) {
          AppLogger.log(
            ref,
            'TUN',
            'VPN stopped by external event (notification/system)',
          );
          _stopTimer();
          state = VpnStateData(status: VpnState.disconnected);
        } else {
          AppLogger.log(
            ref,
            'TUN',
            'Core stopped during transition, keeping connecting state...',
          );
        }
        return null;
      }
      if (call.method == 'onVpnPaused') {
        _stopTimer();
        state = VpnStateData(status: VpnState.disconnected);
        return null;
      }
      if (call.method == 'onVpnResumed') {
        state = VpnStateData(status: VpnState.connected);
        _startTimer();
      }
    });
  }

  void updatePingDisplay(String pingStr) {
    state = state.copyWith(ping: pingStr);
  }

  void _listenToServerAndChainChanges() {
    ref.listen(mapSelectionProvider, (previous, next) {
      if (_applyingNativeSelection ||
          _isBusy ||
          state.isSwitching ||
          state.status != VpnState.connected ||
          _getActiveChain() != null)
        return;
      final target = _getActiveServer();
      if (target == null ||
          target.uniqueKey == _nativeServerKey ||
          previous?.server.uniqueKey == target.uniqueKey)
        return;
      unawaited(
        _seamlessUpdate(
          newServer: target,
          newChain: null,
          oldDisplayName: previous?.server.name ?? target.name,
          onRevert: () =>
              ref.read(mapSelectionProvider.notifier).choose(previous),
        ),
      );
    });
    // Следим за сменой одиночного сервера (только если не включен режим цепочки)
    ref.listen(subscriptionProvider, (previous, next) {
      if (_applyingNativeSelection) return;
      if (state.status == VpnState.connected && !state.isSwitching) {
        if (_getActiveChain() != null) return;

        final previousMapSelection = ref.read(mapSelectionProvider);
        ProxyConfig? oldActive;
        String? oldSubId;
        if (previous != null) {
          for (var sub in previous) {
            for (var srv in sub.servers) {
              if (srv.isActive) {
                oldActive = srv;
                oldSubId = sub.id;
              }
            }
          }
        }

        final newActive = _getActiveServer(next);
        final oldEffective =
            previousMapSelection != null &&
                previousMapSelection.appliesTo(oldActive?.uniqueKey)
            ? previousMapSelection.server
            : oldActive;
        if (newActive != null &&
            oldActive != null &&
            oldEffective?.uniqueKey != newActive.uniqueKey) {
          AppLogger.log(
            ref,
            'UI',
            'Active server changed, updating seamlessly...',
          );
          _seamlessUpdate(
            newServer: newActive,
            newChain: null,
            oldDisplayName:
                previousMapSelection != null &&
                    previousMapSelection.appliesTo(oldActive.uniqueKey)
                ? previousMapSelection.server.name
                : oldActive.name,
            onRevert: () {
              if (oldSubId != null) {
                ref
                    .read(subscriptionProvider.notifier)
                    .setActiveServer(
                      oldSubId,
                      oldActive!,
                      preserveMapSelection: true,
                    );
                unawaited(
                  ref
                      .read(mapSelectionProvider.notifier)
                      .setCurrent(previousMapSelection),
                );
              }
            },
          );
        }
      }
    });

    // Следим за включением / сменой / отключением цепочки на лету
    ref.listen(chainsProvider, (previous, next) {
      if (_applyingNativeSelection) return;
      if (state.status == VpnState.connected && !state.isSwitching) {
        final oldChain = previous != null ? _getActiveChain(previous) : null;
        final newChain = _getActiveChain(next);

        if (oldChain?.id == newChain?.id &&
            jsonEncode(oldChain?.toMap()) == jsonEncode(newChain?.toMap()))
          return;

        final fallbackSrv = _getActiveServer();
        final newServer = newChain != null ? newChain.nodes.last : fallbackSrv;
        if (newServer == null) return;

        final oldName = oldChain?.name ?? fallbackSrv?.name ?? 'VPN';
        AppLogger.log(ref, 'UI', 'Chain mode changed, updating seamlessly...');

        _seamlessUpdate(
          newServer: newServer,
          newChain: newChain,
          oldDisplayName: oldName,
          onRevert: () {
            if (oldChain != null)
              ref.read(chainsProvider.notifier).updateChain(oldChain);
            ref.read(chainsProvider.notifier).setActiveChain(oldChain?.id);
          },
        );
      }
    });
  }

  Future<bool> _checkConnectivity(
    String coreToUse,
    SettingsState settings, {
    int? customPort,
    bool isTestCore = false,
  }) async {
    final port = customPort ?? settings.httpPort;
    AppLogger.log(
      ref,
      'TUN',
      'Checking connectivity via $coreToUse on port $port...',
    );
    if (!isTestCore && Platform.isAndroid) {
      final readiness = await waitForVpnReadiness(
        readSnapshot: () async =>
            await _platform.invokeMapMethod<String, dynamic>('getVpnState') ??
            {},
        isCancelled: () => _isCancelling,
      );
      if (readiness != VpnReadiness.ready) {
        AppLogger.log(
          ref,
          'TUN',
          'VPN did not become ready: ${readiness.name}',
        );
        return false;
      }
    }
    bool isConnected = false;

    for (int i = 0; i < 8; i++) {
      // УВЕЛИЧЕНО ВРЕМЯ ОЖИДАНИЯ ЯДРА ДО 8 СЕКУНД
      if (_isCancelling) return false;

      if (!isTestCore) {
        if (!await _platform.invokeMethod('isRunning')) {
          AppLogger.log(
            ref,
            'CORE',
            '$coreToUse main process exited unexpectedly',
          );
          return false;
        }
      } else {
        if (!await _platform.invokeMethod('isTestCoreRunning')) {
          AppLogger.log(
            ref,
            'CORE',
            '$coreToUse test process exited unexpectedly',
          );
          return false;
        }
      }

      await Future.delayed(const Duration(seconds: 1));

      if (!isTestCore) {
        if (!await _platform.invokeMethod('isRunning')) return false;
      } else {
        if (!await _platform.invokeMethod('isTestCoreRunning')) return false;
      }

      HttpClient? client;
      try {
        client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        client.findProxy = (uri) => "PROXY 127.0.0.1:$port";

        final request = await client
            .getUrl(Uri.parse('http://www.gstatic.com/generate_204'))
            .timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(
          const Duration(seconds: 3),
        );

        if (response.statusCode == 204 || response.statusCode == 200) {
          isConnected = true;
          break;
        }
      } catch (e) {
        AppLogger.log(ref, 'NETWORK', 'Attempt ${i + 1} failed: $e');
      } finally {
        client?.close(force: true);
      }
    }
    return isConnected;
  }

  String _resolveCoreToUse(
    ProxyConfig server,
    ProxyChain? chain,
    SettingsState settings,
  ) {
    final nodes = chain?.nodes ?? [server];
    final hasWireGuard = nodes.any(
      (node) =>
          node.finalJson.containsKey('endpoints') ||
          ['wireguard', 'awg'].contains(node.finalJson['type']) ||
          (node.finalJson['outbounds'] as List? ?? []).any(
            (o) => ['wireguard', 'awg'].contains(o['type']),
          ),
    );
    final hasXrayWireGuard = nodes.any(
      (node) =>
          node.finalJson['protocol'] == 'wireguard' ||
          (node.finalJson['outbounds'] as List? ?? []).any(
            (o) => o['protocol'] == 'wireguard',
          ),
    );
    final nativeRules = ref
        .read(rulesProvider)
        .any(
          (r) =>
              r.conditions != null &&
              RoutingRuleCodec.needsSingBox(r.conditions!),
        );
    if (hasXrayWireGuard && !hasWireGuard) {
      if (nativeRules)
        throw const FormatException(
          'Эти правила требуют Sing-box, а сервер — Xray',
        );
      return 'XRAY';
    }
    bool hasHy2 = false;
    bool hasXhttp = false;

    if (chain != null && chain.nodes.isNotEmpty) {
      hasHy2 = chain.nodes.any(
        (n) => n.protocol.toUpperCase().contains('HYSTERIA'),
      );
      hasXhttp = chain.nodes.any(
        (n) => jsonEncode(n.finalJson).toLowerCase().contains('"xhttp"'),
      );
    } else {
      hasHy2 = server.protocol.toUpperCase().contains('HYSTERIA');
      hasXhttp = jsonEncode(server.finalJson).toLowerCase().contains('"xhttp"');
    }

    String core = settings.preferredCore.toUpperCase();
    if (nativeRules) {
      if (hasXhttp)
        throw const FormatException(
          'Эти правила требуют Sing-box и несовместимы с XHTTP',
        );
      return 'SINGBOX';
    }

    // A mixed Hysteria + XHTTP chain must stay in Xray: Sing-box does not
    // implement XHTTP and its HTTPUpgrade fallback is rejected by XHTTP servers.
    if (hasWireGuard && hasXhttp)
      throw UnsupportedError(
        'Цепочка WireGuard/AmneziaWG + XHTTP требует совместимого ядра с обоими транспортами',
      );
    if (hasWireGuard) return 'SINGBOX';
    if (hasXhttp) return 'XRAY';

    // Use Sing-box for Hysteria-only profiles.
    if (hasHy2) return 'SINGBOX';

    return core;
  }

  Future<void> _seamlessUpdate({
    required ProxyConfig newServer,
    required ProxyChain? newChain,
    required String oldDisplayName,
    required FutureOr<void> Function() onRevert,
  }) async {
    final settings = ref.read(settingsProvider);
    final coreStatus = ref.read(coreManagerProvider);
    final customRules = ref.read(rulesProvider);

    final targetDisplayName = newChain?.name ?? newServer.name;
    final oldConnectedSeconds = state.connectedSeconds;

    state = state.copyWith(
      isSwitching: true,
      targetServerName: targetDisplayName,
      oldServerName: oldDisplayName,
      oldConnectedSeconds: oldConnectedSeconds,
    );

    String coreToUse = _resolveCoreToUse(newServer, newChain, settings);

    final testHttpPort = settings.httpPort + 2;
    final testSocksPort = settings.socksPort + 2;

    final appDir = await getApplicationSupportDirectory();
    final xrayPath =
        '${appDir.path}/${Platform.isAndroid ? 'libxray.so' : 'xray'}';
    final sbPath = await CoreBinaryPaths.singBox(
      appDir.path,
      newChain?.nodes ?? [newServer],
      custom: settings.singboxUrl.isNotEmpty,
    );

    try {
      AppLogger.log(
        ref,
        'UI',
        'Testing $targetDisplayName (Ports $testSocksPort/$testHttpPort)...',
      );

      String testConfigJson = (coreToUse == 'SINGBOX')
          ? jsonEncode(
              SingBoxConfigBuilder(
                activeProxy: _proxyForCore(newServer),
                settings: settings,
                customRules: customRules,
                isTest: true,
                activeChain: _chainForCore(newChain),
              ).build(),
            )
          : jsonEncode(
              XrayConfigBuilder(
                activeProxy: _proxyForCore(newServer),
                settings: settings,
                customRules: customRules,
                isTest: true,
                activeChain: _chainForCore(newChain),
              ).build(),
            ); // <--- ДОБАВИЛИ activeChain

      await _platform.invokeMethod('startTestCore', {
        'config': testConfigJson,
        'coreType': coreToUse,
        'xrayPath': coreStatus.xray.isDownloaded ? xrayPath : null,
        'sbPath':
            (coreStatus.singbox.isDownloaded || sbPath.contains('amnezia'))
            ? sbPath
            : null,
      });

      bool testSuccess = await _checkConnectivity(
        coreToUse,
        settings,
        customPort: testHttpPort,
        isTestCore: true,
      );

      if (!testSuccess && settings.coreFailover && newChain == null) {
        final String protocolName = newServer.protocol.toUpperCase();
        String? fallbackCore = coreToUse == 'XRAY' ? 'SINGBOX' : 'XRAY';

        if (fallbackCore == 'SINGBOX') {
          final outStr = jsonEncode(newServer.finalJson).toLowerCase();
          if (outStr.contains('"network":"xhttp"') ||
              outStr.contains('"type":"xhttp"'))
            fallbackCore = null;
        }
        if (protocolName == 'HYSTERIA2' ||
            protocolName == 'HY2' ||
            protocolName == 'HYSTERIA') {
          if (fallbackCore == 'XRAY') fallbackCore = null;
        }

        if (fallbackCore != null) {
          AppLogger.log(
            ref,
            'CORE',
            'Primary test failed ($coreToUse). Trying $fallbackCore...',
          );
          await _platform.invokeMethod('stopTestCore');
          await Future.delayed(const Duration(milliseconds: 500));

          String fallbackConfigJson = (fallbackCore == 'SINGBOX')
              ? jsonEncode(
                  SingBoxConfigBuilder(
                    activeProxy: _proxyForCore(newServer),
                    settings: settings,
                    customRules: customRules,
                    isTest: true,
                  ).build(),
                )
              : jsonEncode(
                  XrayConfigBuilder(
                    activeProxy: _proxyForCore(newServer),
                    settings: settings,
                    customRules: customRules,
                    isTest: true,
                  ).build(),
                );

          await _platform.invokeMethod('startTestCore', {
            'config': fallbackConfigJson,
            'coreType': fallbackCore,
            'xrayPath': coreStatus.xray.isDownloaded ? xrayPath : null,
            'sbPath':
                (coreStatus.singbox.isDownloaded || sbPath.contains('amnezia'))
                ? sbPath
                : null,
          });

          testSuccess = await _checkConnectivity(
            fallbackCore,
            settings,
            customPort: testHttpPort,
            isTestCore: true,
          );
          if (testSuccess) coreToUse = fallbackCore;
        }
      }

      if (!testSuccess) throw Exception("Тестовое соединение не удалось");

      String mainConfigJson = (coreToUse == 'SINGBOX')
          ? jsonEncode(
              SingBoxConfigBuilder(
                activeProxy: _proxyForCore(newServer),
                settings: settings,
                customRules: customRules,
                isTest: false,
                activeChain: _chainForCore(newChain),
              ).build(),
            )
          : jsonEncode(
              XrayConfigBuilder(
                activeProxy: _proxyForCore(newServer),
                settings: settings,
                customRules: customRules,
                isTest: false,
                activeChain: _chainForCore(newChain),
              ).build(),
            ); // <--- ДОБАВИЛИ activeChain

      await _platform.invokeMethod('updateVpn', {
        'config': mainConfigJson,
        'coreType': coreToUse,
        'serverName': targetDisplayName,
        'serverKey': newChain != null
            ? 'chain:${newChain.id}'
            : newServer.uniqueKey,
        'xrayPath': coreStatus.xray.isDownloaded ? xrayPath : null,
        'sbPath':
            (coreStatus.singbox.isDownloaded || sbPath.contains('amnezia'))
            ? sbPath
            : null,
      });

      _resetTimer();
      _startTimer();
      state = state.copyWith(
        status: VpnState.connected,
        isSwitching: false,
        targetServerName: null,
        oldServerName: null,
      );
      if (Platform.isAndroid) unawaited(syncNativeState());

      final context = appNavigatorKey.currentContext;
      final overlay = appNavigatorKey.currentState?.overlay;
      if (context != null && overlay != null) {
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Переключено на {0}",
            args: [targetDisplayName],
          ),
          overlay: overlay,
        );
      }
    } catch (e) {
      AppLogger.log(ref, 'UI', 'Switch failed: $e');

      final context = appNavigatorKey.currentContext;
      final overlay = appNavigatorKey.currentState?.overlay;
      if (context != null && overlay != null) {
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Ошибка переключения: {0}",
            args: [e.toString().replaceAll('Exception: ', '')],
          ),
          isError: true,
          overlay: overlay,
        );
      }

      await onRevert();
      state = state.copyWith(
        isSwitching: false,
        targetServerName: null,
        oldServerName: null,
      );
    } finally {
      await _platform.invokeMethod('stopTestCore');
    }
  }

  Future<void> syncNativeState() => _syncWithNative();

  void _applyNativeState(Map<String, dynamic> snapshot) {
    if (!mounted || _isBusy || state.isSwitching || state.isRetrying) return;
    final revision = (snapshot['revision'] as num?)?.toInt() ?? 0;
    if (revision < _lastNativeRevision) return;
    _lastNativeRevision = revision;
    final status = switch (snapshot['status']) {
      'connected' => VpnState.connected,
      'starting' => VpnState.connecting,
      'paused' => VpnState.paused,
      _ => VpnState.disconnected,
    };
    final nativeKey = snapshot['serverKey'];
    if (nativeKey is String) _nativeServerKey = nativeKey;
    if (status == VpnState.connected &&
        nativeKey is String &&
        nativeKey.isNotEmpty) {
      _applyingNativeSelection = true;
      try {
        if (nativeKey.startsWith('chain:')) {
          final id = nativeKey.substring('chain:'.length);
          if (ref.read(chainsProvider).any((c) => c.id == id) &&
              _getActiveChain()?.id != id) {
            ref.read(chainsProvider.notifier).setActiveChain(id);
          }
        } else if (ref.read(mapSelectionProvider)?.server.uniqueKey !=
            nativeKey) {
          for (final sub in ref.read(subscriptionProvider)) {
            final matching = sub.servers.where((s) => s.uniqueKey == nativeKey);
            if (matching.isNotEmpty && ref.read(mapSelectionProvider) != null) {
              unawaited(
                ref.read(mapSelectionProvider.notifier).setCurrent(null),
              );
            }
            if (matching.isNotEmpty &&
                (!matching.first.isActive || _getActiveChain() != null)) {
              ref.read(chainsProvider.notifier).setActiveChain(null);
              ref
                  .read(subscriptionProvider.notifier)
                  .setActiveServer(sub.id, matching.first);
              break;
            }
          }
        }
      } finally {
        _applyingNativeSelection = false;
      }
    }
    final previous = state.status;
    if (status == VpnState.disconnected) _sessionClock.reset();
    _sessionClock.sync(
      session: status == VpnState.disconnected
          ? 'stopped'
          : (snapshot['timerSessionId']?.toString() ??
                snapshot['sessionId']?.toString() ??
                ''),
      elapsedMs: status == VpnState.disconnected
          ? 0
          : (snapshot['elapsedMilliseconds'] as num?)?.toInt() ??
                ((snapshot['elapsedSeconds'] as num?)?.toInt() ?? 0) * 1000,
      running: status == VpnState.connected,
    );
    state = VpnStateData(
      status: status,
      serviceServerName: snapshot['serverName']?.toString(),
      serviceServerKey: snapshot['serverKey']?.toString(),
      connectedSeconds: _sessionClock.elapsedSeconds,
      speed: snapshot['speed']?.toString() ?? '0 B/s',
      ping: snapshot['ping']?.toString() ?? '---',
      totalBytes: status == VpnState.disconnected ? 0 : state.totalBytes,
    );
    if (status == VpnState.connected) {
      if (previous != status || _timer == null) _startTimer();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _drainTrafficJournal() async {
    if (_trafficDrainInFlight || !mounted) return;
    _trafficDrainInFlight = true;
    try {
      final raw = await _platform.invokeMethod<String>('getPendingTraffic');
      for (final entry in jsonDecode(raw ?? '[]') as List) {
        if (!mounted) return;
        final rx = (entry['rx'] as num).toInt();
        final tx = (entry['tx'] as num).toInt();
        final session = entry['sessionId'].toString();
        final apps = Map<String, int>.from(
          (entry['appBytes'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          ),
        );
        await ref
            .read(statsProvider.notifier)
            .updateFromNative(
              rx,
              tx,
              sessionId: session,
              appBytes: apps,
              isWifi: entry['network'] == 'wifi',
              isMobile: entry['network'] == 'mobile',
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                (entry['timestamp'] as num).toInt(),
              ),
            );
        await _platform.invokeMethod<void>('acknowledgeTraffic', {
          'sessionId': session,
          'rx': rx,
          'tx': tx,
        });
      }
    } on MissingPluginException {
      // Non-Android test environments do not have a native traffic journal.
    } finally {
      _trafficDrainInFlight = false;
    }
  }

  Future<void> _syncWithNative() async {
    if (_nativeSyncInFlight || !mounted) return;
    _nativeSyncInFlight = true;
    try {
      if (Platform.isAndroid) {
        final snapshot = await _platform.invokeMapMethod<String, dynamic>(
          'getVpnState',
        );
        if (snapshot != null) _applyNativeState(snapshot);
        await _drainTrafficJournal();
        return;
      }
      final bool isRunning = await _platform.invokeMethod('isRunning');
      if (isRunning) {
        if (state.status == VpnState.disconnected) {
          final prefs = await SharedPreferences.getInstance();
          final startTime =
              prefs.getInt('vpn_start_time') ??
              DateTime.now().millisecondsSinceEpoch;
          final elapsed =
              (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000;

          state = VpnStateData(
            status: VpnState.connected,
            connectedSeconds: elapsed,
          );
          _startTimer();
        }
      } else {
        if (state.status != VpnState.disconnected &&
            state.status != VpnState.connecting) {
          _stopTimer();
          state = VpnStateData(status: VpnState.disconnected);
        }
      }
    } catch (_) {
    } finally {
      _nativeSyncInFlight = false;
    }
  }

  void _startTimer() async {
    _timer?.cancel();
    if (Platform.isAndroid) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && state.status == VpnState.connected) {
          state = state.copyWith(
            connectedSeconds: _sessionClock.elapsedSeconds,
          );
        }
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    if (state.connectedSeconds == 0) {
      await prefs.setInt(
        'vpn_start_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      final startTime = prefs.getInt('vpn_start_time');
      if (startTime != null) {
        final elapsed =
            (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000;
        state = state.copyWith(connectedSeconds: elapsed);
      }
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      state = state.copyWith(connectedSeconds: state.connectedSeconds + 1);
    });
  }

  void _resetTimer() async {
    _sessionClock.reset();
    if (Platform.isAndroid) {
      state = state.copyWith(connectedSeconds: 0);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vpn_start_time', DateTime.now().millisecondsSinceEpoch);
    state = state.copyWith(connectedSeconds: 0);
  }

  void _stopTimer() async {
    _timer?.cancel();
    _timer = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vpn_start_time');
  }

  Timer? _timer;

  Future<void> toggle() async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      if (Platform.isAndroid && state.status == VpnState.paused) {
        await _platform.invokeMethod('resumeVpn');
      } else if (state.status == VpnState.disconnected) {
        _isCancelling = false;
        await _connect();
      } else if (state.status == VpnState.connecting) {
        _isCancelling = true;
        await _platform.invokeMethod('stopVpn');
        state = VpnStateData(status: VpnState.disconnected);
        AppLogger.log(ref, 'UI', 'Connection attempt cancelled');
      } else {
        _isCancelling = true;
        await _disconnect();
      }
    } finally {
      _isBusy = false;
      if (Platform.isAndroid) unawaited(syncNativeState());
    }
  }

  Future<void> disconnect() async {
    if (_isBusy || state.isSwitching)
      throw const FormatException('Дождитесь завершения подключения');
    _isBusy = true;
    try {
      _isCancelling = true;
      await _disconnect();
    } finally {
      _isBusy = false;
      if (Platform.isAndroid) unawaited(syncNativeState());
    }
  }

  Future<void> connectToServer(ProxyConfig selected, {String? sourceKey}) =>
      _connectMapTarget(selected, sourceKey: sourceKey);
  Future<void> connectToChain(ProxyChain chain) async {
    if (chain.nodes.isEmpty)
      throw const FormatException('Добавьте хотя бы один узел');
    await _connectMapTarget(chain.nodes.last, chain: chain);
  }

  Future<void> _connectMapTarget(
    ProxyConfig selected, {
    String? sourceKey,
    ProxyChain? chain,
  }) async {
    if (_isBusy || state.isSwitching || state.status == VpnState.connecting) {
      throw const FormatException('Дождитесь завершения подключения');
    }
    _isBusy = true;
    final notifier = ref.read(subscriptionProvider.notifier);
    final runtime = ref.read(mapSelectionProvider.notifier);
    await notifier.ready;
    await runtime.ready;
    await ref.read(chainsProvider.notifier).ready;
    final oldChain = _getActiveChain(), oldServer = _getActiveServer();
    final oldStored = _storedActiveServer();
    final oldSelection = ref.read(mapSelectionProvider);
    String? oldSub;
    for (final sub in ref.read(subscriptionProvider)) {
      if (sub.servers.any((s) => s.uniqueKey == oldStored?.uniqueKey))
        oldSub = sub.id;
    }
    Future<void> restore() async {
      _applyingNativeSelection = true;
      try {
        if (oldStored != null && oldSub != null)
          notifier.setActiveServer(
            oldSub,
            oldStored,
            preserveMapSelection: true,
          );
        ref.read(chainsProvider.notifier).setActiveChain(oldChain?.id);
        await runtime.choose(oldSelection);
      } finally {
        _applyingNativeSelection = false;
      }
    }

    try {
      _applyingNativeSelection = true;
      try {
        ref.read(chainsProvider.notifier).setActiveChain(chain?.id);
        if (chain == null) {
          final key = sourceKey ?? selected.uniqueKey;
          Subscription? source;
          for (final sub in ref.read(subscriptionProvider)) {
            if (sub.servers.any((s) => s.uniqueKey == key)) {
              source = sub;
              break;
            }
          }
          if (source != null)
            notifier.setActiveServer(
              source.id,
              source.servers.firstWhere((s) => s.uniqueKey == key),
              preserveMapSelection: true,
            );
          final stored = _storedActiveServer();
          await runtime.choose(
            selected.uniqueKey == stored?.uniqueKey
                ? null
                : MapServerSelection(
                    selected,
                    anchorKey: stored?.uniqueKey,
                    sourceKey: source?.servers
                        .firstWhere((s) => s.uniqueKey == key)
                        .uniqueKey,
                  ),
          );
        } else {
          await runtime.choose(null);
        }
      } finally {
        _applyingNativeSelection = false;
      }
      if (state.status == VpnState.connected) {
        if (oldChain?.id == chain?.id &&
            oldServer?.uniqueKey == selected.uniqueKey)
          return;
        try {
          await _seamlessUpdate(
            newServer: selected,
            newChain: chain,
            oldDisplayName: oldChain?.name ?? oldServer?.name ?? selected.name,
            onRevert: restore,
          );
        } catch (_) {
          await restore();
          state = state.copyWith(
            isSwitching: false,
            targetServerName: null,
            oldServerName: null,
          );
          rethrow;
        }
      } else {
        if (state.status == VpnState.paused) await _disconnect();
        _isCancelling = false;
        await _connect();
      }
    } finally {
      _isBusy = false;
      if (Platform.isAndroid) unawaited(syncNativeState());
    }
  }

  Future<void> _connect() async {
    await ref.read(mapSelectionProvider.notifier).ready;
    final settings = ref.read(settingsProvider);
    final activeChain = _getActiveChain();
    ProxyConfig? activeServer = _getActiveServer();

    if (activeChain != null && activeChain.nodes.isNotEmpty) {
      activeServer = activeChain.nodes.last;
    }

    if (activeServer == null) {
      throw Exception("select_server");
    }

    final requiredCore = _resolveCoreToUse(activeServer, activeChain, settings);
    final coreManager = ref.read(coreManagerProvider.notifier);
    final usesAwg =
        settings.singboxUrl.isEmpty &&
        (activeChain?.nodes ?? [activeServer]).any(CoreBinaryPaths.needsAwg);
    final needsCore = usesAwg
        ? !ref.read(coreManagerProvider).awg.isDownloaded
        : !ref.read(coreManagerProvider).isCoreAvailable(requiredCore);
    final configText = [
      jsonEncode(activeServer.finalJson),
      if (activeChain != null)
        ...activeChain.nodes.map((node) => jsonEncode(node.finalJson)),
    ].join(' ').toLowerCase();
    final hasGeoRules =
        configText.contains('geosite') ||
        configText.contains('geoip') ||
        ref
            .read(rulesProvider)
            .any((rule) => rule.type == 'GeoSite' || rule.type == 'GeoIP');
    final needsGeoFiles =
        requiredCore == 'XRAY' &&
        hasGeoRules &&
        !ref.read(coreManagerProvider).rules.isDownloaded;
    if (needsCore || needsGeoFiles) {
      state = VpnStateData(status: VpnState.connecting);
      try {
        if (needsCore) {
          AppLogger.log(
            ref,
            'UI',
            '$requiredCore is missing, downloading required core...',
          );
          await coreManager.downloadItem(
            usesAwg
                ? CoreType.awg
                : requiredCore == 'SINGBOX'
                ? CoreType.singbox
                : CoreType.xray,
          );
          if (usesAwg
              ? !ref.read(coreManagerProvider).awg.isDownloaded
              : !ref.read(coreManagerProvider).isCoreAvailable(requiredCore)) {
            throw Exception(
              'Не удалось загрузить $requiredCore. Проверьте Центр ресурсов и попробуйте снова.',
            );
          }
        }
        if (needsGeoFiles) {
          AppLogger.log(
            ref,
            'UI',
            'Geo rule files are required; downloading...',
          );
          await coreManager.downloadItem(CoreType.rules);
          if (!ref.read(coreManagerProvider).rules.isDownloaded) {
            throw Exception(
              'Не удалось загрузить файлы GeoIP/GeoSite из Центра ресурсов.',
            );
          }
        }
      } catch (_) {
        state = VpnStateData(status: VpnState.disconnected);
        rethrow;
      }
      state = VpnStateData(status: VpnState.disconnected);
    }

    if (_isCancelling) return;

    final displayTarget = activeChain != null
        ? 'Цепочка: ${activeChain.name}'
        : activeServer.name;

    state = VpnStateData(status: VpnState.connecting);
    AppLogger.log(ref, 'UI', 'Starting connection to: $displayTarget');

    try {
      final bool isPrepared = await _platform.invokeMethod('prepareVpn');
      if (!isPrepared) {
        AppLogger.log(ref, 'UI', 'VPN Permission required');
        state = VpnStateData(status: VpnState.disconnected);
        return;
      }

      if (_isCancelling) {
        state = VpnStateData(status: VpnState.disconnected);
        return;
      }

      String primaryCore = _resolveCoreToUse(
        activeServer,
        activeChain,
        settings,
      );
      if (activeChain != null) {
        AppLogger.log(
          ref,
          'CORE',
          'Proxy Chain active (${activeChain.nodes.length} hops). Using SINGBOX.',
        );
      }

      bool success = await _attemptConnection(
        activeServer,
        primaryCore,
        settings,
        activeChain: activeChain,
      );

      if (_isCancelling) {
        await _platform.invokeMethod('stopVpn');
        state = VpnStateData(status: VpnState.disconnected);
        return;
      }

      // Failover делается только для одиночных серверов (цепочки требуют Sing-box detour)
      if (!success && settings.coreFailover && activeChain == null) {
        final String protocolName = activeServer.protocol.toUpperCase();
        List<String> fallbacks = primaryCore == 'XRAY' ? ['SINGBOX'] : ['XRAY'];

        if (protocolName == 'HYSTERIA2' ||
            protocolName == 'HY2' ||
            protocolName == 'HYSTERIA') {
          fallbacks.remove('XRAY');
        }
        if (fallbacks.contains('SINGBOX')) {
          final outStr = jsonEncode(activeServer.finalJson).toLowerCase();
          if (outStr.contains('"network":"xhttp"') ||
              outStr.contains('"type":"xhttp"')) {
            fallbacks.remove('SINGBOX');
          }
        }

        for (String fallbackCore in fallbacks) {
          AppLogger.log(
            ref,
            'CORE',
            'Primary core ($primaryCore) failed. Switching to $fallbackCore...',
          );

          state = state.copyWith(isRetrying: true, status: VpnState.connecting);
          await _platform.invokeMethod('stopVpn');
          await Future.delayed(const Duration(seconds: 1));

          if (_isCancelling) {
            state = VpnStateData(status: VpnState.disconnected);
            return;
          }

          success = await _attemptConnection(
            activeServer,
            fallbackCore,
            settings,
          );
          if (success) {
            state = state.copyWith(isRetrying: false);
            break;
          }
        }
        state = state.copyWith(isRetrying: false);
      }

      if (_isCancelling) {
        await _platform.invokeMethod('stopVpn');
        state = VpnStateData(status: VpnState.disconnected);
        return;
      }

      if (!success) {
        final timeoutProfiles = ref
            .read(profilesProvider)
            .where(
              (profile) => profile.isEnabled && profile.hasTrigger('timeout'),
            )
            .toList();
        if (activeChain == null &&
            timeoutProfiles.isNotEmpty &&
            await _tryProfileTimeoutFallback(
              settings,
              activeServer,
              timeoutProfiles,
            )) {
          return;
        }
        throw Exception(
          activeChain != null
              ? "Не удалось поднять цепочку серверов (проверьте доступность всех узлов)"
              : "Не удалось подключиться: сервер недоступен",
        );
      }

      AppLogger.log(ref, 'UI', 'VPN Connected successfully ($displayTarget)');
      state = state.copyWith(status: VpnState.connected);
      _startTimer();
    } catch (e) {
      AppLogger.log(ref, 'UI', 'Failed to start VPN: $e');
      await _platform.invokeMethod('stopVpn');
      state = VpnStateData(status: VpnState.disconnected);

      final context = appNavigatorKey.currentContext;
      final overlay = appNavigatorKey.currentState?.overlay;
      if (context != null && overlay != null) {
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Ошибка подключения: {0}",
            args: [e.toString().replaceAll('Exception: ', '')],
          ),
          isError: true,
          overlay: overlay,
        );
      }
      rethrow;
    }
  }

  Future<void> _disconnect() async {
    _stopTimer();
    state = VpnStateData(status: VpnState.disconnected);
    AppLogger.log(ref, 'UI', 'Disconnecting...');
    try {
      await _platform.invokeMethod('stopVpn');
    } catch (e) {
      AppLogger.log(ref, 'UI', 'Error stopping VPN: $e');
    }
  }

  Future<bool> _tryProfileTimeoutFallback(
    SettingsState settings,
    ProxyConfig failedServer,
    List<AppProfile> profiles,
  ) async {
    final subscriptions = ref.read(subscriptionProvider);
    final servers = [
      for (final subscription in subscriptions)
        for (final server in subscription.servers) (subscription.id, server),
    ];
    if (servers.length < 2) return false;
    final current = servers.indexWhere(
      (entry) => entry.$2.uniqueKey == failedServer.uniqueKey,
    );
    final candidates = <(String, ProxyConfig)>[];
    final triedKeys = {failedServer.uniqueKey};
    for (final profile in profiles) {
      final pinned = profile.serverKey;
      final group = servers
          .where(
            (entry) =>
                profile.serverKeys.isEmpty ||
                profile.serverKeys.contains(entry.$2.uniqueKey),
          )
          .toList();
      final ordered = pinned == null
          ? [
              for (var step = 1; step <= servers.length; step++)
                if (group.any(
                  (e) =>
                      e.$2.uniqueKey ==
                      servers[(current + step) % servers.length].$2.uniqueKey,
                ))
                  servers[(current + step) % servers.length],
            ]
          : [
              ...servers.where((entry) => entry.$2.uniqueKey == pinned),
              ...group.where((entry) => entry.$2.uniqueKey != pinned),
            ];
      for (final candidate in ordered) {
        if (triedKeys.add(candidate.$2.uniqueKey)) candidates.add(candidate);
      }
    }
    for (final candidate in candidates) {
      if (_isCancelling) return false;
      AppLogger.log(
        ref,
        'PROFILE',
        'Connection timed out; trying ${candidate.$2.name}',
      );
      try {
        await _platform.invokeMethod('stopVpn');
        await Future.delayed(const Duration(milliseconds: 800));
        final server = candidate.$2;
        final core = _resolveCoreToUse(server, null, settings);
        if (await _attemptConnection(server, core, settings)) {
          ref
              .read(subscriptionProvider.notifier)
              .setActiveServer(candidate.$1, server);
          state = VpnStateData(status: VpnState.connected);
          _startTimer();
          AppLogger.log(ref, 'PROFILE', 'Connected with ${server.name}');
          return true;
        }
      } catch (error) {
        AppLogger.log(ref, 'PROFILE', 'Fallback failed: $error');
      }
    }
    await _platform.invokeMethod('stopVpn');
    return false;
  }

  Future<bool> _attemptConnection(
    ProxyConfig activeServer,
    String coreToUse,
    SettingsState settings, {
    ProxyChain? activeChain,
  }) async {
    final String protocolName = activeServer.protocol.toUpperCase();
    final String configJson;
    final customRules = ref.read(rulesProvider);

    if (coreToUse == 'SINGBOX') {
      final configBuilder = SingBoxConfigBuilder(
        activeProxy: _proxyForCore(activeServer),
        settings: settings,
        customRules: customRules,
        activeChain: _chainForCore(activeChain),
      );
      configJson = jsonEncode(configBuilder.build());
    } else {
      final configBuilder = XrayConfigBuilder(
        activeProxy: _proxyForCore(activeServer),
        settings: settings,
        customRules: customRules,
        activeChain: _chainForCore(activeChain), // Runtime-only defaults
      );
      configJson = jsonEncode(configBuilder.build());
    }

    final coreStatus = ref.read(coreManagerProvider);
    final appDir = await getApplicationSupportDirectory();
    final xrayPath =
        '${appDir.path}/${Platform.isAndroid ? 'libxray.so' : 'xray'}';
    final sbPath = await CoreBinaryPaths.singBox(
      appDir.path,
      activeChain?.nodes ?? [activeServer],
      custom: settings.singboxUrl.isNotEmpty,
    );

    final displayServerName = activeChain != null
        ? activeChain.name
        : activeServer.name;

    AppLogger.log(
      ref,
      'CORE',
      'Launching $coreToUse service for $displayServerName...',
    );
    try {
      if (_isCancelling) return false;
      await _platform.invokeMethod('startVpn', {
        'config': configJson,
        'protocol': protocolName,
        'coreType': coreToUse,
        'serverName': displayServerName,
        'serverKey': activeChain != null
            ? 'chain:${activeChain.id}'
            : activeServer.uniqueKey,
        'xrayPath': coreStatus.xray.isDownloaded ? xrayPath : null,
        'sbPath':
            (coreStatus.singbox.isDownloaded || sbPath.contains('amnezia'))
            ? sbPath
            : null,
        'enableTun': true,
        'tunMtu': settings.tunMtu,
        'ipv6': settings.ipv6,
        'strictMode': settings.strictMode,
        'bypassLan': settings.bypassLan,
        'socksPort': settings.socksPort,
        'httpPort': settings.httpPort,
        'perAppEnabled': settings.perAppEnabled,
        'perAppDefaultRule': settings.perAppDefaultRule,
        'perAppRules': settings.perAppRules,
      });
    } catch (e) {
      AppLogger.log(ref, 'CORE', 'Native start failed: $e');
      return false;
    }

    bool isConnected = await _checkConnectivity(coreToUse, settings);
    if (!isConnected) {
      AppLogger.log(ref, 'TUN', 'Connectivity check failed for $coreToUse');
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    _nativeSyncTimer?.cancel();
    _platform.setMethodCallHandler(null);
    _statsChannel.setMethodCallHandler(null);
    _timer?.cancel();
    super.dispose();
  }
}

final vpnProvider = StateNotifierProvider<VpnNotifier, VpnStateData>(
  (ref) => VpnNotifier(ref),
);

// --- МЕНЕДЖЕР СТАТУСА БАТАРЕИ ---
class BatteryStatusNotifier extends StateNotifier<bool> {
  static const _platform = MethodChannel('pro.kaleert.nextlink/battery');

  BatteryStatusNotifier() : super(true) {
    checkStatus();
  }

  Future<void> checkStatus() async {
    if (!Platform.isAndroid) {
      state = true;
      return;
    }
    try {
      final bool isDisabled = await _platform.invokeMethod(
        'isBatteryOptimizationDisabled',
      );
      state = isDisabled;
    } catch (e) {
      debugPrint("Error checking battery status: $e");
    }
  }

  Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('openBatterySettings');
    } catch (e) {
      debugPrint("Error opening battery settings: $e");
    }
  }
}

final batteryStatusProvider =
    StateNotifierProvider<BatteryStatusNotifier, bool>(
      (ref) => BatteryStatusNotifier(),
    );
final batteryWarningShownProvider = StateProvider<bool>((ref) => false);

// --- МЕНЕДЖЕР ВНЕШНЕГО IP ---
class IpInfoState {
  final String ip;
  final String countryCode;
  final String country;
  final String city;
  final IpLocation? details;
  final bool isLoading;

  IpInfoState({
    this.ip = '---',
    this.countryCode = '',
    this.country = '',
    this.city = '',
    this.details,
    this.isLoading = false,
  });

  String get displayLocation {
    if (isLoading && ip == '---') return 'Загрузка...';
    if (ip == '---') return 'Узнать IP';
    final locLabel = countryCode.isNotEmpty ? countryCode : country;
    if (locLabel.isEmpty) return ip;
    return '$ip · $locLabel${city.isNotEmpty ? ', $city' : ''}';
  }
}

class IpInfoNotifier extends StateNotifier<IpInfoState> {
  IpInfoNotifier() : super(IpInfoState());
  final _locations = IpLocationCache();
  int _request = 0;

  Future<void> fetchIp({int? proxyPort}) async {
    final request = ++_request;
    final previous = state;
    state = IpInfoState(
      ip: previous.ip,
      countryCode: previous.countryCode,
      country: previous.country,
      city: previous.city,
      details: previous.details,
      isLoading: true,
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    if (proxyPort != null)
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    Future<Map<String, dynamic>> get(String url) async {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode != 200)
        throw const FormatException('IP lookup failed');
      return Map<String, dynamic>.from(
        jsonDecode(
          await res
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 4)),
        ) as Map,
      );
    }

    try {
      final data = await get('https://api.ipify.org?format=json');
      final ip = '${data['ip'] ?? ''}';
      if (ip.isEmpty) throw const FormatException('Empty IP');
      if (!mounted || request != _request) return;
      state = IpInfoState(ip: ip);
      try {
        final location = await _locations.lookup(
          ip,
          () => get('https://ipwho.is/${Uri.encodeComponent(ip)}'),
        );
        if (!mounted || request != _request) return;
        state = IpInfoState(
          ip: ip,
          countryCode: location.countryCode,
          country: location.country,
          city: location.city,
          details: location,
        );
      } catch (_) {
        /* The current IP remains visible if country lookup fails. */
      }
    } catch (_) {
      if (mounted && request == _request)
        state = IpInfoState(
          ip: previous.ip,
          countryCode: previous.countryCode,
          country: previous.country,
          city: previous.city,
          details: previous.details,
        );
    } finally {
      client.close(force: true);
    }
  }
}

final ipInfoProvider = StateNotifierProvider<IpInfoNotifier, IpInfoState>(
  (ref) => IpInfoNotifier(),
);

// ================= HOME SCREEN =================
class HomeScreen extends ConsumerStatefulWidget {
  final bool preview;
  const HomeScreen({super.key, this.preview = false});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  static bool _startupActionsStarted = false;
  bool _autoConnecting = false;
  bool _buildingMapChain = false;
  DateTime? _backgroundedAt;
  static const _vpnChannel = MethodChannel('pro.kaleert.nextlink/vpn');
  Timer? _systemInfoTimer;
  double? _coreMemoryMb;
  String? _coreMemoryName;
  bool _coreMemoryUnavailable = false;
  bool _isReadingCoreMemory = false;
  bool _isAutoPingRunning = false;
  bool _isAppResumed = true;
  int _systemInfoTick = 0;
  bool _isEvaluatingProfile = false;
  String? _lastPhysicalNetwork;
  bool? _lastHotspotState;
  final _profileTimers = ProfileTimerSchedule();

  @override
  void initState() {
    super.initState();
    if (widget.preview) return;

    // Start downloads immediately, while onboarding is displayed.
    unawaited(ref.read(coreManagerProvider.notifier).preloadMissingResources());

    WidgetsBinding.instance.addObserver(this);
    ThemeActionRegistry.run = _runThemeAction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showFirstRunHelp());
      _refreshHomeIp();
      unawaited(_runStartupActions());
      _systemInfoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _systemInfoTick++;
        // Keep automation alive while the VPN foreground service is running
        // and the Flutter activity is temporarily in the background.
        if (_systemInfoTick % 5 == 0) {
          unawaited(_evaluateProfileTriggers());
        }
        if (!_isAppResumed) return;
        if (_systemInfoTick % 20 == 0) {
          _refreshHomeIp();
        }
        if (_systemInfoTick % 10 == 0) {
          _refreshAutoPing();
        }
        _refreshCoreMemory();
      });
    });
  }

  Future<void> _showFirstRunHelp() async {
    await ClientTour.maybeShow(context);
    if (mounted && ModalRoute.of(context)?.isCurrent != false)
      _checkAndShowBatteryDialog();
  }

  Future<void> _runStartupActions() async {
    if (_startupActionsStarted || !mounted) return;
    _startupActionsStarted = true;
    await ref.read(settingsProvider.notifier).ready;
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final subscriptionsNotifier = ref.read(subscriptionProvider.notifier);
    await subscriptionsNotifier.ready;
    await ref.read(chainsProvider.notifier).ready;
    if (Platform.isAndroid) {
      await _vpnChannel.invokeMethod<void>('scheduleSubscriptionUpdates');
    }
    await _autoConnectOnOpen();

    if (settings.updateOnStart) {
      await subscriptionsNotifier.updateAllSubscriptions();
    }

    if (settings.pingOnStart) {
      ProxyConfig? server;
      ProxyChain? chain;
      for (final candidate in ref.read(chainsProvider)) {
        if (candidate.isActive && candidate.nodes.isNotEmpty) {
          chain = candidate;
          server = candidate.nodes.last;
          break;
        }
      }
      if (server == null) {
        for (final subscription in ref.read(subscriptionProvider)) {
          for (final candidate in subscription.servers) {
            if (candidate.isActive) {
              server = candidate;
              break;
            }
          }
          if (server != null) break;
        }
      }
      final pingNeedsXray = chain != null
          ? chain.nodes.any(
              (node) =>
                  jsonEncode(node.finalJson).toLowerCase().contains('xhttp'),
            )
          : jsonEncode(server?.finalJson ?? const {})
                .toLowerCase()
                .contains('xhttp');
      final pingNeedsSingBox =
          !pingNeedsXray &&
          (chain?.nodes.every(
                (node) => node.protocol.toUpperCase().contains('HYSTERIA'),
              ) ??
              (server?.protocol.toUpperCase().contains('HYSTERIA') ?? false));
      final pingCore = pingNeedsXray
          ? 'XRAY'
          : pingNeedsSingBox
          ? 'SINGBOX'
          : settings.preferredCore;
      if (server != null &&
          ref.read(coreManagerProvider).isCoreAvailable(pingCore)) {
        try {
          await PingUtils.pingServerEx(
            server,
            settings,
            customRules: ref.read(rulesProvider),
            activeChain: chain,
            timeout: const Duration(seconds: 5),
          );
        } catch (error) {
          AppLogger.log(ref, 'STARTUP', 'Initial ping failed: $error');
        }
      }
    }
  }

  Future<void> _autoConnectOnOpen() async {
    if (_autoConnecting || !mounted) return;
    _autoConnecting = true;
    try {
      await ref.read(settingsProvider.notifier).ready;
      await ref.read(subscriptionProvider.notifier).ready;
      await ref.read(chainsProvider.notifier).ready;
      if (!mounted || !ref.read(settingsProvider).connectOnStart) return;
      await ref.read(rulesProvider.notifier).ready;
      await ref.read(coreManagerProvider.notifier).ready;
      if (!mounted) return;
      if (await _vpnChannel.invokeMethod<bool>('isRunning') == true) return;
      if (mounted && ref.read(vpnProvider).status == VpnState.disconnected) {
        await ref.read(vpnProvider.notifier).toggle();
      }
    } catch (error) {
      AppLogger.log(ref, 'STARTUP', 'Auto-connect failed: $error');
    } finally {
      _autoConnecting = false;
    }
  }

  @override
  void dispose() {
    _systemInfoTimer?.cancel();
    if (ThemeActionRegistry.run == _runThemeAction)
      ThemeActionRegistry.run = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppResumed = true;
      unawaited(ref.read(vpnProvider.notifier).syncNativeState());
      ref.read(batteryStatusProvider.notifier).checkStatus();
      _refreshHomeIp();
      _refreshCoreMemory();
      unawaited(_evaluateProfileTriggers());
      if (_backgroundedAt != null &&
          DateTime.now().difference(_backgroundedAt!) >
              const Duration(seconds: 3)) {
        unawaited(_autoConnectOnOpen());
      }
      _backgroundedAt = null;
    } else {
      _isAppResumed = false;
      if (state == AppLifecycleState.paused) _backgroundedAt = DateTime.now();
    }
  }

  void _refreshHomeIp() {
    final connected = ref.read(vpnProvider).status == VpnState.connected;
    final proxyPort = connected ? ref.read(settingsProvider).httpPort : null;
    ref.read(ipInfoProvider.notifier).fetchIp(proxyPort: proxyPort);
  }

  Future<void> _evaluateProfileTriggers() async {
    if (Platform.isAndroid) return;
    if (_isEvaluatingProfile || !mounted) return;
    _isEvaluatingProfile = true;
    try {
      await ref.read(profilesProvider.notifier).ready;
      if (!mounted) return;
      final environment = await _vpnChannel.invokeMapMethod<String, dynamic>(
        'getNetworkEnvironment',
      );
      if (!mounted || environment == null) return;
      final network = environment['network']?.toString() ?? 'none';
      final hotspot = environment['hotspot'] == true;
      final previousNetwork = _lastPhysicalNetwork;
      final previousHotspot = _lastHotspotState;
      _lastPhysicalNetwork = network;
      _lastHotspotState = hotspot;

      final profiles = ref.read(profilesProvider);
      final enabledProfiles = profiles
          .where((profile) => profile.isEnabled)
          .toList();
      if (enabledProfiles.isEmpty) {
        _profileTimers.nextDue([], connected: false, now: DateTime.now());
        return;
      }
      final networkChanged =
          previousNetwork != null && previousNetwork != network;

      AppProfile? triggered;
      String? triggeredBy;
      for (final profile in enabledProfiles) {
        for (final trigger in profile.triggers) {
          final matches = switch (trigger) {
            'any_network' =>
              network != 'none' &&
                  (previousNetwork == null || previousNetwork == 'none'),
            'wifi' => network == 'wifi' && previousNetwork != 'wifi',
            'mobile' => network == 'mobile' && previousNetwork != 'mobile',
            'wifi_to_mobile' =>
              previousNetwork == 'wifi' && network == 'mobile',
            'network_change' => networkChanged && network != 'none',
            'hotspot' => hotspot && previousHotspot != true,
            _ => false,
          };
          if (matches) {
            triggered = profile;
            triggeredBy = trigger;
            break;
          }
        }
        if (triggered != null) break;
      }

      if (triggered != null) {
        final changeNetwork =
            triggeredBy == 'any_network' ||
            triggeredBy == 'wifi' ||
            triggeredBy == 'mobile' ||
            triggeredBy == 'wifi_to_mobile' ||
            triggeredBy == 'network_change' ||
            triggeredBy == 'hotspot';
        await ref
            .read(vpnProvider.notifier)
            .activateProfile(
              triggered,
              connectIfDisconnected: network != 'none',
              rotateServer: changeNetwork && triggered.serverKey == null,
            );
        _profileTimers.markTriggered(triggered.id, DateTime.now());
        return;
      }

      final due = _profileTimers.nextDue(
        enabledProfiles,
        connected: ref.read(vpnProvider).status == VpnState.connected,
        now: DateTime.now(),
      );
      if (due != null) {
        await ref
            .read(vpnProvider.notifier)
            .activateProfile(due, rotateServer: due.serverKey == null);
      }
    } catch (error) {
      // Keep automatic profile checks quiet when the platform cannot report a network.
    } finally {
      _isEvaluatingProfile = false;
    }
  }

  Future<void> _refreshAutoPing() async {
    if (_isAutoPingRunning ||
        ref.read(vpnProvider).status != VpnState.connected) {
      return;
    }

    ProxyConfig? target;
    for (final chain in ref.read(chainsProvider)) {
      if (chain.isActive && chain.nodes.isNotEmpty) {
        target = chain.nodes.first;
        break;
      }
    }
    if (target == null) {
      for (final subscription in ref.read(subscriptionProvider)) {
        for (final server in subscription.servers) {
          if (server.isActive) {
            target = server;
            break;
          }
        }
        if (target != null) break;
      }
    }
    final selection = ref.read(mapSelectionProvider);
    final chainActive = ref
        .read(chainsProvider)
        .any((c) => c.isActive && c.nodes.isNotEmpty);
    if (!chainActive &&
        selection != null &&
        selection.appliesTo(target?.uniqueKey))
      target = selection.server;
    if (target == null || target.isPinging) return;

    _isAutoPingRunning = true;
    final ping = PingUtils.pingServerEx(
      target,
      ref.read(settingsProvider),
      timeout: const Duration(seconds: 4),
    );
    if (mounted) setState(() {});
    try {
      await ping;
    } catch (_) {
      // PingUtils stores a failure on the target when a probe fails.
    } finally {
      _isAutoPingRunning = false;
      if (mounted) {
        ref.read(subscriptionProvider.notifier).refreshState();
        setState(() {});
      }
    }
  }

  Future<void> _refreshCoreMemory() async {
    if (!Platform.isAndroid || _isReadingCoreMemory) return;
    final vpnStatus = ref.read(vpnProvider).status;
    if (vpnStatus == VpnState.disconnected) {
      if ((_coreMemoryMb != null ||
              _coreMemoryUnavailable ||
              _coreMemoryName != null) &&
          mounted) {
        setState(() {
          _coreMemoryMb = null;
          _coreMemoryName = null;
          _coreMemoryUnavailable = false;
        });
      }
      return;
    }
    if (vpnStatus != VpnState.connected) return;

    _isReadingCoreMemory = true;
    try {
      final result = await _vpnChannel.invokeMapMethod<String, dynamic>(
        'getCoreMemory',
      );
      final memoryMb = (result?['memoryMb'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        final core = result?['core'];
        final coreName = core == null
            ? _coreMemoryName
            : core == 'SINGBOX'
            ? 'Sing-box'
            : 'Xray';
        if (_coreMemoryName != null &&
            coreName != null &&
            _coreMemoryName != coreName) {
          _coreMemoryMb = null;
        }
        _coreMemoryName = coreName;
        if (memoryMb != null) _coreMemoryMb = memoryMb;
        _coreMemoryUnavailable = memoryMb == null;
      });
    } on PlatformException {
      if (mounted && ref.read(vpnProvider).status == VpnState.connected) {
        setState(() => _coreMemoryUnavailable = true);
      }
    } finally {
      _isReadingCoreMemory = false;
    }
  }

  Widget _buildHomeSystemMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String flagCountryCode = '',
    String? location,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: location ?? value,
        child: ThemeRegion.auto(
          id: "widget_main_0",
          label: "Row · main.dart",
          child: Row(
            children: [
              ThemeRegion.auto(
                id: "widget_main_1",
                label: "Icon · main.dart",
                child: flagCountryCode.isEmpty
                    ? Icon(icon, size: 18, color: color)
                    : CountryFlagImage(
                        countryCode: flagCountryCode,
                        height: 18,
                      ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: ThemeRegion.auto(
                  id: "widget_main_2",
                  label: "Column · main.dart",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemeRegion.auto(
                        id: "widget_main_3",
                        label: "Text · main.dart",
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ThemeRegion.auto(
                          id: "widget_main_4",
                          label: "Text · main.dart",
                          child: Text(
                            value,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runThemeAction(Map<String, dynamic> element) async {
    final Widget? screen = switch (element['action']) {
      'servers' => const SubscriptionsScreen(),
      'settings' => const SettingsScreen(),
      'rules' => const RulesScreen(),
      'profiles' => const ProfilesScreen(),
      'apps' => const AppsScreen(),
      _ => null,
    };
    if (screen != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      return;
    }
    if ([
      'toggle',
      'connect',
      'disconnect',
      'reconnect',
    ].contains(element['action'])) {
      try {
        final notifier = ref.read(vpnProvider.notifier);
        final connected = ref.read(vpnProvider).status != VpnState.disconnected;
        final action = element['action'];
        if (action == 'toggle' ||
            action == 'connect' && !connected ||
            action == 'disconnect' && connected)
          await notifier.toggle();
        if (action == 'reconnect') {
          if (connected) await notifier.toggle();
          await notifier.toggle();
        }
      } catch (error) {
        if (mounted) CustomNotification.show(context, '$error', isError: true);
      }
    } else if (element['action'] == 'copy') {
      await Clipboard.setData(
        ClipboardData(text: element['value']?.toString() ?? ''),
      );
      if (mounted)
        CustomNotification.show(
          context,
          AppLocalizations.text(context, "Скопировано"),
        );
    } else if (element['action'] == 'url') {
      final url = Uri.tryParse(element['url']?.toString() ?? '');
      if (url != null &&
          ['https', 'http', 'tg', 'nextlink'].contains(url.scheme)) {
        try {
          await _vpnChannel.invokeMethod('openExternalUrl', url.toString());
        } catch (error) {
          if (mounted)
            CustomNotification.show(
              context,
              AppLocalizations.text(
                context,
                "Не удалось открыть ссылку: {0}",
                args: [error],
              ),
              isError: true,
            );
        }
      }
    }
  }

  List<Widget> _buildHeaderActions(
    ThemeConfig theme, {
    required bool isDownloading,
    required bool isBatteryOptimized,
  }) {
    const known = [
      'home_subscriptions_button',
      'home_rules_button',
      'home_apps_button',
      'home_settings_button',
    ];
    final order = <String>[
      ...theme.componentOrder.where(known.contains),
      ...known.where((id) => !theme.componentOrder.contains(id)),
    ];
    final actions = <Widget>[];
    for (final id in order) {
      if (theme.hiddenElements.contains(id)) continue;
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 6));
      final child = switch (id) {
        // The tour highlights these controls in place, so they carry explicit
        // anchors: the auto-generated widget ids are shared by several buttons.
        'home_subscriptions_button' => TourAnchor(
          id: 'home_subscriptions_button',
          child: _buildTopIconBtn(
            icon: Icons.subscriptions_outlined,
            theme: theme,
            componentId: id,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SubscriptionsScreen()),
            ),
          ),
        ),
        'home_rules_button' => TourAnchor(
          id: 'home_rules_button',
          child: _buildTopIconBtn(
            icon: Icons.route_rounded,
            theme: theme,
            componentId: id,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RulesScreen()),
            ),
          ),
        ),
        'home_apps_button' => TourAnchor(
          id: 'home_apps_button',
          child: _buildTopIconBtn(
            icon: Icons.apps_rounded,
            theme: theme,
            componentId: id,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppsScreen()),
            ),
          ),
        ),
        'home_settings_button' => TourAnchor(
          id: 'home_settings_button',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: ThemeRegion.auto(
              id: "widget_main_5",
              label: "Stack · main.dart",
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ThemeRegion.auto(
                    id: "widget_main_6",
                    label: "Container · main.dart",
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.surface.withOpacity(.5),
                        borderRadius: BorderRadius.circular(
                          theme.radiusFor(id),
                        ),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ThemeRegion.auto(
                        id: "widget_main_7",
                        label: "Icon · main.dart",
                        child: Icon(
                          Icons.settings_rounded,
                          color: theme.colorFor(id),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  if (isDownloading || isBatteryOptimized)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: ThemeRegion.auto(
                        id: "widget_main_8",
                        label: "Container · main.dart",
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: theme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: ThemeRegion.auto(
                            id: "widget_main_9",
                            label: "Icon · main.dart",
                            child: Icon(
                              isDownloading
                                  ? Icons.downloading_rounded
                                  : Icons.priority_high_rounded,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _ => const SizedBox.shrink(),
      };
      actions.add(
        SizedBox(
          width: 40,
          height: 44,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ThemeRegion(
              id: id,
              label: AppLocalizations.text(
                context,
                ThemeRegionRegistry.labelFor(id),
              ),
              child: ThemePressEffect(
                componentId: id,
                style: theme.componentAnimations[id] ?? 'soft',
                enabled: theme.animationsEnabled,
                durationMs: theme.pressDurationMs,
                child: child,
              ),
            ),
          ),
        ),
      );
    }
    return actions;
  }

  Future<void> _checkAndShowBatteryDialog() async {
    if (Platform.isAndroid) {
      await ref.read(batteryStatusProvider.notifier).checkStatus();
      final isOptimized = !ref.read(batteryStatusProvider);
      final alreadyShown = ref.read(batteryWarningShownProvider);

      if (isOptimized && !alreadyShown) {
        _showBatteryOptimizationDialog();
      }
    }
  }

  void _showBatteryOptimizationDialog() {
    final theme = ref.read(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    ref.read(batteryWarningShownProvider.notifier).state = true;
    HapticFeedback.heavyImpact();

    showDialog(
      useRootNavigator: false,
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ThemeRegion.auto(
            id: "widget_main_10",
            label: "Container · main.dart",
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: theme.surface.withOpacity(0.8),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: ThemeRegion.auto(
                id: "widget_main_11",
                label: "Column · main.dart",
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemeRegion.auto(
                      id: "widget_main_12",
                      label: "Container · main.dart",
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: ThemeRegion.auto(
                          id: "widget_main_13",
                          label: "Icon · main.dart",
                          child: Icon(
                            Icons.battery_alert_rounded,
                            color: theme.primary,
                            size: 32,
                          ),
                        ),
                      ),
                    ).animate().scale(
                      delay: 200.ms,
                      duration: 400.ms,
                      curve: Curves.easeOutBack,
                    ),
                    const SizedBox(height: 24),
                    ThemeRegion.auto(
                      id: "widget_main_14",
                      label: "Text · main.dart",
                      child: Text(
                        loc.translate('background_work'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ).animate().fade(delay: 300.ms).slideY(begin: 0.2),
                    const SizedBox(height: 12),
                    ThemeRegion.auto(
                      id: "widget_main_15",
                      label: "Text · main.dart",
                      child: Text(
                        loc.translate('battery_optimization_desc'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textDim,
                          height: 1.5,
                        ),
                      ),
                    ).animate().fade(delay: 400.ms).slideY(begin: 0.2),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        if (Platform.isAndroid) {
                          ref
                              .read(batteryStatusProvider.notifier)
                              .openSettings();
                        }
                      },
                      child: ThemeRegion.auto(
                        id: "widget_main_16",
                        label: "Container · main.dart",
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [theme.primary, theme.primaryDark],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: theme.primary.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Center(
                            child: ThemeRegion.auto(
                              id: "widget_main_17",
                              label: "Text · main.dart",
                              child: Text(
                                loc.translate('go_to_settings'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ).animate().fade(delay: 500.ms).slideY(begin: 0.2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coreStatus = ref.watch(coreManagerProvider);
    final vpnState = ref.watch(vpnProvider);
    ref.listen(vpnProvider, (previous, next) {
      if (previous?.status != next.status) _refreshHomeIp();
    });
    final ipInfo = ref.watch(ipInfoProvider);
    final liveThemeData = <String, String>{
      'vpn': AppLocalizations.of(context)!.translate(
        vpnState.status == VpnState.connected ? 'connected' : 'disconnected',
      ),
      'timer': vpnState.formattedTime,
      'traffic': vpnState.formattedTraffic,
      'ip': ipInfo.ip,
      'flag': countryFlag(ipInfo.countryCode),
      'country': ipInfo.countryCode,
      'location': ipInfo.displayLocation,
      'server': vpnState.serviceServerName ?? '—',
      'ping': vpnState.ping,
    };
    if (jsonEncode(ThemeActionRegistry.data.value) != jsonEncode(liveThemeData))
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ThemeActionRegistry.data.value = liveThemeData;
      });

    final theme = ref.watch(themeProvider).currentTheme;
    final isBatteryOptimized = !ref.watch(batteryStatusProvider);
    final loc = AppLocalizations.of(context)!;

    final isConnected = vpnState.status == VpnState.connected;
    final isConnecting =
        vpnState.status == VpnState.connecting || vpnState.isSwitching;
    final isBackgroundActive = isConnected || isConnecting;

    final subscriptions = ref.watch(subscriptionProvider);
    final chains = ref.watch(chainsProvider);
    final noConfiguredServers =
        subscriptions.every((subscription) => subscription.servers.isEmpty) &&
        chains.isEmpty;

    final showGlobe =
        ref.watch(settingsProvider.select((s) => s.showServerGlobe)) &&
        !theme.hiddenElements.contains('home_server_globe');
    if (!showGlobe) _buildingMapChain = false;

    // Определяем активную цепочку
    ProxyChain? activeChain;
    for (final c in chains) {
      if (c.isActive && c.nodes.isNotEmpty) {
        activeChain = c;
        break;
      }
    }
    final bool isChainMode = activeChain != null;

    // Определяем активный сервер и подписку
    ProxyConfig? activeServer;
    for (var sub in subscriptions) {
      for (var srv in sub.servers) {
        if (srv.isActive) {
          activeServer = srv;
          break;
        }
      }
      if (activeServer != null) break;
    }

    final mapSelection = ref.watch(mapSelectionProvider);
    if (mapSelection != null && mapSelection.appliesTo(activeServer?.uniqueKey))
      activeServer = mapSelection.server;

    final ProxyConfig? pingTargetServer = isChainMode
        ? activeChain.nodes.first
        : activeServer;
    final pingText = (pingTargetServer?.isPinging ?? false)
        ? '...'
        : (pingTargetServer != null && pingTargetServer.ping > 0
              ? '${pingTargetServer.ping} ms'
              : '');
    final String mainDisplayTitle =
        vpnState.status != VpnState.disconnected &&
            vpnState.serviceServerName != null
        ? vpnState.serviceServerName!
        : isChainMode
        ? activeChain.name
        : (activeServer?.name ??
              (noConfiguredServers
                  ? loc.translate('no_subscriptions_title')
                  : loc.translate('select_server')));

    String statusText = loc.translate('disconnected');
    Color statusColor = theme.textDim;
    if (vpnState.status == VpnState.paused) {
      statusText = 'Пауза';
    } else if (isConnecting) {
      statusText = loc.translate('connecting');
      statusColor = Colors.orangeAccent;
    } else if (isConnected) {
      statusText = loc.translate('connected');
      statusColor = theme.colorFor('home_status');
    }

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion.auto(
        id: "widget_main_18",
        label: "Stack · main.dart",
        child: Stack(
          children: [
            AnimatedMeshBackground(isConnected: isBackgroundActive),
            if (showGlobe)
              Positioned.fill(
                child: ThemeElement(
                  theme: theme,
                  id: 'home_server_globe',
                  child: ServerGlobe(
                    fullScreen: true,
                    connected: isConnected && !isConnecting,
                    connectedServerKey: vpnState.serviceServerKey,
                    onDisconnect: () =>
                        ref.read(vpnProvider.notifier).disconnect(),
                    currentLocation: ipInfo.details,
                    onEditingChanged: (editing) {
                      if (mounted) setState(() => _buildingMapChain = editing);
                    },
                    onConnectChain: (chain) =>
                        ref.read(vpnProvider.notifier).connectToChain(chain),
                    onConnect: (server, sourceKey) async {
                      try {
                        await ref
                            .read(vpnProvider.notifier)
                            .connectToServer(server, sourceKey: sourceKey);
                      } catch (e) {
                        if (context.mounted)
                          CustomNotification.show(context, '$e', isError: true);
                      }
                    },
                  ),
                ),
              ),

            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: ThemeRegion.auto(
                      id: "widget_main_19",
                      label: "Column · main.dart",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 8),

                          // === HEADER ===
                          AdaptiveHomeHeader(
                            title: GestureDetector(
                              onTap: () {
                                if (theme.hiddenElements.contains(
                                  'home_profiles_button',
                                ))
                                  return;
                                HapticFeedback.lightImpact();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProfilesScreen(),
                                  ),
                                );
                              },
                              child: ThemePressEffect(
                                componentId: 'home_profiles_button',
                                style:
                                    theme
                                        .componentAnimations['home_profiles_button'] ??
                                    'soft',
                                enabled:
                                    theme.animationsEnabled &&
                                    !theme.hiddenElements.contains(
                                      'home_profiles_button',
                                    ),
                                durationMs: theme.pressDurationMs,
                                child: ThemeElement(
                                  theme: theme,
                                  id: 'home_profiles_button',
                                  child: ThemeRegion.auto(
                                    id: "widget_main_20",
                                    label: "Row · main.dart",
                                    child: Row(
                                      children: [
                                        if (!theme.hiddenElements.contains(
                                          'home_app_title',
                                        ))
                                          ThemeElement(
                                            theme: theme,
                                            id: 'home_app_title',
                                            child: ShaderMask(
                                              shaderCallback: (bounds) =>
                                                  LinearGradient(
                                                    colors:
                                                        theme.gradientTitle &&
                                                            theme.useGradients
                                                        ? [
                                                            theme.colorFor(
                                                              'home_app_title',
                                                            ),
                                                            theme.primaryDark,
                                                          ]
                                                        : [
                                                            theme.text,
                                                            theme.text,
                                                          ],
                                                  ).createShader(bounds),
                                              child: ThemeRegion.auto(
                                                id: "widget_main_21",
                                                label: "Text · main.dart",
                                                child: Text(
                                                  loc.translate('app_name'),
                                                  style: const TextStyle(
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -0.5,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        const SizedBox(width: 8),
                                        if (!theme.hiddenElements.contains(
                                          'home_profiles_button',
                                        ))
                                          ThemeRegion.auto(
                                            id: "widget_main_22",
                                            label: "Container · main.dart",
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: theme.surface
                                                    .withOpacity(0.6),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      theme.radiusFor(
                                                        'home_profiles_button',
                                                      ),
                                                    ),
                                                border: Border.all(
                                                  color: Colors.white10,
                                                ),
                                              ),
                                              child: ThemeRegion.auto(
                                                id: "widget_main_23",
                                                label: "Icon · main.dart",
                                                child: Icon(
                                                  Icons.expand_more_rounded,
                                                  color: theme.colorFor(
                                                    'home_profiles_button',
                                                  ),
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            actions: ThemeRegion.auto(
                              id: "widget_main_24",
                              label: "Row · main.dart",
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ..._buildHeaderActions(
                                    theme,
                                    isDownloading: coreStatus.isDownloadingAny,
                                    isBatteryOptimized:
                                        Platform.isAndroid &&
                                        isBatteryOptimized,
                                  ),
                                ],
                              ),
                            ),
                          ).animate().fade(duration: 400.ms).slideY(begin: -0.2),

                          if (_buildingMapChain) const Spacer(),
                          if (!_buildingMapChain) ...[
                            Spacer(flex: showGlobe ? 9 : 2),

                            // === СТАТУС-БАР НАД КНОПКОЙ ===
                            if (!theme.hiddenElements.contains('home_status'))
                              ThemeElement(
                                theme: theme,
                                id: 'home_status',
                                child: ThemeRegion.auto(
                                  id: "widget_main_25",
                                  label: "Container · main.dart",
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isBackgroundActive
                                          ? theme
                                                .colorFor('home_status')
                                                .withOpacity(0.15)
                                          : theme.surface.withOpacity(
                                              theme.glassOpacity,
                                            ),
                                      borderRadius: BorderRadius.circular(
                                        theme.radiusFor('home_status'),
                                      ),
                                      border: Border.all(
                                        color: isBackgroundActive
                                            ? theme
                                                  .colorFor('home_status')
                                                  .withOpacity(0.4)
                                            : Colors.white10,
                                      ),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_main_26",
                                      label: "Row · main.dart",
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ThemeRegion.auto(
                                            id: "widget_main_27",
                                            label: "Container · main.dart",
                                            child: Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: statusColor,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: statusColor
                                                        .withOpacity(0.8),
                                                    blurRadius: 8,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          ThemeRegion.auto(
                                            id: "widget_main_28",
                                            label: "Text · main.dart",
                                            child: Text(
                                              statusText.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.0,
                                                color: statusColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ).animate().fade().slideY(begin: 0.2),

                            SizedBox(height: showGlobe ? 12 : 32),

                            // === ОГРОМНАЯ КНОПКА POWER ===
                            if (!theme.hiddenElements.contains(
                              'home_power_button',
                            ))
                              ThemeElement(
                                theme: theme,
                                id: 'home_power_button',
                                child: GestureDetector(
                                  onTap: () async {
                                    HapticFeedback.mediumImpact();
                                    if (noConfiguredServers) {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const SubscriptionsScreen(),
                                        ),
                                      );
                                      return;
                                    }
                                    try {
                                      if (!context.mounted) return;
                                      await ref
                                          .read(vpnProvider.notifier)
                                          .toggle();
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      CustomNotification.show(
                                        context,
                                        loc.translate(
                                          e.toString().replaceFirst(
                                            'Exception: ',
                                            '',
                                          ),
                                        ),
                                        isError: true,
                                      );
                                    }
                                  },
                                  child: ThemePressEffect(
                                    componentId: 'home_power_button',
                                    style:
                                        theme
                                            .componentAnimations['home_power_button'] ??
                                        'soft',
                                    enabled: theme.animationsEnabled,
                                    durationMs: theme.pressDurationMs,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      width: noConfiguredServers ? 88.0 : (showGlobe
                                          ? theme.powerButtonSize.clamp(
                                              104.0,
                                              132.0,
                                            )
                                          : theme.powerButtonSize),
                                      height: noConfiguredServers ? 88.0 : (showGlobe
                                          ? theme.powerButtonSize.clamp(
                                              104.0,
                                              132.0,
                                            )
                                          : theme.powerButtonSize),
                                      decoration: BoxDecoration(
                                        shape:
                                            theme.componentRadii.containsKey(
                                                  'home_power_button',
                                                ) &&
                                                theme.radiusFor(
                                                      'home_power_button',
                                                    ) <
                                                    36
                                            ? BoxShape.rectangle
                                            : BoxShape.circle,
                                        borderRadius:
                                            theme.componentRadii.containsKey(
                                                  'home_power_button',
                                                ) &&
                                                theme.radiusFor(
                                                      'home_power_button',
                                                    ) <
                                                    36
                                            ? BorderRadius.circular(
                                                theme.radiusFor(
                                                  'home_power_button',
                                                ),
                                              )
                                            : null,
                                        color: isBackgroundActive
                                            ? theme.colorFor(
                                                'home_power_button',
                                              )
                                            : theme.surface.withOpacity(
                                                theme.glassOpacity,
                                              ),
                                        border: Border.all(
                                          color: isBackgroundActive
                                              ? theme.colorFor(
                                                  'home_power_button',
                                                )
                                              : Colors.white.withOpacity(0.05),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          if (isBackgroundActive)
                                            BoxShadow(
                                              color: theme
                                                  .colorFor('home_power_button')
                                                  .withOpacity(0.5),
                                              blurRadius: 70,
                                              spreadRadius: 15,
                                              offset: const Offset(0, 10),
                                            )
                                          else
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.3,
                                              ),
                                              blurRadius: 30,
                                              spreadRadius: 5,
                                              offset: const Offset(0, 10),
                                            ),
                                        ],
                                      ),
                                      child: ThemeRegion.auto(
                                        id: "widget_main_29",
                                        label: "Column · main.dart",
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Builder(
                                              builder: (context) {
                                                Widget icon = ThemeRegion.auto(
                                                  id: "widget_main_30",
                                                  label: "Icon · main.dart",
                                                  child: Icon(
                                                    Icons
                                                        .power_settings_new_rounded,
                                                    size: noConfiguredServers ? 34 : (showGlobe ? 40 : 64),
                                                    color: isBackgroundActive
                                                        ? Colors.white
                                                        : theme.textDim
                                                              .withOpacity(0.7),
                                                  ),
                                                );

                                                if (isConnecting) {
                                                  return icon
                                                      .animate(
                                                        onPlay: (c) => c.repeat(
                                                          reverse: true,
                                                        ),
                                                      )
                                                      .fade(
                                                        begin: 1.0,
                                                        end: 0.5,
                                                        duration: 600.ms,
                                                      )
                                                      .scale(
                                                        begin: const Offset(
                                                          1,
                                                          1,
                                                        ),
                                                        end: const Offset(
                                                          0.9,
                                                          0.9,
                                                        ),
                                                      );
                                                }
                                                return icon;
                                              },
                                            ),
                                            if (isBackgroundActive) ...[
                                              if (theme.isBuiltIn) ...[
                                                const SizedBox(height: 14),
                                                ThemeRegion.auto(
                                                  id: "widget_main_31",
                                                  label: "Text · main.dart",
                                                  child: Text(
                                                    vpnState.isSwitching
                                                        ? vpnState
                                                              .formattedOldTime
                                                        : vpnState
                                                              .formattedTime,
                                                    style: TextStyle(
                                                      fontSize: 21,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                      letterSpacing: 1.2,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ).animate().fade(
                                                  duration: 300.ms,
                                                ),
                                              ] else ...[
                                                const SizedBox(height: 9),
                                                ThemeRegion.auto(
                                                  id: "widget_main_32",
                                                  label:
                                                      "Container · main.dart",
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 5,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: theme.background
                                                          .withOpacity(.86),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      border: Border.all(
                                                        color: theme
                                                            .colorFor(
                                                              'home_power_button',
                                                            )
                                                            .withOpacity(.78),
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withOpacity(.5),
                                                          blurRadius: 12,
                                                        ),
                                                      ],
                                                    ),
                                                    child: ThemeRegion.auto(
                                                      id: "widget_main_33",
                                                      label: "Text · main.dart",
                                                      child: Text(
                                                        vpnState.isSwitching
                                                            ? vpnState
                                                                  .formattedOldTime
                                                            : vpnState
                                                                  .formattedTime,
                                                        style: TextStyle(
                                                          fontSize: 21,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontFeatures: const [
                                                            FontFeature.tabularFigures(),
                                                          ],
                                                          letterSpacing: 1.2,
                                                          color: theme.text,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ).animate().fade(
                                                  duration: 300.ms,
                                                ),
                                              ],
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            SizedBox(height: showGlobe ? 12 : 40),

                            // === НАЗВАНИЕ АКТИВНОГО УЗЛА / ЦЕПОЧКИ И СТАТИСТИКА ===
                            if (vpnState.isSwitching) ...[
                              ThemeRegion.auto(
                                    id: "widget_main_34",
                                    label: "Text · main.dart",
                                    child: Text(
                                      vpnState.targetServerName ?? "",
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .animate(
                                    onPlay: (c) => c.repeat(reverse: true),
                                  )
                                  .fade(begin: 0.4, end: 1.0, duration: 800.ms),
                            ] else ...[
                              ThemeRegion.auto(
                                id: "widget_main_35",
                                label: "Row · main.dart",
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isChainMode) ...[
                                      ThemeRegion.auto(
                                        id: "widget_main_36",
                                        label: "Icon · main.dart",
                                        child: Icon(
                                          Icons.hub_rounded,
                                          size: 22,
                                          color: theme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: ThemeRegion.auto(
                                        id: "widget_main_37",
                                        label: "Text · main.dart",
                                        child: Text(
                                          mainDisplayTitle,
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            ThemeRegion.auto(
                              id: "widget_main_38",
                              label: "Row · main.dart",
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!theme.hiddenElements.contains(
                                    'home_traffic',
                                  ))
                                    ThemePressEffect(
                                      componentId: 'home_traffic',
                                      style:
                                          theme
                                              .componentAnimations['home_traffic'] ??
                                          'soft',
                                      enabled: theme.animationsEnabled,
                                      durationMs: theme.pressDurationMs,
                                      child: GestureDetector(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const StatisticsScreen(),
                                            ),
                                          );
                                        },
                                        child: ThemeElement(
                                          theme: theme,
                                          id: 'home_traffic',
                                          child: ThemeRegion.auto(
                                            id: "widget_main_39",
                                            label: "Container · main.dart",
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: theme.surface
                                                    .withOpacity(
                                                      theme.glassOpacity,
                                                    ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      theme.radiusFor(
                                                        'home_traffic',
                                                      ),
                                                    ),
                                                border: Border.all(
                                                  color: Colors.white10,
                                                ),
                                              ),
                                              child: ThemeRegion.auto(
                                                id: "widget_main_40",
                                                label: "Row · main.dart",
                                                child: Row(
                                                  children: [
                                                    ThemeRegion.auto(
                                                      id: "widget_main_41",
                                                      label: "Icon · main.dart",
                                                      child: Icon(
                                                        Icons
                                                            .arrow_downward_rounded,
                                                        size: 16,
                                                        color: const Color(
                                                          0xFF55E6A4,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    ThemeRegion.auto(
                                                      id: "widget_main_42",
                                                      label: "Text · main.dart",
                                                      child: Text(
                                                        vpnState
                                                            .formattedTraffic,
                                                        style: TextStyle(
                                                          color: theme.text,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!theme.hiddenElements.contains(
                                        'home_traffic',
                                      ) &&
                                      !theme.hiddenElements.contains(
                                        'home_ping',
                                      ))
                                    const SizedBox(width: 12),
                                  if (!theme.hiddenElements.contains(
                                    'home_ping',
                                  ))
                                    ThemePressEffect(
                                      componentId: 'home_ping',
                                      style:
                                          theme
                                              .componentAnimations['home_ping'] ??
                                          'soft',
                                      enabled: theme.animationsEnabled,
                                      durationMs: theme.pressDurationMs,
                                      child: GestureDetector(
                                        onTap: () async {
                                          HapticFeedback.lightImpact();
                                          if (pingTargetServer != null) {
                                            final settings = ref.read(
                                              settingsProvider,
                                            );
                                            final res =
                                                await PingUtils.pingServerEx(
                                                  pingTargetServer,
                                                  settings,
                                                );
                                            ref
                                                .read(
                                                  subscriptionProvider.notifier,
                                                )
                                                .refreshState();
                                            if (res.isSuccess) {
                                              ref
                                                  .read(vpnProvider.notifier)
                                                  .updatePingDisplay(
                                                    '${res.latencyMs} ms',
                                                  );
                                            } else if (res.error != null &&
                                                context.mounted) {
                                              CustomNotification.show(
                                                context,
                                                res.error!,
                                                isError: true,
                                              );
                                            }
                                          }
                                        },
                                        child: ThemeElement(
                                          theme: theme,
                                          id: 'home_ping',
                                          child: ThemeRegion.auto(
                                            id: "widget_main_43",
                                            label: "Container · main.dart",
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: theme.surface
                                                    .withOpacity(
                                                      theme.glassOpacity,
                                                    ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      theme.radiusFor(
                                                        'home_ping',
                                                      ),
                                                    ),
                                                border: Border.all(
                                                  color: Colors.white10,
                                                ),
                                              ),
                                              child: ThemeRegion.auto(
                                                id: "widget_main_44",
                                                label: "Row · main.dart",
                                                child: Row(
                                                  children: [
                                                    ThemeRegion.auto(
                                                      id: "widget_main_45",
                                                      label: "Icon · main.dart",
                                                      child: Icon(
                                                        Icons.speed_rounded,
                                                        size: 16,
                                                        color: theme.colorFor(
                                                          'home_ping',
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    if (pingText.isNotEmpty)
                                                      ThemeRegion.auto(
                                                        id: "widget_main_46",
                                                        label:
                                                            "Text · main.dart",
                                                        child: Text(
                                                          pingText,
                                                          style: TextStyle(
                                                            color: theme.text,
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            if (!theme.hiddenElements.contains(
                              'home_system_info',
                            )) ...[
                              const SizedBox(height: 12),
                              ThemeElement(
                                theme: theme,
                                id: 'home_system_info',
                                child: ThemeRegion.auto(
                                  id: "widget_main_47",
                                  label: "Container · main.dart",
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorFor('home_system_info')
                                          .withOpacity(
                                            showGlobe ? 0.035 : 0.12,
                                          ),
                                      borderRadius: BorderRadius.circular(
                                        theme.radiusFor('home_system_info'),
                                      ),
                                      border: Border.all(
                                        color: theme
                                            .colorFor('home_system_info')
                                            .withOpacity(0.4),
                                      ),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_main_48",
                                      label: "Row · main.dart",
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TourAnchor(
                                              id: 'home_ip_details',
                                              child: _buildHomeSystemMetric(
                                                onTap: () =>
                                                    showIpLocationDetails(
                                                      context,
                                                      ipInfo.details ??
                                                          IpLocation(
                                                            ip:
                                                                ipInfo.ip ==
                                                                    '---'
                                                                ? ''
                                                                : ipInfo.ip,
                                                          ),
                                                    ),
                                                icon: Icons.public_rounded,
                                                flagCountryCode:
                                                    ipInfo.countryCode,
                                                location:
                                                    ipInfo.displayLocation,
                                                label: loc.translate(
                                                  'ip_address',
                                                ),
                                                value: ipInfo.ip == '---'
                                                    ? (ipInfo.isLoading
                                                          ? '…'
                                                          : '---')
                                                    : ipInfo.ip,
                                                color: theme.colorFor(
                                                  'home_system_info',
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_coreMemoryMb != null ||
                                              _coreMemoryUnavailable) ...[
                                            ThemeRegion.auto(
                                              id: "widget_main_49",
                                              label: "Container · main.dart",
                                              child: Container(
                                                width: 1,
                                                height: 32,
                                                color: theme
                                                    .colorFor(
                                                      'home_system_info',
                                                    )
                                                    .withOpacity(0.3),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                    ),
                                              ),
                                            ),
                                            Expanded(
                                              child: _buildHomeSystemMetric(
                                                icon: Icons.memory_rounded,
                                                label:
                                                    '${_coreMemoryName ?? loc.translate('core_memory')} RSS',
                                                value: _coreMemoryMb == null
                                                    ? loc.translate(
                                                        'memory_unavailable',
                                                      )
                                                    : '${_coreMemoryMb!.toStringAsFixed(1)} MB',
                                                color: theme.colorFor(
                                                  'home_system_info',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * .15,
                              ),
                              child: SingleChildScrollView(
                                child: CustomThemeElements(
                                  theme: theme,
                                  onAction: _runThemeAction,
                                  variables: {
                                    'vpn': isConnected
                                        ? loc.translate('connected')
                                        : loc.translate('disconnected'),
                                    'timer': vpnState.formattedTime,
                                    'traffic': vpnState.formattedTraffic,
                                    'ip': ipInfo.ip,
                                    'flag': countryFlag(ipInfo.countryCode),
                                    'country': ipInfo.countryCode,
                                    'location': ipInfo.displayLocation,
                                    'server': vpnState.serviceServerName ?? '—',
                                    'ping': vpnState.ping,
                                  },
                                ),
                              ),
                            ),

                            if (!showGlobe) const Spacer(flex: 2),

                            // === СТАРАЯ ПЛАШКА ИЗ ПЕРВОЙ ВЕРСИИ ===
                            if ((noConfiguredServers ||
                                    !ref.watch(
                                      settingsProvider.select(
                                        (s) => s.showServerGlobe,
                                      ),
                                    )) &&
                                !theme.hiddenElements.contains(
                                  'home_server_card',
                                ))
                              ThemePressEffect(
                                componentId: 'home_server_card',
                                style:
                                    theme
                                        .componentAnimations['home_server_card'] ??
                                    'soft',
                                enabled: theme.animationsEnabled,
                                durationMs: theme.pressDurationMs,
                                child: ThemeElement(
                                  theme: theme,
                                  id: 'home_server_card',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      theme.radiusFor('home_server_card'),
                                    ),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 20,
                                        sigmaY: 20,
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: isChainMode
                                              ? theme.primary.withOpacity(0.12)
                                              : theme.surface.withOpacity(
                                                  theme.glassOpacity,
                                                ),
                                          gradient: theme.useGradients
                                              ? LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    theme
                                                        .colorFor(
                                                          'home_server_card',
                                                        )
                                                        .withOpacity(
                                                          isChainMode
                                                              ? 0.16
                                                              : 0.08,
                                                        ),
                                                    theme.surface.withOpacity(
                                                      0.36,
                                                    ),
                                                  ],
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            theme.radiusFor('home_server_card'),
                                          ),
                                          border: Border.all(
                                            color: isChainMode
                                                ? theme
                                                      .colorFor(
                                                        'home_server_card',
                                                      )
                                                      .withOpacity(0.4)
                                                : Colors.white.withOpacity(
                                                    0.08,
                                                  ),
                                            width: isChainMode ? 1.5 : 1,
                                          ),
                                        ),
                                        child: noConfiguredServers
                                            ? _buildNoSubscriptionsCard(
                                                theme,
                                                loc,
                                              )
                                            : ThemeRegion.auto(
                                                id: "widget_main_50",
                                                label: "Column · main.dart",
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    // MODE HEADER BADGE
                                                    ThemeRegion.auto(
                                                      id: "widget_main_51",
                                                      label: "Row · main.dart",
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          ThemeRegion.auto(
                                                            id: "widget_main_52",
                                                            label: "Container · main.dart",
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical: 4,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    isChainMode
                                                                    ? theme
                                                                          .primary
                                                                          .withOpacity(
                                                                            0.2,
                                                                          )
                                                                    : Colors
                                                                          .blueAccent
                                                                          .withOpacity(
                                                                            0.15,
                                                                          ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                              child: ThemeRegion.auto(
                                                                id: "widget_main_53",
                                                                label: "Row · main.dart",
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    ThemeRegion.auto(
                                                                      id: "widget_main_54",
                                                                      label: "Icon · main.dart",
                                                                      child: Icon(
                                                                        isChainMode
                                                                            ? Icons.link_rounded
                                                                            : Icons.dns_rounded,
                                                                        size:
                                                                            13,
                                                                        color:
                                                                            isChainMode
                                                                            ? theme.primary
                                                                            : Colors.blueAccent,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 6,
                                                                    ),
                                                                    ThemeRegion.auto(
                                                                      id: "widget_main_55",
                                                                      label: "Text · main.dart",
                                                                      child: Text(
                                                                        isChainMode
                                                                            ? loc.translate(
                                                                                'chain_mode',
                                                                              )
                                                                            : loc.translate(
                                                                                'single_server_mode',
                                                                              ),
                                                                        style: TextStyle(
                                                                          color:
                                                                              isChainMode
                                                                              ? theme.primary
                                                                              : Colors.blueAccent,
                                                                          fontSize:
                                                                              11,
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                          letterSpacing:
                                                                              0.8,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          ThemeRegion.auto(
                                                            id: "widget_main_56",
                                                            label: "Icon · main.dart",
                                                            child: Icon(
                                                              isChainMode
                                                                  ? Icons
                                                                        .verified_rounded
                                                                  : Icons
                                                                        .check_circle_outline_rounded,
                                                              size: 16,
                                                              color: isChainMode
                                                                  ? theme
                                                                        .primary
                                                                  : theme
                                                                        .textDim,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),

                                                    if (isChainMode) ...[
                                                      ThemeRegion.auto(
                                                        id: "widget_main_57",
                                                        label:
                                                            "Text · main.dart",
                                                        child: Text(
                                                          activeChain.name,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      ThemeRegion.auto(
                                                        id: "widget_main_58",
                                                        label:
                                                            "Text · main.dart",
                                                        child: Text(
                                                          activeChain.nodes
                                                                  .map(
                                                                    (n) =>
                                                                        n.name,
                                                                  )
                                                                  .join(' ➔ ') +
                                                              AppLocalizations.text(
                                                                context,
                                                                " ➔ Интернет",
                                                              ),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                theme.primary,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      ThemeRegion.auto(
                                                        id: "widget_main_59",
                                                        label:
                                                            "Row · main.dart",
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: GestureDetector(
                                                                onTap: () {
                                                                  HapticFeedback.lightImpact();
                                                                  Navigator.push(
                                                                    context,
                                                                    MaterialPageRoute(
                                                                      builder: (
                                                                        _,
                                                                      ) => const ChainsScreen(),
                                                                    ),
                                                                  );
                                                                },
                                                                child: ThemeRegion.auto(
                                                                  id: "widget_main_60",
                                                                  label: "Container · main.dart",
                                                                  child: Container(
                                                                    padding:
                                                                        const EdgeInsets.symmetric(
                                                                          vertical:
                                                                              8,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .white
                                                                          .withOpacity(
                                                                            0.06,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                      border: Border.all(
                                                                        color: Colors
                                                                            .white10,
                                                                      ),
                                                                    ),
                                                                    child: Center(
                                                                      child: ThemeRegion.auto(
                                                                        id: "widget_main_61",
                                                                        label: "Text · main.dart",
                                                                        child: Text(
                                                                          loc.translate(
                                                                            'change_chain',
                                                                          ),
                                                                          style: const TextStyle(
                                                                            fontSize:
                                                                                12,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                            color:
                                                                                Colors.white,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              child: GestureDetector(
                                                                onTap: () {
                                                                  HapticFeedback.lightImpact();
                                                                  ref
                                                                      .read(
                                                                        chainsProvider
                                                                            .notifier,
                                                                      )
                                                                      .setActiveChain(
                                                                        null,
                                                                      );
                                                                },
                                                                child: ThemeRegion.auto(
                                                                  id: "widget_main_62",
                                                                  label: "Container · main.dart",
                                                                  child: Container(
                                                                    padding:
                                                                        const EdgeInsets.symmetric(
                                                                          vertical:
                                                                              8,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: theme
                                                                          .primary
                                                                          .withOpacity(
                                                                            0.15,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                      border: Border.all(
                                                                        color: theme
                                                                            .primary
                                                                            .withOpacity(
                                                                              0.3,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    child: Center(
                                                                      child: ThemeRegion.auto(
                                                                        id: "widget_main_63",
                                                                        label: "Text · main.dart",
                                                                        child: Text(
                                                                          loc.translate(
                                                                            'disable_chain',
                                                                          ),
                                                                          style: TextStyle(
                                                                            fontSize:
                                                                                12,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                            color:
                                                                                theme.primary,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ] else ...[
                                                      ThemeRegion.auto(
                                                        id: "widget_main_64",
                                                        label:
                                                            "Text · main.dart",
                                                        child: Text(
                                                          activeServer?.name ??
                                                              loc.translate(
                                                                'select_server',
                                                              ),
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                activeServer !=
                                                                    null
                                                                ? Colors.white
                                                                : theme.textDim,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      ThemeRegion.auto(
                                                        id: "widget_main_65",
                                                        label:
                                                            "Text · main.dart",
                                                        child: Text(
                                                          loc.translate(
                                                            'direct_connection_desc',
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                theme.textDim,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      ThemeRegion.auto(
                                                        id: "widget_main_66",
                                                        label:
                                                            "Row · main.dart",
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: GestureDetector(
                                                                onTap: () {
                                                                  HapticFeedback.lightImpact();
                                                                  Navigator.push(
                                                                    context,
                                                                    MaterialPageRoute(
                                                                      builder: (
                                                                        _,
                                                                      ) => const SubscriptionsScreen(),
                                                                    ),
                                                                  );
                                                                },
                                                                child: ThemeRegion.auto(
                                                                  id: "widget_main_67",
                                                                  label: "Container · main.dart",
                                                                  child: Container(
                                                                    padding:
                                                                        const EdgeInsets.symmetric(
                                                                          vertical:
                                                                              8,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .white
                                                                          .withOpacity(
                                                                            0.06,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                      border: Border.all(
                                                                        color: Colors
                                                                            .white10,
                                                                      ),
                                                                    ),
                                                                    child: Center(
                                                                      child: ThemeRegion.auto(
                                                                        id: "widget_main_68",
                                                                        label: "Text · main.dart",
                                                                        child: Text(
                                                                          loc.translate(
                                                                            'change_server',
                                                                          ),
                                                                          style: const TextStyle(
                                                                            fontSize:
                                                                                12,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                            color:
                                                                                Colors.white,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              child: GestureDetector(
                                                                onTap: () {
                                                                  HapticFeedback.lightImpact();
                                                                  if (chains
                                                                      .isNotEmpty) {
                                                                    ref
                                                                        .read(
                                                                          chainsProvider
                                                                              .notifier,
                                                                        )
                                                                        .setActiveChain(
                                                                          chains
                                                                              .first
                                                                              .id,
                                                                        );
                                                                  } else {
                                                                    Navigator.push(
                                                                      context,
                                                                      MaterialPageRoute(
                                                                        builder: (
                                                                          _,
                                                                        ) => const ChainsScreen(),
                                                                      ),
                                                                    );
                                                                  }
                                                                },
                                                                child: ThemeRegion.auto(
                                                                  id: "widget_main_69",
                                                                  label: "Container · main.dart",
                                                                  child: Container(
                                                                    padding:
                                                                        const EdgeInsets.symmetric(
                                                                          vertical:
                                                                              8,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: theme
                                                                          .primary
                                                                          .withOpacity(
                                                                            0.12,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                      border: Border.all(
                                                                        color: theme
                                                                            .primary
                                                                            .withOpacity(
                                                                              0.25,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    child: Center(
                                                                      child: ThemeRegion.auto(
                                                                        id: "widget_main_70",
                                                                        label: "Text · main.dart",
                                                                        child: Text(
                                                                          loc.translate(
                                                                            'enable_chain',
                                                                          ),
                                                                          style: TextStyle(
                                                                            fontSize:
                                                                                12,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                            color:
                                                                                theme.primary,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ).animate().fade(duration: 500.ms, delay: 200.ms).slideY(begin: 0.1),
                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSubscriptionsCard(dynamic theme, AppLocalizations loc) {
    return ThemeRegion.auto(
      id: "widget_main_71",
      label: "Column · main.dart",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ThemeRegion.auto(
            id: "widget_main_72",
            label: "Icon · main.dart",
            child: Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: theme.primary,
            ),
          ),
          const SizedBox(height: 10),
          ThemeRegion.auto(
            id: "widget_main_73",
            label: "Text · main.dart",
            child: Text(
              loc.translate('no_subscriptions_home'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          ThemeRegion.auto(
            id: "widget_main_74",
            label: "TextButton · main.dart",
            child: TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionsScreen(),
                  ),
                );
              },
              style: TextButton.styleFrom(foregroundColor: theme.primary),
              child: ThemeRegion.auto(
                id: "widget_main_76",
                label: "Text · main.dart",
                child: Text(loc.translate('add_your_subscription')),
              ),
            ),
          ),
          ThemeRegion.auto(
            id: "widget_main_77",
            label: "Wrap · main.dart",
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ThemeRegion.auto(
                  id: "widget_main_78",
                  label: "Text · main.dart",
                  child: Text(
                    '${loc.translate('or_try')} ',
                    style: TextStyle(color: theme.textDim, fontSize: 13),
                  ),
                ),
                ThemeRegion.auto(
                  id: "widget_main_79",
                  label: "TextButton · main.dart",
                  child: TextButton(
                    onPressed: () async {
                      try {
                        await _vpnChannel.invokeMethod('openExternalUrl', {
                          'url': 'https://t.me/vpnka_official_bot?start=utm_nextlink',
                        });
                      } catch (error) {
                        if (mounted) {
                          CustomNotification.show(
                            context,
                            '${loc.translate('error')}: $error',
                            isError: true,
                          );
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: theme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: ThemeRegion.auto(
                      id: "widget_main_81",
                      label: "Text · main.dart",
                      child: const Text('VPN-KA'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopIconBtn({
    required IconData icon,
    required dynamic theme,
    required VoidCallback onTap,
    String componentId = 'home_rules_button',
  }) {
    return Tooltip(
      message: AppLocalizations.text(
        context,
        ThemeRegionRegistry.labelFor(componentId),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: ThemeRegion.auto(
          id: "widget_main_82",
          label: "Container · main.dart",
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.surface.withOpacity(theme.glassOpacity),
              borderRadius: BorderRadius.circular(theme.radiusFor(componentId)),
              border: Border.all(color: Colors.white10),
            ),
            child: ThemeRegion.auto(
              id: "widget_main_83",
              label: "Icon · main.dart",
              child: Icon(icon, color: theme.colorFor(componentId), size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
