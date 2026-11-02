@echo off
rem DroidVM GPU (unofficial build) - remove Turnip workaround switches.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
setx /M TU_DEBUG startup >nul
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v TU_WIN_SUBMIT_CPU_WAIT /f >nul 2>&1
echo TU_DEBUG = startup (fixes off)
echo Reboot in 15 s (close this window to cancel)...
timeout /t 15
shutdown /r /t 0
