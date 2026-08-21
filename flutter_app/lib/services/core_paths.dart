// core_paths.dart — Platform-agnostic on-disk paths for the Speccy
// core's persistent state. Routes every call through path_provider so
// the same code resolves to:
//
//   Android: /data/data/<pkg>/files/
//   iOS:     <sandbox>/Library/Application Support/
//   Linux:   ~/.local/share/<app>/
//
// The previous incarnation (before this migration was started) was
// hand-rolled per-platform path logic that broke on iOS + Linux. The
// Retro-Saturn pattern (added in the Phase 5 platform-agnostic paths
// work) is the template this file lifts.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CorePaths {
  CorePaths._();

  static String _baseDir = '';
  static bool _dirsEnsured = false;

  /// One-shot base-dir resolution. Idempotent. Call once at app
  /// startup (before any path getter is touched). The base is cached
  /// so the synchronous getters below can be called from build()
  /// methods without an extra await.
  static Future<void> ensureInit() async {
    if (_baseDir.isNotEmpty) return;
    final base = await getApplicationSupportDirectory();
    _baseDir = base.path;
  }

  /// Make sure every subdir used by the app exists. Idempotent.
  /// Call after [ensureInit] at startup.
  static Future<void> ensureDirs() async {
    if (_dirsEnsured) return;
    await ensureInit();
    for (final sub in const ['profile', 'saves', 'snapshots', 'logs']) {
      final d = Directory(p.join(_baseDir, sub));
      if (!d.existsSync()) {
        await d.create(recursive: true);
      }
    }
    _dirsEnsured = true;
  }

  /// Whether [ensureInit] has resolved the base dir.
  static bool get isReady => _baseDir.isNotEmpty;

  /// Where the core writes `unreal_speccy_portable.xml` + save data.
  /// Passed to `speccy_core_init` as the profile_dir.
  static String get profileDir => p.join(_baseDir, 'profile');

  /// Where the core reads its `rom/` and `font/` resources from.
  /// Override the base dir of these via `setResourceDir` if the host
  /// ships them as Flutter assets.
  static String get resourceDir => p.join(_baseDir, 'resources');

  /// Snapshot file written by `speccy_core_save_state` on Pause.
  /// Lives next to the profile dir under the app's private files dir.
  static String get saveStatePath => p.join(_baseDir, 'snapshots', 'session.sna');

  /// App log file. Reachable from the in-app Logs screen.
  static String get appLogPath => p.join(_baseDir, 'logs', 'retro-spectrum.log');
}
