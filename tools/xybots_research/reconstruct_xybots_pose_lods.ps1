param(
  [string]$RomZip = 'D:\MAME\roms\xybots.zip',
  [string]$OutputRoot = 'D:\Godot\xybotsResearch\exports\sprites\reconstructed_pose_review\pose_0010_lods',
  [int]$StartTile = 0x0010,
  [int]$GapPx = 4
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$spriteLoads = @(
  @{ Name = '136054-1105.2e';  Offset = 0x000000 },
  @{ Name = '136054-1106.2ef'; Offset = 0x010000 },
  @{ Name = '136054-1107.2f';  Offset = 0x020000 },
  @{ Name = '136054-1108.2fj'; Offset = 0x030000 },
  @{ Name = '136054-1109.2jk'; Offset = 0x040000 },
  @{ Name = '136054-1110.2k';  Offset = 0x050000 },
  @{ Name = '136054-1111.2l';  Offset = 0x060000 }
)

$palette = @(
  [System.Drawing.Color]::FromArgb(0, 0, 0, 0),
  [System.Drawing.Color]::FromArgb(255, 0, 255, 0),
  [System.Drawing.Color]::FromArgb(255, 32, 56, 72),
  [System.Drawing.Color]::FromArgb(255, 0, 0, 96),
  [System.Drawing.Color]::FromArgb(255, 32, 32, 128),
  [System.Drawing.Color]::FromArgb(255, 72, 72, 176),
  [System.Drawing.Color]::FromArgb(255, 96, 0, 96),
  [System.Drawing.Color]::FromArgb(255, 176, 32, 104),
  [System.Drawing.Color]::FromArgb(255, 88, 88, 88),
  [System.Drawing.Color]::FromArgb(255, 152, 152, 152),
  [System.Drawing.Color]::FromArgb(255, 192, 192, 192),
  [System.Drawing.Color]::FromArgb(255, 176, 64, 64),
  [System.Drawing.Color]::FromArgb(255, 255, 168, 80),
  [System.Drawing.Color]::FromArgb(255, 232, 208, 88),
  [System.Drawing.Color]::FromArgb(255, 232, 128, 136),
  [System.Drawing.Color]::FromArgb(255, 232, 232, 232)
)

$lodSpecs = @(
  @{ Name = 'lod00_3x6'; Cols = 3; Rows = 6 },
  @{ Name = 'lod01_3x5'; Cols = 3; Rows = 5 },
  @{ Name = 'lod02_2x5'; Cols = 2; Rows = 5 },
  @{ Name = 'lod03_2x4'; Cols = 2; Rows = 4 },
  @{ Name = 'lod04_2x4'; Cols = 2; Rows = 4 },
  @{ Name = 'lod05_2x3'; Cols = 2; Rows = 3 },
  @{ Name = 'lod06_2x3'; Cols = 2; Rows = 3 },
  @{ Name = 'lod07_1x3'; Cols = 1; Rows = 3 },
  @{ Name = 'lod08_1x2'; Cols = 1; Rows = 2 },
  @{ Name = 'lod09_1x2'; Cols = 1; Rows = 2 }
)

function Load-SpriteRegion {
  param([string]$ZipPath)

  if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "ROM zip not found: $ZipPath"
  }

  $region = New-Object byte[] 0x80000
  $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($load in $spriteLoads) {
      $entry = $zip.GetEntry($load.Name)
      if ($null -eq $entry) {
        throw "Missing ROM entry: $($load.Name)"
      }

      $inputStream = $entry.Open()
      try {
        $memoryStream = New-Object System.IO.MemoryStream
        try {
          $inputStream.CopyTo($memoryStream)
          $data = $memoryStream.ToArray()
          [Array]::Copy($data, 0, $region, [int]$load.Offset, $data.Length)
        }
        finally {
          $memoryStream.Dispose()
        }
      }
      finally {
        $inputStream.Dispose()
      }
    }
  }
  finally {
    $zip.Dispose()
  }

  return $region
}

