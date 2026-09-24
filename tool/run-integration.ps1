<#
.SYNOPSIS
    Runs integration_test files against the isolated local QA API, resetting
    app state before each file.

.DESCRIPTION
    - Refuses any -ApiHost that is not a local/private address, so these
      write-oriented tests can never be pointed at production.
    - Verifies the QA API is reachable before starting.
    - Clears the app's data (adb shell pm clear) before EACH file so a session
      left behind by one file cannot leak into the next.
    - Runs each file separately, logs it under build/qa-runs/<timestamp>/, and
      reports PASS/FAIL per file from flutter's exit code.
    - Exits non-zero if any file failed.

.EXAMPLE
    .\tool\run-integration.ps1 -Files qa_auth_journey_test.dart
.EXAMPLE
    .\tool\run-integration.ps1 -All
.EXAMPLE
    .\tool\run-integration.ps1 -All -Device emulator-5556
#>
param(
    [string[]]$Files,
    [switch]$All,
    [string]$Device,
    [string]$ApiHost = "http://10.0.2.2:5121",
    [string]$ApiCheckUrl = "http://localhost:5121/swagger/index.html",
    [string]$Package = "com.example.go_hard_app"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    # ---- Safety: only local/private API hosts -------------------------------
    $hostName = ([Uri]$ApiHost).Host
    $isLocal = $hostName -in @("localhost", "127.0.0.1", "10.0.2.2", "10.0.3.2") -or
        $hostName -match '^192\.168\.' -or $hostName -match '^10\.'
    if (-not $isLocal) {
        Write-Host "REFUSING: -ApiHost '$ApiHost' is not a local/private address. These tests write data and must only target the isolated QA API." -ForegroundColor Red
        exit 2
    }

    # ---- Locate adb ---------------------------------------------------------
    $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
    if (-not $adb) {
        $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
        $candidate = Join-Path $sdk "platform-tools\adb.exe"
        if (Test-Path $candidate) { $adb = $candidate }
    }
    if (-not $adb) { Write-Host "adb not found (add platform-tools to PATH or set ANDROID_HOME)." -ForegroundColor Red; exit 2 }

    # ---- Device -------------------------------------------------------------
    if (-not $Device) {
        $Device = (& $adb devices | Select-String -Pattern '^(\S+)\s+device$' | Select-Object -First 1).Matches.Groups[1].Value
    }
    if (-not $Device) { Write-Host "No Android device/emulator connected." -ForegroundColor Red; exit 2 }
    Write-Host "Device: $Device   API host (app): $ApiHost" -ForegroundColor Cyan

    # ---- QA API reachable? (any HTTP response counts; connection failure = down)
    try {
        Invoke-WebRequest -Uri $ApiCheckUrl -UseBasicParsing -TimeoutSec 10 | Out-Null
    } catch {
        if (-not $_.Exception.Response) {
            Write-Host "QA API not reachable at $ApiCheckUrl - start GoHardAPI first (see integration_test/README.md)." -ForegroundColor Red
            exit 2
        }
    }

    # ---- Which files --------------------------------------------------------
    if ($All) {
        $targets = Get-ChildItem (Join-Path $repoRoot "integration_test") -Filter "*_test.dart" | Sort-Object Name | ForEach-Object { $_.Name }
    } elseif ($Files) {
        $targets = $Files | ForEach-Object { Split-Path $_ -Leaf }
    } else {
        Write-Host "Pass -Files <name.dart,...> or -All." -ForegroundColor Red
        exit 2
    }

    $runDir = Join-Path $repoRoot ("build\qa-runs\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null

    $results = @()
    foreach ($file in $targets) {
        $path = "integration_test/$file"
        if (-not (Test-Path (Join-Path $repoRoot $path))) {
            $results += [pscustomobject]@{ File = $file; Result = "MISSING"; Seconds = 0 }
            continue
        }

        # Native tools (adb "Failed" when the app is already uninstalled, flutter
        # warnings) write to stderr; under "Stop", Windows PowerShell 5.1 would
        # treat that as a terminating error instead of an ordinary result.
        $ErrorActionPreference = "Continue"

        # Fresh state + permission pre-granted so the OS dialog can't race the test.
        & $adb -s $Device shell pm clear $Package 2>&1 | Out-Null
        & $adb -s $Device shell pm grant $Package android.permission.POST_NOTIFICATIONS 2>&1 | Out-Null

        Write-Host "==> $file" -ForegroundColor Cyan
        $log = Join-Path $runDir ($file + ".log")
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & flutter test $path -d $Device "--dart-define=API_HOST=$ApiHost" *> $log
        $code = $LASTEXITCODE
        $ErrorActionPreference = "Stop"
        $sw.Stop()

        $text = Get-Content $log -Raw
        # Trust the exit code; also require flutter's own success line so an
        # early/stale exit is never reported as a pass.
        $passed = ($code -eq 0) -and ($text -match "All tests passed!")
        $results += [pscustomobject]@{
            File    = $file
            Result  = $(if ($passed) { "PASS" } else { "FAIL" })
            Seconds = [int]$sw.Elapsed.TotalSeconds
        }
        if (-not $passed) { Write-Host "    FAILED - see $log" -ForegroundColor Red }
    }

    Write-Host ""
    $results | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "Logs: $runDir"
    if ($results | Where-Object { $_.Result -ne "PASS" }) { exit 1 }
    Write-Host "All integration files passed." -ForegroundColor Green
}
finally {
    Pop-Location
}
