// game_state_service.dart — One auto-saved state per title.
//
// This was Retro-Saturn's backup-RAM service, and the Spectrum has no
// state: there is no load/save_backup_memory in speccy_bridge.h at
// all. What the code actually does, though, is useful here -- it snapshots
// the running machine to a per-title file and restores it on the way back
// in, through speccy_core_save_state / _load_state. So it keeps the
// behaviour and loses the name, which described hardware this machine
// does not have.
//
// One file per title under <app docs>/saves/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';
import 'package:retro_spectrum/services/app_log.dart';

class GameStateService {
  static const _savesSubdir = 'saves';

  /// Path to the on-disk file for a given game. SHA1 of the absolute
  /// game path gives a stable, filesystem-safe filename.
  static File fileFor(String titlePath) {
    final digest = crypto.sha1.convert(utf8.encode(titlePath)).toString();
    return File(p.join(savesDirSync, '$digest.bin'));
  }

  /// Synchronous saves dir — must be awaited once at startup before any
  /// loadInto/saveFrom call. Returns the path.
  static String _savesDirSyncCached = '';
  static String get savesDirSync {
    if (_savesDirSyncCached.isNotEmpty) return _savesDirSyncCached;
    // path_provider is async-only, so cache at first awaited init.
    throw StateError(
        'GameStateService.ensureInit() must be awaited before fileFor()');
  }

  /// Call once at app startup (e.g. main() before runApp).
  static Future<void> ensureInit() async {
    if (_savesDirSyncCached.isNotEmpty) return;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, _savesSubdir));
    if (!d.existsSync()) d.createSync(recursive: true);
    _savesDirSyncCached = d.path;
    return;
  }

  /// Read the 32 KiB state for a game from disk and feed it to
  /// the emulator. Returns true if a save file existed and was loaded.
  static Future<bool> loadInto(SpeccyCore core, String titlePath) async {
    final f = fileFor(titlePath);
    if (!f.existsSync()) return false;
    final tmp = File('${f.path}.load.tmp');
    try {
      await tmp.writeAsBytes(await f.readAsBytes());
      final rc = core.loadState(tmp.path);
      return rc == 0;
    } finally {
      if (tmp.existsSync()) await tmp.delete();
    }
  }

  /// Snapshot the emulator's current state to disk for the given game.
  /// Called when leaving the emulator or every N seconds while playing.
  static Future<void> saveFrom(SpeccyCore core, String titlePath) async {
    final f = fileFor(titlePath);
    final tmp = File('${f.path}.save.tmp');
    try {
      final rc = core.saveState(tmp.path);
      if (rc != 0) {
        AppLog.log('state save: rc=$rc (${titlePath.split('/').last})');
        return;
      }
      if (tmp.existsSync()) {
        await tmp.rename(f.path);
        AppLog.log('state saved: ${f.path.split('/').last}');
      }
    } catch (e) {
      AppLog.log('state save exception: $e');
      if (tmp.existsSync()) await tmp.delete();
    }
  }

  /// Periodic auto-save while a game is running. Spawn once per session
  /// via `GameStateService.startAutoSave(core, titlePath)`.
  static Timer? _autoSaveTimer;
  static String? _autoSavePath;

  static void startAutoSave(SpeccyCore core, String titlePath,
      {Duration interval = const Duration(seconds: 60)}) {
    _autoSavePath = titlePath;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(interval, (_) async {
      if (_autoSavePath != null) {
        // Errors are swallowed — in-game BIOS operations like
        // 'Erase backup data' briefly clear the state; auto-save
        // during that transient state could otherwise throw. The save
        // is a 'best effort' snapshot, not a critical write.
        try {
          await saveFrom(core, _autoSavePath!);
        } catch (_) {
          // ignore — next tick will retry
        }
      }
    });
  }

  static void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _autoSavePath = null;
  }
}