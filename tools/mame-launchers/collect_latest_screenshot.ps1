param(
    [ValidateSet("palettes", "tiles", "sprites", "chars", "tilemaps", "gameplay")]
    [string]$Category,
    [string]$MameRoot = "D:\MAME"
)

$ErrorActionPreference = "Stop"

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$MameSnapRoot = Join-Path $MameRoot "snap"
$DestinationRoot = Join-Path $WorkspaceRoot "screenshots"

if (-not $Category) {
    Write-Host "Choose a category:"
    Write-Host "  palettes, tiles, sprites, chars, tilemaps, gameplay"
    $Category = Read-Host "Category"
}

$Allowed = @("palettes", "tiles", "sprites", "chars", "tilemaps", "gameplay")
if ($Allowed -notcontains $Category) {
    Write-Host "Invalid category: $Category"
    exit 2
}

if (-not (Test-Path -LiteralPath $MameSnapRoot)) {
    Write-Host "No MAME screenshot folder found yet: $MameSnapRoot"
    Write-Host "Run MAME and press F12 to create a screenshot first."
    exit 3
}

$Latest = Get-ChildItem -LiteralPath $MameSnapRoot -Recurse -File -Include *.png,*.jpg,*.jpeg |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Latest) {
    Write-Host "No screenshot files found under $MameSnapRoot"
    exit 4
}

$DestinationDir = Join-Path $DestinationRoot $Category
New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null

$Date = Get-Date -Format "yyyy-MM-dd"
$Index = 1
do {
    $Name = "{0}_{1}_{2:000}{3}" -f $Category, $Date, $Index, $Latest.Extension.ToLowerInvariant()
    $DestinationPath = Join-Path $DestinationDir $Name
    $Index++
} while (Test-Path -LiteralPath $DestinationPath)

Copy-Item -LiteralPath $Latest.FullName -Destination $DestinationPath -ErrorAction Stop

Write-Host "Copied newest screenshot:"
Write-Host "  From: $($Latest.FullName)"
Write-Host "  To:   $DestinationPath"
Write-Host "Original preserved."
