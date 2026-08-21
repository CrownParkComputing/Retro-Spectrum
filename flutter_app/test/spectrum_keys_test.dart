import 'package:flutter_test/flutter_test.dart';
import 'package:retro_spectrum/data/spectrum_keys.dart';

void main() {
  group('Spectrum key codes', () {
    test('the three non-ASCII keys use the engine codes, not ASCII', () {
      // ENTER is 'e', CAPS SHIFT is 'c', SYMBOL SHIFT is 's' -- see
      // TranslateKey in SimpleSpeccy's sdl2_keys.cpp. A previous table had
      // ENTER as 0x0D (carriage return) and CAPS as 0xC1, which are codes
      // the engine ignores, so those keys did nothing at all.
      expect(SpeccyKey.enter, 0x65);
      expect(SpeccyKey.capsShift, 0x63);
      expect(SpeccyKey.symbolShift, 0x73);
      expect(SpeccyKey.enter, isNot(0x0D));
    });

    test('letters are uppercase ASCII', () {
      final letters = <String, int>{};
      for (final row in kSpectrumLayout) {
        for (final cap in row) {
          if (cap.label.length == 1 && RegExp(r'[A-Z]').hasMatch(cap.label)) {
            letters[cap.label] = cap.code;
          }
        }
      }
      expect(letters.length, 26, reason: 'all 26 letters present');
      letters.forEach((label, code) {
        expect(code, label.codeUnitAt(0));
      });
    });

    test('digits are ASCII, and 0 comes last as on the machine', () {
      final row = kSpectrumLayout.first;
      expect(row.map((c) => c.label).join(), '1234567890');
      for (final cap in row) {
        expect(cap.code, cap.label.codeUnitAt(0));
      }
    });

    test('the layout is 40 keys in four rows of ten', () {
      expect(kSpectrumLayout.length, 4);
      for (final row in kSpectrumLayout) {
        expect(row.length, 10);
      }
      final total = kSpectrumLayout.fold<int>(0, (n, r) => n + r.length);
      expect(total, 40);
    });

    test('every key code is distinct', () {
      final codes = [
        for (final row in kSpectrumLayout)
          for (final cap in row) cap.code,
      ];
      expect(codes.toSet().length, codes.length,
          reason: 'a duplicate code means two keys press the same thing');
    });

    test('KF_DOWN is what marks a press', () {
      expect(SpeccyKeyFlags.down, 0x01);
      expect(SpeccyKeyFlags.shift, 0x02);
      expect(SpeccyKeyFlags.alt, 0x08);
    });
  });
}
