// workbench_screen.dart — Main hub. Sidebar nav + content panel.
// Aligned with ViceMultiplatform's WorkbenchScreen so the two
// multiplatform shells (C64-Retro + ymir-android) read as sibling
// apps. Shared with Retro-C64, Retro-Amiga (uae4arm2026p) and
// Retro-Dosbox at the widgets/sidebar.dart level: the Sidebar is
// bytes-identical, the WorkbenchCategory enum is the per-app
// declaration of which destinations the rail exposes, and the
// status bar across the bottom is the same row of rail-toggle +
// session title + (when running) in-game toolbar.
//
// The runtime info that used to live in the sidebar footer (Core
// status, FPS, audio level) now lives in [_statusBar]'s middle slot
// while a session is running -- the rail stays a launcher, the
// bottom strip becomes the in-game status strip.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:retro_spectrum/data/category.dart';
import 'package:retro_spectrum/data/media_entry.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';
import 'package:retro_spectrum/screens/about_screen.dart';
import 'package:retro_spectrum/screens/audio_settings_screen.dart';
import 'package:retro_spectrum/screens/emulator_session_screen.dart';
import 'package:retro_spectrum/screens/history_screen.dart';
import 'package:retro_spectrum/screens/input_settings_screen.dart';
import 'package:retro_spectrum/screens/library_grid.dart';
import 'package:retro_spectrum/screens/paths_settings_screen.dart';
import 'package:retro_spectrum/services/app_prefs.dart';
import 'package:retro_spectrum/services/core_paths.dart';
import 'package:retro_spectrum/theme/spectrum_theme.dart';
import 'package:retro_spectrum/widgets/sidebar.dart';
import 'package:retro_spectrum/widgets/sidebar_style.dart';

class WorkbenchScreen extends StatefulWidget {
  final SpeccyCore core;
  final VoidCallback? onRerunSetup;

  const WorkbenchScreen({super.key, required this.core, this.onRerunSetup});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  WorkbenchCategory _category = WorkbenchCategory.games;
  String _biosPath = '';
  String _gamesFolder = '';

  /// The game the user tapped to launch. Held so the in-panel EmulatorScreen
  /// can call `loadDisc(entry.path)` -- the disc never loads if this is null
  /// (EmulatorScreen falls back to BIOS-only, which boots to the Saturn's
  /// CD Player "No Disc" screen). Set in the LibraryGrid `onLaunch` callback,
  /// cleared in `_onSessionExit`. Independent of [_pausedSession] so the X
  /// (kill) and Pause (snapshot) buttons leave the Dart side in
  /// distinguishable states.
  MediaEntry? _currentEntry;

  /// Whether the side rail is collapsed. The launcher button + the running
  /// tab live in the rail; collapsing it gives the emulator screen as much
  /// room as the device allows, which is the whole point of the
  /// collapsible-sidebar pattern Retro-C64 and Retro-Dosbox use. The
  /// hamburger in [_statusBar] toggles it back; the status bar itself
  /// never collapses, because the only way back from a fully-hidden
  /// rail would otherwise be the X button on the emulator toolbar.
  bool _sidebarHidden = false;

  /// The title that has been paused via the toolbar Pause button. Distinct
  /// from [_currentEntry] so the X (kill) and Pause (snapshot) buttons
  /// leave the Dart side in distinguishable states. A non-null value here
  /// shows the resume banner above the workbench content and blocks fresh
  /// launches until the user either resumes or discards.
  MediaEntry? _pausedSession;

