// setup_scan_service.dart — Auto-scan a folder for Spectrum titles.
//
// Walk the folder, keep whatever the core can open, report what was found.
//
// There is no ROM hunt here, unlike the Saturn sibling this was copied
// from: that scanner looked for a 512 KiB BIOS blob, because a Saturn
// cannot boot without one the user supplies. The Spectrum ROMs are freely
// distributable and ship in assets/roms/, so there is nothing to find.
//
// On Android the most common layout is /storage/FEDD-B1FF/Spectrum/{BIOS,
// Games} (the convention the other Retro-* front ends use). On Linux
// it's ~/Spectrum/Games. iOS is file-import only.

import 'dart:io';

import 'package:retro_spectrum/data/media_entry.dart';
import 'package:retro_spectrum/services/library_scanner.dart';

class ScanResult {
  final String folderPath;
  final List<MediaEntry> games;

  const ScanResult({required this.folderPath, required this.games});

  bool get hasGames => games.isNotEmpty;
  bool get isEmpty => games.isEmpty;
}

class SetupScanService {
  /// Default folders to probe in priority order. First hit wins.
  /// Probed in order, first one that exists wins.
  ///
  /// The Roms/<system> shape is here because that is how handhelds actually
  /// arrive: every front end on a Retroid, an Anbernic or a stock SD card
  /// image lays its library out that way, and a list that only knew about a
  /// folder called "Spectrum" guessed wrong on every one of them -- leaving
  /// a first-run screen that found nothing on a device with a full
  /// collection on it.
  static const _defaultFolders = <String>[
    '/storage/FEDD-B1FF/Roms/zxspectrum',
    '/storage/FEDD-B1FF/Roms/spectrum',
    '/storage/FEDD-B1FF/Spectrum',
    '/storage/emulated/0/Roms/zxspectrum',
    '/storage/emulated/0/Roms/spectrum',
    '/storage/emulated/0/Spectrum',
    '/sdcard/Roms/zxspectrum',
    '/sdcard/Roms/spectrum',
    '/sdcard/Spectrum',
  ];

  /// Get the default scan folder for the current platform.
  static String? defaultFolder() {
    if (Platform.isAndroid) {
      for (final f in _defaultFolders) {
        if (Directory(f).existsSync()) return f;
      }
      return _defaultFolders.first; // fall back even if missing
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/root';
      return '$home/Spectrum';
    }
    return null;
  }

  /// Probe a folder for BIOS + game files. BIOS candidates = saturn*.bin
  static Future<ScanResult> scan(String folderPath) async {
    final games = <MediaEntry>[];

    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      return ScanResult(folderPath: folderPath, games: const []);
    }

    // Scan recursively for BIOS + game files
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.toLowerCase();
      final size = await entity.length();

      // What counts as a title is MediaFormat's business, not a second
      // list here -- the two drifting apart is how a format becomes
      // launchable from the library but invisible to setup.
      final ext = name.split('.').last;
      if (MediaFormat.fromExtension(ext).isSupported) {
        if (size > 0) {
          games.add(MediaEntry(
            displayName: _displayName(entity.path),
            path: entity.path,
            format: MediaFormat.fromExtension(ext),
            baseName: _basename(entity.path),
            bezelKey: LibraryScanner.normalizeBezelKey(entity.path),
          ));
        }
      }
    }

    return ScanResult(folderPath: folderPath, games: _dedup(games));
  }

  /// Two CHD/CUE files for the same game often live side by side — e.g.
  /// `Alien Trilogy (US).chd` and `Alien_Trilogy__US_.chd`. Dedup by
  /// bezelKey (already normalized via `LibraryScanner.normalizeBezelKey`)
  /// keeping the lexicographically-first entry per key. */
  static List<MediaEntry> _dedup(List<MediaEntry> games) {
    final byKey = <String, MediaEntry>{};
    for (final g in games) {
      final key = dedupBaseName(g.baseName);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = g;
      } else {
        try {
          final aSz = File(existing.path).lengthSync();
          final bSz = File(g.path).lengthSync();
          if (bSz > aSz) byKey[key] = g;
        } catch (_) {
          // can't stat, keep whichever we saw first
        }
      }
    }
    final out = byKey.values.toList()
      ..sort((a, b) => a.displayName.toLowerCase()
          .compareTo(b.displayName.toLowerCase()));
    return out;
  }

  /// Returns the default scan folder, falling back to none.
  static String? autoDetectFolder() {
    final d = defaultFolder();
    if (d == null) return null;
    return Directory(d).existsSync() ? d : null;
  }

  static String _basename(String p) {
    final segs = p.split('/');
    final last = segs.isEmpty ? p : segs.last;
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(0, dot) : last;
  }

  static String _displayName(String p) {
    final segs = p.split('/');
    final last = segs.isEmpty ? p : segs.last;
    return last;
  }
}