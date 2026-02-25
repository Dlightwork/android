#define AppName "NoRKN"
#define AppVersion "1.0.0"
#define BuildOutput "d:\project2\ZapretGlassGui\bin\Release\net8.0-windows\win-x64\publish"
#define ProjectRoot "d:\project2"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=admin
SetupIconFile={#ProjectRoot}\norkn.ico
OutputDir={#ProjectRoot}\dist
OutputBaseFilename=NoRKN-Setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\norkn.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"

[Files]
Source: "{#BuildOutput}\NoRKN.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectRoot}\norkn.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\*.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\*.bin"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion recursesubdirs skipifsourcedoesntexist
Source: "{#BuildOutput}\tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs
Source: "{#BuildOutput}\presets\*"; DestDir: "{app}\presets"; Flags: ignoreversion recursesubdirs
Source: "{#BuildOutput}\lists\*"; DestDir: "{app}\lists"; Flags: ignoreversion recursesubdirs
Source: "{#BuildOutput}\lua\*"; DestDir: "{app}\lua"; Flags: ignoreversion recursesubdirs
Source: "{#BuildOutput}\*.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\*.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\*.ps1"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BuildOutput}\WinDivert*.sys"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\Monkey*.sys"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\winws*.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildOutput}\nssm.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\NoRKN.exe"; IconFilename: "{app}\norkn.ico"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\NoRKN.exe"; Tasks: desktopicon; IconFilename: "{app}\norkn.ico"

[Run]
Filename: "{app}\NoRKN.exe"; Description: "Run {#AppName}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKLM; Subkey: "Software\NoRKN"; ValueName: "AppRoot"; ValueType: string; ValueData: "{app}"
