#!/usr/bin/env bash
# Clone all driver sources into $SRC (default: ./src).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/versions.env"
SRC=${SRC:-$ROOT/src}
mkdir -p "$SRC" && cd "$SRC"

clone() { # url dir [branch]
  [ -d "$2/.git" ] && return
  if [ -d "$2" ]; then
    # dir pre-exists (e.g. restored build cache): clone aside and merge in
    git clone -q --depth 1 ${3:+-b "$3"} "$1" "$2.clone"
    cp -a "$2.clone/." "$2/" && rm -rf "$2.clone"
  else
    git clone -q --depth 1 ${3:+-b "$3"} "$1" "$2"
  fi
}
for r in virtio-drivers-windows-rs virtio-d3d11 virtio-d3d12 vkd3d-proton mesa; do
  clone "https://github.com/Droid-VM/$r" "$r" "$DROIDVM_BRANCH"
done

# mesa: local patches (idempotent: skip if already applied)
for r in mesa virtio-drivers-windows-rs virtio-d3d11; do
  for p in "$ROOT"/patches/$r/*.patch; do
    [ -f "$p" ] || continue
    if git -C $r apply --check "$p" 2>/dev/null; then git -C $r apply "$p"
    elif git -C $r apply --reverse --check "$p" 2>/dev/null; then :  # already applied
    else echo "ERROR: patch $p does not apply"; exit 1; fi
  done
done

# virtio-d3d11: its dxvk submodule commit only exists in the Droid-VM fork.
if [ ! -f virtio-d3d11/thirdparty/dxvk/meson.build ]; then
  rm -rf virtio-d3d11/thirdparty/dxvk
  git clone -q -b "$DROIDVM_BRANCH" https://github.com/Droid-VM/dxvk virtio-d3d11/thirdparty/dxvk
  git -C virtio-d3d11/thirdparty/dxvk submodule update -q --init --recursive --depth 1
fi

# vkd3d-proton: public submodules + dxil-spirv at a public commit with patch.
git -C vkd3d-proton submodule update -q --init --depth 1 khronos/SPIRV-Headers khronos/Vulkan-Headers
D=vkd3d-proton/subprojects/dxil-spirv
if [ ! -f "$D/meson.build" ]; then
  rm -rf "$D"
  git clone -q https://github.com/HansKristian-Work/dxil-spirv "$D"
  git -C "$D" checkout -q "$DXIL_SPIRV_COMMIT"
  git -C "$D" submodule update -q --init --recursive --depth 1
  for p in "$ROOT"/patches/dxil-spirv/*.patch; do git -C "$D" apply "$p"; done
fi

clone https://github.com/KhronosGroup/Vulkan-Headers Vulkan-Headers "$VULKAN_SDK_TAG"
clone https://github.com/KhronosGroup/Vulkan-Loader Vulkan-Loader "$VULKAN_SDK_TAG"

# Record exact revisions for the release notes.
{
  for d in virtio-drivers-windows-rs virtio-d3d11 virtio-d3d11/thirdparty/dxvk virtio-d3d12 \
           vkd3d-proton "$D" mesa Vulkan-Loader Vulkan-Headers; do
    echo "- $d: $(git -C "$d" remote get-url origin) @ $(git -C "$d" rev-parse --short=12 HEAD)"
  done
} > "$SRC/REVISIONS.md"
cat "$SRC/REVISIONS.md"
