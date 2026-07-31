param(
    [string]$MameRoot = "D:\MAME",
    [ValidateSet("gdi", "bgfx", "opengl", "d3d", "auto")]
    [string]$VideoMode = "gdi"
)

$ErrorActionPreference = "Stop"

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$LuaScript = Join-Path $WorkspaceRoot "tools\xybots_mob_capture.lua"
$MameExe = Join-Path $MameRoot "mame.exe"
$RomPath = Join-Path (Join-Path $MameRoot "roms") "xybots.zip"

if (-not (Test-Path -LiteralPath $MameExe)) {
    Write-Host "MAME NOT FOUND - expected mame.exe at $MameExe"
    exit 2
}

if (-not (Test-Path -LiteralPath $RomPath)) {
    Write-Host "ROM FILE NOT FOUND - expected:"
    Write-Host "  $RomPath"
    exit 3
}

if (-not (Test-Path -LiteralPath $LuaScript)) {
    Write-Host "Lua recorder not found:"
    Write-Host "  $LuaScript"
    exit 4
}

Write-Host "Launching Xybots with live motion-object RAM capture."
Write-Host ""
Write-Host "Play normally, or stand near objects you want to inspect."
Write-Host "The recorder writes CSV snapshots to:"
Write-Host "  $WorkspaceRoot\exports\live_mob_capture"
Write-Host ""
Write-Host "Exit MAME with Esc when you have captured enough."
Write-Host ""

Push-Location $MameRoot
try {
    if ($VideoMode -eq "auto") {
        & $MameExe xybots -autoboot_delay 1 -autoboot_script $LuaScript
    } else {
        & $MameExe xybots -video $VideoMode -autoboot_delay 1 -autoboot_script $LuaScript
    }
} finally {
    Pop-Location
}
