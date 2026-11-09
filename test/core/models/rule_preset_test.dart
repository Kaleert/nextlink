import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextlink/core/models/rule_preset.dart';
import 'package:nextlink/core/providers/rules_provider.dart';
import 'package:nextlink/core/providers/settings_provider.dart';
import 'package:nextlink/core/models/proxies/vless_config.dart';
import 'package:nextlink/core/engine/config_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final server = VlessConfig(
    name: 'Test',
    address: 'example.org',
    port: 443,
    uuid: '00000000-0000-0000-0000-000000000001',
  );
  test('RU preset compiles domain suffixes and IP rule for both cores', () {
    final rules = RulePreset.all.first.rules;
    final xray = XrayConfigBuilder(
      activeProxy: server,
      settings: SettingsState(),
      customRules: rules,
    ).build();
    final xr = xray['routing']['rules'] as List;
    expect(
      xr.any(
        (r) =>
            r['outboundTag'] == 'direct' &&
            (r['domain'] as List? ?? []).contains('domain:ru'),
      ),
      isTrue,
    );
    expect(
      xr.any(
        (r) =>
            r['outboundTag'] == 'direct' &&
            (r['domain'] as List? ?? []).contains('domain:xn--p1ai'),
      ),
      isTrue,
    );
    expect(
      xr.any(
        (r) =>
            r['outboundTag'] == 'direct' &&
            (r['ip'] as List? ?? []).contains('geoip:ru'),
      ),
      isTrue,
    );
    final sb = SingBoxConfigBuilder(
      activeProxy: server,
      settings: SettingsState(),
      customRules: rules,
    ).build();
    final sr = sb['route']['rules'] as List;
    expect(
      sr.any(
        (r) =>
            r['outbound'] == 'direct' &&
            (r['domain_suffix'] as List? ?? []).contains('ru'),
      ),
      isTrue,
    );
    expect(
      sr.any(
        (r) =>
            r['outbound'] == 'direct' &&
            (r['rule_set'] as List? ?? []).contains('geoip-ru'),
      ),
      isTrue,
    );
  });
  test(
    'applying a preset twice preserves other rules and priority across reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = RulesNotifier();
      await notifier.ready;
      notifier.addRule(
        AppRule(id: 'keep', type: 'GeoSite', value: 'youtube', action: 'PROXY'),
      );
      await notifier.applyPreset(RulePreset.all.first.rules);
      await notifier.applyPreset(RulePreset.all.first.rules);
      expect(notifier.state, hasLength(3));
      expect(notifier.state.first.id, 'preset:ru-domains');
      expect(notifier.state.last.id, 'keep');
      final restored = RulesNotifier();
      await restored.ready;
      expect(restored.state.map((r) => r.id), notifier.state.map((r) => r.id));
      notifier.dispose();
      restored.dispose();
    },
  );
}
