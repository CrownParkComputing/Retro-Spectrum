// speccy_native_paths.dart — per-platform resolution of the
// libspeccycore.{so,dylib} path. Mirrors the Retro-Saturn pattern
// (Retro-Saturn/flutter_app/lib/ffi/spectrum_native_paths.dart):
// Linux uses an absolute path next to the .so, Android uses the bare
// name (jniLibs), iOS uses .framework/<name>.

import 'dart:io';

import 'package:path/path.dart' as p;

class SpeccyNativePaths {
  /// Absolute path to libspeccycore.so on the host (Linux).
  static String? get linuxHostLibrary {
    final candidates = <String>[
      p.join(Directory.current.path,
          'native', 'speccy_core', 'linux', 'build', 'libspeccycore.so'),
      p.join(Directory.current.path, '..', 'native', 'speccy_core',
          'linux', 'build', 'libspeccycore.so'),
      p.join(Directory.current.path, '..', '..', 'native', 'speccy_core',
          'linux', 'build', 'libspeccycore.so'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// Path to SpeccyCore.framework/SpeccyCore on iOS.
  static String? iosFrameworkLibrary() {
    final exe = File(Platform.resolvedExecutable).parent.path;
    final fw = p.join(exe, 'Frameworks', 'SpeccyCore.framework', 'SpeccyCore');
    return File(fw).existsSync() ? fw : null;
  }

  /// Returns the right path for this platform, or null if not found.
  static String? resolveLibrary() {
    if (Platform.isAndroid) return null; // bare name via jniLibs
    if (Platform.isIOS) return iosFrameworkLibrary();
    return linuxHostLibrary;
  }
}
