// rom_loader.dart — Hands the Spectrum ROMs to the core at startup.
//
// The Android build is compiled -DUSE_EXTERN_RESOURCES, which means the core
// never reads its ROMs off disk: they arrive as buffers through
// speccy_core_set_rom / speccy_core_set_font, exactly as the reference
// Android app's Emulator.InitRom does. Without this the engine starts with
// 16 KiB of zeroes where its ROM should be and never reaches a BASIC prompt
// -- which looks like a dead emulator rather than a missing asset.
//
// The five ROMs and the 4x8 font ship in assets/roms/ (see pubspec.yaml).
// They are freely distributable and come from the engine's own res/ tree, so
// there is nothing for the user to find or configure -- which is why this
// app has no BIOS picker, unlike its Saturn sibling.
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../ffi/speccy_bindings.dart';
import '../ffi/speccy_core.dart';

class RomLoader {
  RomLoader._();

  /// asset name -> which ROM slot it fills. The ids are the core's own and
  /// must not be renumbered; see SPECCY_ROM_* in speccy_bridge.h.
  static const Map<SpeccyRom, String> _roms = <SpeccyRom, String>{
    SpeccyRom.sos128_0: 'assets/roms/sos128_0.rom',
    SpeccyRom.sos128_1: 'assets/roms/sos128_1.rom',
    SpeccyRom.sos48: 'assets/roms/sos48.rom',
    SpeccyRom.service: 'assets/roms/service.rom',
    SpeccyRom.dos: 'assets/roms/dos513f.rom',
  };

  static const String _font = 'assets/roms/spxtrm4f.fnt';

  /// Feeds every ROM and the font into [core].
  ///
  /// Must run after init() and before start(), which is the window the
  /// bridge documents: the core copies each buffer as it arrives, and reads
  /// them when it boots.
  static Future<void> loadInto(SpeccyCore core) async {
    for (final entry in _roms.entries) {
      await _push(entry.value, (bytes, size) => core.setRom(entry.key, bytes, size));
    }
    await _push(_font, core.setFont);
  }

  /// Copies one asset into native memory for the duration of the call.
  ///
  /// The core copies what it is given, so the buffer is freed immediately --
  /// holding it would be 82 KiB kept alive for nothing.
  static Future<void> _push(
    String asset,
    void Function(ffi.Pointer<ffi.Uint8>, int) apply,
  ) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();
    final buffer = calloc<ffi.Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      apply(buffer, bytes.length);
    } finally {
      calloc.free(buffer);
    }
  }
}
