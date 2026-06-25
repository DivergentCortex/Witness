function Resolve-WitnessLogPath {
    <#
    .SYNOPSIS
        Resolves the active log file path using a layered lookup.

    .DESCRIPTION
        Shared path resolver used by Write-Log and Write-LogFinal. Walks a
        deterministic resolution order:

            1. CallerResolved (explicit param or caller-scope value, passed in by
               the public function that already checked those layers).
            2. $script:WitnessLogFilePath (set by Initialize-Log).
            3. $Global:LogFilePath (dot-source back-compat).

        Returns $null if no layer yields a value.

    .PARAMETER CallerResolved
        The value the public caller already resolved from its own parameter and
        caller-scope lookup. Pass $null if nothing was found at those layers.

    .EXAMPLE
        $path = Resolve-WitnessLogPath -CallerResolved $userSuppliedPath

    .NOTES
        =========================================
        Curtis Leggett & S.Henry
        Divergent Cortex
        =========================================
    #>
    [CmdletBinding()]
    param(
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
