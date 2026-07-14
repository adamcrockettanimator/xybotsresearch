param(
    [string]$ProjectRoot = "D:\Godot\xybotsResearch\Project\xybots-research",
    [int]$AtlasWidth = 2048,
    [int]$Padding = 2
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$analysisRoot = Join-Path $ProjectRoot "analysis\wall_reconstruction"
$outRoot = Join-Path $analysisRoot "environment_chunk_atlas"
$chunkRoot = Join-Path $outRoot "chunks"
$atlasPath = Join-Path $outRoot "environment_chunks_atlas.png"
$jsonPath = Join-Path $outRoot "environment_chunks_atlas.json"
$csvPath = Join-Path $outRoot "environment_chunks_atlas.csv"
$readmePath = Join-Path $outRoot "README.md"

if (Test-Path -LiteralPath $outRoot) {
    Remove-Item -LiteralPath $outRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $chunkRoot | Out-Null

$zonesFull = @(
    @{ name = "ceiling";     x = 0;   y = 96;  w = 176; h = 40  },
    @{ name = "left_wall";   x = 0;   y = 120; w = 128; h = 120 },
    @{ name = "center_back"; x = 40;  y = 120; w = 136; h = 72  },
    @{ name = "right_wall";  x = 104; y = 120; w = 72;  h = 120 },
    @{ name = "floor";       x = 0;   y = 172; w = 176; h = 68  }
)

$zonesLower = @(
    @{ name = "left_wall";   x = 0;   y = 0;  w = 128; h = 120 },
    @{ name = "center_back"; x = 40;  y = 0;  w = 136; h = 72  },
    @{ name = "right_wall";  x = 104; y = 0;  w = 72;  h = 120 },
    @{ name = "floor";       x = 0;   y = 52; w = 176; h = 68  }
)

function Get-RelativePath([string]$Path) {
    $fullProject = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($fullProject, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($fullProject.Length).TrimStart('\').Replace('\', '/')
    }
    return $fullPath.Replace('\', '/')
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

function New-CropBitmap([System.Drawing.Bitmap]$Source, [hashtable]$Zone) {
    if (($Zone.x + $Zone.w) -gt $Source.Width -or ($Zone.y + $Zone.h) -gt $Source.Height) {
        return $null
    }

    $crop = New-Object System.Drawing.Bitmap $Zone.w, $Zone.h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($crop)
    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $dest = New-Object System.Drawing.Rectangle 0, 0, $Zone.w, $Zone.h
        $src = New-Object System.Drawing.Rectangle $Zone.x, $Zone.y, $Zone.w, $Zone.h
        $graphics.DrawImage($Source, $dest, $src, [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally {
        $graphics.Dispose()
    }
    return $crop
}

$sources = @()
Get-ChildItem -Path (Join-Path $analysisRoot "turn_recordings") -Recurse -Filter "key_*.png" |
    Sort-Object FullName |
    ForEach-Object {
        $sources += @{
            path = $_.FullName
            kind = "turn_keyframe"
            zones = $zonesFull
        }
    }

Get-ChildItem -Path (Join-Path $analysisRoot "unique_corridor_views") -Filter "*.png" |
    Sort-Object Name |
    ForEach-Object {
        $sources += @{
            path = $_.FullName
            kind = "settled_corridor_view"
            zones = $zonesLower
        }
    }

$chunks = New-Object System.Collections.Generic.List[object]
$seen = @{}
$sourceCount = 0

foreach ($sourceInfo in $sources) {
    $sourceCount++
    $sourceBitmap = [System.Drawing.Bitmap]::FromFile($sourceInfo.path)
    try {
        foreach ($zone in $sourceInfo.zones) {
            $crop = New-CropBitmap $sourceBitmap $zone
            if ($null -eq $crop) {
                continue
            }

            $hash = Get-BitmapHash $crop
            if ($seen.ContainsKey($hash)) {
                $seen[$hash].source_count++
                $crop.Dispose()
                continue
            }

            $index = $chunks.Count + 1
            $chunkName = "{0}_{1:D4}.png" -f $zone.name, $index
            $chunkPath = Join-Path $chunkRoot $chunkName
            $crop.Save($chunkPath, [System.Drawing.Imaging.ImageFormat]::Png)

            $chunk = [pscustomobject]@{
                index = $index
                name = [System.IO.Path]::GetFileNameWithoutExtension($chunkName)
                type = $zone.name
                width = $crop.Width
                height = $crop.Height
                atlas_x = 0
                atlas_y = 0
                atlas_w = $crop.Width
                atlas_h = $crop.Height
                source_kind = $sourceInfo.kind
                source = Get-RelativePath $sourceInfo.path
                source_x = $zone.x
                source_y = $zone.y
                source_w = $zone.w
                source_h = $zone.h
                hash = $hash
                image = Get-RelativePath $chunkPath
                source_count = 1
            }
            $chunks.Add($chunk)
            $seen[$hash] = $chunk
            $crop.Dispose()
        }
    }
    finally {
        $sourceBitmap.Dispose()
    }
}

$packedChunks = @($chunks | Sort-Object type, index)

$x = $Padding
$y = $Padding
$rowHeight = 0
foreach ($chunk in $packedChunks) {
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

$atlasHeight = $y + $rowHeight + $Padding
$atlas = New-Object System.Drawing.Bitmap $AtlasWidth, $atlasHeight, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($atlas)
try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    foreach ($chunk in $packedChunks) {
        $chunkBitmap = [System.Drawing.Bitmap]::FromFile((Join-Path $ProjectRoot $chunk.image.Replace('/', '\')))
        try {
            $dest = New-Object System.Drawing.Rectangle $chunk.atlas_x, $chunk.atlas_y, $chunk.width, $chunk.height
            $graphics.DrawImage($chunkBitmap, $dest, 0, 0, $chunk.width, $chunk.height, [System.Drawing.GraphicsUnit]::Pixel)
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
    source_images_scanned = $sources.Count
    unique_chunks = $chunks.Count
    chunk_types = ($packedChunks | Group-Object type | Sort-Object Name | ForEach-Object {
        [ordered]@{ type = $_.Name; count = $_.Count }
    })
    chunks = $packedChunks
}
$json | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

$csvRows = @()
$csvRows += "index,name,type,width,height,atlas_x,atlas_y,atlas_w,atlas_h,source_kind,source,source_x,source_y,source_w,source_h,source_count,hash,image"
foreach ($chunk in $packedChunks) {
    $csvRows += ('{0},"{1}",{2},{3},{4},{5},{6},{7},{8},{9},"{10}",{11},{12},{13},{14},{15},{16},"{17}"' -f
        $chunk.index,
        $chunk.name,
        $chunk.type,
        $chunk.width,
        $chunk.height,
        $chunk.atlas_x,
        $chunk.atlas_y,
        $chunk.atlas_w,
        $chunk.atlas_h,
        $chunk.source_kind,
        $chunk.source,
        $chunk.source_x,
        $chunk.source_y,
        $chunk.source_w,
        $chunk.source_h,
        $chunk.source_count,
        $chunk.hash,
        $chunk.image)
}
$csvRows | Set-Content -Path $csvPath -Encoding UTF8

$typeSummary = $chunks | Group-Object type | Sort-Object Name | ForEach-Object {
    "- {0}: {1}" -f $_.Name, $_.Count
}

@"
# Environment Chunk Atlas

This atlas is built from the wall reconstruction analysis images, not from raw
8x8 tiles. It crops larger reusable corridor chunks from:

- selected every-frame turn keyframes
- settled unique corridor view captures

Chunk families:

$($typeSummary -join "`n")

Files:

- `environment_chunks_atlas.png` - packed atlas image
- `environment_chunks_atlas.json` - atlas rectangles and source references
- `environment_chunks_atlas.csv` - spreadsheet-friendly atlas rectangles
- `chunks/` - individual deduped PNG chunks

These chunks intentionally preserve the captured pixels. Black areas are not
made transparent because the original art uses black both as void and as line
detail.
"@ | Set-Content -Path $readmePath -Encoding UTF8

Write-Host "Sources scanned: $($sources.Count)"
Write-Host "Unique chunks: $($chunks.Count)"
Write-Host "Atlas: $atlasPath"
