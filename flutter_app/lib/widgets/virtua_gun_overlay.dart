// virtua_gun_overlay.dart — Stub. The Spectrum has no light gun
// peripheral, so this is a no-op widget. The full Retro-Saturn
// implementation is ported 1:1 once a Spectrum light-gun mode
// (e.g. for the handful of games that supported a "pistola"
// joystick) is reintroduced.

import 'package:flutter/material.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';

class VirtuaGunOverlay extends StatelessWidget {
  final SpeccyCore core;
  final int port;

  const VirtuaGunOverlay({super.key, required this.core, this.port = 1});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
