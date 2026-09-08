param(
    [string]$JarPath
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$destinationRoot = Join-Path $projectRoot "assets\imported"
$textureDestination = Join-Path $destinationRoot "textures"
$soundDestination = Join-Path $destinationRoot "sounds"
$fontDestination = Join-Path $destinationRoot "fonts"
$minecraftRoot = Join-Path $env:APPDATA ".minecraft"

New-Item -ItemType Directory -Force -Path $textureDestination | Out-Null
New-Item -ItemType Directory -Force -Path $soundDestination | Out-Null
New-Item -ItemType Directory -Force -Path $fontDestination | Out-Null

if (-not $JarPath) {
    $versionRoot = Join-Path $minecraftRoot "versions"
    if (Test-Path $versionRoot) {
        $candidate = Get-ChildItem -Path $versionRoot -Filter "*.jar" -Recurse -File |
            Where-Object { $_.Length -gt 5MB } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate) {
            $JarPath = $candidate.FullName
        }
    }
}

if (-not $JarPath -or -not (Test-Path $JarPath)) {
    Write-Host "Minecraft Java Edition was not found automatically." -ForegroundColor Yellow
    $JarPath = Read-Host "Paste the full path to an official Minecraft client .jar file"
}

if (-not (Test-Path $JarPath)) {
    throw "Minecraft client jar not found: $JarPath"
}

