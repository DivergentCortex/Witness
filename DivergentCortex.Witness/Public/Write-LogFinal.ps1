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
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    3/19/2024 1:20 PM                               -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2024 Synapse Co.                                -
        =  Organization:  Divergent Cortex                                =
        -  Version:       2024.09.30.003                                  -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [string]$Severity = 'Info'
    )

    Write-Log -Message $Message -Severity $Severity
    Write-Log -Message 'Final log entry: Triggering log cleanup.' -Severity Verbose

    # Write-Log may have already cleaned up this session -- don't run it twice
    if ($script:WitnessCleanupRan) {
        return
    }

    # same module-scope / global-override chain Write-Log uses -- both paths must agree on retention
    $maxAgeDays = $script:WitnessMaxAgeDays
    if (Test-Path Variable:Global:WriteLogMaxAgeDays) {
        $maxAgeDays = $Global:WriteLogMaxAgeDays 
    }

    # resolve path the same way Write-Log does so we find the right folder
    $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
    $resolvedPath = Resolve-WitnessLogPath -CallerResolved $callerScopePath

    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        # set sentinel even on early return -- a second Write-LogFinal call must not retry cleanup
        $script:WitnessCleanupRan = $true
        Write-Log -Message 'Write-LogFinal: Cannot determine log folder - skipping cleanup.' -Severity Warning
        return
    }

    $logFolder = Split-Path $resolvedPath
    if ([string]::IsNullOrWhiteSpace($logFolder) -or -not (Test-Path $logFolder)) {
        $script:WitnessCleanupRan = $true  # same invariant -- no cleanup without a valid folder
        Write-Log -Message "Write-LogFinal: Log folder not found at '$logFolder' - skipping cleanup." -Severity Warning
        return
    }

    $script:WitnessCleanupRan = $true  # before the call -- Clear-LogFile calls Write-Log
    try {
        Clear-LogFile -LogFolder $logFolder -MaxAgeDays $maxAgeDays
    }
    catch {
        Write-Log -Message "Log cleanup failed: $_" -Severity Error
    }
}
