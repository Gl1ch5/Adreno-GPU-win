"""DroidVM GPU control panel (unofficial). Local web UI on 127.0.0.1.

Windows only. Runs elevated (PyInstaller --uac-admin). No third-party deps.
"""
import json, os, subprocess, sys, threading, time, urllib.request, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_VERSION = "1.9"
REPO = "Gl1ch5/Adreno-GPU-win"
TASK = "DroidVM GPU logs"
TOOL_DIR = r"C:\ProgramData\DroidVM-GPU"
LOG_DIR = os.path.join(os.path.expanduser("~"), "Downloads", "DroidVM-GPU-Logs")
FIXES = {"noubwc": "Без сжатия UBWC", "sysmem": "Без тайловой памяти (GMEM)",
         "nocb": "Без параллельного биннинга (A8xx)", "nolrz": "Без LRZ", "nolrzfc": "Без LRZ fast clear",
         "nobinmerging": "Без склейки тайлов", "noconcurrentresolves": "Без параллельных resolve",
         "noconcurrentunresolves": "Без параллельных unresolve", "nomultipos": "Без multipos",
         "3d_load": "Загрузка тайлов через 3D",
         "flushall": "Сброс кэшей после каждой отрисовки", "syncdraw": "Синхронизация после отрисовки"}
NOWIN = 0x08000000  # CREATE_NO_WINDOW
last_ping = time.time()
JOB = {"name": None, "pct": None, "msg": ""}
INSTALL_EXE = os.path.join(TOOL_DIR, "DroidVM-GPU.exe")
AGENT_TASK = "DroidVM GPU agent"
APP_URL = f"https://github.com/{REPO}/releases/download/app-latest/"
CHECK_EVERY = 60  # seconds; app: version.txt (no API limit), driver: server cache


def res(name):
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, name)


def ps(script, timeout=60):
    r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                       capture_output=True, text=True, timeout=timeout, creationflags=NOWIN,
                       encoding="utf-8", errors="replace")
    return r.stdout.strip()


# slow, rarely changing data: refreshed in the background, never on the request path
STATIC_PS = r"""
$ErrorActionPreference='SilentlyContinue'
$pid_ = 'PCI\VEN_1AF4&DEV_1050*'
$p = Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like $pid_ } | Select-Object -First 1
$drv = if ($p) { (Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName DEVPKEY_Device_DriverVersion).Data }
$v = Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like $pid_ } | Select-Object -First 1
$mods = @(); $dwm = Get-Process dwm | Select-Object -First 1
if ($dwm) { $mods = @($dwm.Modules | Where-Object { $_.ModuleName -match 'dx11um|vulkan_freedreno|droidvm_vulkan|d3d10warp' } | ForEach-Object { $_.ModuleName }) }
$bf = Get-ChildItem "$env:USERPROFILE\Downloads\DroidVM-GPU-Logs\boot_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$up = if ($bf) { (Select-String -Path $bf.FullName -Pattern '^upload:' | Select-Object -Last 1).Line } else { $null }
$task = Get-ScheduledTask -TaskName 'DroidVM GPU logs'
$gpu = $null; $mesa = $null; $fl = $null; $tuact = $null
$u = 'C:\ProgramData\DroidVM-GPU\dxvk\umd.log'
if (Test-Path $u) {
  $fs = New-Object IO.FileStream($u, 'Open', 'Read', 'ReadWrite,Delete'); $len = $fs.Length
  $fs.Seek([Math]::Max(0, $len - 2MB), 'Begin') | Out-Null; $t = (New-Object IO.StreamReader($fs)).ReadToEnd(); $fs.Close()
  $m = [regex]::Matches($t, 'Found device: ([^\(\r\n]+)\(') | Select-Object -Last 1; if ($m) { $gpu = $m.Groups[1].Value.Trim() }
  $m = [regex]::Matches($t, 'Driver\s*:\s*([^\r\n]+)') | Select-Object -Last 1; if ($m) { $mesa = $m.Groups[1].Value.Trim() }
  $m = [regex]::Matches($t, 'Using feature level (\S+)') | Select-Object -Last 1; if ($m) { $fl = $m.Groups[1].Value -replace 'D3D_FEATURE_LEVEL_','' -replace '_','.' }
}
$os = Get-CimInstance Win32_OperatingSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$env_ = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
[pscustomobject]@{
  driver = $drv; status = "$($p.Status)"; problem = (Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName DEVPKEY_Device_ProblemCode).Data
  device = $p.FriendlyName; gpu = $gpu; mesa = $mesa; fl = $fl
  mode = if ($v) { "$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution) @ $($v.CurrentRefreshRate) Hz" } else { $null }
  dwm = $mods; tu = (Get-ItemProperty $env_).TU_DEBUG; verbose = (Get-ItemProperty $env_).VIRTIO_WDDM_VERBOSE; $pk = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VirtioGpu\Parameters'; poolbase = if ($pk.PoolBaseLow -ne $null) { '0x{0:x}' -f ([uint64]$pk.PoolBaseHigh * 4294967296 + [uint32]$pk.PoolBaseLow) } else { $null }; cpuwait = (Get-ItemProperty $env_).TU_WIN_SUBMIT_CPU_WAIT
  lastlog = if ($bf) { $bf.LastWriteTime.ToString('dd.MM HH:mm:ss') } else { $null }; upload = $up
  task = [bool]$task
  testsign = [bool](bcdedit /enum '{current}' | Select-String -Pattern 'testsigning\s+Yes')
  tdr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers').TdrDelay
  win = "$($os.Caption -replace 'Microsoft ','') $($os.Version)"; cpu = $cpu.Name; cores = $cpu.NumberOfLogicalProcessors
  ramGB = [math]::Round($os.TotalVisibleMemorySize/1MB,1); freeGB = [math]::Round($os.FreePhysicalMemory/1MB,1)
  boot = $os.LastBootUpTime.ToString('o')
} | ConvertTo-Json -Compress
"""

