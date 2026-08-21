// app_prefs.dart — SharedPreferences-backed settings for Retro-Spectrum.
// Mirrors the Retro-Saturn app_prefs.dart shape.

import 'package:shared_preferences/shared_preferences.dart';

class AppPrefs {
  static SharedPreferences? _prefs;

  static const _biosPathKey = 'bios_path';
  static const _gamesFolderKey = 'games_folder';
  static const _setupCompletedKey = 'setup_completed';
  static const _muteKey = 'audio_muted';

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
}
