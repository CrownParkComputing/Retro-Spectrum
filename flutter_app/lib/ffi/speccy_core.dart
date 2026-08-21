// speccy_core.dart — abstract `SpeccyCore` interface + concrete
// `SpeccyCoreBindingsAdapter` implementation. Mirrors Retro-Saturn's
// `speccy_core.dart` so screens never touch `dart:ffi` directly.

import 'dart:ffi';
import 'dart:ffi' as ffi;

import 'speccy_bindings.dart';

/// Abstract interface — everything screens need from the emulator.
/// Tests provide a `FakeSpeccyCore`; production uses
/// `SpeccyCoreBindingsAdapter`.
abstract class SpeccyCore {
  /// Native handle (opaque). Non-null after [init] succeeds.
  Pointer<Uint8>? get handle;

  /// Lifecycle.
  void init(String profileDir, String resourceDir);
  void start();
  void stop();
  void dispose();

  // ROM/font
  void setRom(SpeccyRom rom, Pointer<Uint8> data, int size);
  void setFont(Pointer<Uint8> data, int size);

  // Emulation
  String? runFrame();
  void reset();
  void setPaused(bool paused);
  bool get isRunning;

  // Video
  FrameSnapshot? get framebuffer;
  int get frameCounter;

  // Audio
  int drainAudio(Pointer<Uint8> dst, int maxBytes);
  void setSampleRate(int rate);
  int get audioLevel;

  // Input
  void keyEvent(int key, int flags);
  void kempston(int mask);

  // Media
  bool fileTypeSupported(String name);
  int openFile(String path);
  int openData(String name, Pointer<Uint8> data, int size);
  int saveFile(String path);
  int get tapeState;
  void tapeToggle();
  bool get diskChanged;

  // Save states
  int saveState(String path);
  int loadState(String path);

  // Options
  int getOptionInt(String name, int fallback);
  void setOptionInt(String name, int value);
  bool getOptionBool(String name, bool fallback);
  void setOptionBool(String name, bool value);
  void storeOptions();

  // Status
  int get fpsX100;
}

/// Concrete production implementation backed by `dart:ffi`.
class SpeccyCoreBindingsAdapter implements SpeccyCore {
  final SpeccyCoreBindings _bindings;
  ffi.Pointer<ffi.Uint8>? _handle;

  SpeccyCoreBindingsAdapter(this._bindings);

  @override
  ffi.Pointer<ffi.Uint8>? get handle => _handle;

  @override
  void init(String profileDir, String resourceDir) {
    _handle ??= _bindings.create();
    _bindings.init(_handle!, profileDir, resourceDir);
  }

  @override
  void start() {
    final p = _h();
    _bindings.start(p);
  }

  @override
  void stop() {
    final p = _handle;
    if (p != null) _bindings.stop(p);
  }

  @override
  void dispose() {
    final p = _handle;
    if (p != null) {
      _bindings.destroy(p);
      _handle = null;
    }
  }

  ffi.Pointer<ffi.Uint8> _h() {
    final p = _handle;
    if (p == null) {
      throw StateError('SpeccyCore.init() was never called');
    }
    return p;
  }

  @override
  void setRom(SpeccyRom rom, Pointer<Uint8> data, int size) =>
      _bindings.setRom(_h(), rom, data, size);

  @override
  void setFont(Pointer<Uint8> data, int size) =>
      _bindings.setFont(_h(), data, size);

  @override
  String? runFrame() => _bindings.runFrame(_h());

  @override
  void reset() => _bindings.reset(_h());

  @override
  void setPaused(bool paused) => _bindings.setPaused(_h(), paused);

  @override
  bool get isRunning => _bindings.isRunning(_h());

  @override
  FrameSnapshot? get framebuffer => _bindings.getFramebuffer(_h());

  @override
  int get frameCounter => _bindings.getFrameCounter(_h());

  @override
  int drainAudio(Pointer<Uint8> dst, int maxBytes) =>
      _bindings.drainAudio(_h(), dst, maxBytes);

  @override
  void setSampleRate(int rate) => _bindings.setSampleRate(_h(), rate);

  @override
  int get audioLevel => _bindings.getAudioLevel(_h());

  @override
  void keyEvent(int key, int flags) => _bindings.keyEvent(_h(), key, flags);

  @override
  void kempston(int mask) => _bindings.kempston(_h(), mask);

  @override
  bool fileTypeSupported(String name) => _bindings.fileTypeSupported(_h(), name);

  @override
  int openFile(String path) => _bindings.openFile(_h(), path);

  @override
  int openData(String name, Pointer<Uint8> data, int size) =>
      _bindings.openData(_h(), name, data, size);

  @override
  int saveFile(String path) => _bindings.saveFile(_h(), path);

  @override
  int get tapeState => _bindings.tapeState(_h());

  @override
  void tapeToggle() => _bindings.tapeToggle(_h());

  @override
  bool get diskChanged => _bindings.diskChanged(_h());

  @override
  int saveState(String path) => _bindings.saveState(_h(), path);

  @override
  int loadState(String path) => _bindings.loadState(_h(), path);

  @override
  int getOptionInt(String name, int fallback) =>
      _bindings.getOptionInt(name, fallback);

  @override
  void setOptionInt(String name, int value) =>
      _bindings.setOptionInt(name, value);

  @override
  bool getOptionBool(String name, bool fallback) =>
      _bindings.getOptionBool(name, fallback);

  @override
  void setOptionBool(String name, bool value) =>
      _bindings.setOptionBool(name, value);

  @override
  void storeOptions() => _bindings.storeOptions(_h());

  @override
  int get fpsX100 => _bindings.getFpsX100(_h());
}
