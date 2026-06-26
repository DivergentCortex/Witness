function Initialize-Log {
    <#
    .SYNOPSIS
        Initializes the module log path and writes a structured session-start banner.

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

    .PARAMETER LogFilePath
        Full path to the log file. When omitted, the caller-scope and global fallbacks
        are checked before throwing. The parent directory is created if missing.

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
        throw "Initialize-Log: No log file path provided. Pass -LogFilePath, set `$LogFilePath in your script scope, or set `$Global:LogFilePath before calling Initialize-Log."
    }

    $script:WitnessLogFilePath = $LogFilePath

    # new session, reset cleanup sentinel
    $script:WitnessCleanupRan = $false

    if ([string]::IsNullOrWhiteSpace($ScriptName)) {
        try {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $ScriptName = $callStack[1].ScriptName | Split-Path -Leaf
            }
            if ([string]::IsNullOrWhiteSpace($ScriptName)) { $ScriptName = 'Unknown Script' }
        }
        catch {
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

    $logDir = Split-Path $LogFilePath
    if ($logDir -and !(Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # bypass Write-Log so banner always appears regardless of gate settings
    $now = Get-Date
    $LogDate = $now.ToString('MM-dd-yyyy')
    $LogTime = $now.ToString('HH:mm:ss.fff')

    if ($script:WitnessIsWindows) {
        $contextUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    else {
        $contextUser = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
    }

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

    $fileStream = $null
    $streamWriter = $null
    try {
        $fileMode = [System.IO.FileMode]::Append
        $fileAccess = [System.IO.FileAccess]::Write
        $fileShare = [System.IO.FileShare]::ReadWrite
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        $fileStream = New-Object System.IO.FileStream($LogFilePath, $fileMode, $fileAccess, $fileShare)
        $streamWriter = New-Object System.IO.StreamWriter($fileStream, $utf8NoBom)
        $streamWriter.NewLine = [System.Environment]::NewLine

        foreach ($line in $bannerLines) {
            $entry = "<![LOG[$line]LOG]!>" +
                "<time=`"$LogTime`" " +
                "date=`"$LogDate`" " +
                "component=`"Initialize-Log`" " +
                "context=`"$contextUser`" " +
                "type=`"1`" " +
                "thread=`"$PID`" " +
                "file=`"Initialize-Log.ps1`">"
            $streamWriter.WriteLine($entry)
        }
    }
    catch {
        Write-Warning "Initialize-Log: Failed to write banner to '$LogFilePath': $_"
    }
    finally {
        try { if ($null -ne $streamWriter) { $streamWriter.Dispose() } } catch { }
        try { if ($null -ne $fileStream)   { $fileStream.Dispose()   } } catch { }
        if ($isSCCMDrive) {
            try {
                Set-Location $originalLocation -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning "Initialize-Log: Could not restore CMSite location: $_"
            }
        }
    }
}
