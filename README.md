# droidvm-gpu-build

**Неофициальная** автоматическая сборка видеодрайвера VirtIO-GPU для
**Windows 11 ARM64** в виртуальной машине [DroidVM](https://github.com/Droid-VM)
(проверялась под Snapdragon 8 Gen 5 / Adreno 829).

> ⚠️ Это **не** официальный релиз. Драйвер написали **anonymix007** и
> **команда DroidVM**; этот репозиторий только собирает их открытые исходники
> через GitHub Actions и упаковывает в установщик. Ошибки сборки/упаковки —
> на совести этого репозитория, а не авторов драйвера. Не пишите авторам
> баг-репорты по этой сборке.
>
> Распространяется бесплатно, **не для продажи**. Без каких-либо гарантий.

## Статус (2 ноября 2026)

Сборка доведена до работы именно под нашу связку: **DroidVM (dev 3348830) на
Snapdragon 8 Gen 5 / Adreno 829, Windows 11 ARM64**. Тест — в DroidVM на
реальном устройстве.

**Работает (проверено на устройстве):**
- аппаратное ускорение рабочего стола: `dwm.exe` рисует через наш DirectX 11
  драйвер → DXVK → Vulkan (Turnip) → GPU Adreno 829 телефона;
- DirectX 11 / 10 приложения, уровень **D3D 11_1** (dxdiag: 11_1 … 9_1);
- Chrome / Edge на GPU, видео YouTube 4K идёт почти без лагов;
- прозрачность и эффекты Windows 11, Диспетчер задач видит GPU (3D-нагрузка, VRAM);
- касание при разрешении 1920x1080 в DroidVM.

**Известные проблемы:**
- мелкие артефакты в элементах самой Windows (тени окон, часть текста —
  белые прямоугольники); ошибок при этом нет — ищем, какая оптимизация
  Turnip для A8xx рисует неверно (переключатели в программе);
- **DirectX 12 не создаётся** (`vkd3d_create_device failed`) — DX12-игры пока не идут;
- **DirectX 9** — отдельного драйвера нет, такие программы идут программно (WARP);
- **OpenGL нет** — планируется (Mesa Zink: OpenGL поверх нашего Vulkan);
- Vulkan-приложения напрямую ещё не проверялись.

### Что сделано поверх исходников авторов (для DroidVM dev)
- `vulkan_freedreno.dll` слинкован статически (иначе не грузился: libz/libwinpthread);
- драйвер ядра берёт адрес пула памяти GPU из реестра: crosvm в DroidVM dev
  не сообщает его (фича `DROIDVM_BOOT_POOL`), пул задан в INF под ВМ на **3 ГБ**;
- Turnip узнаёт Adreno 829 по ID `0x44030a00`, который отдаёт хост;
- своя `libvirglrenderer.so` для хоста (релизы `host-N`) — исправлена ошибка
  привязки памяти (EINVAL);
- программа **DroidVM GPU** (ниже) и автосбор логов.

## Обязательные настройки DroidVM
- Graphics: Renderer **VirGL**, Graphics API **Native Context**, Host driver **DRM to KGSL**,
  Virtio-GPU → **Enable display device** включено, разрешение **1920x1080**;
- Protected VM: **Pseudo Unprotected**; память ВМ **3 ГБ** (под неё рассчитан адрес пула);
- аварийный выход: выключить Enable display device — Windows загрузится без драйвера.

## Программа DroidVM GPU
`DroidVM-GPU.exe` (релиз `app-latest`): состояние драйвера и GPU, нагрузка,
отправка логов, переключатели исправлений Turnip, установка новых сборок
драйвера. Сама обновляется (проверка каждую минуту) и сообщает о новой сборке
драйвера; драйвер ставится только по кнопке.

## Скачать

Раздел [Releases](../../releases):

| Файл | Что это |
|---|---|
| `DroidVM-GPU-Setup.exe` | установщик: ставит тестовый сертификат и драйвер, предлагает перезагрузку |
| `DroidVM-GPU-Uninstall.exe` | откат: удаляет драйвер, сертификат, выключает TESTSIGNING (если его включил установщик) |
| `DroidVM-GPU-driver.zip` | тот же пакет для ручной установки через `pnputil` |
| `SHA256SUMS.txt` | контрольные суммы |

## Установка

1. **Сделайте клон (копию) диска ВМ.** Драйвер ядра экспериментальный; если
   Windows не загрузится, проще всего вернуться к копии.
2. В DroidVM перед запуском Windows включите резерв Hugepage (~3 ГБ).
3. Внутри Windows запустите `DroidVM-GPU-Setup.exe` от администратора.
   Он:
   - создаёт точку восстановления (если включена защита системы);
   - импортирует сертификат `DroidVM GPU Test (unofficial build)` в
     «Доверенные корневые центры» и «Доверенные издатели» (компьютер);
   - включает режим тестовой подписи `bcdedit /set testsigning on`
     (без него тестово подписанный драйвер ядра не загрузится; при включённом
     Secure Boot это невозможно);
   - ставит драйвер через `pnputil /add-driver ... /install`;
   - предлагает перезагрузку.
4. После перезагрузки в «Диспетчере устройств» должен появиться
   «Qualcomm Adreno 829 (DroidVM, unofficial build)» (до build-37 — «VirtIO GPU 3D controller»).
5. Режим графики DroidVM — **Native Context** (см. настройки выше). Режим
   **Vulkan** (Venus) в этой сборке не поддерживается.

Журналы: `C:\ProgramData\DroidVM-GPU\install.log`, `uninstall.log`.

## Откат

Любой из способов, затем перезагрузка:

- «Параметры → Приложения → Установленные приложения → DroidVM GPU driver → Удалить»;
- `DroidVM-GPU-Uninstall.exe`;
- вручную (PowerShell от администратора):
  ```powershell
  pnputil /enum-drivers   # найдите oemNN.inf с virtio_wddm_rs.inf
  pnputil /delete-driver oemNN.inf /uninstall /force
  bcdedit /set testsigning off
  ```
- если Windows не грузится — восстановите клон диска ВМ (или безопасный режим
  → удалить драйвер).

После удаления Windows вернётся к «Базовому видеоадаптеру (Майкрософт)».

## Что внутри

| Файл в пакете | Исходник |
|---|---|
| `virtio_wddm_rs.sys` — драйвер ядра WDDM (Rust) | [Droid-VM/virtio-drivers-windows-rs](https://github.com/Droid-VM/virtio-drivers-windows-rs/tree/wingpu) |
| `dx11um_virtio.dll` — DirectX 10/11 (DXVK внутри) | [Droid-VM/virtio-d3d11](https://github.com/Droid-VM/virtio-d3d11/tree/wingpu), [Droid-VM/dxvk](https://github.com/Droid-VM/dxvk/tree/wingpu) |
| `dx12um_virtio.dll` — DirectX 12 | [Droid-VM/virtio-d3d12](https://github.com/Droid-VM/virtio-d3d12/tree/wingpu) + [Droid-VM/vkd3d-proton](https://github.com/Droid-VM/vkd3d-proton/tree/wingpu) |
| `vulkan_freedreno.dll` — Vulkan (Turnip) | [Droid-VM/mesa](https://github.com/Droid-VM/mesa/tree/wingpu) |
| `droidvm_vulkan.dll` — загрузчик Vulkan | [KhronosGroup/Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Loader) |

Точные коммиты каждой сборки указаны в описании релиза.

### Отличия от авторской сборки

Авторский скрипт сборки не опубликован, поэтому:

- заголовки и библиотеки WDK берутся из NuGet (`Microsoft.Windows.WDK.ARM64`,
  `Microsoft.Windows.SDK.CPP`, версия в `versions.env`) вместо EWDK; для
  clang генерируется регистронезависимый `-vfsoverlay`;
- в `.cargo/config.toml` драйвера добавляется цель `aarch64-pc-windows-msvc`
  (копия настроек x86_64);
- INF в исходниках только для x64 — здесь свой ARM64 INF (`package/virtio_wddm_rs.inx`);
- сабмодуль dxil-spirv в vkd3d-proton указывает на неопубликованный коммит:
  используется ближайший публичный + патч `patches/dxil-spirv`;
- **Venus (`vulkan_virtio.dll`) не включён**: в публичной ветке mesa у Venus
  нет Windows-бэкенда (vtest исключён, WDDM-рендерера нет), он не линкуется;
- драйвер подписан **тестовым** сертификатом, созданным при сборке
  (или из секрета `SIGN_PFX_BASE64`/`SIGN_PFX_PASSWORD`).

## Сборка

Всё делает [`.github/workflows/build.yml`](.github/workflows/build.yml):
Linux (llvm-mingw, Rust nightly, meson) собирает бинарники, Windows-раннер
делает каталог (Inf2Cat), подписывает (signtool) и собирает установщик
(Inno Setup). Локально на Linux:

```bash
scripts/setup-winsdk.sh winsdk
scripts/fetch-sources.sh
ARCH=arm64 scripts/build.sh      # результат в out/arm64
```

План: артефакты A8xx → DirectX 12 → OpenGL (Zink) → ARM64EC (x64-игры) → x86 (32-битные игры).

## Лицензия

Исходный код драйвера — © anonymix007 и команда DroidVM, **GNU AGPL-3.0**
(см. [LICENSE](LICENSE) и README исходных репозиториев). Скрипты этого
репозитория распространяются на тех же условиях. Сторонние компоненты (DXVK,
vkd3d-proton, Mesa, Vulkan-Loader) — под своими лицензиями. Продажа сборки
запрещена.
