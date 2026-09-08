$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not (Test-Path (Join-Path $projectRoot "windows"))) {
    & (Join-Path $PSScriptRoot "setup_windows.ps1")
}

& (Join-Path $PSScriptRoot "install_windows_media_bridge.ps1")

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
$statusPath = Join-Path $projectRoot "assets\imported\import_status.json"
$assetPipelineCurrent = $false
if (Test-Path $statusPath) {
    try {
        $status = Get-Content $statusPath -Raw | ConvertFrom-Json
        $assetPipelineCurrent = $status.assetPipelineVersion -ge 10
    } catch {
        $assetPipelineCurrent = $false
    }
}

if (-not (Test-Path $requiredTexture) -or `
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
    -not $assetPipelineCurrent) {
    Write-Host "Minecraft resources are missing or need to be refreshed." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "import_minecraft_assets.ps1")
    flutter clean
    if ($LASTEXITCODE -ne 0) { throw "flutter clean failed with exit code $LASTEXITCODE" }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }
}

if (-not (Test-Path $requiredPageTurn)) {
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
if ($missingNewAssets.Count -gt 0) {
    throw "One or more background/music assets could not be imported. Use a current official Minecraft Java client jar and rerun tools\import_minecraft_assets.ps1."
}

if (Test-Path $statusPath) {
    try {
        $status = Get-Content $statusPath -Raw | ConvertFrom-Json
        if (-not $status.minecraftFontGenerated) {
            Write-Host "The Minecraft font has not been generated yet." -ForegroundColor Yellow
            Write-Host "Run: py -3 -m pip install pillow fonttools" -ForegroundColor Yellow
            Write-Host "Then rerun: powershell -ExecutionPolicy Bypass -File .\tools\import_minecraft_assets.ps1" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Could not read Minecraft import status; continuing with the fallback font." -ForegroundColor DarkYellow
    }
}

& (Join-Path $PSScriptRoot "install_windows_app_icon.ps1")

flutter run -d windows
if ($LASTEXITCODE -ne 0) { throw "flutter run failed with exit code $LASTEXITCODE" }
