#!/usr/bin/env bash
# Build Droid-VM virglrenderer (wingpu, drm2kgsl + venus + vrend) as an Android
# arm64 libvirglrenderer.so with the NDK, mirroring its Android.bp.
# usage: build-virglrenderer.sh VIRGL_SRC EPOXY_BUILD_DIR LIBDRM_SRC OUT
set -euo pipefail
VR=$(realpath "$1"); EPOXY=$(realpath "$2"); DRM=$(realpath "$3"); OUT=$(realpath -m "$4")
HERE=$(cd "$(dirname "$0")" && pwd)
CC=${CC:-aarch64-linux-android31-clang}
mkdir -p "$OUT/obj"
SRCS=$(python3 - "$VR/Android.bp" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
blk = s[s.index('name: "libvirglrenderer"'):]
srcs = re.search(r'srcs:\s*\[(.*?)\]', blk, re.S).group(1)
print(" ".join(re.findall(r'"([^"]+)"', srcs)))
PY
)
INC="-I$VR/prebuilt-intermediates -I$VR/prebuilt-intermediates/venus -I$VR/src -I$VR/src/drm \
 -I$VR/src/drm/drm-uapi -I$VR/src/gallium/auxiliary -I$VR/src/gallium/auxiliary/util \
 -I$VR/src/gallium/include -I$VR/src/mesa -I$VR/src/mesa/compat -I$VR/src/mesa/pipe \
 -I$VR/src/mesa/util -I$VR/src/venus -I$HERE/shim -I$DRM -I$DRM/include/drm \
 -I$EPOXY/../include -I$EPOXY/include"
CFLAGS="-std=gnu17 -O2 -fPIC -fvisibility=hidden -DHAVE_CONFIG_H -include $VR/prebuilt-intermediates/config.h \
 -D__USE_GNU -DHAVE_MEMFD_CREATE=1 -Wno-unused-parameter -Wno-error -w"
objs=()
for s in $SRCS; do
  o="$OUT/obj/$(echo "$s" | tr / _).o"
  objs+=("$o")
  ( cd "$VR" && $CC $CFLAGS $INC -c "$s" -o "$o" ) &
  while [ "$(jobs -r | wc -l)" -ge "$(nproc)" ]; do sleep 0.2; done
done
wait
$CC -shared -o "$OUT/libvirglrenderer.so" -Wl,-soname,libvirglrenderer.so "${objs[@]}" \
  "$EPOXY/src/libepoxy.a" -llog -ldl -lm -Wl,--no-undefined
llvm-strip --strip-unneeded "$OUT/libvirglrenderer.so"
ls -la "$OUT/libvirglrenderer.so"
