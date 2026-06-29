# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# -  Created on:    04/23/2023                                      -
# =  Author:        Curtis Leggett                                  =
# -  Copyright:     2026 Divergent Cortex                           -
# =  Organization:  Divergent Cortex                                =
# -  Version:       1.0.1                                           -
# =-=-                       =-=-=-=-=-=-=-=                     -=-=
# -       The witness is a ghost,                                   -
# =                      yet, somewhere,                            =
# -                             a file is remembering you.          -
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

# DivergentCortex.Witness.psm1
# Module loader. Dot-sources Private helpers first, then Public functions.
# Load order: Private before Public, top-to-bottom within each tier.
#
# [3]  $script:WitnessIsWindows set ONCE here with a 5.1-safe probe.
#      PS 5.1 has no $IsWindows automatic variable; its absence means Windows.
#      Every file in this module reads $script:WitnessIsWindows; raw $IsWindows is never used.
# [12] $script:WitnessCleanupRan initialized to $false here; also reset by Initialize-Log
#      on each new session context.
# [13] Module-scope config defaults declared here. Consumers may override via $Global: vars.

Set-StrictMode -Version Latest

# Platform probe: Test-Path Variable:IsWindows is false on PS 5.1 (variable does not exist).
# Absence of $IsWindows -> treat as Windows, which is correct for PS 5.1 (Windows-only).
$script:WitnessIsWindows = if (Test-Path Variable:IsWindows) {
    $IsWindows 
}
else {
    $true 
}

# Module-scope state
$script:WitnessLogFilePath = $null   # Set by Initialize-Log
$script:WitnessCleanupRan = $false   # Set by Write-Log or Write-LogFinal; reset by Initialize-Log

# Config defaults -- consumers override with $Global: equivalents before or after import.
$script:WitnessAutoCleanup = $true
$script:WitnessMaxSizeMB = 10
$script:WitnessMaxAgeDays = 7
$script:WitnessVerboseConsole = $false
$script:WitnessVerboseLogfile = $false
$script:WitnessDebugConsole = $false
$script:WitnessDebugLogfile = $false

# Load Private helpers first (dependency order: Get-PlatformContext before others).
$privatePath = Join-Path $PSScriptRoot 'Private'
. (Join-Path $privatePath 'Get-PlatformContext.ps1')
. (Join-Path $privatePath 'Clear-LogFile.ps1')
. (Join-Path $privatePath 'Resolve-WitnessLogPath.ps1')

# Load Public functions.
$publicPath = Join-Path $PSScriptRoot 'Public'
. (Join-Path $publicPath 'Write-Log.ps1')
. (Join-Path $publicPath 'Initialize-Log.ps1')
. (Join-Path $publicPath 'Write-LogFinal.ps1')
