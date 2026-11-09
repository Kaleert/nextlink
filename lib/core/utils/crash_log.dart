import 'dart:io';
import 'dart:convert';

import 'log_files.dart';

/// Reads Android's persisted reports for actual process crashes.
/// Dart framework errors and warnings are deliberately not written here.
class CrashLog {
  CrashLog._();
  static String? _filePath;
  static Map<String, String> _technicalInfo = const {};

  static Future<void> initialize() async {
    try {
      final directory = await LogFiles.directory();
      _filePath = '${directory.path}/crash_log.txt';
      _technicalInfo = await LogFiles.collectTechnicalInfo();
    } catch (_) {}
  }

  static Future<String> read() async {
    try {
      final directory = await LogFiles.directory();
      final file = File('${directory.path}/crash_log.txt');
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (error) {
      return 'Could not read crash log: $error';
    }
  }

  static Future<void> recordFatal(
    Object error,
    StackTrace stack, {
    required String source,
  }) async {
    try {
      final cachedPath = _filePath;
      if (cachedPath != null) {
        final file = File(cachedPath);
        file.writeAsStringSync(
          _formatReport(error, stack, source, _technicalInfo),
          mode: FileMode.append,
          flush: true,
        );
        _trimCrashFileSync(file);
        return;
      }
      final directory = await LogFiles.directory();
      final file = File('${directory.path}/crash_log.txt');
      final technicalInfo = await LogFiles.collectTechnicalInfo();
      await file.writeAsString(
        _formatReport(error, stack, source, technicalInfo),
        mode: FileMode.append,
        flush: true,
      );
      await _trimCrashFile(file);
    } catch (_) {}
  }

  static String _formatReport(
    Object error,
    StackTrace stack,
    String source,
    Map<String, String> technicalInfo,
  ) {
    final report = StringBuffer()
      ..writeln('\n========== DART FATAL ERROR ==========')
      ..writeln('Time: ${DateTime.now().toIso8601String()}')
      ..writeln('Source: $source');
    for (final entry in technicalInfo.entries) {
      report.writeln('${entry.key}: ${entry.value}');
    }
    report
      ..writeln('Exception: $error')
      ..writeln('Stack trace:')
      ..writeln(stack)
      ..writeln('=====================================\n');
    return report.toString();
  }

  static Future<void> _trimCrashFile(File file) async {
    const maxBytes = 1024 * 1024;
    if (await file.length() <= maxBytes) return;
    final bytes = await file.readAsBytes();
    var start = bytes.length - maxBytes;
    while (start < bytes.length && (bytes[start] & 0xc0) == 0x80) {
      start++;
    }
    await file.writeAsString(
      utf8.decode(bytes.sublist(start), allowMalformed: true),
      flush: true,
    );
  }

  static void _trimCrashFileSync(File file) {
    const maxBytes = 1024 * 1024;
    if (file.lengthSync() <= maxBytes) return;
    final bytes = file.readAsBytesSync();
    var start = bytes.length - maxBytes;
    while (start < bytes.length && (bytes[start] & 0xc0) == 0x80) {
      start++;
    }
    file.writeAsStringSync(
      utf8.decode(bytes.sublist(start), allowMalformed: true),
      flush: true,
    );
  }
}
