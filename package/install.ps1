# DroidVM GPU driver (unofficial build) - install helper, run elevated.
param([string]$Dir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:ProgramData 'DroidVM-GPU\install.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Append | Out-Null
try {
    try { Checkpoint-Computer -Description 'Before DroidVM GPU driver' -RestorePointType DEVICE_DRIVER_INSTALL } catch { Write-Host "Restore point skipped: $_" }

    $cer = Join-Path $Dir 'DroidVM-GPU-Test.cer'
    foreach ($store in 'Root', 'TrustedPublisher') {
        Import-Certificate -FilePath $cer -CertStoreLocation "Cert:\LocalMachine\$store" | Out-Null
        Write-Host "Certificate imported into LocalMachine\$store"
    }

    # A test-signed kernel driver only loads with TESTSIGNING enabled.
    $bcd = (bcdedit /enum '{current}') -join "`n"
    if ($bcd -notmatch 'testsigning\s+Yes') {
        bcdedit /set testsigning on | Write-Host
        if ($LASTEXITCODE -ne 0) { throw 'bcdedit /set testsigning on failed (Secure Boot enabled?)' }
        Set-Content (Join-Path (Split-Path $log) 'testsigning-enabled-by-us') '1'
    }

    $inf = Join-Path $Dir 'driver\virtio_wddm_rs.inf'
    pnputil /add-driver "$inf" /install | Write-Host
    # 0 = ok, 3010 = ok, reboot required; 259 = no matching device (still staged)
    if ($LASTEXITCODE -notin 0, 3010, 259) { throw "pnputil failed with code $LASTEXITCODE" }
    Write-Host 'Done. Reboot is required.'
} finally { Stop-Transcript | Out-Null }
