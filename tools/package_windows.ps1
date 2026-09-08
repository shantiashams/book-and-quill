#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InnoCompiler,
    [string]$VCRuntimeDirectory,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Build this Windows release on Windows, using the Flutter SDK that runs your app.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

function Require-X64Binary([string]$Path) {
    Require-File $Path
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Not a Windows executable: $Path" }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0x40 -or $peOffset -gt ($stream.Length - 6)) {
            throw "Invalid executable header: $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Expected an x64 executable/DLL, not x86 or ARM64: $Path"
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Invoke-Flutter([string[]]$FlutterArguments) {
    & $script:flutterCommand @FlutterArguments
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($FlutterArguments -join ' ') failed (exit $LASTEXITCODE). No release was completed."
    }
}

function Find-InnoCompiler {
    if ($InnoCompiler) {
        Require-File $InnoCompiler
        return (Resolve-Path -LiteralPath $InnoCompiler).Path
    }
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($innoFolder in @('Inno Setup 7', 'Inno Setup 6')) {
        foreach ($programs in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
            if (-not $programs) { continue }
            $candidate = Join-Path $programs "$innoFolder\ISCC.exe"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw 'Install Inno Setup 6.3 or newer from https://jrsoftware.org/isdl.php, or supply -InnoCompiler with the path to ISCC.exe.'
}

function Find-VCRuntime([string]$VisualStudioRoot) {
    if ($VCRuntimeDirectory) {
        $candidate = (Resolve-Path -LiteralPath $VCRuntimeDirectory).Path
    } else {
        if (-not $VisualStudioRoot) {
            $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
            Require-File $vswhere
            $found = @(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
            if ($LASTEXITCODE -ne 0 -or $found.Count -eq 0) {
                throw 'Visual Studio C++ tools were not found. Install the Desktop development with C++ workload.'
            }
            $VisualStudioRoot = $found[0].Trim()
        }
        $redistRoot = Join-Path $VisualStudioRoot 'VC\Redist\MSVC'
        $versions = @(Get-ChildItem -LiteralPath $redistRoot -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending)
        $candidate = $null
        foreach ($versionFolder in $versions) {
            $x64Root = Join-Path $versionFolder.FullName 'x64'
            if (-not (Test-Path -LiteralPath $x64Root -PathType Container)) { continue }
            $crt = @(Get-ChildItem -LiteralPath $x64Root -Directory -Filter 'Microsoft.VC*.CRT')
            if ($crt.Count -gt 0) {
                $candidate = $crt[0].FullName
                break
            }
        }
        if (-not $candidate) {
            throw 'The x64 Visual C++ redistributable DLL folder was not found. Supply -VCRuntimeDirectory pointing to Microsoft.VC*.CRT under Visual Studio\VC\Redist\MSVC.'
        }
    }
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        Require-X64Binary (Join-Path $candidate $dll)
    }
    return $candidate
}

foreach ($relativePath in @(
    'pubspec.yaml', 'pubspec.lock', 'lib\app_version.dart',
    'windows\CMakeLists.txt', 'windows\runner\book_media_bridge.cpp',
    'tools\install_windows_app_icon.ps1', 'installer\book_and_quill.iss',
    'release\LOCAL_BUILD_NOTICE.txt',
    'assets\imported\textures\book_and_quil.png',
    'assets\imported\textures\book.png',
    'assets\imported\textures\chiseled_bookshelf_empty.png',
    'assets\imported\textures\chiseled_bookshelf_occupied.png',
    'assets\imported\fonts\minecraft_local_v2.ttf',
    'assets\imported\fonts\minecraft_book_grid_v3.ttf',
    'test\book_record_test.dart', 'test\book_storage_test.dart',
    'test\rich_text_editing_controller_test.dart'
)) {
    Require-File (Join-Path $projectRoot $relativePath)
}

$versionSource = [IO.File]::ReadAllText((Join-Path $projectRoot 'lib\app_version.dart'))
$versionMatch = [regex]::Match($versionSource, 'static\s+const\s+String\s+value\s*=\s*[''"](?<v>\d+\.\d+\.\d+)[''"]\s*;')
if (-not $versionMatch.Success) { throw 'Could not read AppVersion.value from lib\app_version.dart.' }
$appVersion = $versionMatch.Groups['v'].Value
$pubspec = [IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml'))
$buildMatch = [regex]::Match($pubspec, '(?m)^version:\s*\d+\.\d+\.\d+\+(?<n>\d+)\s*$')
if (-not $buildMatch.Success) { throw 'pubspec.yaml needs a numeric build suffix, such as version: 3.3.2+21.' }
$buildNumber = $buildMatch.Groups['n'].Value
foreach ($component in @($appVersion.Split('.')) + @($buildNumber)) {
    if ([long]$component -gt 65535) { throw 'Windows version components must be between 0 and 65535.' }
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { throw 'Flutter is not on PATH. Use the terminal where tools\run_windows.ps1 works.' }
$script:flutterCommand = $flutter.Source
$compiler = Find-InnoCompiler
# ISCC.exe's Windows file-version resource is not the compiler engine version.
# Inno validates the required directives during compilation; preserve its errors
# instead of rejecting working installations based on unrelated/absent metadata.
$runtimeRoot = Find-VCRuntime

Write-Host "Release version: $appVersion (Windows build $buildNumber)" -ForegroundColor Cyan
Write-Host "Inno Setup: $compiler"
Write-Host "Visual C++ runtime: $runtimeRoot"
Write-Warning 'This local build bundles your imported assets. Do not publish it until their redistribution and the app branding have been reviewed. Nothing is uploaded by this script.'
if ($CheckOnly) {
    Write-Host 'Prerequisite check passed. No build or install was performed.' -ForegroundColor Green
    return
}

if (Get-Process -Name book_and_quill -ErrorAction SilentlyContinue) {
    throw 'Close Book and Quill before building. The script will not force-close it or risk unsaved writing.'
}

Push-Location $projectRoot
try {
    # Remove only generated Flutter caches, including stale paths after moving the project.
    Invoke-Flutter -FlutterArguments @('clean')
    Invoke-Flutter -FlutterArguments @('pub', 'get', '--enforce-lockfile')
    Invoke-Flutter -FlutterArguments @('analyze', 'lib', '--no-fatal-infos', '--no-fatal-warnings')
    # These are current data/controller tests. The uploaded widget_test.dart is outdated.
    Invoke-Flutter -FlutterArguments @('test', 'test/book_record_test.dart', 'test/book_storage_test.dart', 'test/rich_text_editing_controller_test.dart')
    & (Join-Path $PSScriptRoot 'install_windows_app_icon.ps1')
    # Build flags keep the executable and installer aligned with the version displayed in the app.
    Invoke-Flutter -FlutterArguments @('build', 'windows', '--release', "--build-name=$appVersion", "--build-number=$buildNumber")

    $releaseRoot = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    foreach ($relativePath in @('book_and_quill.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\app.so', 'data\flutter_assets\NOTICES.Z')) {
        Require-File (Join-Path $releaseRoot $relativePath)
    }
    Require-X64Binary (Join-Path $releaseRoot 'book_and_quill.exe')
    $exeInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $releaseRoot 'book_and_quill.exe'))
    $expectedVersion = "$appVersion.$buildNumber"
    $actualVersion = '{0}.{1}.{2}.{3}' -f $exeInfo.FileMajorPart, $exeInfo.FileMinorPart, $exeInfo.FileBuildPart, $exeInfo.FilePrivatePart
    if ($actualVersion -ne $expectedVersion) {
        throw "Executable version is $actualVersion; expected $expectedVersion. Packaging stopped."
    }

    # Prefer redistributables from the actual Visual Studio instance selected by Flutter/CMake.
    $cachePath = Join-Path $projectRoot 'build\windows\x64\CMakeCache.txt'
    Require-File $cachePath
    $instance = [regex]::Match([IO.File]::ReadAllText($cachePath), '(?m)^CMAKE_GENERATOR_INSTANCE:INTERNAL=(.+)\r?$')
    if ($instance.Success) {
        $selectedVS = $instance.Groups[1].Value.Trim() -replace ',version=[\d.]+$', ''
        $runtimeRoot = Find-VCRuntime -VisualStudioRoot $selectedVS
    }

    $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $outputRoot = Join-Path $projectRoot "dist\$appVersion\$runId"
    $payloadRoot = Join-Path $outputRoot 'Book and Quill'
    [void][IO.Directory]::CreateDirectory($payloadRoot)

    # Copy the complete runtime bundle, excluding debug symbols and local importer path metadata.
    foreach ($file in Get-ChildItem -LiteralPath $releaseRoot -Recurse -File) {
        if ($file.Extension -eq '.pdb' -or $file.Name -eq 'import_status.json') { continue }
        $relative = $file.FullName.Substring($releaseRoot.Length).TrimStart([char]'\')
        $destination = Join-Path $payloadRoot $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
    foreach ($dll in Get-ChildItem -LiteralPath $runtimeRoot -File -Filter '*.dll') {
        Copy-Item -LiteralPath $dll.FullName -Destination $payloadRoot -Force
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'release\LOCAL_BUILD_NOTICE.txt') -Destination $payloadRoot

    $installerArguments = @(
        "/DAppVersion=$appVersion",
        "/DBuildNumber=$buildNumber",
        "/DBuildDir=$payloadRoot",
        "/DProjectDir=$projectRoot",
        "/DOutputDir=$outputRoot",
        (Join-Path $projectRoot 'installer\book_and_quill.iss')
    )
    & $compiler @installerArguments
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed (exit $LASTEXITCODE). Partial output is at $outputRoot" }
    $installerPath = Join-Path $outputRoot "Book-and-Quill-$appVersion-windows-x64-setup.exe"
    Require-File $installerPath

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = Join-Path $outputRoot "Book-and-Quill-$appVersion-windows-x64-portable.zip"
    [IO.Compression.ZipFile]::CreateFromDirectory($payloadRoot, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $true)
    $hashLines = foreach ($artifact in @($installerPath, $zipPath)) {
        $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        '{0}  {1}' -f $hash, [IO.Path]::GetFileName($artifact)
    }
    [IO.File]::WriteAllLines((Join-Path $outputRoot 'SHA256SUMS.txt'), [string[]]$hashLines)
    Write-Host "`nInstaller and portable ZIP created in:`n$outputRoot" -ForegroundColor Green
    Write-Host 'Test installation, launch, upgrade, and uninstall on Windows before sharing. Saved books are not included in either package.'
} finally {
    Pop-Location
}
