// peripheral_selector.dart — Lets the user pick which input surface
// is active for each port. The Spectrum has only two surfaces
// (Keyboard, Kempston) so the picker is short. The choice is
// informational: the bridge simultaneously routes keyboard events
// + Kempston bits, so the picker is just a "what is plugged in"
// affordance the UI can show.

import 'package:flutter/material.dart';
import 'package:retro_spectrum/data/peripheral_type.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';

class PeripheralSelector extends StatelessWidget {
  final SpeccyCore core;
  final int port;

  const PeripheralSelector({super.key, required this.core, this.port = 1});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Port $port',
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: _Surface(
                  core: core,
                  port: port,
                  type: SpeccyPeripheralType.keyboard,
                  label: 'Keyboard',
                  description: 'Standard ZX-Spectrum keyboard matrix.',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Surface(
                  core: core,
                  port: port,
                  type: SpeccyPeripheralType.kempston,
                  label: 'Kempston',
                  description: 'Five-button Kempston joystick.',
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  final SpeccyCore core;
  final int port;
  final SpeccyPeripheralType type;
  final String label;
  final String description;

  const _Surface({
    required this.core,
    required this.port,
    required this.type,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF202028),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.white)),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}
