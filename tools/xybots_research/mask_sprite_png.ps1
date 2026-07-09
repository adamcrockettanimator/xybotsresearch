param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath = "",

    # Use this when the sprite is on a flat backing color, e.g. Photoshop crop on white.
    [switch]$RemoveWhiteBackground,

    # Optional: use a matching background frame to isolate changed pixels.
    [string]$BackgroundPath = "",

    # Difference threshold for background subtraction.
    [int]$Threshold = 24,

    # Keep only pixels inside an ROI: x,y,width,height.
    [string]$Roi = "",

    # Remove tiny specks after thresholding.
    [int]$MinimumComponentPixels = 3,

    [switch]$Trim
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input not found: $InputPath"
}

if (-not $OutputPath) {
    $dir = Split-Path -Parent $InputPath
    $name = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $OutputPath = Join-Path $dir ($name + "_masked.png")
}

function Parse-Roi {
    param([string]$Value, [int]$ImageWidth, [int]$ImageHeight)
    if (-not $Value) {
        return [Drawing.Rectangle]::new(0, 0, $ImageWidth, $ImageHeight)
    }

    $parts = $Value -split "," | ForEach-Object { [int]$_.Trim() }
    if ($parts.Count -ne 4) {
        throw "ROI must be x,y,width,height"
    }
    return [Drawing.Rectangle]::new($parts[0], $parts[1], $parts[2], $parts[3])
}

function Get-DiffScore {
    param([Drawing.Color]$A, [Drawing.Color]$B)
    return [Math]::Abs([int]$A.R - [int]$B.R) + [Math]::Abs([int]$A.G - [int]$B.G) + [Math]::Abs([int]$A.B - [int]$B.B)
}

function Remove-SmallComponents {
    param([bool[,]]$Mask, [int]$Width, [int]$Height, [int]$MinimumPixels)

    if ($MinimumPixels -le 1) {
        return
    }

    $seen = New-Object 'bool[,]' $Width, $Height
    $dx = @(1, -1, 0, 0)
    $dy = @(0, 0, 1, -1)

    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            if (-not $Mask[$x, $y] -or $seen[$x, $y]) {
                continue
            }

            $queue = [System.Collections.Generic.Queue[object]]::new()
            $pixels = [System.Collections.Generic.List[object]]::new()
            $queue.Enqueue(@($x, $y))
            $seen[$x, $y] = $true

            while ($queue.Count -gt 0) {
                $p = $queue.Dequeue()
                $px = [int]$p[0]
                $py = [int]$p[1]
                $pixels.Add($p)

                for ($i = 0; $i -lt 4; $i++) {
                    $nx = $px + $dx[$i]
                    $ny = $py + $dy[$i]
                    if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $Width -or $ny -ge $Height) {
                        continue
                    }
                    if ($Mask[$nx, $ny] -and -not $seen[$nx, $ny]) {
                        $seen[$nx, $ny] = $true
                        $queue.Enqueue(@($nx, $ny))
                    }
                }
            }

            if ($pixels.Count -lt $MinimumPixels) {
                foreach ($p in $pixels) {
                    $Mask[[int]$p[0], [int]$p[1]] = $false
                }
            }
        }
    }
}

$inputImage = [Drawing.Bitmap]::new($InputPath)
$background = $null
try {
    if ($BackgroundPath) {
        if (-not (Test-Path -LiteralPath $BackgroundPath)) {
            throw "Background not found: $BackgroundPath"
        }
        $background = [Drawing.Bitmap]::new($BackgroundPath)
        if ($background.Width -ne $inputImage.Width -or $background.Height -ne $inputImage.Height) {
            throw "Background size must match input size."
        }
    }

    $roiRect = Parse-Roi -Value $Roi -ImageWidth $inputImage.Width -ImageHeight $inputImage.Height
    $mask = New-Object 'bool[,]' $inputImage.Width, $inputImage.Height

    for ($y = 0; $y -lt $inputImage.Height; $y++) {
        for ($x = 0; $x -lt $inputImage.Width; $x++) {
            if (-not $roiRect.Contains($x, $y)) {
                $mask[$x, $y] = $false
                continue
            }

            $c = $inputImage.GetPixel($x, $y)
            $keep = $true

            if ($RemoveWhiteBackground) {
                $isWhite = ($c.R -ge 245 -and $c.G -ge 245 -and $c.B -ge 245)
                $keep = -not $isWhite
            } elseif ($background) {
                $b = $background.GetPixel($x, $y)
                $keep = (Get-DiffScore -A $c -B $b) -ge $Threshold
            }

            $mask[$x, $y] = $keep
        }
    }

    Remove-SmallComponents -Mask $mask -Width $inputImage.Width -Height $inputImage.Height -MinimumPixels $MinimumComponentPixels

    $minX = $inputImage.Width
    $minY = $inputImage.Height
    $maxX = -1
    $maxY = -1
    for ($y = 0; $y -lt $inputImage.Height; $y++) {
        for ($x = 0; $x -lt $inputImage.Width; $x++) {
            if ($mask[$x, $y]) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }

    if ($maxX -lt $minX -or $maxY -lt $minY) {
        throw "Mask is empty. Try lowering -Threshold or changing -Roi."
    }

    $outX = 0
    $outY = 0
    $outW = $inputImage.Width
    $outH = $inputImage.Height
    if ($Trim) {
        $outX = $minX
        $outY = $minY
        $outW = $maxX - $minX + 1
        $outH = $maxY - $minY + 1
    }

    $output = [Drawing.Bitmap]::new($outW, $outH, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        for ($y = 0; $y -lt $outH; $y++) {
            for ($x = 0; $x -lt $outW; $x++) {
                $srcX = $x + $outX
                $srcY = $y + $outY
                if ($mask[$srcX, $srcY]) {
                    $output.SetPixel($x, $y, $inputImage.GetPixel($srcX, $srcY))
                } else {
                    $output.SetPixel($x, $y, [Drawing.Color]::FromArgb(0, 0, 0, 0))
                }
            }
        }

        $outDir = Split-Path -Parent $OutputPath
        if ($outDir) {
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        }
        $output.Save($OutputPath, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $output.Dispose()
    }
} finally {
    $inputImage.Dispose()
    if ($background) {
        $background.Dispose()
    }
}

Write-Host "Masked PNG:"
Write-Host "  $OutputPath"
