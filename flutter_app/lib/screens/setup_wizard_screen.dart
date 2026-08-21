// setup_wizard_screen.dart — First run: point the app at your games.
//
// There is exactly one thing this app needs from the user, and it is a
// folder. The ROMs are built in (see RomLoader), so unlike the Saturn front
// end this was adapted from there is no BIOS to hunt down and no second
// step -- that wizard asked for a 512 KiB BIOS blob and a games folder, and
// refused to finish without the first.
//
// It guesses first and asks second: the common locations get probed, and if
// one of them has games in it the user can accept and move on without a file
// picker. When the guess misses -- which it will on any device that keeps
// its ROMs somewhere personal -- the screen says plainly what it looked for
// and what it wants, because "no games found" on its own is a dead end.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:retro_spectrum/services/app_prefs.dart';
import 'package:retro_spectrum/services/library_scanner.dart';
import 'package:retro_spectrum/services/setup_scan_service.dart';

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  bool _busy = false;
  bool _scanned = false;
  ScanResult? _result;
  String _folder = '';

  @override
  void initState() {
    super.initState();
    _guess();
  }

  Future<void> _guess() async {
    final initial =
        await AppPrefs.getGamesFolder() ?? SetupScanService.autoDetectFolder();
    if (initial == null) {
      if (!mounted) return;
      setState(() => _scanned = true);
      return;
    }
    await _scan(initial);
  }

  Future<void> _scan(String path) async {
    setState(() {
      _busy = true;
      _folder = path;
    });
    final result = await SetupScanService.scan(path);
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
      _scanned = true;
    });
  }

  Future<void> _pick() async {
    final chosen = await FilePicker.platform.getDirectoryPath();
    if (chosen != null) await _scan(chosen);
  }

  Future<void> _finish() async {
    if (_folder.isNotEmpty) await AppPrefs.setGamesFolder(_folder);
    await AppPrefs.setSetupCompleted(true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final found = result?.games.length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: !_scanned
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Where are your games?',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      'Pick the folder holding your Spectrum files. '
                      'Subfolders are searched too, so the top of your '
                      'collection is enough.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 16),
                    if (_busy) const LinearProgressIndicator(),
                    if (!_busy) _folderCard(found),
                    const SizedBox(height: 12),
                    _Supported(),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _pick,
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: Text(found > 0
                                ? 'Choose a different folder'
                                : 'Choose games folder'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            // Finishing with nothing found is allowed: the
                            // folder can be set later from Paths, and
                            // trapping someone on this screen because their
                            // collection is not plugged in yet helps nobody.
                            onPressed: _busy ? null : _finish,
                            child: Text(found > 0 ? 'Start' : 'Skip for now'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _folderCard(int found) {
    final none = _folder.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: found > 0 ? const Color(0xFF2E7D48) : const Color(0xFF2A2A34),
        ),
      ),
      child: Row(
        children: [
          Icon(
            found > 0 ? Icons.check_circle : Icons.folder_off,
            size: 20,
            color: found > 0 ? const Color(0xFF61C888) : Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  none
                      ? 'No folder chosen yet'
                      : found > 0
                          ? '$found ${found == 1 ? 'title' : 'titles'} found'
                          : 'Nothing playable in this folder',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (!none) ...[
                  const SizedBox(height: 2),
                  Text(_folder,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white54),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What counts as a game, said out loud.
///
/// Read from MediaFormat rather than typed here, so this cannot promise a
/// format the scanner then ignores -- which is exactly what the Saturn
/// version of this screen did, listing CHD and ISO to Spectrum owners.
class _Supported extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final ext in kSupportedExtensions)
          Chip(
            label: Text('.$ext',
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
            backgroundColor: const Color(0xFF1A1A22),
            side: const BorderSide(color: Color(0xFF2A2A34)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        Chip(
          label: Text(
            'ROMs are built in',
            style: TextStyle(
                fontSize: 11, color: Colors.white.withValues(alpha: 0.45)),
          ),
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}
