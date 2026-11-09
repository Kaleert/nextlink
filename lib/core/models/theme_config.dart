import 'dart:ui';

import 'package:flutter/material.dart';

class ThemeConfig {
  final String name;
  final String description;
  final String author;
  final Color background;
  final Color surface;
  final Color primary;
  final Color primaryDark;
  final Color text;
  final Color textDim;
  final Color meshIdle1;
  final Color meshIdle2;
  final Color meshActive1;
  final Color meshActive2;
  final bool useGradients;
  final bool animationsEnabled;
  final int animationDurationMs;
  final double cardRadius;
  final String fontFamily;
  final List<String> hiddenElements;
  final List<Map<String, dynamic>> customElements;
  final bool gradientTitle;
  final Map<String, String> componentAnimations;
  final Map<String, int> componentColors;
  final Map<String, double> componentRadii;
  final List<String> componentOrder;
  final Map<String, Offset> componentOffsets;
  final Map<String, String> componentTexts;
  final Map<String, Map<String, dynamic>> componentBackgrounds;
  final Map<String, String> componentMotions;
  final Map<String, List<String>> layoutOrders;

  final String backgroundStyle;
  final double gradientAngle;
  final double glassOpacity;
  final double blurSigma;
  final double borderWidth;
  final double textScale;
  final double backgroundIntensity;
  final double powerButtonSize;
  final int pressDurationMs;
  final Map<String, double> componentScales;
  final Map<String, double> componentOpacities;

  double scaleFor(String id) => (componentScales[id] ?? 1).clamp(.65, 1.35);
  double opacityFor(String id) => (componentOpacities[id] ?? 1).clamp(.1, 1);

  Color colorFor(String componentId) =>
      Color(componentColors[componentId] ?? primary.value);

  double radiusFor(String componentId) =>
      componentRadii[componentId]?.clamp(0, 80) ?? cardRadius.clamp(6, 42);

  Offset offsetFor(String componentId) =>
      componentOffsets[componentId] ?? Offset.zero;

  bool get isBuiltIn => const {
    'theme_crimson_red',
    'theme_emerald_green',
    'theme_oceanic_blue',
    'theme_neon_origami',
    'Crimson Red (Default)',
    'Emerald Green',
    'Oceanic Blue',
  }.contains(name);

