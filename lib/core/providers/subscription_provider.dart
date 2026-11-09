// lib/core/providers/subscription_provider.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription.dart';
import '../utils/subscription_response.dart';
import '../utils/log_files.dart';
import '../models/subscription_update_report.dart';
import '../models/proxies/proxy_config.dart';
import '../models/proxies/proxy_parser.dart';
import 'settings_provider.dart';
import 'profiles_provider.dart';
import 'map_selection_provider.dart';

final subscriptionHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class SubscriptionNotifier extends StateNotifier<List<Subscription>> {
  final Ref _ref;
  late final Future<void> _ready;
  Timer? _autoUpdateTimer;
  DateTime _lastAutoUpdateCheck = DateTime.now();
  bool _isUpdatingAll = false;
  Future<SubscriptionUpdateReport>? _updateInFlight;

  SubscriptionNotifier(this._ref)
    : super([
        Subscription(
          id: 'manual',
          name: 'Ручные конфигурации',
          url: '',
          updatedTime: '',
          servers: [],
        ),
      ]) {
    _ready = _loadData();
    if (!Platform.isAndroid)
      _autoUpdateTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_runScheduledUpdate()),
      );
  }

  Future<void> get ready => _ready;

  @override
  void dispose() {
    _autoUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _runScheduledUpdate() async {
    await _ready;
    final settings = _ref.read(settingsProvider);
    if (!settings.autoUpdateSubs ||
        _isUpdatingAll ||
        DateTime.now().difference(_lastAutoUpdateCheck).inHours <
            settings.subUpdateIntervalHours) {
      return;
    }
    _lastAutoUpdateCheck = DateTime.now();
    await updateAllSubscriptions();
  }

  Future<SubscriptionUpdateReport> updateAllSubscriptions({
    Set<String>? onlyIds,
  }) async {
    await _ready;
    await _ref.read(settingsProvider.notifier).ready;
    if (_updateInFlight != null) return _updateInFlight!;
    final future = _updateSubscriptions(onlyIds);
    _updateInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_updateInFlight, future)) _updateInFlight = null;
    }
  }

  Future<SubscriptionUpdateReport> _updateSubscriptions(
    Set<String>? onlyIds,
  ) async {
    _isUpdatingAll = true;
    final updated = <String>[];
    final failed = <String, String>{};
    final ids = state
        .where(
          (s) =>
              s.id != 'manual' &&
              s.url.isNotEmpty &&
              (onlyIds == null || onlyIds.contains(s.id)),
        )
        .map((s) => s.id)
        .toList();
    try {
      for (final id in ids) {
        try {
          await updateSubscription(id);
          updated.add(id);
        } catch (error) {
          failed[id] = error.toString();
        }
      }
    } finally {
      _isUpdatingAll = false;
    }
    if (updated.isNotEmpty && _ref.read(settingsProvider).notifySubUpdate) {
      try {
        await const MethodChannel('pro.kaleert.nextlink/vpn')
            .invokeMethod<void>('notifySubscriptionUpdated', {
              'count': updated.length,
            });
      } on PlatformException {
        /* Notification permission does not change update results. */
      } on MissingPluginException {
        /* No native notifications in tests/desktop. */
      }
    }
    return SubscriptionUpdateReport(updatedIds: updated, failures: failed);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final data = prefs.getString('saved_subscriptions');
    if (data != null) {
      try {
        final List decoded = jsonDecode(data);
        state = decoded.map((e) => Subscription.fromMap(e)).toList();
      } catch (e) {
        print("Ошибка загрузки сохранений: $e");
      }
    }
  }

  Future<Map<String, String>> _subscriptionHeaders() async {
    await _ref.read(settingsProvider.notifier).ready;
    final settings = _ref.read(settingsProvider);
    final headers = <String, String>{
      'User-Agent': settings.userAgent.trim().isEmpty
          ? 'NextLink/1.0.0-beta+4'
          : settings.userAgent.trim(),
      'Accept': 'application/json, text/plain, */*',
      'X-Device-OS': Platform.isAndroid ? 'Android' : Platform.operatingSystem,
      'X-Ver-Os': Platform.operatingSystemVersion.replaceAll(
        RegExp(r'[\r\n]'),
        ' ',
      ),
    };
    if (settings.sendHwid) {
      final prefs = await SharedPreferences.getInstance();
      var hwid = prefs.getString('nextlink_hwid');
      if (hwid == null || hwid.isEmpty) {
        hwid = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
        await prefs.setString('nextlink_hwid', hwid);
      }
      headers['X-Hwid'] = hwid;
      final info = await LogFiles.collectTechnicalInfo();
      final model = info['Device'];
      if (model != null)
        headers['X-Device-Model'] = model.replaceAll(
          RegExp(r'[^\x20-\x7e]'),
          '',
        );
      if (info['Android'] != null)
        headers['X-Ver-Os'] = info['Android']!.split(' ').first;
    }
    return headers;
  }

  List<ProxyConfig> _dedupeServers(List<ProxyConfig> servers) {
    if (!_ref.read(settingsProvider).preventDuplicates) return servers;
    final seen = <String>{};
    return servers.where((server) => seen.add(server.uniqueKey)).toList();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(state.map((e) => e.toMap()).toList());
    await prefs.setString('saved_subscriptions', data);
  }

  // --- УМНЫЙ ПАРСЕР ИМЕНИ ПОДПИСКИ ---
  String? _extractSubName(Map<String, String> headers) {
    // 1. Проверяем profile-title и x-profile-title
    String? rawTitle = headers['profile-title'] ?? headers['x-profile-title'];

    if (rawTitle != null && rawTitle.isNotEmpty) {
      // Очистка от кавычек
      rawTitle = rawTitle.replaceAll('"', '').trim();

      // Обработка префикса base64: (часто встречается в 3X-UI/Marzban)
      if (rawTitle.toLowerCase().startsWith('base64:')) {
        try {
          String b64 = rawTitle.substring(7).trim();
          return utf8.decode(base64Decode(b64), allowMalformed: true);
        } catch (_) {}
      }

      // Попытка декодировать как Uri (URL encoded)
      try {
        final decoded = Uri.decodeComponent(rawTitle);
        // Если что-то реально декодировалось (есть %), возвращаем
        if (rawTitle.contains('%')) return decoded;
      } catch (_) {}

      // Попытка декодировать как чистый base64 (если нет префикса, но строка похожа)
      try {
        String normalized = rawTitle.replaceAll(' ', '+');
        while (normalized.length % 4 != 0) normalized += '=';
        return utf8.decode(base64Decode(normalized), allowMalformed: true);
      } catch (_) {}

      return rawTitle;
    }

    // 2. Проверяем имя файла в content-disposition
    String? cd = headers['content-disposition'];
    if (cd != null) {
      // Ищем filename* (RFC 5987)
      final utf8Match = RegExp(
        r"filename\*\s*=\s*UTF-8''(.+)",
        caseSensitive: false,
      ).firstMatch(cd);
      if (utf8Match != null) {
        try {
          return Uri.decodeComponent(utf8Match.group(1)!);
        } catch (_) {}
      }
      // Ищем обычный filename
      final match = RegExp(
        r'filename="?([^";]+)"?',
        caseSensitive: false,
      ).firstMatch(cd);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String _extractAnnouncement(Map<String, String> headers) {
    final raw = headers['announce']?.trim();
    if (raw == null || raw.isEmpty) return '';
    if (!raw.toLowerCase().startsWith('base64:')) return raw;

    try {
      var payload = raw.substring(7).replaceAll(RegExp(r'\s+'), '');
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      return utf8.decode(base64Decode(payload), allowMalformed: true).trim();
    } catch (_) {
      return '';
    }
  }

  Map<String, String> _extractMetadata(Map<String, String> headers) {
    const supportedHeaders = {
      'profile-title',
      'profile-update-interval',
      'profile-web-page-url',
      'support-url',
      'support_url',
      'url',
      'tun-type',
      'tun-enable',
      'hide-settings',
      'subscriptions-expand-now',
      'subscriptions-collapse',
      'check-url-via-proxy',
      'content-disposition',
    };
    return {
      for (final entry in headers.entries)
        if (supportedHeaders.contains(entry.key.toLowerCase()) ||
            entry.key.toLowerCase().startsWith('profile-') ||
            entry.key.toLowerCase().endsWith('-url'))
          entry.key.toLowerCase(): entry.value.trim(),
    };
  }

  // Изменили возвращаемый тип на Future<String>, чтобы UI мог показать имя!
  Future<String> addSubscription(
    String providedName,
    String url, {
    String? tlsFingerprint,
  }) async {
    await _ready;
    try {
      final response = await _ref
          .read(subscriptionHttpClientProvider)
          .get(Uri.parse(url), headers: await _subscriptionHeaders())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200)
        throw Exception('Ошибка сервера: ${response.statusCode}');

      validateSubscriptionResponse(response.headers, const []);
      final servers = _dedupeServers(
        ProxyParser.parseSubscription(response.body),
      );
      validateSubscriptionResponse(response.headers, servers);
      if (servers.isEmpty)
        throw const FormatException(
          'В подписке нет поддерживаемых конфигураций',
        );
      int upload = 0, download = 0, total = 0, expire = 0;

      final userInfo =
          response.headers['subscription-userinfo'] ??
          response.headers['profile-update-interval'];
      if (userInfo != null) {
        for (var part in userInfo.split(';')) {
          final kv = part.trim().split('=');
          if (kv.length == 2) {
            final key = kv[0].toLowerCase();
            final value = int.tryParse(kv[1]) ?? 0;
            if (key == 'upload') upload = value;
            if (key == 'download') download = value;
            if (key == 'total') total = value;
            if (key == 'expire') expire = value;
          }
        }
      }

      // Вытаскиваем имя из заголовков, если пользователь его не вписал
      String finalName = providedName;
      if (finalName.isEmpty ||
          finalName == 'Imported Sub' ||
          finalName == 'New Sub') {
        finalName = _extractSubName(response.headers) ?? 'Безымянная подписка';
      }

      state = [
        ...state,
        Subscription(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: finalName,
          url: url,
          updatedTime: DateTime.now().toUtc().toIso8601String(),
          upload: upload,
          download: download,
          total: total,
          expireDate: expire,
          tlsFingerprint: tlsFingerprint ?? 'chrome',
          announcement: _extractAnnouncement(response.headers),
          metadata: _extractMetadata(response.headers),
          servers: servers,
        ),
      ];
      await _saveData();
      return finalName; // Возвращаем имя для SnackBar
    } catch (e) {
      throw Exception('Ошибка загрузки: $e');
    }
  }

  Future<void> updateSubscription(String subId) async {
    await _ready;
    var subIndex = state.indexWhere((s) => s.id == subId);
    if (subIndex == -1) throw Exception("Подписка не найдена");
    final sub = state[subIndex];

    try {
      final response = await _ref
          .read(subscriptionHttpClientProvider)
          .get(Uri.parse(sub.url), headers: await _subscriptionHeaders())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200)
        throw Exception('Ошибка сервера: ${response.statusCode}');

      validateSubscriptionResponse(response.headers, const []);
      final servers = _dedupeServers(
        ProxyParser.parseSubscription(response.body),
      );
      validateSubscriptionResponse(response.headers, servers);
      if (servers.isEmpty)
        throw const FormatException(
          'В подписке нет поддерживаемых конфигураций',
        );

      subIndex = state.indexWhere((s) => s.id == subId);
      if (subIndex < 0) return; // Deleted while the request was in flight.
      final latest = state[subIndex];
      final replacements = <String, String>{};
      for (final old in latest.servers) {
        final candidates = servers
            .where(
              (s) =>
                  s.protocol == old.protocol &&
                  s.name == old.name &&
                  s.address == old.address &&
                  s.port == old.port,
            )
            .toList();
        if (!servers.any((s) => s.uniqueKey == old.uniqueKey) &&
            candidates.length == 1) {
          replacements[old.uniqueKey] = candidates.single.uniqueKey;
        }
      }
      if (replacements.isNotEmpty)
        await _ref
            .read(profilesProvider.notifier)
            .rebindServerKeys(replacements);

      // СОХРАНЯЕМ ВЫБРАННЫЙ СЕРВЕР ПРИ ОБНОВЛЕНИИ
      String? activeKey;
      for (var s in latest.servers) {
        if (s.isActive) {
          activeKey = s.uniqueKey;
          break;
        }
      }

      if (activeKey != null) {
        for (var s in servers) {
          if (s.uniqueKey == (replacements[activeKey] ?? activeKey)) {
            s.isActive = true;
            break;
          }
        }
      }

      int upload = 0, download = 0, total = 0, expire = 0;

      final userInfo =
          response.headers['subscription-userinfo'] ??
          response.headers['profile-update-interval'];
      if (userInfo != null) {
        for (var part in userInfo.split(';')) {
          final kv = part.trim().split('=');
          if (kv.length == 2) {
            final key = kv[0].toLowerCase();
            final value = int.tryParse(kv[1]) ?? 0;
            if (key == 'upload') upload = value;
            if (key == 'download') download = value;
            if (key == 'total') total = value;
            if (key == 'expire') expire = value;
          }
        }
      }

      // При обновлении мы не перезаписываем имя, вдруг юзер переименовал её сам!
      final updatedSub = Subscription(
        id: sub.id,
        name: latest.name,
        url: sub.url,
        updatedTime: DateTime.now().toUtc().toIso8601String(),
        upload: upload,
        download: download,
        total: total,
        expireDate: expire,
        tlsFingerprint: latest.tlsFingerprint,
        announcement: _extractAnnouncement(response.headers),
        metadata: _extractMetadata(response.headers),
        servers: servers,
      );
      final newState = [...state];
      newState[subIndex] = updatedSub;
      state = newState;
      await _saveData();
    } catch (e) {
      throw Exception('Ошибка обновления: $e');
    }
  }

  void updateProxyJson(String subId, ProxyConfig server, String newJson) {
    state = state.map((sub) {
      if (sub.id == subId) {
        final newServers = sub.servers.map((s) {
          if (s == server) s.rawJsonOverride = newJson;
          return s;
        }).toList();
        return Subscription(
          id: sub.id,
          name: sub.name,
          url: sub.url,
          updatedTime: sub.updatedTime,
          upload: sub.upload,
          download: sub.download,
          total: sub.total,
          expireDate: sub.expireDate,
          tlsFingerprint: sub.tlsFingerprint,
          announcement: sub.announcement,
          metadata: sub.metadata,
          servers: newServers,
        );
      }
      return sub;
    }).toList();
    _saveData();
  }

  void renameSubscription(String subId, String newName) {
    state = state.map((sub) {
      if (sub.id == subId) {
        return Subscription(
          id: sub.id,
          name: newName,
          url: sub.url,
          updatedTime: sub.updatedTime,
          upload: sub.upload,
          download: sub.download,
          total: sub.total,
          expireDate: sub.expireDate,
          tlsFingerprint: sub.tlsFingerprint,
          announcement: sub.announcement,
          metadata: sub.metadata,
          servers: sub.servers,
        );
      }
      return sub;
    }).toList();
    _saveData();
  }

  void removeSubscription(String subId) {
    state = state.where((sub) => sub.id != subId).toList();
    _saveData();
  }

  Future<void> addSingleProxy(ProxyConfig proxy) async {
    await addManualConfigs([proxy]);
  }

  Future<int> addManualConfigs(List<ProxyConfig> configs) async {
    await _ready;
    if (!mounted) return 0;
    final index = state.indexWhere((s) => s.id == 'manual');
    final manual = index < 0
        ? Subscription(
            id: 'manual',
            name: 'Ручные конфигурации',
            url: '',
            updatedTime: '',
            servers: [],
          )
        : state[index];
    final servers = _dedupeServers([...manual.servers, ...configs]);
    final updated = Subscription(
      id: manual.id,
      name: manual.name,
      url: manual.url,
      updatedTime: manual.updatedTime,
      tlsFingerprint: manual.tlsFingerprint,
      servers: servers,
    );
    final next = [...state];
    if (index < 0) {
      next.insert(0, updated);
    } else {
      next[index] = updated;
    }
    state = next;
    await _saveData();
    return servers.length - manual.servers.length;
  }

  void deleteProxy(String subId, ProxyConfig proxy) {
    state = state.map((sub) {
      if (sub.id == subId) {
        return Subscription(
          id: sub.id,
          name: sub.name,
          url: sub.url,
          updatedTime: sub.updatedTime,
          upload: sub.upload,
          download: sub.download,
          total: sub.total,
          expireDate: sub.expireDate,
          tlsFingerprint: sub.tlsFingerprint,
          announcement: sub.announcement,
          metadata: sub.metadata,
          servers: sub.servers.where((s) => s != proxy).toList(),
        );
      }
      return sub;
    }).toList();
    _saveData();
  }

  void updateProxy(String subId, ProxyConfig oldProxy, ProxyConfig newProxy) {
    state = state.map((sub) {
      if (sub.id == subId) {
        final newServers = sub.servers
            .map((s) => s == oldProxy ? newProxy : s)
            .toList();
        return Subscription(
          id: sub.id,
          name: sub.name,
          url: sub.url,
          updatedTime: sub.updatedTime,
          upload: sub.upload,
          download: sub.download,
          total: sub.total,
          expireDate: sub.expireDate,
          tlsFingerprint: sub.tlsFingerprint,
          announcement: sub.announcement,
          metadata: sub.metadata,
          servers: newServers,
        );
      }
      return sub;
    }).toList();
    _saveData();
  }

  void setActiveServer(
    String subId,
    ProxyConfig selectedServer, {
    bool preserveMapSelection = false,
  }) {
    if (!preserveMapSelection)
      unawaited(_ref.read(mapSelectionProvider.notifier).choose(null));
    bool changed = false;
    final targetKey = selectedServer.uniqueKey;

    state = state.map((sub) {
      bool subChanged = false;
      final updatedServers = sub.servers.map((server) {
        final bool shouldBeActive =
            (sub.id == subId && server.uniqueKey == targetKey);

        if (server.isActive != shouldBeActive) {
          // Клонируем только если статус реально меняется, чтобы не дергать лишний раз UI
          final cloned = ProxyParser.fromMap(server.toMap());
          cloned.isActive = shouldBeActive;
          subChanged = true;
          changed = true;
          return cloned;
        }
        return server;
      }).toList();

      if (subChanged) {
        return Subscription(
          id: sub.id,
          name: sub.name,
          url: sub.url,
          updatedTime: sub.updatedTime,
          upload: sub.upload,
          download: sub.download,
          total: sub.total,
          expireDate: sub.expireDate,
          tlsFingerprint: sub.tlsFingerprint,
          announcement: sub.announcement,
          metadata: sub.metadata,
          servers: updatedServers,
        );
      }
      return sub;
    }).toList();

    if (changed) {
      _saveData();
    }
  }

  void refreshState() {
    state = [...state];
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, List<Subscription>>(
      (ref) => SubscriptionNotifier(ref),
    );
