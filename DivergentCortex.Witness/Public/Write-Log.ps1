# Public/Write-Log.ps1
# CMTrace-compatible structured logger.
# API is IDENTICAL to the donor - zero breaking changes for existing consumers.
#
# Fix references:
#   [1/3] Path resolved in order: explicit -Logfile param -> caller-scope $LogFilePath
#         (via $PSCmdlet.SessionState.PSVariable.GetValue) -> $script:WitnessLogFilePath
#         -> $Global:LogFilePath. Restores dot-source-era "just set $LogFilePath" pattern.
#         NOTE: caller-scope resolution works when the caller is in the same session state
#         (direct call, dot-sourced helper). It cannot cross a foreign-module boundary.
#         Under Import-Module, the recommended pattern is Initialize-Log -LogFilePath or
#         $Global:LogFilePath set before the first Write-Log call.
#   [4]   context= resolved per write (not from cache): WindowsIdentity on Windows,
#         [Environment]::UserDomainName\UserName on non-Windows. Matches donor behavior
#         (impersonation-correct on Windows). No heavy adapter per line.
#   [5]   Line endings: StreamWriter.NewLine set to [System.Environment]::NewLine so
#         the rotation notice (direct file write) matches normal lines on each platform.
#   [11]  No PS7-only syntax. All if/else blocks, 5.1-safe throughout.
#   [12]  $script:WitnessCleanupRan guard in module scope; checked and set here.
#   [13]  Global config vars honored for back-compat; module-scope defaults used when absent.

