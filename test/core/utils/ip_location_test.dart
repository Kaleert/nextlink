import 'package:flutter_test/flutter_test.dart';
import 'package:nextlink/core/utils/ip_location.dart';

void main() {
  test('flags use country codes and unknown locations stay blank', () {
    expect(countryFlag('ru'), '🇷🇺');
    expect(countryFlag('GB'), '🇬🇧');
    for (final invalid in ['', 'USA', 'ZZ', 'XX', '12']) {
      expect(countryFlag(invalid), isEmpty);
    }
  });
  test('geolocation must belong to the actual queried IP', () {
    final valid = {
      'ip': '1.1.1.1',
      'success': true,
      'country_code': 'AU',
      'country': 'Australia',
    };
    expect(IpLocation.fromResponse('1.1.1.1', valid).countryCode, 'AU');
    expect(IpLocation.fromResponse('8.8.8.8', valid).countryCode, isEmpty);
    expect(
      IpLocation.fromResponse('1.1.1.1', {
        ...valid,
        'success': false,
      }).countryCode,
      isEmpty,
    );
  });
  test('geolocation caches countries per IP, not per server name', () async {
    final cache = IpLocationCache();
    var calls = 0;
    Future<Map<String, dynamic>> load(String ip) async {
      calls++;
      return {'success': true, 'ip': ip, 'country_code': 'AU'};
    }

    await cache.lookup('1.1.1.1', () => load('1.1.1.1'));
    await cache.lookup('1.1.1.1', () => throw StateError('cache missed'));
    await cache.lookup('8.8.8.8', () => load('8.8.8.8'));
    expect(calls, 2);
  });
}
