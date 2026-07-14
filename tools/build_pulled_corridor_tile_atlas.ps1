param(
    [string]$ProjectRoot = "D:\Godot\xybotsResearch\Project\xybots-research",
    [string]$SourceGlobRoot = "D:\Godot\xybotsResearch\exports\photoshop",
    [int]$AtlasWidth = 1024,
    [int]$Padding = 2,
    [int]$MinimumArea = 12
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$analysisRoot = Join-Path $ProjectRoot "analysis\wall_reconstruction"
$outRoot = Join-Path $analysisRoot "environment_pulled_tile_atlas"
$chunkRoot = Join-Path $outRoot "chunks"
$sourceCopyRoot = Join-Path $outRoot "source_images"
$atlasPath = Join-Path $outRoot "pulled_corridor_tiles_atlas.png"
$jsonPath = Join-Path $outRoot "pulled_corridor_tiles_atlas.json"
$csvPath = Join-Path $outRoot "pulled_corridor_tiles_atlas.csv"
$readmePath = Join-Path $outRoot "README.md"

if (Test-Path -LiteralPath $outRoot) {
    Remove-Item -LiteralPath $outRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $chunkRoot | Out-Null
New-Item -ItemType Directory -Force -Path $sourceCopyRoot | Out-Null

function Get-RelativePath([string]$Path) {
    $fullProject = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($fullProject, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($fullProject.Length).TrimStart('\').Replace('\', '/')
    }
    return $fullPath.Replace('\', '/')
}

function Test-Foreground([System.Drawing.Color]$Pixel) {
    if ($Pixel.A -eq 0) {
        return $false
    }
    # Treat the Photoshop work area's white background as empty, but preserve
    # black corridor voids and dark line art as real pixels.
    return -not ($Pixel.R -ge 245 -and $Pixel.G -ge 245 -and $Pixel.B -ge 245)
}

function Get-BitmapHash([System.Drawing.Bitmap]$Bitmap) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = New-Object byte[] ($Bitmap.Width * $Bitmap.Height * 4)
        $i = 0
        for ($y = 0; $y -lt $Bitmap.Height; $y++) {
            for ($x = 0; $x -lt $Bitmap.Width; $x++) {
                $pixel = $Bitmap.GetPixel($x, $y)
                $bytes[$i++] = $pixel.R
                $bytes[$i++] = $pixel.G
                $bytes[$i++] = $pixel.B
                $bytes[$i++] = $pixel.A
            }
        }
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Components([System.Drawing.Bitmap]$Bitmap) {
    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $visited = New-Object bool[] ($width * $height)
    $components = New-Object System.Collections.Generic.List[object]

    for ($startY = 0; $startY -lt $height; $startY++) {
        for ($startX = 0; $startX -lt $width; $startX++) {
            $startIndex = $startY * $width + $startX
            if ($visited[$startIndex]) {
                continue
            }
            $visited[$startIndex] = $true
            if (-not (Test-Foreground $Bitmap.GetPixel($startX, $startY))) {
                continue
            }

            $queue = New-Object System.Collections.Generic.Queue[object]
            $queue.Enqueue([pscustomobject]@{ x = $startX; y = $startY })
            $minX = $startX
            $maxX = $startX
            $minY = $startY
            $maxY = $startY
            $area = 0

            while ($queue.Count -gt 0) {
                $p = $queue.Dequeue()
                $area++
                if ($p.x -lt $minX) { $minX = $p.x }
                if ($p.x -gt $maxX) { $maxX = $p.x }
                if ($p.y -lt $minY) { $minY = $p.y }
                if ($p.y -gt $maxY) { $maxY = $p.y }

                foreach ($delta in @(@(-1, 0), @(1, 0), @(0, -1), @(0, 1))) {
                    $nx = $p.x + $delta[0]
                    $ny = $p.y + $delta[1]
                    if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $width -or $ny -ge $height) {
                        continue
                    }
                    $nIndex = $ny * $width + $nx
                    if ($visited[$nIndex]) {
                        continue
                    }
                    $visited[$nIndex] = $true
                    if (Test-Foreground $Bitmap.GetPixel($nx, $ny)) {
                        $queue.Enqueue([pscustomobject]@{ x = $nx; y = $ny })
                    }
                }
            }

            if ($area -ge $MinimumArea) {
                $components.Add([pscustomobject]@{
                    x = $minX
                    y = $minY
                    width = $maxX - $minX + 1
                    height = $maxY - $minY + 1
                    area = $area
                })
            }
        }
    }

    return $components | Sort-Object y, x
}

function New-ComponentBitmap([System.Drawing.Bitmap]$Source, [object]$Component) {
    $crop = New-Object System.Drawing.Bitmap $Component.width, $Component.height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $Component.height; $y++) {
        for ($x = 0; $x -lt $Component.width; $x++) {
            $pixel = $Source.GetPixel($Component.x + $x, $Component.y + $y)
            if (Test-Foreground $pixel) {
                $crop.SetPixel($x, $y, $pixel)
            }
            else {
                $crop.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
            }
        }
    }
    return $crop
}

$sourceFiles = Get-ChildItem -Path $SourceGlobRoot -Filter "corridor_view_*_tiles.png" -File | Sort-Object Name
$chunks = New-Object System.Collections.Generic.List[object]
$seen = @{}

foreach ($source in $sourceFiles) {
    $sourceCopyPath = Join-Path $sourceCopyRoot $source.Name
    Copy-Item -LiteralPath $source.FullName -Destination $sourceCopyPath -Force

    $bitmap = [System.Drawing.Bitmap]::FromFile($source.FullName)
    try {
        $componentIndex = 0
        foreach ($component in (Get-Components $bitmap)) {
            $componentIndex++
            $componentBitmap = New-ComponentBitmap $bitmap $component
            $hash = Get-BitmapHash $componentBitmap
            if ($seen.ContainsKey($hash)) {
                $seen[$hash].source_count++
                $componentBitmap.Dispose()
                continue
            }

            $index = $chunks.Count + 1
            $chunkName = "pulled_tile_{0:D4}.png" -f $index
            $chunkPath = Join-Path $chunkRoot $chunkName
            $componentBitmap.Save($chunkPath, [System.Drawing.Imaging.ImageFormat]::Png)

            $chunk = [pscustomobject]@{
                index = $index
                name = [System.IO.Path]::GetFileNameWithoutExtension($chunkName)
                width = $componentBitmap.Width
                height = $componentBitmap.Height
                atlas_x = 0
                atlas_y = 0
                atlas_w = $componentBitmap.Width
                atlas_h = $componentBitmap.Height
                source = $source.FullName.Replace('\', '/')
                source_copy = Get-RelativePath $sourceCopyPath
                source_name = $source.Name
                source_component = $componentIndex
                source_x = $component.x
                source_y = $component.y
                source_w = $component.width
                source_h = $component.height
                area = $component.area
                source_count = 1
                hash = $hash
                image = Get-RelativePath $chunkPath
            }
            $chunks.Add($chunk)
            $seen[$hash] = $chunk
            $componentBitmap.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

$x = $Padding
$y = $Padding
$rowHeight = 0
foreach ($chunk in $chunks) {
    if (($x + $chunk.width + $Padding) -gt $AtlasWidth) {
        $x = $Padding
        $y += $rowHeight + $Padding
        $rowHeight = 0
    }
    $chunk.atlas_x = $x
    $chunk.atlas_y = $y
    $x += $chunk.width + $Padding
    if ($chunk.height -gt $rowHeight) {
        $rowHeight = $chunk.height
    }
}

$atlasHeight = [Math]::Max(1, $y + $rowHeight + $Padding)
$atlas = New-Object System.Drawing.Bitmap $AtlasWidth, $atlasHeight, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($atlas)
try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    foreach ($chunk in $chunks) {
        $chunkBitmap = [System.Drawing.Bitmap]::FromFile((Join-Path $ProjectRoot $chunk.image.Replace('/', '\')))
        try {
            $graphics.DrawImage($chunkBitmap, $chunk.atlas_x, $chunk.atlas_y, $chunk.width, $chunk.height)
        }
        finally {
            $chunkBitmap.Dispose()
        }
    }
}
finally {
    $graphics.Dispose()
}
$atlas.Save($atlasPath, [System.Drawing.Imaging.ImageFormat]::Png)
$atlas.Dispose()

$json = [ordered]@{
    atlas = Get-RelativePath $atlasPath
    width = $AtlasWidth
    height = $atlasHeight
    padding = $Padding
    source_files_scanned = $sourceFiles.Count
    unique_chunks = $chunks.Count
    chunks = $chunks
}
$json | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

$csvRows = @()
$csvRows += "index,name,width,height,atlas_x,atlas_y,atlas_w,atlas_h,source_name,source_copy,source_component,source_x,source_y,source_w,source_h,area,source_count,hash,image"
foreach ($chunk in $chunks) {
    $csvRows += ('{0},"{1}",{2},{3},{4},{5},{6},{7},"{8}",{9},{10},{11},{12},{13},{14},{15},{16},"{17}"' -f
        $chunk.index, $chunk.name, $chunk.width, $chunk.height, $chunk.atlas_x, $chunk.atlas_y,
        $chunk.atlas_w, $chunk.atlas_h, $chunk.source_name, $chunk.source_copy, $chunk.source_component,
        $chunk.source_x, $chunk.source_y, $chunk.source_w, $chunk.source_h, $chunk.area,
        $chunk.source_count, $chunk.hash, $chunk.image)
}
$csvRows | Set-Content -Path $csvPath -Encoding UTF8

@"
# Pulled Corridor Tile Atlas

This atlas is built from manually pulled-apart corridor breakdown images named
`corridor_view_*_tiles.png`.

The extractor treats white or transparent pixels as empty workspace and extracts
each separated non-white connected component as a reusable chunk. This matches
the manual Photoshop workflow of pulling wall, floor, ceiling, and door pieces
out of a corridor view.

Files:

- `pulled_corridor_tiles_atlas.png` - packed atlas
- `pulled_corridor_tiles_atlas.json` - atlas rectangles and source positions
- `pulled_corridor_tiles_atlas.csv` - spreadsheet-friendly atlas data
- `chunks/` - individual extracted chunks
- `source_images/` - copied source breakdown images

Current source files scanned: $($sourceFiles.Count)
Current unique chunks: $($chunks.Count)
"@ | Set-Content -Path $readmePath -Encoding UTF8

Write-Host "Source files scanned: $($sourceFiles.Count)"
Write-Host "Unique chunks: $($chunks.Count)"
Write-Host "Atlas: $atlasPath"
