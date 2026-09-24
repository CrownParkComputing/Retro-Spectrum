// saf_bridge.dart -- Dart-side client for the Android native bridge
// in MainActivity.kt. The user picks a parent folder once via the
// system file picker (which on Android returns an ACTION_OPEN_DOCUMENT_TREE
// URI), Android grants a persistable URI permission, and this class
// walks the SAF tree and reads files through the native channel.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class SafBridge {
  SafBridge._();

  static const MethodChannel _channel =
      MethodChannel('retro_spectrum/saf');

  /// True only when running on Android where SAF is meaningful.
  static bool get isRelevant => Platform.isAndroid;

  /// Tell the native side which SAF tree URI the user picked so it
  /// can walk it. Idempotent; safe to call again with a new URI.
  static Future<void> setTreeUri(String uriString) async {
    if (!isRelevant) return;
    await _channel.invokeMethod('setSafTree', {'uri': uriString});
  }

  /// Recursive walk of the tree the user picked. Returns a flat list
  /// of entries with name, uri, isDirectory, size, mime. The Dart
  /// side filters this list for the formats it supports.
  static Future<List<SafEntry>> walkTree() async {
    if (!isRelevant) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>('walkSafTree')
        ?? const [];
    return raw.map((m) => SafEntry.fromMap(
          (m as Map).cast<String, dynamic>(),
        )).toList();
  }

  /// Read a single file from the SAF tree. Returns the bytes or null
  /// if the file can't be opened (e.g. the user revoked access).
  static Future<Uint8List?> readFile(String uriString) async {
    if (!isRelevant) return null;
    final bytes =
        await _channel.invokeMethod<Uint8List>('readSafFile', {'uri': uriString});
    return bytes;
  }
}

class SafEntry {
  final String name;
  final String uri;
  final bool isDirectory;
  final int size;
  final String mime;

  const SafEntry({
    required this.name,
    required this.uri,
    required this.isDirectory,
    required this.size,
    required this.mime,
  });

  factory SafEntry.fromMap(Map<String, dynamic> m) {
    return SafEntry(
      name: m['name'] as String? ?? '',
      uri: m['uri'] as String? ?? '',
      isDirectory: m['isDirectory'] as bool? ?? false,
      size: (m['size'] as num?)?.toInt() ?? 0,
      mime: m['mime'] as String? ?? '',
    );
  }
}
