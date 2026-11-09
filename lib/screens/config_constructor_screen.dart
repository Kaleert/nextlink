import '../shared/widgets/theme_region.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../shared/widgets/glass_dropdown.dart';
import '../core/theme/theme_provider.dart';
import '../core/models/theme_config.dart';
import '../core/localization/app_localizations.dart';
import '../core/models/proxies/proxy_config.dart';
import '../core/models/proxies/vless_config.dart';
import '../core/models/proxies/vmess_config.dart';
import '../core/models/proxies/hy2_config.dart';
import '../core/models/proxies/trojan_config.dart';
import '../core/models/proxies/ss_config.dart';

class ConfigConstructorScreen extends ConsumerStatefulWidget {
  final ProxyConfig? initialConfig;
  const ConfigConstructorScreen({super.key, this.initialConfig});

  @override
  ConsumerState<ConfigConstructorScreen> createState() =>
      _ConfigConstructorScreenState();
}

class _ConfigConstructorScreenState
    extends ConsumerState<ConfigConstructorScreen> {
  String selectedProtocol = 'VLESS';
  String selectedNetwork = 'tcp';
  String selectedTls = 'none';
  String selectedFlow = 'none'; // ДОБАВИЛИ СТЕЙТ ДЛЯ FLOW

  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _uuidCtrl = TextEditingController();

  final _sniCtrl = TextEditingController();
  final _pbkCtrl = TextEditingController();
  final _sidCtrl = TextEditingController(); // ДОБАВИЛИ СИД
  final _spxCtrl = TextEditingController(); // ДОБАВИЛИ SPIDER X
  final _fpCtrl = TextEditingController(text: 'chrome');
  final _hostCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _serviceNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialConfig != null) {
      final conf = widget.initialConfig!;
      _nameCtrl.text = conf.name;
      _addrCtrl.text = conf.address;
      _portCtrl.text = conf.port.toString();

      if (conf is VlessConfig) {
        selectedProtocol = 'VLESS';
        _uuidCtrl.text = conf.uuid;
        selectedNetwork =
            [
              'tcp',
              'kcp',
              'ws',
              'http',
              'grpc',
              'quic',
              'xhttp',
              'splithttp',
              'httpupgrade',
              'raw',
            ].contains(conf.network)
            ? conf.network
            : 'tcp';
        selectedTls = ['none', 'tls', 'reality'].contains(conf.security)
            ? conf.security
            : 'none';

        // Защита от кривого flow (если пусто - none)
        selectedFlow = conf.flow.isNotEmpty ? conf.flow : 'none';
        if (![
          'none',
          'xtls-rprx-vision',
          'xtls-rprx-vision-udp443',
        ].contains(selectedFlow)) {
          selectedFlow = 'none'; // Фолбэк
        }

        _sniCtrl.text = conf.sni;
        _pbkCtrl.text = conf.pbk;
        _sidCtrl.text = conf.sid;
        _spxCtrl.text = conf.spx;
        _fpCtrl.text = conf.fp.isNotEmpty ? conf.fp : 'chrome';
        _hostCtrl.text = conf.host;
        _pathCtrl.text = conf.path;
        _serviceNameCtrl.text = conf.serviceName;
      } else if (conf is VmessConfig) {
        selectedProtocol = 'VMess';
        _uuidCtrl.text = conf.uuid;
        selectedNetwork =
            ['tcp', 'kcp', 'ws', 'http', 'grpc', 'quic'].contains(conf.network)
            ? conf.network
            : 'tcp';
        selectedTls = ['none', 'tls', 'reality'].contains(conf.tls)
            ? conf.tls
            : 'none';
        _sniCtrl.text = conf.sni;
        _fpCtrl.text = conf.fp.isNotEmpty ? conf.fp : 'chrome';
        _hostCtrl.text = conf.host;
        _pathCtrl.text = conf.path;
      } else if (conf is TrojanConfig) {
        selectedProtocol = 'Trojan';
        _uuidCtrl.text = conf.password;
        selectedNetwork = ['tcp', 'ws', 'grpc'].contains(conf.network)
            ? conf.network
            : 'tcp';
        selectedTls = ['none', 'tls'].contains(conf.security)
            ? conf.security
            : 'tls';
        _sniCtrl.text = conf.sni;
        _fpCtrl.text = conf.fp.isNotEmpty ? conf.fp : 'chrome';
        _hostCtrl.text = conf.host;
        _pathCtrl.text = conf.path;
      } else if (conf is HysteriaConfig) {
        selectedProtocol = 'Hysteria2';
        _uuidCtrl.text = conf.password;
        _sniCtrl.text = conf.sni;
        _fpCtrl.text = conf.fp.isNotEmpty ? conf.fp : 'chrome';
        selectedNetwork = 'quic';
        selectedTls = 'tls';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _portCtrl.dispose();
    _uuidCtrl.dispose();
    _sniCtrl.dispose();
    _pbkCtrl.dispose();
    _sidCtrl.dispose();
    _spxCtrl.dispose();
    _fpCtrl.dispose();
    _hostCtrl.dispose();
    _pathCtrl.dispose();
    _serviceNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_config_editor',
        child: ThemeRegion.auto(
          id: "widget_config_constructor_screen_0",
          label: "Stack · config_constructor_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: 100,
                right: -150,
                child: ThemeRegion.auto(
                  id: "widget_config_constructor_screen_1",
                  label: "Container · config_constructor_screen.dart",
                  child: Container(
                    width: 400,
                    height: 400,
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
                  id: "widget_config_constructor_screen_2",
                  label: "Container · config_constructor_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),

              SafeArea(
                child: ThemeRegion.auto(
                  id: "widget_config_constructor_screen_3",
                  label: "Column · config_constructor_screen.dart",
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        child: ThemeRegion.auto(
                          id: "widget_config_constructor_screen_4",
                          label: "Row · config_constructor_screen.dart",
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(context);
                                },
                                child: ThemeRegion.auto(
                                  id: "widget_config_constructor_screen_5",
                                  label: "Container · config_constructor_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.surface.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_config_constructor_screen_6",
                                      label: "Icon · config_constructor_screen.dart",
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: theme.text,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ThemeRegion.auto(
                                id: "widget_config_constructor_screen_7",
                                label: "Text · config_constructor_screen.dart",
                                child: Text(
                                  loc.translate('constructor'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _saveConfig,
                                child: ThemeRegion.auto(
                                  id: "widget_config_constructor_screen_8",
                                  label: "Container · config_constructor_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.primary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: theme.primary.withOpacity(0.5),
                                      ),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_config_constructor_screen_9",
                                      label: "Icon · config_constructor_screen.dart",
                                      child: Icon(
                                        Icons.check_rounded,
                                        color: theme.primary,
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

                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildSectionHeader(
                              loc.translate('basic_settings'),
                              theme,
                            ),
                            _buildGlassCard(
                              theme: theme,
                              child: ThemeRegion.auto(
                                id: "widget_config_constructor_screen_10",
                                label:
                                    "Column · config_constructor_screen.dart",
                                child: Column(
                                  children: [
                                    _buildDropdown(
                                      loc.translate('protocol'),
                                      [
                                        'VLESS',
                                        'VMess',
                                        'Trojan',
                                        'Shadowsocks',
                                        'Hysteria2',
                                      ],
                                      selectedProtocol,
                                      (v) =>
                                          setState(() => selectedProtocol = v!),
                                      theme,
                                    ),
                                    const Divider(
                                      color: Colors.white10,
                                      height: 1,
                                    ),
                                    _buildInput(
                                      loc.translate('remarks'),
                                      'Мой сервер',
                                      theme,
                                      controller: _nameCtrl,
                                    ),
                                    const Divider(
                                      color: Colors.white10,
                                      height: 1,
                                    ),
                                    _buildInput(
                                      loc.translate('address'),
                                      '192.168.1.1',
                                      theme,
                                      controller: _addrCtrl,
                                    ),
                                    const Divider(
                                      color: Colors.white10,
                                      height: 1,
                                    ),
                                    _buildInput(
                                      loc.translate('port'),
                                      '443',
                                      theme,
                                      isNumber: true,
                                      controller: _portCtrl,
                                    ),
                                  ],
                                ),
                              ),
                            ).animate().fade(delay: 100.ms).slideX(begin: 0.1),
                            const SizedBox(height: 24),

                            _buildSectionHeader(
                              '${loc.translate('protocol_settings')} ($selectedProtocol)',
                              theme,
                            ),
                            _buildGlassCard(
                              theme: theme,
                              child: ThemeRegion.auto(
                                id: "widget_config_constructor_screen_11",
                                label:
                                    "Column · config_constructor_screen.dart",
                                child: Column(
                                  children: [
                                    if (selectedProtocol == 'VLESS' ||
                                        selectedProtocol == 'VMess') ...[
                                      _buildInput(
                                        'UUID',
                                        'uuid-goes-here',
                                        theme,
                                        controller: _uuidCtrl,
                                      ),
                                    ],
                                    if (selectedProtocol == 'Hysteria2' ||
                                        selectedProtocol == 'Trojan' ||
                                        selectedProtocol == 'Shadowsocks') ...[
                                      _buildInput(
                                        loc.translate('password'),
                                        'my_secure_pass',
                                        theme,
                                        controller: _uuidCtrl,
                                      ),
                                    ],

                                    if (selectedProtocol == 'VMess') ...[
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'AlterId',
                                        '0',
                                        theme,
                                        isNumber: true,
                                      ),
                                    ],

                                    if (selectedProtocol == 'VLESS') ...[
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      // ТЕПЕРЬ СВЯЗАНО СО СТЕЙТОМ selectedFlow
                                      _buildDropdown(
                                        'Flow',
                                        [
                                          'none',
                                          'xtls-rprx-vision',
                                          'xtls-rprx-vision-udp443',
                                        ],
                                        selectedFlow,
                                        (v) =>
                                            setState(() => selectedFlow = v!),
                                        theme,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ).animate().fade(delay: 150.ms).slideX(begin: 0.1),
                            const SizedBox(height: 24),

                            _buildSectionHeader(
                              loc.translate('transport_settings'),
                              theme,
                            ),
                            _buildGlassCard(
                              theme: theme,
                              child: ThemeRegion.auto(
                                id: "widget_config_constructor_screen_12",
                                label:
                                    "Column · config_constructor_screen.dart",
                                child: Column(
                                  children: [
                                    _buildDropdown(
                                      'Сеть (Network)',
                                      [
                                        'tcp',
                                        'kcp',
                                        'ws',
                                        'http',
                                        'grpc',
                                        'quic',
                                        'xhttp',
                                        'splithttp',
                                        'httpupgrade',
                                        'raw',
                                      ],
                                      selectedNetwork,
                                      (v) =>
                                          setState(() => selectedNetwork = v!),
                                      theme,
                                    ),

                                    if (selectedNetwork == 'ws') ...[
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'Path',
                                        '/stream',
                                        theme,
                                        controller: _pathCtrl,
                                      ),
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'Host',
                                        'example.com',
                                        theme,
                                        controller: _hostCtrl,
                                      ),
                                    ],
                                    if (selectedNetwork == 'grpc') ...[
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'ServiceName',
                                        'GrpcService',
                                        theme,
                                        controller: _serviceNameCtrl,
                                      ),
                                    ],
                                    if (selectedNetwork == 'xhttp' ||
                                        selectedNetwork == 'splithttp' ||
                                        selectedNetwork == 'httpupgrade') ...[
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'Path',
                                        '/stream',
                                        theme,
                                        controller: _pathCtrl,
                                      ),
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'Host',
                                        'example.com',
                                        theme,
                                        controller: _hostCtrl,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ).animate().fade(delay: 200.ms).slideX(begin: 0.1),
                            const SizedBox(height: 24),

                            _buildSectionHeader(
                              loc.translate('security_settings'),
                              theme,
                            ),
                            _buildGlassCard(
                              theme: theme,
                              child: ThemeRegion.auto(
                                id: "widget_config_constructor_screen_13",
                                label:
                                    "Column · config_constructor_screen.dart",
                                child: Column(
                                  children: [
                                    _buildDropdown(
                                      'TLS Тип',
                                      ['none', 'tls', 'reality'],
                                      selectedTls,
                                      (v) => setState(() => selectedTls = v!),
                                      theme,
                                    ),

                                    if (selectedTls != 'none') ...[
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'SNI (Server Name)',
                                        'yahoo.com',
                                        theme,
                                        controller: _sniCtrl,
                                      ),
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildDropdown(
                                        'TLS Fingerprint',
                                        ['chrome', 'firefox', 'ios', 'random'],
                                        _normalizedFingerprint,
                                        (v) =>
                                            setState(() => _fpCtrl.text = v!),
                                        theme,
                                      ),
                                    ],

                                    if (selectedTls == 'reality') ...[
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'Public Key',
                                        'pbk_key_here',
                                        theme,
                                        controller: _pbkCtrl,
                                      ),
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      // ТЕПЕРЬ СВЯЗАНО С КОНТРОЛЛЕРАМИ
                                      _buildInput(
                                        'Short ID',
                                        'short_id_here',
                                        theme,
                                        controller: _sidCtrl,
                                      ),
                                      const Divider(
                                        color: Colors.white10,
                                        height: 1,
                                      ),
                                      _buildInput(
                                        'Spider X',
                                        '/',
                                        theme,
                                        controller: _spxCtrl,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ).animate().fade(delay: 250.ms).slideX(begin: 0.1),

                            const SizedBox(height: 50),
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

  void _saveConfig() {
    HapticFeedback.mediumImpact();
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Manual $selectedProtocol'
        : _nameCtrl.text.trim();
    final address = _addrCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 443;
    final secret = _uuidCtrl.text.trim();
    final security = selectedTls == 'none' ? 'none' : selectedTls;
    final fingerprint = _normalizedFingerprint;

    ProxyConfig config;
    if (selectedProtocol == 'VLESS') {
      config = VlessConfig(
        name: name,
        address: address,
        port: port,
        uuid: secret,
        network: selectedNetwork,
        security: security,
        flow: selectedFlow == 'none' ? '' : selectedFlow,
        sni: _sniCtrl.text.trim(),
        pbk: _pbkCtrl.text.trim(),
        sid: _sidCtrl.text.trim(),
        spx: _spxCtrl.text.trim(),
        host: _hostCtrl.text.trim(),
        path: _pathCtrl.text.trim(),
        serviceName: _serviceNameCtrl.text.trim(),
      );
    } else if (selectedProtocol == 'VMess') {
      config = VmessConfig(
        name: name,
        address: address,
        port: port,
        uuid: secret,
        network: selectedNetwork,
        tls: security,
        sni: _sniCtrl.text.trim(),
        host: _hostCtrl.text.trim(),
        path: selectedNetwork == 'grpc'
            ? _serviceNameCtrl.text.trim()
            : _pathCtrl.text.trim(),
      );
    } else if (selectedProtocol == 'Trojan') {
      config = TrojanConfig(
        name: name,
        address: address,
        port: port,
        password: secret,
        network: selectedNetwork,
        security: security == 'none' ? 'none' : 'tls',
        sni: _sniCtrl.text.trim(),
        host: _hostCtrl.text.trim(),
        path: selectedNetwork == 'grpc'
            ? _serviceNameCtrl.text.trim()
            : _pathCtrl.text.trim(),
      );
    } else if (selectedProtocol == 'Shadowsocks') {
      config = ShadowsocksConfig(
        name: name,
        address: address,
        port: port,
        method: 'aes-256-gcm',
        password: secret,
      );
    } else {
      config = HysteriaConfig(
        name: name,
        address: address,
        port: port,
        password: secret,
        sni: _sniCtrl.text.trim(),
      );
    }

    config.fp = fingerprint; // Присваиваем отпечаток здесь!
    Navigator.pop(context, config);
  }

  String get _normalizedFingerprint {
    const values = ['chrome', 'firefox', 'ios', 'random'];
    return values.contains(_fpCtrl.text) ? _fpCtrl.text : 'chrome';
  }

  Widget _buildSectionHeader(String title, ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: ThemeRegion.auto(
        id: "widget_config_constructor_screen_14",
        label: "Text · config_constructor_screen.dart",
        child: Text(
          AppLocalizations.text(context, title),
          style: TextStyle(
            color: theme.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, required ThemeConfig theme}) {
    return ThemeRegion.auto(
      id: "widget_config_constructor_screen_15",
      label: "Container · config_constructor_screen.dart",
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(24), child: child),
      ),
    );
  }

  Widget _buildInput(
    String label,
    String hint,
    ThemeConfig theme, {
    bool isNumber = false,
    TextEditingController? controller,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: ThemeRegion.auto(
        id: "widget_config_constructor_screen_16",
        label: "Row · config_constructor_screen.dart",
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: ThemeRegion.auto(
                id: "widget_config_constructor_screen_17",
                label: "Text · config_constructor_screen.dart",
                child: Text(
                  AppLocalizations.text(context, label),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: ThemeRegion.auto(
                id: "widget_config_constructor_screen_18",
                label: "TextField · config_constructor_screen.dart",
                child: TextField(
                  controller: controller,
                  keyboardType: isNumber
                      ? TextInputType.number
                      : TextInputType.text,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 14, color: theme.text),
                  decoration: InputDecoration.collapsed(
                    hintText: AppLocalizations.text(context, hint),
                    hintStyle: const TextStyle(color: Colors.white24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String value,
    ValueChanged<String?> onChanged,
    ThemeConfig theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: ThemeRegion.auto(
        id: "widget_config_constructor_screen_19",
        label: "Row · config_constructor_screen.dart",
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ThemeRegion.auto(
              id: "widget_config_constructor_screen_20",
              label: "Text · config_constructor_screen.dart",
              child: Text(
                AppLocalizations.text(context, label),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GlassDropdown<String>(
              value: value,
              surfaceColor: theme.surface,
              accentColor: theme.primary,
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: ThemeRegion.auto(
                        id: "widget_config_constructor_screen_21",
                        label: "Text · config_constructor_screen.dart",
                        child: Text(
                          e,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
