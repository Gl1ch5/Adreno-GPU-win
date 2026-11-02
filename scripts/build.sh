#!/usr/bin/env bash
# Build one architecture of the DroidVM GPU driver.
#   ARCH=arm64   : kernel driver + native ARM64 user-mode drivers
# Output goes to $OUT/$ARCH (default ./out/arm64).
# Needs: llvm-mingw in PATH, $WINSDK prepared by setup-winsdk.sh,
# rust nightly with rust-src, clang (as clang-cl), meson, ninja, cmake,
# glslangValidator, cbindgen.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/versions.env"
ARCH=${ARCH:-arm64}
SRC=${SRC:-$ROOT/src}
WINSDK=${WINSDK:-$ROOT/winsdk}
OUT=${OUT:-$ROOT/out}/$ARCH
JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT"

case $ARCH in
  arm64)   PREFIX=aarch64-w64-mingw32; CROSS=aarch64; TAG=arm64 ;;
  arm64ec) PREFIX=arm64ec-w64-mingw32; CROSS=arm64ec; TAG=arm64ec ;;
  x86)     PREFIX=i686-w64-mingw32;    CROSS=i686;    TAG=x86 ;;
  *) echo "unknown ARCH=$ARCH"; exit 1 ;;
esac
CROSSFILE=$ROOT/cross/$CROSS.ini
SDKINC=$WINSDK/sdk/Include/$SDKVER
MINGWINC=$(dirname "$(command -v $PREFIX-clang)")/../generic-w64-mingw32/include

step() { echo "::group::$ARCH: $*"; }
endstep() { echo "::endgroup::"; }

ddk_headers() { # dir
  python3 "$ROOT/scripts/collect-ddk-headers.py" "$1" "$MINGWINC" "$SDKINC/um" "$SDKINC/shared" \
    -- d3d10umddi.h d3d12umddi.h d3dumddi.h d3dkmthk.h
}

# ---------------------------------------------------------------- KMD
if [ "$ARCH" = arm64 ]; then
  step "kernel driver (Rust)"
  K=$SRC/virtio-drivers-windows-rs
  cp "$WINSDK/ewdk.env" "$K/ewdk.env"
  # Upstream config only has the x86_64 target: add the same for aarch64.
  if ! grep -q 'aarch64-pc-windows-msvc' "$K/.cargo/config.toml"; then
    python3 - "$K/.cargo/config.toml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
m = re.search(r'\[target\.x86_64-pc-windows-msvc\].*?\n\]\n', s, re.S)
s = s.replace('target = "x86_64-pc-windows-msvc"', 'target = "aarch64-pc-windows-msvc"')
s = s.replace(m.group(0), m.group(0) + "\n" + m.group(0).replace("x86_64", "aarch64"))
open(p, "w").write(s)
PY
  fi
  mkdir -p "$OUT/include"
  cbindgen --config "$K/gpu-wddm/cbindgen.toml" "$K/gpu-wddm/src/uapi.rs" > "$OUT/include/virtio_wddm_uapi.h"
  (cd "$K" && cargo build --package virtio-gpu-wddm-rs --target aarch64-pc-windows-msvc)
  cp "$K/target/aarch64-pc-windows-msvc/debug/virtio_gpu_wddm_rs.dll" "$OUT/virtio_wddm_rs.sys"
  cp "$K/target/aarch64-pc-windows-msvc/debug/virtio_gpu_wddm_rs.pdb" "$OUT/" 2>/dev/null || true
  endstep
fi
UAPI=$ROOT/out/arm64/include/virtio_wddm_uapi.h

# ---------------------------------------------------------------- D3D11
step "dx11um_virtio.dll (DXVK)"
D11=$SRC/virtio-d3d11
ddk_headers "$D11/include/winddk" >/dev/null
cp "$UAPI" "$D11/include/virtio_wddm_uapi.h"
LTO=-flto; [ "$ARCH" = x86 ] && LTO=
make -C "$D11" -j"$JOBS" PREFIX=$PREFIX BUILD_DIR=build-$TAG LTO=$LTO
cp "$D11/build-$TAG/dist/dx11um_virtio.dll" "$OUT/"
endstep

