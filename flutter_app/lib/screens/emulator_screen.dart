// emulator_screen.dart -- the entire emulation layer for
// Retro-Spectrum is a WebView running Refract (a JS-based ZX
// Spectrum / ZX Spectrum Next emulator by Software Amusements,
// https://www.softwareamusements.com/Web/RefractEmulator/).
//
// Architecture:
//
//   - assets/refract.html is Refract's full HTML, including the
//     inlined Z80N CPU and NextReg engine (~1.7 MB).
//   - The WebView loads it from assets at startup and runs it
//     in-process.
//   - Dart injects a JavaScript shim that overrides Refract's
//     native file-drop handler, so the Dart UI can drop .tap / .tzx /
//     .z80 / .sna / .nex bytes via a JavaScript channel call.
//   - Every ~16 ms Dart polls the WebView's #screen canvas via
//     canvas.toDataURL() and decodes the PNG for Flutter to draw.
//   - Keyboard input from the on-screen controls is forwarded to
//     Refract as synthetic KeyboardEvent dispatches.
//
// No JNI, no JVM, no subprocess, no FFI: pure Dart + WebView.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/media_entry.dart';
import '../services/app_log.dart';
import '../services/saf_bridge.dart';

/// Asset path of the bundled Refract emulator page. `loadFlutterAsset`
/// throws on Android for files larger than ~1 MB, so we read the
/// bytes once and pass them through `loadHtmlString` instead.
const String _refractAssetPath = 'assets/refract.html';

Future<String> _loadRefractHtml() async {
  final data = await rootBundle.loadString(_refractAssetPath);
  return data;
}

/// Holds the live state for the WebView-backed emulator session.
class _EmulatorSessionState extends State<EmulatorSession> {
  late final WebViewController _controller;
  Timer? _frameTimer;

  /// Latest decoded RGBA frame, set by the polling loop. The
  /// emulator screen widget reads this every frame.
  ui.Image? _frameImage;

