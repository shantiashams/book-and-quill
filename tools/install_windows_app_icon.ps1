$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePng = Join-Path $projectRoot "assets\imported\textures\book_and_quil.png"
$resourceRoot = Join-Path $projectRoot "windows\runner\resources"
$iconPath = Join-Path $resourceRoot "app_icon.ico"

if (-not (Test-Path $sourcePng)) {
    throw "The Book and Quill icon texture is missing: $sourcePng"
}
if (-not (Test-Path (Join-Path $projectRoot "windows\runner"))) {
    throw "The Windows runner does not exist yet. Run tools\setup_windows.ps1 first."
}

Add-Type -AssemblyName System.Drawing
[void][System.IO.Directory]::CreateDirectory($resourceRoot)

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = New-Object System.Collections.ArrayList
$sourceImage = [System.Drawing.Image]::FromFile($sourcePng)
try {
    foreach ($size in $sizes) {
        $bitmap = New-Object System.Drawing.Bitmap -ArgumentList @(
            $size,
            $size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
                $destination = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, $size, $size
                $graphics.DrawImage(
                    $sourceImage,
                    $destination,
                    0,
                    0,
                    $sourceImage.Width,
                    $sourceImage.Height,
                    [System.Drawing.GraphicsUnit]::Pixel
                )
            } finally {
                $graphics.Dispose()
            }

            $pngStream = New-Object System.IO.MemoryStream
            try {
                $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
                [void]$frames.Add($pngStream.ToArray())
            } finally {
                $pngStream.Dispose()
            }
        } finally {
            $bitmap.Dispose()
        }
    }
} finally {
    $sourceImage.Dispose()
}

$iconStream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter -ArgumentList $iconStream
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$frames.Count)

    $dataOffset = 6 + (16 * $frames.Count)
    for ($index = 0; $index -lt $frames.Count; $index++) {
        $size = $sizes[$index]
        $frame = [byte[]]$frames[$index]
        $dimension = if ($size -ge 256) { [byte]0 } else { [byte]$size }
        $writer.Write($dimension)
        $writer.Write($dimension)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$frame.Length)
        $writer.Write([UInt32]$dataOffset)
        $dataOffset += $frame.Length
    }

    foreach ($frameValue in $frames) {
        $writer.Write([byte[]]$frameValue)
    }
    $writer.Flush()
    [System.IO.File]::WriteAllBytes($iconPath, $iconStream.ToArray())
} finally {
    $writer.Dispose()
    $iconStream.Dispose()
}

Write-Host "Windows app icon updated from book_and_quil.png." -ForegroundColor Green
