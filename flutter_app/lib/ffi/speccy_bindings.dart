// speccy_bindings.dart — raw `dart:ffi` typedefs for the C ABI in
// native/speccy_core/bridge/speccy_bridge.h.
//
// Functions are int32 returning except setters (void) and
// `_get_*` accessors. The framebuffer is RGBA8888 (the bridge does the
// palette->RGB conversion itself, matching SDL2 / Android builds).
// Dart's `ui.decodeImageFromPixels` accepts RGBA8888 directly on
// little-endian platforms (all three targets).

import 'dart:ffi';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Spectrum machine models — matches the `SPECCY_MODEL_*` macros in
/// speccy_bridge.h.
enum SpeccyModel {
  model48k(0),
  model128k(1);

  const SpeccyModel(this.value);
  final int value;
}

/// ROM slots — matches the `SPECCY_ROM_*` macros in speccy_bridge.h.
/// The ids are pinned to SimpleSpeccy's android.cpp InitRom order;
/// do not renumber.
enum SpeccyRom {
  sos128_0(0),
  sos128_1(1),
  sos48(2),
  service(3),
  dos(4);

  const SpeccyRom(this.value);
  final int value;
}

/// Error codes returned by all `speccy_bridge_*` functions that
/// return int32.
class SpeccyErr {
  static const ok = 0;
  static const errGeneric = -1;
}

// ============================================================
//  Native typedefs (mirrored from speccy_bridge.h)
// ============================================================

typedef _H = ffi.Pointer<ffi.Uint8>; // opaque SpeccyCore*
typedef _C = ffi.Pointer<Utf8>; // const char* (C string)

typedef _CreateNative = ffi.Pointer<ffi.Uint8> Function();
typedef _CreateDart = ffi.Pointer<ffi.Uint8> Function();

typedef _VoidHandleNative = ffi.Void Function();
typedef _VoidHandleDart = void Function();

typedef _IntHandleStrNative = ffi.Int32 Function(_C);
typedef _IntHandleStrDart = int Function(ffi.Pointer<Utf8>);

typedef _IntHandleStrIntNative = ffi.Int32 Function(_C, ffi.Int32);
typedef _IntHandleStrIntDart = int Function(ffi.Pointer<Utf8>, int);

typedef _IntHandleIntNative = ffi.Int32 Function(ffi.Int32);
typedef _IntHandleIntDart = int Function(int);

typedef _VoidHandleIntIntNative = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _VoidHandleIntIntDart = void Function(int, int);

typedef _IntHandleIntIntNative = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _IntHandleIntIntDart = int Function(int, int);

typedef _IntHandleNative = ffi.Int32 Function();
typedef _IntHandleDart = int Function();

typedef _VoidHandleIntNative = ffi.Void Function(ffi.Int32);
typedef _VoidHandleIntDart = void Function(int);

typedef _VoidHandleStrIntNative = ffi.Void Function(ffi.Int32, _C);
typedef _VoidHandleStrIntDart = void Function(int, ffi.Pointer<Utf8>);

typedef _VoidStrIntNative = ffi.Void Function(_C, ffi.Int32);
typedef _VoidStrIntDart = void Function(ffi.Pointer<Utf8>, int);

typedef _IntStrIntNative = ffi.Int32 Function(_C, ffi.Int32);
typedef _IntStrIntDart = int Function(ffi.Pointer<Utf8>, int);

typedef _VoidHandleStrNative = ffi.Void Function(_C);
typedef _VoidHandleStrDart = void Function(ffi.Pointer<Utf8>);

