// spectrum_buttons.dart — A small map of the Spectrum's ordinary
// key-map faces the user with, plus the Kempston joystick's five
// directions / fire. The bridge stores these as raw int32 values
// (the keyboard feeds xPlatform's key-matrix codes, the joystick
// is a 5-bit bitmask), so the Dart side effectively re-stamps them
// here. The Spectrum input model is much simpler than the Saturn's
// 12-button controller -- one keyboard letter per gamepad face
// would be the wrong mental model.

import '../ffi/speccy_bindings.dart';

/// String-keyed map of the keyboard faces a Spectrun game relies on.
/// The SpeccyBridge's key_event(int32_t key, int32_t flags) takes the
/// row/column pair that platform/io.h defines; for the on-screen
/// pad we just send the literal ASCII letter.
final Map<String, int> kSpectrumKeyDefaults = {
  'A': 0x41, 'B': 0x42, 'C': 0x43, 'D': 0x44, 'E': 0x45,
  'F': 0x46, 'G': 0x47, 'H': 0x48, 'I': 0x49, 'J': 0x4A,
  'K': 0x4B, 'L': 0x4C, 'M': 0x4D, 'N': 0x4E, 'O': 0x4F,
  'P': 0x50, 'Q': 0x51, 'R': 0x52, 'S': 0x53, 'T': 0x54,
  'U': 0x55, 'V': 0x56, 'W': 0x57, 'X': 0x58, 'Y': 0x59,
  'Z': 0x5A, ' ': 0x20, 'ENTER': 0x0D, 'CAPS': 0xC1,
};

/// Kempston joystick bitmask constants. The bridge expects the
/// single int32 argument to be OR'd together.
class KempstonBit {
  static const int up = 0x08;
  static const int down = 0x04;
  static const int left = 0x02;
  static const int right = 0x01;
  static const int fire = 0x10;
}
