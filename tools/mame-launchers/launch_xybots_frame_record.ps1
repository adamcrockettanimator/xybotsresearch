param(
    [string]$MameRoot = "D:\MAME",
    [ValidateSet("gdi", "bgfx", "opengl", "d3d", "auto")]
    [string]$VideoMode = "gdi"
)

$ErrorActionPreference = "Stop"

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$MameExe = Join-Path $MameRoot "mame.exe"
$RomPath = Join-Path (Join-Path $MameRoot "roms") "xybots.zip"
$Stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$SessionDir = Join-Path $WorkspaceRoot "exports\frame_recordings\session_$Stamp"
$SnapDir = Join-Path $SessionDir "markers"
$MoviePath = Join-Path $SessionDir "xybots_$Stamp.avi"
$InfoPath = Join-Path $SessionDir "session_info.txt"

if (-not (Test-Path -LiteralPath $MameExe)) {
    Write-Host "MAME NOT FOUND - expected mame.exe at $MameExe"
    exit 2
}

if (-not (Test-Path -LiteralPath $RomPath)) {
    Write-Host "ROM FILE NOT FOUND - expected:"
    Write-Host "  $RomPath"
    exit 3
}

New-Item -ItemType Directory -Force -Path $SnapDir | Out-Null

$StartedAt = Get-Date
@(
    "Xybots frame recording session",
    "StartedAt=$($StartedAt.ToString('o'))",
    "MameRoot=$MameRoot",
    "MoviePath=$MoviePath",
    "MarkerSnapshotDirectory=$SnapDir",
    "",
    "Workflow:",
    "1. Press F12 once to mark the start of the frame range.",
    "2. Press F12 again to mark the end of the frame range.",
    "3. Press Esc to exit MAME.",
    "4. Run .\tools\extract_frame_recording.ps1 to export PNG frames between the markers.",
    "",
    "F12 marker screenshots are saved at native size: 336x240."
) | Set-Content -LiteralPath $InfoPath

Write-Host "Launching Xybots frame recording session."
Write-Host ""
Write-Host "F12 marker workflow:"
Write-Host "  First F12  = mark START"
Write-Host "  Second F12 = mark END"
Write-Host "  Esc        = exit MAME"
Write-Host ""
Write-Host "AVI movie:"
Write-Host "  $MoviePath"
Write-Host "Marker screenshots:"
Write-Host "  $SnapDir"
Write-Host ""

Push-Location $MameRoot
try {
    $args = @(
        "xybots",
        "-aviwrite", $MoviePath,
        "-snapshot_directory", $SnapDir,
        "-snapname", "marker_%i",
        "-snapsize", "336x240",
        "-nosnapbilinear"
    )

    if ($VideoMode -ne "auto") {
        $args += @("-video", $VideoMode)
    }

    & $MameExe @args
} finally {
    Pop-Location
    "EndedAt=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath $InfoPath
}
