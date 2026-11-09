import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/models/subscription.dart';

Subscription subscription(String updatedTime) => Subscription(
  id: 'test',
  name: 'Test',
  url: 'https://example.org/sub',
  updatedTime: updatedTime,
  servers: [],
);
void main() {
  test('update date survives persistence and displays in local time', () {
    final local = DateTime(2026, 11, 6, 13, 45);
    final original = subscription(local.toUtc().toIso8601String());
    final restored = Subscription.fromMap(
      jsonDecode(jsonEncode(original.toMap())),
    );
    expect(restored.updatedTime, original.updatedTime);
    expect(restored.formattedUpdatedTime, '06.11.2026 13:45');
  });
  test(
    'legacy relative labels never pretend to be the current update time',
    () {
      expect(subscription('Только что').formattedUpdatedTime, isEmpty);
      expect(subscription('').formattedUpdatedTime, isEmpty);
      final old = subscription('').toMap()..remove('updatedTime');
      expect(Subscription.fromMap(old).formattedUpdatedTime, isEmpty);
    },
  );
}
