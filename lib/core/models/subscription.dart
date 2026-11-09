// lib/core/models/subscription.dart

import 'proxies/proxy_config.dart';
import 'proxies/proxy_parser.dart'; // Добавили для парсера

class Subscription {
  final String id;
  final String name;
  final String url;
  final String updatedTime;
  final int upload;
  final int download;
  final int total;
  final int expireDate;
  final String tlsFingerprint;
  final String? _announcement;
  final Map<String, String> metadata;
  final List<ProxyConfig> servers;

  String get announcement => _announcement ?? '';

  /// Persist UTC timestamps, display them in the device's local timezone.
  /// Older versions only stored "Только что", which has no recoverable date.
  String get formattedUpdatedTime {
    final timestamp = DateTime.tryParse(updatedTime)?.toLocal();
    if (timestamp == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(timestamp.day)}.${two(timestamp.month)}.${timestamp.year} '
        '${two(timestamp.hour)}:${two(timestamp.minute)}';
  }

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.updatedTime,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expireDate = 0,
    this.tlsFingerprint = 'chrome',
    String? announcement,
    this.metadata = const {},
    required this.servers,
  }) : _announcement = announcement;

  double get usedGB => (upload + download) / (1024 * 1024 * 1024);
  double get totalGB => total / (1024 * 1024 * 1024);
  int get daysLeft {
    if (expireDate == 0) return -1;
    final expire = DateTime.fromMillisecondsSinceEpoch(expireDate * 1000);
    return expire.difference(DateTime.now()).inDays;
  }

  // --- ДОБАВЛЕНО ДЛЯ СОХРАНЕНИЯ В ПАМЯТЬ ---
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'updatedTime': updatedTime,
      'upload': upload,
      'download': download,
      'total': total,
      'expireDate': expireDate,
      'tlsFingerprint': tlsFingerprint,
      'announcement': announcement,
      'metadata': metadata,
      'servers': servers.map((s) => s.toMap()).toList(),
    };
  }

  static Subscription fromMap(Map<String, dynamic> map) {
    return Subscription(
      id: map['id'],
      name: map['name'],
      url: map['url'],
      updatedTime: map['updatedTime'] as String? ?? '',
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expireDate: map['expireDate'] ?? 0,
      tlsFingerprint: map['tlsFingerprint'] ?? 'chrome',
      announcement: map['announcement'] ?? '',
      metadata: (map['metadata'] as Map? ?? {}).map(
        (key, value) =>
            MapEntry(key.toString().toLowerCase(), value.toString()),
      ),
      servers: (map['servers'] as List? ?? [])
          .map((s) => ProxyParser.fromMap(s))
          .toList(),
    );
  }
}
