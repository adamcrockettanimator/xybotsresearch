param(
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [Parameter(Mandatory=$true)][string]$Lod,
  [Parameter(Mandatory=$true)][int]$StartTile,
  [Parameter(Mandatory=$true)][string[]]$Sizes,
  [int]$Scale = 8
)

$ErrorActionPreference = 'Stop'

$startHex = $StartTile.ToString('X4')
$out = Join-Path $OutputRoot ("{0}_{1}_candidates" -f $Lod, $startHex)
if (Test-Path -LiteralPath $out) {
  Get-ChildItem -LiteralPath $out -File | Remove-Item -Force
}
else {
  New-Item -ItemType Directory -Force -Path $out | Out-Null
}

foreach ($size in $Sizes) {
  if ($size -notmatch '^(\d+)x(\d+)$') {
    throw "Size must be height x width, got: $size"
  }
  $rows = [int]$matches[1]
  $cols = [int]$matches[2]
  $count = $rows * $cols
  $endHex = ($StartTile + $count - 1).ToString('X4')
  $path = Join-Path $out ("{0}_{1}-{2}_{3}.png" -f $Lod, $startHex, $endHex, $size)
  & "$PSScriptRoot\reconstruct_xybots_single_pose.ps1" -StartTile $StartTile -Cols $cols -Rows $rows -Order ColumnMajor -OutputPath $path | Out-Null
}

Add-Type -AssemblyName System.Drawing

$files = Get-ChildItem -LiteralPath $out -Filter *.png | Sort-Object Name
$pad = 12
$labelH = 14
$colsPerSheet = 2
$font = New-Object System.Drawing.Font ([System.Drawing.FontFamily]::GenericMonospace), 8
$bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 18, 18, 28))
$white = [System.Drawing.Brushes]::White
$items = @()

try {
  foreach ($file in $files) {
    $img = [System.Drawing.Bitmap]::FromFile($file.FullName)
    $items += [pscustomobject]@{
      File = $file
      Image = $img
      W = $img.Width * $Scale
      H = ($img.Height * $Scale) + $labelH
    }
  }

  $cellW = (($items | ForEach-Object { $_.W } | Measure-Object -Maximum).Maximum) + $pad
  $cellH = (($items | ForEach-Object { $_.H } | Measure-Object -Maximum).Maximum) + $pad
  $rowsPerSheet = [math]::Ceiling($items.Count / $colsPerSheet)
  $sheet = New-Object System.Drawing.Bitmap ($colsPerSheet * $cellW), ($rowsPerSheet * $cellH), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gfx = [System.Drawing.Graphics]::FromImage($sheet)
  try {
    $gfx.FillRectangle($bg, 0, 0, $sheet.Width, $sheet.Height)
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighSpeed
    for ($i = 0; $i -lt $items.Count; $i++) {
      $col = $i % $colsPerSheet
      $row = [math]::Floor($i / $colsPerSheet)
      $x = ($col * $cellW) + 4
      $y = ($row * $cellH) + 4
      $gfx.DrawString($items[$i].File.BaseName, $font, $white, $x, $y)
      $gfx.DrawImage($items[$i].Image, $x, $y + $labelH, $items[$i].W, $items[$i].Image.Height * $Scale)
    }
    $sheetPath = Join-Path $out ("candidate_sheet_{0}x.png" -f $Scale)
    $sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally {
    $gfx.Dispose()
    $sheet.Dispose()
  }
}
finally {
  foreach ($item in $items) {
    $item.Image.Dispose()
  }
  $font.Dispose()
  $bg.Dispose()
}

Write-Output $out
