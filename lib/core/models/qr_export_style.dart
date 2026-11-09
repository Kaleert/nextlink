import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrExportStyle {
  final int foreground, background, size, quietZone;
  final String eyes, modules, correction;
  const QrExportStyle({
    this.foreground = 0xff000000,
    this.background = 0xffffffff,
    this.size = 1024,
    this.quietZone = 4,
    this.eyes = 'square',
    this.modules = 'square',
    this.correction = 'L',
  });
  Color get ink => Color(foreground | 0xff000000);
  Color get paper => Color(background | 0xff000000);
  QrEyeStyle get eyeStyle => QrEyeStyle(
    color: ink,
    eyeShape: eyes == 'circle' ? QrEyeShape.circle : QrEyeShape.square,
  );
  QrDataModuleStyle get moduleStyle => QrDataModuleStyle(
    color: ink,
    dataModuleShape: modules == 'circle'
        ? QrDataModuleShape.circle
        : QrDataModuleShape.square,
  );
  int get errorLevel =>
      {
        'L': QrErrorCorrectLevel.L,
        'M': QrErrorCorrectLevel.M,
        'Q': QrErrorCorrectLevel.Q,
        'H': QrErrorCorrectLevel.H,
      }[correction] ??
      QrErrorCorrectLevel.L;
  double get contrast {
    final inkLuminance = ink.computeLuminance();
    final paperLuminance = paper.computeLuminance();
    final lighter = inkLuminance > paperLuminance
        ? inkLuminance
        : paperLuminance;
    final darker = inkLuminance < paperLuminance
        ? inkLuminance
        : paperLuminance;
    return (lighter + .05) / (darker + .05);
  }

  bool get readable => contrast >= 4.5;
  QrExportStyle copyWith({
    int? foreground,
    int? background,
    int? size,
    int? quietZone,
    String? eyes,
    String? modules,
    String? correction,
  }) => QrExportStyle(
    foreground: foreground ?? this.foreground,
    background: background ?? this.background,
    size: size ?? this.size,
    quietZone: quietZone ?? this.quietZone,
    eyes: eyes ?? this.eyes,
    modules: modules ?? this.modules,
    correction: correction ?? this.correction,
  );
  Map<String, dynamic> toMap() => {
    'foreground': foreground,
    'background': background,
    'size': size,
    'quietZone': quietZone,
    'eyes': eyes,
    'modules': modules,
    'correction': correction,
  };
  factory QrExportStyle.fromMap(Map map) {
    int number(String key, int fallback) =>
        (map[key] is num ? (map[key] as num).toInt() : fallback);
    final style = QrExportStyle(
      foreground: number('foreground', 0xff000000),
      background: number('background', 0xffffffff),
      size: number('size', 1024).clamp(512, 2048),
      quietZone: number('quietZone', 4).clamp(4, 12),
      eyes: map['eyes'] == 'circle' ? 'circle' : 'square',
      modules: map['modules'] == 'circle' ? 'circle' : 'square',
      correction: ['L', 'M', 'Q', 'H'].contains(map['correction'])
          ? map['correction']
          : 'L',
    );
    return style;
  }
}
