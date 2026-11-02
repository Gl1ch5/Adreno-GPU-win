; Standalone rollback tool (works even if the setup's uninstaller is gone)
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
[Setup]
AppId={{6B0D1E52-4C1B-4E0A-9C3D-D401D0D0A82A}
AppName=DroidVM GPU driver rollback
AppVersion={#AppVersion}
CreateAppDir=no
Uninstallable=no
DisableProgramGroupPage=yes
DisableReadyPage=no
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
PrivilegesRequired=admin
OutputBaseFilename=DroidVM-GPU-Uninstall
OutputDir=.
AlwaysRestart=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "uninstall.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Run]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\uninstall.ps1"""; \
  StatusMsg: "Removing driver, certificate..."; Flags: runhidden waituntilterminated
