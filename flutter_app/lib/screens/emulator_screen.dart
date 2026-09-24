// emulator_screen.dart — Renders the emulated framebuffer + the
// peripheral overlays (Virtua Gun, on-screen Saturn pad) inside the
// workbench's content panel. Loads BIOS + disc from the library grid
// tap, restores NVRAM (Saturn backup RAM), mounts the gamepad service,
// and auto-saves NVRAM every 60 seconds while playing.
//
// The in-game toolbar (pad toggle, settings, pause, close) lives in
// the workbench's status bar, beneath the content panel, matching
// Retro-C64's EmulatorControlStrip pattern. The settings drawer is
// rendered from the workbench too. This screen no longer owns its own
// Scaffold -- the emulator chrome is below the picture, not on it.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:retro_spectrum/data/media_entry.dart';
import 'package:retro_spectrum/ffi/zxpoly_core.dart';
import 'package:retro_spectrum/services/app_log.dart';
import 'package:retro_spectrum/services/game_state_service.dart';
import 'package:retro_spectrum/services/gamepad_service.dart';
import 'package:retro_spectrum/services/core_paths.dart';
import 'package:retro_spectrum/widgets/framebuffer_view.dart';
import 'package:retro_spectrum/widgets/kempston_pad.dart';
import 'package:retro_spectrum/widgets/spectrum_keyboard.dart';

class EmulatorScreen extends StatefulWidget {
  final ZxpolyCore core;
  final String? biosPath;
  final String? gamesFolder;
  final MediaEntry? entry;

  /// Owned by the workbench -- the in-game toolbar toggles this, and we
  /// render the on-screen Saturn pad when it is true. Lifting it out of
  /// EmulatorScreen means the pad toggle and the pad overlay see the
  /// same source of truth (the workbench), which is what the previous
  /// in-screen toolbar got wrong (toggle was here, overlay was never
  /// rendered).
  final bool showKeyboard;
  final bool showJoystick;
  final bool editingLayout;

  const EmulatorScreen({
    super.key,
    required this.core,
    this.biosPath,
    this.gamesFolder,
    this.entry,
    this.showKeyboard = false,
    this.showJoystick = false,
    this.editingLayout = false,
  });

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen> {
  GamepadService? _gamepad;
  StreamSubscription<GamepadKeyEvent>? _gamepadKeys;
  String _currentDisc = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMedia());
    final gamepad = GamepadService(widget.core, port: 1);
    // Kempston already goes straight to the core inside the service. Keys
    // did not: they were emitted onto a stream nothing subscribed to, so a
    // pad button mapped to a Spectrum key did nothing at all.
    _gamepadKeys = gamepad.keyEvents.listen(
        (e) => widget.core.keyEvent(e.key, e.flags));
    _gamepad = gamepad;
  }

  @override
  void dispose() {
    // Snapshot on the way out. Errors are swallowed: if the path is gone
    // (app uninstalled mid-launch) there is nothing to do about it here,
    // and dispose() crashing is worse than a lost auto-save.
    if (_currentDisc.isNotEmpty) {
      try {
        GameStateService.saveFrom(widget.core, _currentDisc);
      } catch (_) {}
    }
    GameStateService.stopAutoSave();
    try {
      try {
        widget.core.saveState(CorePaths.saveStatePath);
      } catch (_) {}
    } catch (_) {}
    _gamepadKeys?.cancel();
    _gamepad?.dispose();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    final entry = widget.entry;

    if (entry != null && File(entry.path).existsSync()) {
      _currentDisc = entry.path;
      // Auto-recolour: set BEFORE openFile so the bridge has the flag
      // when the recolour preprocess runs (phase 2.3 wires the
      // preprocess into openFile itself; until then setRecolour is a
      // no-op on the bridge side, and the first frame presented is the
      // stock ZX-Spectrum rendering either way). Default on.
      widget.core.setRecolour(entry.recolour);
      AppLog.log('recolour: ${entry.recolour}');
      AppLog.log('openFile: ${entry.path}');
      final rc = widget.core.openFile(entry.path);
      AppLog.log('openFile rc=$rc');

      // Restore the per-game snapshot (Spectrum snapshot is .sna).
      try {
        final loaded = await GameStateService.loadInto(widget.core, entry.path);
        AppLog.log('snapshot load: $loaded (${entry.displayName})');
        debugPrint('snapshot load: $loaded');
      } catch (e) {
        AppLog.log('snapshot load exception: $e');
      }

      GameStateService.startAutoSave(widget.core, entry.path);
      AppLog.log('snapshot auto-save started (60s interval)');
    }

    // The fps lookup is wrapped in try/catch because a missing
    // symbol on the bridge (an older build, a wrong ABI) used to take
    // down the entire frame loop with an unhandled Dart exception --
    // 'spinning not loading the tap', since the exception fires
    // after openFile() has already started the loader. Treat a
    // failure to read fps as 'we don't know yet' and move on.
    try {
      final fps = widget.core.fpsX100;
      AppLog.log('emulator running @ ${fps / 100.0}fps');
    } catch (e) {
      AppLog.log('fps lookup failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // No FPS overlay: the status bar already reports the core's rate, and
      // this widget's counter measures its own redraws -- a different number
      // under the same name, drawn over the corner of the picture.
      Positioned.fill(child: FramebufferView(core: widget.core)),

      // The stick sits OVER the picture, because it has to be under a thumb
      // and a Spectrum screen is 4:3 on a wide display -- there is room
      // either side of the picture and none below it.
      if (widget.showJoystick)
        Positioned.fill(
          child: KempstonPad(
            core: widget.core,
            editing: widget.editingLayout,
          ),
        ),

      // The keyboard takes the foot of the view rather than floating: it is
      // forty keys, it is being read, and a game that wants a keypress has
      // usually just said so in text you also need to see.
      if (widget.showKeyboard)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SpectrumKeyboard(core: widget.core),
        ),
    ]);
  }
}
