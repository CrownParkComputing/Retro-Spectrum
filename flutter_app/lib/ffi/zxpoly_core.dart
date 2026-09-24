// zxpoly_core.dart — abstract `ZxpolyCore` interface + concrete
// `ZxpolyCoreBindingsAdapter` implementation. Mirrors Retro-Saturn's
// `zxpoly_core.dart` so screens never touch `dart:ffi` directly.

import 'dart:ffi';

import 'zxpoly_bindings.dart';

/// Abstract interface — everything screens need from the emulator.
/// Tests provide a `FakeZxpolyCore`; production uses
/// `ZxpolyCoreBindingsAdapter`.
abstract class ZxpolyCore {

  /// Lifecycle.
  void init(String profileDir, String resourceDir);
  void start();
  void stop();
  void dispose();

  // ROM/font
  void setRom(ZxpolyRom rom, Pointer<Uint8> data, int size);
  void setFont(Pointer<Uint8> data, int size);

  /// Auto-recolour. The whole point of the zxpoly swap. Default on.
  /// Per-game toggle in the UI calls setRecolour before openFile().
  void setRecolour(bool enabled);
  bool get recolour;

  /// Run the recolour preprocess against the currently-loaded game.
  /// Called by the UI after a short delay (the .tap loader needs
  /// seconds to finish populating memory) or in response to an
  /// explicit user action. No-op when [recolour] is false.
  int recolourNow();

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
class ZxpolyCoreBindingsAdapter implements ZxpolyCore {
  final ZxpolyCoreBindings _bindings;

  /// Whether init() has run. The bridge owns a singleton and hands back no
  /// handle, so this is the only "is it up?" there is -- and the reason the
  /// adapter used to invent one. See ZxpolyCoreBindings.
  bool _initialised = false;

  ZxpolyCoreBindingsAdapter(this._bindings);

  @override
  void init(String profileDir, String resourceDir) {
    _bindings.init(profileDir, resourceDir);
    _initialised = true;
  }

  @override
  void start() {
    if (!_initialised) {
      throw StateError('ZxpolyCore.init() was never called');
    }
    _bindings.start();
  }

  @override
  void stop() {
    if (_initialised) _bindings.stop();
  }

  @override
  void dispose() {
    // Nothing to free: zxpoly_bridge.h has no destroy, because there is no
    // per-instance state to destroy. Stopping is the whole teardown.
    stop();
    _initialised = false;
  }

  @override
  void setRom(ZxpolyRom rom, Pointer<Uint8> data, int size) =>
      _bindings.setRom(rom, data, size);

  @override
  void setFont(Pointer<Uint8> data, int size) =>
      _bindings.setFont(data, size);

  @override
  void setRecolour(bool enabled) => _bindings.setRecolour(enabled);

  @override
  bool get recolour => _bindings.getRecolour();

  @override
  int recolourNow() => _bindings.recolourNow();

  @override
  String? runFrame() => _bindings.runFrame();

  @override
  void reset() => _bindings.reset();

  @override
  void setPaused(bool paused) => _bindings.setPaused(paused);

  @override
  bool get isRunning => _bindings.isRunning();

  @override
  FrameSnapshot? get framebuffer => _bindings.getFramebuffer();

  @override
  int get frameCounter => _bindings.getFrameCounter();

  @override
  int drainAudio(Pointer<Uint8> dst, int maxBytes) =>
      _bindings.drainAudio(dst, maxBytes);

  @override
  void setSampleRate(int rate) => _bindings.setSampleRate(rate);

  @override
  int get audioLevel => _bindings.getAudioLevel();

  @override
  void keyEvent(int key, int flags) => _bindings.keyEvent(key, flags);

  @override
  void kempston(int mask) => _bindings.kempston(mask);

  @override
  bool fileTypeSupported(String name) => _bindings.fileTypeSupported(name);

  @override
  int openFile(String path) => _bindings.openFile(path);

  @override
  int openData(String name, Pointer<Uint8> data, int size) =>
      _bindings.openData(name, data, size);

  @override
  int saveFile(String path) => _bindings.saveFile(path);

  @override
  int get tapeState => _bindings.tapeState();

  @override
  void tapeToggle() => _bindings.tapeToggle();

  @override
  bool get diskChanged => _bindings.diskChanged();

  @override
  int saveState(String path) => _bindings.saveState(path);

  @override
  int loadState(String path) => _bindings.loadState(path);

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
  void storeOptions() => _bindings.storeOptions();

  @override
  int get fpsX100 => _bindings.getFpsX100();
}
