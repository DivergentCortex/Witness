# DivergentCortex.Witness.psm1
# Module loader. Dot-sources Private helpers first, then Public functions.
# Follows fleet helper load order: Private before Public, top-to-bottom within each tier.
#
# Fix references:
#   [3]  $script:WitnessIsWindows set ONCE here with a 5.1-safe probe.
#        PS 5.1 has no $IsWindows automatic variable - its absence means Windows.
#        Every file in this module reads $script:WitnessIsWindows; raw $IsWindows is NEVER used.
#   [12] $script:WitnessCleanupRan initialized to $false here; also reset by Initialize-Log
#        on each new session context (Fix [2]).
#   [13] Module-scope config defaults declared here. Consumers may override via $Global: vars.

Set-StrictMode -Version Latest

# ---- Platform probe (Fix [3]) ----
# Test-Path Variable:IsWindows is false on PS 5.1 (variable does not exist).
# Absence of $IsWindows -> treat as Windows (correct for PS 5.1 which is Windows-only).
$script:WitnessIsWindows = if (Test-Path Variable:IsWindows) {
    $IsWindows 
}
else {
    $true 
}

# ---- Module-scope state ----
$script:WitnessLogFilePath = $null   # Set by Initialize-Log
$script:WitnessCleanupRan = $false  # Set by Write-Log or Write-LogFinal; reset by Initialize-Log
# Note: $script:WitnessContext is intentionally absent. Get-PlatformContext runs once in
# Initialize-Log and its result is held only in a local variable for the banner. It is
# not stored in module scope because Write-Log resolves context= cheaply per write and
# the cached adapter result was dead state (assigned, never read after Initialize-Log returned).

# ---- Config defaults (Fix [13]) ----
# These are the fallback values when the consumer has not set the $Global: equivalents.
$script:WitnessAutoCleanup = $true
$script:WitnessMaxSizeMB = 10
$script:WitnessMaxAgeDays = 7
$script:WitnessVerboseConsole = $false
$script:WitnessVerboseLogfile = $false
$script:WitnessDebugConsole = $false
$script:WitnessDebugLogfile = $false

# ---- Load Private helpers first ----
$privatePath = Join-Path $PSScriptRoot 'Private'
. (Join-Path $privatePath 'Get-PlatformContext.ps1')
. (Join-Path $privatePath 'Clear-LogFile.ps1')
. (Join-Path $privatePath 'Resolve-WitnessLogPath.ps1')

# ---- Load Public functions ----
$publicPath = Join-Path $PSScriptRoot 'Public'
. (Join-Path $publicPath 'Write-Log.ps1')
. (Join-Path $publicPath 'Initialize-Log.ps1')
. (Join-Path $publicPath 'Write-LogFinal.ps1')
