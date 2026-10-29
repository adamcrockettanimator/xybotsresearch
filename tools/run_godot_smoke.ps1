[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Script,

    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),

    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 45,

    [ValidateRange(1, 100000)]
    [int]$QuitAfterFrames = 900
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$scriptRelativePath = if ($Script.StartsWith('res://')) {
    $Script.Substring('res://'.Length).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
} else {
    $Script
}
$scriptPath = Join-Path $ProjectRoot $scriptRelativePath
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Smoke-test script does not exist: $scriptPath"
}

$godotCommand = Get-Command godot.exe -ErrorAction Stop
$logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("godot-smoke-{0}.log" -f [guid]::NewGuid())
$arguments = @(
    '--headless',
    '--path', $ProjectRoot,
    '--script', $Script,
    '--quit-after', $QuitAfterFrames,
    '--log-file', $logPath
)

Write-Host "Running $Script (timeout: $TimeoutSeconds seconds; frame guard: $QuitAfterFrames)."
$process = Start-Process -FilePath $godotCommand.Source -ArgumentList $arguments -PassThru -NoNewWindow

try {
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force
        throw "Godot smoke test exceeded $TimeoutSeconds seconds and was terminated: $Script"
    }

    $logLines = @()
    if (Test-Path -LiteralPath $logPath) {
        $logLines = Get-Content -LiteralPath $logPath
        $logLines
    }

    if ($process.ExitCode -ne 0) {
        throw "Godot smoke test exited with code $($process.ExitCode): $Script"
    }

    # Godot's standalone script runner can return zero after an assertion even
    # though it emitted a script error and only stopped because of the frame guard.
    if ($logLines | Select-String -SimpleMatch 'SCRIPT ERROR:' -Quiet) {
        throw "Godot reported a script error: $Script"
    }
}
finally {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
}
