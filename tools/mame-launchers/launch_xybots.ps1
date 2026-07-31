param(
    [string]$MameRoot = "D:\MAME",
    [ValidateSet("gdi", "bgfx", "opengl", "d3d", "auto")]
    [string]$VideoMode = "gdi",
    [switch]$SkipAudit
)

$ErrorActionPreference = "Stop"

$MameExe = Join-Path $MameRoot "mame.exe"
$RomPath = Join-Path (Join-Path $MameRoot "roms") "xybots.zip"

if (-not (Test-Path -LiteralPath $MameExe)) {
    Write-Host "MAME NOT FOUND - expected mame.exe at $MameExe"
    exit 2
}

if (-not (Test-Path -LiteralPath $RomPath)) {
    Write-Host "ROM FILE NOT FOUND - expected:"
    Write-Host "  $RomPath"
    Write-Host ""
    Write-Host "Place your legally obtained xybots.zip there and rerun this launcher."
    exit 3
}

if (-not $SkipAudit) {
    Write-Host "Running quick ROM audit..."
    Push-Location $MameRoot
    try {
        & $MameExe -verifyroms xybots
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "ROM AUDIT FAILED - launch stopped so the error can be inspected first."
            Write-Host "Run .\mame\verify_xybots.ps1 for a timestamped log."
            exit 4
        }
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "Xybots research controls:"
Write-Host ""
Write-Host "F4      Open graphics viewer"
Write-Host "Enter   Cycle palette / graphics / tilemap views"
Write-Host "[ ]     Change graphics set"
Write-Host "Arrow keys / Page Up / Page Down   Navigate"
Write-Host "Left / Right   Change palette"
Write-Host "F12     Save screenshot"
Write-Host "Esc     Exit MAME"
Write-Host ""
Write-Host "Launching MAME from $MameRoot with -video $VideoMode ..."

Push-Location $MameRoot
try {
    if ($VideoMode -eq "auto") {
        & $MameExe xybots
    } else {
        & $MameExe xybots -video $VideoMode
    }
} finally {
    Pop-Location
}
