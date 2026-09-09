#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [switch]$Bundle,
    [switch]$Install,
    [string]$DeviceId
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Bundle -and $Mode -ne 'release') { throw 'An app bundle requires -Mode release.' }
if ($Bundle -and $Install) { throw 'Use an APK to install directly on a device.' }
& (Join-Path $PSScriptRoot 'setup_android.ps1')
Push-Location $projectRoot
try {
    if ($Mode -eq 'release') {
        $keys = Join-Path $projectRoot 'android/key.properties'
        if (-not (Test-Path $keys)) {
            throw 'Release signing is not configured. Follow ANDROID_SETUP.md and create android/key.properties, or build a debug APK first.'
        }
        $keyText = [IO.File]::ReadAllText($keys)
        foreach ($name in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
            if ($keyText -notmatch "(?m)^$name=.+" -or $keyText -match 'YOUR_') {
                throw 'Complete your local android/key.properties before making a release.'
            }
        }
    }
    & flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Android regression checks failed; no APK was packaged.' }
    $target = if ($Bundle) { 'appbundle' } else { 'apk' }
    & flutter build $target "--$Mode"
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed. Check flutter doctor -v and the first Gradle error above.' }
    $source = if ($Bundle) { 'build/app/outputs/bundle/release/app-release.aab' } else { "build/app/outputs/flutter-apk/app-$Mode.apk" }
    if (-not (Test-Path $source)) { throw "Expected build output was not found: $source" }
    $versionText = [IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml'))
    $version = [regex]::Match($versionText, '(?m)^version:\s*([^+\s]+)').Groups[1].Value
    if (-not $version) { throw 'Could not read the application version.' }
    $extension = if ($Bundle) { 'aab' } else { 'apk' }
    $outputDirectory = Join-Path $projectRoot "dist/$version/android"
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $output = Join-Path $outputDirectory "Book-and-Quill-$version-android-$Mode.$extension"
    Copy-Item -LiteralPath $source -Destination $output -Force
    Write-Host "Built: $output" -ForegroundColor Green
    if ($Install) {
        $installArguments = @('install', "--$Mode")
        if ($DeviceId) { $installArguments += @('-d', $DeviceId) }
        & flutter @installArguments
        if ($LASTEXITCODE -ne 0) { throw 'The APK built successfully, but installation failed. Check flutter devices.' }
    }
} finally { Pop-Location }
