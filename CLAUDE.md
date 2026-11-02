# Заметки для Claude

Сначала прочитай `docs/STATUS.md` — состояние, результаты тестов на устройстве,
обходные пути сборки, устройство сервера логов. Общие правила проекта — в `AGENTS.md`.

## Как работать с пользователем
- Отвечать по-русски, коротко. Пользователь работает с телефона, без мыши.
- Команды для Windows — одной строкой для **PowerShell** (не cmd: `&` не работает).
  По возможности без кавычек: Telegram превращает их в «ёлочки».
- Не писать «работает», пока не подтверждено на устройстве.
- Перед установкой драйвера напоминать про клон диска ВМ.
- Не создавать PR/issue в чужих репозиториях (Droid-VM и т.п.); можно дать текст,
  пользователь отправит сам.

## Логи с ВМ — без участия пользователя
- ВМ сама шлёт лог через ~90 с после каждой загрузки на сервер (MCP "Server").
- Читать: MCP `run_root`: `ls -t /var/lib/droidvm-logs | head` и `cat` нужного файла.
- Лог DroidVM (хостовой, crosvm) сервер НЕ видит — его пользователь присылает сам
  (нужны строки `ERROR`, `capset`, `ResourceAttachBacking`, `vulkan.adreno.so`).
- Аварийный выход для пользователя: DroidVM → Graphics → Virtio-GPU →
  Enable display device = off (Windows грузится через SimpleFB).
- Токен сервера лежит только на сервере (`/opt/droidvm-logs/token`), не коммитить.

## Сборщик логов (tools/DroidVM-GPU-Logs.cmd)
- Ссылка для ВМ: `https://grzxk.ru:8877/setup/<token>` (токен только на сервере).
- При каждой загрузке задача качает свежий скрипт с сервера и выполняет его. Обновить
  сборщик = положить файл в `/opt/droidvm-logs/DroidVM-GPU-Logs.cmd` (брать raw по хэшу
  коммита: raw по ветке кэшируется).
- Драйвер сам НЕ ставится (пользователь попросил ставить вручную). Батник в конце
  показывает версию драйвера (`20.15.1.N` = build-N) и результат отправки.
- Включает: `VIRTIO_WDDM_LOG_FILE` (лог UMD), `MESA_LOG_FILE`, `TU_DEBUG=startup`,
  `MESA_LOG_LEVEL=debug`, `VDRM_WDDM_DEBUG=1`, WER-дампы dwm (`*.dmp.b64` на сервере).
  Новые переменные действуют со следующей загрузки.
- Загрузки без дисплея (BasicDisplay) содержат старые строки mesa/umd — смотреть лог
  загрузки с включённым Enable display device.

## Настройки DroidVM для теста (обязательно)
- Graphics: Renderer VirGL, Graphics API **Native Context**, Host driver DRM to KGSL,
  Enable display device = on, Protected VM = Pseudo Unprotected.
- Память ~3 GiB (в логе хоста `3002 MB`, пул `0x13c000000..0x140000000`): адрес пула
  в INF рассчитан на это. В режиме Vulkan Windows видит только capset venus.
- На хосте стоит своя libvirglrenderer (host-3), бэкап `.orig` рядом.

## Батники исправлений
- `https://grzxk.ru:8877/fix` → `tools/DroidVM-GPU-Fix.cmd`: ставит `TU_DEBUG` (сейчас
  `startup,noubwc,sysmem`) и перезагружает. `/fixoff` → `DroidVM-GPU-Fix-Off.cmd`
  (`TU_DEBUG=startup`). На сервере файлы в `/opt/droidvm-logs/` (CRLF), маршруты в server.py.
- Сборщик логов `TU_DEBUG` не перезаписывает, если он уже задан.

## Программа DroidVM GPU (tools/app)
- `https://grzxk.ru:8877/app` → релиз `app-latest` (`DroidVM-GPU.exe` + `version.txt` = run_number).
  Python stdlib + PyInstaller (`--uac-admin`), UI — `ui.html` в Edge `--app`.
- Первый запуск копирует себя в `C:\ProgramData\DroidVM-GPU\DroidVM-GPU.exe` и регистрирует
  задачу «DroidVM GPU agent» (ONLOGON, HIGHEST, `--agent`). Агент каждую минуту обновляет exe
  (переименование .old/.new) и открывает окно, если вышла новая сборка драйвера.
  Драйвер сам не ставит — пользователь жмёт «Установить» (видимый установщик).
- Батники `/fix`, `/fixoff` — запасной вариант; основное — переключатели в программе.
- Сервер: `/latest` — кэш (90 с) последнего build-N из GitHub API для агента.
