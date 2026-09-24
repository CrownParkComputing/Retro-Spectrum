// media_entry.dart — One scanned Spectrum title on disk.
//
// The Spectrum has no single medium: a title arrives as a tape (.tap,
// .tzx), a snapshot (.z80, .sna), a disk (.trd, .scl), or any of those
// inside a .zip. The core sorts that out itself -- zxpoly_bridge_open_file
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
  sze,   // SNA Extended -- pre-adapted for ZX-Poly's 4-CPU mode
  zxp,   // ZX-Poly's own packed format
  nex,   // ZX Spectrum Next native executable
  trd,
  scl,
  zip;

  /// Short label for the corner badge (upper-cased extension).
  String get extensionLabel => switch (this) {
        MediaFormat.tap => 'TAP',
        MediaFormat.tzx => 'TZX',
        MediaFormat.z80 => 'Z80',
        MediaFormat.sna => 'SNA',
        MediaFormat.sze => 'SZE',
        MediaFormat.zxp => 'ZXP',
        MediaFormat.nex => 'NEX',
        MediaFormat.trd => 'TRD',
        MediaFormat.scl => 'SCL',
        MediaFormat.zip => 'ZIP',
        MediaFormat.unknown => '?',
      };

  /// What sort of medium this is, for the tile's second line. A tape has
  /// to be played and a snapshot does not, which is the difference a
  /// player actually cares about. SZE/ZXP are pre-adapted snapshots;
  /// they behave like snapshots from the loader's point of view.
  String get mediumLabel => switch (this) {
        MediaFormat.tap || MediaFormat.tzx => 'Tape',
        MediaFormat.z80 ||
        MediaFormat.sna ||
        MediaFormat.sze ||
        MediaFormat.zxp ||
        MediaFormat.nex => 'Snapshot',
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
      case 'sze':
        return MediaFormat.sze;
      case 'zxp':
        return MediaFormat.zxp;
      case 'nex':
        return MediaFormat.nex;
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

  /// Absolute path on the device -- what zxpoly_bridge_open_file wants.
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

  /// Auto-recolour. The whole point of the zxpoly swap: four parallel
  /// Z80s each own one of R, G, B, Y, so when the bridge redistributes
  /// the game's graphics data across the parallel CPUs at launch the
  /// Spectrum's 8-colour-per-cell attribute clash is gone.
  ///
  /// Default true. Per-game; the value is persisted in AppPrefs keyed
  /// by [path] and rehydrated when the scanner surfaces an entry, so
  /// the user's choice sticks across app restarts.
  ///
  /// Toggle it off and the same four CPUs render the original
  /// 8-colour-per-cell Spectrum look -- useful for comparing the
  /// rendering against what the game would look like on a real machine.
  final bool recolour;

  const MediaEntry({
    required this.displayName,
    required this.path,
    required this.format,
    required this.baseName,
    required this.bezelKey,
    this.recolour = true,
  });

  /// Upper-case extension for the small badge under the title.
  String get extensionLabel => format.extensionLabel;

  /// Returns a copy of this entry with [recolour] overridden. Used by
  /// the pause-menu toggle and by the library grid's quick-toggle.
  MediaEntry withRecolour(bool value) => MediaEntry(
        displayName: displayName,
        path: path,
        format: format,
        baseName: baseName,
        bezelKey: bezelKey,
        recolour: value,
      );

  /// Two entries are the same game if they share path + format (covers
  /// the case where the user has the same title under different parent
  /// folders -- the scanner dedupes against this).
  @override
  bool operator ==(Object other) =>
      other is MediaEntry && other.path == path && other.format == format;

  @override
  int get hashCode => Object.hash(path, format);
}
