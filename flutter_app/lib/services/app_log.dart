// app_log.dart — A log the user can actually send me. Mirrors
// Retro-Saturn's AppLog. Records Dart-side events to memory + a
// file under the app's per-platform data dir.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_spectrum/services/core_paths.dart';

class AppLog {
  AppLog._();

  static final List<String> _lines = <String>[];
  static const int _maxLines = 2000;

  static String? _filePath;
  static bool _initialized = false;

  static String? get filePath => _filePath;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await CorePaths.ensureDirs();
      final path = CorePaths.appLogPath;
      final dir = Directory(p.dirname(path));
      if (!dir.existsSync()) await dir.create(recursive: true);
      _filePath = path;
    } catch (e) {
      _append('log init failed: $e');
    }
  }

  static void log(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$stamp  $message';
    _append(line);
    final path = _filePath;
    if (path == null) return;
    try {
      File(path).writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // A log write must never take the app down.
    }
  }

  static void _append(String line) {
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
  }

  static Future<String> read() async {
    final path = _filePath;
    if (path == null) return _lines.join('\n');
    try {
      final text = await File(path).readAsString();
      return text.isEmpty ? _lines.join('\n') : text;
    } catch (e) {
      return '${_lines.join('\n')}\n(could not read $path: $e)';
    }
  }

  static Future<void> clear() async {
    _lines.clear();
    final path = _filePath;
    if (path == null) return;
    try {
      await File(path).writeAsString(
          '=== cleared ${DateTime.now().toIso8601String()} ===\n');
    } catch (_) {}
  }
}
