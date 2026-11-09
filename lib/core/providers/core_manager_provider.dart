import '../localization/app_localizations.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/wg_release.dart';
import '../utils/core_update_checker.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'logger_provider.dart';
import 'settings_provider.dart';

enum CoreType { xray, singbox, rules, awg }

class CoreItemStatus {
  final bool isDownloaded;
  final String version;
  final bool isDownloading;
  final double downloadProgress;
  final int downloadedBytes;
  final int totalBytes;
  final bool hasUpdate;
  final bool isPaused;
  final String? lastError;

  CoreItemStatus({
    this.isDownloaded = false,
    this.version = 'N/A',
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.hasUpdate = false,
    this.isPaused = false,
    this.lastError,
  });

  String get formattedProgress {
    if (totalBytes <= 0) return "0.0 МБ / 0.0 МБ";
    final downloaded = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
    final total = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    return "$downloaded МБ / $total МБ";
  }

  CoreItemStatus copyWith({
    bool? isDownloaded,
    String? version,
    bool? isDownloading,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
    bool? hasUpdate,
    bool? isPaused,
    String? lastError,
    bool clearError = false,
  }) {
    return CoreItemStatus(
      isDownloaded: isDownloaded ?? this.isDownloaded,
      version: version ?? this.version,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      isPaused: isPaused ?? this.isPaused,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class CoreStatus {
  final CoreItemStatus xray;
  final CoreItemStatus singbox;
  final CoreItemStatus rules;
  final CoreItemStatus awg;
  final bool isCheckingUpdates;

  CoreStatus({
    CoreItemStatus? xray,
    CoreItemStatus? singbox,
    CoreItemStatus? rules,
    CoreItemStatus? awg,
    this.isCheckingUpdates = false,
  }) : xray = xray ?? CoreItemStatus(),
       singbox = singbox ?? CoreItemStatus(),
       rules = rules ?? CoreItemStatus(),
       awg = awg ?? CoreItemStatus();

  CoreStatus copyWith({
    CoreItemStatus? xray,
    CoreItemStatus? singbox,
    CoreItemStatus? rules,
    CoreItemStatus? awg,
    bool? isCheckingUpdates,
  }) {
    return CoreStatus(
      xray: xray ?? this.xray,
      singbox: singbox ?? this.singbox,
      rules: rules ?? this.rules,
      awg: awg ?? this.awg,
      isCheckingUpdates: isCheckingUpdates ?? this.isCheckingUpdates,
    );
  }

  bool get isReady =>
      xray.isDownloaded && singbox.isDownloaded && rules.isDownloaded;
  bool get isDownloadingAny =>
      xray.isDownloading ||
      singbox.isDownloading ||
      rules.isDownloading ||
      awg.isDownloading;
  bool isCoreAvailable(String core) => core.toUpperCase() == 'SINGBOX'
      ? singbox.isDownloaded
      : xray.isDownloaded;
}

class CoreManagerNotifier extends StateNotifier<CoreStatus> {
  final Ref ref;
  final Map<CoreType, Map<String, dynamic>> _lastTransfers = {};
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<CoreType, Completer<void>> _resumeSignals = {};
  final Set<CoreType> _notificationFailures = {};
  final Map<CoreType, Future<void>> _notificationUpdates = {};

  Future<void> _waitIfPaused(CoreType type) async {
    final signal = _resumeSignals[type];
    if (signal != null) await signal.future;
  }

  Future<String> _readXrayVersion(String path) async {
    if (!Platform.isLinux) return 'Custom';

    for (final args in [
      ['version'],
      ['--version'],
    ]) {
      try {
        final result = await Process.run(
          path,
          args,
        ).timeout(const Duration(seconds: 5));

        if (result.exitCode != 0) continue;

        final output = '${result.stdout}\n${result.stderr}';
        final match = RegExp(
          r'Xray\s+v?(\d+(?:\.\d+)+)',
          caseSensitive: false,
        ).firstMatch(output);

        if (match != null) {
          return '${match.group(1)} (Custom)';
        }
      } catch (_) {
        // Try the next command.
      }
    }

    return 'Custom';
  }

  Future<void> _onNotificationResponse(NotificationResponse response) async {
    final action = response.actionId;
    final id = response.id;
    if (id == null ||
        (action != 'pause_download' && action != 'resume_download')) {
      return;
    }
    final type = CoreType.values.firstWhere(
      (candidate) => candidate.index == id,
      orElse: () => CoreType.rules,
    );
    if (!_getItemStatus(type).isDownloading) return;
    if (action == 'pause_download') {
      if (_resumeSignals.containsKey(type)) return;
      _resumeSignals[type] = Completer<void>();
    } else {
      _resumeSignals.remove(type)?.complete();
    }
    final status = _getItemStatus(type)
        .copyWith(isPaused: action == 'pause_download');
    _updateItemStatus(type, status);
    await _showNotification(type, status);
  }

  Future<void> resumeDownload(CoreType type) async {
    _resumeSignals.remove(type)?.complete();
    final status = _getItemStatus(type).copyWith(isPaused: false);
    _updateItemStatus(type, status);
    await _showNotification(type, status);
  }

  CoreManagerNotifier(this.ref) : super(CoreStatus()) {
    print("CoreManager: Constructor called");
    ready = _init();
  }

  late final Future<void> ready;

  Future<void> _init() async {
    print("CoreManager: _init() starting...");

    await ref.read(settingsProvider.notifier).ready;

    // Initialize notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification_nl');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    if (Platform.isAndroid) {
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    if (Platform.isAndroid) {
      // A previous process cannot continue a Dart download. Remove its stale UI.
      for (final type in CoreType.values) {
        await _showNotification(type, _getItemStatus(type));
      }
    }
    // Offline shadow preload; original flavor has no bundled assets.
    if (Platform.isAndroid) {
      try {
        final files = await const MethodChannel('pro.kaleert.nextlink/preload')
            .invokeListMethod<String>('installBundledResources');
        if (files != null && files.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          for (final (name, key) in [
            ('libxray.so', 'xray_version'),
            ('libsingbox.so', 'singbox_version'),
            ('libawg.so', 'awg_version'),
          ]) {
            if (files.contains(name) && prefs.getString(key) == null) {
              await prefs.setString(key, 'Bundled');
            }
          }
          if (files.contains('geoip.dat') && files.contains('geosite.dat') &&
              prefs.getString('rules_version') == null) {
            await prefs.setString('rules_version', 'Bundled');
          }
        }
      } catch (error) {
        debugPrint('Shadow preload skipped: $error');
      }
    }
    if (Platform.isLinux) {
      // Linux shadow archive stores seeds beside the executable in data/preload/.
      final bundle = File(Platform.resolvedExecutable).parent.path;
      final preload = Directory('$bundle/data/preload');
      if (await preload.exists()) {
        final support = await getApplicationSupportDirectory();
        final prefs = await SharedPreferences.getInstance();
        for (final (name, key) in [
          ('xray', 'xray_version'),
          ('sing-box', 'singbox_version'),
          ('amnezia-box', 'awg_version'),
          ('geoip.dat', 'rules_version'),
          ('geosite.dat', 'rules_version'),
        ]) {
          final source = File('${preload.path}/$name');
          final dest = File('${support.path}/$name');
          if (!await source.exists() || await source.length() <= 1024 ||
              (await dest.exists() && await dest.length() > 1024)) continue;
          final temporary = File('${dest.path}.seed-tmp');
          try {
            await source.copy(temporary.path);
            await temporary.rename(dest.path);
            if (!name.endsWith('.dat')) {
              await Process.run('chmod', ['+x', dest.path]);
            }
            if (prefs.getString(key) == null) {
              await prefs.setString(key, 'Bundled');
            }
          } finally {
            if (await temporary.exists()) await temporary.delete();
          }
        }
      }
    }
    await _checkStatus();

    final settings = ref.read(settingsProvider);

    if (settings.autoUpdateCores) {
      print("CoreManager: Automatically downloading missing resources...");
      unawaited(_downloadMissingResources());
    }
    if (settings.autoInstallCoreUpdates) unawaited(_installAutomaticUpdates());
  }

  Future<void> _installAutomaticUpdates() async {
    await checkForUpdates();
    for (final type in CoreType.values) {
      if (!ref.read(settingsProvider).autoInstallCoreUpdates) return;
      if (!_getItemStatus(type).isDownloaded || !_getItemStatus(type).hasUpdate)
        continue;
      if (Platform.isAndroid) {
        try {
          if (await const MethodChannel('pro.kaleert.nextlink/vpn')
                  .invokeMethod<bool>('isRunning') !=
              false)
            return;
        } catch (_) {
          return;
        }
      } else {
        return;
      }
      await downloadItem(type);
    }
  }

  /// Preload missing VPN components without blocking the UI.
  Future<void> preloadMissingResources() async {
    try {
      await ready;
      await _downloadMissingResources();
    } catch (e) {
      debugPrint('Core preload failed: $e');
    }
  }

  Future<void> _downloadMissingResources() async {
    final missing = <CoreType>[
      if (!state.xray.isDownloaded) CoreType.xray,
      if (!state.singbox.isDownloaded) CoreType.singbox,
      if (!state.rules.isDownloaded) CoreType.rules,
      if (!state.awg.isDownloaded) CoreType.awg,
    ];
    if (missing.isEmpty) return;
    await Future.wait(missing.map(downloadItem));
  }

  Future<void> _checkStatus() async {
    final appDir = await getApplicationSupportDirectory();
    final isAndroid = !kIsWeb && Platform.isAndroid;

    final xrayName = isAndroid ? 'libxray.so' : 'xray';
    final singboxName = isAndroid ? 'libsingbox.so' : 'sing-box';

    final xrayFile = File('${appDir.path}/$xrayName');
    final singboxFile = File('${appDir.path}/$singboxName');
    final geoipFile = File('${appDir.path}/geoip.dat');
    final geositeFile = File('${appDir.path}/geosite.dat');

    final prefs = await SharedPreferences.getInstance();

    Future<bool> isCoreFileValid(File file) async {
      if (!await file.exists() || await file.length() <= 1000) return false;
      if (!isAndroid) return true;
      final handle = await file.open();
      try {
        final header = await handle.read(4);
        return header.length == 4 &&
            header[0] == 0x7f &&
            header[1] == 0x45 &&
            header[2] == 0x4c &&
            header[3] == 0x46;
      } finally {
        await handle.close();
      }
    }

    state = state.copyWith(
      awg: state.awg.copyWith(
        isDownloaded: await isCoreFileValid(
          File('${appDir.path}/${isAndroid ? 'libawg.so' : 'amnezia-box'}'),
        ),
        version: prefs.getString('awg_version') ?? 'N/A',
      ),
      xray: state.xray.copyWith(
        isDownloaded: await isCoreFileValid(xrayFile),
        version: prefs.getString('xray_version') ?? 'N/A',
      ),
      singbox: state.singbox.copyWith(
        isDownloaded: await isCoreFileValid(singboxFile),
        version: prefs.getString('singbox_version') ?? 'N/A',
      ),
      rules: state.rules.copyWith(
        isDownloaded:
            await geoipFile.exists() &&
            await geositeFile.exists() &&
            await geoipFile.length() > 0 &&
            await geositeFile.length() > 0,
        version: prefs.getString('rules_version') ?? 'N/A',
      ),
    );
  }

  Future<void> downloadAll() async {
    try {
      await Future.wait([
        downloadItem(CoreType.xray),
        downloadItem(CoreType.singbox),
        downloadItem(CoreType.rules),
        downloadItem(CoreType.awg),
      ]);
    } catch (e) {
      print("CoreManager: downloadAll failed: $e");
    }
  }

  final Map<CoreType, Future<void>> _activeDownloads = {};

  Future<void> downloadItem(CoreType type, {bool force = false}) async {
    if (_activeDownloads.containsKey(type)) return _activeDownloads[type];

    final current = _getItemStatus(type);
    if (current.isDownloaded && !force && !current.hasUpdate) return;

    final downloadFuture = _doDownloadItem(type, force: force);
    _activeDownloads[type] = downloadFuture;

    try {
      await downloadFuture;
    } finally {
      _activeDownloads.remove(type);
    }
  }

  Future<void> _doDownloadItem(CoreType type, {bool force = false}) async {
    CoreItemStatus current = _getItemStatus(type);
    if (current.isDownloading && !force) return;
    _resumeSignals.remove(type)?.complete();

    _updateItemStatus(
      type,
      current.copyWith(
        isDownloading: true,
        isPaused: false,
        downloadProgress: 0.0,
        downloadedBytes: 0,
        totalBytes: 0,
        clearError: true,
      ),
    );
    var completed = false;

    try {
      final appDir = await getApplicationSupportDirectory();
      final isAndroid = Platform.isAndroid;
      final arch = _getArchitecture();
      final settings = ref.read(settingsProvider);
      final prefs = await SharedPreferences.getInstance();

      Map<String, String>? info;
      String customUrl = '';
      RemoteCoreRelease? serverRelease;

      switch (type) {
        case CoreType.xray:
          customUrl = settings.xrayUrl.trim();

          if (customUrl.isEmpty) {
            info = await _getLatestReleaseInfo(
              'XTLS/Xray-core',
              [isAndroid ? 'android' : 'linux', arch],
              ['.zip'],
            );
          }

          break;
        case CoreType.singbox:
          serverRelease = await _resolveServerRelease(
            type,
            settings.singboxUrl,
            arch,
          );
          info = {
            'url': serverRelease.url.toString(),
            'version': serverRelease.version ?? 'Server',
          };
          break;
        case CoreType.awg:
          serverRelease = await _resolveServerRelease(
            type,
            settings.awgUrl,
            arch,
          );
          final bytes = await _downloadWithProgress(
            serverRelease.url.toString(),
            type,
          );
          _verifyServerArtifact(bytes, serverRelease);
          WgRelease.validateBinary(bytes, arch);
          final name = isAndroid ? 'libawg.so' : 'amnezia-box';
          await _saveBinary(bytes, appDir.path, name);
          await _rememberInstallation(
            type,
            File('${appDir.path}/$name'),
            prefs,
          );
          final hash = _lastTransfers[type]!['remoteHash'] as String;
          await prefs.setString(
            'awg_version',
            serverRelease.version ?? 'SHA-256 ${hash.substring(0, 8)}',
          );
          await _checkStatus();
          completed = true;
          _updateItemStatus(
            type,
            _getItemStatus(type).copyWith(
              isDownloading: false,
              downloadProgress: 1,
              hasUpdate: false,
            ),
          );
          await _showNotification(type, _getItemStatus(type));
          return;
        case CoreType.rules:
          customUrl = settings.rulesUrl;
          info = {
            'version': 'Latest',
            'url': 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
          }; // Dummy for rules
          break;
      }

      final url = customUrl.isNotEmpty ? customUrl : info?['url'];
      final version = info?['version'] ?? 'Custom';

      if (url == null || url.isEmpty) {
        throw StateError(
          'Xray: не удалось подобрать релиз для архитектуры $arch',
        );
      }

      if (type == CoreType.rules) {
        const githubBase =
            'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/';
        const cdnBase =
            'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/';

        Future<List<int>> fetchRule(String name) async {
          final configured = settings.rulesUrl.trim();
          if (configured.isNotEmpty) {
            final custom = name == 'geoip.dat'
                ? configured
                : configured.replaceAll('geoip.dat', 'geosite.dat');
            // Do not silently replace a user-configured source.
            return _downloadWithProgress(custom, CoreType.rules);
          }

          Object? primaryError;
          try {
            final bytes = await _downloadWithProgress(
              '$cdnBase$name',
              CoreType.rules,
            );
            if (bytes.length < 1024) {
              throw const FormatException('Rules file is unexpectedly small');
            }
            return bytes;
          } catch (error) {
            primaryError = error;
            AppLogger.log(
              ref,
              'DOWNLOAD',
              'jsDelivr rules download failed ($name): $error. Trying GitHub.',
            );
          }

          try {
            final bytes = await _downloadWithProgress(
              '$githubBase$name',
              CoreType.rules,
            );
            if (bytes.length < 1024) {
              throw const FormatException('Rules file is unexpectedly small');
            }
            return bytes;
          } catch (fallbackError) {
            throw Exception(
              'Cannot download $name. GitHub: $primaryError; '
              'jsDelivr: $fallbackError',
            );
          }
        }

        AppLogger.log(ref, 'UI', 'Скачивание правил...');
        // Download both before replacing any installed rule file.
        final geoipBytes = await fetchRule('geoip.dat');
        final geositeBytes = await fetchRule('geosite.dat');
        await _saveBinary(geoipBytes, appDir.path, 'geoip.dat');
        await _saveBinary(geositeBytes, appDir.path, 'geosite.dat');
        await prefs.setString('rules_version', version);
      } else {
        String targetName = '';
        String tag = '';
        switch (type) {
          case CoreType.xray:
            targetName = isAndroid ? 'libxray.so' : 'xray';
            tag = 'xray';
            break;
          case CoreType.singbox:
            targetName = isAndroid ? 'libsingbox.so' : 'sing-box';
            tag = 'sing-box';
            break;
          default:
            break;
        }

        await _downloadAndExtract(
          url,
          targetName,
          appDir.path,
          tag,
          type,
          release: serverRelease,
          fallbackAssetUrl:
              type == CoreType.xray && customUrl.isEmpty && info != null
              ? info['assetApiUrl']
              : null,
        );
        if (type == CoreType.singbox) {
          await _rememberInstallation(
            type,
            File('${appDir.path}/$targetName'),
            prefs,
          );
        }
        final installedVersion = type == CoreType.xray && customUrl.isNotEmpty
            ? await _readXrayVersion('${appDir.path}/$targetName')
            : type == CoreType.singbox && serverRelease?.version == null
            ? 'SHA-256 ${(_lastTransfers[type]!['remoteHash'] as String).substring(0, 8)}'
            : version;
        await prefs.setString(
          '${tag.replaceAll("-", "")}_version',
          installedVersion,
        );
      }

      await _checkStatus();
      completed = true;
      _updateItemStatus(
        type,
        _getItemStatus(type).copyWith(
          isDownloading: false,
          isPaused: false,
          downloadProgress: 1.0,
          hasUpdate: false,
          clearError: true,
        ),
      );
      await _showNotification(type, _getItemStatus(type));
      AppLogger.log(
        ref,
        'UI',
        '${type.name.toUpperCase()} updated successfully',
      );
    } catch (e) {
      print("CoreManager: Download error for ${type.name}: $e");
      AppLogger.log(ref, 'UI', 'Error downloading ${type.name}: $e');
      final failed = _getItemStatus(type).copyWith(
        isDownloading: false,
        isPaused: false,
        lastError: e.toString(),
      );
      _updateItemStatus(type, failed);
      await _showNotification(type, failed);
    } finally {
      _resumeSignals.remove(type)?.complete();
      if (!completed) {
        final status = _getItemStatus(type);
        _updateItemStatus(
          type,
          status.copyWith(isDownloading: false, isPaused: false),
        );
      }
    }
  }

  CoreItemStatus _getItemStatus(CoreType type) {
    switch (type) {
      case CoreType.xray:
        return state.xray;
      case CoreType.singbox:
        return state.singbox;
      case CoreType.awg:
        return state.awg;
      case CoreType.rules:
        return state.rules;
    }
  }

  void _updateItemStatus(CoreType type, CoreItemStatus status) {
    switch (type) {
      case CoreType.xray:
        state = state.copyWith(xray: status);
        break;
      case CoreType.singbox:
        state = state.copyWith(singbox: status);
        break;
      case CoreType.awg:
        state = state.copyWith(awg: status);
        break;
      case CoreType.rules:
        state = state.copyWith(rules: status);
        break;
    }
  }

  Future<Map<String, String>?> _getLatestReleaseInfo(
    String repo,
    List<String> mustContain,
    List<String> preferredExtensions,
  ) async {
    int retry = 0;
    while (retry < 3) {
      try {
        // Log DNS resolution attempt
        try {
          final addresses = await InternetAddress.lookup('api.github.com');
          print(
            "DNS Lookup api.github.com: ${addresses.map((a) => a.address).join(', ')}",
          );
        } catch (e) {
          print("DNS Lookup api.github.com FAILED: $e");
        }

        final response = await http
            .get(
              Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
              headers: {'User-Agent': 'NextLink-App'},
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) {
          print("GitHub API Error ($repo): ${response.statusCode}");

          if (const [502, 503, 504].contains(response.statusCode)) {
            retry++;
            if (retry < 3) {
              await Future.delayed(Duration(seconds: retry * 2));
              continue;
            }
          }

          return null;
        }

        final data = json.decode(response.body);
        final version = data['tag_name'] as String;
        final assets = data['assets'] as List;

        // Xray: exact asset selection, as verified by the download test.
        if (repo == 'XTLS/Xray-core') {
          final platform = mustContain.first.toLowerCase();
          final arch = mustContain.last.toLowerCase();

          final suffix = switch (arch) {
            'arm64-v8a' || 'arm64' || 'aarch64' => 'arm64-v8a',
            'x86_64' ||
            'amd64' ||
            'x64' => platform == 'linux' ? '64' : 'amd64',
            'x86' || 'i386' || 'i686' => '32',
            'armeabi-v7a' || 'armv7' || 'arm32' => 'arm32-v7a',
            _ => arch,
          };

          final expected = 'xray-$platform-$suffix.zip'.toLowerCase();

          final matches = assets
              .where(
                (asset) => (asset['name'] as String).toLowerCase() == expected,
              )
              .toList();

          if (matches.isEmpty) {
            throw StateError(
              'Xray asset not found: $expected; '
              'available: ${assets.map((a) => a['name']).join(', ')}',
            );
          }

          final asset = matches.single;
          return {
            'url': asset['browser_download_url'] as String,
            'assetApiUrl': asset['url'] as String,
            'version': version,
          };
        }

        final archVariants = _getArchVariants(mustContain);

        final isXray = repo == 'XTLS/Xray-core';
        final requestedArch = mustContain.last.toLowerCase();
        final requestedPlatform = mustContain.first.toLowerCase();

        final archAliases = switch (requestedArch) {
          'arm64-v8a' ||
          'aarch64' ||
          'arm64' => ['arm64-v8a', 'arm64', 'aarch64'],
          'x86_64' || 'amd64' || 'x64' => ['amd64', 'x86_64'],
          'armeabi-v7a' || 'armv7' => ['armeabi-v7a', 'armv7', 'arm-v7'],
          _ => [requestedArch],
        };

        var filtered = assets.where((a) {
          final name = (a['name'] as String).toLowerCase();

          if (isXray) {
            if (!name.endsWith('.zip')) return false;

            final platformMatches = requestedPlatform == 'android'
                ? name.startsWith('xray-android-')
                : name.startsWith('xray-linux-');

            if (!platformMatches) return false;

            return archAliases.any((alias) => name.endsWith('-$alias.zip'));
          }

          final matchesArch = archVariants.any(
            (v) => name.contains(v.toLowerCase()),
          );
          if (!matchesArch) return false;

          if (mustContain.contains('android')) {
            return name.contains('android') || name.contains('linux');
          }
          if (mustContain.contains('linux')) {
            return name.contains('linux');
          }
          return true;
        }).toList();

        if (repo == 'XTLS/Xray-core' &&
            mustContain.contains('android') &&
            filtered.isEmpty) {
          final arch = mustContain.last.toLowerCase();
          final expected = switch (arch) {
            'arm64-v8a' || 'arm64' || 'aarch64' => 'xray-android-arm64-v8a.zip',
            'x86_64' || 'amd64' => 'xray-android-amd64.zip',
            _ => '',
          };

          filtered = assets
              .where((a) => (a['name'] as String).toLowerCase() == expected)
              .toList();
        }

        if (filtered.isEmpty) {
          print(
            "GitHub API: No matching assets for $repo (arch: $archVariants)",
          );
          return null;
        }

        filtered.sort((a, b) {
          final nameA = (a['name'] as String).toLowerCase();
          final nameB = (b['name'] as String).toLowerCase();
          int scoreA = 0;
          int scoreB = 0;
          for (int i = 0; i < preferredExtensions.length; i++) {
            if (nameA.endsWith(preferredExtensions[i]))
              scoreA = preferredExtensions.length - i;
            if (nameB.endsWith(preferredExtensions[i]))
              scoreB = preferredExtensions.length - i;
          }
          return scoreB.compareTo(scoreA);
        });

        return {
          'url': filtered.first['browser_download_url'] as String,
          'assetApiUrl': filtered.first['url'] as String,
          'version': version,
        };
      } catch (e) {
        print("GitHub API Exception ($repo, attempt ${retry + 1}): $e");
        retry++;
        if (retry < 3) await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  List<String> _getArchVariants(List<String> mustContain) {
    List<String> variants = [];
    for (var part in mustContain) {
      if (part == 'android' || part == 'linux') continue;
      variants.add(part);
      if (part == 'arm64-v8a')
        variants.addAll(['arm64', 'aarch64']);
      else if (part == 'armeabi-v7a')
        variants.addAll(['armv7', 'arm-v7', 'armeabi']);
      else if (part == 'x86_64')
        variants.addAll(['amd64', 'x64']);
    }
    return variants;
  }

  String _getArchitecture() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) {
      try {
        final result = Process.runSync('getprop', ['ro.product.cpu.abi']);
        final abi = result.stdout.toString().trim();
        if (abi.isNotEmpty) return abi;
      } catch (_) {}
      return 'arm64-v8a';
    }
    return 'amd64';
  }

  Future<void> _downloadAndExtract(
    String url,
    String targetFileName,
    String targetDir,
    String coreTag,
    CoreType type, {
    RemoteCoreRelease? release,
    String? fallbackAssetUrl,
  }) async {
    late final List<int> bytes;

    if (type == CoreType.xray && fallbackAssetUrl != null) {
      // GitHub Assets API is preferred for Xray.
      try {
        final downloaded = await _downloadWithProgress(
          fallbackAssetUrl,
          type,
          headers: const {
            'Accept': 'application/octet-stream',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'NextLink-App',
          },
        );

        if (downloaded.length < 4 ||
            downloaded[0] != 0x50 ||
            downloaded[1] != 0x4b ||
            downloaded[2] != 0x03 ||
            downloaded[3] != 0x04) {
          throw const FormatException(
            'GitHub Assets API did not return a ZIP file',
          );
        }

        bytes = downloaded;
      } catch (apiError) {
        AppLogger.log(
          ref,
          'DOWNLOAD',
          'Xray Assets API failed: $apiError. Trying GitHub Releases.',
        );

        bytes = await _downloadWithProgress(url, type);

        if (bytes.length < 4 ||
            bytes[0] != 0x50 ||
            bytes[1] != 0x4b ||
            bytes[2] != 0x03 ||
            bytes[3] != 0x04) {
          throw const FormatException(
            'GitHub Releases did not return a ZIP file',
          );
        }
      }
    } else {
      // Custom URLs and other cores retain their existing download path.
      bytes = await _downloadWithProgress(url, type);
    }

    if (release != null) _verifyServerArtifact(bytes, release);

    Future<void> saveCore(List<int> payload) async {
      if (type == CoreType.singbox ||
          (Platform.isAndroid && type == CoreType.xray))
        WgRelease.validateBinary(
          payload,
          _getArchitecture(),
          coreName: type == CoreType.xray ? 'Xray' : 'Sing-box',
        );
      await _saveBinary(payload, targetDir, targetFileName);
    }

    final isZip = url.toLowerCase().contains('.zip');
    final isTarGz = url.toLowerCase().contains('.tar.gz');

    if (isZip) {
      final archive = ZipDecoder().decodeBytes(bytes);
      bool extracted = false;

      // First pass: try to find exact or semi-exact matches
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.split('/').last.toLowerCase();

        // Permissive matching: starts with tag or known core name and doesn't have an extension
        // or matches the tag exactly.
        bool isPossibleBinary =
            name == coreTag ||
            name == 'xray' ||
            name == 'sing-box' ||
            (name.startsWith(coreTag) && !name.contains('.'));

        if (isPossibleBinary) {
          await saveCore(file.content as List<int>);
          extracted = true;
          break;
        }
      }

      // Second pass: if not found, look for large files without extensions
      if (!extracted) {
        for (final file in archive) {
          if (!file.isFile) continue;
          final name = file.name.split('/').last.toLowerCase();
          if (!name.contains('.') && file.size > 1024 * 1024) {
            await saveCore(file.content as List<int>);
            extracted = true;
            break;
          }
        }
      }

      // Look for assets (.dat, .db)
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.split('/').last.toLowerCase();
        if (name.endsWith('.dat') || name.endsWith('.db')) {
          await _saveBinary(file.content as List<int>, targetDir, name);
        }
      }

      if (!extracted) throw Exception('No suitable binary found in ZIP');
    } else if (isTarGz) {
      final decompressed = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(decompressed);
      bool extracted = false;
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.split('/').last.toLowerCase();
        if (name == coreTag ||
            name == 'sing-box' ||
            (file.size > 1024 * 1024 && !name.contains('.'))) {
          await saveCore(file.content as List<int>);
          extracted = true;
          break;
        }
      }
      if (!extracted) throw Exception('No binary found in TAR.GZ');
    } else {
      await saveCore(bytes);
    }
  }

  Future<List<int>> _downloadWithProgress(
    String url,
    CoreType type, {
    Map<String, String> headers = const {},
  }) async {
    const maxRetries = 3;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      final client = http.Client();

      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll(headers);

        final bytes = await (() async {
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 20));

          if (response.statusCode != 200) {
            throw HttpException(
              'HTTP ${response.statusCode}',
              uri: Uri.parse(url),
            );
          }

          final expected = response.contentLength ?? 0;
          final builder = BytesBuilder(copy: false);
          var received = 0;
          var lastUpdate = 0;

          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 20),
          )) {
            await _waitIfPaused(type);

            builder.add(chunk);
            received += chunk.length;

            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastUpdate > 500 || received == expected) {
              lastUpdate = now;
              final status = _getItemStatus(type).copyWith(
                downloadProgress: expected > 0
                    ? (received / expected).clamp(0.0, 1.0)
                    : 0.0,
                downloadedBytes: received,
                totalBytes: expected,
              );
              _updateItemStatus(type, status);
              _showNotification(type, status);
            }
          }

          if (expected > 0 && received != expected) {
            throw FormatException(
              'Incomplete download: $received/$expected bytes',
            );
          }

          final result = builder.takeBytes();

          if (result.isEmpty) {
            throw const FormatException('Empty download');
          }

          if (type == CoreType.singbox || type == CoreType.awg) {
            _lastTransfers[type] = CoreUpdateChecker.transfer(
              Uri.parse(url),
              sha256.convert(result).toString(),
              response.headers,
              result.length,
            );
          }

          return result;
        })().timeout(const Duration(minutes: 3));

        return bytes;
      } catch (error) {
        final message = error.toString();

        AppLogger.log(
          ref,
          'DOWNLOAD',
          'Download attempt ${attempt + 1}/$maxRetries failed: $message',
        );

        // Let the caller try another source immediately.
        if (RegExp(r'HTTP (502|503|504)\b').hasMatch(message)) {
          rethrow;
        }

        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      } finally {
        client.close();
      }
    }

    throw StateError('Download failed');
  }

  Future<void> _showNotification(CoreType type, CoreItemStatus status) {
    // Serialize progress and cancellation so a pending show cannot resurrect it.
    final previous = _notificationUpdates[type] ?? Future<void>.value();
    final next = previous.then(
      (_) => _presentNotification(type, _getItemStatus(type)),
    );
    _notificationUpdates[type] = next;
    return next;
  }

  Future<void> _presentNotification(
    CoreType type,
    CoreItemStatus status,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final catalog = await AppLocalizations.uiCatalog(
      AppLocalizations.languageForSetting(ref.read(settingsProvider).language),
    );
    String text(String source, [List<Object?> args = const []]) =>
        AppLocalizations.format(catalog, source, args);
    final isPaused = status.isPaused;
    final isFailed = status.lastError != null;
    if (!status.isDownloading && !isFailed) {
      try {
        await _notifications.cancel(type.index);
        _notificationFailures.remove(type);
      } catch (error) {
        if (_notificationFailures.add(type)) {
          AppLogger.log(
            ref,
            'DOWNLOAD',
            'Unable to remove notification: $error',
          );
        }
      }
      return;
    }
    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'download_channel_id',
      text('Загрузки компонентов'),
      channelDescription: text(
        'Уведомления о прогрессе загрузки ядер и правил',
      ),
      importance: Importance.defaultImportance,
      priority: Priority.high,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: (status.downloadProgress * 100).toInt(),
      ongoing: status.isDownloading && !isFailed,
      icon: 'ic_notification_nl',
      groupKey: 'nextlink.downloads',
      actions: status.isDownloading && !isFailed
          ? [
              AndroidNotificationAction(
                isPaused ? 'resume_download' : 'pause_download',
                text(isPaused ? 'Продолжить' : 'Пауза'),
                cancelNotification: false,
              ),
            ]
          : const [],
    );

    final platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    try {
      await _notifications.show(
        type.index,
        isFailed
            ? text('Не удалось загрузить {0}', [type.name])
            : isPaused
            ? text('Загрузка {0} приостановлена', [type.name])
            : status.isDownloading
            ? text('Загрузка {0}', [type.name])
            : '${type.name}: загрузка завершена',
        isFailed ? status.lastError! : status.formattedProgress,
        platformChannelSpecifics,
      );
      _notificationFailures.remove(type);
    } catch (error) {
      if (_notificationFailures.add(type)) {
        AppLogger.log(ref, 'DOWNLOAD', 'Unable to update notification: $error');
      }
    }
  }

  Future<void> _saveBinary(
    List<int> content,
    String targetDir,
    String targetFileName,
  ) async {
    final outFile = File('$targetDir/$targetFileName');
    final temporary = File('${outFile.path}.download');
    await temporary.writeAsBytes(content, flush: true);
    await temporary.rename(outFile.path);
    if (Platform.isAndroid) {
      // On Android we usually don't need chmod if using linker, but good practice
    } else if (!kIsWeb) {
      await Process.run('chmod', ['+x', outFile.path]);
    }
  }

  Future<RemoteCoreRelease> _resolveServerRelease(
    CoreType type,
    String custom,
    String arch,
  ) async {
    final client = http.Client();
    try {
      return await CoreUpdateChecker(client)
          .resolve(core: type.name, custom: custom, architecture: arch);
    } finally {
      client.close();
    }
  }

  void _verifyServerArtifact(List<int> bytes, RemoteCoreRelease release) {
    if (release.size != null && bytes.length != release.size ||
        release.hash != null &&
            sha256.convert(bytes).toString() != release.hash)
      throw const FormatException(
        'Контрольная сумма или размер ядра не совпали с манифестом',
      );
  }

  Map<String, dynamic> _readMetadata(SharedPreferences prefs, String key) {
    try {
      final value = jsonDecode(prefs.getString(key) ?? '{}');
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _rememberInstallation(
    CoreType type,
    File file,
    SharedPreferences prefs,
  ) async {
    final transfer = _lastTransfers[type];
    if (transfer == null) return;
    final stat = await file.stat();
    final receipt = {
      ...transfer,
      'localHash': await CoreUpdateChecker.fileHash(file),
      'localSignature': CoreUpdateChecker.signature(stat),
    };
    await prefs.setString('${type.name}_release_receipt', jsonEncode(receipt));
    await prefs.setString('${type.name}_update_cache', jsonEncode(receipt));
  }

  Future<void> _checkServerUpdate(
    CoreType type,
    String custom,
    String arch,
    File file,
    SharedPreferences prefs,
  ) async {
    if (!_getItemStatus(type).isDownloaded ||
        _getItemStatus(type).isDownloading)
      return;
    final client = http.Client();
    try {
      final checker = CoreUpdateChecker(client);
      final release = await checker.resolve(
        core: type.name,
        custom: custom,
        architecture: arch,
      );
      final result = await checker.check(
        file,
        release,
        cache: _readMetadata(prefs, '${type.name}_update_cache'),
        receipt: _readMetadata(prefs, '${type.name}_release_receipt'),
      );
      final current = ref.read(settingsProvider);
      if (_getItemStatus(type).isDownloading ||
          (type == CoreType.singbox ? current.singboxUrl : current.awgUrl) !=
              custom)
        return;
      await prefs.setString(
        '${type.name}_update_cache',
        jsonEncode(result.cache),
      );
      _updateItemStatus(
        type,
        _getItemStatus(type).copyWith(hasUpdate: result.hasUpdate),
      );
    } catch (error) {
      AppLogger.log(ref, 'UPDATE', 'Не удалось проверить ${type.name}: $error');
    } finally {
      client.close();
    }
  }

  Future<void> checkForUpdates() async {
    if (state.isCheckingUpdates) return;
    state = state.copyWith(isCheckingUpdates: true);

    try {
      final arch = _getArchitecture();
      final prefs = await SharedPreferences.getInstance();
      final settings = ref.read(settingsProvider);

      final installedXrayVersion = prefs.getString('xray_version');
      Map<String, String>? xrayInfo;
      if (state.xray.isDownloaded &&
          settings.xrayUrl.isEmpty &&
          installedXrayVersion != null &&
          installedXrayVersion.trim().isNotEmpty &&
          installedXrayVersion != 'N/A' &&
          installedXrayVersion != 'Custom') {
        try {
          xrayInfo = await _getLatestReleaseInfo(
            'XTLS/Xray-core',
            ['android', arch],
            ['.zip'],
          );
        } catch (_) {
          /* The other core servers are independent. */
        }
      }

      if (xrayInfo != null)
        state = state.copyWith(
          xray: state.xray.copyWith(
            hasUpdate:
                _normalizeVersion(installedXrayVersion!) !=
                _normalizeVersion(xrayInfo['version'] ?? ''),
          ),
        );
      final appDir = await getApplicationSupportDirectory();
      await Future.wait([
        _checkServerUpdate(
          CoreType.singbox,
          settings.singboxUrl,
          arch,
          File(
            '${appDir.path}/${Platform.isAndroid ? 'libsingbox.so' : 'sing-box'}',
          ),
          prefs,
        ),
        _checkServerUpdate(
          CoreType.awg,
          settings.awgUrl,
          arch,
          File(
            '${appDir.path}/${Platform.isAndroid ? 'libawg.so' : 'amnezia-box'}',
          ),
          prefs,
        ),
      ]);
    } catch (_) {
    } finally {
      state = state.copyWith(isCheckingUpdates: false);
    }
  }

  String _normalizeVersion(String version) =>
      version.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
}

final coreManagerProvider =
    StateNotifierProvider<CoreManagerNotifier, CoreStatus>(
      (ref) => CoreManagerNotifier(ref),
    );