  /// Snapshot file written by [SpeccyCore.saveState] on Pause. Resolved
  /// from [CorePaths.saveStatePath] so the path is the same on
  /// Android, iOS and Linux. The SMPC state file lives in the same
  /// per-platform app-data dir; this is its sibling.
  String get _saveStatePath => CorePaths.saveStatePath;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    final b = await AppPrefs.getBiosPath() ?? '';
    final g = await AppPrefs.getGamesFolder() ?? '';
    if (!mounted) return;
    setState(() {
      _biosPath = b;
      _gamesFolder = g;
    });
  }

  /// Hands the session its own screen -- the family pattern shared with
  /// the Amiga, Saturn, C64 and DOSBox front ends. Every way into a game
  /// funnels through here, so pausing and closing land back on the
  /// workbench in exactly one place.
  Future<void> _openSession(MediaEntry? entry) async {
    if (!mounted) return;
    setState(() {
      _currentEntry = entry;
      _pausedSession = null;
    });
    final SessionExit? how = await Navigator.of(context).push<SessionExit>(
      MaterialPageRoute<SessionExit>(
        fullscreenDialog: true,
        builder: (BuildContext context) => EmulatorSessionScreen(
          core: widget.core,
          biosPath: _biosPath,
          gamesFolder: _gamesFolder,
          entry: entry,
          saveStatePath: _saveStatePath,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _pausedSession = how == SessionExit.paused ? _currentEntry : null;
      if (how != SessionExit.paused) _currentEntry = null;
    });
  }

  /// Tap on the "Paused: <title>" banner. Restores the snapshot the
  /// session screen's Save and exit wrote, then re-enters the session.
  Future<void> _onResumePaused() async {
    final paused = _pausedSession;
    if (paused == null) return;
    final result = widget.core.loadState(_saveStatePath);
    if (!mounted) return;
    if (result != 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not restore your session (error $result).'),
      ));
      return;
    }
    await _openSession(paused);
  }

  /// Drop the paused snapshot without resuming. The file stays on disk
  /// (next launch overwrites it) but the workbench no longer offers
  /// resume. Equivalent in spirit to Retro-C64's "Discard" button.
  void _discardPaused() {
    setState(() => _pausedSession = null);
  }

  Widget _contentForCategory() {
    switch (_category) {
      case WorkbenchCategory.resume:
        // Resume is hidden from the rail when no session is paused, so
        // landing here means a paused session exists; the banner offers
        // it back, or the user can discard and start over.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pausedSession != null) _resumableBanner(),
            const Expanded(
              child: Center(
                child: Text('Resume not available -- pick a game to start over.',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        );
      case WorkbenchCategory.games:
        if (_gamesFolder.isEmpty) {
          return const Center(
              child: Text('Pick a games folder in 📂 Paths',
                  style: TextStyle(color: Colors.white54)));
        }
        return LibraryGrid(
          folderPath: _gamesFolder,
          onLaunch: (entry) => unawaited(_openSession(entry)),
        );
      case WorkbenchCategory.paths:
        return const PathsSettingsScreen();
      case WorkbenchCategory.audio:
        return AudioSettingsScreen(core: widget.core);
      case WorkbenchCategory.input:
        return InputSettingsScreen(core: widget.core);
      case WorkbenchCategory.history:
        return const HistoryScreen();
      case WorkbenchCategory.about:
        return const AboutScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpectrumColors.rootBackground,
      body: Container(
        color: SpectrumColors.rootBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_sidebarHidden) ...[
                        Sidebar(
                          destinations: [
                            for (final c in WorkbenchCategory.values)
                              SidebarDestination(
                                c.title,
                                icon: c.icon,
                                group: c.group,
                              ),
                          ],
                          selectedIndex: _category.index,
                          onSelected: (i) => setState(
                              () => _category = WorkbenchCategory.values[i]),
                          style: spectrumSidebarStyle,
                          pinLastGroupToBottom: true,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: _contentPanel()),
                    ],
                  ),
                ),
                _statusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The bottom strip, outside both the sidebar and the content panel: the
  /// hamburger toggle on the left, the paused-session title (when one
  /// exists) in the middle, and the in-game toolbar on the right -- matching
  /// Retro-C64's EmulatorControlStrip pattern. It always renders, even with
  /// the rail hidden, because the hamburger is the only way back once the
  /// rail is gone.
  ///
  /// The in-game toolbar buttons (pad toggle, settings, pause, close) only
  /// show while a session is running. Paused / no-session hides them so the
  /// bar is just the launcher chrome.
  ///
  /// The session title is a tap target for the paused-session case: tapping
  /// it loads the snapshot and brings the emulator back.
  Widget _statusBar() {
    final paused = _pausedSession;
    return Row(
      children: [
        IconButton(
          onPressed: () =>
              setState(() => _sidebarHidden = !_sidebarHidden),
          icon: Icon(
            _sidebarHidden ? Icons.menu : Icons.menu_open,
            size: 20,
          ),
          color: SpectrumColors.sidebarLabelIdle,
          tooltip: _sidebarHidden ? 'Show sidebar' : 'Hide sidebar',
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: paused != null
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onResumePaused,
                  child: Row(children: [
                    const Icon(Icons.history,
                        size: 14, color: SpectrumColors.sidebarLabelIdle),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Paused -- ${paused.displayName} (tap to resume)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: SpectrumColors.sidebarLabelIdle),
                      ),
                    ),
                  ]),
                )
              : _currentEntry != null
                      ? Text(
                          _currentEntry!.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: SpectrumColors.sidebarLabelIdle),
                        )
                      : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// The right-hand pane: the resumable-session card when paused, plus the
  /// current category content. Sessions run on their own screen
  /// (EmulatorSessionScreen) -- the workbench is only ever the launcher.
  Widget _contentPanel() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SpectrumColors.panelFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SpectrumColors.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pausedSession != null) _resumableBanner(),
          Expanded(child: _contentForCategory()),
        ],
      ),
    );
  }

  /// "Paused: <title>" banner above the workbench. Same role as
  /// Retro-Dosbox's _resumableBanner and Retro-C64's Running-tab card:
  /// surfaces the resumable session even when the user has navigated
  /// somewhere other than Running. Saturn's accent is the same blue the
  /// sidebar selection uses (SpectrumColors.tabSelected), so a paused state
  /// reads as "still the app you were in", not as a foreign warning.
  Widget _resumableBanner() {
    final entry = _pausedSession!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: SpectrumColors.tabSelected.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: SpectrumColors.tabSelected),
      ),
      child: Row(children: [
        const Icon(Icons.history, size: 16, color: SpectrumColors.tabSelected),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onResumePaused,
            child: Text(
              'Paused: ${entry.displayName} -- tap to resume',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: SpectrumColors.tabSelected, fontSize: 12),
            ),
          ),
        ),
        IconButton(
          onPressed: _discardPaused,
          icon: const Icon(Icons.close, size: 16),
          color: SpectrumColors.tabSelected,
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  /// The Core status block that used to be baked into the rail's own class.
  /// It lives in the canonical Sidebar's footer slot now -- which is exactly
}

/// Sidebar nav matching the C64-Retro layout. Width computed from
/// widest title; clamped to SpectrumMetrics.sidebarMinWidth/Max.
