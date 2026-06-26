# PSScriptAnalyzer suppressions:
# PSAvoidGlobalVars: $Global:LogFilePath is the documented legacy fallback for consumers
#   that set this before importing the module. Intentional, not accidental global use.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
param()

function Resolve-WitnessLogPath {
    <#
    .SYNOPSIS
        Resolves the active log file path using a deterministic layered lookup.

    .DESCRIPTION
        Shared by Write-Log and Write-LogFinal. Walks three resolution layers in order:

          1. CallerResolved -- the value the public caller already resolved from its
             own parameter and caller-scope check. Pass $null if nothing was found.
          2. $script:WitnessLogFilePath -- set by Initialize-Log.
          3. $Global:LogFilePath -- legacy dot-source back-compat fallback.

        Returns $null when no layer yields a non-whitespace value.

    .PARAMETER CallerResolved
        The path the public caller already resolved from its parameter and caller-scope
        check. Pass $null or empty string if those layers yielded nothing.

    .OUTPUTS
        System.String -- the resolved path, or $null.

    .EXAMPLE
        $path = Resolve-WitnessLogPath -CallerResolved $userSuppliedPath
        if (-not $path) { throw 'No log path available.' }

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    6/18/2026 11:15 AM                              -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2026 Synapse Co.                                -
        =  Organization:  Divergent Cortex                                -
        -  Version:       2026.06.18.001                                  -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CallerResolved
    )

    if (-not [string]::IsNullOrWhiteSpace($CallerResolved)) {
        return $CallerResolved
    }

    if (-not [string]::IsNullOrWhiteSpace($script:WitnessLogFilePath)) {
        return $script:WitnessLogFilePath
    }

    if (Test-Path Variable:Global:LogFilePath) {
        $glbPath = $Global:LogFilePath
        if (-not [string]::IsNullOrWhiteSpace($glbPath)) {
            return $glbPath
        }
    }

    return $null
}
