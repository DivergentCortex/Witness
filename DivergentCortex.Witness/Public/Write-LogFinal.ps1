function Write-LogFinal {
    <#
    .SYNOPSIS
        Writes a final log entry and triggers the session-end log cleanup pass.

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
        Use Write-LogFinal as the last log call in a script. It writes the supplied
        message at the given severity, then runs Clear-LogFile against the log directory
        to prune logs older than MaxAgeDays.

        The module-scope cleanup sentinel ($script:WitnessCleanupRan) prevents cleanup
        from running twice. If Write-Log already triggered auto-cleanup earlier in the
        session, Write-LogFinal skips it. Calling Initialize-Log resets the sentinel so
        each new session gets exactly one cleanup pass.

        The MaxAgeDays value is read from the same source chain Write-Log uses:
        $script:WitnessMaxAgeDays, overridden by $Global:WriteLogMaxAgeDays when set.
        Both cleanup paths always apply the same retention policy.

    .PARAMETER Message
        The final message to write before cleanup runs.

    .PARAMETER Severity
        CMTrace severity level. Accepted values: Info, Information, Warning, Error,
        Verbose, Debug, Success. Default: Info.

    .OUTPUTS
        None.

    .EXAMPLE
        Write-LogFinal -Message 'Deployment completed successfully.' -Severity Success

        Standard end-of-script call: logs a success entry and triggers cleanup.

    .EXAMPLE
        Write-LogFinal -Message 'Script finished with warnings.' -Severity Warning

        Log a warning as the final entry when the script completed with non-fatal issues.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [string]$Severity = 'Info'
    )

    Write-Log -Message $Message -Severity $Severity

    # dont run cleanup twice
    if ($script:WitnessCleanupRan) {
        return
    }

    $maxAgeDays = $script:WitnessMaxAgeDays
    if (Test-Path Variable:Global:WriteLogMaxAgeDays) { $maxAgeDays = $Global:WriteLogMaxAgeDays }

    $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
    $resolvedPath = Resolve-WitnessLogPath -CallerResolved $callerScopePath

    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        $script:WitnessCleanupRan = $true
        Write-Log -Message 'Write-LogFinal: Cannot determine log folder - skipping cleanup.' -Severity Warning
        return
    }

    $logFolder = Split-Path $resolvedPath
    if ([string]::IsNullOrWhiteSpace($logFolder) -or -not (Test-Path $logFolder)) {
        $script:WitnessCleanupRan = $true
        Write-Log -Message "Write-LogFinal: Log folder not found at '$logFolder' - skipping cleanup." -Severity Warning
        return
    }

    # sentinel before call prevents recursion
    $script:WitnessCleanupRan = $true
    try {
        Clear-LogFile -LogFolder $logFolder -MaxAgeDays $maxAgeDays
    }
    catch {
        Write-Log -Message "Log cleanup failed: $_" -Severity Error
    }
}
