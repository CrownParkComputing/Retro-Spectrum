// saturn_pad_overlay.dart — Stub. The Spectrum's "pad" is a 40-key
// keyboard, not a 12-button Saturn pad. The full retro-Saturn
// `_SaturnPadOverlay` is ported 1:1 once the on-screen keyboard
// layout is finalized; until then, this file is a no-op widget so
// the surrounding code (workbench_screen.dart) keeps compiling.
//
// The real implementation will:
//   - Render a ZX-Spectrum keyboard layout (40 keys in 5 rows of 8)
//   - On tap, call core.keyEvent(asciiCode, flags) on press and again
//     with flags=0 on release
//   - Highlight the currently-pressed key (driven by the gamepads
//     service's keyEvents stream)

import 'package:flutter/material.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';

class SaturnPadOverlay extends StatelessWidget {
  final SpeccyCore core;
  final List<int> pressedKeys = const [];

  const SaturnPadOverlay({super.key, required this.core});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
