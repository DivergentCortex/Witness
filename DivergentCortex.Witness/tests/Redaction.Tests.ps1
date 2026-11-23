# Redaction tests for DivergentCortex.Witness.
# Runs the shared cases in ts/tslogger/tests/redaction_cases.json, which pylogger, tslogger and
# shlogger run too, so every language logger must produce identical text.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
# The modules root is MODULES_ROOT when set, else the directory the suite is run from
# (documented: run from the modules root).
$modulesRoot = if ($env:MODULES_ROOT) { $env:MODULES_ROOT } else { (Get-Location).Path }
$casesPath = Join-Path $modulesRoot 'ts/tslogger/tests/redaction_cases.json'
if (-not (Test-Path -LiteralPath $casesPath)) {
    Write-Output "FAIL: shared cases not found at $casesPath (run from the modules root or set MODULES_ROOT)"
    exit 1
}
Import-Module $moduleRoot -Force

$script:Failures = 0
function Assert-That {
    param([string]$Description, [bool]$Condition)
    if ($Condition) { Write-Output "PASS: $Description" }
    else { Write-Output "FAIL: $Description"; $script:Failures++ }
}

$module = Get-Module DivergentCortex.Witness
$cases = Get-Content -LiteralPath $casesPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($case in $cases) {
    $actual = & $module { param($text) ConvertTo-WitnessRedactedText -Text $text } $case.input
    Assert-That "redact: $($case.name)" ($actual -ceq $case.expected)
}

$longRun = 'a' * 200000
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$null = & $module { param($text) ConvertTo-WitnessRedactedText -Text $text } $longRun
$timer.Stop()
Assert-That "a 200000 character unbroken run redacts in $([int]$timer.Elapsed.TotalMilliseconds) ms (limit 2000 ms)" ($timer.Elapsed.TotalMilliseconds -lt 2000)

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) "witness-redaction-test-$PID"
$logPath = Join-Path $workDir 'redact.log'
Initialize-Log -LogFilePath $logPath -ScriptName 'RedactionTest' -Version '1.0'
Write-Log -Message 'pushing with ghp_A1b2C3d4E5f6G7h8I9j0 to https://bob:hunter2hunter2@host/r.git' -Severity Info -WriteBackToHost:$false
$content = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8

Assert-That 'log file holds neither the token nor the password' (-not $content.Contains('ghp_A1b2C3d4E5f6G7h8I9j0') -and -not $content.Contains('hunter2hunter2'))
Assert-That 'log file line carries the redacted message' ($content.Contains('<![LOG[pushing with [REDACTED] to https://bob:[REDACTED]@host/r.git]LOG]!>'))

if ($script:Failures -gt 0) { exit 1 }
exit 0
