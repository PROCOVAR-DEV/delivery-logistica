#ifndef Version
  #error Version required
#endif
#ifndef BundleDir
  #error BundleDir required
#endif
#ifndef OutputDir
  #error OutputDir required
#endif
[Setup]
AppId=cloud.procovar.reparto.windows
AppName=Reparto
AppVersion={#Version}
AppPublisher=ProCovar
DefaultDirName={localappdata}\Programs\ProCovar\Reparto
DefaultGroupName=ProCovar
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=reparto-{#Version}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
UninstallDisplayIcon={app}\reparto.exe
[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; Flags: unchecked
[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{userprograms}\ProCovar\Reparto"; Filename: "{app}\reparto.exe"
Name: "{userdesktop}\Reparto"; Filename: "{app}\reparto.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\reparto.exe"; Description: "Abrir Reparto"; Flags: nowait postinstall skipifsilent
