// bezel_index.dart — Stub. The Spectrum's CRT-style bezel work
// falls in the same bucket as Retro-Saturn's. The full Retro-Saturn
// implementation is ported 1:1 once the deck artwork is collected;
// until then, the media card falls back to the title-only fallback.
// `BezelMatch`/`BezelIndex`/`BezelMatchKind` are imported from here
// so the rest of the app can compile in the meantime.

import 'package:flutter/foundation.dart';

@immutable
class BezelMatch {
  final String title;
  final String? coverPath;
  final BezelMatchKind kind;

  const BezelMatch({
    required this.title,
    this.coverPath,
    required this.kind,
  });
}

enum BezelMatchKind {
  exact,
  loose,
  none,
}

class BezelIndex {
  static const BezelMatch none = BezelMatch(
    title: '',
    kind: BezelMatchKind.none,
  );

  static BezelMatch find(String title) => none;
}
