# AGENTS.md — droidvm-gpu-build (Adreno-GPU-win)

Неофициальная сборка VirtIO-GPU WDDM драйвера DroidVM (anonymix007 / Droid-VM,
ветка `wingpu`) для Windows 11 ARM64. AGPL-3.0, не для продажи.

## Структура
- `.github/workflows/build.yml` — Linux (llvm-mingw) собирает бинарники, Windows-раннер
  делает INF/каталог/подпись/установщики (Inno Setup) и релиз `build-N`.
- `scripts/fetch-sources.sh` — клонирует исходники (+ фиксы сабмодулей).
- `scripts/setup-winsdk.sh` — WDK/SDK из NuGet + case-insensitive VFS overlay (`gen-vfs.py`).
- `scripts/build.sh` — `ARCH=arm64` (KMD, dx11um, dx12um, Turnip, loader; KMD также в
  diag-варианте `--features bringup-diagnostics`).
- `scripts/package.ps1` — пакет, подпись, `DroidVM-GPU-Setup(.exe|-diag.exe)`, Uninstall, zip.
- `package/` — ARM64 INF (`virtio_wddm_rs.inx`), установщик, install/uninstall.ps1.
- `tools/DroidVM-GPU-Logs.cmd` — сборщик логов в ВМ (задача при загрузке, логи в
  Downloads, опционально upload на сервер, включает RDP).
- `patches/dxil-spirv/` — патч к dxil-spirv (неопубликованный коммит апстрима).
- `versions.env` — пины версий.
- `docs/STATUS.md` — журнал тестов и текущее состояние. Обновлять после каждого теста.

## Правила
- Локальная проверка до пуша: `scripts/fetch-sources.sh && ARCH=arm64 scripts/build.sh`
  (нужны llvm-mingw, rust nightly + rust-src, clang как clang-cl, meson, ninja, cmake,
  glslangValidator, cbindgen). PowerShell-скрипты проверять парсером pwsh.
- Не синхронизировать `virtio_wddm_uapi.h` (UMD) с `uapi.rs` (KMD) — см. STATUS.md.
- `*.cmd` хранятся с CRLF (`.gitattributes`).
- Не включать Venus (`vulkan_virtio.dll`) — на Windows не собирается/не работает.
- Коммиты: ветка `claude/droidvm-gpu-driver-build-kbxnrt`, без идентификаторов моделей.
- Секреты (токен сервера логов, PFX) в репозиторий не коммитить. Репозиторий публичный.
