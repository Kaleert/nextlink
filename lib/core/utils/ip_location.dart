import 'country_flag_assets.dart';

import 'dart:io';

String countryFlag(String code) {
  final normalized = code.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalized) ||
      const {'ZZ', 'XX'}.contains(normalized))
    return '';
  return String.fromCharCodes(normalized.codeUnits.map((c) => c + 0x1f1a5));
}

class IpLocation {
  final String countryCode,
      country,
      city,
      ip,
      region,
      timezone,
      utc,
      callingCode,
      postal,
      isp;
  final double? latitude, longitude;
  const IpLocation({
    this.countryCode = '',
    this.country = '',
    this.city = '',
    this.ip = '',
    this.region = '',
    this.timezone = '',
    this.utc = '',
    this.callingCode = '',
    this.postal = '',
    this.isp = '',
    this.latitude,
    this.longitude,
  });
  bool get hasCoordinates => latitude != null && longitude != null;

  static double? _coordinate(dynamic value, double limit) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return number != null && number.isFinite && number.abs() <= limit
        ? number
        : null;
  }

  factory IpLocation.fromResponse(String ip, Map<String, dynamic> data) {
    if (data['success'] != true ||
        data['ip'] != ip ||
        InternetAddress.tryParse(ip) == null) {
      return const IpLocation();
    }
    final code = '${data['country_code'] ?? ''}'.toUpperCase();
    return IpLocation(
      countryCode: CountryFlagAssets.path(code) == null ? '' : code,
      country: '${data['country'] ?? ''}',
      city: '${data['city'] ?? ''}',
      ip: ip,
      region: '${data['region'] ?? ''}',
      latitude: _coordinate(data['latitude'], 90),
      longitude: _coordinate(data['longitude'], 180),
      timezone:
          '${data['timezone'] is Map ? data['timezone']['id'] ?? '' : ''}',
      utc: '${data['timezone'] is Map ? data['timezone']['utc'] ?? '' : ''}',
      callingCode: '${data['calling_code'] ?? ''}',
      postal: '${data['postal'] ?? ''}',
      isp:
          '${data['connection'] is Map ? data['connection']['isp'] ?? '' : ''}',
    );
  }
}

/// Cache countries by the actual external IP, never by a server's display name.
class IpLocationCache {
  final _cache = <String, (DateTime, IpLocation)>{};
  Future<IpLocation> lookup(
    String ip,
    Future<Map<String, dynamic>> Function() load,
  ) async {
    final cached = _cache[ip];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(hours: 6))
      return cached.$2;
    final location = IpLocation.fromResponse(ip, await load());
    if (location.countryCode.isNotEmpty) {
      if (_cache.length >= 64) _cache.remove(_cache.keys.first);
      _cache[ip] = (DateTime.now(), location);
    }
    return location;
  }
}
