# Состояние проекта и журнал тестов (для продолжения работы)

Обновлено: 2026-11-02. Ветка: `claude/droidvm-gpu-driver-build-kbxnrt`
(в репозитории нет `main`, PR не открыт). Релизы: build-4 (первый рабочий CI),
build-5 (добавлен `DroidVM-GPU-Setup-diag.exe`).

## Устройство пользователя
- Телефон: Snapdragon 8 Gen 5, Adreno 829 (KGSL chip_id 0x44030a20 → 0x44030a00, gpu_id 6840).
- DroidVM: backend CrosVM, hypervisor **Qualcomm Gunyah**.
- ВМ: Windows 11 ARM64 (build 26300), qcow2 `/data/media/0/DroidVM/Windows 11 ARM64 (DroidVM)_1/`.
- Память ВМ ~3 ГБ, 2 vCPU (пользователю советовали 8 GiB / 6 CPU). Поле Memory в **GiB**.
- Graphics: Renderer VirGL, Graphics API **Native Context**, Host driver **DRM to KGSL**,
  VRAM/Command buffer pool 64 MB, Transport pipeline CPU Copy, SimpleFB включён.
- Пользователь пишет с телефона: давать команды одной строкой для **PowerShell** (не cmd, `&` не работает).

## Режимы Protected VM (проверено на устройстве)
| Режим | Результат |
|---|---|
| Unprotected | ВМ не стартует: `GH-DIAG: GH_VM_START failed`, `Operation not permitted` |
| Protected | ВМ не стартует (со слов пользователя) |
| Protected without firmware | Windows грузится, драйвер **Code 43**; хост: `split_queue get_avail_index: host access to lent memory region ... in protected VM` |
| Pseudo Unprotected | Драйвер стартует, capset проходит, но `ResourceAttachBacking: ErrRutabaga(ComponentError(22))` ×2 → чёрный экран/зависание, иногда WinRE |

Код KMD (`guest_backing.rs`) рассчитан на «pseudo-unprotected VM». В
Droid-VM/gunyah-guest-drivers-windows viogpu помечен «not ported» для protected VM.
Один запуск (05:15) в цикле ресетился (`exit type 2`) сразу после старта, в логе
появился `GH-POOL: gpu_guest pool ... 1024 MB (guest-owned)` — какую настройку
включил пользователь, не выяснено. Гипотеза: хост принимает backing только из
GPU-пула, отсюда EINVAL(22). Не проверено.

Аварийный выход: Graphics → Virtio-GPU → **Enable display device = off** (или
отключить устройство в Диспетчере) → Windows грузится через SimpleFB.

## Диагностика (bringup-diagnostics)
- `DroidVM-GPU-Setup-diag.exe`: KMD собран с `--features bringup-diagnostics`.
- Пишет в `HKLM\SYSTEM\CurrentControlSet\Services\VirtioGpu\Parameters\Bringup`,
  но **только открывает** ключ (ZwOpenKey) — ключ должен существовать. INF build-4/5
  его не создавал; исправлено коммитом "INF: create Parameters\Bringup key". На
  машине пользователя ключ создан вручную `reg add ... /f`.
- Установлен oem11.inf, DriverVer 20.15.1.5 (build-5; normal и diag имеют одинаковую
  версию — различаются размером .sys: 787768 vs 771384 байт).
- Чтение: `reg query HKLM\SYSTEM\CurrentControlSet\Services\VirtioGpu\Parameters\Bringup > "$env:USERPROFILE\Desktop\bringup.txt"; notepad "$env:USERPROFILE\Desktop\bringup.txt"`
- Следующий шаг: прочитать значения после запуска в Pseudo Unprotected, найти
  место отказа attach backing (см. `gpu-wddm/src/command.rs` attach_backing*,
  `guest_backing.rs`).

## Особенности сборки (что пришлось чинить)
- WDK/SDK из NuGet **10.0.28000.2526** (26100 не хватает для d3d12). Explicit
  case-insensitive VFS overlay (`scripts/gen-vfs.py`); directory-remap не работает.
- `.cargo/config.toml`: добавляется секция aarch64-pc-windows-msvc.
- dxvk сабмодуль → Droid-VM/dxvk@wingpu (коммит из .gitmodules не опубликован).
- dxil-spirv: коммит bdbd41e не опубликован → bb7e3607 + `patches/dxil-spirv`
  (start_row/start_col в stream output).
- uapi: UMD собираются со своим `virtio-d3d11/include/virtio_wddm_uapi.h`, KMD со
  своим `uapi.rs`. Не синхронизировать: KMD разбирает расширения по размеру
  (+12 ReuseBlob, +32 Primary, adapter.rs:2535/2568) — проверено.
- Venus (`vulkan_virtio.dll`) не собирается: на Windows нет рендерера (vtest
  исключён, WDDM-бэкенда нет). Не включён.
- INF: слот D3D9 пустой `<>` (D3D9On12), HWID с SUBSYS_11001AF4 и общий
  `PCI\VEN_1AF4&DEV_1050` (реальное устройство: SUBSYS_10501AF4).
- Подпись: новый self-signed сертификат каждую сборку (если нет секрета
  SIGN_PFX_BASE64); TESTSIGNING включает установщик — работает (Windows приняла).

