import '../providers/settings_provider.dart';

/// LAN clients have their own authenticated HTTP listener. The TUN bridge and
/// diagnostics always use private loopback listeners without authentication.
class LanProxyInbounds {
  static void validate(SettingsState s) {
    if (s.lanPort < 1 || s.lanPort > 65535)
      throw const FormatException('Порт LAN должен быть от 1 до 65535');
    if ({
      s.httpPort,
      s.socksPort,
      s.httpPort + 2,
      s.socksPort + 2,
    }.contains(s.lanPort))
      throw const FormatException(
        'Порт LAN занят внутренним прокси или диагностикой',
      );
    if (s.lanUsername.isEmpty != s.lanPassword.isEmpty)
      throw const FormatException(
        'Укажите логин и пароль вместе или оставьте оба пустыми',
      );
  }

  static List<Map<String, dynamic>> singBox(
    SettingsState s, {
    bool isTest = false,
  }) {
    if (!s.lanConn || isTest) return [];
    validate(s);
    return [
      {
        'type': 'http',
        'tag': 'lan-http',
        'listen': '0.0.0.0',
        'listen_port': s.lanPort,
        if (s.lanUsername.isNotEmpty)
          'users': [
            {'username': s.lanUsername, 'password': s.lanPassword},
          ],
      },
    ];
  }

  static List<Map<String, dynamic>> xray(
    SettingsState s, {
    bool isTest = false,
  }) {
    if (!s.lanConn || isTest) return [];
    validate(s);
    return [
      {
        'protocol': 'http',
        'tag': 'lan-http',
        'listen': '0.0.0.0',
        'port': s.lanPort,
        'settings': {
          if (s.lanUsername.isNotEmpty)
            'accounts': [
              {'user': s.lanUsername, 'pass': s.lanPassword},
            ],
        },
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls'],
        },
      },
    ];
  }
}
