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
import '../services/app_prefs.dart';
import 'dpad_view.dart';
import 'movable_control.dart';
import 'wobble_joystick.dart';

/// Which stick to draw. Stored per user; see AppPrefs.
enum JoystickStyle { wobble, dpad }

class KempstonPad extends StatefulWidget {
  const KempstonPad({
    super.key,
    required this.core,
    this.style = JoystickStyle.wobble,
    this.editing = false,
  });

  final SpeccyCore core;
  final JoystickStyle style;

  /// Drag mode: the stick and fire button can be moved, and say so.
  final bool editing;

  @override
  State<KempstonPad> createState() => _KempstonPadState();
}

class _KempstonPadState extends State<KempstonPad> {
  int _mask = 0;

  /// Where each control has been dragged to, as a fraction of the play
  /// area. Empty means "never moved" -- see AppPrefs.getControlPositions.
  Map<String, Offset> _positions = const {};

  @override
  void initState() {
    super.initState();
    _loadPositions();
  }

  Future<void> _loadPositions() async {
    final positions = await AppPrefs.getControlPositions();
    if (!mounted) return;
    setState(() => _positions = positions);
  }

  /// Bottom-left for the stick and bottom-right for fire: the corners a
  /// thumb reaches without moving the hand holding the device.
  static const _defaults = <String, Offset>{
    kControlIdStick: Offset(0.16, 0.74),
    kControlIdFire: Offset(0.86, 0.74),
  };

  Offset _fraction(String id) => _positions[id] ?? _defaults[id]!;

  void _move(String id, Offset fraction) =>
      setState(() => _positions = {..._positions, id: fraction});

  void _commit(String id) => AppPrefs.setControlPosition(id, _fraction(id));

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
    // LayoutBuilder, because the stored positions are fractions and can
    // only become pixels once the play area has a size.
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        return Stack(
          children: [
            MovableControl(
              area: area,
              fraction: _fraction(kControlIdStick),
              editing: widget.editing,
              label: 'Joystick',
              onMoved: (f) => _move(kControlIdStick, f),
              onMoveEnd: () => _commit(kControlIdStick),
              child: switch (widget.style) {
                JoystickStyle.wobble =>
                  WobbleJoystick(onDirections: _directions),
                JoystickStyle.dpad => DpadView(onDirections: _directions),
              },
            ),
            MovableControl(
              area: area,
              fraction: _fraction(kControlIdFire),
              editing: widget.editing,
              label: 'Fire',
              onMoved: (f) => _move(kControlIdFire, f),
              onMoveEnd: () => _commit(kControlIdFire),
              child: _FireButton(
                onChanged: (down) => _send(KempstonBit.fire, down),
              ),
            ),
          ],
        );
      },
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
