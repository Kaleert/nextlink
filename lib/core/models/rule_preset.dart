import '../providers/rules_provider.dart';

class RulePreset {
  final String id, title, description;
  final List<AppRule> rules;
  const RulePreset(this.id, this.title, this.description, this.rules);

  static List<RulePreset> get all => [
    RulePreset(
      'ru_direct',
      'RU напрямую',
      'Домены .ru, .su и .рф и российские IP — Direct. Остальной трафик сохраняет текущие правила.',
      [
        AppRule(
          id: 'preset:ru-domains',
          type: 'Domain Suffix',
          value: 'ru,su,xn--p1ai',
          action: 'DIRECT',
          conditions: {
            'domain_suffix': ['ru', 'su', 'xn--p1ai'],
          },
        ),
        AppRule(
          id: 'preset:ru-ip',
          type: 'GeoIP',
          value: 'ru',
          action: 'DIRECT',
        ),
      ],
    ),
    RulePreset(
      'local_direct',
      'Локальная сеть напрямую',
      'Частные IPv4/IPv6-сети и localhost — Direct.',
      [
        AppRule(
          id: 'preset:local',
          type: 'IP CIDR',
          value: '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.0/8,fc00::/7,fe80::/10,::1/128',
          action: 'DIRECT',
          conditions: {
            'ip_cidr': [
              '10.0.0.0/8',
              '172.16.0.0/12',
              '192.168.0.0/16',
              '127.0.0.0/8',
              'fc00::/7',
              'fe80::/10',
              '::1/128',
            ],
          },
        ),
      ],
    ),
    RulePreset(
      'block_quic',
      'Блокировать QUIC',
      'Блокирует UDP/443. Приложения с поддержкой TCP смогут перейти на него.',
      [
        AppRule(
          id: 'preset:quic',
          type: 'UDP Port',
          value: '443',
          action: 'BLOCK',
          conditions: {
            'network': ['udp'],
            'port': ['443'],
          },
        ),
      ],
    ),
  ];
}
