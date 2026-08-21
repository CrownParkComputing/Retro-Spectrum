// kempston_pad.dart — The on-screen joystick, wired to the Kempston port.
//
// A Spectrum game reads a joystick one of several ways, and Kempston is the
// one that behaves like a joystick rather than like keys: a single byte of
// direction bits and a fire bit, which is exactly the shape
// speccy_core_kempston takes. (The alternatives -- Sinclair, cursor, QAOP --
// are keyboard keys wearing a joystick's name; those are the on-screen
// keyboard's job, not this widget's.)
//
// The stick itself is Retro-C64's, ported unchanged: both machines have a
// digital 8-way port, so the same widget and the same dead zone apply. What
// differs is only where the bits go.
import 'package:flutter/material.dart';

import '../data/spectrum_keys.dart';
import '../ffi/speccy_core.dart';
import 'dpad_view.dart';
import 'wobble_joystick.dart';

/// Which stick to draw. Stored per user; see AppPrefs.
enum JoystickStyle { wobble, dpad }

class KempstonPad extends StatefulWidget {
  const KempstonPad({
    super.key,
    required this.core,
    this.style = JoystickStyle.wobble,
  });

  final SpeccyCore core;
  final JoystickStyle style;

  @override
  State<KempstonPad> createState() => _KempstonPadState();
}

class _KempstonPadState extends State<KempstonPad> {
  int _mask = 0;

  /// The port takes one byte holding every bit at once, so directions and
  /// fire have to be merged here rather than sent as separate events --
  /// otherwise pressing fire while running would cancel the direction.
  void _send(int bits, bool on) {
    final next = on ? (_mask | bits) : (_mask & ~bits);
    if (next == _mask) return;
    _mask = next;
    widget.core.kempston(_mask);
  }

  void _directions(bool up, bool down, bool left, bool right) {
    _send(KempstonBit.up, up);
    _send(KempstonBit.down, down);
    _send(KempstonBit.left, left);
    _send(KempstonBit.right, right);
  }

  @override
  void dispose() {
    // Centre the stick on the way out. Leaving a direction set would have
    // the game running into a wall with nothing on screen to explain it.
    if (_mask != 0) widget.core.kempston(0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          switch (widget.style) {
            JoystickStyle.wobble =>
              WobbleJoystick(onDirections: _directions),
            JoystickStyle.dpad => DpadView(onDirections: _directions),
          },
          const Spacer(),
          _FireButton(
            onChanged: (down) => _send(KempstonBit.fire, down),
          ),
        ],
      ),
    );
  }
}

class _FireButton extends StatefulWidget {
  const _FireButton({required this.onChanged});

  final void Function(bool down) onChanged;

  @override
  State<_FireButton> createState() => _FireButtonState();
}

class _FireButtonState extends State<_FireButton> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
    widget.onChanged(down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Pointer events rather than a tap, so holding fire holds it: a tap
      // is only recognised on release, which in a shoot-em-up is a shot you
      // never fired.
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _down
              ? const Color(0xFFD03030)
              : Colors.black.withValues(alpha: 0.45),
          border: Border.all(
            color: _down ? const Color(0xFFFF8080) : Colors.white24,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          'FIRE',
          style: TextStyle(
            color: _down ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
