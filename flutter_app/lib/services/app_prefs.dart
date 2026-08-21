// app_prefs.dart — SharedPreferences-backed settings for Retro-Spectrum.
// Mirrors the Retro-Saturn app_prefs.dart shape.

import 'dart:convert';

import 'package:flutter/painting.dart' show Offset;
import 'package:shared_preferences/shared_preferences.dart';

/// Identifies the movable on-screen controls in [AppPrefs.getControlPositions].
const String kControlIdStick = 'stick';
const String kControlIdFire = 'fire';

class AppPrefs {
  static SharedPreferences? _prefs;

  static const _biosPathKey = 'bios_path';
  static const _gamesFolderKey = 'games_folder';
  static const _setupCompletedKey = 'setup_completed';
  static const _muteKey = 'audio_muted';
  static const _controlPositionsKey = 'control_positions';

  static Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> setBiosPath(String path) async {
    await _prefs!.setString(_biosPathKey, path);
  }

  static Future<String?> getBiosPath() async => _prefs!.getString(_biosPathKey);

  static Future<void> setGamesFolder(String path) async {
    await _prefs!.setString(_gamesFolderKey, path);
  }

  static Future<String?> getGamesFolder() async => _prefs!.getString(_gamesFolderKey);

  static Future<void> setSetupCompleted(bool v) async {
    await _prefs!.setBool(_setupCompletedKey, v);
  }

  static Future<bool> isSetupCompleted() async =>
      _prefs!.getBool(_setupCompletedKey) ?? false;

  static Future<void> setMuted(bool v) async {
    await _prefs!.setBool(_muteKey, v);
  }

  static Future<bool> isMuted() async => _prefs!.getBool(_muteKey) ?? false;

  /// Where the player has dragged each on-screen control.
  ///
  /// Stored as a FRACTION of the play area (0..1 from the control's centre),
  /// not pixels, exactly as Retro-C64 does it. The same setting has to
  /// survive rotation, the keyboard appearing under it, and the identical
  /// build running on a handheld and a tablet -- a stick parked 40px from
  /// the bottom of a phone lands mid-screen on a larger display, where as a
  /// fraction it stays where it looks like it belongs.
  ///
  /// An absent entry means "never moved", which is deliberately not the
  /// same as a stored 0,0: an untouched control keeps following its default
  /// corner.
  static Future<Map<String, Offset>> getControlPositions() async {
    final raw = _prefs!.getString(_controlPositionsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, Offset>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! List || value.length != 2) return;
        final dx = (value[0] as num).toDouble();
        final dy = (value[1] as num).toDouble();
        if (dx.isNaN || dy.isNaN) return;
        out[key] = Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
      });
      return out;
    } catch (_) {
      // A corrupt layout costs the custom positions, not the app: empty
      // puts every control back at its default corner.
      return const {};
    }
  }

  static Future<void> setControlPosition(String id, Offset fraction) async {
    final current = Map<String, Offset>.from(await getControlPositions());
    current[id] = Offset(
      fraction.dx.clamp(0.0, 1.0),
      fraction.dy.clamp(0.0, 1.0),
    );
    await _prefs!.setString(
      _controlPositionsKey,
      jsonEncode({
        for (final e in current.entries) e.key: [e.value.dx, e.value.dy],
      }),
    );
  }

  /// Puts every control back to its default corner.
  static Future<void> clearControlPositions() async =>
      _prefs!.remove(_controlPositionsKey);
}
