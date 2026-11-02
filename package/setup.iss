; DroidVM GPU driver - unofficial build installer (Inno Setup 6)
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
[Setup]
AppId={{6B0D1E52-4C1B-4E0A-9C3D-D401D0D0A829}
AppName=DroidVM GPU driver (unofficial build)
AppVersion={#AppVersion}
AppPublisher=anonymix007 / DroidVM team (unofficial build)
DefaultDirName={commonpf}\DroidVM-GPU
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
PrivilegesRequired=admin
OutputBaseFilename=DroidVM-GPU-Setup
OutputDir=.
Compression=lzma2
SolidCompression=yes
AlwaysRestart=yes
LicenseFile=LICENSE.txt
InfoBeforeFile=README-install.txt
UninstallDisplayName=DroidVM GPU driver (unofficial build)

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "driver\*"; DestDir: "{app}\driver"; Flags: ignoreversion
Source: "DroidVM-GPU-Test.cer"; DestDir: "{app}"; Flags: ignoreversion
Source: "install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "README-install.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install.ps1"" -Dir ""{app}"""; \
  StatusMsg: "Installing certificate and driver..."; Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"""; \
  Flags: runhidden waituntilterminated; RunOnceId: "RemoveDriver"
