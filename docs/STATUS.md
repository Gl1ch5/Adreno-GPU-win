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

## 07:09: пользователь уже на DroidVM 0.0.6.r242.g3348830 (dev, 2026-10-12) — та же ошибка
- DroidVM@3348830 берёт хост (crosvm/virglrenderer) из сабмодуля DroidVM-Prebuilts @ c4998e1
  (2026-09-12, это последний коммит prebuilts). Гостевые исходники wingpu новее: KMD 10-01, UMD 10-03;
  virglrenderer drm2kgsl-фиксы для Adreno 830 (10-13) в APK не попали.
- Гипотеза: рассинхрон гость (октябрь) ↔ хост (12 сентября). Опции: ждать новых prebuilts / issue
  разработчикам; собрать гостя из исходников ~09-12; собрать хост самим (рискованно).

## 07:27–07:34: своя хостовая libvirglrenderer.so (релизы host-1/host-2)
- Путь: /data/user/0/cn.classfun.droidvm/usr/lib/libvirglrenderer.so; из Termux только через
  `su -c "nsenter -t 1 -m -- ..."` (изоляция данных приложений). Скрипты host/install|restore-virgl.sh.
- host-1 падал на assert (устаревший prebuilt u_format_table.c) → host-2: таблица генерируется, NDEBUG.
- host-2 грузится, теперь видна точная причина:
  `attach_iov: res_handle=2 rejected: ret=22 count=26 existing_count=2523` (то же для res 3).
  Первая привязка — KMD UPDATE_PAGE_TABLE (attach_backing_virtual, постранично 2523, без detach),
  вторая — MAP_APERTURE_SEGMENT (detach+attach по MDL, 26 кусков); на хосте detach не успевает.
- host-3: патч host/patches/0001 — attach_iov заменяет существующий backing вместо EINVAL.
- 07:40 host-3: `attach_iov: res_handle=2/3 replacing existing backing (2523 -> 18/375 iovs)` — ошибок
  ResourceAttachBacking больше нет. Windows: Status=OK, present 10/10 (host path, NotGuestBlob),
  submit/fence 10/10. Ждём, что видно на экране.

## 2026-11-02 07:55 — чёрный экран = падение dwm.exe
- host-3: attach EINVAL нет, хост пишет `FLUSH-ROUTE: transfer_read: readback is black` (ещё на этапе прошивки).
- Windows: устройство Status=OK, но `dwm.exe` падает в цикле: исключение `0x889800b0`,
  `dwmcore.dll+0x27bde4`. dxdiag: Feature Levels пусто, WDDM 2.0.
- Импорты/экспорты `dx11um_virtio.dll` и `dx12um_virtio.dll` в порядке.
- Ошибка пакета: `vulkan_freedreno.dll` импортирует `libwinpthread-1.dll` и `libz-1.dll`,
  в пакете их нет (Vulkan не загрузится). Исправить: статическая линковка.
- Сборщик логов (b9683f0): лог DXVK (`DXVK_LOG_PATH`) и минидамп dwm (WER LocalDumps)
  отправляются на сервер (`*.dmp.b64`).

## 2026-11-02 11:05 — корень: crosvm без DROIDVM_BOOT_POOL
- build-29: Turnip грузится (статическая линковка), но `enumAdapters` = 0.
- build-33 + VDRM_WDDM_DEBUG: `vdrm-wddm: connect failed at shared ring`,
  `Escape VESCMAPB: status=0xc0000182` (DEVICE_CONFIGURATION_ERROR).
- Bringup: `BlobMapInfo=0x80000001` (MAP_INFO_POOL), `BlobMapOffsetLow=0x200000`,
  записей `BootPool*` нет → фича virtio-gpu bit 7 `DROIDVM_BOOT_POOL` не согласована.
- KMD (wingpu, adapter.rs:1826) без boot_pool отвечает DEVICE_CONFIGURATION_ERROR.
- crosvm в DroidVM dev 3348830 (prebuilts c4998e1) собран из ветки `droidvm`:
  там есть MAP_INFO_POOL, но нет `boot_pool.rs`/DVMPOOL1. Он есть в crosvm `wingpu`
  (3a09957, 2026-10-14). Нужен crosvm из ветки wingpu на хосте.
- Важно: в DroidVM должен стоять Graphics API = Native Context (в режиме Vulkan
  Windows видит только capset venus).