typedef _VoidHandleStrStrNative = ffi.Void Function(_C, _C);
typedef _VoidHandleStrStrDart = void Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _VoidHandleIntPtrIntNative = ffi.Void Function(ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _VoidHandleIntPtrIntDart = void Function(int, ffi.Pointer<ffi.Uint8>, int);

typedef _VoidHandlePtrIntNative = ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _VoidHandlePtrIntDart = void Function(ffi.Pointer<ffi.Uint8>, int);

typedef _IntHandlePtrIntNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _IntHandlePtrIntDart = int Function(ffi.Pointer<ffi.Uint8>, int);

typedef _IntHandleStrPtrIntNative = ffi.Int32 Function(_C, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _IntHandleStrPtrIntDart = int Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint8>, int);

typedef _StrHandleNative = ffi.Pointer<Utf8> Function();
typedef _StrHandleDart = ffi.Pointer<Utf8> Function();

typedef _FbHandleNative = ffi.Pointer<ffi.Uint32> Function(ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>);
typedef _FbHandleDart = ffi.Pointer<ffi.Uint32> Function(ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>);

/// Low-level bindings to libspeccycore.{so,dylib}.
class SpeccyCoreBindings {
  final DynamicLibrary _lib;

  SpeccyCoreBindings._(this._lib);

  factory SpeccyCoreBindings.load({String? libraryPath}) {
    final DynamicLibrary lib;
    if (Platform.isLinux) {
      lib = DynamicLibrary.open(libraryPath ?? 'libspeccycore.so');
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open(libraryPath ?? 'libspeccycore.so');
    } else if (Platform.isIOS) {
      lib = libraryPath != null
          ? DynamicLibrary.open(libraryPath)
          : DynamicLibrary.process();
    } else {
      throw UnsupportedError(
          'retro_spectrum: no libspeccycore binding for ${Platform.operatingSystem}');
    }
    return SpeccyCoreBindings._(lib);
  }

  late final _init = _lib.lookupFunction<_VoidHandleStrStrNative, _VoidHandleStrStrDart>(
      'speccy_core_init');
  late final _setRom = _lib.lookupFunction<_VoidHandleIntPtrIntNative, _VoidHandleIntPtrIntDart>(
      'speccy_core_set_rom');
  late final _setFont = _lib.lookupFunction<_VoidHandlePtrIntNative, _VoidHandlePtrIntDart>(
      'speccy_core_set_font');
  late final _start = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'speccy_core_start');
  late final _stop = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'speccy_core_stop');
  late final _isRunning = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'speccy_core_is_running');
  late final _runFrame = _lib.lookupFunction<_StrHandleNative, _StrHandleDart>(
      'speccy_core_run_frame');
  late final _setPaused = _lib.lookupFunction<_VoidHandleIntNative, _VoidHandleIntDart>(
      'speccy_core_set_paused');
  late final _reset = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'speccy_core_reset');

  late final _getFramebuffer = _lib.lookupFunction<_FbHandleNative, _FbHandleDart>(
      'speccy_core_get_framebuffer');
  late final _getFrameCounter = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'speccy_core_get_frame_counter');

  late final _drainAudio = _lib.lookupFunction<_IntHandlePtrIntNative, _IntHandlePtrIntDart>(
      'speccy_core_drain_audio');
  late final _setSampleRate = _lib.lookupFunction<_VoidHandleIntNative, _VoidHandleIntDart>(
      'speccy_core_set_sample_rate');
  late final _getAudioLevel = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'speccy_core_get_audio_level');

  late final _keyEvent = _lib.lookupFunction<_VoidHandleIntIntNative, _VoidHandleIntIntDart>(
      'speccy_core_key_event');
  late final _kempston = _lib.lookupFunction<_VoidHandleIntNative, _VoidHandleIntDart>(
      'speccy_core_kempston');

  late final _fileTypeSupported = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'speccy_core_file_type_supported');
  late final _openFile = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'speccy_core_open_file');
  late final _openData = _lib.lookupFunction<_IntHandleStrPtrIntNative, _IntHandleStrPtrIntDart>(
      'speccy_core_open_data');
  late final _saveFile = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'speccy_core_save_file');
  late final _tapeState = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'speccy_core_tape_state');
  late final _tapeToggle = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'speccy_core_tape_toggle');
  late final _diskChanged = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'speccy_core_disk_changed');

  late final _saveState = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'speccy_core_save_state');
  late final _loadState = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'speccy_core_load_state');

  late final _getOptionInt = _lib.lookupFunction<_IntStrIntNative, _IntStrIntDart>(
      'speccy_core_get_option_int');
  late final _setOptionInt = _lib.lookupFunction<_VoidStrIntNative, _VoidStrIntDart>(
      'speccy_core_set_option_int');
  late final _getOptionBool = _lib.lookupFunction<_IntStrIntNative, _IntStrIntDart>(
      'speccy_core_get_option_bool');
  late final _setOptionBool = _lib.lookupFunction<_VoidStrIntNative, _VoidStrIntDart>(
      'speccy_core_set_option_bool');
  late final _storeOptions = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'speccy_core_store_options');

  late final _getFpsX100 = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'speccy_core_get_fps_x100');

  // ============================================================
  //  Public Dart wrappers
  // ============================================================

  ffi.Pointer<ffi.Uint8> create() {
    // The bridge has no create/destroy and no handle: speccy_bridge.h owns
    // a singleton, and every entry point there takes no handle at all.
    //
    // This sentinel exists purely so the adapter keeps the shape the rest of
    // the app expects. It is NOT passed to native code, and passing it was
    // the bug: every call handed address 0x1 to a function whose first
    // parameter is something else entirely, so speccy_core_init read its
    // profile_dir from address 1 and the app died on launch with
    // "SIGSEGV, fault addr 0x1" before it drew a frame.
    return ffi.Pointer<ffi.Uint8>.fromAddress(1);
  }

  void destroy(ffi.Pointer<ffi.Uint8> p) {
    stop(p);
  }

  void init(ffi.Pointer<ffi.Uint8> p, String profileDir, String resourceDir) {
    final p1 = profileDir.toNativeUtf8();
    final p2 = resourceDir.toNativeUtf8();
    try {
      _init(p1, p2);
    } finally {
      calloc.free(p1);
      calloc.free(p2);
    }
  }

  void setRom(ffi.Pointer<ffi.Uint8> p, SpeccyRom rom,
      ffi.Pointer<ffi.Uint8> data, int size) {
    _setRom(rom.value, data, size);
  }

  void setFont(ffi.Pointer<ffi.Uint8> p, ffi.Pointer<ffi.Uint8> data, int size) {
    _setFont(data, size);
  }

  int start(ffi.Pointer<ffi.Uint8> p) => _start();

  void stop(ffi.Pointer<ffi.Uint8> p) => _stop();

  bool isRunning(ffi.Pointer<ffi.Uint8> p) => _isRunning() != 0;

  String? runFrame(ffi.Pointer<ffi.Uint8> p) {
    final ptr = _runFrame();
    if (ptr == nullptr) return null;
    return ptr.toDartString();
  }

  void setPaused(ffi.Pointer<ffi.Uint8> p, bool paused) =>
      _setPaused(paused ? 1 : 0);

  void reset(ffi.Pointer<ffi.Uint8> p) => _reset();

  /// Returns the current framebuffer (RGBA8888) and its size. The
  /// Uint8List is a copy — the underlying pointer is only valid until
  /// the next frame completes.
  FrameSnapshot? getFramebuffer(ffi.Pointer<ffi.Uint8> p) {
    final wPtr = calloc<ffi.Int32>();
    final hPtr = calloc<ffi.Int32>();
    try {
      final fbPtr = _getFramebuffer(wPtr, hPtr);
      final w = wPtr.value;
      final h = hPtr.value;
      if (fbPtr == nullptr || w == 0 || h == 0) return null;
      final len = w * h;
      final list = Uint8List.fromList(fbPtr.asTypedList(len * 4));
      return FrameSnapshot(width: w, height: h, rgba: list);
    } finally {
      calloc.free(wPtr);
      calloc.free(hPtr);
    }
  }

  int getFrameCounter(ffi.Pointer<ffi.Uint8> p) => _getFrameCounter();

  int drainAudio(ffi.Pointer<ffi.Uint8> p, ffi.Pointer<ffi.Uint8> dst, int maxBytes) =>
      _drainAudio(dst, maxBytes);

  void setSampleRate(ffi.Pointer<ffi.Uint8> p, int rate) => _setSampleRate(rate);

  int getAudioLevel(ffi.Pointer<ffi.Uint8> p) => _getAudioLevel();

  void keyEvent(ffi.Pointer<ffi.Uint8> p, int key, int flags) =>
      _keyEvent(key, flags);

  void kempston(ffi.Pointer<ffi.Uint8> p, int mask) => _kempston(mask);

  bool fileTypeSupported(ffi.Pointer<ffi.Uint8> p, String name) {
    final n = name.toNativeUtf8();
    try {
      return _fileTypeSupported(n) != 0;
    } finally {
      calloc.free(n);
    }
  }

  int openFile(ffi.Pointer<ffi.Uint8> p, String path) {
    final n = path.toNativeUtf8();
    try {
      return _openFile(n);
    } finally {
      calloc.free(n);
    }
  }

  int openData(ffi.Pointer<ffi.Uint8> p, String name, ffi.Pointer<ffi.Uint8> data,
      int size) {
    final n = name.toNativeUtf8();
    try {
      return _openData(n, data, size);
    } finally {
      calloc.free(n);
    }
  }

  int saveFile(ffi.Pointer<ffi.Uint8> p, String path) {
    final n = path.toNativeUtf8();
    try {
      return _saveFile(n);
    } finally {
      calloc.free(n);
    }
  }

  int tapeState(ffi.Pointer<ffi.Uint8> p) => _tapeState();

  void tapeToggle(ffi.Pointer<ffi.Uint8> p) => _tapeToggle();

  bool diskChanged(ffi.Pointer<ffi.Uint8> p) => _diskChanged() != 0;

  int saveState(ffi.Pointer<ffi.Uint8> p, String path) {
    final n = path.toNativeUtf8();
    try {
      return _saveState(n);
    } finally {
      calloc.free(n);
    }
  }

  int loadState(ffi.Pointer<ffi.Uint8> p, String path) {
    final n = path.toNativeUtf8();
    try {
      return _loadState(n);
    } finally {
      calloc.free(n);
    }
  }

  int getOptionInt(String name, int fallback) {
    final n = name.toNativeUtf8();
    try {
      return _getOptionInt(n, fallback);
    } finally {
      calloc.free(n);
    }
  }

  void setOptionInt(String name, int value) {
    final n = name.toNativeUtf8();
    try {
      _setOptionInt(n, value);
    } finally {
      calloc.free(n);
    }
  }

  bool getOptionBool(String name, bool fallback) {
    final n = name.toNativeUtf8();
    try {
      return _getOptionBool(n, fallback ? 1 : 0) != 0;
    } finally {
      calloc.free(n);
    }
  }

  void setOptionBool(String name, bool value) {
    final n = name.toNativeUtf8();
    try {
      _setOptionBool(n, value ? 1 : 0);
    } finally {
      calloc.free(n);
    }
  }

  void storeOptions(ffi.Pointer<ffi.Uint8> p) => _storeOptions();

  /// FPS scaled by 100 (i.e. 5000 == 50.00 fps).
  int getFpsX100(ffi.Pointer<ffi.Uint8> p) => _getFpsX100();
}

/// A snapshot of the emulator's current framebuffer.
class FrameSnapshot {
  final int width;
  final int height;
  /// RGBA8888. The native pixel format is fed directly to
  /// `ui.decodeImageFromPixels(..., PixelFormat.rgba8888)`.
  final Uint8List rgba;

  FrameSnapshot({required this.width, required this.height, required this.rgba});
}
