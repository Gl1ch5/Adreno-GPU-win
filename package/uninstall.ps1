# DroidVM GPU driver (unofficial build) - rollback, run elevated.
# Removes the driver package (Windows falls back to Microsoft Basic Display
# Adapter), the test certificate and, if we enabled it, TESTSIGNING.
$ErrorActionPreference = 'Continue'
$state = Join-Path $env:ProgramData 'DroidVM-GPU'
New-Item -ItemType Directory -Force $state | Out-Null
Start-Transcript -Path (Join-Path $state 'uninstall.log') -Append | Out-Null

$drivers = Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -like '*\virtio_wddm_rs.inf' }
foreach ($d in $drivers) {
    Write-Host "Removing $($d.Driver) ($($d.OriginalFileName))"
    pnputil /delete-driver $d.Driver /uninstall /force | Write-Host
}
if (-not $drivers) { Write-Host 'Driver package not found (already removed?)' }

foreach ($store in 'Root', 'TrustedPublisher') {
    Get-ChildItem "Cert:\LocalMachine\$store" | Where-Object { $_.Subject -eq 'CN=DroidVM GPU Test (unofficial build)' } |
        ForEach-Object { Write-Host "Removing certificate $($_.Thumbprint) from $store"; Remove-Item $_.PSPath }
}

$flag = Join-Path $state 'testsigning-enabled-by-us'
if (Test-Path $flag) {
    bcdedit /set testsigning off | Write-Host
    Remove-Item $flag
}
Write-Host 'Rollback finished. Reboot is required.'
Stop-Transcript | Out-Null