## 2026-11-02 11:34 — build-34: пул работает, Turnip не знает chip_id
- Обход пула через реестр работает: `VESCMAPB` = 0, `BlobMapStage=4`, `VESCEXEC` идут,
  `physical render enabled`. Подключение vdrm-wddm проходит.
- Новая ошибка: `tu_device.cc:1778: device (chip_id = 44030A00, gpu_id = 6840) is unsupported`.
  Хост нормализует 0x44030a20 → 0x44030a00, а в freedreno_devices.py есть только KGSL-id.
  Патч mesa 0002 добавляет `0x44030a00` (как у a840/FD750 «virtio guest, patch level 0»).

## 2026-11-02 11:51 — build-35: УСКОРЕНИЕ РАБОТАЕТ (рабочий стол на GPU)
- Подтверждено логом с ВМ (Native Context, DRM to KGSL, Pseudo Unprotected, 3 GiB):
  dwm.exe и explorer.exe загрузили `dx11um_virtio.dll`, `droidvm_vulkan.dll`,
  `vulkan_freedreno.dll`; Turnip `Found compatible device 'virtio-gpu (WDDM)'`;
  DXVK `Using feature level D3D_FEATURE_LEVEL_11_1`; dxdiag Feature Levels 11_1..9_1;
  падений dwm после загрузки нет. Пользователь видит рабочий стол.
- Проблемы: касание попадает не туда, изображение обрезано (вероятно, режим Windows
  не совпадает с поверхностью DroidVM; в логе хоста `1280x800 -> 1280x720`).
  Сборщик теперь пишет разрешение экрана и HID-устройства.

## 2026-11-02 12:05 — 1920x1080 в DroidVM: касание верное, артефакты
- С разрешением 1920x1080 в DroidVM касание попадает правильно, обрезки нет.
- Диспетчер задач показывает GPU «VirtIO GPU 3D controller», нагрузка 3D, прозрачность есть.
- Артефакты: цветной мусор на тенях/blur окон и белые прямоугольники вместо части текста.
- Эксперимент 1: `TU_DEBUG=startup,noubwc` (отключить UBWC) через сборщик логов.
- 12:19: `TU_DEBUG=0x29` (startup+noubwc+sysmem) применился — артефакты остались,
  значит не UBWC и не GMEM. Испорчено то, что заливается с CPU (глифы, тени).
- Эксперимент 2: `TU_DEBUG=...,flushall,syncdraw` + `TU_WIN_SUBMIT_CPU_WAIT=1`.
  Если не поможет — подозрение на когерентность guest-alloc BO (`MSM_BO_CACHED_COHERENT`,
  tu_knl_drm_virtio.cc ~1859) / кэшируемое отображение в KMD.
- 12:38 (fixoff, TU_DEBUG=startup): sync-эксперимент не помог. Чтение umd.log исправлено.
  В umd.log: Turnip `Found device: Adreno (TM) 829 (turnip Mesa driver 26.2.99)`;
  ошибки `DxvkSubmissionQueue: VK_ERROR_DEVICE_LOST`, `Exception on CS thread`,
  `DxvkCommandPool: Failed to begin command buffer`, dx12um `vkd3d_create_device failed`,
  `Triton: tritonResourceMap: 0x887b0001`, `pfnDeallocateCb failed: 0x80070057`.
  Режим 1920x1080@60. Следующий шаг: хостовой лог KGSL (fault/ERROR) в момент артефактов.
- 12:51: mesa.log: `wddm submit failed: status=0xc00002b6` (STATUS_DEVICE_REMOVED),
  `virtual submission seqno N not consumed (host N-1)`, `wddm_bo_create: submit_ccmd_stream failed`.
  Гипотеза: TDR (2 с) сбрасывает GPU, пока хост ещё работает → DEVICE_LOST и недорисованные окна.
  Эксперимент 3 (`/fix`): TdrDelay=10, TdrDdiDelay=20, VDRM_WDDM_VIRTUAL_TIMEOUT_MS=20000.
- 13:3x: TDR 10 с не помог; событий 4101 (TDR) в журнале нет → гипотеза TDR отпала.
  Ошибки в mesa/umd копились с прошлых загрузок (файлы залочены) — сборщик теперь читает
  только новые строки (смещения в C:\ProgramData\DroidVM-GPU\log-offsets.txt).
- INF: имя устройства «Qualcomm Adreno 829 (DroidVM, unofficial build)» (со следующей сборки);
  сборщик и программа ищут устройство по PCI\VEN_1AF4&DEV_1050.
