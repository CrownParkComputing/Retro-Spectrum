import 'package:flutter_test/flutter_test.dart';
import 'package:retro_spectrum/data/media_entry.dart';

void main() {
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
