; Compile through tools\package_windows.ps1 with Inno Setup 6.3 or newer.
; Keep AppId unchanged in future releases so upgrades share one installation.
#ifndef AppVersion
  #error AppVersion must be supplied by package_windows.ps1
#endif
#ifndef BuildNumber
  #error BuildNumber must be supplied by package_windows.ps1
#endif
#ifndef BuildDir
  #error BuildDir must be supplied by package_windows.ps1
#endif
#ifndef ProjectDir
  #error ProjectDir must be supplied by package_windows.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by package_windows.ps1
#endif

[Setup]
AppId={{F43DF555-7CEC-48F9-B343-86F1A49CD564}
AppName=Book and Quill
AppVersion={#AppVersion}
AppVerName=Book and Quill {#AppVersion}
AppPublisher=SHANTIASHAMS
VersionInfoVersion={#AppVersion}.{#BuildNumber}
DefaultDirName={localappdata}\Programs\Book and Quill
DefaultGroupName=Book and Quill
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible and not arm64
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Book-and-Quill-{#AppVersion}-windows-x64-setup
SetupIconFile={#ProjectDir}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\book_and_quill.exe
InfoBeforeFile={#ProjectDir}\release\LOCAL_BUILD_NOTICE.txt
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Book and Quill"; Filename: "{app}\book_and_quill.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Book and Quill"; Filename: "{app}\book_and_quill.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\book_and_quill.exe"; Description: "Open Book and Quill"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

; Intentionally no UninstallDelete or InstallDelete entries.
; Notes live in {localappdata}\Book and Quill, NOT inside {app}.
