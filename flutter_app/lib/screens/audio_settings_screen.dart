// audio_settings_screen.dart — Audio configuration for the Speccy
// core. Unlike the Saturn's Ymir bridge (which exposed a mute
// toggle), the Speccy bridge has no master mute; the only audio
// surface here is the live SCSP-style level meter and the sample
// rate picker. The user can also flip the "sound" option (the
// engine exposes sound on/off via the option registry).

import 'package:flutter/material.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';

class AudioSettingsScreen extends StatefulWidget {
  final SpeccyCore core;
  const AudioSettingsScreen({super.key, required this.core});

  @override
  State<AudioSettingsScreen> createState() => _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends State<AudioSettingsScreen> {
  bool _sound = true;

  @override
  void initState() {
    super.initState();
    _sound = widget.core.getOptionBool('sound', true);
  }

  void _setSound(bool v) {
    widget.core.setOptionBool('sound', v);
    setState(() => _sound = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      appBar: AppBar(title: const Text('🔊 Audio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _Section('Output'),
        SwitchListTile(
          title: const Text('Enable sound'),
          subtitle: const Text(
              'Master audio toggle. Mutes the Beeper / AY / tape audio. '
              'Off is the classic "silent" mode many games support.',
              style: TextStyle(fontSize: 11, color: Colors.white54)),
          value: _sound,
          onChanged: _setSound,
        ),
        const SizedBox(height: 24),
        const _Section('Live level'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _AudioLevelBar(level: widget.core.audioLevel, muted: !_sound),
        ),
        const SizedBox(height: 8),
        const Text(
          'The bar samples the audio mixer as it is mixed. The peak '
          'follows the AY music or beeper chatter. If the bar is flat '
          'while sound is playing, the engine is muted or the JVM '
          'has not yet produced output.',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        const SizedBox(height: 24),
        const _Section('Bridge status'),
        Text('FPS: ${widget.core.fpsX100 / 100.0}',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              color: Colors.white54,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _AudioLevelBar extends StatelessWidget {
  final int level;
  final bool muted;
  const _AudioLevelBar({required this.level, required this.muted});

  @override
  Widget build(BuildContext context) {
    final pct = (level.clamp(0, 1000)) / 1000.0;
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 100),
          widthFactor: muted ? 0 : pct,
          heightFactor: 1,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF50E3C2), Color(0xFF60A0FF)],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ]),
    );
  }
}