  ThemeConfig({
    required this.name,
    this.backgroundStyle = 'mesh',
    this.gradientAngle = 45,
    this.glassOpacity = .52,
    this.blurSigma = 26,
    this.borderWidth = 1,
    this.textScale = 1,
    this.backgroundIntensity = 1,
    this.powerButtonSize = 200,
    this.pressDurationMs = 160,
    this.componentScales = const {},
    this.componentOpacities = const {},
    this.description = '',
    this.author = '',
    this.background = const Color(0xFF080808),
    this.surface = const Color(0xFF141414),
    this.primary = const Color(0xFFE00000),
    this.primaryDark = const Color(0xFF700000),
    this.text = Colors.white,
    this.textDim = const Color(0xFF888888),
    this.meshIdle1 = const Color(0xFF220505),
    this.meshIdle2 = const Color(0xFF110202),
    this.meshActive1 = const Color(0xFF3A0000),
    this.meshActive2 = const Color(0xFF1F0000),
    this.useGradients = true,
    this.animationsEnabled = true,
    this.animationDurationMs = 8000,
    this.cardRadius = 24,
    this.fontFamily = 'Nunito',
    this.hiddenElements = const [],
    this.customElements = const [],
    this.gradientTitle = true,
    this.componentAnimations = const {},
    this.componentColors = const {},
    this.componentRadii = const {},
    this.componentOrder = const [],
    this.componentOffsets = const {},
    this.componentTexts = const {},
    this.componentBackgrounds = const {},
    this.componentMotions = const {},
    this.layoutOrders = const {},
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'backgroundStyle': backgroundStyle,
    'gradientAngle': gradientAngle,
    'glassOpacity': glassOpacity,
    'blurSigma': blurSigma,
    'borderWidth': borderWidth,
    'textScale': textScale,
    'backgroundIntensity': backgroundIntensity,
    'powerButtonSize': powerButtonSize,
    'pressDurationMs': pressDurationMs,
    'componentScales': componentScales,
    'componentOpacities': componentOpacities,
    'description': description,
    'author': author,
    'background': background.value,
    'surface': surface.value,
    'primary': primary.value,
    'primaryDark': primaryDark.value,
    'text': text.value,
    'textDim': textDim.value,
    'meshIdle1': meshIdle1.value,
    'meshIdle2': meshIdle2.value,
    'meshActive1': meshActive1.value,
    'meshActive2': meshActive2.value,
    'useGradients': useGradients,
    'animationsEnabled': animationsEnabled,
    'animationDurationMs': animationDurationMs,
    'cardRadius': cardRadius,
    'fontFamily': fontFamily,
    'hiddenElements': hiddenElements,
    'customElements': customElements,
    'gradientTitle': gradientTitle,
    'componentAnimations': componentAnimations,
    'componentColors': componentColors,
    'componentRadii': componentRadii,
    'componentOrder': componentOrder,
    'componentTexts': componentTexts,
    'componentBackgrounds': componentBackgrounds,
    'componentMotions': componentMotions,
    'layoutOrders': layoutOrders,
    'componentOffsets': componentOffsets.map(
      (key, value) => MapEntry(key, [value.dx, value.dy]),
    ),
  };

  ThemeConfig copyWith({
    String? name,
    String? backgroundStyle,
    double? gradientAngle,
    double? glassOpacity,
    double? blurSigma,
    double? borderWidth,
    double? textScale,
    double? backgroundIntensity,
    double? powerButtonSize,
    int? pressDurationMs,
    Map<String, double>? componentScales,
    Map<String, double>? componentOpacities,
    String? description,
    String? author,
    Color? background,
    Color? surface,
    Color? primary,
    Color? primaryDark,
    Color? text,
    Color? textDim,
    Color? meshIdle1,
    Color? meshIdle2,
    Color? meshActive1,
    Color? meshActive2,
    bool? useGradients,
    bool? animationsEnabled,
    int? animationDurationMs,
    double? cardRadius,
    String? fontFamily,
    List<String>? hiddenElements,
    List<Map<String, dynamic>>? customElements,
    bool? gradientTitle,
    Map<String, String>? componentAnimations,
    Map<String, int>? componentColors,
    Map<String, double>? componentRadii,
    List<String>? componentOrder,
    Map<String, Offset>? componentOffsets,
    Map<String, String>? componentTexts,
    Map<String, Map<String, dynamic>>? componentBackgrounds,
    Map<String, String>? componentMotions,
    Map<String, List<String>>? layoutOrders,
  }) => ThemeConfig(
    name: name ?? this.name,
    backgroundStyle: backgroundStyle ?? this.backgroundStyle,
    gradientAngle: gradientAngle ?? this.gradientAngle,
    glassOpacity: glassOpacity ?? this.glassOpacity,
    blurSigma: blurSigma ?? this.blurSigma,
    borderWidth: borderWidth ?? this.borderWidth,
    textScale: textScale ?? this.textScale,
    backgroundIntensity: backgroundIntensity ?? this.backgroundIntensity,
    powerButtonSize: powerButtonSize ?? this.powerButtonSize,
    pressDurationMs: pressDurationMs ?? this.pressDurationMs,
    componentScales: componentScales ?? this.componentScales,
    componentOpacities: componentOpacities ?? this.componentOpacities,
    description: description ?? this.description,
    author: author ?? this.author,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    primary: primary ?? this.primary,
    primaryDark: primaryDark ?? this.primaryDark,
    text: text ?? this.text,
    textDim: textDim ?? this.textDim,
    meshIdle1: meshIdle1 ?? this.meshIdle1,
    meshIdle2: meshIdle2 ?? this.meshIdle2,
    meshActive1: meshActive1 ?? this.meshActive1,
    meshActive2: meshActive2 ?? this.meshActive2,
    useGradients: useGradients ?? this.useGradients,
    animationsEnabled: animationsEnabled ?? this.animationsEnabled,
    animationDurationMs: animationDurationMs ?? this.animationDurationMs,
    cardRadius: cardRadius ?? this.cardRadius,
    fontFamily: fontFamily ?? this.fontFamily,
    hiddenElements: hiddenElements ?? this.hiddenElements,
    customElements: customElements ?? this.customElements,
    gradientTitle: gradientTitle ?? this.gradientTitle,
    componentAnimations: componentAnimations ?? this.componentAnimations,
    componentColors: componentColors ?? this.componentColors,
    componentRadii: componentRadii ?? this.componentRadii,
    componentOrder: componentOrder ?? this.componentOrder,
    componentOffsets: componentOffsets ?? this.componentOffsets,
    componentTexts: componentTexts ?? this.componentTexts,
    componentBackgrounds: componentBackgrounds ?? this.componentBackgrounds,
    componentMotions: componentMotions ?? this.componentMotions,
    layoutOrders: layoutOrders ?? this.layoutOrders,
  );

  factory ThemeConfig.fromMap(Map<String, dynamic> map) {
    Color parseColor(dynamic value, int fallback) {
      if (value is num) return Color(value.toInt());
      if (value is String) {
        final raw = value.trim().replaceFirst('#', '').replaceFirst('0x', '');
        final parsed = int.tryParse(raw, radix: 16);
        if (parsed != null)
          return Color(raw.length <= 6 ? 0xFF000000 | parsed : parsed);
      }
      return Color(fallback);
    }

    final offsets = <String, Offset>{};
    final rawOffsets = map['componentOffsets'];
    if (rawOffsets is Map) {
      for (final entry in rawOffsets.entries) {
        final value = entry.value;
        if (value is List &&
            value.length >= 2 &&
            value[0] is num &&
            value[1] is num) {
          offsets[entry.key.toString()] = Offset(
            (value[0] as num).toDouble(),
            (value[1] as num).toDouble(),
          );
        } else if (value is Map && value['x'] is num && value['y'] is num) {
          offsets[entry.key.toString()] = Offset(
            (value['x'] as num).toDouble(),
            (value['y'] as num).toDouble(),
          );
        }
      }
    }

    return ThemeConfig(
      name: map['name'] ?? 'Custom',
      backgroundStyle:
          const [
            'mesh',
            'linear',
            'radial',
            'off',
          ].contains(map['backgroundStyle'])
          ? map['backgroundStyle']
          : 'mesh',
      gradientAngle: ((map['gradientAngle'] as num?)?.toDouble() ?? 45)
          .clamp(-180, 180)
          .toDouble(),
      glassOpacity: ((map['glassOpacity'] as num?)?.toDouble() ?? .52)
          .clamp(0.08, 1)
          .toDouble(),
      blurSigma: ((map['blurSigma'] as num?)?.toDouble() ?? 26)
          .clamp(0, 64)
          .toDouble(),
      borderWidth: ((map['borderWidth'] as num?)?.toDouble() ?? 1)
          .clamp(0, 3)
          .toDouble(),
      textScale: ((map['textScale'] as num?)?.toDouble() ?? 1)
          .clamp(0.8, 1.3)
          .toDouble(),
      backgroundIntensity:
          ((map['backgroundIntensity'] as num?)?.toDouble() ?? 1)
              .clamp(0, 1)
              .toDouble(),
      powerButtonSize: ((map['powerButtonSize'] as num?)?.toDouble() ?? 200)
          .clamp(140, 240)
          .toDouble(),
      pressDurationMs: ((map['pressDurationMs'] as num?)?.toInt() ?? 160)
          .clamp(80, 500)
          .toInt(),
      componentScales: (map['componentScales'] as Map? ?? {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      ),
      componentOpacities: (map['componentOpacities'] as Map? ?? {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      ),
      description: map['description']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      background: parseColor(map['background'], 0xFF080808),
      surface: parseColor(map['surface'], 0xFF141414),
      primary: parseColor(map['primary'], 0xFFE00000),
      primaryDark: parseColor(map['primaryDark'], 0xFF700000),
      text: parseColor(map['text'], 0xFFFFFFFF),
      textDim: parseColor(map['textDim'], 0xFF888888),
      meshIdle1: parseColor(map['meshIdle1'], 0xFF220505),
      meshIdle2: parseColor(map['meshIdle2'], 0xFF110202),
      meshActive1: parseColor(map['meshActive1'], 0xFF3A0000),
      meshActive2: parseColor(map['meshActive2'], 0xFF1F0000),
      useGradients: map['useGradients'] ?? true,
      animationsEnabled: map['animationsEnabled'] ?? true,
      animationDurationMs:
          ((map['animationDurationMs'] as num?)?.toInt() ?? 8000).clamp(
            1000,
            20000,
          ),
      cardRadius: (map['cardRadius'] as num?)?.toDouble() ?? 24,
      fontFamily: map['fontFamily']?.toString() ?? 'Nunito',
      hiddenElements: (map['hiddenElements'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      customElements: (map['customElements'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      gradientTitle: map['gradientTitle'] ?? true,
      componentAnimations: (map['componentAnimations'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      componentColors: (map['componentColors'] as Map? ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          value is num
              ? value.toInt()
              : int.tryParse(value.toString()) ?? 0xFF72F7D4,
        ),
      ),
      componentRadii: (map['componentRadii'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      ),
      componentOrder: (map['componentOrder'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      componentOffsets: offsets,
      componentBackgrounds: (map['componentBackgrounds'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
      ),
      componentMotions: (map['componentMotions'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      componentTexts: (map['componentTexts'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      layoutOrders: (map['layoutOrders'] as Map? ?? {}).map(
        (k, v) => MapEntry(
          k.toString(),
          (v as List).map((e) => e.toString()).toList(),
        ),
      ),
    );
  }

  static ThemeConfig get neonOrigami => ThemeConfig(
    name: 'theme_neon_origami',
    author: 'Kaleert',
    description: 'Неоновое оригами: ледяной фон, ультрафиолет и лайм, острые карточки и плавное движение.',
    background: const Color(0xFF080D17),
    surface: const Color(0xFF182038),
    primary: const Color(0xFFD5FF70),
    primaryDark: const Color(0xFF9D7AFF),
    text: const Color(0xFFF1F6FF),
    textDim: const Color(0xFF9AAAC8),
    meshIdle1: const Color(0xFF241342),
    meshIdle2: const Color(0xFF063A45),
    meshActive1: const Color(0xFF492263),
    meshActive2: const Color(0xFF154F43),
    gradientTitle: true,
    cardRadius: 10,
    glassOpacity: .38,
    blurSigma: 30,
    backgroundIntensity: .9,
    animationDurationMs: 12000,
    pressDurationMs: 220,
    componentColors: {
      'home_traffic_arrow': 0xFF72F7B4,
      'home_power_button': 0xFF56388D,
    },
    componentAnimations: {
      'home_power_button': 'soft',
      'home_settings_button': 'bounce',
    },
    componentMotions: {'home_app_title': 'float'},
    componentRadii: {
      'home_power_button': 28,
      'home_server_card': 10,
      'home_system_info': 10,
      'home_timer': 8,
    },
  );

  static ThemeConfig get defaultTheme => ThemeConfig(
    name: 'theme_crimson_red',
    author: 'Kaleert',
    description: 'Классическая тёмная тема NextLink с рубиновым акцентом.',
    gradientTitle: false,
    cardRadius: 18,
  );

  static ThemeConfig get emeraldGreen => ThemeConfig(
    name: 'theme_emerald_green',
    author: 'Kaleert',
    description: 'Глубокие зелёные оттенки и яркий изумрудный акцент.',
    gradientTitle: false,
    cardRadius: 18,
    primary: const Color(0xFF00E050),
    primaryDark: const Color(0xFF007028),
    meshIdle1: const Color(0xFF05220E),
    meshIdle2: const Color(0xFF021107),
    meshActive1: const Color(0xFF003A14),
    meshActive2: const Color(0xFF001F0B),
  );

  static ThemeConfig get oceanicBlue => ThemeConfig(
    name: 'theme_oceanic_blue',
    author: 'Kaleert',
    description: 'Холодная синяя палитра с глубоким океанским фоном.',
    gradientTitle: false,
    cardRadius: 18,
    primary: const Color(0xFF0080E0),
    primaryDark: const Color(0xFF004070),
    meshIdle1: const Color(0xFF050E22),
    meshIdle2: const Color(0xFF020711),
    meshActive1: const Color(0xFF00143A),
    meshActive2: const Color(0xFF000B1F),
  );
}
