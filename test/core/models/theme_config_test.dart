import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/theme_config.dart';

void main() {
  test(
    'old themes retain defaults and new controls survive file round trip',
    () {
      final old = ThemeConfig.fromMap({'name': 'Legacy'});
      expect(old.fontFamily, 'Nunito');
      expect(ThemeConfig.defaultTheme.fontFamily, 'Nunito');
      expect(ThemeConfig.emeraldGreen.fontFamily, 'Nunito');
      expect(ThemeConfig.oceanicBlue.fontFamily, 'Nunito');
      expect(old.powerButtonSize, 200);
      expect(old.pressDurationMs, 160);
      final edited = old.copyWith(
        backgroundStyle: 'linear',
        gradientAngle: 90,
        glassOpacity: .3,
        blurSigma: 40,
        borderWidth: 2,
        textScale: 1.1,
        powerButtonSize: 180,
        backgroundIntensity: .7,
        pressDurationMs: 220,
        componentScales: {'home_status': .8},
        componentOpacities: {'home_ping': .5},
        customElements: [
          {'id': 'a', 'label': 'Servers', 'action': 'servers'},
        ],
      );
      final imported = ThemeConfig.fromMap(edited.toMap());
      expect(imported.toMap(), edited.toMap());
      expect(imported.scaleFor('home_status'), .8);
      expect(imported.opacityFor('home_ping'), .5);
    },
  );
  test('imported numeric controls are clamped to safe ranges', () {
    final theme = ThemeConfig.fromMap({
      'name': 'Bad numbers',
      'glassOpacity': 10,
      'blurSigma': -4,
      'textScale': 5,
      'powerButtonSize': 4000,
    });
    expect(theme.glassOpacity, 1);
    expect(theme.blurSigma, 0);
    expect(theme.textScale, 1.3);
    expect(theme.powerButtonSize, 240);
  });
}
