function Initialize-Log {
    <#
    .SYNOPSIS
        Initializes the module log path and writes a structured session-start banner.

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
        Call Initialize-Log once at the start of a script or session. It stores the
        resolved log file path in module scope so all subsequent Write-Log calls can
        find it without an explicit -Logfile argument.

        Log path resolution order (first non-empty wins):
          1. -LogFilePath parameter passed to this call.
          2. $LogFilePath in the caller's scope (dot-source back-compat).
          3. $Global:LogFilePath (legacy global fallback via Resolve-WitnessLogPath).

        After resolving the path, Initialize-Log writes a fixed session-start banner
        directly to the log file, bypassing the Verbose/Debug gate. The banner records
        who is running, on what host, under which identity, and where the log lives.
        This context must always be present in the file regardless of gate settings.

        Calling Initialize-Log a second time (e.g., when switching log targets mid-script)
        resets the auto-cleanup sentinel so the new log directory gets exactly one cleanup
        pass during that session.

        Initialize-Log never throws. When no log path resolves, the module state is left
        unchanged and the failure goes through Write-WitnessFailureLine to the error stream.
        A banner that cannot be written is reported the same way, and the console banner
        still prints.

    .PARAMETER LogFilePath
        Full path to the log file. When omitted, the caller-scope and global fallbacks
        are checked before a missing path is reported. The parent directory is created if
        missing.

    .PARAMETER ScriptName
        Name of the calling script included in the start banner. Auto-detected from
        the call stack when not supplied.

    .PARAMETER Version
        Version string written to the banner VERSION line.

    .OUTPUTS
        None. Side effect: sets $script:WitnessLogFilePath and writes the banner.

    .EXAMPLE
        Initialize-Log -LogFilePath 'C:\Logs\Deploy_20260601.log' -ScriptName 'Deploy' -Version '2.1.0'

        Standard call: explicit path, name, and version. All subsequent Write-Log calls
        in the session use this path automatically.

    .EXAMPLE
        $LogFilePath = Join-Path $env:TEMP "MyScript_$(Get-Date -Format 'yyyyMMdd').log"
        Initialize-Log -ScriptName 'MyScript' -Version '1.0'

        Dot-source back-compat pattern: set $LogFilePath in caller scope before calling
        Initialize-Log without -LogFilePath.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath,

        [Parameter(Mandatory = $false)]
        [string]$ScriptName,

        [Parameter(Mandatory = $false)]
        [string]$Version
    )

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
        Write-WitnessFailureLine -Message 'Initialize-Log: no log file path provided. Pass -LogFilePath, set $LogFilePath in your script scope, or set $Global:LogFilePath before calling Initialize-Log. The log was not initialized.'
        return
    }

    $script:WitnessLogFilePath = $LogFilePath

    # new session, reset cleanup sentinel
    $script:WitnessCleanupRan = $false

    $contextUser = Get-WitnessContextUser

    if ([string]::IsNullOrWhiteSpace($ScriptName)) {
        try {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $ScriptName = $callStack[1].ScriptName | Split-Path -Leaf
            }
            if ([string]::IsNullOrWhiteSpace($ScriptName)) { $ScriptName = 'Unknown Script' }
        }
        catch {
            Write-WitnessFailureLine -LogPath $LogFilePath -ContextUser $contextUser -Message "Initialize-Log: script name lookup failed: $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
            $ScriptName = 'Unknown Script'
        }
    }

    $ctx = Get-PlatformContext

    # CMSite PSDrive breaks filesystem ops - same guard as Write-Log uses
    $originalLocation = Get-Location
    $isSCCMDrive = $false
    if ($script:WitnessIsWindows) {
        if ($null -ne $originalLocation.Provider -and $originalLocation.Provider.Name -eq 'CMSite') {
            $isSCCMDrive = $true
            Set-Location C:
        }
    }

    try {
        New-WitnessLogDirectory -LogPath $LogFilePath -ContextUser $contextUser | Out-Null

        # bypass Write-Log so banner always appears regardless of gate settings
        $now = Get-Date
        $LogDate = $now.ToString('MM-dd-yyyy')
        $LogTime = $now.ToString('HH:mm:ss.fff')

        $bannerLines = @(
            "===============================================================================",
            "SCRIPT START: $ScriptName",
            "TIME:         $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "IDENTITY:     $($ctx.IdentityName)",
            "CONTEXT:      $(if ($ctx.IsSystem) { 'SYSTEM' } else { 'USER' }), Admin=$($ctx.IsAdmin)",
            "PLATFORM:     $($ctx.Platform)",
            "ENV USER:     $($ctx.UserDomainName)\$($ctx.UserName)",
            "INTERACTIVE:  $($ctx.InteractiveUser)",
            "SESSION:      $($ctx.SessionType)",
            "HOST:         $($ctx.HostName)",
            "PID:          $($ctx.ProcessId)",
            "LOG:          $LogFilePath",
            "VERSION:      $Version",
            "==============================================================================="
        )

        Write-WitnessBannerFile -LogPath $LogFilePath -Lines $bannerLines -LogTime $LogTime -LogDate $LogDate -ContextUser $contextUser | Out-Null

        # the banner prints on screen regardless of debug or verbose gate settings
        foreach ($line in $bannerLines) {
            Write-Host $line -ForegroundColor Cyan
        }
    }
    finally {
        if ($isSCCMDrive) {
            Restore-WitnessLocation -Location $originalLocation | Out-Null
        }
    }
}
