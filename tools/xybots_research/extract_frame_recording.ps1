param(
    [string]$SessionDir = "",
    [switch]$ExtractWholeMovie
)

$ErrorActionPreference = "Stop"

if (-not $SessionDir) {
    $SessionDir = Get-ChildItem -LiteralPath "D:\Godot\xybotsResearch\exports\frame_recordings" -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $SessionDir -or -not (Test-Path -LiteralPath $SessionDir)) {
    Write-Host "No frame recording session found."
    exit 2
}

$InfoPath = Join-Path $SessionDir "session_info.txt"
$Movie = Get-ChildItem -LiteralPath $SessionDir -File | Where-Object { $_.Extension -in ".avi", ".mng" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$MarkerDir = Join-Path $SessionDir "markers"
$FrameDir = Join-Path $SessionDir "frames"

if (-not $Movie) {
    Write-Host "No AVI/MNG movie found in:"
    Write-Host "  $SessionDir"
    exit 3
}

$ffmpeg = (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) {
    $ffmpeg = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $ffmpeg) {
    Write-Host "ffmpeg.exe not found. Install FFmpeg or make it available on PATH, then rerun this script."
    exit 4
}

$startedAt = $null
if (Test-Path -LiteralPath $InfoPath) {
    $line = Get-Content -LiteralPath $InfoPath | Where-Object { $_ -like "StartedAt=*" } | Select-Object -First 1
    if ($line) {
        $startedAt = [datetimeoffset]::Parse(($line -replace "^StartedAt=", "")).LocalDateTime
    }
}

New-Item -ItemType Directory -Force -Path $FrameDir | Out-Null

$markers = @()
if (Test-Path -LiteralPath $MarkerDir) {
    $markers = Get-ChildItem -LiteralPath $MarkerDir -Recurse -File -Include *.png,*.jpg,*.jpeg | Sort-Object LastWriteTime
}

$args = @("-y", "-hide_banner")
$rangeDescription = "whole movie"

if (-not $ExtractWholeMovie -and $markers.Count -ge 2 -and $startedAt) {
    $startSec = [Math]::Max(0, ($markers[0].LastWriteTime - $startedAt).TotalSeconds)
    $endSec = [Math]::Max($startSec + 0.1, ($markers[1].LastWriteTime - $startedAt).TotalSeconds)
    $args += @("-ss", ("{0:0.###}" -f $startSec), "-to", ("{0:0.###}" -f $endSec))
    $rangeDescription = "between first two F12 markers ($('{0:0.###}' -f $startSec)s to $('{0:0.###}' -f $endSec)s)"
} elseif (-not $ExtractWholeMovie -and $markers.Count -eq 1 -and $startedAt) {
    $startSec = [Math]::Max(0, ($markers[0].LastWriteTime - $startedAt).TotalSeconds)
    $args += @("-ss", ("{0:0.###}" -f $startSec))
    $rangeDescription = "from first F12 marker to end ($('{0:0.###}' -f $startSec)s)"
}

$outPattern = Join-Path $FrameDir "frame_%05d.png"
$args += @("-i", $Movie.FullName, "-fps_mode", "passthrough", $outPattern)

Write-Host "Extracting $rangeDescription from:"
Write-Host "  $($Movie.FullName)"
Write-Host "Frames output:"
Write-Host "  $FrameDir"

& $ffmpeg @args
if ($LASTEXITCODE -ne 0) {
    Write-Host "FFmpeg failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$count = (Get-ChildItem -LiteralPath $FrameDir -Filter "frame_*.png" -File | Measure-Object).Count
Write-Host "Extracted $count PNG frame(s)."