Write-Host ("Using Minecraft client: " + $JarPath) -ForegroundColor Cyan

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("book-and-quill-assets-" + [guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $temporaryRoot "client.zip"
$expandedPath = Join-Path $temporaryRoot "client"
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null

$importedTextures = New-Object System.Collections.Generic.List[string]
$importedSounds = New-Object System.Collections.Generic.List[string]
$fontImported = $false

function Invoke-PythonCommand {
    param(
        [object]$Candidate,
        [string[]]$Arguments,
        [switch]$Quiet
    )

    $allArguments = @($Candidate.Prefix) + @($Arguments)
    $executable = $Candidate.Path
    $previousPreference = $ErrorActionPreference
    $exitCode = 1

    try {
        # Windows PowerShell turns a native program's stderr into error records.
        # Temporarily using Continue lets us inspect the real process exit code
        # instead of aborting the complete asset import.
        $ErrorActionPreference = "Continue"
        if ($Quiet) {
            & $executable @allArguments *> $null
        } else {
            & $executable @allArguments 2>&1 | ForEach-Object { Write-Host $_ }
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $exitCode = 1
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    return $exitCode
}

function Get-SoundEventCandidates {
    param(
        [object]$SoundRegistry,
        [string[]]$EventNames
    )

    $results = New-Object System.Collections.Generic.List[string]
    if (-not $SoundRegistry) {
        return @()
    }

    foreach ($eventName in $EventNames) {
        $eventProperty = $SoundRegistry.PSObject.Properties[$eventName]
        if (-not $eventProperty) {
            continue
        }

        foreach ($sound in @($eventProperty.Value.sounds)) {
            $soundName = $null
            $soundType = $null
            if ($sound -is [string]) {
                $soundName = $sound
            } elseif ($sound -and $sound.PSObject.Properties["name"]) {
                $soundName = $sound.name
                if ($sound.PSObject.Properties["type"]) {
                    $soundType = $sound.type
                }
            }

            # An entry with type=event points at another sound event rather
            # than an asset object, so it is not a directly copyable file.
            if (-not $soundName -or $soundType -eq "event") {
                continue
            }

            $normalizedName = $soundName -replace "\\", "/"
            if ($normalizedName.StartsWith("minecraft:")) {
                $normalizedName = $normalizedName.Substring("minecraft:".Length)
            }
            if (-not $normalizedName.EndsWith(".ogg")) {
                $normalizedName += ".ogg"
            }
            $assetName = "minecraft/sounds/" + $normalizedName.TrimStart("/")
            if (-not $results.Contains($assetName)) {
                $results.Add($assetName)
            }
        }
    }

    return @($results)
}

function Copy-Texture {
    param(
        [string[]]$Candidates,
        [string]$Destination,
        [string]$FallbackName,
        [string]$FallbackPathPattern
    )

    $source = $null
    foreach ($relativePath in $Candidates) {
        $candidatePath = Join-Path $expandedPath $relativePath
        if (Test-Path $candidatePath) {
            $source = Get-Item $candidatePath
            break
        }
    }

    if (-not $source -and $FallbackName) {
        $source = Get-ChildItem -Path $expandedPath -Filter $FallbackName -Recurse -File |
            Where-Object { -not $FallbackPathPattern -or $_.FullName -match $FallbackPathPattern } |
            Select-Object -First 1
    }

    if ($source) {
        Copy-Item $source.FullName (Join-Path $textureDestination $Destination) -Force
        $importedTextures.Add($Destination)
        Write-Host ("Imported texture: " + $Destination) -ForegroundColor Green
        return $source.FullName
    }

    Write-Host ("Could not locate texture: " + $Destination) -ForegroundColor DarkYellow
    return $null
}

function Get-IndexedAssetFile {
    param(
        [object]$AssetIndex,
        [string[]]$Candidates,
        [string]$NamePattern
    )

    if (-not $AssetIndex) {
        return $null
    }

    $property = $null
    foreach ($candidateName in $Candidates) {
        $property = $AssetIndex.objects.PSObject.Properties[$candidateName]
        if ($property) {
            break
        }
    }

    if (-not $property -and $NamePattern) {
        $property = $AssetIndex.objects.PSObject.Properties |
            Where-Object { $_.Name -match $NamePattern } |
            Select-Object -First 1
    }

    if (-not $property) {
        return $null
    }

    $hash = $property.Value.hash
    if (-not $hash -or $hash.Length -lt 2) {
        return $null
    }

    $objectPath = Join-Path $minecraftRoot ("assets\objects\" + $hash.Substring(0, 2) + "\" + $hash)
    if (Test-Path $objectPath) {
        return $objectPath
    }
    return $null
}

function Get-IndexedAssetAcrossInstalledIndexes {
    param(
        [string[]]$Candidates,
        [string]$NamePattern
    )

    $assetIndexDirectory = Join-Path $minecraftRoot "assets\indexes"
    if (-not (Test-Path $assetIndexDirectory)) {
        return $null
    }

    $installedIndexFiles = Get-ChildItem $assetIndexDirectory -Filter "*.json" -File |
        Sort-Object LastWriteTime -Descending
    foreach ($indexFile in $installedIndexFiles) {
        try {
            $installedIndex = Get-Content $indexFile.FullName -Raw | ConvertFrom-Json
            $source = Get-IndexedAssetFile `
                -AssetIndex $installedIndex `
                -Candidates $Candidates `
                -NamePattern $NamePattern
            if ($source) {
                return $source
            }
        } catch {
            # One damaged or partially downloaded index must not prevent the
            # importer from checking the other locally installed versions.
        }
    }

    return $null
}

function Copy-Sound {
    param(
        [object]$AssetIndex,
        [string[]]$Candidates,
        [string]$NamePattern,
        [string]$Destination
    )

    $source = Get-IndexedAssetFile -AssetIndex $AssetIndex -Candidates $Candidates -NamePattern $NamePattern
    if (-not $source) {
        $source = Get-IndexedAssetAcrossInstalledIndexes `
            -Candidates $Candidates `
            -NamePattern $NamePattern
    }
    if (-not $source) {
        $leafName = Split-Path $Candidates[0] -Leaf
        $sourceItem = Get-ChildItem -Path $expandedPath -Filter $leafName -Recurse -File |
            Select-Object -First 1
        if ($sourceItem) {
            $source = $sourceItem.FullName
        }
    }

    if ($source) {
        Copy-Item $source (Join-Path $soundDestination $Destination) -Force
        $importedSounds.Add($Destination)
        Write-Host ("Imported sound: " + $Destination) -ForegroundColor Green
    } else {
        Write-Host ("Could not locate sound: " + $Destination) -ForegroundColor DarkYellow
    }
}

try {
    Copy-Item $JarPath $archivePath
    Expand-Archive -Path $archivePath -DestinationPath $expandedPath -Force

    Copy-Texture `
        -Candidates @("assets\minecraft\textures\block\chiseled_bookshelf_empty.png") `
        -Destination "chiseled_bookshelf_empty.png" `
        -FallbackName "chiseled_bookshelf_empty.png" `
        -FallbackPathPattern "textures[\\/]block" | Out-Null

    Copy-Texture `
        -Candidates @("assets\minecraft\textures\block\chiseled_bookshelf_occupied.png") `
        -Destination "chiseled_bookshelf_occupied.png" `
        -FallbackName "chiseled_bookshelf_occupied.png" `
        -FallbackPathPattern "textures[\\/]block" | Out-Null

    Copy-Texture `
        -Candidates @("assets\minecraft\textures\block\stone_bricks.png") `
        -Destination "stone_bricks.png" `
        -FallbackName "stone_bricks.png" `
        -FallbackPathPattern "textures[\\/]block" | Out-Null

    # Import every selectable app background from the same official client
    # jar as the bookshelf and GUI textures. A data table keeps the app's
    # filenames stable even where Minecraft uses a different source name
    # (for example smooth quartz uses the quartz block bottom texture).
    $backgroundTextureImports = @(
        [pscustomobject]@{ Destination = "stone.png"; Sources = @("stone.png") },
        [pscustomobject]@{ Destination = "cobblestone.png"; Sources = @("cobblestone.png") },
        [pscustomobject]@{ Destination = "dirt.png"; Sources = @("dirt.png") },
        [pscustomobject]@{ Destination = "sand.png"; Sources = @("sand.png") },
        [pscustomobject]@{ Destination = "sandstone.png"; Sources = @("sandstone.png") },
        [pscustomobject]@{ Destination = "netherrack.png"; Sources = @("netherrack.png") },
        [pscustomobject]@{ Destination = "end_stone.png"; Sources = @("end_stone.png") },
        [pscustomobject]@{ Destination = "obsidian.png"; Sources = @("obsidian.png") },
        [pscustomobject]@{ Destination = "quartz_block_side.png"; Sources = @("quartz_block_side.png", "quartz_block.png") },
        [pscustomobject]@{ Destination = "smooth_quartz.png"; Sources = @("quartz_block_bottom.png", "smooth_quartz.png", "smooth_quartz_block.png") },
        [pscustomobject]@{ Destination = "red_concrete.png"; Sources = @("red_concrete.png") },
        [pscustomobject]@{ Destination = "orange_concrete.png"; Sources = @("orange_concrete.png") },
        [pscustomobject]@{ Destination = "yellow_concrete.png"; Sources = @("yellow_concrete.png") },
        [pscustomobject]@{ Destination = "lime_concrete.png"; Sources = @("lime_concrete.png") },
        [pscustomobject]@{ Destination = "green_concrete.png"; Sources = @("green_concrete.png") },
        [pscustomobject]@{ Destination = "cyan_concrete.png"; Sources = @("cyan_concrete.png") },
        [pscustomobject]@{ Destination = "light_blue_concrete.png"; Sources = @("light_blue_concrete.png") },
        [pscustomobject]@{ Destination = "blue_concrete.png"; Sources = @("blue_concrete.png") },
        [pscustomobject]@{ Destination = "purple_concrete.png"; Sources = @("purple_concrete.png") },
        [pscustomobject]@{ Destination = "magenta_concrete.png"; Sources = @("magenta_concrete.png") },
        [pscustomobject]@{ Destination = "pink_concrete.png"; Sources = @("pink_concrete.png") },
        [pscustomobject]@{ Destination = "brown_concrete.png"; Sources = @("brown_concrete.png") },
        [pscustomobject]@{ Destination = "white_concrete.png"; Sources = @("white_concrete.png") },
        [pscustomobject]@{ Destination = "light_gray_concrete.png"; Sources = @("light_gray_concrete.png") },
        [pscustomobject]@{ Destination = "gray_concrete.png"; Sources = @("gray_concrete.png") },
        [pscustomobject]@{ Destination = "black_concrete.png"; Sources = @("black_concrete.png") },
        [pscustomobject]@{ Destination = "oak_planks.png"; Sources = @("oak_planks.png") },
        [pscustomobject]@{ Destination = "spruce_planks.png"; Sources = @("spruce_planks.png") },
        [pscustomobject]@{ Destination = "birch_planks.png"; Sources = @("birch_planks.png") },
        [pscustomobject]@{ Destination = "jungle_planks.png"; Sources = @("jungle_planks.png") },
        [pscustomobject]@{ Destination = "acacia_planks.png"; Sources = @("acacia_planks.png") },
        [pscustomobject]@{ Destination = "dark_oak_planks.png"; Sources = @("dark_oak_planks.png") },
        [pscustomobject]@{ Destination = "mangrove_planks.png"; Sources = @("mangrove_planks.png") },
        [pscustomobject]@{ Destination = "cherry_planks.png"; Sources = @("cherry_planks.png") },
        [pscustomobject]@{ Destination = "bamboo_planks.png"; Sources = @("bamboo_planks.png") },
        [pscustomobject]@{ Destination = "pale_oak_planks.png"; Sources = @("pale_oak_planks.png") },
        [pscustomobject]@{ Destination = "crimson_planks.png"; Sources = @("crimson_planks.png") },
        [pscustomobject]@{ Destination = "warped_planks.png"; Sources = @("warped_planks.png") },
        [pscustomobject]@{ Destination = "bookshelf.png"; Sources = @("bookshelf.png") },
        [pscustomobject]@{ Destination = "iron_block.png"; Sources = @("iron_block.png") },
        [pscustomobject]@{ Destination = "copper_block.png"; Sources = @("copper_block.png") },
        [pscustomobject]@{ Destination = "gold_block.png"; Sources = @("gold_block.png") },
        [pscustomobject]@{ Destination = "diamond_block.png"; Sources = @("diamond_block.png") },
        [pscustomobject]@{ Destination = "netherite_block.png"; Sources = @("netherite_block.png") }
    )
    foreach ($backgroundTexture in $backgroundTextureImports) {
        $sourceCandidates = @(
            $backgroundTexture.Sources |
                ForEach-Object { "assets\minecraft\textures\block\" + $_ }
        )
        Copy-Texture `
            -Candidates $sourceCandidates `
            -Destination $backgroundTexture.Destination `
            -FallbackName $backgroundTexture.Sources[0] `
            -FallbackPathPattern "textures[\\/]block" | Out-Null
    }

    $legacyWritableBookName = @("writable", "_book.png") -join ""
    Copy-Texture `
        -Candidates @(
            ("assets\minecraft\textures\item\" + $legacyWritableBookName),
            "assets\minecraft\textures\item\book_and_quill.png"
        ) `
        -Destination "book_and_quil.png" `
        -FallbackName $legacyWritableBookName `
        -FallbackPathPattern "textures[\\/]item" | Out-Null

    Copy-Texture `
        -Candidates @("assets\minecraft\textures\gui\book.png") `
        -Destination "book.png" `
        -FallbackName "book.png" `
        -FallbackPathPattern "textures[\\/]gui" | Out-Null

    Copy-Texture `
        -Candidates @(
            "assets\minecraft\textures\misc\enchanted_glint_item.png",
            "assets\minecraft\textures\misc\enchanted_item_glint.png"
        ) `
        -Destination "enchanted_glint_item.png" `
        -FallbackName "enchanted_glint_item.png" `
        -FallbackPathPattern "textures[\\/]misc" | Out-Null

    foreach ($widgetTexture in @(
        "button.png",
        "button_highlighted.png",
        "button_disabled.png",
        "page_forward.png",
        "page_forward_highlighted.png",
        "page_backward.png",
        "page_backward_highlighted.png"
    )) {
        Copy-Texture `
            -Candidates @("assets\minecraft\textures\gui\sprites\widget\" + $widgetTexture) `
            -Destination $widgetTexture `
            -FallbackName $widgetTexture `
            -FallbackPathPattern "textures[\\/]gui[\\/]sprites[\\/]widget" | Out-Null
    }

    $asciiTexture = Copy-Texture `
        -Candidates @("assets\minecraft\textures\font\ascii.png") `
        -Destination "font_ascii_source.png" `
        -FallbackName "ascii.png" `
        -FallbackPathPattern "textures[\\/]font"

    $versionId = Split-Path (Split-Path $JarPath -Parent) -Leaf
    $versionMetadataPath = Join-Path $minecraftRoot ("versions\" + $versionId + "\" + $versionId + ".json")
    $assetIndex = $null

    if (Test-Path $versionMetadataPath) {
        $versionMetadata = Get-Content $versionMetadataPath -Raw | ConvertFrom-Json
        if ($versionMetadata.assetIndex.id) {
            $assetIndexPath = Join-Path $minecraftRoot ("assets\indexes\" + $versionMetadata.assetIndex.id + ".json")
            if (Test-Path $assetIndexPath) {
                $assetIndex = Get-Content $assetIndexPath -Raw | ConvertFrom-Json
            }
        }
    }

    if (-not $assetIndex) {
        $assetIndexDirectory = Join-Path $minecraftRoot "assets\indexes"
        if (Test-Path $assetIndexDirectory) {
            $newestIndex = Get-ChildItem $assetIndexDirectory -Filter "*.json" -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($newestIndex) {
                $assetIndex = Get-Content $newestIndex.FullName -Raw | ConvertFrom-Json
            }
        }
    }

    $soundRegistry = $null
    $soundRegistryPath = Join-Path $expandedPath "assets\minecraft\sounds.json"
    if (Test-Path $soundRegistryPath) {
        $soundRegistry = Get-Content $soundRegistryPath -Raw | ConvertFrom-Json
    } elseif ($assetIndex) {
        # Modern clients commonly keep sounds.json in the hashed asset store
        # instead of the client jar. Resolve it through the selected index so
        # event names map to the exact filenames used by that game version.
        $indexedSoundRegistry = Get-IndexedAssetFile `
            -AssetIndex $assetIndex `
            -Candidates @("minecraft/sounds.json") `
            -NamePattern "(^|/)sounds\.json$"
        if ($indexedSoundRegistry) {
            $soundRegistry = Get-Content $indexedSoundRegistry -Raw | ConvertFrom-Json
        }
    }

    $pageTurnCandidates = @(
        Get-SoundEventCandidates `
            -SoundRegistry $soundRegistry `
            -EventNames @("item.book.page_turn", "item.book.put")
    ) + @(
        "minecraft/sounds/item/book/open_flip1.ogg",
        "minecraft/sounds/item/book/open_flip2.ogg",
        "minecraft/sounds/item/book/open_flip3.ogg",
        "minecraft/sounds/item/book/close_put1.ogg",
        "minecraft/sounds/item/book/close_put2.ogg",
        "minecraft/sounds/item/book/page_turn.ogg",
        "minecraft/sounds/item/book/page_turn1.ogg",
        "minecraft/sounds/item/book/page_turn2.ogg",
        "minecraft/sounds/item/book/page_turn3.ogg",
        "minecraft/sounds/random/page_turn1.ogg"
    )
    $pageTurnVariantCandidates = @(
        $pageTurnCandidates |
            Where-Object {
                $_ -match "(?:open[_-]?flip|page[_-]?turn|turn[_-]?page|book[_-]?page)"
            } |
            Select-Object -Unique
    )

    $insertCandidates = @(
        Get-SoundEventCandidates `
            -SoundRegistry $soundRegistry `
            -EventNames @("block.chiseled_bookshelf.insert", "block.chiseled_bookshelf.insert.enchanted")
    ) + @("minecraft/sounds/block/chiseled_bookshelf/insert1.ogg")

    $pickupCandidates = @(
        Get-SoundEventCandidates `
            -SoundRegistry $soundRegistry `
            -EventNames @("block.chiseled_bookshelf.pickup", "block.chiseled_bookshelf.pickup.enchanted")
    ) + @("minecraft/sounds/block/chiseled_bookshelf/pickup1.ogg")

    $buttonCandidates = @(
        Get-SoundEventCandidates `
            -SoundRegistry $soundRegistry `
            -EventNames @("ui.button.click")
    ) + @("minecraft/sounds/random/click.ogg", "minecraft/sounds/ui/button/click.ogg")

    # Music lives in Minecraft's hashed asset object store. Import a calm
    # overworld rotation plus contextual Nether and End tracks. Current
    # releases use descriptive filenames; legacy candidates keep the importer
    # compatible with older official Java installations.
    foreach ($musicPattern in @("music_*.ogg", "nether_*.ogg", "end_*.ogg")) {
        Get-ChildItem $soundDestination -Filter $musicPattern -File -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }
    $musicImports = @(
        [pscustomobject]@{
            Destination = "music_minecraft.ogg"
            Sources = @("minecraft/sounds/music/game/minecraft.ogg", "minecraft/sounds/music/game/calm1.ogg")
            Pattern = "sounds/music/game/(?:minecraft|calm1)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_clark.ogg"
            Sources = @("minecraft/sounds/music/game/clark.ogg", "minecraft/sounds/music/game/calm2.ogg")
            Pattern = "sounds/music/game/(?:clark|calm2)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_sweden.ogg"
            Sources = @("minecraft/sounds/music/game/sweden.ogg", "minecraft/sounds/music/game/calm3.ogg")
            Pattern = "sounds/music/game/(?:sweden|calm3)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_subwoofer_lullaby.ogg"
            Sources = @("minecraft/sounds/music/game/subwoofer_lullaby.ogg", "minecraft/sounds/music/game/hal1.ogg")
            Pattern = "sounds/music/game/(?:subwoofer_lullaby|hal1)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_living_mice.ogg"
            Sources = @("minecraft/sounds/music/game/living_mice.ogg", "minecraft/sounds/music/game/hal2.ogg")
            Pattern = "sounds/music/game/(?:living_mice|hal2)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_haggstrom.ogg"
            Sources = @("minecraft/sounds/music/game/haggstrom.ogg", "minecraft/sounds/music/game/hal3.ogg")
            Pattern = "sounds/music/game/(?:haggstrom|hal3)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_danny.ogg"
            Sources = @("minecraft/sounds/music/game/danny.ogg", "minecraft/sounds/music/game/hal4.ogg")
            Pattern = "sounds/music/game/(?:danny|hal4)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_key.ogg"
            Sources = @("minecraft/sounds/music/game/key.ogg", "minecraft/sounds/music/game/nuance1.ogg")
            Pattern = "sounds/music/game/(?:key|nuance1)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_oxygene.ogg"
            Sources = @("minecraft/sounds/music/game/oxygene.ogg", "minecraft/sounds/music/game/nuance2.ogg")
            Pattern = "sounds/music/game/(?:oxygene|nuance2)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_dry_hands.ogg"
            Sources = @("minecraft/sounds/music/game/dry_hands.ogg", "minecraft/sounds/music/game/piano1.ogg")
            Pattern = "sounds/music/game/(?:dry_hands|piano1)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_wet_hands.ogg"
            Sources = @("minecraft/sounds/music/game/wet_hands.ogg", "minecraft/sounds/music/game/piano2.ogg")
            Pattern = "sounds/music/game/(?:wet_hands|piano2)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "music_mice_on_venus.ogg"
            Sources = @("minecraft/sounds/music/game/mice_on_venus.ogg", "minecraft/sounds/music/game/piano3.ogg")
            Pattern = "sounds/music/game/(?:mice_on_venus|piano3)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "nether_concrete_halls.ogg"
            Sources = @("minecraft/sounds/music/game/nether/concrete_halls.ogg", "minecraft/sounds/music/game/nether/nether1.ogg")
            Pattern = "sounds/music/game/nether/(?:concrete_halls|nether1)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "nether_dead_voxel.ogg"
            Sources = @("minecraft/sounds/music/game/nether/dead_voxel.ogg", "minecraft/sounds/music/game/nether/nether2.ogg")
            Pattern = "sounds/music/game/nether/(?:dead_voxel|nether2)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "nether_warmth.ogg"
            Sources = @("minecraft/sounds/music/game/nether/warmth.ogg", "minecraft/sounds/music/game/nether/nether3.ogg")
            Pattern = "sounds/music/game/nether/(?:warmth|nether3)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "nether_ballad_of_the_cats.ogg"
            Sources = @("minecraft/sounds/music/game/nether/ballad_of_the_cats.ogg", "minecraft/sounds/music/game/nether/nether4.ogg")
            Pattern = "sounds/music/game/nether/(?:ballad_of_the_cats|nether4)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "nether_chrysopoeia.ogg"
            Sources = @("minecraft/sounds/music/game/nether/crimson_forest/chrysopoeia.ogg")
            Pattern = "sounds/music/game/nether/crimson_forest/chrysopoeia\.ogg$"
        },
        [pscustomobject]@{
            Destination = "nether_rubedo.ogg"
            Sources = @("minecraft/sounds/music/game/nether/nether_wastes/rubedo.ogg")
            Pattern = "sounds/music/game/nether/nether_wastes/rubedo\.ogg$"
        },
        [pscustomobject]@{
            Destination = "nether_so_below.ogg"
            Sources = @("minecraft/sounds/music/game/nether/soulsand_valley/so_below.ogg")
            Pattern = "sounds/music/game/nether/soulsand_valley/so_below\.ogg$"
        },
        [pscustomobject]@{
            Destination = "end_the_end.ogg"
            Sources = @("minecraft/sounds/music/game/end/the_end.ogg", "minecraft/sounds/music/game/end/end.ogg")
            Pattern = "sounds/music/game/end/(?:the_end|end)\.ogg$"
        },
        [pscustomobject]@{
            Destination = "end_alpha.ogg"
            Sources = @("minecraft/sounds/music/game/end/alpha.ogg", "minecraft/sounds/music/game/end/credits.ogg")
            Pattern = "sounds/music/game/end/(?:alpha|credits)\.ogg$"
        }
    )
    foreach ($musicTrack in $musicImports) {
        Copy-Sound `
            -AssetIndex $assetIndex `
            -Candidates $musicTrack.Sources `
            -NamePattern $musicTrack.Pattern `
            -Destination $musicTrack.Destination
    }

    Copy-Sound `
        -AssetIndex $assetIndex `
        -Candidates $pageTurnCandidates `
        -NamePattern "sounds/.*(?:open[_-]?flip|page[_-]?turn|turn[_-]?page|book[/_-]?(?:put|page))[^/]*\.ogg$" `
        -Destination "page_turn.ogg"

    # Import every distinct page-rustle sample exposed by the selected game
    # version. The Dart sound service randomizes these and avoids immediate
    # repeats. Older versions with only one sample use pitch variation.
    $oldPageTurnVariants = Get-ChildItem $soundDestination `
        -Filter "page_turn[0-9]*.ogg" `
        -File `
        -ErrorAction SilentlyContinue
    foreach ($oldVariant in $oldPageTurnVariants) {
        Remove-Item $oldVariant.FullName -Force
    }
    $seenVariantSources = New-Object System.Collections.Generic.HashSet[string]
    $variantNumber = 1
    foreach ($candidateName in $pageTurnVariantCandidates) {
        $variantSource = Get-IndexedAssetFile `
            -AssetIndex $assetIndex `
            -Candidates @($candidateName) `
            -NamePattern $null
        if (-not $variantSource) {
            $variantSource = Get-IndexedAssetAcrossInstalledIndexes `
                -Candidates @($candidateName) `
                -NamePattern $null
        }
        if (-not $variantSource -or -not $seenVariantSources.Add([string]$variantSource)) {
            continue
        }

        $variantDestination = "page_turn" + $variantNumber + ".ogg"
        Copy-Item $variantSource (Join-Path $soundDestination $variantDestination) -Force
        $importedSounds.Add($variantDestination)
        Write-Host ("Imported sound variant: " + $variantDestination) -ForegroundColor Green
        $variantNumber++
        if ($variantNumber -gt 8) {
            break
        }
    }

    Copy-Sound `
        -AssetIndex $assetIndex `
        -Candidates $insertCandidates `
        -NamePattern "sounds/block/chiseled_bookshelf/insert[0-9]*\.ogg$" `
        -Destination "insert.ogg"

    Copy-Sound `
        -AssetIndex $assetIndex `
        -Candidates $pickupCandidates `
        -NamePattern "sounds/block/chiseled_bookshelf/pickup[0-9]*\.ogg$" `
        -Destination "pickup.ogg"

    Copy-Sound `
        -AssetIndex $assetIndex `
        -Candidates $buttonCandidates `
        -NamePattern "sounds/.*(?:button[/_-]?click|click)\.ogg$" `
        -Destination "click.ogg"

    if ($asciiTexture) {
        # Try every common Windows Python entry point. A Microsoft Store
        # python.exe alias can exist even when the working installation is
        # available only through the py launcher.
        $pythonCandidates = New-Object System.Collections.Generic.List[object]
        foreach ($commandName in @("py", "python", "python3")) {
            $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($command) {
                $prefix = @()
                if ($commandName -eq "py") {
                    $prefix = @("-3")
                }
                $pythonCandidates.Add([pscustomobject]@{
                    Display = $commandName
                    Path = $command.Source
                    Prefix = $prefix
                })
            }
        }

        $workingPython = $null
        $usablePython = $null
        foreach ($candidate in $pythonCandidates) {
            $pythonWorks = (Invoke-PythonCommand `
                -Candidate $candidate `
                -Arguments @("-c", "import sys") `
                -Quiet) -eq 0
            if (-not $pythonWorks) {
                continue
            }

            if (-not $usablePython) {
                $usablePython = $candidate
            }

            $modulesWork = (Invoke-PythonCommand `
                -Candidate $candidate `
                -Arguments @("-c", "import PIL, fontTools") `
                -Quiet) -eq 0
            if ($modulesWork) {
                $workingPython = $candidate
                break
            }
        }

        if ($workingPython) {
            $fontScript = Join-Path $PSScriptRoot "build_minecraft_font.py"
            # Keep the proportional UI font and generate a separate fixed-
            # advance font for the exact 20 x 15 Book & Quill editor grid.
            $fontOutput = Join-Path $fontDestination "minecraft_local_v2.ttf"
            $uiFontExitCode = Invoke-PythonCommand `
                -Candidate $workingPython `
                -Arguments @($fontScript, "--source", $asciiTexture, "--output", $fontOutput)
            $gridFontOutput = Join-Path $fontDestination "minecraft_book_grid_v3.ttf"
            $gridFontExitCode = Invoke-PythonCommand `
                -Candidate $workingPython `
                -Arguments @(
                    $fontScript,
                    "--source",
                    $asciiTexture,
                    "--output",
                    $gridFontOutput,
                    "--monospace"
                )
            $fontImported = `
                $uiFontExitCode -eq 0 -and `
                $gridFontExitCode -eq 0 -and `
                (Test-Path $fontOutput) -and `
                (Test-Path $gridFontOutput)
            if (-not $fontImported) {
                Write-Host "Minecraft font conversion failed; the bundled pixel fallback remains active." -ForegroundColor DarkYellow
            }
        } elseif ($usablePython) {
            $installCommand = if ($usablePython.Display -eq "py") {
                "py -3 -m pip install pillow fonttools"
            } else {
                $usablePython.Display + " -m pip install pillow fonttools"
            }
            Write-Host "Minecraft font conversion needs Pillow and fontTools in the detected Python environment." -ForegroundColor DarkYellow
            Write-Host ("Run: " + $installCommand) -ForegroundColor Yellow
            Write-Host "Then run this importer again. The bundled pixel fallback remains active for now." -ForegroundColor Yellow
        } else {
            Write-Host "Python was not found, so the bundled pixel fallback font remains active." -ForegroundColor DarkYellow
        }
    }

    $status = @{
        assetPipelineVersion = 10
        importedAt = (Get-Date).ToString("o")
        sourceJar = $JarPath
        textures = @($importedTextures)
        sounds = @($importedSounds)
        minecraftFontGenerated = $fontImported
    }
    $status | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $destinationRoot "import_status.json") -Encoding UTF8
}
finally {
    if (Test-Path $temporaryRoot) {
        Remove-Item -Path $temporaryRoot -Recurse -Force
    }
}

Write-Host ""
Write-Host "Minecraft asset import finished." -ForegroundColor Cyan
Write-Host ("Textures imported: " + $importedTextures.Count)
Write-Host ("Sounds imported: " + $importedSounds.Count)
Write-Host ("Minecraft font generated: " + $fontImported)
Write-Host "Stop the running app and launch it again so Flutter bundles the new resources." -ForegroundColor Cyan
