import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/crash_log.dart';
import '../utils/log_files.dart';

class LogEntry {
  final String time;
  final String tag;
  final String message;

  LogEntry({required this.time, required this.tag, required this.message});
}

class LoggerNotifier extends StateNotifier<List<LogEntry>> {
  static const _platform = MethodChannel('pro.kaleert.nextlink/logger');
  late final Future<void> _loaded;

  LoggerNotifier() : super([]) {
    _loaded = _load();
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'onNativeLog') {
        final String tag = call.arguments['tag'] ?? 'NATIVE';
        final String msg = call.arguments['message'] ?? '';
        addLog(tag, msg);
      }
    });
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSettings = prefs.getString('app_settings');
      Map<String, dynamic> settings = {};
      if (savedSettings != null) {
        try {
          settings = jsonDecode(savedSettings) as Map<String, dynamic>;
        } catch (_) {}
      }
      await LogFiles.configureRetention(
        maxFiles: (settings['maxLogFiles'] as num?)?.toInt() ?? 20,
        maxStorageMb: (settings['maxLogStorageMb'] as num?)?.toInt() ?? 20,
      );
      final data = prefs.getString('app_logs');
      final restoredLogs = <LogEntry>[];
      if (data != null) {
        final List decoded = jsonDecode(data);
        restoredLogs.addAll(
          decoded
              .map(
                (e) => LogEntry(
                  time: e['time'],
                  tag: e['tag'],
                  message: e['message'],
                ),
              )
              .toList(),
        );
      }
      final pendingLogs = state;
      state = [...restoredLogs, ...pendingLogs];
      await LogFiles.seedApplicationLogIfMissing(
        restoredLogs.map(
          (entry) => '[${entry.time}] [${entry.tag}] ${entry.message}',
        ),
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await _loaded;
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(
        state
            .map((e) => {'time': e.time, 'tag': e.tag, 'message': e.message})
            .toList(),
      );
      await prefs.setString('app_logs', data);
    } catch (_) {}
  }

  void addLog(String tag, String message) {
    final now = DateTime.now();
    final timeStr =
        "${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    state = [...state, LogEntry(time: timeStr, tag: tag, message: message)];
    unawaited(
      _loaded.then(
        (_) => LogFiles.appendApplicationLine(
          '[$timeStr] [${tag.toUpperCase()}] $message',
        ),
      ),
    );

    if (state.length > 500) {
      state = state.sublist(state.length - 500);
    }
    _save();
  }

  void clear() {
    state = [];
    _save();
  }

  Future<LogFileEntry> saveSnapshot({
    required String appLogsTitle,
    required String crashLogTitle,
    required String noCrashesText,
  }) async {
    await _loaded;
    final files = await LogFiles.listFiles();
    final appLogFiles =
        files
            .where(
              (file) =>
                  file.name == 'application_log.txt' ||
                  RegExp(r'^application_log\.\d+\.txt$').hasMatch(file.name),
            )
            .toList()
          ..sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
    final appLogs = appLogFiles.isEmpty
        ? state
              .map((entry) => '[${entry.time}] [${entry.tag}] ${entry.message}')
              .join('\n')
        : (await Future.wait(
            appLogFiles.map((file) => LogFiles.readFile(file)),
          )).join('\n');
    final crashLog = await CrashLog.read();
    final technicalInfo = await LogFiles.collectTechnicalInfo();
    final technicalBlock = technicalInfo.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
    final contents =
        'Technical information\n$technicalBlock\n\n$appLogsTitle\n$appLogs\n\n$crashLogTitle\n${crashLog.isEmpty ? noCrashesText : crashLog}';
    return LogFiles.saveSnapshot(contents);
  }
}

final loggerProvider = StateNotifierProvider<LoggerNotifier, List<LogEntry>>(
  (ref) => LoggerNotifier(),
);

// Глобальный помощник для логирования
class AppLogger {
  static void log(dynamic ref, String tag, String message) {
    if (ref is WidgetRef) {
      ref.read(loggerProvider.notifier).addLog(tag, message);
    } else if (ref is Ref) {
      ref.read(loggerProvider.notifier).addLog(tag, message);
    }
  }
}
