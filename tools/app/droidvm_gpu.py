"""DroidVM GPU control panel (unofficial). Local web UI on 127.0.0.1.

Windows only. Runs elevated (PyInstaller --uac-admin). No third-party deps.
"""
import json, os, subprocess, sys, threading, time, urllib.request, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_VERSION = "1.1"
REPO = "Gl1ch5/Adreno-GPU-win"
TASK = "DroidVM GPU logs"
TOOL_DIR = r"C:\ProgramData\DroidVM-GPU"
LOG_DIR = os.path.join(os.path.expanduser("~"), "Downloads", "DroidVM-GPU-Logs")
FIXES = {"noubwc": "Без сжатия UBWC", "sysmem": "Без тайловой памяти (GMEM)",
         "flushall": "Сброс кэшей после каждой отрисовки", "syncdraw": "Синхронизация после отрисовки"}
NOWIN = 0x08000000  # CREATE_NO_WINDOW
last_ping = time.time()


def res(name):
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, name)


def ps(script, timeout=60):
    r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                       capture_output=True, text=True, timeout=timeout, creationflags=NOWIN,
                       encoding="utf-8", errors="replace")
    return r.stdout.strip()


STATUS_PS = r"""
$ErrorActionPreference='SilentlyContinue'
$d = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like '*VirtIO GPU*' } | Select-Object -First 1
$p = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -like '*VirtIO GPU*' } | Select-Object -First 1
$v = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like '*VirtIO GPU*' } | Select-Object -First 1
$mods = @(); $dwm = Get-Process dwm | Select-Object -First 1
if ($dwm) { $mods = @($dwm.Modules | Where-Object { $_.ModuleName -match 'dx11um|vulkan_freedreno|droidvm_vulkan|d3d10warp' } | ForEach-Object { $_.ModuleName }) }
$bf = Get-ChildItem "$env:USERPROFILE\Downloads\DroidVM-GPU-Logs\boot_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$up = if ($bf) { (Select-String -Path $bf.FullName -Pattern '^upload:' | Select-Object -Last 1).Line } else { $null }
$task = Get-ScheduledTask -TaskName 'DroidVM GPU logs'
[pscustomobject]@{
  driver = $d.DriverVersion; status = "$($p.Status)"; problem = (Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName DEVPKEY_Device_ProblemCode).Data
  device = $p.FriendlyName
  mode = if ($v) { "$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution) @ $($v.CurrentRefreshRate) Hz" } else { $null }
  dwm = $mods; tu = [Environment]::GetEnvironmentVariable('TU_DEBUG','Machine')
  cpuwait = [Environment]::GetEnvironmentVariable('TU_WIN_SUBMIT_CPU_WAIT','Machine')
  lastlog = if ($bf) { $bf.LastWriteTime.ToString('dd.MM HH:mm:ss') } else { $null }; upload = $up
  task = [bool]$task; taskstate = "$($task.State)"
  testsign = [bool](bcdedit | Select-String -Pattern 'testsigning\s+Yes')
  tdr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers').TdrDelay
} | ConvertTo-Json -Compress
"""


def latest_build():
    req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases?per_page=100",
                                 headers={"User-Agent": "droidvm-gpu-app"})
    rel = json.load(urllib.request.urlopen(req, timeout=20))
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
        out = subprocess.run(["schtasks", "/Run", "/TN", TASK], capture_output=True, text=True,
                             creationflags=NOWIN, errors="replace")
        return {"ok": out.returncode == 0, "msg": "Сбор логов запущен, займёт 1–2 минуты" if out.returncode == 0
                else "Сборщик не установлен: запустите батник сборщика один раз"}
    if name == "openlogs":
        os.makedirs(LOG_DIR, exist_ok=True); os.startfile(LOG_DIR); return {"ok": True, "msg": "Открыто"}
    if name == "fix":
        return {"ok": True, "msg": "TU_DEBUG = " + set_fix(arg or []) + ". Нужна перезагрузка"}
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
        b = latest_build()
        exe = os.path.join(TOOL_DIR, f"Setup-diag-{b['tag']}.exe"); os.makedirs(TOOL_DIR, exist_ok=True)
        urllib.request.urlretrieve(b["url"], exe)
        subprocess.Popen([exe])  # visible installer: user sees progress and result
        return {"ok": True, "msg": f"Запущен установщик {b['tag']}"}
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
            try:
                st = json.loads(ps(STATUS_PS) or "{}")
            except Exception as e:
                st = {"error": str(e)}
            st["app"] = APP_VERSION; st["fixes"] = FIXES
            return self._send(200, json.dumps(st, ensure_ascii=False).encode(), "application/json")
        if self.path == "/api/ping":
            return self._send(200, b"{}", "application/json")
        self._send(404, b"not found", "text/plain")

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        req = json.loads(self.rfile.read(n) or b"{}")
        try:
            out = action(req.get("action"), req.get("arg"))
        except Exception as e:
            out = {"ok": False, "msg": f"Ошибка: {e}"}
        self._send(200, json.dumps(out, ensure_ascii=False).encode(), "application/json")

    def log_message(self, *a):
        pass


def watchdog():
    while True:
        time.sleep(15)
        if time.time() - last_ping > 90:  # UI window closed
            os._exit(0)


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    url = f"http://127.0.0.1:{srv.server_address[1]}/"
    threading.Thread(target=watchdog, daemon=True).start()
    edge = [p for p in (r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe") if os.path.exists(p)]
    if edge:
        subprocess.Popen([edge[0], f"--app={url}", "--window-size=1100,760"])
    else:
        webbrowser.open(url)
    srv.serve_forever()


if __name__ == "__main__":
    main()
