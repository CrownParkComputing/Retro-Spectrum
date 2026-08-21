// media_entry.dart — One scanned Spectrum title on disk.
//
// The Spectrum has no single medium: a title arrives as a tape (.tap,
// .tzx), a snapshot (.z80, .sna), a disk (.trd, .scl), or any of those
// inside a .zip. The core sorts that out itself -- speccy_core_open_file
// dispatches on content, and file_type.cpp is where the list really
// lives -- so this enum exists to label and filter, not to decide.

/// The file kinds the Speccy core can open. `unknown` is what any
/// extension we don't recognise yields; the scanner filters those out,
/// but the value still exists so a stray entry can be displayed (with a
/// "?" badge) rather than crashing the grid.
enum MediaFormat {
  unknown,
  tap,
  tzx,
  z80,
  sna,
  trd,
  scl,
  zip;

  /// Short label for the corner badge (upper-cased extension).
  String get extensionLabel => switch (this) {
        MediaFormat.tap => 'TAP',
        MediaFormat.tzx => 'TZX',
        MediaFormat.z80 => 'Z80',
        MediaFormat.sna => 'SNA',
        MediaFormat.trd => 'TRD',
        MediaFormat.scl => 'SCL',
        MediaFormat.zip => 'ZIP',
        MediaFormat.unknown => '?',
      };

  /// What sort of medium this is, for the tile's second line. A tape has
  /// to be played and a snapshot does not, which is the difference a
  /// player actually cares about.
  String get mediumLabel => switch (this) {
        MediaFormat.tap || MediaFormat.tzx => 'Tape',
        MediaFormat.z80 || MediaFormat.sna => 'Snapshot',
        MediaFormat.trd || MediaFormat.scl => 'Disk',
        MediaFormat.zip => 'Archive',
        MediaFormat.unknown => 'Unsupported',
      };

  /// True for the formats the core can actually open.
  bool get isSupported => this != MediaFormat.unknown;

  /// Map a filename extension to a [MediaFormat]. Case-insensitive and
  /// ignores a leading dot, so `.tap` and `TAP` both resolve.
  static MediaFormat fromExtension(String ext) {
    switch (ext.toLowerCase().replaceFirst('.', '')) {
      case 'tap':
        return MediaFormat.tap;
      case 'tzx':
        return MediaFormat.tzx;
      case 'z80':
        return MediaFormat.z80;
      case 'sna':
        return MediaFormat.sna;
      case 'trd':
        return MediaFormat.trd;
      case 'scl':
        return MediaFormat.scl;
      case 'zip':
        return MediaFormat.zip;
      default:
        return MediaFormat.unknown;
    }
  }
}

/// One game as discovered on disk. Immutable: the library grid and the
/// bezel index both key off [path] + [bezelKey], neither of which changes
/// once the entry has been scanned.
class MediaEntry {
  /// The filename as the user sees it (e.g. `"Manic Miner.tap"`).
  final String displayName;

  /// Absolute path on the device -- what speccy_core_open_file wants.
  final String path;

  /// Format derived from the filename extension.
  final MediaFormat format;

  /// Display title with the extension stripped ("Panzer Dragoon (USA)").
  /// Kept on the entry so grid cells that want to show a cleaned-up name
  /// don't have to re-derive it (and so we agree on what "cleaned up"
  /// means).
  final String baseName;

  /// Normalized bezel key -- the form the bezel index uses for both
  /// exact and loose lookups. Empty when the display name has no usable
  /// characters; the bezel index falls back to a hash in that case.
  final String bezelKey;

  const MediaEntry({
    required this.displayName,
    required this.path,
    required this.format,
    required this.baseName,
    required this.bezelKey,
  });

  /// Upper-case extension for the small badge under the title.
  String get extensionLabel => format.extensionLabel;

  /// Two entries are the same game if they share path + format (covers
  /// the case where the user has the same title under different parent
  /// folders -- the scanner dedupes against this).
  @override
  bool operator ==(Object other) =>
      other is MediaEntry && other.path == path && other.format == format;

  @override
  int get hashCode => Object.hash(path, format);
}
