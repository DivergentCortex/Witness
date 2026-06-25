# Private/Resolve-WitnessLogPath.ps1
# Shared path resolver used by Write-Log and Write-LogFinal.
# Cannot read $PSCmdlet.SessionState itself (private functions have no CmdletBinding
# in the caller's runspace), so the caller-scope candidate is passed in as a parameter.
#
# Resolution order (Fix [3] - Codex HIGH):
#   1. Explicit -Logfile / -LogFilePath parameter (passed here as CallerParam)
#   2. Caller's own scope via $PSCmdlet.SessionState (resolved by the PUBLIC function before calling here)
#   3. $script:WitnessLogFilePath (set by Initialize-Log)
#   4. $Global:LogFilePath (dot-source back-compat)

function Resolve-WitnessLogPath {
    [CmdletBinding()]
    param(
        # The value the public caller already resolved from its own param + caller-scope lookup.
        # Pass $null if nothing was found at those layers.
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
