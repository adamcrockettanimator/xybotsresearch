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

$TriggerPath = Join-Path $MameSourceRoot "snap\xybots_capture\start_controlled_capture.txt"
Remove-Item -LiteralPath $TriggerPath -Force -ErrorAction SilentlyContinue

Write-Host "Launching Xybots controlled movement capture build."
Write-Host ""
Write-Host "Manual setup:"
Write-Host "  1. Press any key at the first screen."
Write-Host "  2. Press 5 to insert coin."
Write-Host "  3. Press 1 to start."
Write-Host "  4. Clear robots and place the player."
Write-Host "  5. Tell Codex: ready"
Write-Host ""
Write-Host "Codex will then create:"
Write-Host "  $TriggerPath"
Write-Host ""

$env:MAME_XYBOTS_CAPTURE = "1"
$env:MAME_XYBOTS_AUTO_SCRIPT = "1"
$env:MAME_XYBOTS_AUTO_SCRIPT_WAIT_TRIGGER = "1"

Push-Location $MameSourceRoot
try {
    if ($VideoMode -eq "auto") {
        & $MameExe xybots -rompath $RomRoot -cheat -keyboardprovider win32 -window
    } else {
        & $MameExe xybots -rompath $RomRoot -video $VideoMode -cheat -keyboardprovider win32 -window
    }
} finally {
    Pop-Location
}
