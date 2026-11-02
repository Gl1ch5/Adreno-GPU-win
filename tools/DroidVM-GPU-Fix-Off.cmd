@echo off
rem DroidVM GPU (unofficial build) - remove workaround switches.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDdiDelay /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v VDRM_WDDM_VIRTUAL_TIMEOUT_MS /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v TU_WIN_SUBMIT_CPU_WAIT /f >nul 2>&1
setx /M TU_DEBUG startup >nul
echo All workarounds removed.
echo Reboot in 15 s (close this window to cancel)...
timeout /t 15
shutdown /r /t 0
