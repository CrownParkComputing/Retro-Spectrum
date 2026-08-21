// spectrum_keys.dart — The Spectrum's 40 keys, and the Kempston joystick.
//
// The codes here are the engine's, not ASCII-with-good-intentions. Letters
// and digits do arrive as plain uppercase ASCII, but the three keys that
// have no ASCII equivalent are single lowercase letters chosen by the
// engine: 'e' is ENTER, 'c' is CAPS SHIFT, 's' is SYMBOL SHIFT. See
// TranslateKey in SimpleSpeccy's platform/sdl2/sdl2_keys.cpp, which is the
// reference every front end has to agree with.
//
// This replaces a table that had ENTER as 0x0D and CAPS as 0xC1 -- carried
// over from a Saturn controller map, and codes the engine simply ignores.

/// Flags for speccy_core_key_event, from xPlatform::eKeyFlags.
class SpeccyKeyFlags {
  static const int down = 0x01;
  static const int shift = 0x02; // CAPS SHIFT, as a modifier
  static const int ctrl = 0x04;
  static const int alt = 0x08; // SYMBOL SHIFT, as a modifier
}

/// The engine's codes for the keys that are not their own ASCII.
class SpeccyKey {
  static const int enter = 0x65; // 'e'
  static const int capsShift = 0x63; // 'c'
  static const int symbolShift = 0x73; // 's'
  static const int space = 0x20;
}

/// One key as drawn on the rubber mat: what to send, and what to show.
class SpectrumKeyCap {
  const SpectrumKeyCap(this.code, this.label, {this.wide = false});

  /// What goes to speccy_core_key_event.
  final int code;

  /// What the player sees on the key.
  final String label;

  /// CAPS / SYMBOL SHIFT and ENTER read better with room to breathe.
  final bool wide;
}

/// The 40-key layout, four rows of ten, exactly as the machine has it.
const List<List<SpectrumKeyCap>> kSpectrumLayout = [
  [
    SpectrumKeyCap(0x31, '1'), SpectrumKeyCap(0x32, '2'),
    SpectrumKeyCap(0x33, '3'), SpectrumKeyCap(0x34, '4'),
    SpectrumKeyCap(0x35, '5'), SpectrumKeyCap(0x36, '6'),
    SpectrumKeyCap(0x37, '7'), SpectrumKeyCap(0x38, '8'),
    SpectrumKeyCap(0x39, '9'), SpectrumKeyCap(0x30, '0'),
  ],
  [
    SpectrumKeyCap(0x51, 'Q'), SpectrumKeyCap(0x57, 'W'),
    SpectrumKeyCap(0x45, 'E'), SpectrumKeyCap(0x52, 'R'),
    SpectrumKeyCap(0x54, 'T'), SpectrumKeyCap(0x59, 'Y'),
    SpectrumKeyCap(0x55, 'U'), SpectrumKeyCap(0x49, 'I'),
    SpectrumKeyCap(0x4F, 'O'), SpectrumKeyCap(0x50, 'P'),
  ],
  [
    SpectrumKeyCap(0x41, 'A'), SpectrumKeyCap(0x53, 'S'),
    SpectrumKeyCap(0x44, 'D'), SpectrumKeyCap(0x46, 'F'),
    SpectrumKeyCap(0x47, 'G'), SpectrumKeyCap(0x48, 'H'),
    SpectrumKeyCap(0x4A, 'J'), SpectrumKeyCap(0x4B, 'K'),
    SpectrumKeyCap(0x4C, 'L'),
    SpectrumKeyCap(SpeccyKey.enter, 'ENTER', wide: true),
  ],
  [
    SpectrumKeyCap(SpeccyKey.capsShift, 'CAPS', wide: true),
    SpectrumKeyCap(0x5A, 'Z'), SpectrumKeyCap(0x58, 'X'),
    SpectrumKeyCap(0x43, 'C'), SpectrumKeyCap(0x56, 'V'),
    SpectrumKeyCap(0x42, 'B'), SpectrumKeyCap(0x4E, 'N'),
    SpectrumKeyCap(0x4D, 'M'),
    SpectrumKeyCap(SpeccyKey.symbolShift, 'SYM', wide: true),
    SpectrumKeyCap(SpeccyKey.space, 'SPACE', wide: true),
  ],
];

/// Kempston joystick bitmask constants. The bridge expects the single
/// int32 argument to be OR'd together.
class KempstonBit {
  static const int up = 0x08;
  static const int down = 0x04;
  static const int left = 0x02;
  static const int right = 0x01;
  static const int fire = 0x10;
}
