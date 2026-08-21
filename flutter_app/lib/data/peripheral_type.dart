// peripheral_type.dart — Display-friendly metadata for the two
// input surfaces the Speccy bridge exposes: keyboard and Kempston
// joystick. The bridge stores both as raw int32 values (no enum),
// so this file is purely a UI helper -- not a 1:1 with the FFI.
//
// The Spectrum has two input surfaces, so the catalogue is small.
// Anywhere the UI needs to render an input label, go through
// [displayNameForPeripheral] / [descriptionForPeripheral] instead
// of typing the literal "Keyboard" / "Kempston" out by hand.

import '../ffi/speccy_bindings.dart';

/// The two input surfaces the Speccy host exposes.
enum SpeccyPeripheralType {
  keyboard(0),
  kempston(1);

  const SpeccyPeripheralType(this.value);
  final int value;
}

class PeripheralInfo {
  final SpeccyPeripheralType type;
  final String displayName;
  final String description;

  const PeripheralInfo(this.type, this.displayName, this.description);
}

const List<PeripheralInfo> kPeripheralCatalogue = [
  PeripheralInfo(SpeccyPeripheralType.keyboard, 'Keyboard',
      'Maps physical / on-screen keys to the Spectrum keyboard matrix.'),
  PeripheralInfo(SpeccyPeripheralType.kempston, 'Kempston Joystick',
      'Five-button Kempston joystick (up, down, left, right, fire).'),
];

String displayNameForPeripheral(SpeccyPeripheralType type) {
  for (final p in kPeripheralCatalogue) {
    if (p.type == type) return p.displayName;
  }
  return type.name;
}

String descriptionForPeripheral(SpeccyPeripheralType type) {
  for (final p in kPeripheralCatalogue) {
    if (p.type == type) return p.description;
  }
  return '';
}

extension SpeccyPeripheralTypeDisplay on SpeccyPeripheralType {
  String get displayName => displayNameForPeripheral(this);
  String get description => descriptionForPeripheral(this);
}
