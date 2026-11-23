<#
.SYNOPSIS
    Runs the Witness Pester suites through the module diagnostic surface.
.PARAMETER Suite
    Pester filenames under tests, run independently for per-suite totals.
.OUTPUTS
    Suite summaries with counts and a nonzero process exit on failure.
#>
[CmdletBinding()]
param (
    [ValidateSet('DivergentCortex.Witness.Tests.ps1', 'Witness.FailurePath.Tests.ps1')]
    [string[]]$Suite = @('DivergentCortex.Witness.Tests.ps1', 'Witness.FailurePath.Tests.ps1')
)

Import-Module (Join-Path $PSScriptRoot 'DivergentCortex.Witness.psd1') -Force -ErrorAction Stop
$testLog = Join-Path $PSScriptRoot ("logs/test.witness_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
Initialize-Log -LogFilePath $testLog -ScriptName 'Invoke-WitnessTests'

$exitCode = 0
$pesterReady = $false
try {
    Write-Log -Message 'Loading Pester v5 for Witness verification' -Severity Info
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $pesterReady = (Get-Module Pester).Version.Major -eq 5
    if ($pesterReady) {
        Write-Log -Message "Pester $((Get-Module Pester).Version) loaded" -Severity Success
    }
    else {
        Write-Log -Message 'Witness verification requires Pester major version 5' -Severity Error
        $exitCode = 1
    }
}
catch {
    Write-Log -Message "Pester import failed: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
    $exitCode = 1
}

# retain the canonical command when a suite unloads its module
$witnessWriter = Get-Command Write-Log
if ($pesterReady) {
    foreach ($name in $Suite) {
        $witnessReady = $false
        try {
            & $witnessWriter -Logfile $testLog -Message "Loading Witness for suite '$name'" -Severity Info
            Import-Module (Join-Path $PSScriptRoot 'DivergentCortex.Witness.psd1') -Force -ErrorAction Stop
            $witnessWriter = Get-Command Write-Log -ErrorAction Stop
            $witnessReady = $true
            & $witnessWriter -Logfile $testLog -Message "Witness loaded for suite '$name'" -Severity Success
        }
        catch {
            & $witnessWriter -Logfile $testLog -Message "Witness import failed for suite '$name': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            [pscustomobject]@{ Suite = $name; Total = 0; Passed = 0; Failed = 1; Skipped = 0; Result = 'ImportFailed' }
            $exitCode = 1
        }
        if (-not $witnessReady) {
            continue
        }
        $testPath = Join-Path $PSScriptRoot "tests/$name"
        $configuration = New-PesterConfiguration
        $configuration.Run.Path = $testPath
        $configuration.Run.PassThru = $true
        $configuration.Output.Verbosity = 'None'
        try {
            & $witnessWriter -Logfile $testLog -Message "Running Witness suite $name" -Severity Info
            $result = Invoke-Pester -Configuration $configuration 6>$null
            $summary = [pscustomobject]@{
                Suite = $name
                Total = $result.TotalCount
                Passed = $result.PassedCount
                Failed = $result.FailedCount
                Skipped = $result.SkippedCount
                Result = $result.Result
            }
            $summary
            if ($result.Result -eq 'Passed' -and $result.TotalCount -gt 0) {
                & $witnessWriter -Logfile $testLog -Message "$name passed=$($result.PassedCount) failed=$($result.FailedCount) skipped=$($result.SkippedCount) total=$($result.TotalCount)" -Severity Success
            }
            else {
                & $witnessWriter -Logfile $testLog -Message "$name result=$($result.Result) failed=$($result.FailedCount) total=$($result.TotalCount)" -Severity Error
                foreach ($failure in $result.Failed) {
                    & $witnessWriter -Logfile $testLog -Message "$($failure.ExpandedPath): $($failure.ErrorRecord)" -Severity Error
                }
                $exitCode = 1
            }
        }
        catch {
            & $witnessWriter -Logfile $testLog -Message "Witness suite '$testPath' failed: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            $exitCode = 1
        }
    }
}

exit $exitCode
