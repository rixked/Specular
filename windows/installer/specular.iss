; Inno Setup script for the Windows installer (SPEC.md §3.6).
;
; Built in the release workflow:
;   iscc /DAppVersion=0.1.0 /DSourceDir=<release bundle> /DOutputDir=<dist> specular.iss
;
; Installs per user (no admin rights), so in-app updates run without a UAC
; prompt. The app starts this installer with /SILENT for updates; it closes
; the running app, replaces the files and starts Specular again.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Never change the AppId: updates find the existing installation through it.
AppId={{6F1E3C2A-8B4D-4E5F-9A7B-3C2D1E0F5A6B}
AppName=Specular
AppVersion={#AppVersion}
AppPublisher=rixk.de
AppPublisherURL=https://github.com/rixked/Specular
DefaultDirName={localappdata}\Programs\Specular
DefaultGroupName=Specular
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=specular-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no
UninstallDisplayIcon={app}\specular.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Specular"; Filename: "{app}\specular.exe"
Name: "{autodesktop}\Specular"; Filename: "{app}\specular.exe"; Tasks: desktopicon

[Run]
; First install: offer to start the app.
Filename: "{app}\specular.exe"; Description: "Start Specular"; Flags: nowait postinstall skipifsilent
; Silent update from inside the app: start it again right away.
Filename: "{app}\specular.exe"; Flags: nowait; Check: WizardSilent
