// spectrum_keyboard.dart — The Spectrum's own 40 keys, on screen.
//
// This replaces a stub that drew nothing, left over from the Saturn front
// end this app was copied from: a Saturn has a 12-button pad, and one
// keyboard letter per gamepad face was never going to be the right mental
// model for a machine whose games say "Press any key" and mean it.
//
// Four rows of ten, laid out as the rubber mat is, so muscle memory and
// every loading screen's instructions still apply.
//
// CAPS SHIFT and SYMBOL SHIFT latch rather than needing to be held. On
// hardware you hold one and press another; on a touchscreen that is a
// two-finger contortion, so tapping arms them until tapped again and the
// key stays lit while it is armed. They are sent as real key presses --
// the engine treats 'c' and 's' as keys in their own right -- so a game
// reading the keyboard matrix directly sees exactly what it would see if
// someone were holding them down.
import 'package:flutter/material.dart';

import '../data/spectrum_keys.dart';
import '../ffi/speccy_core.dart';

class SpectrumKeyboard extends StatefulWidget {
  const SpectrumKeyboard({super.key, required this.core});

  final SpeccyCore core;

  @override
  State<SpectrumKeyboard> createState() => _SpectrumKeyboardState();
}

class _SpectrumKeyboardState extends State<SpectrumKeyboard> {
  /// The latched modifiers, held down at the engine until released.
  final Set<int> _latched = <int>{};

  /// The key currently under a finger, for the pressed highlight.
  int? _pressed;

  bool _isModifier(int code) =>
      code == SpeccyKey.capsShift || code == SpeccyKey.symbolShift;

  void _down(SpectrumKeyCap cap) {
    if (_isModifier(cap.code)) {
      setState(() {
        if (_latched.remove(cap.code)) {
          widget.core.keyEvent(cap.code, 0);
        } else {
          _latched.add(cap.code);
          widget.core.keyEvent(cap.code, SpeccyKeyFlags.down);
        }
      });
      return;
    }
    setState(() => _pressed = cap.code);
    widget.core.keyEvent(cap.code, SpeccyKeyFlags.down);
  }

  void _up(SpectrumKeyCap cap) {
    if (_isModifier(cap.code)) return; // latched; released by tapping again
    widget.core.keyEvent(cap.code, 0);
    if (mounted) setState(() => _pressed = null);
  }

  @override
  void dispose() {
    // Leaving with a modifier still down would wedge it for the next
    // session -- the engine has no idea this widget went away.
    for (final code in _latched) {
      widget.core.keyEvent(code, 0);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in kSpectrumLayout)
            Row(
              children: [
                for (final cap in row)
                  Expanded(
                    // The wide keys earn their extra width from the same
                    // ten-column grid, so the rows still line up.
                    flex: cap.wide ? 3 : 2,
                    child: _Key(
                      cap: cap,
                      pressed: _pressed == cap.code,
                      latched: _latched.contains(cap.code),
                      onDown: () => _down(cap),
                      onUp: () => _up(cap),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.cap,
    required this.pressed,
    required this.latched,
    required this.onDown,
    required this.onUp,
  });

  final SpectrumKeyCap cap;
  final bool pressed;
  final bool latched;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final lit = pressed || latched;
    return Listener(
      // Pointer events, not a tap: a tap is only recognised on release, so
      // a held direction would not reach the game until the finger left.
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: Container(
        margin: const EdgeInsets.all(2),
        height: 38,
        decoration: BoxDecoration(
          color: lit ? const Color(0xFF2B6FE0) : const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: lit ? const Color(0xFF7FB2FF) : const Color(0xFF31313C),
          ),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              cap.label,
              style: TextStyle(
                color: lit ? Colors.white : Colors.white70,
                fontSize: cap.wide ? 10 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
