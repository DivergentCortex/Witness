function Write-LogFinal {
    <#
    .SYNOPSIS
        Writes a final log message and triggers the log cleanup routine.

    .DESCRIPTION
        Use Write-LogFinal as the last log call in a script. It writes the supplied
        message, emits a verbose notice, then runs Clear-LogFile against the log folder.
        Respects the module-scope cleanup sentinel ($script:WitnessCleanupRan) so cleanup
        never runs twice in a session regardless of call order.

        Calling Initialize-Log a second time resets the cleanup sentinel so a new session
        gets exactly one cleanup pass.

    .PARAMETER Message
        The final message to log.

    .PARAMETER Severity
        Log level: Info, Information, Warning, Error, Verbose, Debug, Success. Default: Info.

    .EXAMPLE
        Write-LogFinal -Message "Script completed successfully." -Severity Info

    .EXAMPLE
        Write-LogFinal -Message "Script completed." -Severity Success

    .NOTES
        =========================================
        Curtis Leggett & S.Henry
        Divergent Cortex
        =========================================
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [string]$Severity = 'Info'
    )

    Write-Log -Message $Message -Severity $Severity
    Write-Log -Message 'Final log entry: Triggering log cleanup.' -Severity Verbose

    # ---- Double-cleanup guard (Fix [1]) ----
    # If Write-Log already ran auto-cleanup this session, skip it here.
    if ($script:WitnessCleanupRan) {
        return
    }

    # ---- Config-aware retention (Fix [R1]) ----
    # Resolve MaxAgeDays using the same module-scope / global-override chain Write-Log uses.
    # Both cleanup paths must apply the same retention policy.
    $maxAgeDays = $script:WitnessMaxAgeDays
    if (Test-Path Variable:Global:WriteLogMaxAgeDays) { $maxAgeDays = $Global:WriteLogMaxAgeDays }

    # ---- Resolve log file path (Fix [2], Fix [1/3]) ----
    $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
    $resolvedPath    = Resolve-WitnessLogPath -CallerResolved $callerScopePath

    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        # Fix [R3]: set sentinel before returning so no future path can trigger cleanup
        # in this session via a retry or a second Write-LogFinal call.
        $script:WitnessCleanupRan = $true
        Write-Log -Message 'Write-LogFinal: Cannot determine log folder - skipping cleanup.' -Severity Warning
        return
    }

    $logFolder = Split-Path $resolvedPath
    if ([string]::IsNullOrWhiteSpace($logFolder) -or -not (Test-Path $logFolder)) {
        $script:WitnessCleanupRan = $true  # Fix [R3]: same invariant on this return path
        Write-Log -Message "Write-LogFinal: Log folder not found at '$logFolder' - skipping cleanup." -Severity Warning
        return
    }

    $script:WitnessCleanupRan = $true  # set before calling to prevent any recursion path
    try {
        Clear-LogFile -LogFolder $logFolder -MaxAgeDays $maxAgeDays
    } catch {
        Write-Log -Message "Log cleanup failed: $_" -Severity Error
    }
}