function Draw-Tile {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [byte[]]$Region,
    [int]$TileIndex,
    [int]$DestX,
    [int]$DestY
  )

  $offset = $TileIndex * 32
  if ($offset -lt 0 -or ($offset + 31) -ge $Region.Length) {
    throw "Tile index out of range: $TileIndex"
  }

  for ($y = 0; $y -lt 8; $y++) {
    for ($x = 0; $x -lt 8; $x++) {
      $packed = $Region[$offset + ($y * 4) + [math]::Floor($x / 2)]
      if (($x -band 1) -eq 0) {
        $pen = ($packed -shr 4) -band 0x0f
      }
      else {
        $pen = $packed -band 0x0f
      }

      $Bitmap.SetPixel($DestX + $x, $DestY + $y, $palette[$pen])
    }
  }
}

function New-LodBitmap {
  param(
    [byte[]]$Region,
    [int]$TileStart,
    [int]$Cols,
    [int]$Rows
  )

  $bitmap = New-Object System.Drawing.Bitmap ($Cols * 8), ($Rows * 8), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  for ($i = 0; $i -lt ($Cols * $Rows); $i++) {
    $destCol = [math]::Floor($i / $Rows)
    $destRow = $i % $Rows
    Draw-Tile -Bitmap $bitmap -Region $Region -TileIndex ($TileStart + $i) -DestX ($destCol * 8) -DestY ($destRow * 8)
  }
  return $bitmap
}

if (-not (Test-Path -LiteralPath $OutputRoot)) {
  New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
}
else {
  Get-ChildItem -LiteralPath $OutputRoot -File |
    Where-Object { $_.Name -like 'pose_0010_lod*.png' -or $_.Name -eq 'pose_0010_lod_manifest.csv' } |
    Remove-Item -Force
}

$region = Load-SpriteRegion -ZipPath $RomZip
$manifest = New-Object System.Collections.Generic.List[object]
$lodImages = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
$tile = $StartTile

try {
  foreach ($lod in $lodSpecs) {
    $tileCount = $lod.Cols * $lod.Rows
    $image = New-LodBitmap -Region $region -TileStart $tile -Cols $lod.Cols -Rows $lod.Rows
    $lodImages.Add($image) | Out-Null

    $path = Join-Path $OutputRoot ("pose_0010_{0}_{1}_{2}-{3}.png" -f $lod.Name, ('{0}x{1}' -f $lod.Cols, $lod.Rows), $tile.ToString('X4'), ($tile + $tileCount - 1).ToString('X4'))
    $image.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

    $manifest.Add([pscustomobject]@{
      name           = $lod.Name
      cols           = $lod.Cols
      rows           = $lod.Rows
      width_px       = $image.Width
      height_px      = $image.Height
      start_tile_hex = $tile.ToString('X4')
      end_tile_hex   = ($tile + $tileCount - 1).ToString('X4')
      png            = $path
    }) | Out-Null

    $tile += $tileCount
  }

  $sheetWidth = (($lodImages | ForEach-Object { $_.Width }) | Measure-Object -Sum).Sum + (($lodImages.Count - 1) * $GapPx)
  $sheetHeight = (($lodImages | ForEach-Object { $_.Height }) | Measure-Object -Maximum).Maximum
  $sheet = New-Object System.Drawing.Bitmap $sheetWidth, $sheetHeight, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gfx = [System.Drawing.Graphics]::FromImage($sheet)
  try {
    $gfx.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighSpeed
    $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

    $x = 0
    foreach ($image in $lodImages) {
      $gfx.DrawImage($image, $x, ($sheetHeight - $image.Height), $image.Width, $image.Height)
      $x += $image.Width + $GapPx
    }
  }
  finally {
    $gfx.Dispose()
  }

  $sheetPath = Join-Path $OutputRoot 'pose_0010_lod_strip.png'
  $sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $sheet.Dispose()

  $manifestPath = Join-Path $OutputRoot 'pose_0010_lod_manifest.csv'
  $manifest | Export-Csv -NoTypeInformation -Encoding UTF8 $manifestPath

  Write-Output "Wrote individual LOD PNGs to $OutputRoot"
  Write-Output "Wrote strip $sheetPath"
  Write-Output "Wrote manifest $manifestPath"
  Write-Output ("Last tile used: {0}" -f ($tile - 1).ToString('X4'))
}
finally {
  foreach ($image in $lodImages) {
    $image.Dispose()
  }
}
