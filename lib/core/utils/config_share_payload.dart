import 'dart:convert';

import 'package:archive/archive.dart';

import '../models/proxies/proxy_config.dart';
import '../models/proxies/wireguard_config.dart';
import '../models/subscription.dart';

class ConfigSharePayload {
  final String name;
  final String json;
  final String url;
  final String qr;
  final String? conf;
  const ConfigSharePayload({
    required this.name,
    required this.json,
    required this.url,
    required this.qr,
    this.conf,
  });

  factory ConfigSharePayload.server(ProxyConfig server) {
    final json = jsonEncode(server.finalJson);
    final original = server.toUri();
    final isLink = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(original);
    final direct = isLink && server.rawJsonOverride == null;
    final conf = server is WireGuardConfig && server.rawJsonOverride == null
        ? original
        : null;
    final content = conf ?? json;
    return ConfigSharePayload(
      name: server.name,
      json: json,
      url: direct ? original : importLink(content),
      qr: direct ? original : content,
      conf: conf,
    );
  }
  factory ConfigSharePayload.subscription(Subscription sub) =>
      ConfigSharePayload(
        name: sub.name,
        json: jsonEncode(sub.servers.map((s) => s.finalJson).toList()),
        url: sub.url,
        qr: sub.url,
      );

  static String importLink(String content) =>
      'nextlink://import/${base64Url.encode(utf8.encode(content)).replaceAll('=', '')}';

  static const maxQrDecodedBytes = 1024 * 1024;
  static String? compressedImportLink(String content) {
    if (content.length > maxQrDecodedBytes) return null;
    final bytes = utf8.encode(content);
    if (bytes.length > maxQrDecodedBytes) return null;
    final compressed = GZipEncoder().encode(bytes);
    return compressed == null
        ? null
        : 'nextlink://import-gzip/${base64Url.encode(compressed).replaceAll('=', '')}';
  }

  static List<int> _inflateQr(List<int> bytes) {
    if (bytes.length < 18) throw const FormatException('Повреждён сжатый QR');
    final input = InputStream(bytes);
    final output = _LimitedQrOutput(maxQrDecodedBytes);
    try {
      GZipDecoder().decodeStream(input, output);
      final data = output.getBytes();
      if (input.readUint32() != getCrc32(data) ||
          input.readUint32() != data.length ||
          !input.isEOS)
        throw const FormatException('Повреждён сжатый QR');
      return data;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён сжатый QR');
    }
  }

  /// Accept generated import links and plain subscription/protocol payloads.
  static String decodeQr(String raw) {
    var content = raw.trim();
    for (var i = 0; i < 3; i++) {
      final uri = Uri.tryParse(content);
      if (uri?.scheme != 'nextlink') return content;
      if (!['import', 'import-gzip'].contains(uri!.host) ||
          uri.pathSegments.length != 1) {
        throw const FormatException(
          'В QR должна быть подписка или конфигурация, а не команда управления VPN',
        );
      }
      if (uri.pathSegments.single.length > maxQrDecodedBytes * 2)
        throw const FormatException('Слишком большой QR для импорта');
      final bytes = base64Url.decode(
        base64Url.normalize(uri.pathSegments.single),
      );
      final decoded = uri.host == 'import-gzip' ? _inflateQr(bytes) : bytes;
      if (decoded.length > maxQrDecodedBytes)
        throw const FormatException('Слишком большой QR для импорта');
      content = utf8.decode(decoded).trim();
    }
    throw const FormatException('Слишком много вложенных ссылок импорта');
  }
}

class _LimitedQrOutput extends OutputStream {
  final int limit;
  _LimitedQrOutput(this.limit);
  void check(int count) {
    if (length + count > limit)
      throw const FormatException('Распакованный QR слишком большой');
  }

  @override
  void writeByte(int value) {
    check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    check(len ?? bytes.length);
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase input) {
    check(input.length);
    super.writeInputStream(input);
  }
}
