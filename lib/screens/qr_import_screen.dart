import '../core/localization/app_localizations.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme/theme_provider.dart';
import '../shared/widgets/custom_notification.dart';

class QrImportScreen extends ConsumerStatefulWidget {
  const QrImportScreen({super.key});
  @override
  ConsumerState<QrImportScreen> createState() => _QrImportScreenState();
}

class _QrImportScreenState extends ConsumerState<QrImportScreen>
    with WidgetsBindingObserver {
  final _scanner = MobileScannerController(
    autoStart: false,
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _returned = false;
  bool _picking = false;
  String? _error;
  bool get _cameraSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_cameraSupported)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _start();
      });
  }

  Future<void> _start() async {
    if (!mounted ||
        _returned ||
        _picking ||
        _scanner.value.isStarting ||
        _scanner.value.isRunning)
      return;
    try {
      await _scanner.start();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = 'Камера недоступна. Разрешите доступ к камере или выберите изображение QR-кода.',
        );
    }
  }

  void _detected(BarcodeCapture capture) {
    if (_returned || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        _returned = true;
        _scanner.stop();
        Navigator.pop(context, raw);
        return;
      }
    }
  }

  Future<void> _torch() async {
    if (!_scanner.value.isInitialized || !_scanner.value.isRunning) return;
    try {
      await _scanner.toggleTorch();
    } catch (_) {
      if (mounted)
        CustomNotification.show(
          context,
          AppLocalizations.text(context, "Фонарик недоступен"),
          isError: true,
        );
    }
  }

  Future<void> _image() async {
    if (_picking) return;
    _picking = true;
    try {
      if (_cameraSupported) await _scanner.stop();
      final path = await const MethodChannel('pro.kaleert.nextlink/theme_files')
          .invokeMethod<String>('pickQrImage');
      if (path == null || !mounted) return;
      final capture = await _scanner.analyzeImage(path);
      if (capture == null ||
          capture.barcodes.every((b) => b.rawValue?.trim().isEmpty ?? true)) {
        if (mounted)
          CustomNotification.show(
            context,
            AppLocalizations.text(context, "На изображении не найден QR-код"),
            isError: true,
          );
      } else {
        _detected(capture);
      }
    } catch (e) {
      if (mounted)
        CustomNotification.show(
          context,
          AppLocalizations.text(
            context,
            "Не удалось прочитать QR-код: {0}",
            args: [e],
          ),
          isError: true,
        );
    } finally {
      _picking = false;
      if (mounted && !_returned && _cameraSupported) await _start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_cameraSupported || _returned || _picking) return;
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused) {
      _scanner.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(AppLocalizations.text(context, "Добавить через QR")),
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_cameraSupported)
                    MobileScanner(
                      controller: _scanner,
                      onDetect: _detected,
                      errorBuilder: (_, e) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error ??
                                AppLocalizations.text(
                                  context,
                                  "Нет доступа к камере. Разрешите доступ в настройках приложения.",
                                ),
                          ),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Text(
                        AppLocalizations.text(
                          context,
                          "Сканирование камерой доступно на Android, iOS и macOS",
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.primary, width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              AppLocalizations.text(
                context,
                "Наведите камеру на QR подписки или конфигурации",
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              if (_cameraSupported)
                IconButton(
                  tooltip: AppLocalizations.text(context, "Фонарик"),
                  onPressed: _torch,
                  icon: const Icon(Icons.flashlight_on_rounded),
                ),
              if (Platform.isAndroid)
                TextButton.icon(
                  onPressed: _image,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(AppLocalizations.text(context, "Из изображения")),
                ),
              if (_error != null)
                TextButton(
                  onPressed: _start,
                  child: Text(AppLocalizations.text(context, "Повторить")),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
