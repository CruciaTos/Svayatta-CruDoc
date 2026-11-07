; CruDoc Inno Setup Script
; Adds Windows Firewall allow rule for CruDoc executable on Private and Domain profiles (Task N8)

#define MyAppName "CruDoc"
; The release workflow passes /DMyAppVersion=x.y.z.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Svayatta CruDoc"
#define MyAppExeName "CruDoc.exe"

[Setup]
AppId={{5E4C20BA-2B96-412C-A1A4-32529E7F6589}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=CruDoc-windows-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin

[Files]
Source: "..\CruDoc\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
; Task N8: Add Windows Firewall rule on Private and Domain profiles only
Filename: "netsh.exe"; Parameters: "advfirewall firewall add rule name=""CruDoc LAN Sharing"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes profile=private,domain"; Flags: runhidden
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Remove Windows Firewall rule upon uninstall
Filename: "netsh.exe"; Parameters: "advfirewall firewall delete rule name=""CruDoc LAN Sharing"""; Flags: runhidden
