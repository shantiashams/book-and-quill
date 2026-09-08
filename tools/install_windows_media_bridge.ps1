$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runnerRoot = Join-Path $projectRoot "windows\runner"
$sourceRoot = Join-Path $PSScriptRoot "windows_media_bridge"

if (-not (Test-Path $runnerRoot)) {
    throw "The Windows runner does not exist yet. Run tools\setup_windows.ps1 first."
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Text
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

Copy-Item (Join-Path $sourceRoot "book_media_bridge.h") `
    (Join-Path $runnerRoot "book_media_bridge.h") -Force
Copy-Item (Join-Path $sourceRoot "book_media_bridge.cpp") `
    (Join-Path $runnerRoot "book_media_bridge.cpp") -Force

$cmakePath = Join-Path $runnerRoot "CMakeLists.txt"
$cmake = [System.IO.File]::ReadAllText($cmakePath)
if ($cmake -notmatch 'book_media_bridge\.cpp') {
    $flutterSource = '  "flutter_window.cpp"'
    if (-not $cmake.Contains($flutterSource)) {
        throw "Could not find flutter_window.cpp in windows\runner\CMakeLists.txt."
    }
    $cmake = $cmake.Replace(
        $flutterSource,
        "  `"book_media_bridge.cpp`"`r`n$flutterSource"
    )
}
if ($cmake -notmatch 'windowsapp\.lib') {
    $cmake += "`r`n# Book and Quill Windows media sessions (SMTC).`r`n"
    $cmake += 'target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib" "runtimeobject.lib")'
    $cmake += "`r`n"
}
if ($cmake -notmatch '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS') {
    $cmake += "`r`n# C++/WinRT requires standard coroutines with current MSVC releases.`r`n"
    $cmake += 'set_property(TARGET ${BINARY_NAME} PROPERTY CXX_STANDARD 20)'
    $cmake += "`r`n"
    $cmake += 'set_property(TARGET ${BINARY_NAME} PROPERTY CXX_STANDARD_REQUIRED ON)'
    $cmake += "`r`n"
    $cmake += 'target_compile_definitions(${BINARY_NAME} PRIVATE _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)'
    $cmake += "`r`n"
}
Write-Utf8File -Path $cmakePath -Text $cmake

$headerPath = Join-Path $runnerRoot "flutter_window.h"
$header = [System.IO.File]::ReadAllText($headerPath)
if ($header -notmatch 'class BookMediaBridge;') {
    $classMarker = 'class FlutterWindow : public Win32Window {'
    if (-not $header.Contains($classMarker)) {
        throw "Could not find FlutterWindow in windows\runner\flutter_window.h."
    }
    $header = $header.Replace(
        $classMarker,
        "class BookMediaBridge;`r`n`r`n$classMarker"
    )
}
if ($header -notmatch 'media_bridge_;') {
    $controllerMarker = '  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;'
    if (-not $header.Contains($controllerMarker)) {
        throw "Could not find FlutterViewController in windows\runner\flutter_window.h."
    }
    $header = $header.Replace(
        $controllerMarker,
        "  std::unique_ptr<BookMediaBridge> media_bridge_;`r`n$controllerMarker"
    )
}
Write-Utf8File -Path $headerPath -Text $header

$sourcePath = Join-Path $runnerRoot "flutter_window.cpp"
$source = [System.IO.File]::ReadAllText($sourcePath)
if ($source -notmatch '#include "book_media_bridge\.h"') {
    $includeMarker = '#include "flutter_window.h"'
    if (-not $source.Contains($includeMarker)) {
        throw "Could not find flutter_window.h include in flutter_window.cpp."
    }
    $source = $source.Replace(
        $includeMarker,
        "$includeMarker`r`n`r`n#include `"book_media_bridge.h`""
    )
}
if ($source -notmatch 'make_unique<BookMediaBridge>') {
    $registerMarker = '  RegisterPlugins(flutter_controller_->engine());'
    if (-not $source.Contains($registerMarker)) {
        throw "Could not find plugin registration in flutter_window.cpp."
    }
    $bridgeCreation = @"
$registerMarker
  media_bridge_ = std::make_unique<BookMediaBridge>(
      flutter_controller_->engine()->messenger(), GetHandle());
"@
    $source = $source.Replace($registerMarker, $bridgeCreation.TrimEnd())
}
if ($source -notmatch 'media_bridge_\.reset\(\);') {
    $destroyMarker = 'void FlutterWindow::OnDestroy() {'
    if (-not $source.Contains($destroyMarker)) {
        throw "Could not find FlutterWindow::OnDestroy in flutter_window.cpp."
    }
    $source = $source.Replace(
        $destroyMarker,
        "$destroyMarker`r`n  media_bridge_.reset();"
    )
}
Write-Utf8File -Path $sourcePath -Text $source

Write-Host "Windows media-session bridge is installed." -ForegroundColor Green
