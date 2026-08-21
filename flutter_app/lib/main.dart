// main.dart — Retro-Spectrum app entry. Loads the SpeccyCore,
// resolves the platform-appropriate profile dir / ROM buffer /
// save state path, then routes to SetupWizardScreen or
// WorkbenchScreen based on whether setup is complete. Mirrors
// Retro-Saturn's main.dart pattern (the proven ViceMultiplatform
// layout).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:retro_spectrum/ffi/speccy_bindings.dart';
import 'package:retro_spectrum/ffi/speccy_core.dart';
import 'package:retro_spectrum/ffi/speccy_native_paths.dart';
import 'package:retro_spectrum/screens/setup_wizard_screen.dart';
import 'package:retro_spectrum/screens/workbench_screen.dart';
import 'package:retro_spectrum/services/app_log.dart';
import 'package:retro_spectrum/services/app_prefs.dart';
import 'package:retro_spectrum/services/core_paths.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CorePaths.ensureDirs();
  await AppPrefs.load();
  await AppLog.init();
  AppLog.log('app start');
  runApp(const RetroSpectrumApp());
}

class RetroSpectrumApp extends StatefulWidget {
  const RetroSpectrumApp({super.key});

  @override
  State<RetroSpectrumApp> createState() => _RetroSpectrumAppState();
}

class _RetroSpectrumAppState extends State<RetroSpectrumApp>
    with WidgetsBindingObserver {
  SpeccyCore? _core;
  String? _loadError;
  bool? _setupCompleted;

  bool _corePausedBeforeBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCore();
    _checkSetup();
  }

  @override
  void dispose() {
    final core = _core;
    if (core != null) {
      core.stop();
      core.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final foreground = state == AppLifecycleState.resumed;
    final core = _core;
    if (!foreground) {
      _corePausedBeforeBackground = core?.isRunning ?? false;
      if (!_corePausedBeforeBackground) core?.setPaused(true);
    } else {
      if (!_corePausedBeforeBackground) core?.setPaused(false);
    }
  }

  Future<void> _loadCore() async {
    try {
      final libPath = SpeccyNativePaths.resolveLibrary();
      final bindings = SpeccyCoreBindings.load(libraryPath: libPath);
      final core = SpeccyCoreBindingsAdapter(bindings);
      core.init(
        CorePaths.profileDir,
        CorePaths.resourceDir,
      );
      core.start();
      if (!mounted) return;
      setState(() => _core = core);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  Future<void> _checkSetup() async {
    final completed = await AppPrefs.isSetupCompleted();
    if (!mounted) return;
    setState(() => _setupCompleted = completed);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retro-Spectrum',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: _loadError != null
          ? _ErrorScreen(message: _loadError!)
          : (_core == null || _setupCompleted == null)
              ? const _LoadingScreen()
              : (_setupCompleted == false
                  ? SetupWizardScreen(
                      onComplete: () => setState(() => _setupCompleted = true),
                    )
                  : WorkbenchScreen(
                      core: _core!,
                      onRerunSetup: () =>
                          setState(() => _setupCompleted = false),
                    )),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF050607),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load libspeccycore:\n$message',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
