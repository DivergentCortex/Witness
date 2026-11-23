function Invoke-WitnessAutoCleanup {
    <#
    .SYNOPSIS
        Runs the once-per-session age-based log cleanup from the first Write-Log call.

    .DESCRIPTION
        Cleanup runs when auto-cleanup is on, the session sentinel is not yet set and the log file
        exists. The sentinel is set before Clear-LogFile runs so the Write-Log calls Clear-LogFile
        makes cannot start a second pass. A failed cleanup reports through Write-WitnessFailureLine.
        This function never throws.

    .PARAMETER LogPath
        The active log file whose folder is cleaned.

    .PARAMETER AutoCleanup
        Whether auto-cleanup is enabled.

    .PARAMETER MaxAgeDays
        Logs older than this many days are removed.

    .PARAMETER ContextUser
        The identity written to failure lines.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        $AutoCleanup,

        [Parameter(Mandatory = $true)]
        $MaxAgeDays,

        [Parameter(Mandatory = $true)]
        [string]$ContextUser
    )

    if (-not $AutoCleanup) { return }
    if ($script:WitnessCleanupRan) { return }
    if (-not (Test-Path $LogPath)) { return }

    $script:WitnessCleanupRan = $true
    $logFolder = Split-Path $LogPath
    if (-not ($logFolder -and (Test-Path $logFolder))) { return }

    try {
        Clear-LogFile -LogFolder $logFolder -MaxAgeDays $MaxAgeDays
    }
    catch {
        Write-WitnessFailureLine -LogPath $LogPath -ContextUser $ContextUser -Message "Write-Log: auto-cleanup failed in '$logFolder': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
    }
}
