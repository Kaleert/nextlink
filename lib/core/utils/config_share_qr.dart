import 'dart:convert';

import 'package:qr_flutter/qr_flutter.dart';

import 'config_share_payload.dart';

class ConfigShareQr {
  final String data;
  final QrCode code;
  final bool compressed;
  ConfigShareQr._(this.data, this.code, this.compressed);
  static ConfigShareQr? _encode(
    String data, {
    bool compressed = false,
    int level = QrErrorCorrectLevel.L,
  }) {
    final limit =
        {
          QrErrorCorrectLevel.L: 2953,
          QrErrorCorrectLevel.M: 2331,
          QrErrorCorrectLevel.Q: 1663,
          QrErrorCorrectLevel.H: 1273,
        }[level] ??
        2953;
    if (data.length > limit || utf8.encode(data).length > limit) return null;
    try {
      final result = QrValidator.validate(
        data: data,
        errorCorrectionLevel: level,
      );
      final code = result.qrCode;
      if (result.status != QrValidationStatus.valid || code == null)
        return null;
      // qr 3.x chooses version 40 even for oversized input. Capacity is checked
      // lazily by dataCache, not by QrValidator.validate/fromData.
      if (code.dataCache.isEmpty) return null;
      return ConfigShareQr._(data, code, compressed);
    } on Exception {
      return null;
    }
  }

  static ConfigShareQr? prepare(
    String original, {
    int errorLevel = QrErrorCorrectLevel.L,
  }) {
    final plain = _encode(original, level: errorLevel);
    if (plain != null) return plain;
    final compressed = ConfigSharePayload.compressedImportLink(original);
    return compressed == null
        ? null
        : _encode(compressed, compressed: true, level: errorLevel);
  }
}