function Write-Log {
    <#
    .SYNOPSIS
        Write to a log file in CMTrace-compatible format with automatic log management.

    .DESCRIPTION
        Outputs strings to a log file formatted for CMTrace.exe and writes to console.
        Cross-platform: Windows PowerShell 5.1 and PowerShell 7.4+ on Windows/Linux/macOS.

        Severity levels (CMTrace type codes):
            1 - Info/Information/Success (default)
            2 - Warning (yellow in CMTrace)
            3 - Error (red in CMTrace)
            4 - Verbose
            5 - Debug

    .PARAMETER Message
        The message to log.

    .PARAMETER Logfile
        Path to the log file. Defaults to the caller-scope $LogFilePath, then the path
        set by Initialize-Log, then $Global:LogFilePath.

    .PARAMETER Severity
        Log level: Info, Information, Warning, Error, Verbose, Debug, Success

    .PARAMETER Component
        Override the auto-detected component name.

    .PARAMETER WriteBackToHost
        Write formatted output to the console. Default: $true.

    .PARAMETER MaxRetries
        Number of retry attempts on file lock. Default: 3.

    .PARAMETER RetryDelay
        Seconds to wait between retries. Default: 0.5.

    .PARAMETER Color
        Optional console color override for the message text.

    .EXAMPLE
        Write-Log -Message "Operation completed" -Severity Info

    .EXAMPLE
        Write-Log -Message "Something might be wrong" -Severity Warning

    .EXAMPLE
        try {
            Get-Process -Name DoesNotExist -ErrorAction Stop
        } catch {
            Write-Log -Message $_.Exception.Message -Severity Error
        }
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Logfile,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [Alias('LogLevel', 'Type', 'level')]
        [String]$Severity = 'Info',

        [Parameter(Mandatory = $false)]
        [String]$Component,

        [Parameter(Mandatory = $false)]
        [switch]$WriteBackToHost = $true,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [double]$RetryDelay = 0.5,

        [Parameter(Mandatory = $false)]
        [System.ConsoleColor]$Color
    )

    # ---- Resolve log file path (Fix [1/3]) ----
    # Layer 1: explicit -Logfile parameter
    # Layer 2: caller's own scope (restores dot-source-era $LogFilePath = '...' pattern)
    # Layers 3+: module-scope and global (delegated to Resolve-WitnessLogPath)
    $callerCandidate = $null
    if ($PSBoundParameters.ContainsKey('Logfile') -and -not [string]::IsNullOrWhiteSpace($Logfile)) {
        $callerCandidate = $Logfile
    } else {
        $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
        if (-not [string]::IsNullOrWhiteSpace($callerScopePath)) {
            $callerCandidate = $callerScopePath
        }
    }
    $Logfile = Resolve-WitnessLogPath -CallerResolved $callerCandidate

    if ([string]::IsNullOrWhiteSpace($Logfile)) {
        throw "FATAL: No log file path set. Call Initialize-Log -LogFilePath first, or set `$LogFilePath in your script scope before calling Write-Log."
    }

    # ---- Config (Fix [13]) ----
    # Module-scope defaults; global overrides honored for back-compat.
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

    # Map "Information" to "Info"
    if ($Severity -eq 'Information') { $Severity = 'Info' }

    # Early return if both outputs disabled for this severity
    if ($Severity -eq 'Verbose' -and (-not $verboseToConsole) -and (-not $verboseToLogfile)) { return }
    if ($Severity -eq 'Debug'   -and (-not $debugToConsole)   -and (-not $debugToLogfile))   { return }

    # ---- SCCM drive detection (Windows only) ----
    $originalLocation = Get-Location
    $isSCCMDrive      = $false
    if ($script:WitnessIsWindows) {
        if ($null -ne $originalLocation.Provider -and $originalLocation.Provider.Name -eq 'CMSite') {
            $isSCCMDrive = $true
            Set-Location C:
        }
    }

    try {
        # ---- Caller detection ----
        $callStack          = Get-PSCallStack
        $Source             = 'Unknown'
        $callerFunctionName = 'Unknown'
        $lineNumber         = '?'

        if ($null -ne $callStack -and $callStack.Count -gt 1) {
            $callerInfo = $callStack[1]
            if ($callerInfo.Location)         { $Source     = $callerInfo.Location }
            if ($callerInfo.ScriptLineNumber)  { $lineNumber = $callerInfo.ScriptLineNumber }
            if ($callerInfo.Command) {
                $callerFunctionName = $callerInfo.Command
                if ($callerFunctionName -like '*.ps1') {
                    $callerFunctionName = [System.IO.Path]::GetFileNameWithoutExtension($callerFunctionName)
                    Write-Verbose "Call from script body: $callerFunctionName"
                } else {
                    Write-Verbose "Call from function: $callerFunctionName"
                }
            }
        }

        # ---- Component resolution ----
        # Also checks caller-scope $Component via SessionState for back-compat (Fix [3]).
        if ([string]::IsNullOrEmpty($Component)) {
            if ($callerFunctionName -ne 'Unknown' -and $callerFunctionName -notlike '*ps1') {
                $Component = $callerFunctionName
            } else {
                $callerComponent = $PSCmdlet.SessionState.PSVariable.GetValue('Component')
                if (-not [string]::IsNullOrEmpty($callerComponent)) {
                    $Component = $callerComponent
                } else {
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

        # ---- Timestamp (local time, no UTC offset - deliberate operator preference) ----
        $DateTime  = Get-Date
        $LogDate   = $DateTime.ToString('MM-dd-yyyy')
        $LogTime   = $DateTime.ToString('HH:mm:ss.fff')

        # ---- Severity -> CMTrace type numeric mapping ----
        $severityType = '1'
        if ($Severity -eq 'Error')       { $severityType = '3' }
        elseif ($Severity -eq 'Warning') { $severityType = '2' }
        elseif ($Severity -eq 'Info')    { $severityType = '1' }
        elseif ($Severity -eq 'Success') { $severityType = '1' }
        elseif ($Severity -eq 'Verbose') { $severityType = '4' }
        elseif ($Severity -eq 'Debug')   { $severityType = '5' }

        # ---- context= field resolved per write (Fix [4]) ----
        # Donor-parity: WindowsIdentity per write on Windows (impersonation-correct).
        # Non-Windows: cheap [Environment] API, no loginctl/who per line.
        if ($script:WitnessIsWindows) {
            $contextUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        } else {
            $contextUser = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
        }

        # ---- Build CMTrace log line ----
        $logline = "<![LOG[$Message]LOG]!>" +
            "<time=`"$LogTime`" " +
            "date=`"$LogDate`" " +
            "component=`"$Component`" " +
            "context=`"$contextUser`" " +
            "type=`"$severityType`" " +
            "thread=`"$PID`" " +
            "file=`"$Source`">"

        # ---- Create log directory if needed ----
        $logDir = Split-Path $Logfile
        if ($logDir -and !(Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        # ---- Console output ----
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

        # ---- Logfile output ----
        $shouldWriteLogfile = $true
        if ($Severity -eq 'Verbose') { $shouldWriteLogfile = $verboseToLogfile }
        elseif ($Severity -eq 'Debug') { $shouldWriteLogfile = $debugToLogfile }

        # ---- Size-based log rotation ----
        # Fix [5]: rotation notice uses [System.Environment]::NewLine (\r\n Windows, \n Linux)
        # so the first line of the new file matches the newline convention of subsequent writes.
        if ($shouldWriteLogfile -and (Test-Path $Logfile)) {
            $currentSize = (Get-Item $Logfile).Length / 1MB
            if ($currentSize -ge $maxSizeMB) {
                $rotLogDir   = Split-Path $Logfile
                $logBase     = [System.IO.Path]::GetFileNameWithoutExtension($Logfile)
                $logExt      = [System.IO.Path]::GetExtension($Logfile)
                $rotNum      = 1
                do {
                    $archiveName = '{0}_r{1:D2}{2}' -f $logBase, $rotNum, $logExt
                    $archivePath = Join-Path $rotLogDir $archiveName
                    $rotNum++
                } while (Test-Path $archivePath)

                try { Rename-Item -Path $Logfile -NewName $archiveName -Force } catch {}

                $rotationMsg = "<![LOG[LOG ROTATION: Previous log archived to $archiveName (exceeded ${maxSizeMB}MB)]LOG]!>" +
                    "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                    "context=`"$contextUser`" " +
                    "type=`"1`" thread=`"$PID`" file=`"Write-Log.ps1`">"

                # Fix [R2]: surface rotation-write failure - an empty catch hides disk-full or perm errors.
                # Cannot use Write-Log here (new file may not exist yet); Write-Warning reaches the stream.
                try {
                    [System.IO.File]::WriteAllText($Logfile, "$rotationMsg$([System.Environment]::NewLine)")
                } catch {
                    Write-Warning "Write-Log: Failed to write rotation notice to '$Logfile': $_"
                }
            }
        }

        # ---- Auto-cleanup once per session (Fix [12]) ----
        if ($autoCleanup -and (-not $script:WitnessCleanupRan) -and (Test-Path $Logfile)) {
            $script:WitnessCleanupRan = $true  # set BEFORE calling to prevent recursion
            $logFolder = Split-Path $Logfile
            if ($logFolder -and (Test-Path $logFolder)) {
                try {
                    Clear-LogFile -LogFolder $logFolder -MaxAgeDays $maxAgeDays
                } catch {
                    Write-Warning "Auto-cleanup failed: $_"
                }
            }
        }

        # ---- Write to logfile with retry on lock ----
        if ($shouldWriteLogfile) {
            $retryCount     = 0
            $writeSucceeded = $false

            while (-not $writeSucceeded -and $retryCount -le $MaxRetries) {
                $fileStream   = $null
                $streamWriter = $null

                try {
                    $fileMode   = [System.IO.FileMode]::Append
                    $fileAccess = [System.IO.FileAccess]::Write
                    $fileShare  = [System.IO.FileShare]::ReadWrite

                    $fileStream             = New-Object System.IO.FileStream($Logfile, $fileMode, $fileAccess, $fileShare)
                    $streamWriter           = New-Object System.IO.StreamWriter($fileStream)
                    $streamWriter.NewLine   = [System.Environment]::NewLine
                    $streamWriter.WriteLine($logline)
                    $writeSucceeded = $true

                    # Contention notice on successful retry
                    if ($retryCount -gt 0) {
                        $retryNote = "<![LOG[WRITE-LOG FILE CONTENTION: Previous entry required $retryCount retry attempt(s) due to file lock on $Logfile]LOG]!>" +
                            "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                            "context=`"$contextUser`" " +
                            "type=`"2`" thread=`"$PID`" file=`"Write-Log.ps1`">"
                        $streamWriter.WriteLine($retryNote)
                    }
                } catch [System.IO.IOException] {
                    $retryCount++
                    if ($retryCount -le $MaxRetries) {
                        Start-Sleep -Milliseconds ([int]($RetryDelay * 1000))
                    } else {
                        Write-Warning "Failed to write to log after $MaxRetries retries (file locked): $Logfile"
                    }
                } catch {
                    Write-Warning "Failed to write to log file: $_"
                    break
                } finally {
                    if ($null -ne $streamWriter) { $streamWriter.Close() }
                    if ($null -ne $fileStream)   { $fileStream.Close() }
                }
            }
        }
    } finally {
        if ($isSCCMDrive) {
            try { Set-Location $originalLocation -ErrorAction SilentlyContinue } catch {}
        }
    }
}