## Не сделано
- ARM64EC (x64-игры) и x86 (32-бит) — заготовки в cross/*.ini и build.sh.
- Проверка на устройстве: графика не заработала ни в одном режиме.

## Результат diag (Pseudo Unprotected, oem11 = build-5 diag), 2026-11-02 ~05:50
- Инициализация OK: StartDeviceStatus 0, CreateDevice 0x83, submit/fence 20/20, IRQ/DPC без потерь.
- Primary/shadow: два 3D virgl-ресурса (ResId 2,3; 0x9db страниц ≈ 10 МБ, Bind 0x4008a,
  VirglFlags 4) → AttachBuild0/1 с MDL → хост отвечает `ResourceAttachBacking ComponentError(22)`.
- Present: RtPresentLocalIneligibleNotGuestBlob = 20/20 (src kind 2 = _3D), локальное копирование
  не используется → чёрный экран.
- Гипотеза: в режиме DRM to KGSL хост не умеет 3D virgl-ресурсы; в логе каждый раз
  `linker: /vendor/lib64/hw/vulkan.adreno.so ... is not accessible for the namespace` — crosvm
  не может загрузить системный Vulkan Adreno. Это сторона DroidVM, не сборки.
- Предложено попробовать: Graphics API = Vulkan; GPU-blit = Vulkan (System).

## Сервер логов (MCP "Server", grzxk.ru / 64.188.66.249)
- Сервис `droidvm-logs` (systemd, DynamicUser): `/opt/droidvm-logs/server.py`, слушает 127.0.0.1:8876.
- nginx: `/etc/nginx/conf.d/droidvm-logs.conf` — `https://grzxk.ru:8877` (сертификат grzxk.ru). Другие сайты не трогались.
- Токен: `/opt/droidvm-logs/token` (в репозиторий НЕ коммитить).
- Скачать настроенный сборщик: `https://grzxk.ru:8877/setup/<token>` (подставляет токен в tools/DroidVM-GPU-Logs.cmd,
  копия шаблона в `/opt/droidvm-logs/DroidVM-GPU-Logs.cmd`, обновлять после правок).
- Логи: `/var/lib/droidvm-logs/` (читать через MCP run_root: `ls -t /var/lib/droidvm-logs | head`).
- В VM: задача планировщика "DroidVM GPU logs" (SYSTEM, через 90 с после загрузки) → `C:\ProgramData\DroidVM-GPU\collect.ps1`,
  копии в `%USERPROFILE%\Downloads\DroidVM-GPU-Logs\` (LATEST.txt), также включает RDP и GPU для RDP.

## Тест 06:16 (Graphics API = Vulkan или Native+Vulkan(System) — уточняется)
- Сервер получил лог текущей загрузки с GPU: device Status=OK, Problem=0 (нет Code 43),
  RtCreateDevice 0x62, submit 12/12, но present 12/12 NotGuestBlob, primary снова 3D virgl
  (ResId 2/3) → вероятно, снова чёрный экран. Логи предыдущей попытки не пришли
  (ВМ выключена раньше 90 с). Ждём лог DroidVM (ERROR) и проверку RDP на 192.168.148.128.
- Релиз build-12: INF создаёт Parameters\Bringup, в релизе есть DroidVM-GPU-Logs.cmd (без токена).

## Разбор EINVAL(22) по исходникам хоста (Droid-VM/crosvm@droidvm 849e05f, virglrenderer@wingpu 6e0d606)
- crosvm `rutabaga_gfx/src/rutabaga_core.rs:768-785` (classic_component): при default_component=Gfxstream
  классические 3D-ресурсы «создаются, но readback/attach падают с EINVAL»; уходят в Rutabaga2D,
  только если тот есть среди компонентов. default=Gfxstream, если включён любой gfxstream-capset.
- virglrenderer `src/virglrenderer.c:447-471`: EINVAL в virgl-пути всегда печатает `attach_iov: ...`;
  в логах пользователя этих строк нет → вероятно, ошибка из gfxstream (гипотеза).
- `vulkan.adreno.so` грузит не drm2kgsl (только Venus/vkr или gfxstream) → признак, что включён не чистый DRM.
- KMD: тип primary выбирает UMD (ALLOCATE_3D, adapter.rs:2608); ветка ALLOCATE_BLOB (2551) есть.
  Единственный registry-параметр KMD — PresentLocalCopy, на attach не влияет.
  GUEST-blob требует CREATE_GUEST_HANDLE (хост даёт только при udmabuf).
- Следующий шаг: варианты Renderer в DroidVM; в логе хоста искать `capset|component|gfxstream|attach_iov`.

## 07:04 тест (VirGL + Vulkan + Vulkan(Turnip), Venus pool) — та же ошибка 22
- `ResourceAttachBacking ComponentError(22)` ×2 и в режиме Venus → не зависит от режима хоста.
- virglrenderer@wingpu: сообщение `attach_iov: res_handle=... not found/rejected` (ERROR) добавлено
  в 7490d07 (2026-09-11, "feat: add wddm resource layout support"); crosvm передаёт ERROR в лог.
  В логах пользователя его нет → вероятно, у пользователя DroidVM старше сентября 2026 (без WDDM-поддержки).
- Релизы DroidVM: стабильный 0.0.6 (2026-04-14); dev 0.0.6.r242.3348830 (2026-10-12).
  Рекомендовано: узнать версию, при необходимости обновить до dev (с клоном диска) и повторить тест.
