param(
    [string]$MameRoot = "D:\MAME"
)

if (-not (Test-Path -LiteralPath $MameRoot)) {
    Write-Host "MAME folder not found: $MameRoot"
    exit 2
}

Invoke-Item -LiteralPath $MameRoot
