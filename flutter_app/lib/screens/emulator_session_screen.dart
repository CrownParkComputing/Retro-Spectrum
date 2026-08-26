// emulator_session_screen.dart -- The emulator's own screen: the family
// pattern shared with Retro-Amiga, Retro-Saturn, Retro-C64 and
// Retro-Dosbox. Launching pushes this route fullscreen; everything a
// player needs mid-game lives here, and both ways out land back on the
// workbench in exactly one place.
//
// A corner handle opens the pause menu (machine paused, picture dimmed):
// Resume, Save and exit, Close. The right-hand rail carries the in-game
// tools that used to sit on the workbench status bar -- Spectrum keyboard,
// Kempston stick, layout editing -- as labelled buttons.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_spectrum/data/media_entry.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';
import 'package:retro_spectrum/screens/emulator_screen.dart';
import 'package:retro_spectrum/theme/spectrum_theme.dart';

/// How a session ended, from the workbench's point of view.
///
/// [paused] snapshotted the machine: the workbench offers it back with a
/// tap-to-resume banner. [closed] dropped the session with no resume path.
enum SessionExit { paused, closed }

class EmulatorSessionScreen extends StatefulWidget {
  final SpeccyCore core;
  final String? biosPath;
  final String? gamesFolder;
  final MediaEntry? entry;

  /// Where Save and exit writes its snapshot -- the workbench reads the
  /// same path back on resume.
  final String saveStatePath;

  const EmulatorSessionScreen({
    super.key,
    required this.core,
    this.biosPath,
    this.gamesFolder,
    this.entry,
    required this.saveStatePath,
  });

  @override
  State<EmulatorSessionScreen> createState() => _EmulatorSessionScreenState();
}

class _EmulatorSessionScreenState extends State<EmulatorSessionScreen> {
  /// The Spectrum's keyboard and its joystick are different machines' worth
  /// of input -- a text adventure wants the forty keys and a shoot-em-up
  /// wants a stick and fire -- so they are two toggles, not one "pad".
  bool _keyboardVisible = false;
  bool _joystickVisible = false;
  bool _editingLayout = false;

  /// The pause menu: machine stopped, picture dimmed, choices pinned up.
  bool _menuOpen = false;

  /// Whether the corner handle and rail are on screen. They hide a few
  /// seconds after the last touch: a 4:3 machine on a widescreen handheld
  /// has no width to lend to furniture that is only occasionally wanted.
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    // The session owns the whole screen: hide the system bars for the
    // duration and give them back on the way out. Sticky, because an edge
    // swipe on a handheld is easy to do by accident mid-game.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _restartControlsTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_menuOpen) setState(() => _controlsVisible = false);
    });
  }

  void _wakeControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _restartControlsTimer();
  }

  void _setMenu(bool open) {
    setState(() {
      _menuOpen = open;
      _controlsVisible = true;
    });
    // The menu freezes the machine for real -- audio included -- rather
    // than dimming a game that plays on underneath.
    widget.core.setPaused(open);
    if (!open) _restartControlsTimer();
  }

  /// Save and exit: snapshot and hand the workbench a session it can offer
  /// back. Stays on this screen if the snapshot fails -- popping anyway
  /// would silently lose the game.
  void _saveAndExit() {
    final result = widget.core.saveState(widget.saveStatePath);
    if (result != 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save your session (error $result).'),
      ));
      return;
    }
    Navigator.of(context).pop(SessionExit.paused);
  }

  /// Close: drop the session with no resume path.
  void _close() {
    Navigator.of(context).pop(SessionExit.closed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // The machine. EmulatorScreen still draws the framebuffer and
            // the overlays; the session chrome lives out here on top of it.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _wakeControls(),
                child: EmulatorScreen(
                  core: widget.core,
                  biosPath: widget.biosPath,
                  gamesFolder: widget.gamesFolder,
                  entry: widget.entry,
                  showKeyboard: _keyboardVisible,
                  showJoystick: _joystickVisible,
                  editingLayout: _editingLayout,
                ),
              ),
            ),
            if (_menuOpen) ...[
              // Dim the frozen picture. Tapping the picture resumes --
              // the cheapest way back into the game is the game itself.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setMenu(false),
                  child: Container(color: const Color(0xB3000000)),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ResumeButton(onTap: () => _setMenu(false)),
                    const SizedBox(height: 28),
                    _MenuChoice(
                      icon: Icons.save_outlined,
                      label: 'Save and exit',
                      detail:
                          'Snapshot this session and return to the workbench',
                      onTap: _saveAndExit,
                    ),
                    const SizedBox(height: 12),
                    _MenuChoice(
                      icon: Icons.close,
                      label: 'Close',
                      detail: 'End the session and return to the workbench',
                      onTap: _close,
                    ),
                  ],
                ),
              ),
            ],
            // The in-game tool rail, down the right edge where the thumb
            // already is. Hidden while the menu is up -- the menu IS the
            // controls then.
            if (!_menuOpen)
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Center(child: _toolRail()),
                  ),
                ),
              ),
            // The corner handle: the one control that is always reachable.
            // ☰ opens the pause menu; while the menu is up it reads ▶ and
            // resumes, so the same corner always undoes itself.
            Positioned(
              left: 4,
              top: 4,
              child: AnimatedOpacity(
                opacity: (_controlsVisible || _menuOpen) ? 1 : 0.25,
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: const Color(0x66000000),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      _wakeControls();
                      _setMenu(!_menuOpen);
                    },
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        _menuOpen ? Icons.play_arrow : Icons.menu,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolRail() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailTool(
          icon: Icons.keyboard,
          label: 'Keys',
          lit: _keyboardVisible,
          tooltip: _keyboardVisible
              ? 'Hide Spectrum keyboard'
              : 'Show Spectrum keyboard',
          onTap: () {
            _wakeControls();
            setState(() => _keyboardVisible = !_keyboardVisible);
          },
        ),
        _RailTool(
          icon: Icons.gamepad,
          label: 'Stick',
          lit: _joystickVisible,
          tooltip:
              _joystickVisible ? 'Hide joystick' : 'Show joystick (Kempston)',
          onTap: () {
            _wakeControls();
            setState(() {
              _joystickVisible = !_joystickVisible;
              // Moving controls that are not on screen is a mode with
              // nothing in it.
              if (!_joystickVisible) _editingLayout = false;
            });
          },
        ),
        // Only while the stick is up, for the same reason.
        if (_joystickVisible)
          _RailTool(
            icon: _editingLayout ? Icons.check : Icons.open_with,
            label: 'Layout',
            lit: _editingLayout,
            tooltip: _editingLayout
                ? 'Done moving controls'
                : 'Move the stick and fire button',
            onTap: () {
              _wakeControls();
              setState(() => _editingLayout = !_editingLayout);
            },
          ),
      ],
    );
  }
}

/// One labelled tool on the session rail: a 34px circle with its name under
/// it, matching the Amiga, Saturn, C64 and DOSBox rails.
class _RailTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool lit;
  final VoidCallback onTap;

  const _RailTool({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.lit = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color:
                  lit ? SpectrumColors.tabSelected : const Color(0x66000000),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: tooltip,
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      icon,
                      color: lit ? Colors.black : Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                shadows: [Shadow(blurRadius: 3, color: Colors.black)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big centred resume control on the pause menu.
class _ResumeButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ResumeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SpectrumColors.tabSelected,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Icon(Icons.play_arrow, color: Colors.black, size: 44),
        ),
      ),
    );
  }
}

/// A pause-menu row: icon, name, and a line saying what it will do.
class _MenuChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  const _MenuChoice({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE0181C20),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
