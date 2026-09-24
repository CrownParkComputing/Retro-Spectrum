#!/bin/sh
# check-bridge.sh -- the gate before any Flutter work.
#
# The previous build had check-core.sh over UnrealSpeccyPortable; this
# is the equivalent over the zxpoly stub. It builds the headless
# library and dlopens it to verify the recolour API round-trips
# (set_recolour / get_recolour) -- the only non-errored behaviour in
# phase 1.
#
# Reuse the build:
#   SKIP_BUILD=1 native/zxpoly_bridge/linux/check-bridge.sh
#
# Pass a custom zxpoly checkout (phase 2):
#   ZXPOLY_SRC=/path/to/zxpoly native/zxpoly_bridge/linux/check-bridge.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${BUILD_DIR:-${HERE}/out}"
SKIP_BUILD="${SKIP_BUILD:-}"

cd "$(cd "${HERE}/../../.." && pwd)"  # project root (Retro-Spectrum/)

if [ -z "${SKIP_BUILD}" ]; then
    cmake -S native/zxpoly_bridge/linux -B "${BUILD_DIR}"
    cmake --build "${BUILD_DIR}" -j
fi

LIB="${BUILD_DIR}/libzxpolycore.so"
if [ ! -f "${LIB}" ]; then
    echo "Library not built: ${LIB}" >&2
    exit 1
fi

cat > /tmp/zxpoly_check.c <<'EOF'
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef int  (*set_recolour_t)(int);
typedef int  (*get_recolour_t)(void);

int main(int argc, char **argv) {
    const char *lib = argc > 1 ? argv[1] : "./libzxpolycore.so";
    void *h = dlopen(lib, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen(%s): %s\n", lib, dlerror()); return 1; }

    set_recolour_t  set_recolour  = (set_recolour_t)  dlsym(h, "zxpoly_bridge_set_recolour");
    get_recolour_t  get_recolour  = (get_recolour_t)  dlsym(h, "zxpoly_bridge_get_recolour");
    if (!set_recolour || !get_recolour) {
        fprintf(stderr, "dlsym: %s\n", dlerror());
        return 1;
    }

    /* Default must be on. */
    if (get_recolour() != 1) {
        fprintf(stderr, "default recolour is off; expected on\n");
        return 1;
    }
    /* Round-trip off and on. */
    if (set_recolour(0) != 0 || get_recolour() != 0) return 1;
    if (set_recolour(1) != 0 || get_recolour() != 1) return 1;

    dlclose(h);
    puts("check-bridge: OK");
    return 0;
}
EOF

cc -o /tmp/zxpoly_check /tmp/zxpoly_check.c -ldl
/tmp/zxpoly_check "${BUILD_DIR}/libzxpolycore.so"
