// gamepad_service.dart — Maps physical gamepads (via the `gamepads` plugin)
// to the Spectrum's two input surfaces: keyboard + Kempston joystick.
//
// The Spectrum has no analog pad, no Virtua Gun, no mission stick. The
// D-pad maps to keyboard direction keys (5/6/7/8 on the Spectrum's
// keyboard matrix -- the row/column the game expects for "left")
// OR to the Kempston bitmask (up/down/left/right bits), and A/B/X/Y
// map to the most common keyboard faces (ENTER, SPACE, 0, M).
//
// The bridge exposes:
//
//   speccy_core_key_event(int key, int flags)
//   speccy_core_kempston(int mask)
//
// where key is the ASCII/matrix code, flags is xPlatform::eKeyFlags
// (KF_DOWN=1, KF_UP=0, with the shift/ctrl/alt/joystick-mode
// selectors in the high bits), and the kempston mask is 0=up
// up/down/left/right are bits 3/2/1/0, fire is bit 4.
//
// The bridge has no pad-mask API like Ymir's setPadButton. The
// emulator screen collects the service's `keyDown` / `keyUp` events
// and forwards them to the bridge.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';
import 'package:retro_spectrum/data/spectrum_keys.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';

/// Flag values from xPlatform::eKeyFlags on the native side.
const int _kfDown = 0x01;

class GamepadService extends ChangeNotifier {
  final SpeccyCore core;
  final int port;

  StreamSubscription? _sub;
  bool _disposed = false;
  bool _connected = false;

  /// Currently-held Kempston bitmask. 0 = nothing pressed; non-zero
  /// bits are directions (0x01 right, 0x02 left, 0x04 down, 0x08 up)
  /// and fire (0x10).
  int _kempston = 0;

  final StreamController<int> _kempstonChanges =
      StreamController<int>.broadcast();
  Stream<int> get kempstonChanges => _kempstonChanges.stream;
  int get currentKempston => _kempston;
  bool get connected => _connected;

  /// Currently-held key codes (ASCII), streamed as the user presses
  /// / releases them. The emulator screen forwards these to the
  /// bridge via `keyEvent(key, flags)`.
  final StreamController<GamepadKeyEvent> _keyEvents =
      StreamController<GamepadKeyEvent>.broadcast();
  Stream<GamepadKeyEvent> get keyEvents => _keyEvents.stream;

  GamepadService(this.core, {this.port = 1}) {
    _sub = Gamepads.normalizedEvents.listen(_handleEvent,
        onError: (Object e) => debugPrint('gamepad error: $e'));
  }

  @visibleForTesting
  void handleEvent(NormalizedGamepadEvent event) {
    final button = event.button;
    if (button != null) {
      final down = event.value != 0;
      switch (button) {
        case GamepadButton.dpadUp:
          _changeKempstonBit(KempstonBit.up, down);
          // '6' is the standard Spectrum cursor-up key.
          _emitKey(down ? 0x36 : 0x00, down);
          break;
        case GamepadButton.dpadDown:
          _changeKempstonBit(KempstonBit.down, down);
          _emitKey(down ? 0x32 : 0x00, down);
          break;
        case GamepadButton.dpadLeft:
          _changeKempstonBit(KempstonBit.left, down);
          _emitKey(down ? 0x38 : 0x00, down);
          break;
        case GamepadButton.dpadRight:
          _changeKempstonBit(KempstonBit.right, down);
          _emitKey(down ? 0x39 : 0x00, down);
          break;
        case GamepadButton.a:
          // A → ENTER (the typical "fire" key in Spectrum games).
          _emitKey(down ? 0x0D : 0x00, down);
          break;
        case GamepadButton.b:
          _emitKey(down ? 0x20 : 0x00, down); // SPACE
          break;
        case GamepadButton.x:
          _emitKey(down ? 0x30 : 0x00, down); // '0'
          break;
        case GamepadButton.y:
          _emitKey(down ? 0x4D : 0x00, down); // 'M'
          break;
        case GamepadButton.start:
          _emitKey(down ? 0x20 : 0x00, down); // SPACE
          break;
        default:
          break;
      }
      return;
    }
  }

  void _handleEvent(NormalizedGamepadEvent event) {
    try {
      handleEvent(event);
    } catch (e) {
      debugPrint('gamepad handler: $e');
    }
  }

  void _changeKempstonBit(int bit, bool down) {
    if (down) {
      _kempston |= bit;
    } else {
      _kempston &= ~bit;
    }
    _kempstonChanges.add(_kempston);
    core.kempston(_kempston);
    notifyListeners();
  }

  void _emitKey(int key, bool down) {
    _keyEvents.add(GamepadKeyEvent(key, down ? _kfDown : 0));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sub?.cancel();
    _kempstonChanges.close();
    _keyEvents.close();
    super.dispose();
  }
}

/// One key press or release from a physical pad, in the core's own terms:
/// [key] is what speccy_core_key_event takes, [flags] carries KF_DOWN.
///
/// Public because the emulator screen is what forwards these to the core.
/// While this was private the stream could not be consumed outside this
/// file at all, so every button mapped to a key was emitted and dropped.
class GamepadKeyEvent {
  final int key;
  final int flags;
  const GamepadKeyEvent(this.key, this.flags);
}
