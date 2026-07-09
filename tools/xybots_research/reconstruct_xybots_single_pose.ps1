param(
  [string]$RomZip = 'D:\MAME\roms\xybots.zip',
  [string]$OutputPath = 'D:\Godot\xybotsResearch\exports\sprites\reconstructed_pose_review\pose_0010_3x6.png',
  [int]$StartTile = 0x0010,
  [int]$Cols = 3,
  [int]$Rows = 6,
  [ValidateSet('ColumnMajor', 'RowMajor')]
  [string]$Order = 'ColumnMajor'
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

$region = Load-SpriteRegion -ZipPath $RomZip
$bitmap = New-Object System.Drawing.Bitmap ($Cols * 8), ($Rows * 8), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

try {
  for ($i = 0; $i -lt ($Cols * $Rows); $i++) {
    if ($Order -eq 'ColumnMajor') {
      $destCol = [math]::Floor($i / $Rows)
      $destRow = $i % $Rows
    }
    else {
      $destCol = $i % $Cols
      $destRow = [math]::Floor($i / $Cols)
    }
    Draw-Tile -Bitmap $bitmap -Region $region -TileIndex ($StartTile + $i) -DestX ($destCol * 8) -DestY ($destRow * 8)
  }

  $outputDir = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  }

  $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
  Write-Output "Wrote $OutputPath"
  Write-Output ("Tiles: {0} through {1}" -f $StartTile.ToString('X4'), ($StartTile + ($Cols * $Rows) - 1).ToString('X4'))
  Write-Output ("Size: {0}x{1}" -f $bitmap.Width, $bitmap.Height)
  Write-Output "Order: $Order"
}
finally {
  $bitmap.Dispose()
}
