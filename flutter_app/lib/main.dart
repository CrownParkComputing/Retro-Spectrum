// main.dart — Retro-Spectrum app entry. With the WebView/Refract
// rewrite there is no native engine to load at startup; the WebView
// boots Refract on demand when the user opens the emulator screen.
// We just resolve the platform-appropriate paths, load
// SharedPreferences, and route to the SetupWizardScreen or the
// WorkbenchScreen based on whether the user has picked a games
// folder.

import 'package:flutter/material.dart';
import 'package:retro_spectrum/screens/setup_wizard_screen.dart';
import 'package:retro_spectrum/screens/workbench_screen.dart';
import 'package:retro_spectrum/services/app_log.dart';
import 'package:retro_spectrum/services/app_prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class _RetroSpectrumAppState extends State<RetroSpectrumApp> {
  bool? _setupCompleted;

  @override
  void initState() {
    super.initState();
    _checkSetup();
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
      home: _setupCompleted == null
          ? const _LoadingScreen()
          : (_setupCompleted == false
              ? SetupWizardScreen(
                  onComplete: () => setState(() => _setupCompleted = true),
                )
              : WorkbenchScreen(
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