# fast, live counters
LIVE_PS = r"""
$ErrorActionPreference='SilentlyContinue'
$c = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage','\GPU Engine(*engtype_Copy)\Utilization Percentage','\GPU Adapter Memory(*)\Dedicated Usage','\GPU Adapter Memory(*)\Shared Usage'
$r = @{e3d=0.0; ecopy=0.0; ded=0.0; sha=0.0}
$c.CounterSamples | ForEach-Object {
  if ($_.Path -match 'engtype_3d') { $r.e3d += $_.CookedValue } elseif ($_.Path -match 'engtype_copy') { $r.ecopy += $_.CookedValue }
  elseif ($_.Path -match 'dedicated usage') { $r.ded += $_.CookedValue } elseif ($_.Path -match 'shared usage') { $r.sha += $_.CookedValue } }
[pscustomobject]@{ eng3d=[math]::Round($r.e3d,1); engcopy=[math]::Round($r.ecopy,1); vramMB=[math]::Round($r.ded/1MB); sharedMB=[math]::Round($r.sha/1MB) } | ConvertTo-Json -Compress
"""

# env of this process = what processes started after the last boot actually use
ACTIVE_TU = os.environ.get("TU_DEBUG", "")
CACHE = {"static": {}, "live": {}, "static_t": 0.0}
REFRESH = threading.Event()


def refresher():
    while True:
        try:
            CACHE["static"] = json.loads(ps(STATIC_PS, timeout=90) or "{}"); CACHE["static_t"] = time.time()
        except Exception as e:
            CACHE["static"]["error"] = str(e)
        REFRESH.wait(30); REFRESH.clear()


def live():
    while True:
        try:
            CACHE["live"] = json.loads(ps(LIVE_PS, timeout=30) or "{}")
        except Exception:
            pass
        time.sleep(4)



def clean_env():
    """Environment for launching our own exe: without the PyInstaller vars the child
    would reuse this process's _MEI temp dir ("Failed to remove temporary directory")."""
    env = {k: v for k, v in os.environ.items() if not k.upper().startswith(("_PYI", "_MEI"))}
    env["PYINSTALLER_RESET_ENVIRONMENT"] = "1"
    return env


