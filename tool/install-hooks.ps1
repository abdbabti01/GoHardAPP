<#
.SYNOPSIS
    Configures this repository to use the tracked Git hooks in .githooks/.

.DESCRIPTION
    Sets core.hooksPath to .githooks for this repository only. Does not
    touch global Git configuration, so other repositories are unaffected.
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    git config core.hooksPath .githooks
    Write-Host "==> core.hooksPath set to .githooks for this repository." -ForegroundColor Green
}
finally {
    Pop-Location
}
