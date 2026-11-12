; Helmy's Windows installer, built by Inno Setup in build.yml:
;   iscc /DAppVersion=0.3.3 /DArch=x64 /DSourceDir=<Release folder> /DOutputName=Helmy-v0.3.3-windows-x64 helmy.iss
; Installs for the person alone (no administrator), in the Start menu, and opens Helmy.
#define AppName "Helmy"

[Setup]
AppId={{6F3B2D1E-6C1A-4C77-9E0B-2B8F6C4D7A11}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Mittolabs
AppPublisherURL=https://helmy.ke
AppSupportURL=https://github.com/mittolabs/helmy/issues
DefaultDirName={localappdata}\Programs\Helmy
DefaultGroupName=Helmy
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\helmy.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Tasks]
Name: "desktopicon"; Description: "Put Helmy on the desktop"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Helmy"; Filename: "{app}\helmy.exe"
Name: "{autodesktop}\Helmy"; Filename: "{app}\helmy.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\helmy.exe"; Description: "Open Helmy"; Flags: nowait postinstall skipifsilent