def launch_self(*args):
    subprocess.Popen([INSTALL_EXE, *args], env=clean_env(), cwd=TOOL_DIR, creationflags=NOWIN)


def app_build():
    try:
        return int(open(res("build.txt")).read().strip())
    except Exception:
        return 0


def http_get(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "droidvm-gpu-app"})
    return urllib.request.urlopen(req, timeout=timeout).read()


def remote_app_build():
    return int(http_get(APP_URL + "version.txt").decode().split()[0])


def installed_driver_build():
    v = ps("(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like '*VirtIO GPU*' } | Select-Object -First 1).DriverVersion")
    try:
        return int(v.strip().split(".")[-1])
    except Exception:
        return 0


def install_self():
    """Copy the running exe to ProgramData and register the logon agent."""
    if not getattr(sys, "frozen", False):
        return
    os.makedirs(TOOL_DIR, exist_ok=True)
    me = os.path.abspath(sys.executable)
    if os.path.normcase(me) != os.path.normcase(INSTALL_EXE):
        try:
            if os.path.exists(INSTALL_EXE):
                os.replace(INSTALL_EXE, INSTALL_EXE + ".old")
            import shutil
            shutil.copy2(me, INSTALL_EXE)
        except Exception:
            pass
    subprocess.run(["schtasks", "/Create", "/F", "/TN", AGENT_TASK, "/SC", "ONLOGON", "/RL", "HIGHEST",
                    "/TR", f'"{INSTALL_EXE}" --agent'], capture_output=True, creationflags=NOWIN)
    # start the agent now if it is not running yet
    subprocess.run(["schtasks", "/Run", "/TN", AGENT_TASK], capture_output=True, creationflags=NOWIN)


def self_update():
    """Download a newer app build and swap the exe. Returns True if updated."""
    try:
        if remote_app_build() <= app_build():
            return False
        data = http_get(APP_URL + "DroidVM-GPU.exe", timeout=300)
        if len(data) < 1_000_000:
            return False
        new = INSTALL_EXE + ".new"
        open(new, "wb").write(data)
        if os.path.exists(INSTALL_EXE):
            try:
                os.remove(INSTALL_EXE + ".old")
            except OSError:
                pass
            os.replace(INSTALL_EXE, INSTALL_EXE + ".old")  # running exe can be renamed
        os.replace(new, INSTALL_EXE)
        return True
    except Exception:
        return False


def agent():
    """Background agent: keeps the app current, opens the UI on a new driver build."""
    for f in (INSTALL_EXE + ".old", INSTALL_EXE + ".new"):
        try:
            os.remove(f)
        except OSError:
            pass
    seen = os.path.join(TOOL_DIR, "agent-seen-driver.txt")
    while True:
        if self_update():
            launch_self("--agent")
            os._exit(0)
        try:
            b = latest_build()
            prev = open(seen).read().strip() if os.path.exists(seen) else ""
            if b["n"] > installed_driver_build() and prev != b["tag"]:
                open(seen, "w").write(b["tag"])
                launch_self()
        except Exception:
            pass
        time.sleep(CHECK_EVERY)


def latest_build():
    # server caches the GitHub API answer (GitHub allows 60 unauthenticated calls/hour)
    try:
        b = json.loads(http_get("https://grzxk.ru:8877/latest", timeout=15))
        if b.get("tag"):
            return b
    except Exception:
        pass
    rel = json.loads(http_get(f"https://api.github.com/repos/{REPO}/releases?per_page=100", timeout=20))
    rel = [r for r in rel if r["tag_name"].startswith("build-")]
    rel.sort(key=lambda r: r["created_at"], reverse=True)
    r = rel[0]
    url = next(a["browser_download_url"] for a in r["assets"] if a["name"] == "DroidVM-GPU-Setup-diag.exe")
    return {"tag": r["tag_name"], "n": int(r["tag_name"].split("-")[1]), "url": url, "date": r["created_at"][:10]}


