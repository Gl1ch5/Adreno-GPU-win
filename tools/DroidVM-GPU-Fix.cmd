@echo off
rem DroidVM GPU (unofficial build) - workaround switches. Double-click to run.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
rem Longer GPU timeouts: Windows TDR (2 s default) resets the GPU while the
rem host is still working -> DEVICE_REMOVED (0xc00002b6) and broken windows.
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /t REG_DWORD /d 10 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDdiDelay /t REG_DWORD /d 20 /f >nul
setx /M VDRM_WDDM_VIRTUAL_TIMEOUT_MS 20000 >nul
rem previous experiments did not help: back to defaults
setx /M TU_DEBUG startup >nul
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v TU_WIN_SUBMIT_CPU_WAIT /f >nul 2>&1
echo TdrDelay=10 s, TdrDdiDelay=20 s, VDRM_WDDM_VIRTUAL_TIMEOUT_MS=20000, TU_DEBUG=startup
echo Reboot in 15 s (close this window to cancel)...
timeout /t 15
shutdown /r /t 0
