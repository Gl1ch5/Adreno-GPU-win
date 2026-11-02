@echo off
rem DroidVM GPU (unofficial build) - Turnip workaround switches. Double-click to run.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
rem Fixes: noubwc = no UBWC texture compression, sysmem = no GMEM tile rendering.
rem flushall,syncdraw + TU_WIN_SUBMIT_CPU_WAIT = full sync/flush (test for cache/sync bugs).
rem All only disable optimisations (slower, never breaks boot).
set FIX=startup,noubwc,sysmem,flushall,syncdraw
setx /M TU_DEBUG %FIX% >nul
setx /M TU_WIN_SUBMIT_CPU_WAIT 1 >nul
echo TU_DEBUG = %FIX%
echo TU_WIN_SUBMIT_CPU_WAIT = 1
echo Reboot in 15 s (close this window to cancel)...
timeout /t 15
shutdown /r /t 0