- Программа 1.3: прогресс-бар, имя GPU из лога DXVK, загрузка 3D/Copy, VRAM, система.
- 13:59 (быстрый лог, только новые строки): за время артефактов ошибок нет (ни DEVICE_LOST,
  ни submit failed). Артефакты — неверная отрисовка Turnip на A8xx (gen2), не сбой.
- Программа 1.6: переключатели TU_DEBUG nocb, nolrz, nolrzfc, nobinmerging,
  noconcurrent(un)resolves, nomultipos, 3d_load + «Включить все» для бисекции.
- 14:25: все TU_DEBUG-переключатели «активно» (подтверждено программой) — артефакты те же,
  ошибок нет. Скриншот изнутри Windows (Win+PrtScn) тоже с артефактами → проблема в отрисовке
  внутри гостя (UMD/DXVK/KMD), не в выводе на хост. Ломаются GDI-элементы (тени, рамки, часть
  текста Win32), DirectX-контент (браузер, видео) чистый. Подозрение: путь GDI-redirection
  поверхностей в triton (tritonResource.c ~548, комментарий про Metal-хост и stride 256).
  Следующий шаг: VIRTIO_WDDM_VERBOSE=1 (переключатель в программе 1.8) + фильтр сборщика.
- 14:54: `Failed to create present context: 0x8007000e` (E_OUTOFMEMORY). В ВМ 2,9 ГБ ОЗУ,
  свободно ~0,1 ГБ (Диспетчер задач 90%). Новая гипотеза артефактов и лагов — нехватка памяти
  (у GPU нет своей VRAM, всё в ОЗУ ВМ). Проверка: больше памяти ВМ. Адрес пула зависит от
  памяти: base = 0x80000000 + RAM − 64 MiB (3 GiB → 0x13c000000, сверено с логом хоста).
  Программа 1.9: выбор памяти ВМ → PoolBaseLow/High в реестре.
- 15:22 (5 ГБ, пул 0x1bc000000 — формула сверена с логом хоста): артефактов меньше
  (меню Диспетчера задач нормальное), но белые блоки в трее остались → ОЗУ лишь часть причины.
  VRAM 16,5 ГБ в Диспетчере — HOST3D_DEFAULT (crosvm не даёт DROIDVM_VRAM_BUDGET), не реальная память.
  Следующая гипотеза: мал drm2kgsl-пул (DroidVM «Command buffer pool size» = 64 МБ).
  Программа 1.11: выбор размера пула; base = 0x80000000 + RAM − pool.

## Сводка по артефактам (2026-11-02 15:45)
Симптом: белые прямоугольники вместо части системного текста (трей, кнопки WinUI) и цветной
мусор по рамкам/заголовкам классических окон. На скриншоте изнутри Windows тоже есть →
ломается отрисовка в госте. DirectX-контент (браузер, видео, наша программа) чистый.
В логах во время артефактов ошибок нет.

Исключено (проверено на устройстве):
- TU_DEBUG: noubwc, sysmem, nocb, nolrz, nolrzfc, nobinmerging, noconcurrent(un)resolves,
  nomultipos, 3d_load, flushall, syncdraw — все «активно», без изменений;
- TU_WIN_SUBMIT_CPU_WAIT, TdrDelay=10/TdrDdiDelay=20 (событий TDR 4101 нет);
- ClearType и тени/все визуальные эффекты выключены — без изменений;
- MPO (Dwm OverlayTestMode=5) — без изменений;
- хост/вывод на экран (артефакты на скриншоте изнутри Windows).
Частично помогло: ОЗУ ВМ 3 → 5 ГБ (было E_OUTOFMEMORY, свободно 0,1 ГБ) — меньше белых блоков
и меньше лагов; пул GPU 64 → 256 МБ — система отзывчивее, артефакты остались.

Текущая гипотеза: путь GDI-redirection поверхностей (содержимое классических окон, KMD standard
allocations) в triton UMD (`tritonResource.c` ~548 — написан под Metal-хост, stride align 256).
Нужен VIRTIO_WDDM_VERBOSE=1 (переключатель в программе ≥1.12; сборщик пишет `VERBOSE=`).

