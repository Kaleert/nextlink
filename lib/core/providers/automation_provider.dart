import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/config_builder.dart';
import '../models/subscription.dart';
import '../utils/core_binary_paths.dart';
import '../utils/proxy_runtime.dart';
import '../utils/routing_rule_codec.dart';
import 'profiles_provider.dart';
import 'subscription_provider.dart';
import 'settings_provider.dart';
import 'rules_provider.dart';
import 'core_manager_provider.dart';

final automationSyncProvider = Provider<AutomationSynchronizer>((ref) {
  final sync = AutomationSynchronizer(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

/// Compile user rules once in Flutter; Android can then run them without an engine.
class AutomationSynchronizer {
  final Ref ref;
  Timer? _timer;
  bool _disposed = false;
  bool _running = false;
  bool _suspended = false;
  bool _again = false;
  String? _lastPlan;
  int _revision = 0;
  AutomationSynchronizer(this.ref) {
    if (!Platform.isAndroid) return;
    ref.listen(profilesProvider, (_, __) => schedule());
    ref.listen(subscriptionProvider, (_, __) => schedule());
    ref.listen(settingsProvider, (_, __) => schedule());
    ref.listen(rulesProvider, (_, __) => schedule());
    ref.listen(coreManagerProvider, (_, __) => schedule());
    schedule();
  }
  void suspend() {
    _suspended = true;
    _lastPlan = null;
    _timer?.cancel();
  }

  void resume() {
    _suspended = false;
    schedule();
  }

  void schedule() {
    _revision++;
    if (_suspended || _disposed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), _sync);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _revision++;
    await ref.read(profilesProvider.notifier).ready;
    await ref.read(subscriptionProvider.notifier).ready;
    await ref.read(settingsProvider.notifier).ready;
    await ref.read(rulesProvider.notifier).ready;
    final plan = await compileAutomationPlan(
      profiles: ref.read(profilesProvider),
      subscriptions: ref.read(subscriptionProvider),
      settings: ref.read(settingsProvider),
      rules: ref.read(rulesProvider),
      appDir: (await getApplicationSupportDirectory()).path,
    );
    final encoded = jsonEncode(plan);
    await const MethodChannel('pro.kaleert.nextlink/vpn')
        .invokeMethod<void>('storeAutomationPlan', {'plan': encoded});
    _lastPlan = encoded;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  Future<void> _sync() async {
    if (_disposed || _suspended) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    final revision = _revision;
    try {
      await ref.read(profilesProvider.notifier).ready;
      await ref.read(subscriptionProvider.notifier).ready;
      await ref.read(settingsProvider.notifier).ready;
      if (_disposed) return;
      await ref.read(rulesProvider.notifier).ready;
      final plan = await compileAutomationPlan(
        profiles: ref.read(profilesProvider),
        subscriptions: ref.read(subscriptionProvider),
        settings: ref.read(settingsProvider),
        rules: ref.read(rulesProvider),
        appDir: (await getApplicationSupportDirectory()).path,
      );
      final encoded = jsonEncode(plan);
      if (!_disposed &&
          !_suspended &&
          revision == _revision &&
          encoded != _lastPlan) {
        await const MethodChannel('pro.kaleert.nextlink/vpn')
            .invokeMethod('syncAutomation', {'plan': encoded});
        _lastPlan = encoded;
      }
    } catch (_) {
      /* Foreground-service restrictions are retried on the next foreground edit. */
    } finally {
      _running = false;
      if (_again && !_disposed) {
        _again = false;
        schedule();
      }
    }
  }
}

Future<Map<String, dynamic>> compileAutomationPlan({
  required List<AppProfile> profiles,
  required List<Subscription> subscriptions,
  required SettingsState settings,
  required List<AppRule> rules,
  required String appDir,
}) async {
  final targets = <Map<String, dynamic>>[];
  if (profiles.any((p) => p.isEnabled)) {
    for (final sub in subscriptions) {
      for (final server in sub.servers) {
        if (!profiles.any(
          (p) =>
              p.isEnabled &&
              (p.serverKeys.isEmpty ||
                  p.serverKeys.contains(server.uniqueKey) ||
                  p.serverKey == server.uniqueKey),
        ))
          continue;
        try {
          final runtimeServer = proxyWithFallbackFingerprint(
            server,
            sub.tlsFingerprint,
          );
          final raw = runtimeServer.finalJson;
          final xhttp = jsonEncode(raw).toLowerCase().contains('"xhttp"');
          final endpoint =
              raw.containsKey('endpoints') ||
              ['wireguard', 'awg'].contains(raw['type']) ||
              (raw['outbounds'] as List? ?? []).any(
                (o) => ['wireguard', 'awg'].contains(o['type']),
              );
          final xrayWg =
              raw['protocol'] == 'wireguard' ||
              (raw['outbounds'] as List? ?? []).any(
                (o) => o['protocol'] == 'wireguard',
              );
          final nativeRules = rules.any(
            (r) =>
                r.conditions != null &&
                RoutingRuleCodec.needsSingBox(r.conditions!),
          );
          if (nativeRules && (xhttp || xrayWg))
            throw const FormatException('Правила требуют Sing-box');
          final core = nativeRules
              ? 'SINGBOX'
              : xhttp || xrayWg
              ? 'XRAY'
              : endpoint || server.protocol.contains('HYSTERIA')
              ? 'SINGBOX'
              : settings.preferredCore.toUpperCase();
          final path = core == 'SINGBOX'
              ? await CoreBinaryPaths.singBox(appDir, [
                  server,
                ], custom: settings.singboxUrl.isNotEmpty)
              : '${appDir}/libxray.so';
          if (!await File(path).exists()) continue;
          final config = core == 'SINGBOX'
              ? SingBoxConfigBuilder(
                  activeProxy: runtimeServer,
                  settings: settings,
                  customRules: rules,
                ).build()
              : XrayConfigBuilder(
                  activeProxy: runtimeServer,
                  settings: settings,
                  customRules: rules,
                ).build();
          targets.add({
            'key': server.uniqueKey,
            'name': server.name,
            'coreType': core,
            'corePath': path,
            'config': jsonEncode(config),
          });
        } catch (_) {
          /* An unsupported server must not prevent valid plans from syncing. */
        }
        if (targets.length % 16 == 0) await Future<void>.delayed(Duration.zero);
      }
    }
  }
  final plan = {
    'profiles': profiles.map((p) => p.toMap()).toList(),
    'probeUrl': settings.pingUrl,
    'servers': targets,
    'tunnel': {
      'httpPort': settings.httpPort,
      'socksPort': settings.socksPort,
      'tunMtu': settings.tunMtu,
      'ipv6': settings.ipv6,
      'strictMode': settings.strictMode,
      'bypassLan': settings.bypassLan,
      'perAppEnabled': settings.perAppEnabled,
      'perAppDefaultRule': settings.perAppDefaultRule,
      'perAppRules': settings.perAppRules,
    },
  };
  return plan;
}

Future<void> refreshBackgroundAutomationPlan(
  ProviderContainer container,
) async {
  await container.read(profilesProvider.notifier).ready;
  await container.read(rulesProvider.notifier).ready;
  final plan = await compileAutomationPlan(
    profiles: container.read(profilesProvider),
    subscriptions: container.read(subscriptionProvider),
    settings: container.read(settingsProvider),
    rules: container.read(rulesProvider),
    appDir: (await getApplicationSupportDirectory()).path,
  );
  await const MethodChannel('pro.kaleert.nextlink/vpn')
      .invokeMethod<void>('storeAutomationPlan', {'plan': jsonEncode(plan)});
}
