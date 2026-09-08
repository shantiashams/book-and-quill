param(
    [switch]$ImportMinecraftAssets,
    [switch]$SkipMinecraftAssets
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Invoke-FlutterChecked {
    param([string[]]$Arguments)

    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 does not automatically convert a failing
        # native process exit code into a terminating error.
        $ErrorActionPreference = "Continue"
        & flutter @Arguments
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        throw ("Flutter command failed (exit " + $exitCode + "): flutter " + ($Arguments -join " "))
    }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "Flutter is not available in PATH." -ForegroundColor Red
    Write-Host "In VS Code install the Flutter extension, press Ctrl+Shift+P, choose 'Flutter: New Project', then choose 'Download SDK'."
    Write-Host "Restart VS Code after adding Flutter to PATH, then run this script again."
    exit 1
}

Invoke-FlutterChecked @("config", "--enable-windows-desktop")

$runnerCmake = Join-Path $projectRoot "windows\CMakeLists.txt"
$runnerNeedsRename = $false
if (Test-Path $runnerCmake) {
    $runnerCmakeText = Get-Content $runnerCmake -Raw
    $runnerNeedsRename = $runnerCmakeText -match 'quillcraft'
}

if (-not (Test-Path (Join-Path $projectRoot "windows")) -or $runnerNeedsRename) {
    Write-Host "Generating the Windows runner..." -ForegroundColor Cyan
    Invoke-FlutterChecked @("create", "--platforms=windows", "--project-name", "book_and_quill", "--org", "local.book_and_quill", ".")
}

# `flutter create` preserves existing runner files. If this project reuses the
# tiny Windows runner from the old build, update its generated names in place;
# Flutter and Visual Studio remain installed outside this folder.
foreach ($relativeFile in @(
    "windows\CMakeLists.txt",
    "windows\runner\main.cpp",
    "windows\runner\Runner.rc",
    "windows\runner\runner.exe.manifest"
)) {
    $runnerFile = Join-Path $projectRoot $relativeFile
    if (Test-Path $runnerFile) {
        $runnerText = [System.IO.File]::ReadAllText($runnerFile)
        $runnerText = $runnerText.Replace("Quillcraft", "Book and Quill")
        $runnerText = $runnerText.Replace("quillcraft", "book_and_quill")
        if ($relativeFile -eq "windows\runner\main.cpp" -or `
            $relativeFile -eq "windows\runner\Runner.rc") {
            $runnerText = $runnerText.Replace("book_and_quill", "Book and Quill")
        }
        [System.IO.File]::WriteAllText(
            $runnerFile,
            $runnerText,
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
}

& (Join-Path $PSScriptRoot "install_windows_media_bridge.ps1")

Invoke-FlutterChecked @("pub", "get")

$requiredTexture = Join-Path $projectRoot "assets\imported\textures\chiseled_bookshelf_empty.png"
$requiredBookGui = Join-Path $projectRoot "assets\imported\textures\book.png"
$requiredBookIcon = Join-Path $projectRoot "assets\imported\textures\book_and_quil.png"
$requiredSand = Join-Path $projectRoot "assets\imported\textures\sand.png"
$requiredSandstone = Join-Path $projectRoot "assets\imported\textures\sandstone.png"
$requiredNetherite = Join-Path $projectRoot "assets\imported\textures\netherite_block.png"
$requiredConcrete = Join-Path $projectRoot "assets\imported\textures\white_concrete.png"
$requiredPageTurn = Join-Path $projectRoot "assets\imported\sounds\page_turn.ogg"
$requiredOverworldMusic = Join-Path $projectRoot "assets\imported\sounds\music_minecraft.ogg"
$requiredNetherMusic = Join-Path $projectRoot "assets\imported\sounds\nether_concrete_halls.ogg"
$requiredEndMusic = Join-Path $projectRoot "assets\imported\sounds\end_the_end.ogg"
$requiredGridFont = Join-Path $projectRoot "assets\imported\fonts\minecraft_book_grid_v3.ttf"
$importStatus = Join-Path $projectRoot "assets\imported\import_status.json"
$assetPipelineCurrent = $false
if (Test-Path $importStatus) {
    try {
        $status = Get-Content $importStatus -Raw | ConvertFrom-Json
        $assetPipelineCurrent = $status.assetPipelineVersion -ge 10
    } catch {
        $assetPipelineCurrent = $false
    }
}
$assetsMissing = `
    -not (Test-Path $requiredTexture) -or `
    -not (Test-Path $requiredBookGui) -or `
    -not (Test-Path $requiredBookIcon) -or `
    -not (Test-Path $requiredSand) -or `
    -not (Test-Path $requiredSandstone) -or `
    -not (Test-Path $requiredNetherite) -or `
    -not (Test-Path $requiredConcrete) -or `
    -not (Test-Path $requiredPageTurn) -or `
    -not (Test-Path $requiredOverworldMusic) -or `
    -not (Test-Path $requiredNetherMusic) -or `
    -not (Test-Path $requiredEndMusic) -or `
    -not (Test-Path $requiredGridFont) -or `
    -not $assetPipelineCurrent

if (-not $SkipMinecraftAssets -and ($ImportMinecraftAssets -or $assetsMissing)) {
    Write-Host "Minecraft resources are missing; starting the local importer..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "import_minecraft_assets.ps1")
    Invoke-FlutterChecked @("clean")
    Invoke-FlutterChecked @("pub", "get")
}

if (-not $SkipMinecraftAssets -and -not (Test-Path $requiredPageTurn)) {
    throw "Minecraft's page-turn sound could not be found in the locally installed assets. Rerun the importer and check its 'Could not locate sound' lines."
}

$missingNewAssets = @(
    $requiredSand,
    $requiredSandstone,
    $requiredNetherite,
    $requiredConcrete,
    $requiredOverworldMusic,
    $requiredNetherMusic,
    $requiredEndMusic
) | Where-Object { -not (Test-Path $_) }
if (-not $SkipMinecraftAssets -and $missingNewAssets.Count -gt 0) {
    throw "One or more background/music assets could not be imported. Use a current official Minecraft Java client jar and rerun tools\import_minecraft_assets.ps1."
}

& (Join-Path $PSScriptRoot "install_windows_app_icon.ps1")

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Run the app with: flutter run -d windows"
