param(
  [string]$SourceImage = 'D:\Godot\xybotsResearch\exports\sprites\xybots_sprites_raw_8x8_tiles.png',
  [string]$OutputRoot = 'D:\Godot\xybotsResearch\exports\sprites\reconstructed_pose_sheets',
  [int]$StartTile = 16,
  [int]$MaxTileCount = 16384,
  [int]$PoseLimit = 0,
  [int]$GapPx = 8,
  [string]$TransparentRgb = '18,18,28'
)

Add-Type -AssemblyName System.Drawing

$tileSize = 8
$lodSpecs = @(
  @{ Name = 'lod0_3x6'; Cols = 3; Rows = 6 },
  @{ Name = 'lod1_3x5'; Cols = 3; Rows = 5 },
  @{ Name = 'lod2_2x4'; Cols = 2; Rows = 4 },
  @{ Name = 'lod3_2x4'; Cols = 2; Rows = 4 },
  @{ Name = 'lod4_2x3'; Cols = 2; Rows = 3 },
  @{ Name = 'lod5_1x3'; Cols = 1; Rows = 3 },
  @{ Name = 'lod6_1x2'; Cols = 1; Rows = 2 },
  @{ Name = 'lod7_1x2'; Cols = 1; Rows = 2 }
)

$transparentParts = $TransparentRgb.Split(',') | ForEach-Object { [int]$_.Trim() }
$transparentR = $transparentParts[0]
$transparentG = $transparentParts[1]
$transparentB = $transparentParts[2]

function New-ArgbBitmap {
  param([int]$Width, [int]$Height)
  return New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Save-Png {
  param(
    [System.Drawing.Image]$Image,
    [string]$Path
  )
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $Image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Get-TileRect {
  param(
    [int]$TileIndex,
    [int]$AtlasTileCols
  )
  $tileX = $TileIndex % $AtlasTileCols
  $tileY = [math]::Floor($TileIndex / $AtlasTileCols)
  return New-Object System.Drawing.Rectangle ($tileX * $tileSize), ($tileY * $tileSize), $tileSize, $tileSize
}

function Build-LodImage {
  param(
    [System.Drawing.Bitmap]$Atlas,
    [int]$StartTileIndex,
    [int]$AtlasTileCols,
    [int]$Cols,
    [int]$Rows
  )
  $width = $Cols * $tileSize
  $height = $Rows * $tileSize
  $bmp = New-ArgbBitmap -Width $width -Height $height
  $gfx = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $gfx.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighSpeed
    $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

    $tileCount = $Cols * $Rows
    for ($i = 0; $i -lt $tileCount; $i++) {
      $sourceTileIndex = $StartTileIndex + $i
      $sourceRect = Get-TileRect -TileIndex $sourceTileIndex -AtlasTileCols $AtlasTileCols
      $destCol = [math]::Floor($i / $Rows)
      $destRow = $i % $Rows
      $destRect = New-Object System.Drawing.Rectangle ($destCol * $tileSize), ($destRow * $tileSize), $tileSize, $tileSize
      $gfx.DrawImage($Atlas, $destRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
    }
  }
  finally {
    $gfx.Dispose()
  }
  return $bmp
}

function Set-KeyColorTransparent {
  param([System.Drawing.Bitmap]$Image)
  for ($y = 0; $y -lt $Image.Height; $y++) {
    for ($x = 0; $x -lt $Image.Width; $x++) {
      $p = $Image.GetPixel($x, $y)
      if ($p.A -eq 0 -or ($p.R -eq $transparentR -and $p.G -eq $transparentG -and $p.B -eq $transparentB)) {
        $Image.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, $p.R, $p.G, $p.B))
      }
    }
  }
}

$atlas = [System.Drawing.Bitmap]::FromFile($SourceImage)
try {
  $atlasTileCols = [int]($atlas.Width / $tileSize)
  $tilesPerPose = ($lodSpecs | ForEach-Object { $_.Cols * $_.Rows } | Measure-Object -Sum).Sum
  $availableTiles = ([math]::Min($MaxTileCount, ($atlas.Width / $tileSize) * ($atlas.Height / $tileSize))) - $StartTile
  $poseCount = [math]::Floor($availableTiles / $tilesPerPose)
  if ($PoseLimit -gt 0) {
    $poseCount = [math]::Min($poseCount, $PoseLimit)
  }

  if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
  }

  $manifest = New-Object System.Collections.Generic.List[object]

  for ($poseIndex = 0; $poseIndex -lt $poseCount; $poseIndex++) {
    $poseStartTile = $StartTile + ($poseIndex * $tilesPerPose)
    $sheetWidth = (($lodSpecs | ForEach-Object { $_.Cols }) | Measure-Object -Sum).Sum * $tileSize
    $sheetWidth += ($lodSpecs.Count - 1) * $GapPx
    $sheetHeight = (($lodSpecs | ForEach-Object { $_.Rows }) | Measure-Object -Maximum).Maximum * $tileSize

    $sheet = New-ArgbBitmap -Width $sheetWidth -Height $sheetHeight
    $sheetGfx = [System.Drawing.Graphics]::FromImage($sheet)
    try {
      $sheetGfx.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
      $sheetGfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
      $sheetGfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighSpeed
      $sheetGfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

      $x = 0
      $lodStartTile = $poseStartTile
      foreach ($lod in $lodSpecs) {
        $lodTileCount = $lod.Cols * $lod.Rows
        $lodBmp = Build-LodImage -Atlas $atlas -StartTileIndex $lodStartTile -AtlasTileCols $atlasTileCols -Cols $lod.Cols -Rows $lod.Rows
        try {
          $destY = $sheetHeight - $lodBmp.Height
          $sheetGfx.DrawImage($lodBmp, $x, $destY, $lodBmp.Width, $lodBmp.Height)
        }
        finally {
          $lodBmp.Dispose()
        }

        $manifest.Add([pscustomobject]@{
          pose_index      = $poseIndex
          pose_start_hex  = ([int]$poseStartTile).ToString('X4')
          lod_name        = $lod.Name
          cols            = $lod.Cols
          rows            = $lod.Rows
          tile_count      = $lodTileCount
          start_tile_hex  = ([int]$lodStartTile).ToString('X4')
          end_tile_hex    = ([int]($lodStartTile + $lodTileCount - 1)).ToString('X4')
        }) | Out-Null

        $x += ($lod.Cols * $tileSize) + $GapPx
        $lodStartTile += $lodTileCount
      }
    }
    finally {
      $sheetGfx.Dispose()
    }

    Set-KeyColorTransparent -Image $sheet
    $sheetPath = Join-Path $OutputRoot ('pose_{0:D4}.png' -f $poseIndex)
    Save-Png -Image $sheet -Path $sheetPath
    $sheet.Dispose()
    Write-Output "Wrote $sheetPath"
  }

  $manifestPath = Join-Path $OutputRoot 'pose_manifest.csv'
  $manifest | Export-Csv -NoTypeInformation -Encoding UTF8 $manifestPath
  Write-Output "Manifest: $manifestPath"
  Write-Output "Pose count: $poseCount"
}
finally {
  $atlas.Dispose()
}
