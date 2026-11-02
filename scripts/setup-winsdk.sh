#!/usr/bin/env bash
# Assemble an EWDK-like tree from NuGet packages, so the upstream build
# scripts (util/ewdk) can find headers/libs without the EWDK ISO.
# usage: setup-winsdk.sh OUT_DIR
set -euo pipefail
OUT=$(realpath -m "$1")
NUGET_VER=${NUGET_VER:-10.0.28000.2526}
SDKVER=${SDKVER:-10.0.28000.0}
DL=$OUT/.nuget
mkdir -p "$DL" "$OUT/sdk"
for p in microsoft.windows.wdk.arm64 microsoft.windows.wdk.x64 microsoft.windows.sdk.cpp; do
  [ -d "$DL/$p" ] && continue
  curl -sSLf --retry 5 -o "$DL/$p.zip" \
    "https://api.nuget.org/v3-flatcontainer/$p/$NUGET_VER/$p.$NUGET_VER.nupkg"
  mkdir -p "$DL/$p" && (cd "$DL/$p" && unzip -q ../$p.zip) && rm "$DL/$p.zip"
done
S=$OUT/sdk
mkdir -p "$S/Include" "$S/Lib"
cp -r --update=none "$DL/microsoft.windows.sdk.cpp/c/Include/." "$S/Include/"
for a in arm64 x64; do
  cp -r --update=none "$DL/microsoft.windows.wdk.$a/c/Include/." "$S/Include/"
  cp -r --update=none "$DL/microsoft.windows.wdk.$a/c/Lib/." "$S/Lib/"
done
# lower-case arch dir aliases (lld on Linux is case sensitive)
for d in "$S/Lib/$SDKVER/km" "$S/Lib/$SDKVER/um" "$S/Lib/wdf/kmdf" ; do
  [ -d "$d" ] || continue
  for a in ARM64:arm64 X64:x64 x64:x64; do
    up=${a%:*}; lo=${a#*:}
    [ -d "$d/$up" ] && [ ! -e "$d/$lo" ] && ln -s "$up" "$d/$lo"
  done
done
# Case-insensitive VFS overlay: WDK headers include each other with random
# casing. util/ewdk mounts the SDK at /winsys/sdk through this overlay.
python3 "$(dirname "$0")/gen-vfs.py" "$S" "$OUT/vfs-overlay.json"
cat > "$OUT/ewdk.env" <<ENV
export VCTOOLSDIR="$OUT/vc"
export WINSDKDIR="$S"
export WINSDKVER="$SDKVER"
export VFSOVERLAY="$OUT/vfs-overlay.json"
ENV
mkdir -p "$OUT/vc"
echo "WinSDK ready in $OUT"
