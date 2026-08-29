<#
.SYNOPSIS
    Runs the canonical GoHardAPP verification sequence (format, analyze, test).

.DESCRIPTION
    Mirrors the check order documented in CLAUDE.md's Verification section.
    Applies formatting, then re-verifies, analyzes, and finally runs tests.
    Stops immediately with a non-zero exit code on the first failure.
#>

$ErrorActionPreference = "Stop"

# Resolve the repository root from this script's location so the script
# works no matter which directory it is invoked from.
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    function Invoke-Step {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Command,
            [Parameter(Mandatory = $true)][string[]]$Arguments
        )

        Write-Host "==> $Name" -ForegroundColor Cyan
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            Write-Host "==> FAILED: $Name (exit code $LASTEXITCODE)" -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }

    Invoke-Step -Name "Applying dart format" -Command "dart" -Arguments @("format", ".")
    Invoke-Step -Name "Verifying formatting (dart format --set-exit-if-changed)" -Command "dart" -Arguments @("format", "--output=none", "--set-exit-if-changed", ".")
    Invoke-Step -Name "Running flutter analyze" -Command "flutter" -Arguments @("analyze")
    Invoke-Step -Name "Running flutter test" -Command "flutter" -Arguments @("test", "--concurrency=1")

    Write-Host "==> All verification steps passed." -ForegroundColor Green
}
finally {
    Pop-Location
}
