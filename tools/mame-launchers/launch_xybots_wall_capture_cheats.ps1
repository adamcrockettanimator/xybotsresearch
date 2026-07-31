param(
    [string]$MameSourceRoot = "D:\Godot\xybotsResearch\mame-src",
    [string]$RomRoot = "D:\MAME\roms",
    [ValidateSet("gdi", "bgfx", "opengl", "d3d", "auto")]
    [string]$VideoMode = "gdi"
)

$ErrorActionPreference = "Stop"

$MameExe = Join-Path $MameSourceRoot "xybots.exe"
$RomPath = Join-Path $RomRoot "xybots.zip"

if (-not (Test-Path -LiteralPath $MameExe)) {
    Write-Host "XYBOTS CAPTURE BUILD NOT FOUND - expected:"
    Write-Host "  $MameExe"
    exit 2
}

if (-not (Test-Path -LiteralPath $RomPath)) {
    Write-Host "ROM FILE NOT FOUND - expected:"
    Write-Host "  $RomPath"
    exit 3
}

Write-Host "Launching Xybots wall/playfield capture build with cheats enabled."
Write-Host ""
Write-Host "Controls:"
Write-Host "  F10  Toggle every-frame wall/turn recording"
Write-Host "  F11  Write one full capture: playfield PNG, playfield JSON, sprite PNGs"
Write-Host "  F12  Toggle automatic unique sprite capture"
Write-Host "  Tab  Open MAME menu, including Cheat"
Write-Host "  Esc  Exit MAME"
Write-Host ""
Write-Host "Output:"
Write-Host "  $MameSourceRoot\snap\xybots_capture\capture_####"
Write-Host "  $MameSourceRoot\snap\xybots_capture\wall_turn_recordings\session_####"
Write-Host ""

$env:MAME_XYBOTS_CAPTURE = "1"

Push-Location $MameSourceRoot
try {
    if ($VideoMode -eq "auto") {
        & $MameExe xybots -rompath $RomRoot -cheat
    } else {
        & $MameExe xybots -rompath $RomRoot -video $VideoMode -cheat
    }
} finally {
    Pop-Location
}
