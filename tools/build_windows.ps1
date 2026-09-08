$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not (Test-Path (Join-Path $projectRoot "windows"))) {
    & (Join-Path $PSScriptRoot "setup_windows.ps1")
}

& (Join-Path $PSScriptRoot "install_windows_media_bridge.ps1")
& (Join-Path $PSScriptRoot "install_windows_app_icon.ps1")

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed with exit code $LASTEXITCODE" }
Write-Host ""
Write-Host "Release build created in build\windows\x64\runner\Release" -ForegroundColor Green
