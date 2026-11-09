import '../models/proxies/proxy_config.dart';

/// Panel failures are often returned as HTTP 200 with a dummy VPN profile.
/// Never replace a working subscription with one of those profiles.
void validateSubscriptionResponse(
  Map<String, String> headers,
  List<ProxyConfig> servers,
) {
  bool enabled(String key) =>
      const {'1', 'true'}.contains(headers[key]?.toLowerCase());
  if (enabled('x-hwid-max-devices-reached') || enabled('x-hwid-limit')) {
    throw const FormatException(
      'Достигнут лимит устройств подписки. Удалите старое устройство у провайдера.',
    );
  }
  if (enabled('x-hwid-not-supported')) {
    throw const FormatException(
      'Провайдер требует HWID. Включите отправку HWID в настройках подписок и обновите подписку.',
    );
  }
  if (servers.isNotEmpty &&
      servers.every(
        (s) => RegExp(
          r'app not supported|client not supported|hwid not supported',
          caseSensitive: false,
        ).hasMatch(s.name),
      )) {
    throw const FormatException(
      'Провайдер отклонил клиент. Включите отправку HWID и проверьте User-Agent в настройках подписок.',
    );
  }
}
