// input_settings_screen.dart — Spectrum input surface. The Spectrum
// has only two input surfaces (keyboard + Kempston joystick), so this
// screen is intentionally short: a peripheral selector showing the
// active input surface per port, a quick-reference card of the
// keyboard faces a Spectrum game relies on, and a note on gamepad
// mapping.

import 'package:flutter/material.dart';
import 'package:retro_spectrum/data/spectrum_keys.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';

class InputSettingsScreen extends StatefulWidget {
  final SpeccyCore core;
  const InputSettingsScreen({super.key, required this.core});

  @override
  State<InputSettingsScreen> createState() => _InputSettingsScreenState();
}

class _InputSettingsScreenState extends State<InputSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      appBar: AppBar(title: const Text('🕹️ Input')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Peripherals',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Keyboard defaults',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final row in kSpectrumLayout)
                  for (final cap in row)
                    Chip(
                      label: Text(cap.label),
                      backgroundColor: const Color(0xFF202028),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.gamepad, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Gamepad input uses the platform gamepads plugin. Connect a '
                  'Bluetooth / USB controller and the d-pad, A/B/X/Y, '
                  'L/R + Start are mapped to the Spectrum keyboard + Kempston '
                  'directions automatically. The keyboard is the only '
                  'mandatory input surface.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
