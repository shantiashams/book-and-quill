#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git was not found.' }
Push-Location $projectRoot
try {
    $gitRoot = & git rev-parse --show-toplevel
    if ($LASTEXITCODE -ne 0) { throw 'Extract this update into your existing Git project first.' }
    if ([IO.Path]::GetFullPath($gitRoot.Trim()) -ne [IO.Path]::GetFullPath($projectRoot)) {
        throw 'Run this script from the Book and Quill repository, not a nested extracted folder.'
    }
    # Explicit project files only; never stage a downloaded SDK, personal
    # writing, key.properties, signing keys, or unrelated project files.
    $manifest = Join-Path $PSScriptRoot 'android_github_files.json'
    # Windows PowerShell 5.1 emits a JSON array as one pipeline object.
    # Assign it first, then enumerate explicitly so Join-Path and git each
    # receive individual paths under both Windows PowerShell and PowerShell 7.
    $parsedFiles = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($manifest))
    $files = @(foreach ($entry in $parsedFiles) {
        if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) {
            throw 'The Android file manifest must contain individual non-empty path strings.'
        }
        $entry
    })
    if ($files.Count -eq 0) { throw 'The Android file manifest is empty.' }
    $requiredAssets = @(
        'assets/imported/textures/book_and_quil.png',
        'assets/imported/fonts/minecraft_local_v2.ttf',
        'assets/imported/fonts/minecraft_book_grid_v3.ttf'
    )
    foreach ($relative in ($files + $requiredAssets)) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
            throw "Missing $relative. Extract the whole update into the project and keep your existing assets."
        }
    }
    # Existing source releases ignored these assets. Include only the app's
    # image, sound, and font formats, leaving every other ignored file alone.
    $assetRoot = Join-Path $projectRoot 'assets/imported'
    $assets = @(Get-ChildItem -LiteralPath $assetRoot -File -Recurse |
        Where-Object { $_.Extension.ToLowerInvariant() -in @('.png', '.ogg', '.ttf') })
    foreach ($asset in $assets) {
        if ($asset.Length -gt 99MB) { throw "Asset too large for ordinary Git: $($asset.Name). Use Git LFS first." }
    }
    & git add -- @files
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage the Android source update.' }
    foreach ($asset in $assets) {
        $relative = $asset.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
        & git add -f -- $relative
        if ($LASTEXITCODE -ne 0) { throw "Could not stage asset: $relative" }
    }
    Write-Host "Staged the Android build update and $($assets.Count) app assets." -ForegroundColor Green
    & git --no-pager diff --cached --stat
    Write-Host 'Next: git commit -m "Fix Windows Android Kotlin cache - v3.4.5"'
    Write-Host 'Then: git pull --no-rebase --no-edit origin main'
    Write-Host 'If that succeeds: git push origin main'
    Write-Host 'Download the APK from GitHub > Actions > Android APK > successful run > Artifacts.'
} finally { Pop-Location }
