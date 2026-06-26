function Resolve-WitnessLogPath {
    <#
    .SYNOPSIS
        Resolves the active log file path using a deterministic layered lookup.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    04/23/2023                                      -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2026 Divergent Cortex                           -
        =  Organization:  Divergent Cortex                                =
        -  Version:       1.0.1                                           -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

    .DESCRIPTION
        Shared by Write-Log and Write-LogFinal. Walks three resolution layers in order:

          1. CallerResolved (explicit param or caller-scope value, passed in by
             the public function that already checked those layers).
          2. $script:WitnessLogFilePath (set by Initialize-Log).
          3. $Global:LogFilePath (dot-source back-compat).

        Returns $null when no layer yields a non-whitespace value.

    .PARAMETER CallerResolved
        The path the public caller already resolved from its parameter and caller-scope
        check. Pass $null or empty string if those layers yielded nothing.

    .OUTPUTS
        System.String. The resolved path, or $null.

    .EXAMPLE
        $path = Resolve-WitnessLogPath -CallerResolved $userSuppliedPath
        if (-not $path) { throw 'No log path available.' }
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
