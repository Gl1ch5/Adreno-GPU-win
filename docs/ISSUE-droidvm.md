# Draft issue for Droid-VM developers (user posts it himself)

**Title:** wingpu on Snapdragon 8 Gen 5 (Adreno 829): desktop accelerated, but GDI/WinUI artifacts; boot pool feature missing in dev crosvm

**Setup**
- Device: Snapdragon 8 Gen 5, Adreno 829, DroidVM 0.0.6.r242.g3348830 (dev, 2026-10-12)
- Graphics: VirGL, Native Context, DRM to KGSL, Pseudo Unprotected, 5120 MiB RAM, 256 MB command buffer pool
- Guest: Windows 11 ARM64 24H2 (26100), unofficial wingpu build (KMD virtio-drivers-windows-rs, UMD virtio-d3d11 + DXVK, Turnip)
- Build, patches and logs: https://github.com/gl1ch5/adreno-gpu-win (branch claude/droidvm-gpu-driver-build-kbxnrt)

**What works**
- dwm runs on DXVK + Turnip, D3D 11_1, 4K video is smooth, Task Manager shows the GPU.

**Problems / what we had to patch**
1. crosvm does not offer virtio-gpu feature 7 (`DROIDVM_BOOT_POOL`) → KMD `VESCMAPB` fails `0xc0000182`.
   Workaround: KMD reads pool base from registry; pool = top of guest RAM
   (`0x80000000 + RAM - pool`, e.g. 5 GiB/256 MB → `0x1b0000000`). Any mismatch = black screen.
   Could the feature be exposed, or the pool address passed to the guest another way?
2. Turnip did not know chip id `0x44030a00` (virtio guest form of Adreno 829) → added to the table.
3. Mesa/zlib/winpthread had to be linked statically (DLLs not found in dwm).
4. **Unresolved: artifacts** in small GDI/WinUI elements (title bars, buttons, tray, icons):
   garbage/white/green blocks, sometimes stale content. Large surfaces are clean.
   Excluded: TU_DEBUG noubwc/sysmem, CPU wait, TDR, ClearType, MPO, pitch 256 for GDI
   shadow/staging surfaces, uncached CPU mapping for CPU-visible 3D allocations.
   Imported shared surfaces have correct row pitch. Small elements are STAGING textures
   (Map from CPU, then copy on GPU). Also seen: occasional `VK_ERROR_DEVICE_LOST`
   (`wddm submit failed status=0xc00002b6`) and `pfnDeallocateCb failed 0x80070057`.
   Question: is the guest RAM pool mapped coherently for KGSL on the host side (cache
   maintenance for guest-written pages)? Any known issue on 8 Gen 5 / a8xx?

**Not working yet:** DX12 (vkd3d_create_device failed), DX9 (no UMD), OpenGL.

Screenshots and full logs available on request.
