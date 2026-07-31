param(
    [string]$MameRoot = "D:\MAME",
    [string]$RomName = "xybots.zip"
)

$ErrorActionPreference = "Stop"

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $WorkspaceRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$LogPath = Join-Path $LogDir "verify_xybots_$Timestamp.log"
$MameExe = Join-Path $MameRoot "mame.exe"
$RomPath = Join-Path (Join-Path $MameRoot "roms") $RomName

function Write-Status {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail = ""
    )

    $label = if ($Ok) { "$Name FOUND" } else { "$Name NOT FOUND" }
    if ($Name -eq "ROM AUDIT") {
        $label = if ($Ok) { "ROM AUDIT PASSED" } else { "ROM AUDIT FAILED" }
    }

    $line = if ($Detail) { "$label - $Detail" } else { $label }
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line
}

"Xybots ROM verification started: $(Get-Date -Format o)" | Set-Content -LiteralPath $LogPath
"MAME root: $MameRoot" | Add-Content -LiteralPath $LogPath
"Expected ROM: $RomPath" | Add-Content -LiteralPath $LogPath
"" | Add-Content -LiteralPath $LogPath

if (-not (Test-Path -LiteralPath $MameExe)) {
    Write-Status "MAME" $false "Expected mame.exe at $MameExe"
    Write-Host ""
    Write-Host "Install official MAME, or rerun this script with -MameRoot pointing to the folder containing mame.exe."
    exit 2
}

Write-Status "MAME" $true $MameExe

try {
    $Version = & $MameExe -version 2>&1
    "MAME version: $Version" | Add-Content -LiteralPath $LogPath
    Write-Host "MAME VERSION $Version"
} catch {
    "Failed to query MAME version: $($_.Exception.Message)" | Add-Content -LiteralPath $LogPath
}

if (-not (Test-Path -LiteralPath $RomPath)) {
    Write-Status "ROM FILE" $false $RomPath
    Write-Host ""
    Write-Host "Place your legally obtained Xybots ROM set here:"
    Write-Host "  $RomPath"
    Write-Host ""
    Write-Host "Do not unzip it. Do not rename internal files. The expected zip filename is xybots.zip."
    exit 3
}

Write-Status "ROM FILE" $true $RomPath

$Hash = Get-FileHash -LiteralPath $RomPath -Algorithm SHA256
"ROM SHA256: $($Hash.Hash)" | Add-Content -LiteralPath $LogPath
Write-Host "ROM SHA256 $($Hash.Hash)"

"" | Add-Content -LiteralPath $LogPath
"Running from ${MameRoot}: $MameExe -verifyroms xybots" | Add-Content -LiteralPath $LogPath

$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
Push-Location $MameRoot
try {
    $AuditOutput = & $MameExe -verifyroms xybots 2>&1
    $AuditExit = $LASTEXITCODE
} finally {
    Pop-Location
    $ErrorActionPreference = $PreviousErrorActionPreference
}

$AuditOutput | ForEach-Object { $_.ToString() } | Add-Content -LiteralPath $LogPath

if ($AuditExit -eq 0) {
    Write-Status "ROM AUDIT" $true "MAME accepted the xybots set."
    Write-Host "Log: $LogPath"
    exit 0
}

Write-Status "ROM AUDIT" $false "MAME returned exit code $AuditExit. Exact output was saved."
Write-Host ""
Write-Host "Plain-English next step:"
Write-Host "  The zip is present, but MAME does not consider it a complete valid xybots set for this MAME version."
Write-Host "  Keep the exact log for analysis. Do not unzip, patch, or replace files from random download sites."
Write-Host "Log: $LogPath"
exit 4
