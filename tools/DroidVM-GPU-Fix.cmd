@echo off
rem DroidVM GPU (unofficial build) - Turnip workaround switches. Double-click to run.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
rem Fixes: noubwc = no UBWC texture compression, sysmem = no GMEM tile rendering.
rem Both only disable optimisations (slower, never breaks boot). Run again to see/keep.
set FIX=startup,noubwc,sysmem
setx /M TU_DEBUG %FIX% >nul
echo TU_DEBUG = %FIX%
echo Reboot in 15 s (close this window to cancel)...
timeout /t 15
shutdown /r /t 0