def set_fix(flags):
    val = ",".join(["startup"] + [f for f in flags if f in FIXES])
    ps(f"[Environment]::SetEnvironmentVariable('TU_DEBUG','{val}','Machine')")
    return val


def action(name, arg):
    if name == "sendlogs":
        collect = os.path.join(TOOL_DIR, "collect.ps1")
        if not os.path.exists(collect):
            return {"ok": False, "msg": "Сборщик не установлен: запустите батник сборщика один раз"}
        def run():
            JOB.update(name="sendlogs", pct=None, msg="Собираю и отправляю логи…")
            try:
                subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", collect, "-Quick"],
                               capture_output=True, timeout=240, creationflags=NOWIN)
                JOB.update(msg="Логи отправлены")
            except Exception as e:
                JOB.update(msg=f"Ошибка: {e}")
            time.sleep(2); JOB.update(name=None)
        threading.Thread(target=run, daemon=True).start()
        return {"ok": True, "msg": "Сбор логов запущен"}
    if name == "openlogs":
        os.makedirs(LOG_DIR, exist_ok=True); os.startfile(LOG_DIR); return {"ok": True, "msg": "Открыто"}
    if name == "fix":
        return {"ok": True, "msg": "Сохранено: " + set_fix(arg or []) + ". Применится после перезагрузки"}
    if name == "vmmem":
        # DroidVM places the drm2kgsl pool in the last 64 MiB of guest RAM:
        # base = 0x80000000 + RAM - 64 MiB (3 GiB -> 0x13c000000, matches the host log)
        gb = int(arg)
        if gb not in (3, 4, 5, 6, 8, 10, 12):
            return {"ok": False, "msg": "Неверный объём"}
        base = 0x80000000 + gb * (1 << 30) - (64 << 20)
        key = r"HKLM:\SYSTEM\CurrentControlSet\Services\VirtioGpu\Parameters"
        ps(f"New-Item '{key}' -Force | Out-Null; Set-ItemProperty '{key}' PoolBaseLow {base & 0xffffffff} -Type DWord; "
           f"Set-ItemProperty '{key}' PoolBaseHigh {base >> 32} -Type DWord; Set-ItemProperty '{key}' PoolSizeMiB 64 -Type DWord")
        return {"ok": True, "msg": f"Пул GPU настроен на ВМ {gb} ГБ (0x{base:x}). Выключите ВМ, поставьте в DroidVM память {gb} ГБ и запустите"}
    if name == "verbose":
        ps("[Environment]::SetEnvironmentVariable('VIRTIO_WDDM_VERBOSE'," + ("'1'" if arg else "$null") + ",'Machine')")
        return {"ok": True, "msg": "Подробный лог " + ("включён" if arg else "выключен") + ". Нужна перезагрузка"}
    if name == "cpuwait":
        v = "1" if arg else ""
        ps(f"[Environment]::SetEnvironmentVariable('TU_WIN_SUBMIT_CPU_WAIT',{('$null' if not v else repr(v))},'Machine')")
        return {"ok": True, "msg": "Сохранено. Нужна перезагрузка"}
    if name == "tdr":
        key = r"HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        env = r"HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        if arg:
            ps(f"Set-ItemProperty '{key}' TdrDelay 10 -Type DWord; Set-ItemProperty '{key}' TdrDdiDelay 20 -Type DWord; "
               "[Environment]::SetEnvironmentVariable('VDRM_WDDM_VIRTUAL_TIMEOUT_MS','20000','Machine')")
        else:
            ps(f"Remove-ItemProperty '{key}' TdrDelay,TdrDdiDelay -ErrorAction SilentlyContinue; "
               f"Remove-ItemProperty '{env}' VDRM_WDDM_VIRTUAL_TIMEOUT_MS -ErrorAction SilentlyContinue")
        return {"ok": True, "msg": "Таймауты " + ("увеличены" if arg else "по умолчанию") + ". Нужна перезагрузка"}
    if name == "checkupdate":
        return {"ok": True, **latest_build()}
    if name == "update":
        def run():
            try:
                b = latest_build()
                exe = os.path.join(TOOL_DIR, f"Setup-diag-{b['tag']}.exe"); os.makedirs(TOOL_DIR, exist_ok=True)
                JOB.update(name="update", pct=0, msg=f"Скачиваю {b['tag']}…")
                req = urllib.request.Request(b["url"], headers={"User-Agent": "droidvm-gpu-app"})
                with urllib.request.urlopen(req, timeout=60) as r, open(exe, "wb") as f:
                    total = int(r.headers.get("Content-Length") or 0); got = 0
                    while chunk := r.read(256 * 1024):
                        f.write(chunk); got += len(chunk)
                        if total: JOB["pct"] = int(got * 100 / total)
                JOB.update(pct=100, msg=f"Запускаю установщик {b['tag']}")
                subprocess.Popen([exe])
                time.sleep(3)
            except Exception as e:
                JOB.update(msg=f"Ошибка: {e}"); time.sleep(4)
            JOB.update(name=None, pct=None)
        threading.Thread(target=run, daemon=True).start()
        return {"ok": True, "msg": "Скачивание началось"}
    if name == "reboot":
        subprocess.Popen(["shutdown", "/r", "/t", "5"], creationflags=NOWIN); return {"ok": True, "msg": "Перезагрузка через 5 с"}
    if name == "quit":
        threading.Timer(0.5, lambda: os._exit(0)).start(); return {"ok": True, "msg": "bye"}
    return {"ok": False, "msg": "unknown action"}


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype):
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        global last_ping
        last_ping = time.time()
        if self.path in ("/", "/index.html"):
            return self._send(200, open(res("ui.html"), "rb").read(), "text/html; charset=utf-8")
        if self.path == "/api/status":
            st = dict(CACHE["static"]); st.update(CACHE["live"])
            st["loaded"] = CACHE["static_t"] > 0
            st["app"] = APP_VERSION; st["appbuild"] = app_build(); st["fixes"] = FIXES
            st["tuactive"] = ACTIVE_TU
            st["agent"] = AGENT_OK[0]
            return self._send(200, json.dumps(st, ensure_ascii=False).encode(), "application/json")
        if self.path == "/api/job":
            return self._send(200, json.dumps(JOB, ensure_ascii=False).encode(), "application/json")
        if self.path == "/api/ping":
            return self._send(200, b"{}", "application/json")
        self._send(404, b"not found", "text/plain")

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        req = json.loads(self.rfile.read(n) or b"{}")
        try:
            out = action(req.get("action"), req.get("arg"))
            REFRESH.set()
        except Exception as e:
            out = {"ok": False, "msg": f"Ошибка: {e}"}
        self._send(200, json.dumps(out, ensure_ascii=False).encode(), "application/json")

    def log_message(self, *a):
        pass


AGENT_OK = [False]


def check_agent():
    AGENT_OK[0] = subprocess.run(["schtasks", "/Query", "/TN", AGENT_TASK], capture_output=True,
                                 creationflags=NOWIN).returncode == 0


def watchdog():
    while True:
        time.sleep(15)
        if time.time() - last_ping > 90:  # UI window closed
            os._exit(0)


def main():
    if "--agent" in sys.argv:
        return agent()
    threading.Thread(target=lambda: (install_self(), check_agent()), daemon=True).start()
    threading.Thread(target=refresher, daemon=True).start()
    threading.Thread(target=live, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    url = f"http://127.0.0.1:{srv.server_address[1]}/"
    threading.Thread(target=watchdog, daemon=True).start()
    edge = [p for p in (r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe") if os.path.exists(p)]
    if edge:
        subprocess.Popen([edge[0], f"--app={url}", "--window-size=1100,760"], env=clean_env())
    else:
        webbrowser.open(url)
    srv.serve_forever()


if __name__ == "__main__":
    main()
