function Write-Log {
    <#
    .SYNOPSIS
        Writes a CMTrace-compatible log entry and optional color-coded console output.

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
        Write-Log is the primary logging surface for the DivergentCortex.Witness module.
        Each call produces one CMTrace-format line appended to the resolved log file and,
        when WriteBackToHost is true, a color-coded console line keyed to severity.

        Log path resolution order (first non-empty wins):
          1. -Logfile parameter passed directly to this call.
          2. $LogFilePath in the caller's scope (dot-source back-compat).
          3. $script:WitnessLogFilePath set by Initialize-Log.
          4. $Global:LogFilePath (legacy global fallback).

        Severity gates: Verbose and Debug are suppressed on both console and log file by
        default. Each surface is independently controlled via $Global:VerboseConsole,
        $Global:VerboseLogfile, $Global:DebugConsole, $Global:DebugLogfile or their
        $script:Witness* equivalents set in the module loader.

        The CMTrace field order is locked: time, date, component, context, type, thread, file.
        Timestamps use local time with no UTC offset (HH:mm:ss.fff).

        On log file size >= MaxSizeMB, the current file is renamed with an _rNN suffix and
        a new file is started. Auto-cleanup of aged logs runs once per session.

        SCCM/CMSite drive: if the PowerShell working directory is a CMSite PSDrive the
        function temporarily sets location to C: for filesystem operations and restores it.

        Failures inside the logger (a rotation, a locked file, a folder that cannot be
        created, a missing log path) never throw. The logger cannot report through itself, so
        each failure goes through Write-WitnessFailureLine: one CMTrace Warning line appended
        straight to the log file, or to the error stream when there is no usable log file.

    .PARAMETER Message
        The text to log. Accepts pipeline input.

    .PARAMETER Logfile
        Absolute path to the log file. When omitted, resolved via the layered lookup
        described above. Must be a writable filesystem path.

    .PARAMETER Severity
        CMTrace severity level. Accepted values: Info, Information, Warning, Error,
        Verbose, Debug, Success. Information is normalized to Info at runtime.
        Default: Info.

        Success is a console-only distinction: it produces a green-labeled console line
        but writes type 1 (Info) to the log file. CMTrace has no native Success type;
        file consumers see Success entries as Info.

    .PARAMETER Component
        Source component label written to the CMTrace component= field. Auto-detected
        from the PowerShell call stack when not supplied.

    .PARAMETER WriteBackToHost
        When true, emits a color-coded line to the console in addition to the log file.
        Default: true.

    .PARAMETER MaxRetries
        Number of retry attempts when the log file is locked by another process.
        Default: 3.

    .PARAMETER RetryDelay
        Seconds to pause between lock-retry attempts. Accepts fractional values.
        Default: 0.5.

    .PARAMETER Color
        Overrides the default console foreground color for the message text. The severity
        label color is not affected. Accepts any [System.ConsoleColor] value.

    .OUTPUTS
        None. All output goes to the log file and/or console.

    .EXAMPLE
        Initialize-Log -LogFilePath 'C:\Logs\Deploy.log' -ScriptName 'Deploy' -Version '2.1'
        Write-Log -Message 'Starting deployment' -Severity Info

        Standard usage: initialize once at script start, then call Write-Log for each entry.

    .EXAMPLE
        try {
            Get-Service -Name 'NonExistent' -ErrorAction Stop
        } catch {
            Write-Log -Message $_.Exception.Message -Severity Error
        }

        Log a caught exception as an Error entry.

    .EXAMPLE
        'Step 1 complete', 'Step 2 complete' | Write-Log -Severity Info -WriteBackToHost:$false

        Pipeline input: pipe message strings directly to Write-Log.
    #>
    [CmdletBinding(SupportsShouldProcess = $false)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Logfile,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [Alias('LogLevel', 'Type', 'level')]
        [string]$Severity = 'Info',

        [Parameter(Mandatory = $false)]
        [string]$Component,

        [Parameter(Mandatory = $false)]
        [bool]$WriteBackToHost = $true,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 10)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0.0, 30.0)]
        [double]$RetryDelay = 0.5,

        [Parameter(Mandatory = $false)]
        [System.ConsoleColor]$Color
    )

    process {
        $callerCandidate = $null
        if ($PSBoundParameters.ContainsKey('Logfile') -and -not [string]::IsNullOrWhiteSpace($Logfile)) {
            $callerCandidate = $Logfile
        }
        else {
            $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
            if (-not [string]::IsNullOrWhiteSpace($callerScopePath)) {
                $callerCandidate = $callerScopePath
            }
        }
        $resolvedLogfile = Resolve-WitnessLogPath -CallerResolved $callerCandidate

        if ([string]::IsNullOrWhiteSpace($resolvedLogfile)) {
            Write-WitnessFailureLine -Message 'Write-Log: no log file path set. Call Initialize-Log -LogFilePath first, or set $LogFilePath in your script scope before calling Write-Log. The entry was not written.'
            return
        }

        $autoCleanup = $script:WitnessAutoCleanup
        if (Test-Path Variable:Global:WriteLogAutoCleanup) { $autoCleanup = $Global:WriteLogAutoCleanup }

        $maxSizeMB = $script:WitnessMaxSizeMB
        if (Test-Path Variable:Global:WriteLogMaxSizeMB) { $maxSizeMB = $Global:WriteLogMaxSizeMB }

        $maxAgeDays = $script:WitnessMaxAgeDays
        if (Test-Path Variable:Global:WriteLogMaxAgeDays) { $maxAgeDays = $Global:WriteLogMaxAgeDays }

        # GetVariableValue crosses the module boundary, direct read cant
        $callerDebugPref   = $PSCmdlet.GetVariableValue('DebugPreference')
        $callerVerbosePref = $PSCmdlet.GetVariableValue('VerbosePreference')
        $nativeDebugActive   = ($null -ne $callerDebugPref)   -and ($callerDebugPref   -ne 'SilentlyContinue')
        $nativeVerboseActive = ($null -ne $callerVerbosePref) -and ($callerVerbosePref -ne 'SilentlyContinue')

        $verboseToConsole = $script:WitnessVerboseConsole
        if (Test-Path Variable:Global:VerboseConsole) { $verboseToConsole = $Global:VerboseConsole }

        $verboseToLogfile = $script:WitnessVerboseLogfile
        if (Test-Path Variable:Global:VerboseLogfile) { $verboseToLogfile = $Global:VerboseLogfile }

        $debugToConsole = $script:WitnessDebugConsole
        if (Test-Path Variable:Global:DebugConsole) { $debugToConsole = $Global:DebugConsole }

        $debugToLogfile = $script:WitnessDebugLogfile
        if (Test-Path Variable:Global:DebugLogfile) { $debugToLogfile = $Global:DebugLogfile }

        # native preference overrides per-surface flags
        if ($nativeVerboseActive) { $verboseToConsole = $true; $verboseToLogfile = $true }
        if ($nativeDebugActive)   { $debugToConsole   = $true; $debugToLogfile   = $true }

        if ($Severity -eq 'Information') { $Severity = 'Info' }

        # redact before any sink sees the text
        $Message = ConvertTo-WitnessRedactedText -Text $Message

        if ($Severity -eq 'Verbose' -and (-not $verboseToConsole) -and (-not $verboseToLogfile)) { return }
        if ($Severity -eq 'Debug' -and (-not $debugToConsole) -and (-not $debugToLogfile)) { return }

        # CMSite provider breaks filesystem ops
        $originalLocation = Get-Location
        $isSCCMDrive = $false
        if ($script:WitnessIsWindows) {
            if ($null -ne $originalLocation.Provider -and $originalLocation.Provider.Name -eq 'CMSite') {
                $isSCCMDrive = $true
                Set-Location C:
            }
        }

        try {
            $callStack = Get-PSCallStack
            $Source = 'Unknown'
            $callerFunctionName = 'Unknown'
            $lineNumber = '?'

            if ($null -ne $callStack -and $callStack.Count -gt 1) {
                $callerInfo = $callStack[1]
                if ($callerInfo.Location) { $Source = $callerInfo.Location }
                if ($callerInfo.ScriptLineNumber) { $lineNumber = $callerInfo.ScriptLineNumber }
                if ($callerInfo.Command) {
                    $callerFunctionName = $callerInfo.Command
                    if ($callerFunctionName -like '*.ps1') {
                        $callerFunctionName = [System.IO.Path]::GetFileNameWithoutExtension($callerFunctionName)
                    }
                }
            }

            if ([string]::IsNullOrEmpty($Component)) {
                if ($callerFunctionName -ne 'Unknown' -and $callerFunctionName -notlike '*.ps1') {
                    $Component = $callerFunctionName
                }
                else {
                    $callerComponent = $PSCmdlet.SessionState.PSVariable.GetValue('Component')
                    if (-not [string]::IsNullOrEmpty($callerComponent)) {
                        $Component = $callerComponent
                    }
                    else {
                        $Component = $callerFunctionName
                    }
                }
            }
            if ([string]::IsNullOrEmpty($Component) -or $Component -eq 'Unknown') {
                if ($callStack.Count -gt 1 -and $null -ne $callStack[1].InvocationInfo -and $null -ne $callStack[1].InvocationInfo.MyCommand) {
                    $Component = $callStack[1].InvocationInfo.MyCommand.Name
                }
                if ([string]::IsNullOrEmpty($Component)) { $Component = 'Unknown' }
            }

            # local time, utc confuses operators
            $DateTime = Get-Date
            $LogDate = $DateTime.ToString('MM-dd-yyyy')
            $LogTime = $DateTime.ToString('HH:mm:ss.fff')

            # cmtrace expects integer type codes
            $severityType = '1'
            if ($Severity -eq 'Error') { $severityType = '3' }
            elseif ($Severity -eq 'Warning') { $severityType = '2' }
            elseif ($Severity -eq 'Verbose') { $severityType = '4' }
            elseif ($Severity -eq 'Debug') { $severityType = '5' }

            # re-resolve per write for impersonation changes
            $contextUser = Get-WitnessContextUser

            $logline = "<![LOG[$Message]LOG]!>" +
                "<time=`"$LogTime`" " +
                "date=`"$LogDate`" " +
                "component=`"$Component`" " +
                "context=`"$contextUser`" " +
                "type=`"$severityType`" " +
                "thread=`"$PID`" " +
                "file=`"$Source`">"

            New-WitnessLogDirectory -LogPath $resolvedLogfile -ContextUser $contextUser | Out-Null

            $shouldWriteConsole = $true
            if ($Severity -eq 'Verbose') { $shouldWriteConsole = $verboseToConsole }
            elseif ($Severity -eq 'Debug') { $shouldWriteConsole = $debugToConsole }

            if ($WriteBackToHost -and $shouldWriteConsole) {
                $messageColor = $null
                if ($PSBoundParameters.ContainsKey('Color')) { $messageColor = [string]$Color }
                Write-WitnessConsoleLine -Severity $Severity -Component $Component -LineNumber "$lineNumber" -Message $Message -MessageColor $messageColor
            }

            $shouldWriteLogfile = $true
            if ($Severity -eq 'Verbose') { $shouldWriteLogfile = $verboseToLogfile }
            elseif ($Severity -eq 'Debug') { $shouldWriteLogfile = $debugToLogfile }

            if ($shouldWriteLogfile -and (Test-Path $resolvedLogfile)) {
                Invoke-WitnessRotation -LogPath $resolvedLogfile -MaxSizeMB $maxSizeMB -LogTime $LogTime -LogDate $LogDate -ContextUser $contextUser | Out-Null
            }

            # sentinel is set before the cleanup call to prevent recursion
            Invoke-WitnessAutoCleanup -LogPath $resolvedLogfile -AutoCleanup $autoCleanup -MaxAgeDays $maxAgeDays -ContextUser $contextUser

            # readwrite share so concurrent readers arent blocked
            if ($shouldWriteLogfile) {
                Add-WitnessLogLine -LogPath $resolvedLogfile -Line $logline -MaxRetries $MaxRetries -RetryDelay $RetryDelay -LogTime $LogTime -LogDate $LogDate -ContextUser $contextUser | Out-Null
            }
        }
        finally {
            if ($isSCCMDrive) {
                Restore-WitnessLocation -Location $originalLocation
            }
        }
    }
}
