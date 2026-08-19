#!/usr/bin/env bash
# Build the headless Spectrum core and run every scenario against it.
#
# This is the gate before any Flutter work: the core must boot and render with
# nothing else involved. Run it after touching the bridge or bumping the
# SimpleSpeccy checkout.
#
#   native/speccy_core/linux/check-core.sh
#   SKIP_BUILD=1 native/speccy_core/linux/check-core.sh   # reuse out/
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/out"
SPECCY_SRC="${SPECCY_SRC:-$HOME/StudioProjects/SimpleSpeccy}"

if [ -z "${SKIP_BUILD:-}" ]; then
    cmake -S "$HERE" -B "$OUT" -DCMAKE_BUILD_TYPE=Release -DSPECCY_SRC="$SPECCY_SRC" >/dev/null
    cmake --build "$OUT" -j"$(nproc)" >/dev/null
fi

mkdir -p /tmp/retro-spectrum-check
cd "$OUT"
# Only pass a media path if one was actually given -- an empty argv[3] is
# still non-NULL to the harness and would be opened as the file "".
if [ -n "${1:-}" ]; then
    exec ./check_core ./libspeccycore.so "$SPECCY_SRC/res" "$1"
else
    exec ./check_core ./libspeccycore.so "$SPECCY_SRC/res"
fi