  bool _ready = false;
  bool _error = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'RefractBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          AppLog.log('refract: ${msg.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            _ready = true;
            await _controller.runJavaScript(_installHelper);
            _frameTimer = Timer.periodic(
              const Duration(milliseconds: 16),
              (_) => _captureFrame(),
            );
            final entry = widget.entry;
            if (entry != null && File(entry.path).existsSync()) {
              _loadFile(entry.path);
            }
          },
          onWebResourceError: (err) {
            _error = true;
            _errorMessage = err.description;
          },
        ),
      );
    // Load Refract's HTML directly via rootBundle.loadString and
    // hand it to the WebView via loadHtmlString. This avoids
    // loadFlutterAsset which throws on Android for files larger than
    // ~1 MB (Refract's bundled page is 1.7 MB). Kick off from a
    // separate async helper because initState itself can't await.
    _bootRefract();
  }

  Future<void> _bootRefract() async {
    final html = await _loadRefractHtml();
    await _controller.loadHtmlString(html);
  }

  @override
  void didUpdateWidget(covariant EmulatorSession old) {
    super.didUpdateWidget(old);
    if (old.entry?.path != widget.entry?.path && widget.entry != null) {
      _loadFile(widget.entry!.path);
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  /// Drops the file at [path] into the Refract page by synthesising
  /// a DragEvent with a File payload. Refract's drop handler reads
  /// it as if the user had dragged the file from the OS file picker.
  Future<void> _loadFile(String path) async {
    if (!_ready) return;
    try {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      // Escape the path for embedding in a JS string literal.
      final jsPath = _jsString(path);
      // Inject a File via DataTransfer and dispatch a drop event on
      // the #screen canvas -- exactly what Refract's own drop
      // handler listens for.
      final js =
          'window.__retroLoadFile($jsPath, "$b64");';
      await _controller.runJavaScript(js);
    } catch (e) {
      AppLog.log('refract loadFile failed: $e');
    }
  }

  Future<void> _captureFrame() async {
    if (!_ready) return;
    try {
      final dataUrl = await _controller.runJavaScriptReturningResult(
        'document.getElementById("screen") && '
        'document.getElementById("screen").toDataURL("image/png")',
      ) as String?;
      if (dataUrl == null || !dataUrl.startsWith('data:image/png;base64,')) {
        return;
      }
      final pngBytes = base64Decode(dataUrl.substring(22));
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _frameImage = frame.image);
    } catch (_) {
      // Refract not initialised yet, or canvas isn't ready; skip.
    }
  }

  /// Translate a Spectrum key index into a Refract keyboard event.
  /// Refract listens on document for keydown/keyup and routes via the
  /// MATRIX / KEMPSTON lookup table baked into its JS. We fire the
  /// matching browser KeyboardEvent from Dart.
  void _sendKey(int key, bool press) {
    if (!_ready) return;
    final code = _spectrumKeyCode(key);
    if (code == null) return;
    final type = press ? 'keydown' : 'keyup';
    _controller.runJavaScript(
      '(() => {'
      '  const ev = new KeyboardEvent("$type", {code: "$code", bubbles: true});'
      '  document.dispatchEvent(ev);'
      '})()',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Refract failed to load: $_errorMessage',
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    return Stack(children: [
      // The Refract WebView itself. Hidden behind the Flutter
      // framebuffer surface -- Dart draws the captured PNG instead.
      // We give it a real on-screen size so the JS engine keeps
      // running and producing fresh frames.
      Positioned.fill(
        child: IgnorePointer(
          child: WebViewWidget(controller: _controller),
        ),
      ),
      // The Flutter-rendered framebuffer surface. Drawn from
      // _frameImage which the polling loop fills every 16 ms.
      Positioned.fill(
        child: ColoredBox(
          color: Colors.black,
          child: _frameImage == null
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : RawImage(
                  image: _frameImage,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                ),
        ),
      ),
    ]);
  }
}

class EmulatorSession extends StatefulWidget {
  final MediaEntry? entry;

  /// Handler for keyboard input from the on-screen Spectrum
  /// keyboard. [key] is the 0..39 Spectrum matrix index; [press]
  /// is true for key-down, false for key-up.
  final void Function(int key, bool press)? onKey;

  const EmulatorSession({super.key, required this.entry, this.onKey});

  @override
  State<EmulatorSession> createState() => _EmulatorSessionState();
}

// ---- helpers ----

/// Convert a Spectrum matrix key index to the DOM KeyboardEvent.code
/// value Refract expects (matches its own MATRIX table). Indices
/// follow the standard 8x5 layout, top-to-bottom, left-to-right.
String? _spectrumKeyCode(int key) {
  const codes = [
    // row 0 (port 0xFE bit 0): SHIFT, Z, X, C, V
    'ShiftLeft', 'KeyZ', 'KeyX', 'KeyC', 'KeyV',
    // row 1 (port 0xFE bit 1): A, S, D, F, G
    'KeyA', 'KeyS', 'KeyD', 'KeyF', 'KeyG',
    // row 2 (port 0xFE bit 2): Q, W, E, R, T
    'KeyQ', 'KeyW', 'KeyE', 'KeyR', 'KeyT',
    // row 3 (port 0xFE bit 3): 1, 2, 3, 4, 5
    'Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5',
    // row 4 (port 0xFE bit 4): 0, 9, 8, 7, 6
    'Digit0', 'Digit9', 'Digit8', 'Digit7', 'Digit6',
    // row 5 (port 0xFD bit 0): P, O, I, U, Y
    'KeyP', 'KeyO', 'KeyI', 'KeyU', 'KeyY',
    // row 6 (port 0xFD bit 1): ENTER, L, K, J, H
    'Enter', 'KeyL', 'KeyK', 'KeyJ', 'KeyH',
    // row 7 (port 0xFD bit 2): SPACE, SYM, M, N, B
    'Space', 'ControlLeft', 'KeyM', 'KeyN', 'KeyB',
  ];
  if (key < 0 || key >= 40) return null;
  return codes[key];
}

/// Quote a Dart string for safe inclusion in a JS literal.
String _jsString(String s) {
  // Use JSON-style double-quoted escape.
  return '"' +
      s.replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"')
          .replaceAll('\n', r'\n')
          .replaceAll('\r', r'\r') +
      '"';
}

/// JavaScript that Refract needs installed once it loads. Hooks
/// the page's drop event so Dart can synthesise file drops via
/// `window.__retroLoadFile(path, base64)`.
const String _installHelper = r'''
window.__retroLoadFile = function(path, b64) {
  try {
    const bin = Uint8Array.from(atob(b64), function(c) {
      return c.charCodeAt(0);
    });
    const file = new File([bin], path);
    const dt = new DataTransfer();
    dt.items.add(file);
    const ev = new DragEvent('drop', {
      dataTransfer: dt, bubbles: true, cancelable: true
    });
    const target = document.getElementById('screen')
                 || document.body;
    target.dispatchEvent(ev);
  } catch (e) {
    console.error('retro load failed', e);
  }
};
window.__retroIsReady = function() { return true; };
''';
