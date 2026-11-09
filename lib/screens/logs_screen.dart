import '../shared/widgets/theme_region.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/theme_provider.dart';
import '../core/providers/logger_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/subscription_provider.dart';
import '../core/providers/rules_provider.dart';
import '../core/providers/chains_provider.dart';
import '../core/models/proxies/proxy_config.dart';
import '../core/models/theme_config.dart';
import '../core/utils/ping_utils.dart';
import '../core/utils/ansi_parser.dart';
import '../core/utils/log_files.dart';
import '../shared/widgets/custom_notification.dart';
import '../shared/widgets/glass_dropdown.dart';
import '../core/localization/app_localizations.dart';

class _CurlOptions {
  final String method;
  final Map<String, String> headers;
  final String body;
  final Duration timeout;
  final bool followRedirects;
  final bool allowBadCertificate;

  const _CurlOptions(
    this.method,
    this.headers,
    this.body,
    this.timeout,
    this.followRedirects,
    this.allowBadCertificate,
  );
}

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;
  final TextEditingController _debugController = TextEditingController();
  final TextEditingController _paramsController = TextEditingController();
  final TextEditingController _redirectLimitController = TextEditingController(
    text: '5',
  );

  static const _outputChannel = MethodChannel(
    'pro.kaleert.nextlink/diagnostic_output',
  );
  String _diagnosticRequestId = '';
  bool _streamedDiagnostic = false;
  bool _isDebugging = false;
  bool _pingProbeStarted = false;
  Timer? _pingElapsedTimer;
  int _livePingElapsedMs = 0;
  String _pingDnsValue = '—';
  String _pingValue = '—';
  String _pingRulesValue = '—';
  String _pingRouteValue = '—';
  String? _pingError;
  bool _pingSucceeded = false;
  String _selectedTool = 'ping';
  String _selectedConfig = 'current';
  String _diagnosticOutput = '';
  int _selectedLogFilter = 0;
  final List<String> _logFilters = [
    'Весь лог',
    'Ядро (CORE)',
    'Туннель (TUN)',
    'Служебные (UI)',
    'Прочее',
  ];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _paramsController.text = '-c 4 -W 2';
    _outputChannel.setMethodCallHandler((call) async {
      if (mounted &&
          call.method == 'chunk' &&
          call.arguments['requestId'] == _diagnosticRequestId) {
        _streamedDiagnostic = true;
        _appendDiagnostic(call.arguments['text']?.toString() ?? '');
      }
    });
  }

  @override
  void dispose() {
    _outputChannel.setMethodCallHandler(null);
    _pingElapsedTimer?.cancel();
    _mainTabController.dispose();
    _debugController.dispose();
    _paramsController.dispose();
    _redirectLimitController.dispose();
    super.dispose();
  }

  Color _getTagColor(String tag) {
    final upperTag = tag.toUpperCase();
    switch (upperTag) {
      case 'CORE':
        return Colors.blueAccent;
      case 'TUN':
        return Colors.orangeAccent;
      case 'ROUTING':
        return Colors.purpleAccent;
      case 'SUBSCRIPTION':
        return Colors.greenAccent;
      case 'NETWORK':
        return Colors.redAccent;
      case 'UI':
        return Colors.pinkAccent;
      case 'INIT':
        return Colors.tealAccent;
      case 'SINGBOX':
        return Colors.cyanAccent;
      case 'XRAY':
        return Colors.indigoAccent;
      case 'DNS':
        return Colors.amberAccent;
      case 'PROXY':
        return Colors.deepOrangeAccent;
      default:
        final int hash = tag
            .split('')
            .fold(0, (prev, element) => prev + element.codeUnitAt(0));
        final List<Color> accentColors = [
          Colors.blueAccent,
          Colors.greenAccent,
          Colors.orangeAccent,
          Colors.purpleAccent,
          Colors.redAccent,
          Colors.pinkAccent,
          Colors.tealAccent,
          Colors.cyanAccent,
          Colors.amberAccent,
        ];
        return accentColors[hash % accentColors.length];
    }
  }

  List<String> _splitArguments(String input) {
    final matches = RegExp(r"""(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'|\S+)""")
        .allMatches(input);
    return matches.map((match) {
      var value = match.group(0)!;
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }).toList();
  }

  Uri _targetUri(String text) {
    final trimmed = text.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed;
    }
    return Uri.parse('https://$trimmed');
  }

  Future<void> _runNetworkTool(List<ProxyConfig> servers) async {
    final targetText = _debugController.text.trim();
    if (targetText.isEmpty) return;
    ProxyConfig? selectedServer;
    if (_selectedConfig != 'current') {
      for (final server in servers) {
        if (server.uniqueKey == _selectedConfig) {
          selectedServer = server;
          break;
        }
      }
    }
    if (_selectedConfig != 'current' && selectedServer == null) {
      setState(() => _diagnosticOutput = 'Выбранный конфиг больше недоступен.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isDebugging = true;
      _diagnosticRequestId = DateTime.now().microsecondsSinceEpoch.toString();
      _streamedDiagnostic = false;
      _livePingElapsedMs = 0;
      _pingProbeStarted = false;
      _pingDnsValue = '…';
      _pingValue = '…';
      _pingRulesValue = '…';
      _pingRouteValue = '…';
      _pingError = null;
      _pingSucceeded = false;
      _diagnosticOutput = _selectedTool == 'legacy_ping'
          ? 'Ping VPN\n'
          : '${_selectedTool.toUpperCase()} $targetText\n';
    });

    try {
      final settings = ref.read(settingsProvider);
      final arguments = _splitArguments(_paramsController.text);
      if (_selectedTool == 'legacy_ping') {
        ProxyConfig? targetServer = selectedServer;
        if (targetServer == null) {
          for (final server in servers) {
            if (server.isActive) {
              targetServer = server;
              break;
            }
          }
        }
        if (targetServer == null) {
          throw Exception(
            'Нет активного сервера. Выберите конфиг для проверки.',
          );
        }
        final mode = settings.pingType;
        ProxyChain? activeChain;
        if (_selectedConfig == 'current') {
          for (final chain in ref.read(chainsProvider)) {
            if (chain.isActive && chain.nodes.isNotEmpty) {
              activeChain = chain;
              break;
            }
          }
        }
        final rules = ref.read(rulesProvider);
        final targetUrl = _targetUri(targetText).toString();
        final targetHost = Uri.parse(targetUrl).host;
        setState(() {
          _pingDnsValue = '$targetHost → определяю IP…';
        });
        unawaited(_updateDirectDnsCard(targetHost));
        final route = _resolvePingRoute(
          targetServer,
          rules,
          targetUrl,
          activeChain: activeChain,
        );
        final arrow = route.lastIndexOf('→');
        setState(() {
          _pingRulesValue = arrow < 0 ? '—' : route.substring(0, arrow).trim();
          _pingRouteValue = _normalizeRouteTag(
            arrow < 0 ? route : route.substring(arrow + 1),
          );
        });
        _appendDiagnostic(
          'Сервер: ${targetServer.name}\nРежим: $mode\nURL проверки: $targetUrl\n\nПроверяю маршрут…\n',
        );
        final result = await PingUtils.pingServerEx(
          targetServer,
          settings,
          customRules: rules,
          activeChain: activeChain,
          targetUrl: targetUrl,
          redirectLimit:
              int.tryParse(_redirectLimitController.text.trim())
                  ?.clamp(0, 50) ??
              5,
          onProbeStart: () {
            _pingProbeStarted = true;
            _startPingElapsedTimer();
          },
        );
        _pingElapsedTimer?.cancel();
        _pingElapsedTimer = null;
        _livePingElapsedMs = result.isSuccess ? result.latencyMs : 0;
        _pingSucceeded = result.isSuccess;
        _pingValue = result.isSuccess ? '${result.latencyMs} мс' : 'Ошибка';
        _pingError = result.error;
        _diagnosticOutput += result.isSuccess
            ? 'Итоговый пинг: ${result.latencyMs} мс\nИтоговый маршрут: $route'
            : 'Маршрут: $route\nПинг не прошёл: ${result.error ?? 'неизвестная ошибка'}';
      } else if (_selectedTool == 'ping') {
        if (selectedServer != null) {
          final uri = _targetUri(targetText);
          final count = _optionInt(arguments, '-c', fallback: 4).clamp(1, 10);
          final timeoutSeconds = _optionInt(
            arguments,
            '-W',
            fallback: 2,
          ).clamp(1, 20);
          final result = await PingUtils.pingUrlViaConfig(
            selectedServer,
            settings,
            uri,
            timeout: Duration(seconds: timeoutSeconds),
            probeCount: count,
          );
          if (!result.isSuccess)
            throw Exception(result.error ?? 'Проверка не прошла');
          _diagnosticOutput =
              'HTTP ${uri.host} через ${selectedServer.name}\n${result.samples.join(' ms, ')} ms';
        } else {
          final uri = _targetUri(targetText);
          final host = uri.host;
          final result = await const MethodChannel('pro.kaleert.nextlink/vpn')
              .invokeMapMethod<String, dynamic>('runNetworkDiagnostic', {
                'tool': 'ping',
                'requestId': _diagnosticRequestId,
                'host': host,
                'args': arguments.isEmpty ? ['-c', '4', '-W', '2'] : arguments,
                'timeoutSeconds': 20,
              });
          final output = (result?['output'] as String? ?? '').trim();
          if (!_streamedDiagnostic)
            _appendDiagnostic(output.isEmpty ? 'Нет ответа от ping.' : output);
        }
      } else {
        final uri = _targetUri(targetText);
        final nativeCurl =
            Platform.isAndroid &&
            await const MethodChannel('pro.kaleert.nextlink/vpn')
                    .invokeMethod<bool>('hasNativeCurl') ==
                true;
        if (nativeCurl) {
          Future<HttpProbeResult> execute(int? proxyPort) async {
            final result = await const MethodChannel('pro.kaleert.nextlink/vpn')
                .invokeMapMethod<String, dynamic>('runNetworkDiagnostic', {
                  'tool': 'curl',
                  'host': uri.toString(),
                  'args': arguments,
                  'timeoutSeconds': 90,
                  'requestId': _diagnosticRequestId,
                  if (proxyPort != null) 'proxyPort': proxyPort,
                });
            if (!_streamedDiagnostic)
              _appendDiagnostic(result?['output']?.toString() ?? '');
            _appendDiagnostic(
              '\ncurl: код завершения ${result?['exitCode']}\n',
            );
            return const HttpProbeResult(
              statusCode: 0,
              latencyMs: 0,
              body: '',
              headers: {},
            );
          }

          if (selectedServer != null) {
            await PingUtils.httpRequestViaConfig(
              server: selectedServer,
              settings: settings,
              uri: uri,
              withReadyProxy: (port) => execute(port),
            );
          } else {
            final running =
                await const MethodChannel('pro.kaleert.nextlink/vpn')
                    .invokeMethod<bool>('isRunning') ==
                true;
            await execute(running ? settings.httpPort : null);
          }
        } else {
          _appendDiagnostic(
            'Системный curl отсутствует; используется HTTP-клиент с ограниченным набором параметров.\n',
          );
          final curlOptions = _parseCurlOptions(arguments);
          final result = selectedServer == null
              ? await _httpRequestCurrentVpn(uri, curlOptions)
              : await PingUtils.httpRequestViaConfig(
                  server: selectedServer,
                  settings: settings,
                  uri: uri,
                  method: curlOptions.method,
                  headers: curlOptions.headers,
                  body: curlOptions.body,
                  timeout: curlOptions.timeout,
                  followRedirects: curlOptions.followRedirects,
                  allowBadCertificate: curlOptions.allowBadCertificate,
                  onBodyChunk: _appendDiagnostic,
                  onResponseHeaders: (statusCode, headers) => _appendDiagnostic(
                    'HTTP $statusCode\n${headers.entries.map((e) => '${e.key}: ${e.value}').join('\n')}\n\n',
                  ),
                );
          final elapsed = result.latencyMs;
          _appendDiagnostic('\n${result.statusCode} · $elapsed ms\n');
        }
      }
    } catch (error) {
      _diagnosticOutput = error.toString().replaceFirst('Exception: ', '');
      if (_selectedTool == 'legacy_ping') {
        _pingError = error.toString().replaceFirst('Exception: ', '');
        _pingSucceeded = false;
        if (_pingValue == '…') _pingValue = 'Ошибка';
      }
    } finally {
      _pingElapsedTimer?.cancel();
      _pingElapsedTimer = null;
      if (mounted) setState(() => _isDebugging = false);
    }
  }

  void _startPingElapsedTimer() {
    final stopwatch = Stopwatch()..start();
    _pingElapsedTimer?.cancel();
    _pingElapsedTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(() => _livePingElapsedMs = stopwatch.elapsedMilliseconds);
    });
  }

  String _resolvePingRoute(
    ProxyConfig server,
    List<AppRule> rules,
    String targetUrl, {
    ProxyChain? activeChain,
  }) {
    final uri = Uri.tryParse(targetUrl);
    final host = uri?.host.toLowerCase() ?? '';
    final port = uri?.hasPort == true
        ? uri!.port
        : (uri?.scheme == 'https' ? 443 : 80);

    for (final rule in rules) {
      final value = rule.action == 'CHAIN' && rule.value.contains('=>')
          ? rule.value.substring(0, rule.value.indexOf('=>')).trim()
          : rule.value;
      final values = value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty);
      final matches = switch (rule.type) {
        'Domain Keyword' => values.any(
          (item) => host.contains(item.toLowerCase()),
        ),
        'Port' => values.map(int.tryParse).whereType<int>().contains(port),
        _ => false,
      };
      if (matches) {
        return '${rule.type}: $value → ${_routeActionName(rule.action, server, activeChain)}';
      }
    }

    final raw = server.finalJson;
    final routing = raw['routing'] as Map? ?? raw['route'] as Map?;
    final rawRules = routing?['rules'];
    if (rawRules is List) {
      for (final item in rawRules) {
        if (item is! Map) continue;
        final conditions = <String>[];
        var matches = true;
        for (final entry in item.entries) {
          final key = entry.key.toString();
          final values = entry.value is List
              ? (entry.value as List).map((value) => value.toString()).toList()
              : [entry.value.toString()];
          if (key == 'port') {
            final portValues = values
                .expand((value) => value.split(','))
                .map((value) => value.trim());
            final portMatches = portValues.any((value) {
              final range = value.split('-').map(int.tryParse).toList();
              return range.first != null &&
                  range.last != null &&
                  port >= range.first! &&
                  port <= range.last!;
            });
            if (!portMatches) matches = false;
            conditions.add('port: ${portValues.join(', ')}');
          } else if (key == 'domain' ||
              key == 'domain_suffix' ||
              key == 'domain_keyword' ||
              key == 'domain_regex') {
            final domainMatches = values.any((condition) {
              final lowerCondition = condition.toLowerCase();
              if (lowerCondition.startsWith('geosite:')) return false;
              if (lowerCondition.startsWith('regexp:')) {
                try {
                  return RegExp(
                    condition.substring(7),
                    caseSensitive: false,
                  ).hasMatch(host);
                } catch (_) {
                  return false;
                }
              }
              if (key == 'domain_regex') {
                try {
                  return RegExp(condition, caseSensitive: false).hasMatch(host);
                } catch (_) {
                  return false;
                }
              }
              if (condition.startsWith('full:')) {
                return host == condition.substring(5).toLowerCase();
              }
              final normalized = condition
                  .replaceFirst(RegExp(r'^(full|domain|keyword|suffix):'), '')
                  .toLowerCase();
              return key == 'domain_keyword' || condition.startsWith('keyword:')
                  ? host.contains(normalized)
                  : host == normalized || host.endsWith('.$normalized');
            });
            if (!domainMatches) matches = false;
            conditions.add('$key: ${values.join(', ')}');
          } else if ({
            'outbound',
            'outboundTag',
            'action',
            'balancerTag',
            'server',
            'type',
          }.contains(key)) {
            continue;
          } else if ({
            'rule_set',
            'ruleSet',
            'geosite',
            'geoip',
            'ip',
          }.contains(key)) {
            conditions.add('$key: ${values.join(', ')}');
            matches = false;
          } else if (key == 'inbound' || key == 'inboundTag') {
            final inboundMatches = values.any(
              (value) => value == 'http' || value == 'socks',
            );
            if (!inboundMatches) matches = false;
            conditions.add('$key: ${values.join(', ')}');
          } else if (key == 'network') {
            final networkMatches = values.any(
              (value) => value.toLowerCase().contains('tcp'),
            );
            if (!networkMatches) matches = false;
            conditions.add('network: ${values.join(', ')}');
          } else {
            matches = false;
            conditions.add('$key: ${values.join(', ')}');
          }
        }
        if (matches && conditions.isNotEmpty) {
          final action =
              item['outboundTag'] ??
              item['outbound'] ??
              item['action'] ??
              'default';
          return '${conditions.join('; ')} → ${_routeActionName(action.toString(), server, activeChain)}';
        }
      }
    }

    final defaultOutbound = routing?['final']?.toString();
    if (defaultOutbound != null && defaultOutbound.isNotEmpty) {
      return _routeActionName(defaultOutbound, server, activeChain);
    }
    return defaultOutbound == null || defaultOutbound.isEmpty
        ? 'proxy'
        : _routeActionName(defaultOutbound, server, activeChain);
  }

  Future<void> _updateDirectDnsCard(String host) async {
    try {
      final addresses = Platform.isAndroid
          ? await const MethodChannel('pro.kaleert.nextlink/vpn')
                .invokeListMethod<String>('resolveHostDirect', {'host': host})
                .timeout(const Duration(seconds: 8))
          : (await InternetAddress.lookup(host)
                    .timeout(const Duration(seconds: 8)))
                .map((address) => address.address)
                .toList();
      if (!mounted) return;
      setState(() {
        _pingDnsValue = '$host → ${addresses?.join(', ') ?? 'IP не найден'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pingDnsValue =
            '$host → DNS ошибка: ${error.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  String _normalizeRouteTag(String route) {
    final normalized = route.toLowerCase();
    if (normalized.contains('direct') || normalized.contains('freedom')) {
      return 'direct';
    }
    if (normalized.contains('block') || normalized.contains('blackhole')) {
      return 'block';
    }
    if (normalized.contains('inbound')) return 'inbound';
    return 'proxy';
  }

  String _routeActionName(
    String action,
    ProxyConfig server,
    ProxyChain? chain,
  ) {
    switch (action.toUpperCase()) {
      case 'DIRECT':
      case 'FREEDOM':
        return 'direct';
      case 'BLOCK':
      case 'BLACKHOLE':
        return 'block';
      case 'CHAIN':
        return chain?.name ?? action;
      case 'PROXY':
      case 'PROXY-1':
        return 'Proxy · ${chain?.name ?? server.name}';
      default:
        return action;
    }
  }

  void _appendDiagnostic(String chunk) {
    if (!mounted || chunk.isEmpty) return;
    setState(() {
      const maxLength = 1024 * 1024;
      _diagnosticOutput += chunk;
      if (_diagnosticOutput.length > maxLength) {
        _diagnosticOutput = _diagnosticOutput.substring(
          _diagnosticOutput.length - maxLength,
        );
      }
    });
  }

  int _optionInt(List<String> args, String option, {required int fallback}) {
    final index = args.indexOf(option);
    if (index < 0 || index + 1 >= args.length) return fallback;
    return int.tryParse(args[index + 1]) ?? fallback;
  }

  _CurlOptions _parseCurlOptions(List<String> args) {
    var method = 'GET';
    var body = '';
    var timeout = const Duration(seconds: 15);
    var followRedirects = false;
    var allowBadCertificate = false;
    final headers = <String, String>{'User-Agent': 'curl/8.0.0'};
    for (var index = 0; index < args.length; index++) {
      final option = args[index];
      String nextValue() {
        if (index + 1 >= args.length)
          throw FormatException('Нет значения для $option');
        return args[++index];
      }

      switch (option) {
        case '-I':
        case '--head':
          method = 'HEAD';
        case '-i':
        case '-v':
        case '-s':
        case '-S':
        // Headers are always shown; these flags do not change the request.
        case '-L':
        case '--location':
          followRedirects = true;
        case '-X':
        case '--request':
          method = nextValue().toUpperCase();
        case '-H':
        case '--header':
          final header = nextValue();
          final separator = header.indexOf(':');
          if (separator < 1)
            throw FormatException('Неверный заголовок: $header');
          headers[header.substring(0, separator).trim()] = header
              .substring(separator + 1)
              .trim();
        case '-A':
        case '--user-agent':
          headers['User-Agent'] = nextValue();
        case '-e':
        case '--referer':
          headers['Referer'] = nextValue();
        case '-u':
        case '--user':
          headers['Authorization'] =
              'Basic ${base64Encode(utf8.encode(nextValue()))}';
        case '-k':
        case '--insecure':
          allowBadCertificate = true;
        case '-d':
        case '--data':
        case '--data-raw':
          body = nextValue();
          if (method == 'GET') method = 'POST';
        case '-m':
        case '--max-time':
        case '--connect-timeout':
          timeout = Duration(
            seconds: (double.tryParse(nextValue()) ?? 15).ceil().clamp(1, 90),
          );
        default:
          throw FormatException('Параметр curl не поддержан: $option');
      }
    }
    return _CurlOptions(
      method,
      headers,
      body,
      timeout,
      followRedirects,
      allowBadCertificate,
    );
  }

  Future<HttpProbeResult> _httpRequestCurrentVpn(
    Uri uri,
    _CurlOptions options,
  ) async {
    final client = HttpClient()..connectionTimeout = options.timeout;
    if (options.allowBadCertificate) {
      client.badCertificateCallback = (_certificate, _host, _port) => true;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .openUrl(options.method, uri)
          .timeout(options.timeout);
      request.followRedirects = options.followRedirects;
      options.headers.forEach(request.headers.set);
      if (options.body.isNotEmpty) request.write(options.body);
      final response = await request.close().timeout(options.timeout);
      final headers = <String, String>{};
      response.headers.forEach(
        (name, values) => headers[name] = values.join(', '),
      );
      _appendDiagnostic(
        'HTTP ${response.statusCode}\n${headers.entries.map((e) => '${e.key}: ${e.value}').join('\n')}\n\n',
      );
      final body = StringBuffer();
      await for (final chunk
          in response.transform(utf8.decoder).timeout(options.timeout)) {
        _appendDiagnostic(chunk);
        if (body.length < 1024 * 1024) {
          final remaining = 1024 * 1024 - body.length;
          body.write(
            chunk.length <= remaining ? chunk : chunk.substring(0, remaining),
          );
        }
      }
      return HttpProbeResult(
        statusCode: response.statusCode,
        latencyMs: stopwatch.elapsedMilliseconds.clamp(1, 1 << 30),
        body: body.toString(),
        headers: headers,
      );
    } finally {
      stopwatch.stop();
      client.close(force: true);
    }
  }

  Widget _buildNetworkToolPane(
    ThemeConfig theme,
    AppLocalizations loc,
    List<ProxyConfig> servers,
  ) {
    final dnsCardValue = _pingDnsValue == '—'
        ? (_debugController.text.trim().isEmpty
              ? 'Домен → IP'
              : '${_targetUri(_debugController.text.trim()).host} → ожидание проверки')
        : _pingDnsValue;
    final configItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'current',
        child: ThemeRegion.auto(
          id: "widget_logs_screen_0",
          label: "Text · logs_screen.dart",
          child: Text(
            _selectedTool == 'ping'
                ? AppLocalizations.text(context, "Системный маршрут")
                : loc.translate('current_vpn'),
          ),
        ),
      ),
      ...servers.map(
        (server) => DropdownMenuItem(
          value: server.uniqueKey,
          child: ThemeRegion.auto(
            id: "widget_logs_screen_1",
            label: "Text · logs_screen.dart",
            child: Text(server.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    ];
    final toolLabels = {
      'legacy_ping': 'Ping VPN',
      'ping': 'Ping',
      'curl': 'curl',
    };
    final currentRouteSelected =
        !configItems.any((item) => item.value == _selectedConfig) ||
        _selectedConfig == 'current';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: ThemeRegion.auto(
        id: "widget_logs_screen_2",
        label: "Column · logs_screen.dart",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ThemeRegion.auto(
              id: "widget_logs_screen_3",
              label: "Row · logs_screen.dart",
              child: Row(
                children: toolLabels.entries.map((entry) {
                  final selected = entry.key == _selectedTool;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() {
                          _selectedTool = entry.key;
                          _paramsController.text = switch (entry.key) {
                            'legacy_ping' => '',
                            'ping' => '-c 4 -W 2',
                            _ => '-I -L -m 15',
                          };
                        }),
                        child: ThemeRegion.auto(
                          id: "widget_logs_screen_4",
                          label: "Container · logs_screen.dart",
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? theme.primary.withOpacity(0.16)
                                  : Colors.white.withOpacity(0.035),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? theme.primary.withOpacity(0.4)
                                    : Colors.white.withOpacity(0.05),
                              ),
                            ),
                            child: Center(
                              child: ThemeRegion.auto(
                                id: "widget_logs_screen_5",
                                label: "Text · logs_screen.dart",
                                child: Text(
                                  AppLocalizations.text(context, entry.value),
                                  style: TextStyle(
                                    color: selected
                                        ? theme.primary
                                        : theme.textDim,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            ThemeRegion.auto(
              id: "widget_logs_screen_6",
              label: "Row · logs_screen.dart",
              child: Row(
                children: [
                  ThemeRegion.auto(
                    id: "widget_logs_screen_7",
                    label: "Icon · logs_screen.dart",
                    child: Icon(
                      Icons.route_rounded,
                      color: theme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ThemeRegion.auto(
                    id: "widget_logs_screen_8",
                    label: "Text · logs_screen.dart",
                    child: Text(
                      loc.translate('route_via'),
                      style: TextStyle(color: theme.textDim, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  GlassDropdown<String>(
                    value:
                        configItems.any((item) => item.value == _selectedConfig)
                        ? _selectedConfig
                        : 'current',
                    items: configItems,
                    surfaceColor: theme.surface,
                    accentColor: theme.primary,
                    onChanged: (value) =>
                        setState(() => _selectedConfig = value ?? 'current'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _buildToolTextField(
                _debugController,
                _selectedTool == 'legacy_ping'
                    ? 'Домен для проверки, например google.com'
                    : loc.translate('target_host_hint'),
                theme,
              ),
            ),
            if (_selectedTool == 'legacy_ping') ...[
              const SizedBox(height: 8),
              _buildToolTextField(
                _redirectLimitController,
                'redirectLimit',
                theme,
              ),
            ],
            if (_selectedTool != 'legacy_ping') ...[
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 4),
                child: ThemeRegion.auto(
                  id: "widget_logs_screen_9",
                  label: "Text · logs_screen.dart",
                  child: Text(
                    _selectedTool == 'ping' && !currentRouteSelected
                        ? AppLocalizations.text(
                            context,
                            "Через выбранный конфиг выполняется HTTP-проверка, а не ICMP.",
                          )
                        : _selectedTool == 'ping'
                        ? AppLocalizations.text(
                            context,
                            "Системный ICMP вне HTTP/SOCKS-прокси. Для проверки туннеля используйте Ping VPN.",
                          )
                        : currentRouteSelected
                        ? loc.translate('current_vpn_rules_note')
                        : loc.translate('selected_config_note'),
                    style: TextStyle(color: theme.textDim, fontSize: 10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 8),
              _buildToolTextField(
                _paramsController,
                loc.translate('extra_parameters'),
                theme,
              ),
            ],
            const SizedBox(height: 10),
            ThemeRegion.auto(
              id: "widget_logs_screen_10",
              label: "FilledButton · logs_screen.dart",
              child: FilledButton.icon(
                onPressed: _isDebugging ? null : () => _runNetworkTool(servers),
                icon: ThemeRegion.auto(
                  id: "widget_logs_screen_11",
                  label: "Icon · logs_screen.dart",
                  child: const Icon(Icons.play_arrow_rounded, size: 18),
                ),
                label: ThemeRegion.auto(
                  id: "widget_logs_screen_12",
                  label: "Text · logs_screen.dart",
                  child: Text(loc.translate('run_diagnostic')),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary.withOpacity(0.15),
                  foregroundColor: theme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _selectedTool == 'legacy_ping'
                  ? SingleChildScrollView(
                      child: ThemeRegion.auto(
                        id: "widget_logs_screen_14",
                        label: "Column · logs_screen.dart",
                        child: Column(
                          children: [
                            _buildPingResultCard(
                              theme,
                              'DNS',
                              dnsCardValue,
                              Icons.dns_rounded,
                            ),
                            _buildPingResultCard(
                              theme,
                              'PING',
                              _isDebugging
                                  ? (_pingProbeStarted
                                        ? '$_livePingElapsedMs мс'
                                        : 'Запуск ядра…')
                                  : (_pingError ?? _pingValue),
                              Icons.speed_rounded,
                              animate: _isDebugging && _pingProbeStarted,
                            ),
                            _buildPingResultCard(
                              theme,
                              'Правила',
                              _pingRulesValue,
                              Icons.rule_rounded,
                            ),
                            _buildPingResultCard(
                              theme,
                              'Маршрут',
                              _pingRouteValue,
                              Icons.alt_route_rounded,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ThemeRegion.auto(
                      id: "widget_logs_screen_15",
                      label: "Container · logs_screen.dart",
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                        child: _diagnosticOutput.isEmpty
                            ? Center(
                                child: ThemeRegion.auto(
                                  id: "widget_logs_screen_16",
                                  label: "Text · logs_screen.dart",
                                  child: Text(
                                    loc.translate('enter_address_trace'),
                                    style: TextStyle(
                                      color: theme.textDim.withOpacity(0.65),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOut,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0, 0.025),
                                            end: Offset.zero,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child: SelectableText(
                                    _diagnosticOutput,
                                    key: ValueKey(_diagnosticOutput),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPingResultCard(
    ThemeConfig theme,
    String title,
    String value,
    IconData icon, {
    bool animate = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.surface.withOpacity(0.34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: ThemeRegion.auto(
        id: "widget_logs_screen_17",
        label: "Row · logs_screen.dart",
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThemeRegion.auto(
              id: "widget_logs_screen_18",
              label: "Icon · logs_screen.dart",
              child: Icon(icon, color: theme.primary, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: ThemeRegion.auto(
                id: "widget_logs_screen_19",
                label: "Column · logs_screen.dart",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThemeRegion.auto(
                      id: "widget_logs_screen_20",
                      label: "Text · logs_screen.dart",
                      child: Text(
                        AppLocalizations.text(context, title),
                        style: TextStyle(
                          color: theme.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: ThemeRegion.auto(
                        id: "widget_logs_screen_21",
                        label: "Text · logs_screen.dart",
                        child: Text(
                          value,
                          key: ValueKey('$title:$value'),
                          style: TextStyle(
                            color:
                                title == 'Маршрут' && value.startsWith('block')
                                ? Colors.redAccent
                                : theme.text,
                            fontSize: title == 'PING' ? 16 : 13,
                            fontWeight: title == 'PING'
                                ? FontWeight.w700
                                : FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (animate)
              ThemeRegion.auto(
                    id: "widget_logs_screen_22",
                    label: "Icon · logs_screen.dart",
                    child: Icon(Icons.circle, size: 7, color: theme.primary),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .fade(begin: 0.3, end: 1, duration: 650.ms)
                  .scale(
                    begin: const Offset(0.85, 0.85),
                    end: const Offset(1.15, 1.15),
                    duration: 650.ms,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolTextField(
    TextEditingController controller,
    String hint,
    ThemeConfig theme,
  ) {
    return ThemeRegion.auto(
      id: "widget_logs_screen_23",
      label: "TextField · logs_screen.dart",
      child: TextField(
        controller: controller,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
        decoration: InputDecoration(
          hintText: AppLocalizations.text(context, hint),
          hintStyle: TextStyle(
            color: theme.textDim.withOpacity(0.65),
            fontSize: 12,
          ),
          isDense: true,
          filled: true,
          fillColor: theme.surface.withOpacity(0.3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
      ),
    );
  }

  Future<void> _saveLogsToFile() async {
    HapticFeedback.mediumImpact();
    try {
      final loc = AppLocalizations.of(context)!;
      final saved = await ref
          .read(loggerProvider.notifier)
          .saveSnapshot(
            appLogsTitle: loc.translate('app_logs'),
            crashLogTitle: loc.translate('crash_log'),
            noCrashesText: loc.translate('no_crashes_yet'),
          );
      if (mounted) {
        CustomNotification.show(
          context,
          '${loc.translate('logs_saved')}: ${saved.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        CustomNotification.show(
          context,
          '${loc.translate('error')}: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _showSavedLogFiles() async {
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    var files = await LogFiles.listFiles();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: ThemeRegion.auto(
                id: "widget_logs_screen_24",
                label: "Container · logs_screen.dart",
                child: Container(
                  height: MediaQuery.sizeOf(sheetContext).height * 0.75,
                  decoration: BoxDecoration(
                    color: theme.surface.withOpacity(0.3),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: ThemeRegion.auto(
                    id: "widget_logs_screen_25",
                    label: "Column · logs_screen.dart",
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                          child: ThemeRegion.auto(
                            id: "widget_logs_screen_26",
                            label: "Row · logs_screen.dart",
                            child: Row(
                              children: [
                                Expanded(
                                  child: ThemeRegion.auto(
                                    id: "widget_logs_screen_27",
                                    label: "Text · logs_screen.dart",
                                    child: Text(
                                      loc.translate('log_files'),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                ThemeRegion.auto(
                                  id: "widget_logs_screen_28",
                                  label: "IconButton · logs_screen.dart",
                                  child: IconButton(
                                    onPressed: () async {
                                      final refreshed =
                                          await LogFiles.listFiles();
                                      if (sheetContext.mounted) {
                                        setSheetState(() => files = refreshed);
                                      }
                                    },
                                    icon: ThemeRegion.auto(
                                      id: "widget_logs_screen_29",
                                      label: "Icon · logs_screen.dart",
                                      child: Icon(
                                        Icons.refresh_rounded,
                                        color: theme.textDim,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        Expanded(
                          child: files.isEmpty
                              ? Center(
                                  child: ThemeRegion.auto(
                                    id: "widget_logs_screen_30",
                                    label: "Text · logs_screen.dart",
                                    child: Text(
                                      loc.translate('no_log_files'),
                                      style: TextStyle(color: theme.textDim),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: files.length,
                                  itemBuilder: (context, index) {
                                    final entry = files[index];
                                    final size = entry.sizeBytes < 1024 * 1024
                                        ? '${(entry.sizeBytes / 1024).toStringAsFixed(1)} KB'
                                        : '${(entry.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                                    return Material(
                                      color: Colors.transparent,
                                      child: ThemeRegion.auto(
                                        id: "widget_logs_screen_31",
                                        label: "ListTile · logs_screen.dart",
                                        child: ListTile(
                                          leading: ThemeRegion.auto(
                                            id: "widget_logs_screen_32",
                                            label: "Icon · logs_screen.dart",
                                            child: Icon(
                                              entry.isManualSnapshot
                                                  ? Icons.save_alt_rounded
                                                  : Icons.description_outlined,
                                              color: theme.primary,
                                            ),
                                          ),
                                          title: ThemeRegion.auto(
                                            id: "widget_logs_screen_33",
                                            label: "Text · logs_screen.dart",
                                            child: Text(
                                              entry.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          subtitle: ThemeRegion.auto(
                                            id: "widget_logs_screen_34",
                                            label: "Text · logs_screen.dart",
                                            child: Text(
                                              '$size · ${entry.modifiedAt}',
                                            ),
                                          ),
                                          onTap: () async {
                                            try {
                                              final content =
                                                  await LogFiles.readFile(
                                                    entry,
                                                  );
                                              if (!sheetContext.mounted ||
                                                  !mounted)
                                                return;
                                              Navigator.pop(sheetContext);
                                              _showLogFileContent(
                                                entry.name,
                                                content,
                                              );
                                            } catch (error) {
                                              if (sheetContext.mounted) {
                                                CustomNotification.show(
                                                  this.context,
                                                  '${loc.translate('error')}: $error',
                                                  isError: true,
                                                );
                                              }
                                            }
                                          },
                                          trailing: ThemeRegion.auto(
                                            id: "widget_logs_screen_35",
                                            label: "Row · logs_screen.dart",
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ThemeRegion.auto(
                                                  id: "widget_logs_screen_36",
                                                  label: "IconButton · logs_screen.dart",
                                                  child: IconButton(
                                                    tooltip: loc.translate(
                                                      'share_file',
                                                    ),
                                                    onPressed: () async {
                                                      try {
                                                        await LogFiles.shareFiles(
                                                          [entry],
                                                          chooserTitle: loc
                                                              .translate(
                                                                'share_logs',
                                                              ),
                                                        );
                                                      } catch (error) {
                                                        if (mounted) {
                                                          CustomNotification.show(
                                                            this.context,
                                                            '${loc.translate('error')}: $error',
                                                            isError: true,
                                                          );
                                                        }
                                                      }
                                                    },
                                                    icon: ThemeRegion.auto(
                                                      id: "widget_logs_screen_37",
                                                      label: "Icon · logs_screen.dart",
                                                      child: const Icon(
                                                        Icons.ios_share_rounded,
                                                        size: 19,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                ThemeRegion.auto(
                                                  id: "widget_logs_screen_38",
                                                  label: "IconButton · logs_screen.dart",
                                                  child: IconButton(
                                                    tooltip: loc.translate(
                                                      'delete_file',
                                                    ),
                                                    onPressed: () async {
                                                      try {
                                                        await LogFiles.deleteFile(
                                                          entry,
                                                        );
                                                        if (sheetContext
                                                            .mounted) {
                                                          setSheetState(
                                                            () => files.remove(
                                                              entry,
                                                            ),
                                                          );
                                                        }
                                                      } catch (error) {
                                                        if (mounted) {
                                                          CustomNotification.show(
                                                            this.context,
                                                            '${loc.translate('error')}: $error',
                                                            isError: true,
                                                          );
                                                        }
                                                      }
                                                    },
                                                    icon: ThemeRegion.auto(
                                                      id: "widget_logs_screen_39",
                                                      label: "Icon · logs_screen.dart",
                                                      child: const Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        size: 19,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogFileContent(String name, String contents) {
    final theme = ref.read(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    showDialog<void>(
      useRootNavigator: false,
      context: context,
      barrierColor: Colors.black.withOpacity(0.18),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: ThemeRegion.auto(
              id: "widget_logs_screen_40",
              label: "Container · logs_screen.dart",
              child: Container(
                width: 760,
                height: MediaQuery.sizeOf(dialogContext).height * 0.86,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  color: theme.surface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: ThemeRegion.auto(
                  id: "widget_logs_screen_41",
                  label: "Column · logs_screen.dart",
                  child: Column(
                    children: [
                      ThemeRegion.auto(
                        id: "widget_logs_screen_42",
                        label: "Row · logs_screen.dart",
                        child: Row(
                          children: [
                            Expanded(
                              child: ThemeRegion.auto(
                                id: "widget_logs_screen_43",
                                label: "Text · logs_screen.dart",
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            ThemeRegion.auto(
                              id: "widget_logs_screen_44",
                              label: "IconButton · logs_screen.dart",
                              child: IconButton(
                                tooltip: loc.translate('share_file'),
                                onPressed: () async {
                                  try {
                                    final entries = await LogFiles.listFiles();
                                    final matches = entries
                                        .where((e) => e.name == name)
                                        .toList();
                                    if (matches.isNotEmpty) {
                                      await LogFiles.shareFiles(
                                        [matches.first],
                                        chooserTitle: loc.translate(
                                          'share_logs',
                                        ),
                                      );
                                    }
                                  } catch (error) {
                                    if (mounted) {
                                      CustomNotification.show(
                                        this.context,
                                        '${loc.translate('error')}: $error',
                                        isError: true,
                                      );
                                    }
                                  }
                                },
                                icon: ThemeRegion.auto(
                                  id: "widget_logs_screen_45",
                                  label: "Icon · logs_screen.dart",
                                  child: const Icon(Icons.ios_share_rounded),
                                ),
                              ),
                            ),
                            ThemeRegion.auto(
                              id: "widget_logs_screen_46",
                              label: "IconButton · logs_screen.dart",
                              child: IconButton(
                                tooltip: loc.translate('delete_file'),
                                onPressed: () async {
                                  try {
                                    final entries = await LogFiles.listFiles();
                                    final matches = entries
                                        .where((e) => e.name == name)
                                        .toList();
                                    if (matches.isNotEmpty) {
                                      await LogFiles.deleteFile(matches.first);
                                    }
                                    if (dialogContext.mounted)
                                      Navigator.pop(dialogContext);
                                  } catch (error) {
                                    if (mounted) {
                                      CustomNotification.show(
                                        this.context,
                                        '${loc.translate('error')}: $error',
                                        isError: true,
                                      );
                                    }
                                  }
                                },
                                icon: ThemeRegion.auto(
                                  id: "widget_logs_screen_47",
                                  label: "Icon · logs_screen.dart",
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                ),
                              ),
                            ),
                            ThemeRegion.auto(
                              id: "widget_logs_screen_48",
                              label: "IconButton · logs_screen.dart",
                              child: IconButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: ThemeRegion.auto(
                                  id: "widget_logs_screen_49",
                                  label: "Icon · logs_screen.dart",
                                  child: const Icon(Icons.close_rounded),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white10),
                      Expanded(
                        child: SelectionArea(
                          child: SingleChildScrollView(
                            child: SizedBox(
                              width: double.infinity,
                              child: SelectableText(
                                contents,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(loggerProvider);
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final servers = ref
        .watch(subscriptionProvider)
        .expand((sub) => sub.servers)
        .toList();

    final List<String> logFilters = [
      loc.translate('all_logs'),
      loc.translate('core_tag'),
      loc.translate('tunnel_tag'),
      loc.translate('ui_tag'),
      loc.translate('other'),
    ];

    final List<LogEntry> filteredLogs;
    if (_selectedLogFilter == 0) {
      filteredLogs = logs;
    } else {
      String filterTag = '';
      if (_selectedLogFilter == 1) filterTag = 'CORE';
      if (_selectedLogFilter == 2) filterTag = 'TUN';
      if (_selectedLogFilter == 3) filterTag = 'UI';

      if (filterTag.isEmpty) {
        filteredLogs = logs
            .where((l) => !['CORE', 'TUN', 'UI'].contains(l.tag.toUpperCase()))
            .toList();
      } else {
        filteredLogs = logs
            .where((l) => l.tag.toUpperCase() == filterTag)
            .toList();
      }
    }

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_diagnostics',
        child: ThemeRegion.auto(
          id: "widget_logs_screen_50",
          label: "Stack · logs_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: -100,
                right: 50,
                child: ThemeRegion.auto(
                  id: "widget_logs_screen_51",
                  label: "Container · logs_screen.dart",
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.meshIdle1,
                    ),
                  ),
                ),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: ThemeRegion.auto(
                  id: "widget_logs_screen_52",
                  label: "Container · logs_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),

              SafeArea(
                child: ThemeRegion.auto(
                  id: "widget_logs_screen_53",
                  label: "Column · logs_screen.dart",
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        child: ThemeRegion.auto(
                          id: "widget_logs_screen_54",
                          label: "Row · logs_screen.dart",
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(context);
                                },
                                child: ThemeRegion.auto(
                                  id: "widget_logs_screen_55",
                                  label: "Container · logs_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.surface.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_logs_screen_56",
                                      label: "Icon · logs_screen.dart",
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: theme.text,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ThemeRegion.auto(
                                  id: "widget_logs_screen_57",
                                  label: "Text · logs_screen.dart",
                                  child: Text(
                                    loc.translate('diagnostics'),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: loc.translate('save_logs'),
                                child: GestureDetector(
                                  onTap: _saveLogsToFile,
                                  child: ThemeRegion.auto(
                                    id: "widget_logs_screen_58",
                                    label: "Container · logs_screen.dart",
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.surface.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white10,
                                        ),
                                      ),
                                      child: ThemeRegion.auto(
                                        id: "widget_logs_screen_59",
                                        label: "Icon · logs_screen.dart",
                                        child: Icon(
                                          Icons.save_alt_rounded,
                                          color: theme.textDim,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: loc.translate('log_files'),
                                child: GestureDetector(
                                  onTap: _showSavedLogFiles,
                                  child: ThemeRegion.auto(
                                    id: "widget_logs_screen_60",
                                    label: "Container · logs_screen.dart",
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.surface.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white10,
                                        ),
                                      ),
                                      child: ThemeRegion.auto(
                                        id: "widget_logs_screen_61",
                                        label: "Icon · logs_screen.dart",
                                        child: Icon(
                                          Icons.folder_open_rounded,
                                          color: theme.textDim,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  ref.read(loggerProvider.notifier).clear();
                                },
                                child: ThemeRegion.auto(
                                  id: "widget_logs_screen_62",
                                  label: "Container · logs_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.surface.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_logs_screen_63",
                                      label: "Icon · logs_screen.dart",
                                      child: Icon(
                                        Icons.delete_sweep_rounded,
                                        color: theme.textDim,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fade().slideY(begin: -0.2),

                      ThemeRegion.auto(
                        id: "widget_logs_screen_64",
                        label: "Container · logs_screen.dart",
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.surface.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: TabBar(
                            controller: _mainTabController,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: theme.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.primary.withOpacity(0.5),
                              ),
                            ),
                            labelColor: theme.primary,
                            unselectedLabelColor: theme.textDim,
                            dividerColor: Colors.transparent,
                            labelPadding: EdgeInsets.zero,
                            tabs: [
                              Tab(
                                child: ThemeRegion.auto(
                                  id: "widget_logs_screen_65",
                                  label: "Text · logs_screen.dart",
                                  child: Text(
                                    loc.translate('journal'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              Tab(
                                child: ThemeRegion.auto(
                                  id: "widget_logs_screen_66",
                                  label: "Text · logs_screen.dart",
                                  child: Text(
                                    loc.translate('network_tools'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fade(delay: 100.ms),

                      Expanded(
                        child: TabBarView(
                          controller: _mainTabController,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            ThemeRegion.auto(
                              id: "widget_logs_screen_67",
                              label: "Column · logs_screen.dart",
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 40,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      itemCount: logFilters.length,
                                      itemBuilder: (context, index) {
                                        final isSelected =
                                            _selectedLogFilter == index;
                                        return GestureDetector(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setState(
                                              () => _selectedLogFilter = index,
                                            );
                                          },
                                          child: ThemeRegion.auto(
                                            id: "widget_logs_screen_68",
                                            label:
                                                "Container · logs_screen.dart",
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? Colors.white.withOpacity(
                                                        0.1,
                                                      )
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? Colors.white24
                                                      : Colors.transparent,
                                                ),
                                              ),
                                              child: Center(
                                                child: ThemeRegion.auto(
                                                  id: "widget_logs_screen_69",
                                                  label:
                                                      "Text · logs_screen.dart",
                                                  child: Text(
                                                    logFilters[index],
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : theme.textDim,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Expanded(
                                    child: ThemeRegion.auto(
                                      id: "widget_logs_screen_70",
                                      label: "Container · logs_screen.dart",
                                      child: Container(
                                        margin: const EdgeInsets.fromLTRB(
                                          24,
                                          16,
                                          24,
                                          24,
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0A0A0A),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.05,
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.5,
                                              ),
                                              blurRadius: 20,
                                            ),
                                          ],
                                        ),
                                        child: filteredLogs.isEmpty
                                            ? Center(
                                                child: ThemeRegion.auto(
                                                  id: "widget_logs_screen_71",
                                                  label:
                                                      "Text · logs_screen.dart",
                                                  child: Text(
                                                    loc.translate('no_logs'),
                                                    style: TextStyle(
                                                      color: theme.textDim,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : ListView.builder(
                                                physics:
                                                    const BouncingScrollPhysics(),
                                                itemCount: filteredLogs.length,
                                                itemBuilder: (context, index) {
                                                  final log =
                                                      filteredLogs[index];
                                                  final tagColor = _getTagColor(
                                                    log.tag,
                                                  );
                                                  const textStyle = TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 11,
                                                    height: 1.4,
                                                    fontFamilyFallback: [
                                                      'Courier New',
                                                      'monospace',
                                                    ],
                                                  );

                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 4.0,
                                                        ),
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: textStyle,
                                                        children: [
                                                          TextSpan(
                                                            text:
                                                                '[${log.time}] ',
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white38,
                                                                ),
                                                          ),
                                                          TextSpan(
                                                            text:
                                                                '[${log.tag.toUpperCase()}]: ',
                                                            style: TextStyle(
                                                              color: tagColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                          ...AnsiParser.parse(
                                                            log.message,
                                                            baseStyle: textStyle
                                                                .copyWith(
                                                                  color: Colors
                                                                      .white70,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                      ),
                                    ),
                                  ).animate().fade(delay: 200.ms),
                                ],
                              ),
                            ),
                            _buildNetworkToolPane(theme, loc, servers),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
