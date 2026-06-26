function Initialize-Log {
    <#
    .SYNOPSIS
        Initializes the log file path and writes a structured start banner.

    .DESCRIPTION
        Call Initialize-Log once at script start. It stores the log file path in module
        scope so all subsequent Write-Log calls resolve the path automatically.
        Also runs the platform context adapter (Get-PlatformContext) once for the banner.

        Calling Initialize-Log a second time (e.g., when switching to a new log file)
        resets the auto-cleanup guard so the new log tree gets cleaned.

    .PARAMETER LogFilePath
        Full path to the log file. If omitted, reads $LogFilePath from the caller's scope
        or $Global:LogFilePath (back-compat).

    .PARAMETER ScriptName
        Name of the calling script. Auto-detected from the call stack if not provided.

    .PARAMETER Version
        Version string to include in the start banner.

    .EXAMPLE
        Initialize-Log -LogFilePath "C:\Logs\MyScript_20260601.log" -ScriptName "MyScript" -Version "1.0"

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    11/08/2022 9:30 AM                              -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2022 Synapse Co.                                -
        =  Organization:  Divergent Cortex                                =
        -  Version:       2024.01.15.004                                  -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath,

        [string]$ScriptName,

        [string]$Version
    )

    # layer 1: explicit param wins; layer 2: caller scope for scripts that set $LogFilePath directly
    # layers 3+ delegated to Resolve-WitnessLogPath
    $callerCandidate = $null
    if ($PSBoundParameters.ContainsKey('LogFilePath') -and -not [string]::IsNullOrWhiteSpace($LogFilePath)) {
        $callerCandidate = $LogFilePath
    }
    else {
        $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
        if (-not [string]::IsNullOrWhiteSpace($callerScopePath)) {
            $callerCandidate = $callerScopePath
        }
    }
    $LogFilePath = Resolve-WitnessLogPath -CallerResolved $callerCandidate

    if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
        throw "Initialize-Log: No log file path provided. Pass -LogFilePath, set `$LogFilePath in your script scope, or set `$Global:LogFilePath before calling Initialize-Log."
    }

    $script:WitnessLogFilePath = $LogFilePath

    # each Initialize-Log call is a new session -- reset so cleanup fires once for the new log tree
    $script:WitnessCleanupRan = $false

    # call stack gives us the filename of whatever sourced Initialize-Log
    if ([string]::IsNullOrWhiteSpace($ScriptName)) {
        try {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $ScriptName = $callStack[1].ScriptName | Split-Path -Leaf
            }
            if ([string]::IsNullOrWhiteSpace($ScriptName)) {
                $ScriptName = 'Unknown Script' 
            }
        }
        catch {
            $ScriptName = 'Unknown Script'
        }
    }

    # local variable only -- $script:WitnessContext was dead state never read after this returns
    $ctx = Get-PlatformContext

    # start banner -- everything debug so it only shows when debug output is on
    Write-Log -Message '===============================================================================' -Severity Verbose
    Write-Log -Message "SCRIPT START: $ScriptName" -Severity Debug
    Write-Log -Message "TIME:         $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Severity Debug
    Write-Log -Message "IDENTITY:     $($ctx.IdentityName)" -Severity Debug
    Write-Log -Message "CONTEXT:      $(if ($ctx.IsSystem) { 'SYSTEM' } else { 'USER' }), Admin=$($ctx.IsAdmin)" -Severity Debug
    Write-Log -Message "PLATFORM:     $($ctx.Platform)" -Severity Debug
    Write-Log -Message "ENV USER:     $($ctx.UserDomainName)\$($ctx.UserName)" -Severity Debug
    if ($ctx.InteractiveUser) {
        Write-Log -Message "INTERACTIVE:  $($ctx.InteractiveUser)" -Severity Debug
    }
    Write-Log -Message "HOST:         $($ctx.HostName)" -Severity Debug
    Write-Log -Message "PID:          $($ctx.ProcessId)" -Severity Debug
    Write-Log -Message "LOG:          $LogFilePath" -Severity Debug
    Write-Log -Message "VERSION:      $Version" -Severity Debug
    Write-Log -Message '===============================================================================' -Severity Verbose
}
