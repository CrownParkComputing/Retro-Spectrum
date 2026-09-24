// zxpoly_bindings.dart — raw `dart:ffi` typedefs for the C ABI in
// native/zxpoly_bridge/bridge/zxpoly_bridge.h.
//
// Functions are int32 returning except setters (void) and
// `_get_*` accessors. The framebuffer is RGBA8888 (the bridge does the
// 4-CPU colour-index → RGBA conversion itself, mirroring the JVM-side
// renderer so the four video RAMs combine into a single 4-bit-per-pixel
// image). Dart's `ui.decodeImageFromPixels` accepts RGBA8888 directly on
// little-endian platforms (all three targets).

import 'dart:ffi';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Spectrum machine models — matches the ZXPOLY_MODEL_* macros in
/// zxpoly_bridge.h. (Phase 2 will populate these from the JVM-side
/// enum; phase 1 keeps the same shape as the old SimpleSpeccy era.)
enum ZxpolyModel {
  model48k(0),
  model128k(1);

  const ZxpolyModel(this.value);
  final int value;
}

/// ROM slots — matches the ZXPOLY_ROM_* enum in zxpoly_bridge.h.
/// The ids are pinned to the order zxpoly expects; do not renumber.
enum ZxpolyRom {
  sos128_0(0),
  sos128_1(1),
  sos48(2),
  service(3),
  dos(4);

  const ZxpolyRom(this.value);
  final int value;
}

/// Error codes returned by all `zxpoly_bridge_*` functions that
/// return int32.
class ZxpolyErr {
  static const ok = 0;
  static const errGeneric = -1;
  static const errNotImpl = -2;   // phase 2 stub
  static const errBadArg = -3;
  static const errNoMem = -4;
  static const errNoFile = -5;
  static const errBadFile = -6;
  static const errNoRom = -7;
}

// ============================================================
//  Native typedefs (mirrored from zxpoly_bridge.h)
// ============================================================

typedef _C = ffi.Pointer<Utf8>; // const char* (C string)

typedef _VoidHandleNative = ffi.Void Function();
typedef _VoidHandleDart = void Function();

typedef _IntHandleStrNative = ffi.Int32 Function(_C);
typedef _IntHandleStrDart = int Function(ffi.Pointer<Utf8>);

typedef _VoidHandleIntIntNative = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _VoidHandleIntIntDart = void Function(int, int);

typedef _IntHandleNative = ffi.Int32 Function();
typedef _IntHandleDart = int Function();

typedef _VoidHandleIntNative = ffi.Void Function(ffi.Int32);
typedef _VoidHandleIntDart = void Function(int);

typedef _VoidStrIntNative = ffi.Void Function(_C, ffi.Int32);
typedef _VoidStrIntDart = void Function(ffi.Pointer<Utf8>, int);

typedef _IntStrIntNative = ffi.Int32 Function(_C, ffi.Int32);
typedef _IntStrIntDart = int Function(ffi.Pointer<Utf8>, int);

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

/// Low-level bindings to libemulator_bridge.{so,dylib}.
class ZxpolyCoreBindings {
  final DynamicLibrary _lib;

  ZxpolyCoreBindings._(this._lib);

  factory ZxpolyCoreBindings.load({String? libraryPath}) {
    final DynamicLibrary lib;
    if (Platform.isLinux) {
      lib = DynamicLibrary.open(libraryPath ?? 'libemulator_bridge.so');
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open(libraryPath ?? 'libemulator_bridge.so');
    } else if (Platform.isIOS) {
      lib = libraryPath != null
          ? DynamicLibrary.open(libraryPath)
          : DynamicLibrary.process();
    } else {
      throw UnsupportedError(
          'retro_spectrum: no libzxpolycore binding for ${Platform.operatingSystem}');
    }
    return ZxpolyCoreBindings._(lib);
  }

