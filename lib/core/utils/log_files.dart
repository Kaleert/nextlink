import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class LogFileEntry {
  final File file;
  final int sizeBytes;
  final DateTime modifiedAt;

  const LogFileEntry({
    required this.file,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  String get name => file.uri.pathSegments.last;
  bool get isManualSnapshot => name.startsWith('NextLink_Logs_');
}

class LogFiles {
  LogFiles._();

  static const _channel = MethodChannel('pro.kaleert.nextlink/logger');
  static const _maxCurrentLogBytes = 1024 * 1024;
  static const _maxRotatedLogs = 3;
  static Future<void> _writeQueue = Future<void>.value();
  static int _maxFiles = 20;
  static int _maxStorageBytes = 20 * 1024 * 1024;
  static int _writesSinceRetention = 0;

  static Future<void> configureRetention({
    required int maxFiles,
    required int maxStorageMb,
  }) {
    _maxFiles = maxFiles.clamp(5, 100);
    _maxStorageBytes = maxStorageMb.clamp(10, 200) * 1024 * 1024;
    return enforceRetention();
  }

  static Future<void> enforceRetention() {
    _writeQueue = _writeQueue.then((_) => _enforceRetentionNow());
    return _writeQueue;
  }

  static Future<Directory> directory() async {
    final support = await getApplicationSupportDirectory();
    final logs = Directory('${support.path}/logs');
    await logs.create(recursive: true);
    return logs;
  }

  static Future<Map<String, String>> collectTechnicalInfo() async {
    try {
      final values = await _channel.invokeMapMethod<String, dynamic>(
        'getLogTechnicalInfo',
      );
      if (values != null && values.isNotEmpty) {
        return values.map((key, value) => MapEntry(key, '$value'));
      }
    } catch (_) {}
    return {
      'Platform': Platform.operatingSystem,
      'Platform version': Platform.operatingSystemVersion,
      'Dart runtime': Platform.version.split(' ').first,
    };
  }

  static Future<File> _currentAppLog() async =>
      File('${(await directory()).path}/application_log.txt');

  static Future<void> seedApplicationLogIfMissing(
    Iterable<String> lines,
  ) async {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _currentAppLog();
        if (await file.exists() && await file.length() > 0) return;
        final technicalInfo = await collectTechnicalInfo();
        final header = [
          'Technical information',
          ...technicalInfo.entries.map(
            (entry) => '${entry.key}: ${entry.value}',
          ),
          '',
        ].join('\n');
        final restored = lines.join('\n');
        await file.writeAsString(
          '$header${restored.isEmpty ? '' : '$restored\n'}',
          flush: true,
        );
        await _trimFileTail(file, _maxCurrentLogBytes);
        await _enforceRetentionNow();
      } catch (_) {}
    });
    await _writeQueue;
  }

  static Future<void> appendApplicationLine(String line) {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _currentAppLog();
        var rotated = false;
        if (await file.exists() &&
            await file.length() + line.length + 1 >= _maxCurrentLogBytes) {
          await _rotateLogs(file);
          rotated = true;
        }
        if (!await file.exists() || await file.length() == 0) {
          final technicalInfo = await collectTechnicalInfo();
          final header = [
            'Technical information',
            ...technicalInfo.entries.map(
              (entry) => '${entry.key}: ${entry.value}',
            ),
            '',
          ].join('\n');
          await file.writeAsString('$header\n', flush: true);
        }
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
        await _trimFileTail(file, _maxCurrentLogBytes);
        _writesSinceRetention++;
        if (rotated || _writesSinceRetention >= 32) {
          _writesSinceRetention = 0;
          await _enforceRetentionNow();
        }
      } catch (_) {}
    });
    return _writeQueue;
  }

  static Future<void> _rotateLogs(File current) async {
    final dir = current.parent;
    final oldest = File('${dir.path}/application_log.$_maxRotatedLogs.txt');
    if (await oldest.exists()) await oldest.delete();
    for (var index = _maxRotatedLogs - 1; index >= 1; index--) {
      final from = File('${dir.path}/application_log.$index.txt');
      if (await from.exists()) {
        await from.rename('${dir.path}/application_log.${index + 1}.txt');
      }
    }
    if (await current.exists()) {
      await current.rename('${dir.path}/application_log.1.txt');
    }
  }

  static Future<void> _trimFileTail(File file, int maxBytes) async {
    final bytes = await file.readAsBytes();
    if (bytes.length <= maxBytes) return;
    var start = bytes.length - maxBytes;
    while (start < bytes.length && (bytes[start] & 0xc0) == 0x80) {
      start++;
    }
    final tail = utf8.decode(bytes.sublist(start), allowMalformed: true);
    await file.writeAsString(tail, flush: true);
  }

  static Future<LogFileEntry> saveSnapshot(String contents) async {
    await _writeQueue;
    final dir = await directory();
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}${now.millisecond.toString().padLeft(3, '0')}';
    final file = File('${dir.path}/NextLink_Logs_$stamp.txt');
    await file.writeAsString(contents, flush: true);
    await enforceRetention();
    if (!await file.exists()) {
      throw FileSystemException(
        'The snapshot exceeds the configured log storage limit',
        file.path,
      );
    }
    return LogFileEntry(
      file: file,
      sizeBytes: await file.length(),
      modifiedAt: await file.lastModified(),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static Future<void> _enforceRetentionNow() async {
    try {
      final dir = await directory();
      // Older builds put non-fatal Flutter framework errors in this file.
      final legacyCrashLogs = [File('${dir.parent.path}/crash_log.txt')];
      for (final legacyFile in legacyCrashLogs) {
        if (await legacyFile.exists()) await legacyFile.delete();
      }
      final currentLog = File('${dir.path}/application_log.txt');
      if (await currentLog.exists()) {
        await _trimFileTail(currentLog, _maxCurrentLogBytes);
      }
      final files = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
          files.add(entity);
        }
      }
      const protectedNames = {'application_log.txt', 'crash_log.txt'};
      files.sort((a, b) {
        final aProtected = protectedNames.contains(a.uri.pathSegments.last);
        final bProtected = protectedNames.contains(b.uri.pathSegments.last);
        if (aProtected != bProtected) return aProtected ? -1 : 1;
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      });

      var keptCount = 0;
      var keptBytes = 0;
      for (final file in files) {
        final protected = protectedNames.contains(file.uri.pathSegments.last);
        final size = await file.length();
        final withinCount = keptCount < _maxFiles;
        final withinSize = keptBytes + size <= _maxStorageBytes;
        if (protected || (withinCount && withinSize)) {
          keptCount++;
          keptBytes += size;
        } else {
          await file.delete();
        }
      }
    } catch (_) {}
  }

  static Future<List<LogFileEntry>> listFiles() async {
    final dir = await directory();
    final entries = <LogFileEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.txt')) {
        continue;
      }
      try {
        final stat = await entity.stat();
        entries.add(
          LogFileEntry(
            file: entity,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      } catch (_) {}
    }
    entries.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return entries;
  }

  static Future<String> readFile(LogFileEntry entry) async {
    final base = (await directory()).absolute.path;
    final path = entry.file.absolute.path;
    if (!path.startsWith('$base${Platform.pathSeparator}')) {
      throw FileSystemException('Log file is outside the logs directory', path);
    }
    return entry.file.readAsString();
  }

  static Future<void> deleteFile(LogFileEntry entry) async {
    final base = (await directory()).absolute.path;
    final path = entry.file.absolute.path;
    if (!path.startsWith('$base${Platform.pathSeparator}')) {
      throw FileSystemException('Log file is outside the logs directory', path);
    }
    await entry.file.delete();
  }

  static Future<void> shareFiles(
    Iterable<LogFileEntry> entries, {
    required String chooserTitle,
  }) async {
    final dir = (await directory()).absolute.path;
    final paths = entries
        .map((entry) => entry.file.absolute.path)
        .where((path) => path.startsWith('$dir${Platform.pathSeparator}'))
        .toList();
    if (paths.isEmpty) throw StateError('No log files to share');
    await _channel.invokeMethod<void>('shareLogFiles', {
      'paths': paths,
      'chooserTitle': chooserTitle,
    });
  }
}