Настройки ВМ сейчас: память 5120 МиБ, Command buffer pool 256 МБ → пул 0x1b0000000 (программа
считает base = 0x80000000 + RAM − pool; сверено с логом хоста для 3 ГБ/64 МБ и 5 ГБ/64 МБ).
- 15:54 VERBOSE=1: общие поверхности dwm (`linear present blob`) — strides от Turnip:
  71x48→512, 553x48→2304, 32x32→256 (кратно 256), 1024x832→4096, 960x480→3840.
  Ломаются именно маленькие (кнопки заголовка, трей, значки), где width*4 не кратно 256.
  Потребитель (dwm) импортирует их через VK_EXT_image_drm_format_modifier с явным rowPitch
  (resource.c ~1222). Гипотеза: Turnip A8xx не соблюдает явный rowPitch при импорте.
  Патч virtio-d3d11 0001: лог «import layout MISMATCH» (явный vs фактический rowPitch).
- Найдено расхождение pitch: KMD для GDI shadow/staging сообщает Pitch = w*4 и в local
  present copy берёт w*4 (device.rs `None => (*width * 4, 0)`), а triton OpenResource для
  TYPE_3D читает с align(w*4, 256) (Metal-хост, tritonResource.c ~571); Turnip не импортирует
  linear с pitch не кратным 64. Патч KMD 0002: `droidvm_pitch(w) = align(w*4, 256)` для
  shadow/staging Pitch+size, local copy и fallback layout. Основной экран (1920*4) не меняется.

## 2026-11-02 16:30 — build-39: pitch 256 для GDI-поверхностей — артефакты остались
- Патч KMD `0002-gdi-surface-pitch-256` (shadow/staging pitch = align(w*4,256)) + диагностика UMD
  (`import layout ok/MISMATCH` в umd.log). Ничего не сломал, но артефакты не убрал.
- Чёрный экран после установки build-39 был НЕ из-за патча: INF перезаписал PoolBase на
  значения 3 ГБ/64 МБ → Vulkan `Failed to enumerate adapters`, dwm 0x889800b0 по кругу.
  Лечение — «Настроить» в программе. С build-40 INF пишет пул с NOCLOBBER (0x00010003).
- Сборщик логов: строки umd.log дедуплицируются по «форме» (цифры→#), спам present пропущен,
  `layout|MISMATCH` включены. Строк `import layout` от build-39 ещё не видели — нужен лог после
  перезагрузки с новым сборщиком.

### Гипотезы на завтра
1. Смотреть `import layout MISMATCH`: если есть — Turnip выбирает свой pitch/tiling (UBWC,
   tile) вместо явного; проверить `TU_DEBUG=noubwc` вместе с `VK_EXT_image_drm_format_modifier`
   linear, align 64/256 в tu_image.
2. Формат/swizzle: BGRA vs RGBA или sRGB у GDI-поверхностей (пёстрые/зелёные пятна = каналы/
   неинициализированная память). Логировать DXGI-формат импортируемых ресурсов.
3. Синхронизация CPU↔GPU: GDI пишет в staging без flush/invalidate кэша (Gunyah, cached
   mapping) → устаревшие данные. Проверить mapping как write-combined/uncached в KMD.
4. Частичные обновления (dirty rects) при present: копируется только часть, остальное мусор.
5. Пул мал/фрагментирован: при 256 МБ стало лучше — проверить 512 МБ.

### 16:34 — первый лог с новым сборщиком (build-39)
- Импортирован только один ресурс: `import layout ok 1024x768: rowPitch=4096`. Мелкие GDI-поверхности
  НЕ идут через импорт → гипотеза про pitch импорта отпадает (патч 0002 безвреден, но не причина).
- Мелкие элементы создаются как STAGING-текстуры (`usage 3, map 3`, напр. 18x18 fmt 87), CPU пишет
  через Map, затем копия на GPU. `tritonResourceMap: 0x887b0001` = WASSTILLDRAWING (норма для DO_NOT_WAIT).
- Главный подозреваемый теперь — гипотеза 3 (кэш CPU / coherency при Map staging) и путь
  CopySubresourceRegion staging→texture (pitch staging-буфера DXVK vs то, что пишет GDI/dwm).
- Ещё: `pfnDeallocateCb failed: 0x80070057` — возможен двойной free; проверить.

## 2026-11-03 — build-42 (uncached CPU-visible 3D) — артефакты остались
- Гипотеза кэша CPU для 3D-аллокаций не подтвердилась (Alloc3d всего 2 за загрузку).
- В логе разово: `wddm submit failed status=0xc00002b6` + `VK_ERROR_DEVICE_LOST`.
- Сборщик: ручная отправка (-Quick) теперь шлёт скриншот `*-shot_*.png.b64` (с перезагрузки).
- Пауза. Текст issue для разработчиков Droid-VM — `docs/ISSUE-droidvm.md` (отправляет пользователь).