  late final _init = _lib.lookupFunction<_VoidHandleStrStrNative, _VoidHandleStrStrDart>(
      'zxpoly_bridge_init');
  late final _setRom = _lib.lookupFunction<_VoidHandleIntPtrIntNative, _VoidHandleIntPtrIntDart>(
      'zxpoly_bridge_set_rom');
  late final _setFont = _lib.lookupFunction<_VoidHandlePtrIntNative, _VoidHandlePtrIntDart>(
      'zxpoly_bridge_set_font');
  late final _setRecolour = _lib.lookupFunction<_VoidHandleIntNative, _VoidHandleIntDart>(
      'zxpoly_bridge_set_recolour');
  late final _getRecolour = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_get_recolour');
  late final _recolourNow = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_recolour_now');
  late final _start = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_start');
  late final _stop = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'zxpoly_bridge_stop');
  late final _isRunning = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_is_running');
  late final _runFrame = _lib.lookupFunction<_StrHandleNative, _StrHandleDart>(
      'zxpoly_bridge_run_frame');
  late final _setPaused = _lib.lookupFunction<_VoidHandleIntNative, _VoidHandleIntDart>(
      'zxpoly_bridge_set_paused');
  late final _reset = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'zxpoly_bridge_reset');

  late final _getFramebuffer = _lib.lookupFunction<_FbHandleNative, _FbHandleDart>(
      'zxpoly_bridge_get_framebuffer');
  late final _getFrameCounter = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_frame_counter');

  late final _drainAudio = _lib.lookupFunction<_IntHandlePtrIntNative, _IntHandlePtrIntDart>(
      'zxpoly_bridge_drain_audio');
  late final _setSampleRate = _lib.lookupFunction<_VoidHandleIntNative, _VoidHandleIntDart>(
      'zxpoly_bridge_set_sample_rate');
  late final _getAudioLevel = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_audio_level');

  late final _keyEvent = _lib.lookupFunction<_VoidHandleIntIntNative, _VoidHandleIntIntDart>(
      'zxpoly_bridge_key_event');
  late final _kempston = _lib.lookupFunction<_VoidHandleIntNative, _VoidHandleIntDart>(
      'zxpoly_bridge_kempston');

  late final _fileTypeSupported = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'zxpoly_bridge_file_type_supported');
  late final _openFile = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'zxpoly_bridge_open_file');
  late final _openData = _lib.lookupFunction<_IntHandleStrPtrIntNative, _IntHandleStrPtrIntDart>(
      'zxpoly_bridge_open_data');
  late final _saveFile = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'zxpoly_bridge_save_file');
  late final _tapeState = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_tape_state');
  late final _tapeToggle = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'zxpoly_bridge_tape_toggle');
  late final _diskChanged = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_disk_changed');

  late final _saveState = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'zxpoly_bridge_save_state');
  late final _loadState = _lib.lookupFunction<_IntHandleStrNative, _IntHandleStrDart>(
      'zxpoly_bridge_load_state');

  late final _getOptionInt = _lib.lookupFunction<_IntStrIntNative, _IntStrIntDart>(
      'zxpoly_bridge_get_option_int');
  late final _setOptionInt = _lib.lookupFunction<_VoidStrIntNative, _VoidStrIntDart>(
      'zxpoly_bridge_set_option_int');
  late final _getOptionBool = _lib.lookupFunction<_IntStrIntNative, _IntStrIntDart>(
      'zxpoly_bridge_get_option_bool');
  late final _setOptionBool = _lib.lookupFunction<_VoidStrIntNative, _VoidStrIntDart>(
      'zxpoly_bridge_set_option_bool');
  late final _storeOptions = _lib.lookupFunction<_VoidHandleNative, _VoidHandleDart>(
      'zxpoly_bridge_store_options');

  late final _getFpsX100 = _lib.lookupFunction<_IntHandleNative, _IntHandleDart>(
      'zxpoly_bridge_get_fps_x100');

  // ============================================================
  //  Public Dart wrappers
  // ============================================================

  void init(String profileDir, String resourceDir) {
    final p1 = profileDir.toNativeUtf8();
    final p2 = resourceDir.toNativeUtf8();
    try {
      _init(p1, p2);
    } finally {
      calloc.free(p1);
      calloc.free(p2);
    }
  }

  void setRom(ZxpolyRom rom,
      ffi.Pointer<ffi.Uint8> data, int size) {
    _setRom(rom.value, data, size);
  }

  void setFont(ffi.Pointer<ffi.Uint8> data, int size) {
    _setFont(data, size);
  }

  /// Auto-recolour: 1 = on (default), 0 = off. Per-game toggle in the UI
  /// calls this before open_file(). The recolour preprocess runs
  /// synchronously inside open_file when on; the first presented frame
  /// is already the full-colour version.
  void setRecolour(bool enabled) => _setRecolour(enabled ? 1 : 0);
  bool getRecolour() => _getRecolour() != 0;

  /// Run the recolour preprocess now -- the Dart UI calls this after
  /// the .tap loader has populated the screen, since .tap loading is
  /// multi-second. Returns 0 on success; a negative ZXPOLY_ERR_* code
  /// on failure. No-op when the toggle is off.
  int recolourNow() => _recolourNow();

  int start() => _start();

  void stop() => _stop();

  bool isRunning() => _isRunning() != 0;

  String? runFrame() {
    final ptr = _runFrame();
    if (ptr == nullptr) return null;
    return ptr.toDartString();
  }

  void setPaused(bool paused) =>
      _setPaused(paused ? 1 : 0);

  void reset() => _reset();

  /// Returns the current framebuffer (RGBA8888) and its size. The
  /// Uint8List is a copy — the underlying pointer is only valid until
  /// the next frame completes.
  FrameSnapshot? getFramebuffer() {
    final wPtr = calloc<ffi.Int32>();
    final hPtr = calloc<ffi.Int32>();
    try {
      final fbPtr = _getFramebuffer(wPtr, hPtr);
      final w = wPtr.value;
      final h = hPtr.value;
      if (fbPtr == nullptr || w == 0 || h == 0) return null;
      // asTypedList counts ELEMENTS, and fbPtr is a Pointer<Uint32>: one
      // element is one pixel, not one byte. Asking for len * 4 asked for
      // four times the whole framebuffer -- 1.2 MB read out of a 307 KB
      // array -- and the read ran off the end of the mapping and took the
      // process down with SIGSEGV the moment a game was launched.
      final len = w * h;
      final pixels = fbPtr.asTypedList(len);
      // Copied, not viewed: the core overwrites this buffer on the next
      // frame, and a view would change under the decoder.
      final rgba = Uint8List.fromList(
          pixels.buffer.asUint8List(pixels.offsetInBytes, len * 4));
      return FrameSnapshot(width: w, height: h, rgba: rgba);
    } finally {
      calloc.free(wPtr);
      calloc.free(hPtr);
    }
  }

  int getFrameCounter() => _getFrameCounter();

  int drainAudio(ffi.Pointer<ffi.Uint8> dst, int maxBytes) =>
      _drainAudio(dst, maxBytes);

  void setSampleRate(int rate) => _setSampleRate(rate);

  int getAudioLevel() => _getAudioLevel();

  void keyEvent(int key, int flags) =>
      _keyEvent(key, flags);

  void kempston(int mask) => _kempston(mask);

  bool fileTypeSupported(String name) {
    final n = name.toNativeUtf8();
    try {
      return _fileTypeSupported(n) != 0;
    } finally {
      calloc.free(n);
    }
  }

  int openFile(String path) {
    final n = path.toNativeUtf8();
    try {
      return _openFile(n);
    } finally {
      calloc.free(n);
    }
  }

  int openData(String name, ffi.Pointer<ffi.Uint8> data,
      int size) {
    final n = name.toNativeUtf8();
    try {
      return _openData(n, data, size);
    } finally {
      calloc.free(n);
    }
  }

  int saveFile(String path) {
    final n = path.toNativeUtf8();
    try {
      return _saveFile(n);
    } finally {
      calloc.free(n);
    }
  }

  int tapeState() => _tapeState();

  void tapeToggle() => _tapeToggle();

  bool diskChanged() => _diskChanged() != 0;

  int saveState(String path) {
    final n = path.toNativeUtf8();
    try {
      return _saveState(n);
    } finally {
      calloc.free(n);
    }
  }

  int loadState(String path) {
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

  void storeOptions() => _storeOptions();

  /// FPS scaled by 100 (i.e. 5000 == 50.00 fps).
  int getFpsX100() => _getFpsX100();
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
