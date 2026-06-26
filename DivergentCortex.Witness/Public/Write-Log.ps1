# PSScriptAnalyzer suppressions - justified at function level:
# PSAvoidOverwritingBuiltInCmdlets: Write-Log is the deliberate public name of this module.
#   The "built-in" is Windows-only and not present on Linux/macOS; suppression is correct here.
# PSAvoidGlobalVars: $Global:* vars are a documented back-compat surface for consumers that
#   set these before dot-sourcing or importing. Not accidental global use.
# PSAvoidUsingWriteHost: color-coded severity output is the explicit console feature of this
#   function. Write-Output cannot produce color; Write-Host is correct here.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()

function Write-Log {
    <#
    .SYNOPSIS
        Writes a CMTrace-compatible log entry and optional color-coded console output.

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

    .PARAMETER Message
        The text to log. Accepts pipeline input.

    .PARAMETER Logfile
        Absolute path to the log file. When omitted, resolved via the layered lookup
        described above. Must be a writable filesystem path.

    .PARAMETER Severity
        CMTrace severity level. Accepted values: Info, Information, Warning, Error,
        Verbose, Debug, Success. Information is normalized to Info at runtime.
        Default: Info.

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

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    4/23/2023 2:15 PM                               -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2023 Synapse Co.                                -
        =  Organization:  Divergent Cortex                                =
        -  Version:       2026.06.25.010                                  -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
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
        # Layer 1: explicit param wins; layer 2: caller-scope for dot-source back-compat.
        # Layers 3+ delegated to Resolve-WitnessLogPath.
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
            throw "FATAL: No log file path set. Call Initialize-Log -LogFilePath first, or set `$LogFilePath in your script scope before calling Write-Log."
        }

        # Module-scope defaults; $Global: overrides honored for back-compat with
        # consumers that set these before importing the module.
        $autoCleanup = $script:WitnessAutoCleanup
        if (Test-Path Variable:Global:WriteLogAutoCleanup) { $autoCleanup = $Global:WriteLogAutoCleanup }

        $maxSizeMB = $script:WitnessMaxSizeMB
        if (Test-Path Variable:Global:WriteLogMaxSizeMB) { $maxSizeMB = $Global:WriteLogMaxSizeMB }

        $maxAgeDays = $script:WitnessMaxAgeDays
        if (Test-Path Variable:Global:WriteLogMaxAgeDays) { $maxAgeDays = $Global:WriteLogMaxAgeDays }

        $verboseToConsole = $script:WitnessVerboseConsole
        if (Test-Path Variable:Global:VerboseConsole) { $verboseToConsole = $Global:VerboseConsole }

        $verboseToLogfile = $script:WitnessVerboseLogfile
        if (Test-Path Variable:Global:VerboseLogfile) { $verboseToLogfile = $Global:VerboseLogfile }

        $debugToConsole = $script:WitnessDebugConsole
        if (Test-Path Variable:Global:DebugConsole) { $debugToConsole = $Global:DebugConsole }

        $debugToLogfile = $script:WitnessDebugLogfile
        if (Test-Path Variable:Global:DebugLogfile) { $debugToLogfile = $Global:DebugLogfile }

        # Normalize alias before the severity gate below.
        if ($Severity -eq 'Information') { $Severity = 'Info' }

        # Early exit when both sinks are off for this severity level.
        if ($Severity -eq 'Verbose' -and (-not $verboseToConsole) -and (-not $verboseToLogfile)) { return }
        if ($Severity -eq 'Debug' -and (-not $debugToConsole) -and (-not $debugToLogfile)) { return }

        # SCCM CMSite provider breaks filesystem ops -- escape to C: first.
        $originalLocation = Get-Location
        $isSCCMDrive = $false
        if ($script:WitnessIsWindows) {
            if ($null -ne $originalLocation.Provider -and $originalLocation.Provider.Name -eq 'CMSite') {
                $isSCCMDrive = $true
                Set-Location C:
            }
        }

        try {
            # Walk the call stack to find the immediate caller.
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

            # Resolve component: explicit param > caller function name > caller-scope $Component.
            if ([string]::IsNullOrEmpty($Component)) {
                if ($callerFunctionName -ne 'Unknown' -and $callerFunctionName -notlike '*ps1') {
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

            # Local time intentionally -- UTC offsets confuse operators scanning logs.
            $DateTime = Get-Date
            $LogDate = $DateTime.ToString('MM-dd-yyyy')
            $LogTime = $DateTime.ToString('HH:mm:ss.fff')

            # CMTrace reads type= as an integer code, not a string label.
            $severityType = '1'
            if ($Severity -eq 'Error') { $severityType = '3' }
            elseif ($Severity -eq 'Warning') { $severityType = '2' }
            elseif ($Severity -eq 'Verbose') { $severityType = '4' }
            elseif ($Severity -eq 'Debug') { $severityType = '5' }
            # Info and Success both map to type 1.

            # Resolved per write so impersonation changes mid-session are captured.
            # Non-Windows skips loginctl/who for this -- too expensive per line.
            if ($script:WitnessIsWindows) {
                $contextUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
            else {
                $contextUser = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
            }

            # CMTrace envelope -- field order is locked by the format contract.
            $logline = "<![LOG[$Message]LOG]!>" +
                "<time=`"$LogTime`" " +
                "date=`"$LogDate`" " +
                "component=`"$Component`" " +
                "context=`"$contextUser`" " +
                "type=`"$severityType`" " +
                "thread=`"$PID`" " +
                "file=`"$Source`">"

            # Ensure the log directory exists before the first write.
            $logDir = Split-Path $resolvedLogfile
            if ($logDir -and !(Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }

            # Console and logfile gates are independent: verbose/debug can be silenced on
            # one surface while remaining active on the other.
            $shouldWriteConsole = $true
            if ($Severity -eq 'Verbose') { $shouldWriteConsole = $verboseToConsole }
            elseif ($Severity -eq 'Debug') { $shouldWriteConsole = $debugToConsole }

            if ($WriteBackToHost -and $shouldWriteConsole) {
                $displayComponent = $Component
                if ($displayComponent.Length -gt 12) {
                    $displayComponent = $displayComponent.Substring(0, 10) + '..'
                }

                $severityConfig = @{
                    'Error'   = @{ Label = ' ERROR ';   LabelColor = 'Red';      MessageColor = 'Red' }
                    'Warning' = @{ Label = ' WARNING '; LabelColor = 'Yellow';   MessageColor = 'Yellow' }
                    'Info'    = @{ Label = ' INFO ';    LabelColor = 'Green';    MessageColor = 'White' }
                    'Success' = @{ Label = ' SUCCESS '; LabelColor = 'Green';    MessageColor = 'Green' }
                    'Verbose' = @{ Label = ' VERBOSE '; LabelColor = 'DarkGray'; MessageColor = 'DarkGray' }
                    'Debug'   = @{ Label = ' DEBUG ';   LabelColor = 'Magenta';  MessageColor = 'Magenta' }
                }

                $config = $severityConfig[$Severity]
                $finalMessageColor = if ($PSBoundParameters.ContainsKey('Color')) { $Color } else { $config.MessageColor }

                Write-Host '[' -NoNewline -ForegroundColor Gray
                Write-Host $config.Label -NoNewline -ForegroundColor $config.LabelColor
                Write-Host '] [' -NoNewline -ForegroundColor Gray
                Write-Host "$displayComponent" -NoNewline -ForegroundColor Blue
                Write-Host '] [' -NoNewline -ForegroundColor Gray
                Write-Host "$lineNumber" -NoNewline -ForegroundColor Cyan
                Write-Host ']' -NoNewline -ForegroundColor Gray
                Write-Host ': ' -NoNewline -ForegroundColor Magenta
                Write-Host "$Message" -ForegroundColor $finalMessageColor
            }

            $shouldWriteLogfile = $true
            if ($Severity -eq 'Verbose') { $shouldWriteLogfile = $verboseToLogfile }
            elseif ($Severity -eq 'Debug') { $shouldWriteLogfile = $debugToLogfile }

            # Size-based rotation: rename current file before starting a new one.
            if ($shouldWriteLogfile -and (Test-Path $resolvedLogfile)) {
                $currentSize = (Get-Item $resolvedLogfile).Length / 1MB
                if ($currentSize -ge $maxSizeMB) {
                    $rotLogDir = Split-Path $resolvedLogfile
                    $logBase = [System.IO.Path]::GetFileNameWithoutExtension($resolvedLogfile)
                    $logExt = [System.IO.Path]::GetExtension($resolvedLogfile)
                    $rotNum = 1
                    do {
                        $archiveName = '{0}_r{1:D2}{2}' -f $logBase, $rotNum, $logExt
                        $archivePath = Join-Path $rotLogDir $archiveName
                        $rotNum++
                    } while (Test-Path $archivePath)

                    try {
                        Rename-Item -Path $resolvedLogfile -NewName $archiveName -Force
                    }
                    catch {
                        # Rotation rename failed -- log continues to the oversized file rather
                        # than losing the entry. The next write will re-evaluate size.
                        Write-Warning "Write-Log: Could not rotate log to '$archiveName': $_"
                    }

                    $rotationMsg = "<![LOG[LOG ROTATION: Previous log archived to $archiveName (exceeded ${maxSizeMB}MB)]LOG]!>" +
                        "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                        "context=`"$contextUser`" " +
                        "type=`"1`" thread=`"$PID`" file=`"Write-Log.ps1`">"

                    # Cannot call Write-Log here -- new file may not exist yet.
                    try {
                        [System.IO.File]::WriteAllText($resolvedLogfile, "$rotationMsg$([System.Environment]::NewLine)")
                    }
                    catch {
                        Write-Warning "Write-Log: Failed to write rotation notice to '$resolvedLogfile': $_"
                    }
                }
            }

            # Auto-cleanup runs once per session. Sentinel is set before the call to
            # prevent recursion (Clear-LogFile calls Write-Log internally).
            if ($autoCleanup -and (-not $script:WitnessCleanupRan) -and (Test-Path $resolvedLogfile)) {
                $script:WitnessCleanupRan = $true
                $logFolder = Split-Path $resolvedLogfile
                if ($logFolder -and (Test-Path $logFolder)) {
                    try {
                        Clear-LogFile -LogFolder $logFolder -MaxAgeDays $maxAgeDays
                    }
                    catch {
                        Write-Warning "Auto-cleanup failed: $_"
                    }
                }
            }

            # FileStream with ReadWrite share allows concurrent readers while writing.
            if ($shouldWriteLogfile) {
                $retryCount = 0
                $writeSucceeded = $false

                while (-not $writeSucceeded -and $retryCount -le $MaxRetries) {
                    $fileStream = $null
                    $streamWriter = $null

                    try {
                        $fileMode = [System.IO.FileMode]::Append
                        $fileAccess = [System.IO.FileAccess]::Write
                        $fileShare = [System.IO.FileShare]::ReadWrite

                        $fileStream = New-Object System.IO.FileStream($resolvedLogfile, $fileMode, $fileAccess, $fileShare)
                        $streamWriter = New-Object System.IO.StreamWriter($fileStream)
                        $streamWriter.NewLine = [System.Environment]::NewLine
                        $streamWriter.WriteLine($logline)
                        $writeSucceeded = $true

                        if ($retryCount -gt 0) {
                            $retryNote = "<![LOG[WRITE-LOG FILE CONTENTION: Previous entry required $retryCount retry attempt(s) due to file lock on $resolvedLogfile]LOG]!>" +
                                "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                                "context=`"$contextUser`" " +
                                "type=`"2`" thread=`"$PID`" file=`"Write-Log.ps1`">"
                            $streamWriter.WriteLine($retryNote)
                        }
                    }
                    catch [System.IO.IOException] {
                        $retryCount++
                        if ($retryCount -le $MaxRetries) {
                            Start-Sleep -Milliseconds ([int]($RetryDelay * 1000))
                        }
                        else {
                            Write-Warning "Failed to write to log after $MaxRetries retries (file locked): $resolvedLogfile"
                        }
                    }
                    catch {
                        Write-Warning "Failed to write to log file '$resolvedLogfile': $_"
                        break
                    }
                    finally {
                        if ($null -ne $streamWriter) { $streamWriter.Close() }
                        if ($null -ne $fileStream) { $fileStream.Close() }
                    }
                }
            }
        }
        finally {
            if ($isSCCMDrive) {
                try {
                    Set-Location $originalLocation -ErrorAction SilentlyContinue
                }
                catch {
                    # Location restore after CMSite escape failed -- non-fatal, working
                    # directory may remain at C: for the rest of the pipeline call.
                    Write-Warning "Write-Log: Could not restore CMSite location: $_"
                }
            }
        }
    }
}
