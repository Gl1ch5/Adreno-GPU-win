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
$L.Add("--- Processes using GPU driver DLLs ---")
foreach ($pn in 'dwm','explorer') {
  Get-Process $pn -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_; try { $p.Modules | Where-Object { $_.ModuleName -match 'virtio|dx11um|dx12um|vulkan|freedreno|dxgi|d3d11|d3d9on12|d3d12' } |
      ForEach-Object { $L.Add("$($p.ProcessName)[$($p.Id)]: $($_.FileName)") } } catch { $L.Add("$pn modules: $_") }
  }
}
$L.Add("--- Errors/warnings, last 30 min (System+Application) ---")
Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2,3; StartTime=(Get-Date).AddMinutes(-30)} -ErrorAction SilentlyContinue |
  Select-Object -First 60 | ForEach-Object { $L.Add("$($_.TimeCreated) [$($_.LogName)/$($_.ProviderName) $($_.Id)] $(($_.Message -replace '\s+',' ').Substring(0, [Math]::Min(300, ($_.Message -replace '\s+',' ').Length)))") }
$L.Add("--- DXVK logs (newest) ---")
Get-ChildItem 'C:\ProgramData\DroidVM-GPU\dxvk' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
  $L.Add("## $($_.Name) $($_.LastWriteTime) $($_.Length) bytes"); Get-Content $_.FullName -Tail 120 | ForEach-Object { $L.Add($_) } }
$L.Add("--- dwm crash dumps ---")
$dmp = Get-ChildItem 'C:\ProgramData\DroidVM-GPU\dumps' -Filter *.dmp -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$dmp | Select-Object -First 5 | ForEach-Object { $L.Add("$($_.Name) $($_.Length)") }
$L.Add("--- dxdiag (display) ---")
try {
  $dx = Join-Path $env:TEMP 'dxdiag.txt'; Remove-Item $dx -ErrorAction SilentlyContinue
  $pr = Start-Process dxdiag -ArgumentList "/t $dx" -PassThru -WindowStyle Hidden; if (-not $pr.WaitForExit(90000)) { $pr.Kill(); $L.Add('dxdiag timeout') }
  $t = Get-Content $dx -ErrorAction SilentlyContinue
  $i = ($t | Select-String -Pattern '^Display Devices' | Select-Object -First 1).LineNumber
  if ($i) { $t[($i-1)..([Math]::Min($t.Count-1, $i+60))] | ForEach-Object { $L.Add($_) } } else { $L.Add('(no dxdiag output)') }
} catch { $L.Add("dxdiag failed: $_") }
$L | Set-Content -Encoding UTF8 $out
Copy-Item $out (Join-Path $dir 'LATEST.txt') -Force
# optional: send to the log server (only in the build downloaded from the server)
if ($upTok -notlike '__UPLOAD*') {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri 'https://grzxk.ru:8877/upload' -Method Post -TimeoutSec 30 `
      -Headers @{ 'X-Token' = $upTok; 'X-Name' = "$env:COMPUTERNAME-boot_$ts.txt" } `
      -ContentType 'text/plain; charset=utf-8' -Body ([IO.File]::ReadAllBytes($out)) | Out-Null
    if ($dmp) { $d = $dmp[0]; Invoke-RestMethod -Uri 'https://grzxk.ru:8877/upload' -Method Post -TimeoutSec 60 `
      -Headers @{ 'X-Token' = $upTok; 'X-Name' = "$env:COMPUTERNAME-boot_$ts.dmp.b64" } `
      -ContentType 'text/plain' -Body ([Convert]::ToBase64String([IO.File]::ReadAllBytes($d.FullName))) | Out-Null
      Remove-Item 'C:\ProgramData\DroidVM-GPU\dumps\*' -Force -ErrorAction SilentlyContinue }
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
$trg.Delay = 'PT120S'
Register-ScheduledTask -TaskName 'DroidVM GPU logs' -Action $act -Trigger $trg -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

# 2b) DXVK log + dwm crash dumps (dwm runs as DWM-n user: folders must be writable)
foreach ($sub in 'dxvk','dumps') { $p = "C:\ProgramData\DroidVM-GPU\$sub"; New-Item $p -ItemType Directory -Force | Out-Null; icacls $p /grant '*S-1-1-0:(OI)(CI)M' | Out-Null }
[Environment]::SetEnvironmentVariable('DXVK_LOG_LEVEL', 'info', 'Machine')
[Environment]::SetEnvironmentVariable('DXVK_LOG_PATH', 'C:\ProgramData\DroidVM-GPU\dxvk', 'Machine')
$wer = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\dwm.exe'
New-Item $wer -Force | Out-Null
Set-ItemProperty $wer -Name DumpFolder -Value 'C:\ProgramData\DroidVM-GPU\dumps' -Type ExpandString
Set-ItemProperty $wer -Name DumpType -Value 1 -Type DWord
Set-ItemProperty $wer -Name DumpCount -Value 3 -Type DWord

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
