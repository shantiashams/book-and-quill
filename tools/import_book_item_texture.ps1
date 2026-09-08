param(
    [string]$MinecraftRoot,
    [string]$ClientJar
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $projectRoot "assets\imported\textures\book_item.png"
$jarMember = "assets/minecraft/textures/item/book.png"

if ([string]::IsNullOrWhiteSpace($MinecraftRoot)) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw "APPDATA is unavailable. Pass -MinecraftRoot with the path to your .minecraft folder."
    }
    $MinecraftRoot = Join-Path $env:APPDATA ".minecraft"
}

if ([string]::IsNullOrWhiteSpace($ClientJar)) {
    $versionsRoot = Join-Path $MinecraftRoot "versions"
    if (-not (Test-Path -LiteralPath $versionsRoot)) {
        throw "Minecraft versions folder was not found: $versionsRoot"
    }

    $jar = Get-ChildItem -LiteralPath $versionsRoot -Filter "*.jar" -File -Recurse |
        Where-Object { $_.Name -notlike "*-sources.jar" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $jar) {
        throw "No Minecraft Java client JAR was found below: $versionsRoot"
    }
    $ClientJar = $jar.FullName
}

if (-not (Test-Path -LiteralPath $ClientJar -PathType Leaf)) {
    throw "Minecraft client JAR was not found: $ClientJar"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ClientJar)

try {
    $entry = $archive.GetEntry($jarMember)
    if ($null -eq $entry) {
        throw "The selected Minecraft client does not contain: $jarMember"
    }

    $destinationDirectory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

    $source = $entry.Open()
    try {
        $target = [System.IO.File]::Create($destination)
        try {
            $source.CopyTo($target)
        }
        finally {
            $target.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }
}
finally {
    $archive.Dispose()
}

Write-Host "Imported Minecraft item texture: $destination"
Write-Host "The Book & Quill page GUI remains: assets\imported\textures\book.png"
