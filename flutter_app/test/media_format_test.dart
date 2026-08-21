import 'package:flutter_test/flutter_test.dart';
import 'package:retro_spectrum/data/media_entry.dart';
import 'package:retro_spectrum/services/library_scanner.dart';

void main() {
  _pinned();
  group('MediaFormat', () {
    test('recognises the formats the core can open', () {
      // These were chd/cue/mds/ccd/iso -- Saturn disc images, inherited from
      // the front end this app was copied from. A Spectrum library scanned
      // as completely empty because not one file matched.
      for (final ext in ['tap', 'tzx', 'z80', 'sna', 'trd', 'scl', 'zip']) {
        expect(MediaFormat.fromExtension(ext).isSupported, isTrue,
            reason: '.$ext should be launchable');
      }
    });

    test('does not recognise Saturn disc images', () {
      for (final ext in ['cue', 'chd', 'iso']) {
        expect(MediaFormat.fromExtension(ext), MediaFormat.unknown);
      }
    });

    test('matching ignores case and a leading dot', () {
      expect(MediaFormat.fromExtension('.TAP'), MediaFormat.tap);
      expect(MediaFormat.fromExtension('Tzx'), MediaFormat.tzx);
    });

    test('labels the medium, because a tape plays and a snapshot does not', () {
      expect(MediaFormat.tap.mediumLabel, 'Tape');
      expect(MediaFormat.z80.mediumLabel, 'Snapshot');
      expect(MediaFormat.trd.mediumLabel, 'Disk');
      expect(MediaFormat.zip.mediumLabel, 'Archive');
    });

    test('an unknown extension is not supported but still displayable', () {
      final f = MediaFormat.fromExtension('txt');
      expect(f, MediaFormat.unknown);
      expect(f.isSupported, isFalse);
      expect(f.extensionLabel, '?');
    });
  });
}

// The scanner used to keep its own hardcoded set of extensions beside
// MediaFormat. They drifted, and a Spectrum library scanned as completely
// empty while MediaFormat already knew about .tap and .tzx -- the scanner
// rejected every file before the enum was ever consulted. This pins the two
// together so that cannot happen again.

void _pinned() {
  group('scanner filter', () {
    test('accepts exactly what MediaFormat says is supported', () {
      final fromEnum = {
        for (final f in MediaFormat.values)
          if (f.isSupported) f.name,
      };
      expect(kSupportedExtensions, fromEnum);
    });

    test('a real Spectrum filename is accepted', () {
      // The shape they actually arrive in, from the device's own library.
      const name = '3 Weeks In Paradise (1985)(Mikro-Gen)(128k).tzx';
      final ext = name.split('.').last;
      expect(kSupportedExtensions.contains(ext), isTrue);
      expect(MediaFormat.fromExtension(ext), MediaFormat.tzx);
    });
  });
}