# ---------------------------------------------------------------- D3D12
step "vkd3d-proton (UMD static libs)"
VK=$SRC/vkd3d-proton; VKB=$VK/build.umd-$TAG
[ -f "$VKB/build.ninja" ] || meson setup "$VKB" "$VK" --cross-file "$CROSSFILE" \
  --buildtype release -Denable_umd=true -Denable_tests=false -Denable_extras=false -Denable_trace=false
ninja -C "$VKB" -j "$JOBS" \
  libs/vkd3d/libvkd3d-proton.a libs/vkd3d-shader/libvkd3d-shader.a \
  libs/vkd3d-common/libvkd3d_common.a subprojects/dxil-spirv/libdxil-spirv.a \
  subprojects/dxil-spirv/libdxbc_spv_module.a \
  subprojects/dxil-spirv/subprojects/dxbc-spirv/libdxbc_spv.a
endstep
step "dx12um_virtio.dll"
D12=$SRC/virtio-d3d12
ddk_headers "$D12/include/winddk" >/dev/null
make -C "$D12" -j"$JOBS" PREFIX=$PREFIX BUILD_DIR=build-$TAG VKD3D_SRC="$VK" VKD3D_BUILD="$VKB" D3D11_DIR="$D11"
cp "$D12/build-$TAG/dist/dx12um_virtio.dll" "$OUT/"
endstep

# ---------------------------------------------------------------- Mesa (Turnip)
step "vulkan_freedreno.dll (Turnip)"
M=$SRC/mesa; MB=$M/build-$TAG
WDDM_INC=$OUT/wddm-inc; mkdir -p "$WDDM_INC"
cp "$UAPI" "$D11"/include/winddk/*.h "$WDDM_INC/"
[ -f "$MB/build.ninja" ] || meson setup "$MB" "$M" --cross-file "$CROSSFILE" --buildtype release \
  -Dvulkan-drivers=freedreno -Dfreedreno-kmds=virtio -Dgallium-drivers= -Dplatforms=windows \
  -Dllvm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Degl=disabled -Dglx=disabled \
  -Dzstd=disabled -Dexpat=disabled -Dvalgrind=disabled -Dbuild-tests=false -Dmicrosoft-clc=disabled \
  -Dc_args="-I$WDDM_INC" -Dcpp_args="-I$WDDM_INC" \
  -Dc_link_args=-lwinpthread -Dcpp_link_args=-lwinpthread
ninja -C "$MB" -j "$JOBS" src/freedreno/vulkan/libvulkan_freedreno.dll
cp "$MB/src/freedreno/vulkan/libvulkan_freedreno.dll" "$OUT/vulkan_freedreno.dll"
$PREFIX-strip --strip-debug --strip-unneeded "$OUT/vulkan_freedreno.dll"
endstep

# ---------------------------------------------------------------- Vulkan loader
step "droidvm_vulkan.dll (Khronos Vulkan-Loader)"
VH=$SRC/vulkan-headers-install
[ -d "$VH" ] || { cmake -S "$SRC/Vulkan-Headers" -B "$SRC/build-vh" -G Ninja -DCMAKE_INSTALL_PREFIX="$VH" >/dev/null; cmake --install "$SRC/build-vh" >/dev/null; }
case $ARCH in arm64|arm64ec) PROC=ARM64 ;; x86) PROC=x86 ;; esac
LB=$SRC/build-vulkan-loader-$TAG
cmake -S "$SRC/Vulkan-Loader" -B "$LB" -G Ninja \
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=$PROC \
  -DCMAKE_C_COMPILER=$PREFIX-clang -DCMAKE_CXX_COMPILER=$PREFIX-clang++ \
  -DCMAKE_RC_COMPILER=$PREFIX-windres -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF -DBUILD_WERROR=OFF -DUSE_MASM=OFF -DUSE_GAS=OFF \
  -DVULKAN_HEADERS_INSTALL_DIR="$VH"
cmake --build "$LB" -j "$JOBS"
cp "$LB/loader/vulkan-1.dll" "$OUT/droidvm_vulkan.dll"
endstep

# ---------------------------------------------------------------- naming
if [ "$ARCH" != arm64 ]; then
  # The UMD looks for <name>_x86.dll / <name>_arm64ec.dll next to the native ones.
  for f in dx11um_virtio dx12um_virtio vulkan_freedreno droidvm_vulkan; do
    mv "$OUT/$f.dll" "$OUT/${f}_$TAG.dll"
  done
fi
rm -rf "$OUT/wddm-inc"
ls -la "$OUT"
